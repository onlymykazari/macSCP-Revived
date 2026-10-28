//
//  ExternalLaunchRequest.swift
//  macSCP
//
//  Parses `macscp://` URLs used by other apps on this machine to launch
//  macSCP with a specific connection/bookmark, path, and view.
//
//  Security rules:
//  - Credentials are never accepted in URLs. The userinfo component is
//    deliberately ignored (it exists in the parsed URL only to be redacted
//    from logs); lookups resolve to saved connections and passwords come
//    from the Keychain inside the app.
//  - Only whitelisted query parameters are interpreted; unknown ones are
//    logged and ignored.
//

import Foundation

enum ExternalLaunchView: String, Sendable {
    case files
    case terminal
}

enum ExternalLaunchTarget: Equatable, Sendable {
    /// `connection=<UUID>` — exact match on a saved connection id.
    case connectionId(UUID)
    /// `connection=<name>` — case-insensitive match on a saved connection name.
    case connectionName(String)
    /// `bookmark=<name>` — case-insensitive match on a saved bookmark name;
    /// the bookmark's remote path becomes the default initial path.
    case bookmarkName(String)
}

struct ExternalLaunchRequest: Equatable, Sendable {
    let target: ExternalLaunchTarget
    let view: ExternalLaunchView
    let path: String?
    let forceNew: Bool
    let sourceURL: String
}

/// Extras an external launch carries through the connect flow, which may
/// detour through the password-prompt sheet before a window is opened.
struct ExternalLaunchContext: Equatable, Sendable {
    var remotePathOverride: String?
    /// Deterministic window values: re-launching the same connection without
    /// `new=1` re-stores the data under the same key and `openWindow` then
    /// activates the existing window. nil = always mint a fresh window.
    var browserWindowId: String?
    var terminalWindowId: String?
}

/// One candidate in the ambiguity-resolution sheet when a name matches
/// several connections/bookmarks.
struct ExternalLaunchChoice: Identifiable, Equatable {
    let connection: Connection
    let path: String?
    var id: UUID { connection.id }
}

/// Identifiable wrapper so the choices array can drive `sheet(item:)`.
struct ExternalLaunchChoicesSheet: Identifiable, Equatable {
    let id = UUID()
    let choices: [ExternalLaunchChoice]
}

enum ExternalLaunchParseError: Error, Equatable {
    case badScheme(String)
    case badHost(String)
    case missingTarget
    case bothTargets
    case badView(String)
    case malformedURL

    var message: String {
        switch self {
        case .badScheme(let scheme):
            return "Unknown URL scheme '\(scheme)' (expected '\(ExternalLaunchRequest.scheme)')"
        case .badHost(let host):
            return "Unsupported macscp URL '\(host)' (expected '\(ExternalLaunchRequest.host)')"
        case .missingTarget:
            return "The URL must specify a 'connection' or 'bookmark' parameter"
        case .bothTargets:
            return "The URL must not specify both 'connection' and 'bookmark'"
        case .badView(let value):
            return "Unknown view '\(value)' (expected 'files' or 'terminal')"
        case .malformedURL:
            return "The URL could not be parsed"
        }
    }
}

extension ExternalLaunchRequest {
    static let scheme = "macscp"
    static let host = "open"
    static let enabledDefaultsKey = "externalLaunchEnabled"

    /// Parses an external launch URL.
    /// - Parameter url: The URL delivered by the system.
    /// - Returns: A parsed request, or a parse error carrying a user-facing message.
    static func parse(_ url: URL) -> Result<ExternalLaunchRequest, ExternalLaunchParseError> {
        guard let urlScheme = url.scheme?.lowercased() else {
            return .failure(.malformedURL)
        }
        guard urlScheme == scheme else {
            return .failure(.badScheme(urlScheme))
        }
        // `open macscp://...` always yields the "open" host; accept a missing
        // host for hand-typed URLs but reject anything else.
        if let host = url.host, !host.isEmpty, host.lowercased() != Self.host {
            return .failure(.badHost(host))
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.malformedURL)
        }

        var connection: String?
        var bookmark: String?
        var view = ExternalLaunchView.files
        var path: String?
        var forceNew = false

        for item in components.queryItems ?? [] {
            switch item.name {
            case "connection":
                connection = nonEmpty(item.value)
            case "bookmark":
                bookmark = nonEmpty(item.value)
            case "view":
                if let raw = nonEmpty(item.value) {
                    guard let parsed = ExternalLaunchView(rawValue: raw.lowercased()) else {
                        return .failure(.badView(raw))
                    }
                    view = parsed
                }
            case "path":
                path = nonEmpty(item.value)
            case "new":
                forceNew = ["1", "true", "yes"].contains(item.value?.lowercased())
            default:
                logInfo("ExternalLaunch: ignoring unknown parameter '\(item.name)'", category: .app)
            }
        }

        switch (connection, bookmark) {
        case (nil, nil):
            return .failure(.missingTarget)
        case (let connection?, nil):
            // A UUID selects by id; anything else is a connection name.
            if let id = UUID(uuidString: connection) {
                return .success(ExternalLaunchRequest(
                    target: .connectionId(id),
                    view: view,
                    path: path,
                    forceNew: forceNew,
                    sourceURL: sanitized(url)
                ))
            }
            return .success(ExternalLaunchRequest(
                target: .connectionName(connection),
                view: view,
                path: path,
                forceNew: forceNew,
                sourceURL: sanitized(url)
            ))
        case (nil, let bookmark?):
            return .success(ExternalLaunchRequest(
                target: .bookmarkName(bookmark),
                view: view,
                path: path,
                forceNew: forceNew,
                sourceURL: sanitized(url)
            ))
        default:
            return .failure(.bothTargets)
        }
    }

    /// The URL for logs and error surfaces with any userinfo redacted —
    /// callers should never put credentials in a URL, but never log one if they do.
    static func sanitized(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if components?.user != nil || components?.password != nil {
            components?.user = "***"
            components?.password = "***"
        }
        return components?.url?.absoluteString ?? url.absoluteString
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
