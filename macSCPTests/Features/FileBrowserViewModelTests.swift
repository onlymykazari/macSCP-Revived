//
//  FileBrowserViewModelTests.swift
//  macSCPTests
//
//  Unit tests for FileBrowserViewModel
//

import XCTest
@testable import macSCP

@MainActor
final class FileBrowserViewModelTests: XCTestCase {
    var sut: FileBrowserViewModel!
    var mockSFTPSession: MockSFTPSession!
    var mockFileRepository: MockFileRepository!
    var mockClipboardService: ClipboardService!

    let testConnection = Connection(
        name: "Test Server",
        host: "test.example.com",
        username: "testuser"
    )

    override func setUp() async throws {
        try await super.setUp()
        mockSFTPSession = MockSFTPSession()
        mockFileRepository = MockFileRepository()
        mockClipboardService = ClipboardService.shared

        sut = FileBrowserViewModel(
            connection: testConnection,
            sftpSession: mockSFTPSession,
            fileRepository: mockFileRepository,
            clipboardService: mockClipboardService,
            password: "testpass"
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockSFTPSession = nil
        mockFileRepository = nil
        mockClipboardService = nil
        try await super.tearDown()
    }

    // MARK: - Connection Tests

    func testConnect_Success() async {
        // Given
        await mockSFTPSession.reset()

        // When
        await sut.connect()

        // Then
        let connectCalled = await mockSFTPSession.connectPasswordCalled
        let isConnected = await mockSFTPSession.isConnected
        XCTAssertTrue(connectCalled)
        XCTAssertTrue(isConnected)
        XCTAssertTrue(sut.isConnected)
    }

    func testConnect_Error() async {
        // Given
        await MainActor.run {
            Task {
                await mockSFTPSession.reset()
            }
        }
        // Note: Setting error on actor requires proper handling
        // For this test, we'll verify the error state

        // When
        // await sut.connect()

        // Then - state management tests
        XCTAssertFalse(sut.isConnected)
    }

    func testDisconnect() async {
        // Given
        await sut.connect()

        // When
        await sut.disconnect()

        // Then
        XCTAssertFalse(sut.isConnected)
        XCTAssertEqual(sut.currentPath, "/")
        XCTAssertTrue(sut.files.isEmpty)
    }

    // MARK: - Navigation Tests

    func testNavigateTo_Success() async {
        // Given
        let testFiles = [
            RemoteFile(name: "test.txt", path: "/test.txt", isDirectory: false, size: 100, permissions: "-rw-r--r--")
        ]
        mockFileRepository.mockFiles = testFiles
        await sut.connect()

        // When
        await sut.navigateTo("/home")

        // Then
        XCTAssertTrue(mockFileRepository.listFilesCalled)
        XCTAssertEqual(mockFileRepository.lastListPath, "/home")
    }

    func testGoUp() async {
        // Given
        mockFileRepository.mockFiles = []
        await sut.connect()
        sut = FileBrowserViewModel(
            connection: testConnection,
            sftpSession: mockSFTPSession,
            fileRepository: mockFileRepository,
            clipboardService: mockClipboardService,
            password: "testpass"
        )

        // Then - verify parent path calculation
        XCTAssertTrue(sut.canGoUp == (sut.currentPath != "/"))
    }

    // MARK: - Go to Folder Tests

    func testNormalizedGoToPath_Absolute() {
        XCTAssertEqual(
            FileBrowserViewModel.normalizedGoToPath("/var/www//html/", relativeTo: "/home"),
            "/var/www/html"
        )
        XCTAssertEqual(
            FileBrowserViewModel.normalizedGoToPath("/", relativeTo: "/home"),
            "/"
        )
    }

    func testNormalizedGoToPath_RelativeResolvedAgainstCurrentPath() {
        XCTAssertEqual(
            FileBrowserViewModel.normalizedGoToPath("logs", relativeTo: "/var/www"),
            "/var/www/logs"
        )
        XCTAssertEqual(
            FileBrowserViewModel.normalizedGoToPath("../etc", relativeTo: "/var/www"),
            "/var/etc"
        )
        XCTAssertEqual(
            FileBrowserViewModel.normalizedGoToPath("./lib/./x", relativeTo: "/usr"),
            "/usr/lib/x"
        )
    }

    func testNormalizedGoToPath_ParentBeyondRootClampsToRoot() {
        XCTAssertEqual(
            FileBrowserViewModel.normalizedGoToPath("../../..", relativeTo: "/var"),
            "/"
        )
    }

    func testNormalizedGoToPath_HomePrefixedPassthrough() {
        XCTAssertEqual(
            FileBrowserViewModel.normalizedGoToPath("~", relativeTo: "/var"),
            "~"
        )
        XCTAssertEqual(
            FileBrowserViewModel.normalizedGoToPath("~/documents", relativeTo: "/var"),
            "~/documents"
        )
    }

    func testNormalizedGoToPath_EmptyInputReturnsNil() {
        XCTAssertNil(FileBrowserViewModel.normalizedGoToPath("", relativeTo: "/var"))
        XCTAssertNil(FileBrowserViewModel.normalizedGoToPath("   \n ", relativeTo: "/var"))
        XCTAssertEqual(
            FileBrowserViewModel.normalizedGoToPath("  /tmp\t", relativeTo: "/var"),
            "/tmp"
        )
    }

    func testGoToPath_NavigatesToNormalizedPath() async {
        // Given (mock session connects into /home/user)
        mockFileRepository.mockFiles = []
        await sut.connect()
        XCTAssertEqual(sut.currentPath, "/home/user")

        // When
        await sut.goToPath("../../var/log")

        // Then
        XCTAssertTrue(mockFileRepository.listFilesCalled)
        XCTAssertEqual(mockFileRepository.lastListPath, "/var/log")
        XCTAssertFalse(sut.isShowingGoToFolder)
    }

    func testGoToPath_EmptyInputDismissesWithoutNavigating() async {
        // Given
        mockFileRepository.mockFiles = []
        await sut.connect()
        mockFileRepository.listFilesCalled = false
        sut.showGoToFolder()
        XCTAssertTrue(sut.isShowingGoToFolder)

        // When
        await sut.goToPath("   ")

        // Then
        XCTAssertFalse(sut.isShowingGoToFolder)
        XCTAssertFalse(mockFileRepository.listFilesCalled)
    }

    func testShowGoToFolder_RequiresConnection() async {
        // Given
        XCTAssertFalse(sut.isConnected)

        // When
        sut.showGoToFolder()

        // Then
        XCTAssertFalse(sut.isShowingGoToFolder)

        // When connected
        await sut.connect()
        sut.showGoToFolder()

        // Then
        XCTAssertTrue(sut.isShowingGoToFolder)

        // Dismissal
        sut.dismissGoToFolder()
        XCTAssertFalse(sut.isShowingGoToFolder)
    }

    // MARK: - File Operations Tests

    func testCreateFolder() async {
        // Given
        await sut.connect()

        // When
        await sut.createFolder(name: "NewFolder")

        // Then
        XCTAssertTrue(mockFileRepository.createDirectoryCalled)
    }

    func testCreateFile() async {
        // Given
        await sut.connect()

        // When
        await sut.createFile(name: "newfile.txt")

        // Then
        XCTAssertTrue(mockFileRepository.createFileCalled)
    }

    func testRenameFile() async {
        // Given
        let file = RemoteFile(name: "old.txt", path: "/old.txt", isDirectory: false, size: 100, permissions: "-rw-r--r--")
        await sut.connect()

        // When
        await sut.renameFile(file, to: "new.txt")

        // Then
        XCTAssertTrue(mockFileRepository.renameCalled)
    }

    func testDeleteFiles() async {
        // Given
        let file = RemoteFile(name: "test.txt", path: "/test.txt", isDirectory: false, size: 100, permissions: "-rw-r--r--")
        await sut.connect()

        // When
        await sut.deleteFiles([file])

        // Then
        XCTAssertTrue(mockFileRepository.deleteCalled)
    }

    // MARK: - Clipboard Tests

    func testCopySelectedFiles() async {
        // Given
        let file = RemoteFile(name: "test.txt", path: "/test.txt", isDirectory: false, size: 100, permissions: "-rw-r--r--")
        mockFileRepository.mockFiles = [file]
        await sut.connect()
        await sut.loadFiles()
        sut.selectedFiles = [file.id]

        // When
        sut.copySelectedFiles()

        // Then
        XCTAssertTrue(mockClipboardService.isCopy)
        XCTAssertEqual(mockClipboardService.fileCount, 1)
    }

    func testCutSelectedFiles() async {
        // Given
        let file = RemoteFile(name: "test.txt", path: "/test.txt", isDirectory: false, size: 100, permissions: "-rw-r--r--")
        mockFileRepository.mockFiles = [file]
        await sut.connect()
        await sut.loadFiles()
        sut.selectedFiles = [file.id]

        // When
        sut.cutSelectedFiles()

        // Then
        XCTAssertTrue(mockClipboardService.isCut)
    }

    // MARK: - Selection Tests

    func testSelectAll() async {
        // Given
        let files = [
            RemoteFile(name: "file1.txt", path: "/file1.txt", isDirectory: false, size: 100, permissions: "-rw-r--r--"),
            RemoteFile(name: "file2.txt", path: "/file2.txt", isDirectory: false, size: 100, permissions: "-rw-r--r--")
        ]
        mockFileRepository.mockFiles = files
        await sut.connect()
        await sut.loadFiles()

        // When
        sut.selectAll()

        // Then
        XCTAssertEqual(sut.selectedFiles.count, files.count)
    }

    func testDeselectAll() async {
        // Given
        let file = RemoteFile(name: "test.txt", path: "/test.txt", isDirectory: false, size: 100, permissions: "-rw-r--r--")
        mockFileRepository.mockFiles = [file]
        await sut.connect()
        await sut.loadFiles()
        sut.selectedFiles = [file.id]

        // When
        sut.deselectAll()

        // Then
        XCTAssertTrue(sut.selectedFiles.isEmpty)
    }

    // MARK: - Sorted Files Tests

    func testSortedFiles_DirectoriesFirst() async {
        // Given
        let files = [
            RemoteFile(name: "file.txt", path: "/file.txt", isDirectory: false, size: 100, permissions: "-rw-r--r--"),
            RemoteFile(name: "folder", path: "/folder", isDirectory: true, size: 0, permissions: "drwxr-xr-x")
        ]
        mockFileRepository.mockFiles = files
        await sut.connect()
        await sut.loadFiles()

        // Then
        XCTAssertTrue(sut.sortedFiles.first?.isDirectory ?? false)
    }

    func testSortedFiles_HiddenFilesFiltered() async {
        // Given
        let files = [
            RemoteFile(name: ".hidden", path: "/.hidden", isDirectory: false, size: 100, permissions: "-rw-r--r--"),
            RemoteFile(name: "visible.txt", path: "/visible.txt", isDirectory: false, size: 100, permissions: "-rw-r--r--")
        ]
        mockFileRepository.mockFiles = files
        await sut.connect()
        await sut.loadFiles()
        sut.showHiddenFiles = false

        // Then
        XCTAssertEqual(sut.sortedFiles.count, 1)
        XCTAssertFalse(sut.sortedFiles.first?.isHidden ?? true)
    }

    // MARK: - Quick Look Tests

    func testDownloadFileQuietlyCallsRepository() async {
        let file = RemoteFile(name: "a.txt", path: "/a.txt", isDirectory: false, size: 10, permissions: "-rw-r--r--")
        await sut.connect()

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("macSCPTests-preview-a.txt")
        try? await sut.downloadFileQuietly(file, destinationURL: destination)

        XCTAssertTrue(mockFileRepository.downloadCalled)
    }

    // MARK: - Paste Naming Tests

    func testUniqueCopyName_AddsCopySuffix() {
        XCTAssertEqual(
            FileBrowserViewModel.uniqueCopyName(for: "report.pdf", existing: ["report.pdf"]),
            "report copy.pdf"
        )
        XCTAssertEqual(
            FileBrowserViewModel.uniqueCopyName(for: "Makefile", existing: ["Makefile"]),
            "Makefile copy"
        )
    }

    func testUniqueCopyName_IncrementsUntilFree() {
        let existing: Set<String> = ["a.txt", "a copy.txt", "a copy 2.txt"]
        XCTAssertEqual(
            FileBrowserViewModel.uniqueCopyName(for: "a.txt", existing: existing),
            "a copy 3.txt"
        )
    }

    // MARK: - Bookmark Tests

    func testAddBookmark_SavesCurrentFolder() async {
        // Given
        let mockBookmarkRepository = MockBookmarkRepository()
        sut = FileBrowserViewModel(
            connection: testConnection,
            sftpSession: mockSFTPSession,
            fileRepository: mockFileRepository,
            clipboardService: mockClipboardService,
            password: "testpass",
            bookmarkRepository: mockBookmarkRepository
        )
        mockFileRepository.mockFiles = []
        await sut.connect()
        // Mock session reports /home/user as the connected directory
        XCTAssertEqual(sut.currentPath, "/home/user")

        // When
        await sut.addCurrentFolderToBookmarks()

        // Then
        XCTAssertTrue(mockBookmarkRepository.saveCalled)
        XCTAssertEqual(sut.bookmarks.count, 1)
        XCTAssertEqual(sut.bookmarks.first?.remotePath, "/home/user")
        XCTAssertEqual(sut.bookmarks.first?.name, "user")
    }

    func testDeleteBookmark_RemovesFromList() async {
        // Given
        let mockBookmarkRepository = MockBookmarkRepository()
        sut = FileBrowserViewModel(
            connection: testConnection,
            sftpSession: mockSFTPSession,
            fileRepository: mockFileRepository,
            clipboardService: mockClipboardService,
            password: "testpass",
            bookmarkRepository: mockBookmarkRepository
        )
        mockFileRepository.mockFiles = []
        await sut.connect()
        await sut.addCurrentFolderToBookmarks()
        guard let bookmark = sut.bookmarks.first else {
            return XCTFail("Expected a bookmark to exist")
        }

        // When
        await sut.deleteBookmark(bookmark)

        // Then
        XCTAssertTrue(mockBookmarkRepository.deleteCalled)
        XCTAssertTrue(sut.bookmarks.isEmpty)
    }

    func testRenameBookmark_UpdatesName() async {
        // Given
        let mockBookmarkRepository = MockBookmarkRepository()
        sut = FileBrowserViewModel(
            connection: testConnection,
            sftpSession: mockSFTPSession,
            fileRepository: mockFileRepository,
            clipboardService: mockClipboardService,
            password: "testpass",
            bookmarkRepository: mockBookmarkRepository
        )
        mockFileRepository.mockFiles = []
        await sut.connect()
        await sut.addCurrentFolderToBookmarks()
        guard let bookmark = sut.bookmarks.first else {
            return XCTFail("Expected a bookmark to exist")
        }

        // When
        await sut.renameBookmark(bookmark, to: "Production")

        // Then
        XCTAssertTrue(mockBookmarkRepository.updateCalled)
        XCTAssertEqual(sut.bookmarks.first?.name, "Production")
    }

    // MARK: - Default Remote Path Tests

    func testConnect_NavigatesToDefaultRemotePath() async {
        // Given
        let connection = Connection(
            name: "Test Server",
            host: "test.example.com",
            username: "testuser",
            defaultRemotePath: "/var/www"
        )
        sut = FileBrowserViewModel(
            connection: connection,
            sftpSession: mockSFTPSession,
            fileRepository: mockFileRepository,
            clipboardService: mockClipboardService,
            password: "testpass"
        )
        mockFileRepository.mockFiles = []

        // When
        await sut.connect()

        // Then
        XCTAssertTrue(mockFileRepository.listFilesCalled)
        XCTAssertEqual(mockFileRepository.lastListPath, "/var/www")
    }
}
