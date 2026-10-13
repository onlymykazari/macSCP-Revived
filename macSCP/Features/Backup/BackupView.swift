//
//  BackupView.swift
//  macSCP
//
//  Backup & Restore settings pane
//

import SwiftUI

struct BackupView: View {
    @Bindable var viewModel: BackupViewModel

    var body: some View {
        Form {
            exportSection
            restoreSection
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
        .errorAlert($viewModel.error)
    }

    // MARK: - Export

    @ViewBuilder
    private var exportSection: some View {
        Section {
            Toggle("Include saved passwords and S3 keys", isOn: $viewModel.includeCredentials)
            Toggle("Include app-lock preferences", isOn: $viewModel.includeSettings)

            SecureField("Backup password", text: $viewModel.exportPassword)
            SecureField("Confirm password", text: $viewModel.exportPasswordConfirmation)

            HStack {
                Button {
                    Task { await viewModel.exportBackup() }
                } label: {
                    if viewModel.isExporting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Exporting…")
                        }
                    } else {
                        Text("Export Backup…")
                    }
                }
                .disabled(!viewModel.canExport || viewModel.isExporting)

                if let name = viewModel.exportSuccessMessage {
                    Label(name, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                        .help(name)
                }
            }
        } header: {
            Text("Export")
        } footer: {
            Text("Creates an encrypted backup of all connections and folders (password must be at least \(BackupViewModel.minimumPasswordLength) characters). SSH private key files on disk are not included.")
        }
    }

    // MARK: - Restore

    @ViewBuilder
    private var restoreSection: some View {
        Section {
            switch viewModel.importPhase {
            case .idle:
                Button("Choose Backup File…") {
                    viewModel.chooseBackupFile()
                }

            case .fileChosen(let fileName):
                chooseAnotherButton

                Label(fileName, systemImage: "doc.badge.lock")
                    .font(.callout)

                SecureField("Backup password", text: $viewModel.importPassword)

                Button("Unlock Preview") {
                    Task { await viewModel.previewBackup() }
                }
                .disabled(!viewModel.canPreview)

            case .previewed(let summary):
                chooseAnotherButton

                summaryRows(summary)

                Picker("Strategy", selection: $viewModel.strategy) {
                    ForEach(RestoreStrategy.allCases) { strategy in
                        Text(strategy.label).tag(strategy)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.strategy == .replace {
                    Label(
                        "Replace All deletes every existing connection, folder, and saved password before importing.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                Button {
                    Task { await viewModel.restoreBackup() }
                } label: {
                    if viewModel.isImporting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Restoring…")
                        }
                    } else {
                        Text("Restore Backup")
                    }
                }
                .disabled(!viewModel.canRestore || viewModel.isImporting)
                .tint(viewModel.strategy == .replace ? .red : .accentColor)

            case .restored(let result):
                chooseAnotherButton

                Label(result.summaryText, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                if viewModel.strategy == .replace {
                    Text("Connections list in already-open windows updates on next launch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Restore")
        } footer: {
            Text("Merge keeps newer local versions of items that already exist. The Touch ID master switch is never changed by a restore.")
        }
    }

    private var chooseAnotherButton: some View {
        Button("Choose Another File…") {
            viewModel.resetImport()
        }
    }

    @ViewBuilder
    private func summaryRows(_ summary: BackupSummary) -> some View {
        LabeledContent("Created") {
            Text(summary.createdAt, style: .date)
        }
        LabeledContent("Contents") {
            Text(
                "\(summary.connectionCount) connections, \(summary.folderCount) folders"
                    + (summary.credentialCount > 0 ? ", \(summary.credentialCount) with saved passwords" : "")
            )
        }
        LabeledContent("App Settings") {
            Text(summary.includesSettings ? "Included" : "Not included")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - RestoreResult Formatting

extension RestoreResult {
    var summaryText: String {
        var parts: [String] = []
        if connectionsAdded > 0 { parts.append("\(connectionsAdded) added") }
        if connectionsUpdated > 0 { parts.append("\(connectionsUpdated) updated") }
        if connectionsSkipped > 0 { parts.append("\(connectionsSkipped) kept local version") }
        if foldersAdded > 0 { parts.append("\(foldersAdded) folders added") }
        if foldersUpdated > 0 { parts.append("\(foldersUpdated) folders updated") }
        return parts.isEmpty ? "Nothing to import" : parts.joined(separator: " · ")
    }
}

#Preview("Backup") {
    BackupView(
        viewModel: BackupViewModel(
            service: BackupService(
                connectionRepository: DependencyContainer.shared.connectionRepository,
                folderRepository: DependencyContainer.shared.folderRepository,
                keychainService: DependencyContainer.shared.keychainService,
                settingsStore: AppLockSettingsStore()
            )
        )
    )
}
