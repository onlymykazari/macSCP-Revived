//
//  BookmarkRepositoryProtocol.swift
//  macSCP
//
//  Protocol for bookmark data operations
//

import Foundation

protocol BookmarkRepositoryProtocol: Sendable {
    /// Fetches all bookmarks
    func fetchAll() async throws -> [Bookmark]

    /// Fetches all bookmarks belonging to a connection, ordered for display
    func fetchAll(connectionId: UUID) async throws -> [Bookmark]

    /// Saves a new bookmark
    func save(_ bookmark: Bookmark) async throws

    /// Updates an existing bookmark
    func update(_ bookmark: Bookmark) async throws

    /// Deletes a bookmark by ID
    func delete(id: UUID) async throws

    /// Returns the count of all bookmarks
    func count() async throws -> Int
}
