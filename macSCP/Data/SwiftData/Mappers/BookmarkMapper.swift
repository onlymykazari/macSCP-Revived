//
//  BookmarkMapper.swift
//  macSCP
//
//  Maps between BookmarkEntity and Bookmark domain model
//

import Foundation

enum BookmarkMapper {
    /// Converts a BookmarkEntity to a Bookmark domain model
    static func toDomain(_ entity: BookmarkEntity) -> Bookmark {
        Bookmark(
            id: entity.id,
            connectionId: entity.connectionId,
            name: entity.name,
            remotePath: entity.remotePath,
            displayOrder: entity.displayOrder,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    /// Updates a BookmarkEntity from a Bookmark domain model
    static func update(_ entity: BookmarkEntity, from domain: Bookmark) {
        entity.connectionId = domain.connectionId
        entity.name = domain.name
        entity.remotePath = domain.remotePath
        entity.displayOrder = domain.displayOrder
        entity.updatedAt = Date()
    }

    /// Creates a new BookmarkEntity from a Bookmark domain model
    static func toEntity(_ domain: Bookmark) -> BookmarkEntity {
        BookmarkEntity(
            id: domain.id,
            connectionId: domain.connectionId,
            name: domain.name,
            remotePath: domain.remotePath,
            displayOrder: domain.displayOrder,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt
        )
    }
}
