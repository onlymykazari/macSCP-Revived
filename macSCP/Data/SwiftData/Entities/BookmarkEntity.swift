//
//  BookmarkEntity.swift
//  macSCP
//
//  SwiftData entity for remote path bookmarks
//

import Foundation
import SwiftData

@Model
final class BookmarkEntity {
    @Attribute(.unique) var id: UUID
    var connectionId: UUID
    var name: String
    var remotePath: String
    var displayOrder: Int = 0
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        connectionId: UUID,
        name: String,
        remotePath: String,
        displayOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.connectionId = connectionId
        self.name = name
        self.remotePath = remotePath
        self.displayOrder = displayOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
