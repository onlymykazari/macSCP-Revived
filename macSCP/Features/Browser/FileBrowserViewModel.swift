//
//  FileBrowserViewModel.swift
//  macSCP
//
//  ViewModel for the file browser feature
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class FileBrowserViewModel {
    // MARK: - Published State
    private(set) var files: [RemoteFile] = []
    private(set) var state: ViewState<Void> = .idle
    private(set) var currentPath: String = "/"
    private(set) var isConnected: Bool = false
    var error: AppError?

    // MARK: - Transfer Progress State
    private(set) var activeTransfers: [UUID: TransferProgress] = [:]
    private(set) var recentTransfers: [TransferProgress] = []  // Completed/failed transfers
    private var transferTasks: [UUID: Task<Void, Never>] = [:]  // Tasks for cancellation
    var isShowingTransfersPopover: Bool = false

    /// Whether any transfer is currently in progress
    var hasActiveTransfers: Bool {
        !activeTransfers.isEmpty
    }

    /// Total number of active transfers
    var activeTransferCount: Int {
        activeTransfers.count
    }

    /// All transfers for display (active + recent)
    var allTransfers: [TransferProgress] {
        let active = activeTransfers.values.sorted { $0.startTime > $1.startTime }
        return active + recentTransfers
    }

    /// Overall progress of all active transfers (0.0 to 1.0)
    var overallProgress: Double {
        guard !activeTransfers.isEmpty else { return 0 }
        let totalBytes = activeTransfers.values.reduce(0) { $0 + $1.totalBytes }
        let transferredBytes = activeTransfers.values.reduce(0) { $0 + $1.bytesTransferred }
        guard totalBytes > 0 else { return 0 }
        return Double(transferredBytes) / Double(totalBytes)
    }

    var selectedFiles: Set<UUID> = []
    var sortCriteria: RemoteFile.SortCriteria = .name
    var sortAscending: Bool = true
    var showHiddenFiles: Bool = false

    // Bookmarks
    private(set) var bookmarks: [Bookmark] = []
    var isShowingRenameBookmarkSheet = false
    var bookmarkToRename: Bookmark?

    // Sheet states
    var isShowingNewFolderSheet = false
    var isShowingNewFileSheet = false
    var isShowingRenameSheet = false
    var isShowingDeleteConfirmation = false
    var isShowingGoToFolder = false

    // File to operate on
    var fileToRename: RemoteFile?
    var filesToDelete: [RemoteFile] = []

    // Window opening state
    var pendingFileInfoWindowId: String?
    var pendingEditorWindowId: String?
    var pendingTerminalWindowId: String?

    // MARK: - Connection Info
    let connection: Connection
    private let password: String

    // MARK: - Dependencies
    private let sftpSession: SFTPSessionProtocol?
    private let s3Session: S3SessionProtocol?
    private let fileRepository: FileRepositoryProtocol
    private let clipboardService: ClipboardService
    private let bookmarkRepository: BookmarkRepositoryProtocol?
    private let navigationService = NavigationService()

    // MARK: - Initialization (SFTP)
    init(
        connection: Connection,
        sftpSession: SFTPSessionProtocol,
        fileRepository: FileRepositoryProtocol,
        clipboardService: ClipboardService,
        password: String,
        bookmarkRepository: BookmarkRepositoryProtocol? = nil
    ) {
        self.connection = connection
        self.sftpSession = sftpSession
        self.s3Session = nil
        self.fileRepository = fileRepository
        self.clipboardService = clipboardService
        self.bookmarkRepository = bookmarkRepository
        self.password = password
    }

    // MARK: - Initialization (S3)
    init(
        connection: Connection,
        s3Session: S3SessionProtocol,
        fileRepository: FileRepositoryProtocol,
        clipboardService: ClipboardService,
        secretAccessKey: String,
        bookmarkRepository: BookmarkRepositoryProtocol? = nil
    ) {
        self.connection = connection
        self.sftpSession = nil
        self.s3Session = s3Session
        self.fileRepository = fileRepository
        self.clipboardService = clipboardService
        self.bookmarkRepository = bookmarkRepository
        self.password = secretAccessKey
    }

    // MARK: - Computed Properties

    var sortedFiles: [RemoteFile] {
        var result = files

        if !showHiddenFiles {
            result = result.filter { !$0.isHidden }
        }

        return RemoteFile.sortedFiles(result, by: sortCriteria, ascending: sortAscending)
    }

    var selectedFilesList: [RemoteFile] {
        files.filter { selectedFiles.contains($0.id) }
    }

    var canGoBack: Bool {
        navigationService.canGoBack
    }

    var canGoForward: Bool {
        navigationService.canGoForward
    }

    var canGoUp: Bool {
        currentPath != "/"
    }

    var pathComponents: [PathComponent] {
        var components: [PathComponent] = []
        var path = ""

        for component in currentPath.split(separator: "/") {
            path += "/" + component
            components.append(PathComponent(name: String(component), path: path))
        }

        if components.isEmpty {
            components.append(PathComponent(name: "/", path: "/"))
        }

        return components
    }

    var clipboardDisplayText: String {
        clipboardService.displayText
    }

    var hasClipboardItems: Bool {
        !clipboardService.isEmpty && !clipboardService.isSuperseded
    }

    var canPaste: Bool {
        clipboardService.canPaste(to: connection.id)
    }

    // MARK: - Connection

    func connect() async {
        state = .loading

        do {
            if connection.connectionType == .s3 {
                // S3 connection
                guard let s3Session = s3Session else {
                    throw AppError.notConnected
                }
                try await s3Session.connect(
                    accessKeyId: connection.username,
                    secretAccessKey: password,
                    region: connection.s3Region ?? "us-east-1",
                    bucket: connection.s3Bucket ?? "",
                    endpoint: connection.s3Endpoint
                )
                isConnected = true
                currentPath = await s3Session.currentPath
                navigationService.reset(to: currentPath)
                AnalyticsService.trackFileBrowserOpened(protocol: .init(from: connection.connectionType))
                await finishConnectionSetup()
            } else {
                // SFTP connection
                guard let sftpSession = sftpSession else {
                    throw AppError.notConnected
                }
                if connection.authMethod == .password {
                    try await sftpSession.connect(
                        host: connection.host,
                        port: connection.port,
                        username: connection.username,
                        password: password
                    )
                } else if let keyPath = connection.privateKeyPath {
                    try ensurePrivateKeyAccess(keyPath)
                    try await sftpSession.connect(
                        host: connection.host,
                        port: connection.port,
                        username: connection.username,
                        privateKeyPath: keyPath,
                        passphrase: password.isEmpty ? nil : password
                    )
                }
                isConnected = true
                currentPath = await sftpSession.currentPath
                navigationService.reset(to: currentPath)
                AnalyticsService.trackFileBrowserOpened(protocol: .init(from: connection.connectionType))
                await finishConnectionSetup()
            }
        } catch {
            logError("Connection failed: \(error)", category: connection.connectionType == .s3 ? .s3 : .sftp)
            state = .error(AppError.from(error))
        }
    }

    /// The sandbox can't read keys in ~/.ssh unless the user granted access.
    /// When the key isn't readable, asks once for the key's folder (covers
    /// every key in it) and remembers the grant for future launches.
    private func ensurePrivateKeyAccess(_ rawKeyPath: String) throws {
        let keyPath = FileManager.mappingContainerHomeToReal(rawKeyPath)
        if keyPath != rawKeyPath {
            logInfo("Private key path remapped from sandbox container to real home: \(keyPath)", category: .app)
        }
        guard !SecurityScopedAccess.shared.canRead(keyPath) else { return }

        let keyFolder = URL(fileURLWithPath: keyPath).deletingLastPathComponent()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = keyFolder
        panel.prompt = "Grant Access"
        panel.message = "Allow macSCP to read the folder containing this connection's private key (\(keyFolder.path))."

        guard panel.runModal() == .OK, let url = panel.url else {
            throw AppError.connectionFailed("Access to the private key folder was not granted.")
        }
        SecurityScopedAccess.shared.remember(url)

        guard SecurityScopedAccess.shared.canRead(keyPath) else {
            throw AppError.connectionFailed("Private key \(keyPath) is still not readable — pick the folder that actually contains it.")
        }
    }

    /// Shared post-connect work: loads bookmarks and jumps to the
    /// connection's default remote path when one is configured.
    private func finishConnectionSetup() async {
        await loadBookmarks()

        if let target = connection.defaultRemotePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !target.isEmpty {
            let normalized = Self.normalizedGoToPath(target, relativeTo: "/") ?? target
            await navigateTo(normalized)
        } else {
            await loadFiles()
        }
    }

    func disconnect() async {
        if connection.connectionType == .s3 {
            await s3Session?.disconnect()
        } else {
            await sftpSession?.disconnect()
        }
        isConnected = false
        files = []
        currentPath = "/"
        navigationService.reset()
    }

    // MARK: - Navigation

    func loadFiles() async {
        state = .loading

        do {
            files = try await fileRepository.listFiles(at: currentPath)
            if connection.connectionType == .s3 {
                currentPath = await s3Session?.currentPath ?? "/"
            } else {
                currentPath = await sftpSession?.currentPath ?? "/"
            }
            state = .success(())
        } catch {
            logError("Failed to load files: \(error)", category: connection.connectionType == .s3 ? .s3 : .sftp)
            state = .error(AppError.from(error))
        }
    }

    func navigateTo(_ path: String) async {
        state = .loading

        do {
            files = try await fileRepository.listFiles(at: path)
            if connection.connectionType == .s3 {
                currentPath = await s3Session?.currentPath ?? "/"
            } else {
                currentPath = await sftpSession?.currentPath ?? "/"
            }
            navigationService.navigate(to: currentPath)
            selectedFiles.removeAll()
            state = .success(())
        } catch {
            logError("Failed to navigate to \(path): \(error)", category: connection.connectionType == .s3 ? .s3 : .sftp)
            state = .error(AppError.from(error))
        }
    }

    func openFile(_ file: RemoteFile) async {
        if file.isDirectory {
            await navigateTo(file.path)
        } else if FileTypeService.isPreviewable(file) {
            // Open in editor - handled by view
        }
    }

    func goBack() async {
        if let path = navigationService.goBack() {
            await navigateWithoutHistory(to: path)
        }
    }

    func goForward() async {
        if let path = navigationService.goForward() {
            await navigateWithoutHistory(to: path)
        }
    }

    func goUp() async {
        await navigateTo(currentPath.parentPath)
    }

    func goHome() async {
        await navigateTo("~")
    }

    // MARK: - Go to Folder

    /// Opens the path input bar in the breadcrumb (via ⇧⌘G or its folder icon)
    func showGoToFolder() {
        guard isConnected else { return }
        isShowingGoToFolder = true
    }

    func dismissGoToFolder() {
        isShowingGoToFolder = false
    }

    /// Navigates to a user-entered path after normalization
    func goToPath(_ input: String) async {
        isShowingGoToFolder = false

        guard let path = Self.normalizedGoToPath(input, relativeTo: currentPath) else { return }

        await navigateTo(path)
    }

    /// Normalizes a user-entered path: trims whitespace, collapses duplicate
    /// separators, resolves "." and ".." segments, and resolves relative input
    /// against `base`. Returns nil for empty input. "~"-prefixed paths are
    /// passed through for the remote session to expand.
    static func normalizedGoToPath(_ input: String, relativeTo base: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("~") {
            return trimmed
        }

        let combined = trimmed.hasPrefix("/") ? trimmed : base + "/" + trimmed
        var segments: [String] = []
        for segment in combined.split(separator: "/") {
            switch segment {
            case ".":
                continue
            case "..":
                if !segments.isEmpty {
                    segments.removeLast()
                }
            default:
                segments.append(String(segment))
            }
        }
        return "/" + segments.joined(separator: "/")
    }

    /// Reloads the current directory. When the session was lost, reconnects
    /// instead — ⌘R recovers an errored/disconnected browser window.
    func refresh() async {
        guard isConnected else {
            await connect()
            return
        }
        await loadFiles()
    }

    private func navigateWithoutHistory(to path: String) async {
        state = .loading

        do {
            files = try await fileRepository.listFiles(at: path)
            if connection.connectionType == .s3 {
                currentPath = await s3Session?.currentPath ?? "/"
            } else {
                currentPath = await sftpSession?.currentPath ?? "/"
            }
            selectedFiles.removeAll()
            state = .success(())
        } catch {
            logError("Failed to navigate to \(path): \(error)", category: connection.connectionType == .s3 ? .s3 : .sftp)
            state = .error(AppError.from(error))
        }
    }

    // MARK: - File Operations

    func createFolder(name: String) async {
        let path = currentPath.appendingPathComponent(name)

        do {
            try await fileRepository.createDirectory(at: path)
            isShowingNewFolderSheet = false
            AnalyticsService.trackFileOperation(.createFolder, protocol: .init(from: connection.connectionType))
            await loadFiles()
        } catch {
            logError("Failed to create folder: \(error)", category: .sftp)
            self.error = AppError.from(error)
        }
    }

    func createFile(name: String) async {
        let path = currentPath.appendingPathComponent(name)

        do {
            try await fileRepository.createFile(at: path)
            isShowingNewFileSheet = false
            await loadFiles()
        } catch {
            logError("Failed to create file: \(error)", category: .sftp)
            self.error = AppError.from(error)
        }
    }

    func renameFile(_ file: RemoteFile, to newName: String) async {
        let newPath = file.path.directoryPath.appendingPathComponent(newName)

        do {
            try await fileRepository.rename(from: file.path, to: newPath)
            isShowingRenameSheet = false
            fileToRename = nil
            AnalyticsService.trackFileOperation(.rename, protocol: .init(from: connection.connectionType))
            await loadFiles()
        } catch {
            logError("Failed to rename file: \(error)", category: .sftp)
            self.error = AppError.from(error)
        }
    }

    func deleteFiles(_ files: [RemoteFile]) async {
        for file in files {
            do {
                try await fileRepository.delete(at: file.path, isDirectory: file.isDirectory)
            } catch {
                logError("Failed to delete \(file.name): \(error)", category: .sftp)
                self.error = AppError.from(error)
                return
            }
        }

        isShowingDeleteConfirmation = false
        filesToDelete = []
        selectedFiles.removeAll()
        AnalyticsService.trackFileOperation(.delete, protocol: .init(from: connection.connectionType), count: files.count)
        await loadFiles()
    }

    func deleteSelectedFiles() async {
        await deleteFiles(selectedFilesList)
    }

    // MARK: - Clipboard Operations

    /// Copies to the in-app clipboard (works within this connection) and, for
    /// files, the Coordinator additionally writes file promises to the system
    /// pasteboard so Finder can paste them as downloads.
    func copySelectedFiles() {
        clipboardService.copy(files: selectedFilesList, from: currentPath, connectionId: connection.id)
    }

    func cutSelectedFiles() {
        clipboardService.cut(files: selectedFilesList, from: currentPath, connectionId: connection.id)
    }

    /// Records that the Coordinator also wrote the selection to the system
    /// pasteboard (drives the status bar hint).
    func noteSystemPasteboardCopy(count: Int) {
        clipboardService.noteSystemCopy(count: count)
    }

    /// Copies the remote paths of the given files to the system pasteboard
    /// (Finder-style ⌥⌘C "Copy as Pathname").
    func copyPathsToPasteboard(_ files: [RemoteFile]) {
        guard !files.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(files.map(\.path).joined(separator: "\n"), forType: .string)
    }

    /// True when the system pasteboard holds local file URLs that could be
    /// pasted (uploaded) into the current remote directory.
    var canPasteFromSystemPasteboard: Bool {
        NSPasteboard.general.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }

    func paste() async {
        if canPaste {
            await pasteFromInternalClipboard()
        } else if canPasteFromSystemPasteboard {
            await pasteFromSystemPasteboard()
        }
    }

    /// Pastes files previously copied/cut within this connection. Pasting a
    /// copy into its own folder (or over an existing name) gets a Finder-style
    /// "name copy" suffix; cutting onto itself is a no-op.
    private func pasteFromInternalClipboard() async {
        let items = clipboardService.items
        let isCut = clipboardService.isCut
        var existingNames = Set(files.map(\.name))

        for item in items {
            let sameFolder = item.fullSourcePath.directoryPath == currentPath
            if isCut && sameFolder {
                continue
            }

            var destinationName = item.fileName
            if sameFolder || existingNames.contains(destinationName) {
                destinationName = Self.uniqueCopyName(for: destinationName, existing: existingNames)
            }
            existingNames.insert(destinationName)
            let destinationPath = currentPath.appendingPathComponent(destinationName)

            do {
                if isCut {
                    try await fileRepository.move(from: item.fullSourcePath, to: destinationPath)
                } else {
                    try await fileRepository.copy(
                        from: item.fullSourcePath,
                        to: destinationPath,
                        isDirectory: item.isDirectory
                    )
                }
            } catch {
                logError("Failed to paste \(item.fileName): \(error)", category: .sftp)
                self.error = AppError.from(error)
                return
            }
        }

        if isCut {
            clipboardService.clear()
        }

        await loadFiles()
    }

    /// Finder-style duplicate naming: "report.pdf" → "report copy.pdf",
    /// then "report copy 2.pdf", … until the name is free.
    static func uniqueCopyName(for name: String, existing: Set<String>) -> String {
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        func candidate(_ suffix: String) -> String {
            ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)"
        }

        var result = candidate("copy")
        var counter = 2
        while existing.contains(result) {
            result = candidate("copy \(counter)")
            counter += 1
        }
        return result
    }

    /// Uploads local files copied in Finder (or other apps) into the current
    /// remote directory.
    private func pasteFromSystemPasteboard() async {
        guard let urls = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else { return }

        let existingURLs = urls.filter { url in
            FileManager.default.fileExists(atPath: url.path)
        }
        guard !existingURLs.isEmpty else { return }

        await uploadDroppedFiles(existingURLs)
    }

    // MARK: - Download/Upload

    func downloadFile(_ file: RemoteFile) async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let transferId = UUID()
        let transfer = TransferProgress(
            id: transferId,
            fileName: file.name,
            localURL: url,
            remotePath: file.path,
            bytesTransferred: 0,
            totalBytes: file.size,
            transferType: .download,
            status: .inProgress
        )
        activeTransfers[transferId] = transfer
        isShowingTransfersPopover = true

        let downloadTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                try Task.checkCancellation()

                try await self.fileRepository.download(remotePath: file.path, to: url) { [weak self] bytesTransferred in
                    Task { @MainActor in
                        guard self?.activeTransfers[transferId] != nil else { return }
                        self?.activeTransfers[transferId]?.bytesTransferred = bytesTransferred
                    }
                }

                try Task.checkCancellation()

                await MainActor.run {
                    if var completedTransfer = self.activeTransfers.removeValue(forKey: transferId) {
                        completedTransfer.status = .completed
                        completedTransfer.bytesTransferred = file.size
                        self.recentTransfers.insert(completedTransfer, at: 0)
                        if self.recentTransfers.count > 10 {
                            self.recentTransfers = Array(self.recentTransfers.prefix(10))
                        }
                    }
                    self.transferTasks.removeValue(forKey: transferId)
                }

                AnalyticsService.trackFileDownloaded(protocol: .init(from: self.connection.connectionType), fileCount: 1, totalBytes: file.size)
                logInfo("Downloaded: \(file.name)", category: self.connection.connectionType == .s3 ? .s3 : .sftp)

            } catch {
                let isCancellation = error is CancellationError ||
                    Task.isCancelled ||
                    String(describing: error).contains("CancellationError")

                if isCancellation {
                    await MainActor.run {
                        if var cancelledTransfer = self.activeTransfers.removeValue(forKey: transferId) {
                            cancelledTransfer.status = .cancelled
                            self.recentTransfers.insert(cancelledTransfer, at: 0)
                        }
                        self.transferTasks.removeValue(forKey: transferId)
                    }
                    logInfo("Download cancelled: \(file.name)", category: self.connection.connectionType == .s3 ? .s3 : .sftp)
                } else {
                    await MainActor.run {
                        if var failedTransfer = self.activeTransfers.removeValue(forKey: transferId) {
                            failedTransfer.status = .failed
                            failedTransfer.error = error.localizedDescription
                            self.recentTransfers.insert(failedTransfer, at: 0)
                        }
                        self.transferTasks.removeValue(forKey: transferId)
                    }

                    logError("Download failed: \(error)", category: self.connection.connectionType == .s3 ? .s3 : .sftp)
                    await MainActor.run {
                        self.error = AppError.from(error)
                    }
                }
            }
        }

        transferTasks[transferId] = downloadTask
    }

    func uploadFiles() async {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else { return }

        await uploadURLs(panel.urls)
    }

    /// Core upload method that handles multiple files with progress tracking
    private func uploadURLs(_ urls: [URL]) async {
        var showedPopover = false

        for url in urls {
            guard url.isFileURL else { continue }

            let remotePath = currentPath.appendingPathComponent(url.lastPathComponent)
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0

            // Create transfer tracking entry
            let transferId = UUID()
            let transfer = TransferProgress(
                id: transferId,
                fileName: url.lastPathComponent,
                localURL: url,
                remotePath: remotePath,
                bytesTransferred: 0,
                totalBytes: fileSize,
                transferType: .upload,
                status: .inProgress
            )
            activeTransfers[transferId] = transfer

            // Show the transfers popover once the first transfer is tracked
            if !showedPopover {
                isShowingTransfersPopover = true
                showedPopover = true
            }

            // Create a task for this upload so it can be cancelled
            let uploadTask = Task { [weak self] in
                guard let self = self else { return }

                do {
                    // Check for cancellation before starting
                    try Task.checkCancellation()

                    try await self.fileRepository.upload(localURL: url, to: remotePath) { [weak self] bytesTransferred in
                        Task { @MainActor in
                            // Check if transfer was cancelled
                            guard self?.activeTransfers[transferId] != nil else { return }
                            self?.activeTransfers[transferId]?.bytesTransferred = bytesTransferred
                        }
                    }

                    // Check for cancellation after upload
                    try Task.checkCancellation()

                    // Mark as completed
                    await MainActor.run {
                        if var completedTransfer = self.activeTransfers.removeValue(forKey: transferId) {
                            completedTransfer.status = .completed
                            completedTransfer.bytesTransferred = fileSize
                            self.recentTransfers.insert(completedTransfer, at: 0)
                            // Keep only last 10 recent transfers
                            if self.recentTransfers.count > 10 {
                                self.recentTransfers = Array(self.recentTransfers.prefix(10))
                            }
                        }
                        self.transferTasks.removeValue(forKey: transferId)
                    }

                    AnalyticsService.trackFileUploaded(protocol: .init(from: self.connection.connectionType), fileCount: 1, totalBytes: fileSize)
                    logInfo("Uploaded: \(url.lastPathComponent)", category: self.connection.connectionType == .s3 ? .s3 : .sftp)

                } catch {
                    // Check if this was a cancellation (either direct CancellationError or Task was cancelled)
                    let isCancellation = error is CancellationError ||
                        Task.isCancelled ||
                        String(describing: error).contains("CancellationError")

                    if isCancellation {
                        // Mark as cancelled (if not already removed by cancelTransfer)
                        await MainActor.run {
                            if var cancelledTransfer = self.activeTransfers.removeValue(forKey: transferId) {
                                cancelledTransfer.status = .cancelled
                                self.recentTransfers.insert(cancelledTransfer, at: 0)
                            }
                            self.transferTasks.removeValue(forKey: transferId)
                        }
                        logInfo("Upload cancelled: \(url.lastPathComponent)", category: self.connection.connectionType == .s3 ? .s3 : .sftp)
                    } else {
                        // Mark as failed
                        await MainActor.run {
                            if var failedTransfer = self.activeTransfers.removeValue(forKey: transferId) {
                                failedTransfer.status = .failed
                                failedTransfer.error = error.localizedDescription
                                self.recentTransfers.insert(failedTransfer, at: 0)
                            }
                            self.transferTasks.removeValue(forKey: transferId)
                        }

                        logError("Upload failed: \(error)", category: self.connection.connectionType == .s3 ? .s3 : .sftp)
                        await MainActor.run {
                            self.error = AppError.from(error)
                        }
                    }
                }
            }

            transferTasks[transferId] = uploadTask

            // Wait for this upload to complete before starting the next one
            await uploadTask.value
        }

        await loadFiles()
    }

    /// Cancels an active transfer
    func cancelTransfer(_ transfer: TransferProgress) {
        guard transfer.isInProgress else { return }

        // Cancel the task
        if let task = transferTasks[transfer.id] {
            task.cancel()
        }

        // Immediately update UI to show cancelled state
        if var cancelledTransfer = activeTransfers.removeValue(forKey: transfer.id) {
            cancelledTransfer.status = .cancelled
            recentTransfers.insert(cancelledTransfer, at: 0)
        }
        transferTasks.removeValue(forKey: transfer.id)
    }

    /// Cancels all active transfers
    func cancelAllTransfers() {
        for (id, task) in transferTasks {
            task.cancel()
            if var cancelledTransfer = activeTransfers.removeValue(forKey: id) {
                cancelledTransfer.status = .cancelled
                recentTransfers.insert(cancelledTransfer, at: 0)
            }
        }
        transferTasks.removeAll()
    }

    // MARK: - Drag and Drop

    /// Downloads a file to a specific URL (used for drag-out file promises)
    func downloadFileToURL(_ file: RemoteFile, destinationURL: URL) async throws {
        let transferId = UUID()
        let transfer = TransferProgress(
            id: transferId,
            fileName: file.name,
            localURL: destinationURL,
            remotePath: file.path,
            bytesTransferred: 0,
            totalBytes: file.size,
            transferType: .download,
            status: .inProgress
        )
        activeTransfers[transferId] = transfer
        isShowingTransfersPopover = true

        do {
            try await fileRepository.download(remotePath: file.path, to: destinationURL) { [weak self] bytesTransferred in
                Task { @MainActor in
                    guard self?.activeTransfers[transferId] != nil else { return }
                    self?.activeTransfers[transferId]?.bytesTransferred = bytesTransferred
                }
            }

            if var completedTransfer = activeTransfers.removeValue(forKey: transferId) {
                completedTransfer.status = .completed
                completedTransfer.bytesTransferred = file.size
                recentTransfers.insert(completedTransfer, at: 0)
                if recentTransfers.count > 10 {
                    recentTransfers = Array(recentTransfers.prefix(10))
                }
            }

            AnalyticsService.trackFileDownloaded(protocol: .init(from: connection.connectionType), fileCount: 1, totalBytes: file.size)
            logInfo("Downloaded via drag: \(file.name)", category: connection.connectionType == .s3 ? .s3 : .sftp)
        } catch {
            if var failedTransfer = activeTransfers.removeValue(forKey: transferId) {
                failedTransfer.status = .failed
                failedTransfer.error = error.localizedDescription
                recentTransfers.insert(failedTransfer, at: 0)
            }
            throw error
        }
    }

    /// Uploads files dropped from Finder into the current directory
    func uploadDroppedFiles(_ urls: [URL]) async {
        await uploadURLs(urls)
    }

    /// Quietly downloads a file to a local URL without transfer tracking
    /// (used for Quick Look staging and Finder copy-out).
    func downloadFileQuietly(_ file: RemoteFile, destinationURL: URL) async throws {
        try await fileRepository.download(remotePath: file.path, to: destinationURL)
    }

    /// Clears completed/failed transfers from the list
    func clearCompletedTransfers() {
        recentTransfers.removeAll()
    }

    /// Removes a specific transfer from the recent list
    func removeTransfer(_ transfer: TransferProgress) {
        recentTransfers.removeAll { $0.id == transfer.id }
    }

    // MARK: - File Content

    func getFileContent(_ file: RemoteFile) async throws -> String {
        try await fileRepository.readFileContent(at: file.path)
    }

    func saveFileContent(_ content: String, to path: String) async throws {
        try await fileRepository.writeFileContent(content, to: path)
    }

    // MARK: - Selection

    func selectAll() {
        selectedFiles = Set(sortedFiles.map { $0.id })
    }

    func deselectAll() {
        selectedFiles.removeAll()
    }

    func toggleSelection(for file: RemoteFile) {
        if selectedFiles.contains(file.id) {
            selectedFiles.remove(file.id)
        } else {
            selectedFiles.insert(file.id)
        }
    }

    // MARK: - UI Actions

    func confirmDelete(_ files: [RemoteFile]) {
        filesToDelete = files
        isShowingDeleteConfirmation = true
    }

    func confirmDeleteSelected() {
        confirmDelete(selectedFilesList)
    }

    func startRename(_ file: RemoteFile) {
        fileToRename = file
        isShowingRenameSheet = true
    }

    func showFileInfo(_ file: RemoteFile) {
        let data = FileInfoWindowData(
            file: file,
            connectionName: connection.name
        )
        let windowId = WindowManager.shared.storeFileInfoData(data)
        pendingFileInfoWindowId = windowId
        AnalyticsService.track(.fileInfoOpened)
    }

    // MARK: - Menu Actions (Finder-style shortcuts)

    func newFolder() {
        guard isConnected else { return }
        isShowingNewFolderSheet = true
    }

    func newFile() {
        logInfo("New File requested (connected: \(isConnected))", category: .ui)
        guard isConnected else { return }
        isShowingNewFileSheet = true
    }

    /// ⌘↓ / ⌘O — opens the selection: directories are entered, previewable
    /// files are downloaded and shown in the editor.
    func openSelectedFiles() {
        let targets = selectedFilesList
        guard !targets.isEmpty else { return }
        for file in targets {
            if file.isDirectory {
                Task { await navigateTo(file.path) }
            } else {
                openFileInEditor(file)
            }
        }
    }

    /// Fetches a file's content and opens it in an editor window.
    func openFileInEditor(_ file: RemoteFile) {
        Task {
            do {
                let content = try await getFileContent(file)
                openEditor(for: file, content: content)
            } catch {
                self.error = AppError.from(error)
            }
        }
    }

    /// ⌘I — opens a Get Info window for each selected file.
    func getInfoForSelectedFiles() {
        for file in selectedFilesList {
            showFileInfo(file)
        }
    }

    func clearPendingFileInfoWindow() {
        pendingFileInfoWindowId = nil
    }

    func openEditor(for file: RemoteFile, content: String) {
        let data = FileEditorWindowData(
            filePath: file.path,
            fileName: file.name,
            content: content,
            connectionId: connection.id,
            host: connection.host,
            port: connection.port,
            username: connection.username,
            password: password,
            authMethod: connection.authMethod,
            privateKeyPath: connection.privateKeyPath,
            connectionType: connection.connectionType,
            s3Region: connection.s3Region,
            s3Bucket: connection.s3Bucket,
            s3Endpoint: connection.s3Endpoint
        )
        let windowId = WindowManager.shared.storeFileEditorData(data)
        pendingEditorWindowId = windowId
        AnalyticsService.trackEditorOpened(fileExtension: (file.name as NSString).pathExtension)
    }

    func clearPendingEditorWindow() {
        pendingEditorWindowId = nil
    }

    func clearPendingTerminalWindow() {
        pendingTerminalWindowId = nil
    }

    // MARK: - Bookmarks

    func loadBookmarks() async {
        guard let bookmarkRepository else { return }
        bookmarks = (try? await bookmarkRepository.fetchAll(connectionId: connection.id)) ?? []
    }

    /// Bookmarks the current remote folder.
    func addCurrentFolderToBookmarks() async {
        guard isConnected, let bookmarkRepository else { return }

        let name = currentPath == "/" ? "/" : (currentPath as NSString).lastPathComponent
        let order = (bookmarks.map(\.displayOrder).max() ?? -1) + 1
        let bookmark = Bookmark(
            connectionId: connection.id,
            name: name,
            remotePath: currentPath,
            displayOrder: order
        )

        do {
            try await bookmarkRepository.save(bookmark)
            await loadBookmarks()
        } catch {
            logError("Failed to add bookmark: \(error)", category: .database)
            self.error = AppError.from(error)
        }
    }

    func renameBookmark(_ bookmark: Bookmark, to newName: String) async {
        guard let bookmarkRepository else { return }

        var updated = bookmark.withUpdatedTimestamp()
        updated.name = newName

        do {
            try await bookmarkRepository.update(updated)
            await loadBookmarks()
        } catch {
            logError("Failed to rename bookmark: \(error)", category: .database)
            self.error = AppError.from(error)
        }
    }

    func deleteBookmark(_ bookmark: Bookmark) async {
        guard let bookmarkRepository else { return }

        do {
            try await bookmarkRepository.delete(id: bookmark.id)
            await loadBookmarks()
        } catch {
            logError("Failed to delete bookmark: \(error)", category: .database)
            self.error = AppError.from(error)
        }
    }

    /// Dismisses the bookmark-rename sheet.
    func dismissBookmarkRename() {
        isShowingRenameBookmarkSheet = false
        bookmarkToRename = nil
    }

    // MARK: - Terminal

    func openTerminal() {
        // Only supported for SFTP connections
        guard connection.connectionType == .sftp else {
            logWarning("Terminal only supported for SFTP connections", category: .ui)
            return
        }

        let data = TerminalWindowData(
            connectionId: connection.id,
            connectionName: connection.name,
            host: connection.host,
            port: connection.port,
            username: connection.username,
            password: password,
            authMethod: connection.authMethod,
            privateKeyPath: connection.privateKeyPath
        )

        let windowId = WindowManager.shared.storeTerminalData(data)
        pendingTerminalWindowId = windowId
        logInfo("Opening terminal from file browser", category: .ui)
    }

    func clearError() {
        error = nil
    }
}

// MARK: - Path Component
struct PathComponent: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let path: String

    static func == (lhs: PathComponent, rhs: PathComponent) -> Bool {
        lhs.path == rhs.path && lhs.name == rhs.name
    }
}
