//
//  NativeFileTableView.swift
//  macSCP
//
//  NSViewRepresentable wrapping NSTableView for native drag and drop support
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Quartz

struct NativeFileTableView: NSViewRepresentable {
    @Bindable var viewModel: FileBrowserViewModel
    let onDoubleClick: (RemoteFile) -> Void
    let onGetInfo: (RemoteFile) -> Void
    let onOpenEditor: ((RemoteFile) -> Void)?

    init(
        viewModel: FileBrowserViewModel,
        onDoubleClick: @escaping (RemoteFile) -> Void,
        onGetInfo: @escaping (RemoteFile) -> Void,
        onOpenEditor: ((RemoteFile) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onDoubleClick = onDoubleClick
        self.onGetInfo = onGetInfo
        self.onOpenEditor = onOpenEditor
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = ContextMenuTableView()

        // Configure columns
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Name"
        nameColumn.width = 250
        nameColumn.minWidth = 150
        nameColumn.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)

        let kindColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("kind"))
        kindColumn.title = "Kind"
        kindColumn.width = 120
        kindColumn.minWidth = 80
        kindColumn.sortDescriptorPrototype = NSSortDescriptor(key: "kind", ascending: true)

        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateColumn.title = "Date Modified"
        dateColumn.width = 140
        dateColumn.minWidth = 100
        dateColumn.sortDescriptorPrototype = NSSortDescriptor(key: "date", ascending: true)

        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeColumn.title = "Size"
        sizeColumn.width = 80
        sizeColumn.minWidth = 60
        sizeColumn.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: true)

        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(kindColumn)
        tableView.addTableColumn(dateColumn)
        tableView.addTableColumn(sizeColumn)

        // Configure table appearance
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.rowHeight = 28
        tableView.intercellSpacing = NSSize(width: 6, height: 2)
        tableView.gridStyleMask = []

        // Set up actions
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))

        // Enable drag and drop
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("com.apple.NSFilePromiseProvider")])

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        // Set up context menu
        tableView.contextMenuDelegate = context.coordinator
        tableView.keyDownDelegate = context.coordinator

        // Configure scroll view
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        context.coordinator.tableView = tableView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.onDoubleClick = onDoubleClick
        context.coordinator.onGetInfo = onGetInfo
        context.coordinator.onOpenEditor = onOpenEditor

        // Update selection state
        if let tableView = context.coordinator.tableView {
            context.coordinator.isUpdating = true
            tableView.reloadData()

            // Sync selection from viewModel to tableView
            let selectedIndexes = NSMutableIndexSet()
            for (index, file) in viewModel.sortedFiles.enumerated() {
                if viewModel.selectedFiles.contains(file.id) {
                    selectedIndexes.add(index)
                }
            }
            tableView.selectRowIndexes(selectedIndexes as IndexSet, byExtendingSelection: false)
            context.coordinator.isUpdating = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            viewModel: viewModel,
            onDoubleClick: onDoubleClick,
            onGetInfo: onGetInfo,
            onOpenEditor: onOpenEditor
        )
    }

    @MainActor
    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSFilePromiseProviderDelegate, ContextMenuTableViewDelegate, FileTableViewKeyHandling, PreviewPanelControlling {
        var viewModel: FileBrowserViewModel
        var onDoubleClick: (RemoteFile) -> Void
        var onGetInfo: (RemoteFile) -> Void
        var onOpenEditor: ((RemoteFile) -> Void)?
        weak var tableView: NSTableView?
        var isUpdating = false

        // Track files being dragged for file promise
        private var draggedFiles: [RemoteFile] = []
        private let filePromiseQueue = OperationQueue()
        /// Files currently staged for Quick Look preview
        private var previewItems: [QuickLookPreviewItem] = []

        init(
            viewModel: FileBrowserViewModel,
            onDoubleClick: @escaping (RemoteFile) -> Void,
            onGetInfo: @escaping (RemoteFile) -> Void,
            onOpenEditor: ((RemoteFile) -> Void)?
        ) {
            self.viewModel = viewModel
            self.onDoubleClick = onDoubleClick
            self.onGetInfo = onGetInfo
            self.onOpenEditor = onOpenEditor
            self.filePromiseQueue.qualityOfService = .userInitiated
        }

        // MARK: - NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            viewModel.sortedFiles.count
        }

        // MARK: - NSTableViewDelegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < viewModel.sortedFiles.count else { return nil }
            let file = viewModel.sortedFiles[row]
            let columnId = tableColumn?.identifier.rawValue ?? ""
            let cellId = NSUserInterfaceItemIdentifier("Cell_\(columnId)")

            var cell = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTableCellView

            if cell == nil {
                cell = NSTableCellView()
                cell?.identifier = cellId

                let textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.lineBreakMode = .byTruncatingTail
                textField.font = NSFont.systemFont(ofSize: 13)

                cell?.addSubview(textField)
                cell?.textField = textField

                if columnId == "name" {
                    let imageView = NSImageView()
                    imageView.translatesAutoresizingMaskIntoConstraints = false
                    imageView.imageScaling = .scaleProportionallyUpOrDown
                    cell?.addSubview(imageView)
                    cell?.imageView = imageView

                    NSLayoutConstraint.activate([
                        imageView.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 4),
                        imageView.centerYAnchor.constraint(equalTo: cell!.centerYAnchor),
                        imageView.widthAnchor.constraint(equalToConstant: 20),
                        imageView.heightAnchor.constraint(equalToConstant: 20),
                        textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
                        textField.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -4),
                        textField.centerYAnchor.constraint(equalTo: cell!.centerYAnchor)
                    ])
                } else {
                    NSLayoutConstraint.activate([
                        textField.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 4),
                        textField.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -4),
                        textField.centerYAnchor.constraint(equalTo: cell!.centerYAnchor)
                    ])
                }
            }

            switch columnId {
            case "name":
                cell?.textField?.stringValue = file.name
                cell?.textField?.textColor = .labelColor
                let iconName = FileTypeService.iconName(for: file)
                if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
                    let color = NSColor(FileTypeService.iconColor(for: file))
                    cell?.imageView?.image = image
                    cell?.imageView?.contentTintColor = color
                }
            case "kind":
                cell?.textField?.stringValue = FileTypeService.typeDescription(for: file)
                cell?.textField?.textColor = .secondaryLabelColor
            case "date":
                cell?.textField?.stringValue = file.modificationDate?.fileListDisplayString ?? "--"
                cell?.textField?.textColor = .secondaryLabelColor
            case "size":
                cell?.textField?.stringValue = file.displaySize
                cell?.textField?.textColor = .secondaryLabelColor
            default:
                break
            }

            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdating, let tableView = tableView else { return }
            let selectedIndexes = tableView.selectedRowIndexes
            var newSelection = Set<UUID>()
            for index in selectedIndexes {
                if index < viewModel.sortedFiles.count {
                    newSelection.insert(viewModel.sortedFiles[index].id)
                }
            }
            viewModel.selectedFiles = newSelection
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let sortDescriptor = tableView.sortDescriptors.first,
                  let key = sortDescriptor.key else { return }

            switch key {
            case "name":
                viewModel.sortCriteria = .name
            case "kind":
                viewModel.sortCriteria = .type
            case "date":
                viewModel.sortCriteria = .date
            case "size":
                viewModel.sortCriteria = .size
            default:
                break
            }

            viewModel.sortAscending = sortDescriptor.ascending
        }

        @objc func handleDoubleClick(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0 && row < viewModel.sortedFiles.count else { return }
            let file = viewModel.sortedFiles[row]
            onDoubleClick(file)
        }

        // MARK: - Drag OUT (Download via File Promise)

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row < viewModel.sortedFiles.count else { return nil }
            let file = viewModel.sortedFiles[row]
            guard file.isFile else { return nil } // Skip directories for now

            let provider = NSFilePromiseProvider(fileType: UTType.data.identifier, delegate: self)
            provider.userInfo = ["file": file, "row": row]
            return provider
        }

        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
            // Store all files being dragged
            draggedFiles = rowIndexes.compactMap { index in
                guard index < viewModel.sortedFiles.count else { return nil }
                return viewModel.sortedFiles[index]
            }.filter { $0.isFile }
        }

        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            draggedFiles = []
        }

        // MARK: - NSFilePromiseProviderDelegate

        func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
            guard let userInfo = filePromiseProvider.userInfo as? [String: Any],
                  let file = userInfo["file"] as? RemoteFile else {
                return "unknown"
            }
            return file.name
        }

        func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
            guard let userInfo = filePromiseProvider.userInfo as? [String: Any],
                  let file = userInfo["file"] as? RemoteFile else {
                completionHandler(nil)
                return
            }

            Task { @MainActor in
                do {
                    try await viewModel.downloadFileToURL(file, destinationURL: url)
                    completionHandler(nil)
                } catch {
                    completionHandler(error)
                }
            }
        }

        func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
            filePromiseQueue
        }

        // MARK: - Drop IN (Upload)

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            // Accept file URLs from Finder
            if info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
                // Drop on the table (not between rows)
                tableView.setDropRow(-1, dropOperation: .on)
                return .copy
            }
            return []
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else {
                return false
            }

            // Filter to only include files that exist
            let validURLs = urls.filter { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            }

            guard !validURLs.isEmpty else { return false }

            Task { @MainActor in
                await viewModel.uploadDroppedFiles(validURLs)
            }

            return true
        }
    }
}

