//
//  BackupServiceTests.swift
//  macSCPTests
//
//  Unit tests for backup export/restore logic
//

import XCTest
@testable import macSCP

@MainActor
final class MockBackupSettingsStore: BackupSettingsStore {
    var toRead: BackupSettings = BackupSettings(
        isBiometricLockEnabled: false,
        lockOnAppResume: false,
        lockBeforeConnection: false,
        lockAfterInactivity: false,
        inactivityTimeout: 300
    )
    private(set) var applied: BackupSettings?

    func read() -> BackupSettings { toRead }

    func apply(_ settings: BackupSettings) {
        applied = settings
    }
}

@MainActor
final class BackupServiceTests: XCTestCase {
    var sut: BackupService!
    var mockConnections: MockConnectionRepository!
    var mockFolders: MockFolderRepository!
    var mockKeychain: MockKeychainService!
    var mockSettings: MockBackupSettingsStore!

    override func setUp() async throws {
        try await super.setUp()
        mockConnections = MockConnectionRepository()
        mockFolders = MockFolderRepository()
        mockKeychain = MockKeychainService()
        mockSettings = MockBackupSettingsStore()

        sut = BackupService(
            connectionRepository: mockConnections,
            folderRepository: mockFolders,
            keychainService: mockKeychain,
            settingsStore: mockSettings
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockConnections = nil
        mockFolders = nil
        mockKeychain = nil
        mockSettings = nil
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private func makeConnection(
        id: UUID = UUID(),
        name: String = "prod",
        type: ConnectionType = .sftp,
        savePassword: Bool = false,
        updatedAt: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> Connection {
        var connection = Connection(
            id: id,
            name: name,
            host: "example.com",
            username: "deploy",
            authMethod: .password,
            savePassword: savePassword,
            connectionType: type == .s3 ? .s3 : .sftp,
            s3Region: type == .s3 ? "us-east-1" : nil,
            s3Bucket: type == .s3 ? "bucket" : nil
        )
        connection.updatedAt = updatedAt
        return connection
    }

    // MARK: - Export

    func testBuildPayload_IncludesEverything() async throws {
        let sftpId = UUID()
        let s3Id = UUID()
        let connection = makeConnection(id: sftpId, savePassword: true)
        let s3Connection = makeConnection(id: s3Id, name: "assets", type: .s3)

        mockConnections.mockConnections = [connection, s3Connection]
        mockFolders.mockFolders = [Folder(name: "Servers")]
        mockKeychain.mockPasswords[sftpId] = "hunter2"
        mockKeychain.mockS3Credentials[s3Id] = S3Credentials(accessKeyId: "AKIA", secretAccessKey: "secret")

        let payload = try await sut.buildPayload(includeCredentials: true, includeSettings: true)

        XCTAssertEqual(payload.connections.count, 2)
        XCTAssertEqual(payload.folders.count, 1)
        XCTAssertEqual(payload.credentials.count, 2)
        XCTAssertEqual(payload.credentials.first(where: { $0.connectionId == sftpId })?.password, "hunter2")
        XCTAssertEqual(payload.credentials.first(where: { $0.connectionId == s3Id })?.s3Credentials?.accessKeyId, "AKIA")
        XCTAssertEqual(payload.settings, mockSettings.toRead)
    }

    func testBuildPayload_WithoutCredentialsAndSettings() async throws {
        let id = UUID()
        mockConnections.mockConnections = [makeConnection(id: id, savePassword: true)]
        mockKeychain.mockPasswords[id] = "hunter2"

        let payload = try await sut.buildPayload(includeCredentials: false, includeSettings: false)

        XCTAssertTrue(payload.credentials.isEmpty)
        XCTAssertNil(payload.settings)
    }

    func testExportToURL_PeekRoundTrip() async throws {
        mockConnections.mockConnections = [makeConnection(savePassword: true)]
        mockFolders.mockFolders = [Folder(name: "Servers")]

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("macscp-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try await sut.export(to: url, password: "correct horse", includeCredentials: false, includeSettings: false)

        let backup = try sut.peek(fileAt: url, password: "correct horse")
        XCTAssertEqual(backup.payload.connections.count, 1)
        XCTAssertEqual(backup.payload.folders.count, 1)
    }

    // MARK: - Restore (merge)

    func testRestoreMerge_AddsNewItemsAndCredentials() async throws {
        let id = UUID()
        let connection = makeConnection(id: id, savePassword: true)
        let folder = Folder(name: "Servers")
        let payload = BackupPayload(
            connections: [connection],
            folders: [folder],
            credentials: [BackupCredential(connectionId: id, password: "hunter2", s3Credentials: nil)],
            settings: nil
        )

        let result = try await sut.restore(payload, strategy: .merge)

        XCTAssertEqual(result.connectionsAdded, 1)
        XCTAssertEqual(result.foldersAdded, 1)
        XCTAssertEqual(mockConnections.mockConnections.first?.id, id)
        XCTAssertEqual(mockKeychain.mockPasswords[id], "hunter2")
    }

    func testRestoreMerge_NewerBackupWins_OlderBackupSkipped() async throws {
        let id = UUID()
        let local = makeConnection(id: id, updatedAt: Date(timeIntervalSince1970: 2_000_000))
        let newerBackup = makeConnection(id: id, name: "prod-renamed", updatedAt: Date(timeIntervalSince1970: 3_000_000))
        let olderBackup = makeConnection(id: id, name: "prod-old", updatedAt: Date(timeIntervalSince1970: 1_000_000))

        // Newer backup replaces local
        mockConnections.mockConnections = [local]
        mockKeychain.mockPasswords[id] = "old-password"

        var result = try await sut.restore(
            BackupPayload(connections: [newerBackup], folders: [], credentials: [
                BackupCredential(connectionId: id, password: "new-password", s3Credentials: nil)
            ], settings: nil),
            strategy: .merge
        )

        XCTAssertEqual(result.connectionsUpdated, 1)
        XCTAssertEqual(mockConnections.mockConnections.first?.name, "prod-renamed")
        XCTAssertEqual(mockKeychain.mockPasswords[id], "new-password")

        // Older backup is skipped and does not touch local credentials
        result = try await sut.restore(
            BackupPayload(connections: [olderBackup], folders: [], credentials: [
                BackupCredential(connectionId: id, password: "even-older", s3Credentials: nil)
            ], settings: nil),
            strategy: .merge
        )

        XCTAssertEqual(result.connectionsSkipped, 1)
        XCTAssertEqual(mockConnections.mockConnections.first?.name, "prod-renamed")
        XCTAssertEqual(mockKeychain.mockPasswords[id], "new-password")
    }

    func testRestoreMerge_FolderDedupeByNameRemapsConnections() async throws {
        let localFolder = Folder(name: "Prod")
        mockFolders.mockFolders = [localFolder]

        let importedFolderId = UUID()
        let importedFolder = Folder(id: importedFolderId, name: "Prod")
        let connection = makeConnection()
        var connectionWithFolder = connection
        connectionWithFolder.folderId = importedFolderId

        let result = try await sut.restore(
            BackupPayload(connections: [connectionWithFolder], folders: [importedFolder], credentials: [], settings: nil),
            strategy: .merge
        )

        // No duplicate folder created; connection remapped to the local folder id
        XCTAssertEqual(mockFolders.mockFolders.count, 1)
        XCTAssertEqual(result.foldersAdded, 0)
        XCTAssertEqual(mockConnections.mockConnections.first?.folderId, localFolder.id)
    }

    // MARK: - Restore (replace)

    func testRestoreReplace_WipesExistingDataAndKeychain() async throws {
        let oldId = UUID()
        mockConnections.mockConnections = [makeConnection(id: oldId, savePassword: true)]
        mockFolders.mockFolders = [Folder(name: "Old")]
        mockKeychain.mockPasswords[oldId] = "old-password"

        let newId = UUID()
        let result = try await sut.restore(
            BackupPayload(
                connections: [makeConnection(id: newId, name: "fresh")],
                folders: [Folder(name: "New")],
                credentials: [BackupCredential(connectionId: newId, password: "fresh-password", s3Credentials: nil)],
                settings: nil
            ),
            strategy: .replace
        )

        XCTAssertEqual(result.connectionsAdded, 1)
        XCTAssertEqual(mockConnections.mockConnections.map(\.id), [newId])
        XCTAssertEqual(mockFolders.mockFolders.map(\.name), ["New"])
        XCTAssertNil(mockKeychain.mockPasswords[oldId], "old keychain entry should be deleted")
        XCTAssertEqual(mockKeychain.mockPasswords[newId], "fresh-password")
    }

    // MARK: - Settings

    func testRestore_AppliesSettingsWhenPresent() async throws {
        let settings = BackupSettings(
            isBiometricLockEnabled: true,
            lockOnAppResume: true,
            lockBeforeConnection: false,
            lockAfterInactivity: true,
            inactivityTimeout: 900
        )

        _ = try await sut.restore(
            BackupPayload(connections: [], folders: [], credentials: [], settings: settings),
            strategy: .merge
        )

        XCTAssertEqual(mockSettings.applied, settings)
    }
}
