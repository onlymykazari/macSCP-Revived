//
//  AnalyticsService.swift
//  macSCP
//
//  macSCP-Revived collects no telemetry. All tracking APIs are retained as
//  no-ops so existing call sites compile unchanged.
//

import Foundation

enum AnalyticsService {
    // MARK: - Configuration

    static func initialize() {
        // No telemetry — intentionally empty
    }

    // MARK: - Core Tracking (no-op)

    static func track(_ event: Event) {}

    static func track(_ event: Event, with parameters: [String: String]) {}

    // MARK: - Connection Tracking (no-op)

    static func trackConnectionCreated(protocol: ConnectionProtocol) {}

    static func trackConnectionConnected(protocol: ConnectionProtocol, success: Bool) {}

    static func trackConnectionFailed(protocol: ConnectionProtocol, errorType: String) {}

    // MARK: - File Transfer Tracking (no-op)

    static func trackFileUploaded(protocol: ConnectionProtocol, fileCount: Int, totalBytes: Int64) {}

    static func trackFileDownloaded(protocol: ConnectionProtocol, fileCount: Int, totalBytes: Int64) {}

    static func trackTransferFailed(protocol: ConnectionProtocol, operation: String, errorType: String) {}

    // MARK: - File Operations Tracking (no-op)

    static func trackFileOperation(_ operation: FileOperation, protocol: ConnectionProtocol, count: Int = 1) {}

    // MARK: - Feature Usage Tracking (no-op)

    static func trackFileBrowserOpened(protocol: ConnectionProtocol) {}

    static func trackEditorOpened(fileExtension: String) {}

    static func trackFileSaved(fileExtension: String) {}

    // MARK: - Biometric Tracking (no-op)

    static func trackBiometricToggled(enabled: Bool) {}

    static func trackBiometricResult(success: Bool) {}

    // MARK: - Events

    enum Event: String {
        // App lifecycle
        case appLaunched = "app_launched"

        // Connections
        case connectionCreated = "connection_created"
        case connectionEdited = "connection_edited"
        case connectionDeleted = "connection_deleted"
        case connectionConnected = "connection_connected"
        case connectionFailed = "connection_failed"

        // Folders (local organization)
        case folderCreated = "folder_created"
        case folderDeleted = "folder_deleted"

        // File browser
        case fileBrowserOpened = "file_browser_opened"
        case fileUploaded = "file_uploaded"
        case fileDownloaded = "file_downloaded"
        case fileDeleted = "file_deleted"
        case fileRenamed = "file_renamed"
        case folderCreatedRemote = "folder_created_remote"
        case transferFailed = "transfer_failed"

        // Editor
        case editorOpened = "editor_opened"
        case fileSaved = "file_saved"

        // File info
        case fileInfoOpened = "file_info_opened"

        // Biometric
        case biometricEnabled = "biometric_enabled"
        case biometricDisabled = "biometric_disabled"
        case biometricSuccess = "biometric_success"
        case biometricFailed = "biometric_failed"
    }

    enum ConnectionProtocol: String {
        case sftp = "sftp"
        case s3 = "s3"

        init(from connectionType: ConnectionType) {
            switch connectionType {
            case .sftp: self = .sftp
            case .s3: self = .s3
            }
        }
    }

    enum FileOperation {
        case delete
        case rename
        case createFolder
    }
}
