//
//  SettingsView.swift
//  macSCP
//
//  Application settings view (Cmd+, shortcut via Settings scene)
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @State private var appLockManager = AppLockManager.shared
    @State private var pane: SettingsPane = .security
    @AppStorage(FileLogStore.verboseLoggingDefaultsKey) private var verboseLoggingEnabled = false
    @State private var exportError: String?
    private let biometricService: BiometricAuthServiceProtocol = BiometricAuthService.shared

    private enum SettingsPane: String, CaseIterable, Identifiable {
        case security
        case urlScheme
        case backup
        case diagnostics

        var id: String { rawValue }

        var label: String {
            switch self {
            case .security: return "Security"
            case .urlScheme: return "URL Scheme"
            case .backup: return "Backup & Restore"
            case .diagnostics: return "Diagnostics"
            }
        }
    }

    private var isBiometricAvailable: Bool {
        biometricService.isBiometricAvailable()
    }

    private var isEnabled: Bool {
        appLockManager.isBiometricLockEnabled
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Settings Pane", selection: $pane) {
                ForEach(SettingsPane.allCases) { pane in
                    Text(pane.label).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 12)

            switch pane {
            case .security:
                Form {
                    securitySection
                }
                .formStyle(.grouped)
                .frame(width: 450)
                .fixedSize(horizontal: false, vertical: true)

            case .urlScheme:
                URLSchemeSettingsPane()

            case .backup:
                BackupView(viewModel: DependencyContainer.shared.makeBackupViewModel())

            case .diagnostics:
                Form {
                    diagnosticsSection
                }
                .formStyle(.grouped)
                .frame(width: 470)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .alert("Export Failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    // MARK: - Security Section

    @ViewBuilder
    private var securitySection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { appLockManager.isBiometricLockEnabled },
                set: { newValue in
                    if newValue {
                        appLockManager.enableBiometricLock()
                    } else {
                        Task {
                            await appLockManager.disableBiometricLock()
                        }
                    }
                }
            )) {
                Label("Require Touch ID", systemImage: "touchid")
            }
            .disabled(!isBiometricAvailable)

            if !isBiometricAvailable {
                Text("Touch ID is not available on this Mac. Use a Mac with Touch ID or an Apple Watch to enable this feature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isEnabled {
                Toggle(isOn: Bindable(appLockManager).lockOnAppResume) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lock when switching apps")
                        Text("Require authentication when returning to macSCP")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: Bindable(appLockManager).lockBeforeConnection) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Require before each connection")
                        Text("Authenticate before connecting to any server")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Toggle(isOn: Bindable(appLockManager).lockAfterInactivity) {
                        Text("Lock after inactivity")
                    }

                    Spacer()

                    Picker("", selection: Bindable(appLockManager).inactivityTimeout) {
                        ForEach(InactivityTimeout.allCases) { timeout in
                            Text(timeout.label).tag(timeout)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!appLockManager.lockAfterInactivity)
                }
            }
        } header: {
            Text("Security")
        } footer: {
            if isEnabled {
                Text("The app always requires authentication on launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Diagnostics Section

    @ViewBuilder
    private var diagnosticsSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text("\(versionString) (build \(buildString))")
                    .foregroundStyle(.secondary)
                    .monospaced()
            }

            HStack {
                Text("Build")
                Spacer()
                Text(buildConfiguration)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("About")
        }

        Section {
            Toggle(isOn: $verboseLoggingEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Verbose Logging")
                    Text("Also record debug-level events to the log file. Leave off unless asked for it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                exportLogs()
            } label: {
                Label("Export Logs…", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Logging")
        } footer: {
            Text("Info-level events are always written to an on-disk log that survives relaunches. Export it and attach it to a bug report when something misbehaves.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private var buildString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    private var buildConfiguration: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "macscp-log-\(Int(Date().timeIntervalSince1970)).txt"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try FileLogStore.shared.export(to: url)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

#Preview {
    SettingsView()
}

// MARK: - URL Scheme Pane

/// Documents the macscp:// scheme and hands out copyable per-connection URLs.
private struct URLSchemeSettingsPane: View {
    @AppStorage(ExternalLaunchRequest.enabledDefaultsKey) private var externalLaunchEnabled = true
    @State private var connections: [Connection] = []

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $externalLaunchEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow launching from URLs")
                        Text("Other apps on this Mac can open saved connections through macscp:// links. Passwords are never part of a URL — macSCP looks them up itself.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Integration")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("macscp://open?connection=<name|id>&view=files|terminal&path=<dir>&new=1")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Text("Use bookmark=<name> instead of connection to start from a saved remote path. path is optional (encode spaces as %20); view defaults to the file browser; new=1 forces a fresh window instead of bringing an already open one to the front.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Syntax")
            }

            Section {
                if connections.isEmpty {
                    Text("No saved connections yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(connections) { connection in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(connection.name)
                                Text(connection.connectionString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Copy URLs") {
                                copyExample(for: connection)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Text("Examples")
            } footer: {
                Text("Copy URLs puts a file-browser and a terminal example for the connection on the clipboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            connections = (try? await DependencyContainer.shared.connectionRepository.fetchAll()) ?? []
        }
    }

    private func copyExample(for connection: Connection) {
        let examples = [
            ExternalLaunchSupport.makeURL(connection: connection.name, view: .files)?.absoluteString,
            ExternalLaunchSupport.makeURL(connection: connection.name, view: .terminal, path: "~")?.absoluteString
        ]
        .compactMap { $0 }
        .joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(examples, forType: .string)
    }
}
