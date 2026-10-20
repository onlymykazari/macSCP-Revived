//
//  SSHConfigImportSheet.swift
//  macSCP
//
//  Import wizard: read an ssh config file (via NSOpenPanel, which grants the
//  sandbox access) or paste its text, preview the parsed hosts, and import
//  the selected ones as connections.
//

import SwiftUI

struct SSHConfigImportSheet: View {
    /// Names that already exist locally; shown as duplicates, unchecked by default
    let existingNames: Set<String>
    let onImport: ([ParsedSSHHost]) -> Void
    let onCancel: () -> Void

    @State private var hosts: [ParsedSSHHost] = []
    @State private var selectedIds: Set<UUID> = []
    @State private var sourceName: String?
    @State private var message: String?

    @State private var isShowingTextEntry = false
    @State private var pastedText = ""

    private var importableHosts: [ParsedSSHHost] {
        hosts.filter { !existingNames.contains($0.name) }
    }

    private var selectedCount: Int {
        hosts.filter { selectedIds.contains($0.id) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Import from ssh config")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()

            Divider()

            if hosts.isEmpty {
                emptyState
            } else {
                hostList
            }

            Divider()

            footer
        }
        .frame(width: 560, height: 460)
        .sheet(isPresented: $isShowingTextEntry) {
            textEntrySheet
        }
    }

    // MARK: - Empty State (choose source)

    private var emptyState: some View {
        VStack(spacing: 16) {
            if let message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Read your ~/.ssh/config to create connections automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                Button("Choose Config File…") {
                    chooseConfigFile()
                }
                .keyboardShortcut(.defaultAction)

                Button("Paste Config Text…") {
                    pastedText = ""
                    isShowingTextEntry = true
                }
            }

            Text("Wildcard patterns, Include and Proxy directives are skipped.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Host List

    private var hostList: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let sourceName {
                Text(sourceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            List(hosts) { host in
                let isDuplicate = existingNames.contains(host.name)
                hostRow(host, isDuplicate: isDuplicate)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    @ViewBuilder
    private func hostRow(_ host: ParsedSSHHost, isDuplicate: Bool) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { selectedIds.contains(host.id) },
                set: { on in
                    if on {
                        selectedIds.insert(host.id)
                    } else {
                        selectedIds.remove(host.id)
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(isDuplicate)

            Image(systemName: host.authMethod.iconName)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(host.name)
                    .font(.system(size: 13, weight: .medium))

                HStack(spacing: 6) {
                    Text("\(host.suggestedUsername)@\(host.host):\(host.port)")

                    if let keyPath = host.identityFile {
                        Label(
                            (keyPath as NSString).lastPathComponent,
                            systemImage: "key"
                        )
                        .help(keyPath)
                    } else {
                        Label("password on first connect", systemImage: "lock.open")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if isDuplicate {
                Text("Already exists")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Import \(selectedCount) Connection\(selectedCount == 1 ? "" : "s")") {
                importSelected()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedCount == 0)
        }
        .padding()
    }

    // MARK: - Paste Text Sheet

    private var textEntrySheet: some View {
        VStack(spacing: 12) {
            Text("Paste ssh config")
                .font(.headline)

            TextEditor(text: $pastedText)
                .font(.system(size: 12, design: .monospaced))
                .border(Color.secondary.opacity(0.3))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button("Cancel") {
                    isShowingTextEntry = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Parse") {
                    isShowingTextEntry = false
                    apply(pastedText, sourceName: "pasted text")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 480, height: 340)
    }

    // MARK: - Actions

    /// Imports the selection. Private keys referenced by the config usually
    /// live in ~/.ssh, which the sandbox can't read, so the user is asked
    /// once to grant access to that folder before importing.
    private func importSelected() {
        let selected = hosts.filter { selectedIds.contains($0.id) }

        let unreadableKeys = selected
            .compactMap(\.identityFile)
            .filter { !SecurityScopedAccess.shared.canRead($0) }

        if let firstKey = unreadableKeys.first {
            let keyFolder = URL(fileURLWithPath: firstKey).deletingLastPathComponent()
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = keyFolder
            panel.prompt = "Grant Access"
            panel.message = "Allow macSCP to read the folder containing your private keys (usually ~/.ssh) so the imported connections can authenticate."

            if panel.runModal() == .OK, let url = panel.url {
                SecurityScopedAccess.shared.remember(url)
            } else {
                logWarning("ssh config import: key folder access not granted; key-based hosts will fail to connect until a key is re-picked", category: .ui)
            }
        }

        onImport(selected)
    }

    private func chooseConfigFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select your ssh config file (usually ~/.ssh/config)"
        panel.directoryURL = URL(fileURLWithPath: FileManager.realHomeDirectory)
            .appendingPathComponent(".ssh", isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            apply(text, sourceName: url.lastPathComponent)
        } catch {
            hosts = []
            selectedIds = []
            message = "Couldn't read file: \(error.localizedDescription)"
        }
    }

    private func apply(_ text: String, sourceName: String) {
        let parsed = SSHConfigParser.parse(text)
        guard !parsed.isEmpty else {
            hosts = []
            selectedIds = []
            self.sourceName = nil
            message = "No usable host entries found in \(sourceName)."
            return
        }

        message = nil
        self.sourceName = sourceName
        hosts = parsed
        // Preselect everything new; duplicates stay unchecked
        selectedIds = Set(parsed.filter { !existingNames.contains($0.name) }.map(\.id))
    }
}

// MARK: - Preview
#Preview {
    SSHConfigImportSheet(
        existingNames: ["prod-web"],
        onImport: { _ in },
        onCancel: {}
    )
}
