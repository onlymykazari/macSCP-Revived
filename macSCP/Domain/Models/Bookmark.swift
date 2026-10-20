//
//  Bookmark.swift
//  macSCP
//
//  Domain model for remote path bookmarks (favorites) on a connection
//

import Foundation

struct Bookmark: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var connectionId: UUID
    var name: String
    var remotePath: String
    var displayOrder: Int
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

    func withUpdatedTimestamp() -> Bookmark {
        var copy = self
        copy.updatedAt = Date()
        return copy
    }
}
