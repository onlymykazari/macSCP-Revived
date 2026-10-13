//
//  BackupModels.swift
//  macSCP
//
//  Data model for encrypted backup files (connections, folders,
//  keychain credentials, app-lock preferences)
//

import Foundation

// MARK: - Format Constants

enum BackupFormat {
    static let identifier = "macscp-revived-backup"
    static let version = 1
}

// MARK: - Payload (plaintext content of a backup)

struct BackupPayload: Codable {
    var connections: [Connection]
    var folders: [Folder]
    var credentials: [BackupCredential]
    var settings: BackupSettings?
}

/// Keychain credentials for a single connection
struct BackupCredential: Codable {
    let connectionId: UUID
    var password: String?
    var s3Credentials: S3Credentials?
}

/// App-lock preferences. The master Touch ID toggle is captured for reference
/// but never auto-applied on restore (enabling/disabling it requires local
/// authentication).
struct BackupSettings: Codable, Equatable {
    var isBiometricLockEnabled: Bool
    var lockOnAppResume: Bool
    var lockBeforeConnection: Bool
    var lockAfterInactivity: Bool
    var inactivityTimeout: Int
}

// MARK: - File Envelope (what actually gets written to disk)

/// JSON envelope wrapping the AES-256-GCM encrypted payload. Format and KDF
/// parameters are stored in the clear so future versions can evolve them.
struct BackupFileEnvelope: Codable {
    let format: String
    let version: Int
    let createdAt: Date
    let kdf: BackupKDFParams
    let encryption: String
    let nonce: String
    let data: String
}

struct BackupKDFParams: Codable {
    let algorithm: String
    let iterations: Int
    let salt: String
}

// MARK: - Restore

enum RestoreStrategy: String, CaseIterable, Identifiable {
    case merge
    case replace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .merge: return "Merge"
        case .replace: return "Replace All"
        }
    }
}

struct RestoreResult: Equatable {
    var connectionsAdded = 0
    var connectionsUpdated = 0
    var connectionsSkipped = 0
    var foldersAdded = 0
    var foldersUpdated = 0
}

// MARK: - Settings Store

/// Abstraction over AppLockManager so restore logic stays testable.
@MainActor
protocol BackupSettingsStore {
    func read() -> BackupSettings
    func apply(_ settings: BackupSettings)
}

@MainActor
final class AppLockSettingsStore: BackupSettingsStore {
    private let appLock: AppLockManager

    init(appLock: AppLockManager = .shared) {
        self.appLock = appLock
    }

    func read() -> BackupSettings {
        BackupSettings(
            isBiometricLockEnabled: appLock.isBiometricLockEnabled,
            lockOnAppResume: appLock.lockOnAppResume,
            lockBeforeConnection: appLock.lockBeforeConnection,
            lockAfterInactivity: appLock.lockAfterInactivity,
            inactivityTimeout: appLock.inactivityTimeout.rawValue
        )
    }

    func apply(_ settings: BackupSettings) {
        // The master Touch ID toggle requires local authentication to change,
        // so it is deliberately not restored; only the auxiliary preferences.
        appLock.lockOnAppResume = settings.lockOnAppResume
        appLock.lockBeforeConnection = settings.lockBeforeConnection
        appLock.lockAfterInactivity = settings.lockAfterInactivity
        if let timeout = InactivityTimeout(rawValue: settings.inactivityTimeout) {
            appLock.inactivityTimeout = timeout
        }
    }
}
