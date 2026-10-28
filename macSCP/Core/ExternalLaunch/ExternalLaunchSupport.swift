//
//  ExternalLaunchSupport.swift
//  macSCP
//
//  Helpers shared by the external-launch feature: shell quoting for terminal
//  start directories and URL construction for the Settings examples.
//

import Foundation

enum ExternalLaunchSupport {
    /// Builds a `cd` command to write into a freshly established PTY input
    /// buffer. The shell reads it as its first input line, so the working
    /// directory is set without timing races and with the same semantics as
    /// the user typing it.
    ///
    /// A leading `~` is handed to the shell as `${HOME}` (single quotes would
    /// suppress tilde expansion); the rest of the path stays single-quoted.
    /// Returns nil when the path is empty or contains control characters
    /// (C0/C1 or DEL) — such paths are rejected instead of quoted because they
    /// have no business in a command stream.
    static func terminalCDCommand(path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for scalar in trimmed.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F || (0x80...0x9F).contains(scalar.value) {
                return nil
            }
        }

        if trimmed == "~" {
            return "cd -- \"${HOME}\"\n"
        }
        if trimmed.hasPrefix("~/") {
            let remainder = String(trimmed.dropFirst(1)) // keeps the leading "/"
            return "cd -- \"${HOME}\"\(singleQuoted(remainder))\n"
        }

        return "cd -- \(singleQuoted(trimmed))\n"
    }

    private static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Builds a launch URL for the Settings pane's copyable examples.
    /// Exactly one of `connection` / `bookmark` must be non-nil.
    static func makeURL(
        connection: String? = nil,
        bookmark: String? = nil,
        view: ExternalLaunchView = .files,
        path: String? = nil,
        forceNew: Bool = false
    ) -> URL? {
        var components = URLComponents()
        components.scheme = ExternalLaunchRequest.scheme
        components.host = ExternalLaunchRequest.host

        var items: [URLQueryItem] = []
        if let connection { items.append(URLQueryItem(name: "connection", value: connection)) }
        if let bookmark { items.append(URLQueryItem(name: "bookmark", value: bookmark)) }
        if view != .files { items.append(URLQueryItem(name: "view", value: view.rawValue)) }
        if let path, !path.isEmpty { items.append(URLQueryItem(name: "path", value: path)) }
        if forceNew { items.append(URLQueryItem(name: "new", value: "1")) }
        components.queryItems = items.isEmpty ? nil : items

        return components.url
    }
}
