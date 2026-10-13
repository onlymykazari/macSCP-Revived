//
//  BackupViewModel.swift
//  macSCP
//
//  View model driving the Backup & Restore settings pane
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class BackupViewModel {
    // MARK: - Export State

    var includeCredentials = true
    var includeSettings = true
    var exportPassword = ""
    var exportPasswordConfirmation = ""
    var isExporting = false
    var exportSuccessMessage: String?

    // MARK: - Import State

    enum ImportPhase: Equatable {
        case idle
        case fileChosen(String)          // file name
        case previewed(BackupSummary)
        case restored(RestoreResult)
    }

    var importPassword = ""
    var importPhase: ImportPhase = .idle
    var strategy: RestoreStrategy = .merge
    var isImporting = false
    private var pendingFileURL: URL?

    var error: AppError?

    // MARK: - Dependencies

    private let service: BackupService

    init(service: BackupService) {
        self.service = service
    }

    // MARK: - Validation

    static let minimumPasswordLength = 8

    var canExport: Bool {
        exportPassword.count >= Self.minimumPasswordLength
            && exportPassword == exportPasswordConfirmation
    }

    var canPreview: Bool {
        if case .fileChosen = importPhase { return !importPassword.isEmpty }
        return false
    }

    var canRestore: Bool {
        if case .previewed = importPhase { return true }
        return false
    }

    // MARK: - Export

    func exportBackup() async {
        guard canExport, !isExporting else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let suggestedName = "macSCP-Revived-Backup-\(formatter.string(from: Date())).json"

        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true
        error = nil
        exportSuccessMessage = nil
        do {
            try await service.export(
                to: url,
                password: exportPassword,
                includeCredentials: includeCredentials,
                includeSettings: includeSettings
            )
            exportSuccessMessage = url.lastPathComponent
        } catch {
            self.error = AppError.from(error)
        }
        isExporting = false
    }

    // MARK: - Import

    func chooseBackupFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        importPassword = ""
        importPhase = .fileChosen(url.lastPathComponent)
        pendingFileURL = url
        error = nil
    }

    func previewBackup() async {
        guard canPreview, let url = pendingFileURL else { return }

        do {
            let backup = try service.peek(fileAt: url, password: importPassword)
            importPhase = .previewed(BackupSummary(backup: backup))
        } catch {
            self.error = AppError.from(error)
        }
    }

    func restoreBackup() async {
        guard canRestore, !isImporting, let url = pendingFileURL else { return }

        isImporting = true
        error = nil
        do {
            let backup = try service.peek(fileAt: url, password: importPassword)
            let result = try await service.restore(backup.payload, strategy: strategy)
            importPhase = .restored(result)
        } catch {
            self.error = AppError.from(error)
        }
        isImporting = false
    }

    func resetImport() {
        importPhase = .idle
        importPassword = ""
        pendingFileURL = nil
        error = nil
    }
}

// MARK: - Backup Summary

struct BackupSummary: Equatable {
    let createdAt: Date
    let connectionCount: Int
    let folderCount: Int
    let credentialCount: Int
    let includesSettings: Bool

    init(backup: DecryptedBackup) {
        createdAt = backup.createdAt
        connectionCount = backup.payload.connections.count
        folderCount = backup.payload.folders.count
        credentialCount = backup.payload.credentials.count
        includesSettings = backup.payload.settings != nil
    }
}
