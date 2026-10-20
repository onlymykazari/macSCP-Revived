//
//  QuickLookSupport.swift
//  macSCP
//
//  Quick Look (Space) preview support: remote files are downloaded to a
//  temporary directory and previewed with the system QLPreviewPanel.
//

import AppKit
import Quartz

/// A local file wrapped for Quick Look display with the remote file's name.
final class QuickLookPreviewItem: NSObject, QLPreviewItem {
    let fileURL: URL
    let title: String

    init(url: URL, title: String) {
        self.fileURL = url
        self.title = title
        super.init()
    }

    var previewItemURL: URL? { fileURL }
    var previewItemTitle: String? { title }
}

enum QuickLookConstants {
    /// Local directory that holds files staged for preview (same file name is
    /// overwritten on repeated previews; the OS clears temp on reboot)
    static var stagingDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("macSCPQuickLook", isDirectory: true)
    }

    /// Files above this size are not staged for preview (would block the
    /// Space key for too long).
    static let maxPreviewBytes: Int64 = 100 * 1024 * 1024
}
