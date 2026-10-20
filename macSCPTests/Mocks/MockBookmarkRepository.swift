//
//  MockBookmarkRepository.swift
//  macSCPTests
//
//  In-memory mock of BookmarkRepositoryProtocol
//

import Foundation
@testable import macSCP

final class MockBookmarkRepository: BookmarkRepositoryProtocol, @unchecked Sendable {
    var bookmarks: [Bookmark] = []
    private(set) var saveCalled = false
    private(set) var updateCalled = false
    private(set) var deleteCalled = false

    func fetchAll() async throws -> [Bookmark] {
        bookmarks
    }

    func fetchAll(connectionId: UUID) async throws -> [Bookmark] {
        bookmarks.filter { $0.connectionId == connectionId }
    }

    func save(_ bookmark: Bookmark) async throws {
        saveCalled = true
        bookmarks.append(bookmark)
    }

    func update(_ bookmark: Bookmark) async throws {
        updateCalled = true
        if let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[index] = bookmark
        }
    }

    func delete(id: UUID) async throws {
        deleteCalled = true
        bookmarks.removeAll { $0.id == id }
    }

    func count() async throws -> Int {
        bookmarks.count
    }
}
