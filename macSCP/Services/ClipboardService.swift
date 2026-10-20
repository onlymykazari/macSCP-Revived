//
//  ClipboardService.swift
//  macSCP
//
//  Service for managing remote file clipboard operations
//

import Foundation
import AppKit

@MainActor
@Observable
final class ClipboardService {
    static let shared = ClipboardService()

    private(set) var state = ClipboardState()

    /// Number of files also written to the system pasteboard by the last
    /// Copy (0 = in-app only, e.g. after Cut or when copying directories)
    private(set) var systemPasteboardCount = 0

    /// System pasteboard change count observed when the in-app clipboard was
    /// last set. If the pasteboard changes afterwards (the user copied
    /// something in Finder), the in-app clipboard is superseded and Paste
    /// should use the system pasteboard instead — "last copy wins".
    private(set) var pasteboardChangeCount = 0

    private init() {}

    // MARK: - Public Methods

    /// Copies files to the clipboard
    func copy(files: [RemoteFile], from sourcePath: String, connectionId: UUID) {
        let items = files.map { file in
            ClipboardItem(
                file: file,
                operation: .copy,
                sourcePath: sourcePath,
                connectionId: connectionId
            )
        }

        state = ClipboardState(items: items, operation: .copy)
        systemPasteboardCount = 0
        pasteboardChangeCount = NSPasteboard.general.changeCount
        logDebug("Copied \(files.count) items to clipboard", category: .app)
    }

    /// Records that the last Copy also wrote to the system pasteboard (shown
    /// in the status bar so the dual write is visible). Re-syncs the change
    /// count so our own write doesn't count as a foreign change.
    func noteSystemCopy(count: Int) {
        systemPasteboardCount = count
        pasteboardChangeCount = NSPasteboard.general.changeCount
    }

    /// Cuts files to the clipboard
    func cut(files: [RemoteFile], from sourcePath: String, connectionId: UUID) {
        let items = files.map { file in
            ClipboardItem(
                file: file,
                operation: .cut,
                sourcePath: sourcePath,
                connectionId: connectionId
            )
        }

        state = ClipboardState(items: items, operation: .cut)
        systemPasteboardCount = 0
        pasteboardChangeCount = NSPasteboard.general.changeCount
        logDebug("Cut \(files.count) items to clipboard", category: .app)
    }

    /// Clears the clipboard
    func clear() {
        state.clear()
        systemPasteboardCount = 0
        logDebug("Clipboard cleared", category: .app)
    }

    // MARK: - Computed Properties

    var isEmpty: Bool {
        state.isEmpty
    }

    /// True when something was copied elsewhere (e.g. Finder) after the
    /// in-app copy, making the in-app clipboard stale.
    var isSuperseded: Bool {
        !state.isEmpty && NSPasteboard.general.changeCount != pasteboardChangeCount
    }

    var isCopy: Bool {
        state.isCopy
    }

    var isCut: Bool {
        state.isCut
    }

    var items: [ClipboardItem] {
        state.items
    }

    var fileCount: Int {
        state.fileCount
    }

    var displayText: String {
        let base = state.displayText
        if systemPasteboardCount > 0 {
            return base + " — paste in Finder to download"
        }
        return base
    }

    var connectionId: UUID? {
        state.connectionId
    }

    /// Returns true if the clipboard can paste to the given connection
    /// (non-empty, same connection, and not superseded by a later copy
    /// outside the app)
    func canPaste(to connectionId: UUID) -> Bool {
        guard !isEmpty, !isSuperseded else { return false }
        return state.connectionId == connectionId
    }
}