// MARK: - Context Menu Support
extension NativeFileTableView.Coordinator {
    /// Files a context-menu action should operate on: the whole selection when
    /// the clicked row is part of it, otherwise just the clicked row.
    private func targetFiles(for clickedFile: RemoteFile) -> [RemoteFile] {
        if viewModel.selectedFiles.contains(clickedFile.id), !viewModel.selectedFiles.isEmpty {
            return viewModel.selectedFilesList
        }
        return [clickedFile]
    }

    func contextMenu(for row: Int) -> NSMenu? {
        guard row >= 0 && row < viewModel.sortedFiles.count else { return nil }
        let file = viewModel.sortedFiles[row]
        let targets = targetFiles(for: file)

        let menu = NSMenu()

        if file.isFile {
            let openItem = NSMenuItem(title: "Open in Editor", action: #selector(handleOpenInEditor(_:)), keyEquivalent: "")
            openItem.target = self
            openItem.representedObject = file
            openItem.image = NSImage(systemSymbolName: "pencil.and.outline", accessibilityDescription: nil)
            menu.addItem(openItem)
            menu.addItem(NSMenuItem.separator())
        }

        let copyItem = NSMenuItem(title: "Copy", action: #selector(handleCopy(_:)), keyEquivalent: "c")
        copyItem.keyEquivalentModifierMask = .command
        copyItem.target = self
        copyItem.representedObject = file
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyItem.toolTip = "Copy for pasting within this app, or paste into Finder to download"
        menu.addItem(copyItem)

        let cutItem = NSMenuItem(title: "Cut", action: #selector(handleCut(_:)), keyEquivalent: "x")
        cutItem.keyEquivalentModifierMask = .command
        cutItem.target = self
        cutItem.representedObject = file
        cutItem.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)
        cutItem.toolTip = "Cut for moving within this connection (paste to move)"
        menu.addItem(cutItem)

        if viewModel.canPaste || viewModel.canPasteFromSystemPasteboard {
            let pasteItem = NSMenuItem(title: "Paste", action: #selector(handlePaste(_:)), keyEquivalent: "v")
            pasteItem.keyEquivalentModifierMask = .command
            pasteItem.target = self
            pasteItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
            pasteItem.toolTip = viewModel.canPaste
                ? "Paste files copied within this connection"
                : "Upload files copied in Finder"
            menu.addItem(pasteItem)
        }

        let copyPathItem = NSMenuItem(title: "Copy Path", action: #selector(handleCopyPath(_:)), keyEquivalent: "c")
        copyPathItem.keyEquivalentModifierMask = [.command, .option]
        copyPathItem.target = self
        copyPathItem.representedObject = file
        copyPathItem.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        menu.addItem(copyPathItem)

        menu.addItem(NSMenuItem.separator())

        let renameItem = NSMenuItem(title: "Rename", action: #selector(handleRename(_:)), keyEquivalent: "")
        renameItem.target = self
        renameItem.representedObject = file
        renameItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
        menu.addItem(renameItem)

        let infoItem = NSMenuItem(title: "Get Info", action: #selector(handleGetInfo(_:)), keyEquivalent: "i")
        infoItem.keyEquivalentModifierMask = .command
        infoItem.target = self
        infoItem.representedObject = file
        infoItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(infoItem)

        menu.addItem(NSMenuItem.separator())

        if file.isFile {
            let downloadItem = NSMenuItem(title: "Download", action: #selector(handleDownload(_:)), keyEquivalent: "")
            downloadItem.target = self
            downloadItem.representedObject = file
            downloadItem.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
            menu.addItem(downloadItem)
            menu.addItem(NSMenuItem.separator())
        }

        let deleteItem = NSMenuItem(title: "Delete", action: #selector(handleDelete(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = file
        deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(deleteItem)

        return menu
    }

    @objc func handleOpenInEditor(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? RemoteFile else { return }
        onOpenEditor?(file)
    }

    @objc func handleCopy(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? RemoteFile else { return }
        let targets = targetFiles(for: file)
        viewModel.selectedFiles = Set(targets.map(\.id))
        viewModel.copySelectedFiles()
        copyTargetsToSystemPasteboard(targets)
    }

    @objc func handleCut(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? RemoteFile else { return }
        let targets = targetFiles(for: file)
        viewModel.selectedFiles = Set(targets.map(\.id))
        viewModel.cutSelectedFiles()
    }

    @objc func handlePaste(_ sender: NSMenuItem) {
        Task { @MainActor in
            await viewModel.paste()
        }
    }

    @objc func handleCopyPath(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? RemoteFile else { return }
        let targets = targetFiles(for: file)
        viewModel.copyPathsToPasteboard(targets)
    }

    @objc func handleRename(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? RemoteFile else { return }
        viewModel.startRename(file)
    }

    @objc func handleGetInfo(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? RemoteFile else { return }
        onGetInfo(file)
    }

    @objc func handleDownload(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? RemoteFile else { return }
        Task { @MainActor in
            await viewModel.downloadFile(file)
        }
    }

    @objc func handleDelete(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? RemoteFile else { return }
        viewModel.confirmDelete(targetFiles(for: file))
    }

    // MARK: System Pasteboard (Finder-style copy out)

    /// Files up to this size are staged to a temp file so the system
    /// pasteboard can hold a real file URL (which Finder reliably pastes).
    /// NSFilePromiseProvider was tried first: Finder discovers the promise on
    /// the pasteboard but never fulfils it, so paste does nothing.
    private static let maxFinderCopyBytes: Int64 = 50 * 1024 * 1024

    /// Copies the given files to the system pasteboard as local file URLs by
    /// first downloading them to a temporary directory. Directories and files
    /// over the size limit are skipped (they remain in the in-app clipboard
    /// only). Runs async; the status-bar hint appears once written.
    func copyTargetsToSystemPasteboard(_ files: [RemoteFile]) {
        let candidates = files.filter { $0.isFile && $0.size <= Self.maxFinderCopyBytes }
        guard !candidates.isEmpty else {
            logDebug("Copy: nothing staged for Finder paste (directories only or files too large)", category: .app)
            return
        }

        Task { @MainActor in
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("macSCPClipboard", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            } catch {
                logError("Copy staging directory creation failed: \(error)", category: .app)
                return
            }

            var urls: [NSURL] = []
            for file in candidates {
                let destination = staging.appendingPathComponent(file.name)
                do {
                    try await viewModel.downloadFileQuietly(file, destinationURL: destination)
                    urls.append(NSURL(fileURLWithPath: destination.path))
                } catch {
                    logError("Copy staging failed for \(file.name): \(error)", category: .app)
                }
            }
            guard !urls.isEmpty else { return }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let success = pasteboard.writeObjects(urls)
            if success {
                viewModel.noteSystemPasteboardCopy(count: urls.count)
            }
            logInfo("Copied \(urls.count) file(s) to system pasteboard as file URLs (write: \(success))", category: .app)
        }
    }

    // MARK: Keyboard Handling (Finder-style shortcuts)

    // ANSI key codes; used instead of charactersIgnoringModifiers because
    // Option-modified keys produce alternate characters (⌥C → "ç").
    private enum KeyCodes {
        static let a: UInt16 = 0
        static let x: UInt16 = 7
        static let c: UInt16 = 8
        static let v: UInt16 = 9
        static let n: UInt16 = 45
        static let delete: UInt16 = 51
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let space: UInt16 = 49
    }

    /// Returns true if the key event was handled as a browser shortcut.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)
        let hasCommand = flags.contains(.command)
        let hasOption = flags.contains(.option)
        let hasControl = flags.contains(.control)
        let hasShift = flags.contains(.shift)

        // ⇧⌘N / ⌥⌘N — New File. The menu item carries ⇧⌘N, but Shift+letter
        // key equivalents don't dispatch reliably from SwiftUI commands (and
        // ⇧⌘N is a popular global hotkey), so the table handles both directly.
        if event.keyCode == KeyCodes.n, hasCommand, hasShift || hasOption, !hasControl {
            logInfo("New File shortcut via table keyDown (shift: \(hasShift), option: \(hasOption))", category: .ui)
            viewModel.newFile()
            return true
        }

        // Plain keys (no modifiers)
        if !hasCommand && !hasOption && !hasControl {
            switch event.keyCode {
            case KeyCodes.delete:
                guard !viewModel.selectedFiles.isEmpty else { return false }
                viewModel.confirmDeleteSelected()
                return true
            case KeyCodes.returnKey, KeyCodes.keypadEnter:
                guard viewModel.selectedFilesList.count == 1,
                      let file = viewModel.selectedFilesList.first else { return false }
                viewModel.startRename(file)
                return true
            case KeyCodes.space:
                guard viewModel.selectedFilesList.count == 1,
                      let file = viewModel.selectedFilesList.first,
                      file.isFile else { return false }
                beginQuickLook(for: file)
                return true
            default:
                break
            }
        }

        switch (event.keyCode, hasCommand, hasOption, hasControl) {
        case (KeyCodes.c, true, false, false): // ⌘C
            guard !viewModel.selectedFiles.isEmpty else { return false }
            viewModel.copySelectedFiles()
            copyTargetsToSystemPasteboard(viewModel.selectedFilesList)
            return true
        case (KeyCodes.c, true, true, false): // ⌥⌘C — copy path
            guard !viewModel.selectedFiles.isEmpty else { return false }
            viewModel.copyPathsToPasteboard(viewModel.selectedFilesList)
            return true
        case (KeyCodes.x, true, false, false): // ⌘X
            guard !viewModel.selectedFiles.isEmpty else { return false }
            viewModel.cutSelectedFiles()
            return true
        case (KeyCodes.v, true, false, false): // ⌘V
            Task { @MainActor in
                await viewModel.paste()
            }
            return true
        case (KeyCodes.a, true, false, false): // ⌘A — let NSTableView handle select-all
            return false
        default:
            return false
        }
    }

    // MARK: Quick Look (Space)

    /// Stages the selected file locally and opens it in the system Quick Look
    /// panel. The file must download first, so the panel opens after a short
    /// delay on slow connections.
    func beginQuickLook(for file: RemoteFile) {
        guard file.size <= QuickLookConstants.maxPreviewBytes else {
            logInfo("Quick Look skipped for \(file.name): larger than \(QuickLookConstants.maxPreviewBytes) bytes", category: .app)
            return
        }

        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(
                    at: QuickLookConstants.stagingDirectory,
                    withIntermediateDirectories: true
                )
                let destination = QuickLookConstants.stagingDirectory.appendingPathComponent(file.name)
                try await viewModel.downloadFileQuietly(file, destinationURL: destination)
                previewItems = [QuickLookPreviewItem(url: destination, title: file.name)]
                QLPreviewPanel.shared()?.makeKeyAndOrderFront(nil)
            } catch {
                logError("Quick Look staging failed for \(file.name): \(error)", category: .app)
            }
        }
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.reloadData()
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
    }
}

// MARK: - Quick Look Data Source
extension NativeFileTableView.Coordinator: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        previewItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> any QLPreviewItem {
        previewItems[index]
    }
}

// MARK: - Context Menu & Keyboard Support
protocol ContextMenuTableViewDelegate: AnyObject {
    func contextMenu(for row: Int) -> NSMenu?
}

protocol FileTableViewKeyHandling: AnyObject {
    /// Returns true if the key event was consumed as a browser shortcut.
    func handleKeyDown(_ event: NSEvent) -> Bool
}

/// Bridges QLPreviewPanel's responder-chain control to the coordinator.
protocol PreviewPanelControlling: AnyObject {
    func beginPreviewPanelControl(_ panel: QLPreviewPanel)
    func endPreviewPanelControl(_ panel: QLPreviewPanel)
}

class ContextMenuTableView: NSTableView {
    weak var contextMenuDelegate: ContextMenuTableViewDelegate?
    weak var keyDownDelegate: (FileTableViewKeyHandling & PreviewPanelControlling)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)

        if row >= 0 {
            // Select the row if not already selected
            if !selectedRowIndexes.contains(row) {
                selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            return contextMenuDelegate?.contextMenu(for: row)
        }

        return super.menu(for: event)
    }

    override func keyDown(with event: NSEvent) {
        if keyDownDelegate?.handleKeyDown(event) == true { return }
        super.keyDown(with: event)
    }

    // MARK: Quick Look (Space)

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel) {
        keyDownDelegate?.beginPreviewPanelControl(panel)
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel) {
        keyDownDelegate?.endPreviewPanelControl(panel)
    }
}
