//
//  ConnectionListViewModelTests.swift
//  macSCPTests
//
//  Unit tests for ConnectionListViewModel
//

import XCTest
@testable import macSCP

@MainActor
final class ConnectionListViewModelTests: XCTestCase {
    var sut: ConnectionListViewModel!
    var mockConnectionRepository: MockConnectionRepository!
    var mockFolderRepository: MockFolderRepository!
    var mockBookmarkRepository: MockBookmarkRepository!
    var mockKeychainService: MockKeychainService!
    var mockWindowManager: WindowManager!

    override func setUp() async throws {
        try await super.setUp()
        mockConnectionRepository = MockConnectionRepository()
        mockFolderRepository = MockFolderRepository()
        mockBookmarkRepository = MockBookmarkRepository()
        mockKeychainService = MockKeychainService()
        mockWindowManager = WindowManager.shared

        sut = ConnectionListViewModel(
            connectionRepository: mockConnectionRepository,
            folderRepository: mockFolderRepository,
            bookmarkRepository: mockBookmarkRepository,
            keychainService: mockKeychainService,
            windowManager: mockWindowManager
        )
    }

    override func tearDown() async throws {
        // External launch tests toggle this; restore the default (enabled).
        UserDefaults.standard.removeObject(forKey: ExternalLaunchRequest.enabledDefaultsKey)
        sut = nil
        mockConnectionRepository = nil
        mockFolderRepository = nil
        mockBookmarkRepository = nil
        mockKeychainService = nil
        mockWindowManager = nil
        try await super.tearDown()
    }

    /// Polls until the condition holds or the timeout elapses — external
    /// launches run in unstructured Tasks internally.
    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @autoclosure () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - Load Data Tests

    func testLoadData_Success() async {
        // Given
        let connection = Connection(name: "Test", host: "test.com", username: "user")
        let folder = Folder(name: "Test Folder")
        mockConnectionRepository.mockConnections = [connection]
        mockFolderRepository.mockFolders = [folder]

        // When
        await sut.loadData()

        // Then
        XCTAssertEqual(sut.connections.count, 1)
        XCTAssertEqual(sut.folders.count, 1)
        XCTAssertTrue(mockConnectionRepository.fetchAllCalled)
        XCTAssertTrue(mockFolderRepository.fetchAllCalled)
        XCTAssertTrue(sut.state.isSuccess)
    }

    func testLoadData_Error() async {
        // Given
        mockConnectionRepository.mockError = AppError.fetchFailed("test")

        // When
        await sut.loadData()

        // Then
        XCTAssertTrue(sut.state.isError)
    }

    // MARK: - Connection Tests

    func testSaveConnection_Success() async {
        // Given
        let connection = Connection(name: "Test", host: "test.com", username: "user", savePassword: true)

        // When
        await sut.saveConnection(connection, password: "secret")

        // Then
        XCTAssertTrue(mockConnectionRepository.saveCalled)
        XCTAssertTrue(mockKeychainService.savePasswordCalled)
        XCTAssertEqual(mockKeychainService.lastSavedPassword, "secret")
    }

    func testDeleteConnection_Success() async {
        // Given
        let connection = Connection(name: "Test", host: "test.com", username: "user")
        mockConnectionRepository.mockConnections = [connection]

        // When
        await sut.deleteConnection(connection)

        // Then
        XCTAssertTrue(mockConnectionRepository.deleteCalled)
        XCTAssertEqual(mockConnectionRepository.lastDeletedId, connection.id)
    }

    // MARK: - Folder Tests

    func testCreateFolder_Success() async {
        // Given
        let folderName = "New Folder"

        // When
        await sut.createFolder(name: folderName)

        // Then
        XCTAssertTrue(mockFolderRepository.saveCalled)
        XCTAssertEqual(mockFolderRepository.lastSavedFolder?.name, folderName)
    }

    func testDeleteFolder_Success() async {
        // Given
        let folder = Folder(name: "Test Folder")
        mockFolderRepository.mockFolders = [folder]
        sut.selectedSidebarItem = .folder(folder.id)

        // When
        await sut.deleteFolder(folder)

        // Then
        XCTAssertTrue(mockFolderRepository.deleteCalled)
        XCTAssertEqual(mockFolderRepository.lastDeletedId, folder.id)
        XCTAssertEqual(sut.selectedSidebarItem, .allConnections)
    }

    // MARK: - Filter Tests

    func testFilteredConnections_SearchText() async {
        // Given
        let connection1 = Connection(name: "Production", host: "prod.com", username: "admin")
        let connection2 = Connection(name: "Development", host: "dev.com", username: "dev")
        mockConnectionRepository.mockConnections = [connection1, connection2]
        await sut.loadData()

        // When
        sut.searchText = "prod"

        // Then
        XCTAssertEqual(sut.filteredConnections.count, 1)
        XCTAssertEqual(sut.filteredConnections.first?.name, "Production")
    }

