//
//  BackupService.swift
//  macSCP
//
//  Builds, encrypts, and restores backups of connections, folders,
//  keychain credentials, and app-lock preferences
//

import Foundation

@MainActor
final class BackupService {
    private let connectionRepository: ConnectionRepositoryProtocol
    private let folderRepository: FolderRepositoryProtocol
    private let keychainService: KeychainServiceProtocol
    private let settingsStore: BackupSettingsStore

    init(
        connectionRepository: ConnectionRepositoryProtocol,
        folderRepository: FolderRepositoryProtocol,
        keychainService: KeychainServiceProtocol,
        settingsStore: BackupSettingsStore
    ) {
        self.connectionRepository = connectionRepository
        self.folderRepository = folderRepository
        self.keychainService = keychainService
        self.settingsStore = settingsStore
    }

    // MARK: - Export

    func buildPayload(includeCredentials: Bool, includeSettings: Bool) async throws -> BackupPayload {
        let connections = try await connectionRepository.fetchAll()
        let folders = try await folderRepository.fetchAll()

        var credentials: [BackupCredential] = []
        if includeCredentials {
            for connection in connections {
                var entry = BackupCredential(connectionId: connection.id)
                if connection.isSFTPConnection, connection.savePassword,
                   let password = keychainService.getPassword(for: connection.id) {
                    entry.password = password
                }
                if connection.isS3Connection,
                   let s3 = keychainService.getS3Credentials(for: connection.id) {
                    entry.s3Credentials = s3
                }
                if entry.password != nil || entry.s3Credentials != nil {
                    credentials.append(entry)
                }
            }
        }

        return BackupPayload(
            connections: connections,
            folders: folders,
            credentials: credentials,
            settings: includeSettings ? settingsStore.read() : nil
        )
    }

    /// Writes an encrypted backup file to `url`
    func export(to url: URL, password: String, includeCredentials: Bool, includeSettings: Bool) async throws {
        let payload = try await buildPayload(
            includeCredentials: includeCredentials,
            includeSettings: includeSettings
        )
        let data = try BackupCrypto.encode(payload: payload, password: password)
        try data.write(to: url, options: .atomic)
        logInfo("Backup exported to \(url.lastPathComponent)", category: .app)
    }

    // MARK: - Inspect

    /// Decrypts and validates a backup file without touching any data
    func peek(fileAt url: URL, password: String) throws -> DecryptedBackup {
        let fileContents = try Data(contentsOf: url)
        let backup = try BackupCrypto.decodeBackup(fileContents: fileContents, password: password)
        return backup
    }

    // MARK: - Restore

    func restore(_ payload: BackupPayload, strategy: RestoreStrategy) async throws -> RestoreResult {
        var result = RestoreResult()
        var credentialEligibleIds: Set<UUID>?

        switch strategy {
        case .replace:
            try await wipeExistingData()
            try await insertAll(payload, result: &result)

        case .merge:
            let folderIdMap = try await mergeFolders(payload.folders, result: &result)
            credentialEligibleIds = try await mergeConnections(
                payload.connections,
                folderIdMap: folderIdMap,
                result: &result
            )
        }

        try applyCredentials(payload.credentials, eligibleIds: credentialEligibleIds)

        if let settings = payload.settings {
            settingsStore.apply(settings)
        }

        logInfo(
            "Backup restored (\(strategy.rawValue)): +\(result.connectionsAdded) connections, "
                + "~\(result.connectionsUpdated) updated, =\(result.connectionsSkipped) skipped",
            category: .app
        )
        return result
    }

    // MARK: - Restore Helpers

    private func wipeExistingData() async throws {
        for connection in try await connectionRepository.fetchAll() {
            try? keychainService.deletePassword(for: connection.id)
            try? keychainService.deleteS3Credentials(for: connection.id)
            try await connectionRepository.delete(id: connection.id)
        }
        for folder in try await folderRepository.fetchAll() {
            try await folderRepository.delete(id: folder.id)
        }
    }

    private func insertAll(_ payload: BackupPayload, result: inout RestoreResult) async throws {
        for folder in payload.folders {
            try await folderRepository.save(folder)
            result.foldersAdded += 1
        }
        for connection in payload.connections {
            try await connectionRepository.save(connection)
            result.connectionsAdded += 1
        }
    }

    /// Merges folders by id; folders with a name that already exists locally
    /// are deduplicated by mapping the imported id to the existing local id.
    /// Returns a map from imported folder id to the local folder id to use.
    private func mergeFolders(_ folders: [Folder], result: inout RestoreResult) async throws -> [UUID: UUID] {
        let existing = try await folderRepository.fetchAll()
        var existingById: [UUID: Folder] = [:]
        var existingByName: [String: Folder] = [:]
        for folder in existing {
            existingById[folder.id] = folder
            existingByName[folder.name] = folder
        }

        var folderIdMap: [UUID: UUID] = [:]

        for imported in folders {
            if let local = existingById[imported.id] {
                folderIdMap[imported.id] = imported.id
                if imported.updatedAt > local.updatedAt {
                    try await folderRepository.update(imported)
                    result.foldersUpdated += 1
                }
            } else if let sameName = existingByName[imported.name] {
                folderIdMap[imported.id] = sameName.id
            } else {
                try await folderRepository.save(imported)
                folderIdMap[imported.id] = imported.id
                existingById[imported.id] = imported
                existingByName[imported.name] = imported
                result.foldersAdded += 1
            }
        }

        return folderIdMap
    }

    private func mergeConnections(
        _ connections: [Connection],
        folderIdMap: [UUID: UUID],
        result: inout RestoreResult
    ) async throws -> Set<UUID> {
        let existing = try await connectionRepository.fetchAll()
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        var changedIds = Set<UUID>()

        for var imported in connections {
            if let mappedFolderId = imported.folderId {
                imported.folderId = folderIdMap[mappedFolderId]
            }

            if let local = existingById[imported.id] {
                if imported.updatedAt > local.updatedAt {
                    try await connectionRepository.update(imported)
                    result.connectionsUpdated += 1
                    changedIds.insert(imported.id)
                } else {
                    result.connectionsSkipped += 1
                }
            } else {
                try await connectionRepository.save(imported)
                result.connectionsAdded += 1
                changedIds.insert(imported.id)
            }
        }

        return changedIds
    }

    /// Writes keychain entries back. On merge, credentials are only applied to
    /// connections that were added or updated (skipped connections keep their
    /// local credentials).
    private func applyCredentials(_ credentials: [BackupCredential], eligibleIds: Set<UUID>?) throws {
        for entry in credentials {
            if let eligibleIds, !eligibleIds.contains(entry.connectionId) {
                continue
            }
            if let password = entry.password {
                try keychainService.savePassword(password, for: entry.connectionId)
            }
            if let s3 = entry.s3Credentials {
                try keychainService.saveS3Credentials(s3, for: entry.connectionId)
            }
        }
    }
}
