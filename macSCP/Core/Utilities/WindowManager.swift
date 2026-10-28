//
//  WindowManager.swift
//  macSCP
//
//  Manages window data passing for multi-window support
//

import Foundation
import SwiftUI
import Combine

// MARK: - Window Data Types
struct FileBrowserWindowData: Sendable {
    let connectionId: UUID
    let connectionName: String
    let host: String
    let port: Int
    let username: String
    let password: String
    let authMethod: AuthMethod
    let privateKeyPath: String?
    let connectionType: ConnectionType
    let s3Region: String?
    let s3Bucket: String?
    let s3Endpoint: String?
    let s3SecretAccessKey: String?
    let defaultRemotePath: String?

    init(
        connectionId: UUID,
        connectionName: String,
        host: String,
        port: Int,
        username: String,
        password: String,
        authMethod: AuthMethod,
        privateKeyPath: String?,
        connectionType: ConnectionType = .sftp,
        s3Region: String? = nil,
        s3Bucket: String? = nil,
        s3Endpoint: String? = nil,
        s3SecretAccessKey: String? = nil,
        defaultRemotePath: String? = nil
    ) {
        self.connectionId = connectionId
        self.connectionName = connectionName
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.authMethod = authMethod
        self.privateKeyPath = privateKeyPath
        self.connectionType = connectionType
        self.s3Region = s3Region
        self.s3Bucket = s3Bucket
        self.s3Endpoint = s3Endpoint
        self.s3SecretAccessKey = s3SecretAccessKey
        self.defaultRemotePath = defaultRemotePath
    }
}

struct FileEditorWindowData: Sendable {
    let filePath: String
    let fileName: String
    let content: String
    let connectionId: UUID
    // Connection details for saving
    let host: String
    let port: Int
    let username: String
    let password: String
    let authMethod: AuthMethod
    let privateKeyPath: String?
    // S3-specific fields
    let connectionType: ConnectionType
    let s3Region: String?
    let s3Bucket: String?
    let s3Endpoint: String?

    init(
        filePath: String,
        fileName: String,
        content: String,
        connectionId: UUID,
        host: String,
        port: Int,
        username: String,
        password: String,
        authMethod: AuthMethod,
        privateKeyPath: String?,
        connectionType: ConnectionType = .sftp,
        s3Region: String? = nil,
        s3Bucket: String? = nil,
        s3Endpoint: String? = nil
    ) {
        self.filePath = filePath
        self.fileName = fileName
        self.content = content
        self.connectionId = connectionId
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.authMethod = authMethod
        self.privateKeyPath = privateKeyPath
        self.connectionType = connectionType
        self.s3Region = s3Region
        self.s3Bucket = s3Bucket
        self.s3Endpoint = s3Endpoint
    }
}

struct FileInfoWindowData: Sendable {
    let file: RemoteFile
    let connectionName: String
}

struct TerminalWindowData: Sendable {
    let connectionId: UUID
    let connectionName: String
    let host: String
    let port: Int
    let username: String
    let password: String
    let authMethod: AuthMethod
    let privateKeyPath: String?
    /// Remote directory to cd into once the PTY is up (nil = server default).
    let initialPath: String?

    init(
        connectionId: UUID,
        connectionName: String,
        host: String,
        port: Int,
        username: String,
        password: String,
        authMethod: AuthMethod,
        privateKeyPath: String?,
        initialPath: String? = nil
    ) {
        self.connectionId = connectionId
        self.connectionName = connectionName
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.authMethod = authMethod
        self.privateKeyPath = privateKeyPath
        self.initialPath = initialPath
    }
}

// MARK: - Window Manager
@MainActor
final class WindowManager: ObservableObject {
    static let shared = WindowManager()

    private var fileBrowserData: [String: FileBrowserWindowData] = [:]
    private var fileEditorData: [String: FileEditorWindowData] = [:]
    private var fileInfoData: [String: FileInfoWindowData] = [:]
    private var terminalData: [String: TerminalWindowData] = [:]

    private init() {}

    // MARK: - File Browser Window
    /// Stores browser window data. Passing an explicit `id` makes the call
    /// idempotent under that key; re-opening a window with the same value then
    /// reuses (activates) the existing window instead of stacking duplicates.
    func storeFileBrowserData(_ data: FileBrowserWindowData, id: String? = nil) -> String {
        let key = id ?? UUID().uuidString
        fileBrowserData[key] = data
        return key
    }

    func getFileBrowserData(for id: String) -> FileBrowserWindowData? {
        fileBrowserData[id]
    }

    func removeFileBrowserData(for id: String) {
        fileBrowserData.removeValue(forKey: id)
    }

    // MARK: - File Editor Window
    func storeFileEditorData(_ data: FileEditorWindowData) -> String {
        let id = UUID().uuidString
        fileEditorData[id] = data
        return id
    }

    func getFileEditorData(for id: String) -> FileEditorWindowData? {
        fileEditorData[id]
    }

    func removeFileEditorData(for id: String) {
        fileEditorData.removeValue(forKey: id)
    }

    // MARK: - File Info Window
    func storeFileInfoData(_ data: FileInfoWindowData) -> String {
        let id = UUID().uuidString
        fileInfoData[id] = data
        return id
    }

    func getFileInfoData(for id: String) -> FileInfoWindowData? {
        fileInfoData[id]
    }

    func removeFileInfoData(for id: String) {
        fileInfoData.removeValue(forKey: id)
    }

    // MARK: - Terminal Window
    /// See `storeFileBrowserData(_:id:)` for the explicit-id semantics.
    func storeTerminalData(_ data: TerminalWindowData, id: String? = nil) -> String {
        let key = id ?? UUID().uuidString
        terminalData[key] = data
        return key
    }

    func getTerminalData(for id: String) -> TerminalWindowData? {
        terminalData[id]
    }

    func removeTerminalData(for id: String) {
        terminalData.removeValue(forKey: id)
    }

    // MARK: - Cleanup
    func clearAllData() {
        fileBrowserData.removeAll()
        fileEditorData.removeAll()
        fileInfoData.removeAll()
        terminalData.removeAll()
    }
}