    func testFilteredConnections_ByFolder() async {
        // Given
        let folder = Folder(name: "Test Folder")
        let connection1 = Connection(name: "In Folder", host: "test.com", username: "user", folderId: folder.id)
        let connection2 = Connection(name: "No Folder", host: "test.com", username: "user")
        mockConnectionRepository.mockConnections = [connection1, connection2]
        mockFolderRepository.mockFolders = [folder]
        await sut.loadData()

        // When
        sut.selectedSidebarItem = .folder(folder.id)

        // Then
        XCTAssertEqual(sut.filteredConnections.count, 1)
        XCTAssertEqual(sut.filteredConnections.first?.name, "In Folder")
    }

    // MARK: - Connection Count Tests

    func testConnectionCount_ForFolder() async {
        // Given
        let folder = Folder(name: "Test Folder")
        let connection1 = Connection(name: "Test 1", host: "test.com", username: "user", folderId: folder.id)
        let connection2 = Connection(name: "Test 2", host: "test.com", username: "user", folderId: folder.id)
        let connection3 = Connection(name: "Test 3", host: "test.com", username: "user")
        mockConnectionRepository.mockConnections = [connection1, connection2, connection3]
        mockFolderRepository.mockFolders = [folder]
        await sut.loadData()

        // Then
        XCTAssertEqual(sut.connectionCount(for: folder.id), 2)
        XCTAssertEqual(sut.totalConnectionCount, 3)
    }

    // MARK: - External Launch Tests

    func testExternalLaunch_ConnectionIdOpensBrowserWithDeterministicWindowId() async {
        // Given
        let connection = Connection(name: "Test", host: "test.com", username: "user")
        mockConnectionRepository.mockConnections = [connection]
        mockKeychainService.mockPasswords[connection.id] = "secret"
        let request = ExternalLaunchRequest(
            target: .connectionId(connection.id),
            view: .files,
            path: nil,
            forceNew: false,
            sourceURL: "macscp://open?connection=\(connection.id.uuidString)"
        )

        // When
        sut.handleExternalLaunch(.request(request))
        await waitUntil(sut.pendingWindowId != nil)

        // Then
        XCTAssertEqual(sut.pendingWindowId, "ext-browser-\(connection.id.uuidString)")
        let data = mockWindowManager.getFileBrowserData(for: sut.pendingWindowId!)
        XCTAssertEqual(data?.connectionId, connection.id)
        XCTAssertNil(data?.defaultRemotePath)
    }

    func testExternalLaunch_PathOverridesDefaultRemotePath() async {
        // Given
        let connection = Connection(
            name: "Test", host: "test.com", username: "user", defaultRemotePath: "/srv/default"
        )
        mockConnectionRepository.mockConnections = [connection]
        mockKeychainService.mockPasswords[connection.id] = "secret"
        let request = ExternalLaunchRequest(
            target: .connectionName("test"),
            view: .files,
            path: "/srv/override",
            forceNew: false,
            sourceURL: "macscp://open?connection=test&path=/srv/override"
        )

        // When
        sut.handleExternalLaunch(.request(request))
        await waitUntil(sut.pendingWindowId != nil)

        // Then
        let data = mockWindowManager.getFileBrowserData(for: sut.pendingWindowId!)
        XCTAssertEqual(data?.defaultRemotePath, "/srv/override")
    }

    func testExternalLaunch_ForceNewUsesRandomWindowId() async {
        // Given
        let connection = Connection(name: "Test", host: "test.com", username: "user")
        mockConnectionRepository.mockConnections = [connection]
        mockKeychainService.mockPasswords[connection.id] = "secret"
        let request = ExternalLaunchRequest(
            target: .connectionId(connection.id),
            view: .files,
            path: nil,
            forceNew: true,
            sourceURL: "macscp://open?connection=\(connection.id.uuidString)&new=1"
        )

        // When
        sut.handleExternalLaunch(.request(request))
        await waitUntil(sut.pendingWindowId != nil)

        // Then
        XCTAssertNotEqual(sut.pendingWindowId, "ext-browser-\(connection.id.uuidString)")
    }

    func testExternalLaunch_TerminalOpensTerminalWithInitialPath() async {
        // Given
        let connection = Connection(name: "Test", host: "test.com", username: "user")
        mockConnectionRepository.mockConnections = [connection]
        mockKeychainService.mockPasswords[connection.id] = "secret"
        let request = ExternalLaunchRequest(
            target: .connectionName("test"),
            view: .terminal,
            path: "/var/log",
            forceNew: false,
            sourceURL: "macscp://open?connection=test&view=terminal&path=/var/log"
        )

        // When
        sut.handleExternalLaunch(.request(request))
        await waitUntil(sut.pendingTerminalWindowId != nil)

        // Then
        XCTAssertEqual(sut.pendingTerminalWindowId, "ext-terminal-\(connection.id.uuidString)")
        let data = mockWindowManager.getTerminalData(for: sut.pendingTerminalWindowId!)
        XCTAssertEqual(data?.initialPath, "/var/log")
    }

