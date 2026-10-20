//
//  SecurityScopedAccess.swift
//  macSCP
//
//  Keeps security-scoped bookmarks for files the user granted access to —
//  private keys picked in an open panel, or the ~/.ssh folder for hosts
//  imported from ssh config — so the sandboxed app can still read them on
//  later launches. Lookups match an exact path or the longest bookmarked
//  parent directory.
//

import Foundation

extension FileManager {
    /// The user's real home directory. Inside the App Sandbox,
    /// `NSHomeDirectory()`/`homeDirectoryForCurrentUser` point at the app
    /// container, which is wrong for anything that must match the user's
    /// own files (ssh config, ~/.ssh keys).
    static var realHomeDirectory: String {
        if let passwd = getpwuid(getuid()), let dir = passwd.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    /// Expands a leading `~` against the real home directory.
    static func expandingRealTilde(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        if path == "~" { return realHomeDirectory }
        if path.hasPrefix("~/") { return realHomeDirectory + path.dropFirst(1) }
        return path // "~user/…" — leave untouched
    }

    /// Rewrites paths that were mistakenly resolved against the sandbox
    /// container home (e.g. by an earlier version of the ssh config import)
    /// back onto the real home. No-op outside the sandbox.
    static func mappingContainerHomeToReal(_ path: String) -> String {
        let containerHome = NSHomeDirectory()
        let realHome = realHomeDirectory
        guard containerHome != realHome, path.hasPrefix(containerHome + "/") else { return path }
        return realHome + path.dropFirst(containerHome.count)
    }
}

final class SecurityScopedAccess: @unchecked Sendable {
    static let shared = SecurityScopedAccess()

    private let defaultsKey = "securityScopedBookmarks"
    private let lock = NSLock()

    private init() {}

    private var bookmarks: [String: Data] {
        get { UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// Remembers access to a file or directory the user just picked.
    func remember(_ url: URL) {
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            logWarning("Could not create security-scoped bookmark for \(url.path)", category: .app)
            return
        }
        lock.withLock {
            var all = bookmarks
            all[url.standardizedFileURL.path] = data
            bookmarks = all
        }
        logInfo("Remembered security-scoped access to \(url.path)", category: .app)
    }

    /// True when `path` is readable directly or through a remembered bookmark.
    /// Uses a real open() rather than `isReadableFile`, which the sandbox can
    /// answer optimistically for paths it will refuse to open.
    func canRead(_ path: String) -> Bool {
        if let handle = FileHandle(forReadingAtPath: path) {
            try? handle.close()
            return true
        }
        guard let url = resolvedURL(covering: path) else { return false }
        let granted = url.startAccessingSecurityScopedResource()
        defer {
            if granted { url.stopAccessingSecurityScopedResource() }
        }
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        try? handle.close()
        return true
    }

    /// Runs `body` while access to `path` is active. Without a matching
    /// bookmark it simply runs `body` (the file may be readable anyway).
    func withAccess<T>(to path: String, _ body: () throws -> T) throws -> T {
        guard let url = resolvedURL(covering: path) else { return try body() }
        let granted = url.startAccessingSecurityScopedResource()
        defer {
            if granted { url.stopAccessingSecurityScopedResource() }
        }
        return try body()
    }

    private func resolvedURL(covering path: String) -> URL? {
        let all = lock.withLock { bookmarks }
        let target = URL(fileURLWithPath: path).standardizedFileURL.path

        let matches = all.keys.filter { key in
            target == key || target.hasPrefix(key.hasSuffix("/") ? key : key + "/")
        }
        guard let best = matches.max(by: { $0.count < $1.count }),
              let data = all[best] else { return nil }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        if isStale {
            remember(url)
        }
        return url
    }
}
