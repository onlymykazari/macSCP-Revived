//
//  MacSCPApp.swift
//  macSCP
//
//  Main application entry point
//

import SwiftUI
import SwiftData
import Sparkle

@main
struct MacSCPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var container = DependencyContainer.shared

    private let updaterController: SPUStandardUpdaterController
    @StateObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel

    init() {
        AnalyticsService.initialize()
        AppLockManager.shared.lockIfNeeded()

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updaterController = controller
        self._checkForUpdatesViewModel = StateObject(
            wrappedValue: CheckForUpdatesViewModel(updater: controller.updater)
        )
    }

    var body: some Scene {
        // Main Window - Connection List
        WindowGroup {
            ConnectionListWindow()
        }
        .modelContainer(container.modelContainer)
        .defaultSize(WindowSize.main)
        .commands {
            appCommands
        }

        // File Browser Window
        WindowGroup(id: WindowID.fileBrowser, for: String.self) { $windowId in
            if let windowId = windowId {
                FileBrowserWindow(windowId: windowId)
                    .appLockOverlay()
            }
        }
        .modelContainer(container.modelContainer)
        .defaultSize(WindowSize.fileBrowser)

        // File Editor Window
        WindowGroup(id: WindowID.fileEditor, for: String.self) { $windowId in
            if let windowId = windowId {
                FileEditorWindow(windowId: windowId)
                    .appLockOverlay()
            }
        }
        .modelContainer(container.modelContainer)
        .defaultSize(WindowSize.fileEditor)

        // File Info Window
        WindowGroup(id: WindowID.fileInfo, for: String.self) { $windowId in
            if let windowId = windowId {
                FileInfoWindow(windowId: windowId)
                    .appLockOverlay()
            }
        }
        .modelContainer(container.modelContainer)
        .defaultSize(WindowSize.fileInfo)
        .windowResizability(.contentSize)

        // Terminal Window
        WindowGroup(id: WindowID.terminal, for: String.self) { $windowId in
            if let windowId = windowId {
                TerminalWindow(windowId: windowId)
                    .appLockOverlay()
            }
        }
        .modelContainer(container.modelContainer)
        .defaultSize(WindowSize.terminal)

        // Settings Window (Cmd+,)
        Settings {
            SettingsView()
                .appLockOverlay()
        }
    }

    @FocusedValue(\.browserViewModel) private var browserVM: FileBrowserViewModel?
    @FocusedValue(\.connectionListViewModel) private var connectionListVM: ConnectionListViewModel?

    // MARK: - Commands
    @CommandsBuilder
    private var appCommands: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesView(viewModel: checkForUpdatesViewModel)
        }

        CommandGroup(replacing: .newItem) {
            // In the browser window ⌘N creates a remote folder (Finder-style);
            // in the main window it creates a connection.
            Button(browserVM != nil ? "New Folder" : "New Connection") {
                if let browserVM {
                    browserVM.newFolder()
                } else {
                    connectionListVM?.isShowingNewConnectionSheet = true
                }
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(browserVM == nil && connectionListVM == nil)

            // Uppercase key equivalent = Shift implied; SwiftUI does not
            // reliably match a lowercase letter combined with the .shift flag
            Button("New File") {
                browserVM?.newFile()
            }
            .keyboardShortcut("N", modifiers: .command)
            .disabled(browserVM == nil)
        }

        CommandGroup(after: .toolbar) {
            Button("Refresh") {
                Task { await browserVM?.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(browserVM == nil)

            Button("Get Info") {
                browserVM?.getInfoForSelectedFiles()
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(browserVM == nil)

            // ⌘D (Safari-style); ⌘B is taken by the default Format ▸ Bold item
            Button("Add Bookmark") {
                Task { await browserVM?.addCurrentFolderToBookmarks() }
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(browserVM == nil)
        }

        // Finder-style Go menu for the file browser
        CommandMenu("Go") {
            Button("Back") {
                Task { await browserVM?.goBack() }
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(browserVM == nil)

            Button("Forward") {
                Task { await browserVM?.goForward() }
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(browserVM == nil)

            Divider()

            Button("Enclosing Folder") {
                Task { await browserVM?.goUp() }
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(browserVM == nil)

            Button("Open Selection") {
                browserVM?.openSelectedFiles()
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(browserVM == nil)

            Divider()

            Button("Go to Folder…") {
                browserVM?.showGoToFolder()
            }
            .keyboardShortcut("g", modifiers: [.shift, .command])
            .disabled(browserVM == nil)
        }

        CommandGroup(replacing: .help) {
            Button("Report a Bug…") {
                if let url = URL(string: "https://github.com/onlymykazari/macSCP-Revived/issues") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