    func testExternalLaunch_BookmarkResolvesConnectionAndPath() async {
        // Given
        let connection = Connection(name: "Test", host: "test.com", username: "user")
        mockConnectionRepository.mockConnections = [connection]
        mockKeychainService.mockPasswords[connection.id] = "secret"
        mockBookmarkRepository.bookmarks = [
            Bookmark(connectionId: connection.id, name: "logs", remotePath: "/var/log")
        ]
        let request = ExternalLaunchRequest(
            target: .bookmarkName("LOGS"),
            view: .files,
            path: nil,
            forceNew: false,
            sourceURL: "macscp://open?bookmark=LOGS"
        )

        // When
        sut.handleExternalLaunch(.request(request))
        await waitUntil(sut.pendingWindowId != nil)

        // Then (case-insensitive name match, path falls back to the bookmark)
        let data = mockWindowManager.getFileBrowserData(for: sut.pendingWindowId!)
        XCTAssertEqual(data?.connectionId, connection.id)
        XCTAssertEqual(data?.defaultRemotePath, "/var/log")
    }

    func testExternalLaunch_AmbiguousConnectionNameShowsChoices() async {
        // Given
        let connection1 = Connection(name: "Test", host: "a.com", username: "user")
        let connection2 = Connection(name: "test", host: "b.com", username: "user")
        mockConnectionRepository.mockConnections = [connection1, connection2]
        let request = ExternalLaunchRequest(
            target: .connectionName("Test"),
            view: .files,
            path: nil,
            forceNew: false,
            sourceURL: "macscp://open?connection=Test"
        )

        // When
        sut.handleExternalLaunch(.request(request))
        await waitUntil(sut.externalLaunchChoicesSheet != nil)

        // Then
        XCTAssertEqual(sut.externalLaunchChoicesSheet?.choices.count, 2)
        XCTAssertNil(sut.pendingWindowId)
        XCTAssertNil(sut.pendingTerminalWindowId)

        // Picking one resumes the launch with the stored context.
        mockKeychainService.mockPasswords[connection2.id] = "secret"
        sut.resolveExternalLaunchChoice(ExternalLaunchChoice(connection: connection2, path: nil))
        await waitUntil(sut.pendingWindowId != nil)
        XCTAssertEqual(sut.pendingWindowId, "ext-browser-\(connection2.id.uuidString)")
    }

    func testExternalLaunch_UnknownConnectionSetsError() async {
        // Given
        let request = ExternalLaunchRequest(
            target: .connectionName("Ghost"),
            view: .files,
            path: nil,
            forceNew: false,
            sourceURL: "macscp://open?connection=Ghost"
        )

        // When
        sut.handleExternalLaunch(.request(request))
        await waitUntil(sut.error != nil)

        // Then
        XCTAssertTrue(sut.error is AppError)
        XCTAssertNil(sut.pendingWindowId)
    }

    func testExternalLaunch_TerminalForS3SetsError() async {
        // Given
        let connection = Connection(
            name: "Bucket", host: "s3.amazonaws.com", username: "key",
            connectionType: .s3, s3Bucket: "bucket"
        )
        mockConnectionRepository.mockConnections = [connection]
        let request = ExternalLaunchRequest(
            target: .connectionName("Bucket"),
            view: .terminal,
            path: nil,
            forceNew: false,
            sourceURL: "macscp://open?connection=Bucket&view=terminal"
        )

        // When
        sut.handleExternalLaunch(.request(request))
        await waitUntil(sut.error != nil)

        // Then
        XCTAssertNil(sut.pendingTerminalWindowId)
        XCTAssertNil(sut.pendingWindowId)
    }

    func testExternalLaunch_RejectedOutcomeSetsError() async {
        // When
        sut.handleExternalLaunch(.rejected(message: "Nope", url: "macscp://open"))

        // Then
        XCTAssertNotNil(sut.error)
    }

    func testExternalLaunch_DisabledInSettingsSetsError() async {
        // Given
        UserDefaults.standard.set(false, forKey: ExternalLaunchRequest.enabledDefaultsKey)
        let connection = Connection(name: "Test", host: "test.com", username: "user")
        mockConnectionRepository.mockConnections = [connection]
        let request = ExternalLaunchRequest(
            target: .connectionId(connection.id),
            view: .files,
            path: nil,
            forceNew: false,
            sourceURL: "macscp://open?connection=\(connection.id.uuidString)"
        )

        // When
        sut.handleExternalLaunch(.request(request))
        await waitUntil(sut.error != nil)

        // Then
        XCTAssertNil(sut.pendingWindowId)
    }
}
