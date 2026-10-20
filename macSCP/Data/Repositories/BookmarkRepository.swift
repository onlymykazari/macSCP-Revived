//
//  BookmarkRepository.swift
//  macSCP
//
//  Repository implementation for bookmark operations
//

import Foundation
import SwiftData

final class BookmarkRepository: BookmarkRepositoryProtocol, @unchecked Sendable {
    private let dataStore: DataStore

    init(dataStore: DataStore = .shared) {
        self.dataStore = dataStore
    }

    @MainActor
    func fetchAll() async throws -> [Bookmark] {
        let context = dataStore.modelContext
        let descriptor = FetchDescriptor<BookmarkEntity>(
            sortBy: [
                SortDescriptor(\.displayOrder, order: .forward),
                SortDescriptor(\.name, order: .forward)
            ]
        )

        do {
            let entities = try context.fetch(descriptor)
            return entities.map { BookmarkMapper.toDomain($0) }
        } catch {
            logError("Failed to fetch bookmarks: \(error)", category: .database)
            throw AppError.fetchFailed("bookmarks")
        }
    }

    @MainActor
    func fetchAll(connectionId: UUID) async throws -> [Bookmark] {
        let context = dataStore.modelContext
        let descriptor = FetchDescriptor<BookmarkEntity>(
            predicate: #Predicate<BookmarkEntity> { $0.connectionId == connectionId },
            sortBy: [
                SortDescriptor(\.displayOrder, order: .forward),
                SortDescriptor(\.name, order: .forward)
            ]
        )

        do {
            let entities = try context.fetch(descriptor)
            return entities.map { BookmarkMapper.toDomain($0) }
        } catch {
            logError("Failed to fetch bookmarks for connection: \(error)", category: .database)
            throw AppError.fetchFailed("bookmarks")
        }
    }

    @MainActor
    func save(_ bookmark: Bookmark) async throws {
        let context = dataStore.modelContext
        context.insert(BookmarkMapper.toEntity(bookmark))

        do {
            try context.save()
            logInfo("Saved bookmark: \(bookmark.name)", category: .database)
        } catch {
            logError("Failed to save bookmark: \(error)", category: .database)
            throw AppError.saveFailed("bookmark")
        }
    }

    @MainActor
    func update(_ bookmark: Bookmark) async throws {
        let context = dataStore.modelContext
        let descriptor = FetchDescriptor<BookmarkEntity>(
            predicate: #Predicate<BookmarkEntity> { $0.id == bookmark.id }
        )

        do {
            guard let entity = try context.fetch(descriptor).first else {
                throw AppError.entityNotFound
            }

            BookmarkMapper.update(entity, from: bookmark)
            try context.save()
            logInfo("Updated bookmark: \(bookmark.name)", category: .database)
        } catch let error as AppError {
            throw error
        } catch {
            logError("Failed to update bookmark: \(error)", category: .database)
            throw AppError.saveFailed("bookmark")
        }
    }

    @MainActor
    func delete(id: UUID) async throws {
        let context = dataStore.modelContext
        let descriptor = FetchDescriptor<BookmarkEntity>(
            predicate: #Predicate<BookmarkEntity> { $0.id == id }
        )

        do {
            guard let entity = try context.fetch(descriptor).first else {
                throw AppError.entityNotFound
            }

            context.delete(entity)
            try context.save()
            logInfo("Deleted bookmark: \(id)", category: .database)
        } catch let error as AppError {
            throw error
        } catch {
            logError("Failed to delete bookmark: \(error)", category: .database)
            throw AppError.deleteFailed("bookmark")
        }
    }

    @MainActor
    func count() async throws -> Int {
        let context = dataStore.modelContext
        let descriptor = FetchDescriptor<BookmarkEntity>()

        do {
            return try context.fetchCount(descriptor)
        } catch {
            logError("Failed to count bookmarks: \(error)", category: .database)
            throw AppError.fetchFailed("bookmarks")
        }
    }
}
