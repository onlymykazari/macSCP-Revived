//
//  SSHConfigParser.swift
//  macSCP
//
//  Minimal parser for OpenSSH client config files (~/.ssh/config), covering
//  the directives that map onto macSCP connections: Host, HostName, User,
//  Port, IdentityFile. Wildcard patterns, Include and Proxy* directives are
//  deliberately skipped rather than imported.
//

import Foundation

/// One importable host entry extracted from an ssh config.
struct ParsedSSHHost: Identifiable, Equatable {
    let id: UUID
    /// The `Host` alias (used as the connection name)
    var name: String
    /// The `HostName`, or the alias itself when no HostName is given
    /// (OpenSSH semantics)
    var host: String
    /// The `User`, or nil when unset (OpenSSH falls back to the local user)
    var user: String?
    var port: Int
    /// First `IdentityFile` with `~` expanded, or nil for password auth
    var identityFile: String?

    var authMethod: AuthMethod {
        identityFile == nil ? .password : .privateKey
    }

    /// Username to prefill: the config's User, else the local login name
    var suggestedUsername: String {
        user ?? NSUserName()
    }

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        user: String? = nil,
        port: Int = 22,
        identityFile: String? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.user = user
        self.port = port
        self.identityFile = identityFile
    }
}

enum SSHConfigParser {
    /// Parses config text into importable hosts. When the same alias appears
    /// in multiple `Host` blocks, the first occurrence wins (OpenSSH's
    /// first-value-wins semantics).
    static func parse(_ text: String) -> [ParsedSSHHost] {
        var hosts: [ParsedSSHHost] = []
        var pendingAliases: [String] = []
        var hostName: String?
        var user: String?
        var port = 22
        var identityFile: String?

        func flush() {
            for alias in pendingAliases where !isWildcard(alias) {
                guard !hosts.contains(where: { $0.name == alias }) else { continue }
                hosts.append(ParsedSSHHost(
                    name: alias,
                    host: hostName ?? alias,
                    user: user,
                    port: port,
                    identityFile: identityFile
                ))
            }
            pendingAliases = []
            hostName = nil
            user = nil
            port = 22
            identityFile = nil
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let tokens = self.tokens(of: String(rawLine))
            guard !tokens.isEmpty else { continue }

            switch tokens[0].lowercased() {
            case "host":
                flush()
                pendingAliases = Array(tokens.dropFirst())
            case "hostname":
                hostName = tokens.dropFirst().first
            case "user":
                user = tokens.dropFirst().first
            case "port":
                port = Int(tokens.dropFirst().first ?? "") ?? 22
            case "identityfile":
                if identityFile == nil, let path = tokens.dropFirst().first {
                    // Must expand ~ against the real home: inside the sandbox
                    // NSString.expandingTildeInPath yields the app container
                    identityFile = FileManager.expandingRealTilde(stripQuotes(path))
                }
            default:
                break // MatchedHost, Include, Proxy*, Compression, … — ignored
            }
        }
        flush()

        return hosts
    }

    /// Splits a config line into tokens. Whitespace separates tokens except
    /// inside double quotes (quoted paths like `IdentityFile "~/my key"`
    /// come out as one token, quotes stripped); honors the `Key=Value` form
    /// and truncates at a `#` comment token.
    static func tokens(of line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return [] }

        // `Key=Value` with no whitespace before the '='
        if let eq = trimmed.firstIndex(of: "="),
           !trimmed[trimmed.startIndex..<eq].contains(where: \.isWhitespace) {
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? [key] : [key, String(stripQuotes(value))]
        }

        var parts: [String] = []
        var current = ""
        var inQuotes = false
        var hadQuotes = false

        for ch in trimmed {
            if ch == "\"" {
                inQuotes.toggle()
                hadQuotes = true
            } else if ch.isWhitespace, !inQuotes {
                if !current.isEmpty || hadQuotes {
                    parts.append(current)
                    current = ""
                    hadQuotes = false
                }
            } else if ch == "#", !inQuotes, current.isEmpty, !hadQuotes {
                break // start of a trailing comment
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty || hadQuotes {
            parts.append(current)
        }
        return parts
    }

    private static func isWildcard(_ pattern: String) -> Bool {
        pattern.contains("*") || pattern.contains("?")
    }

    private static func stripQuotes(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }
}
