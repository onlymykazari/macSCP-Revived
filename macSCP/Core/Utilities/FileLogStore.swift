//
//  FileLogStore.swift
//  macSCP
//
//  Persistent file log so diagnostics survive relaunches and can be exported
//  for bug reports. OSLog remains the system sink; info-level and above are
//  always written here, debug entries only when verbose logging is enabled.
//

import Foundation

final class FileLogStore {
    static let shared = FileLogStore()

    static let verboseLoggingDefaultsKey = "verboseLoggingEnabled"

    private let queue = DispatchQueue(label: "com.onlymykazari.macscp-revived.filelog", qos: .utility)
    private let logDirectory: URL
    private let logFileURL: URL
    private let maxLogBytes = 2 * 1024 * 1024

    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private init() {
        logDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        logFileURL = logDirectory.appendingPathComponent("macscp.log")
    }

    var isVerboseEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.verboseLoggingDefaultsKey)
    }

    func write(level: LogLevel, category: LogCategory, message: String) {
        if case .debug = level {
            guard isVerboseEnabled else { return }
        }

        let line = "\(timestampFormatter.string(from: Date())) \(level.prefix) [\(category.rawValue)] \(message)\n"
        let data = Data(line.utf8)
        let directory = logDirectory

        queue.async { [logFileURL, maxLogBytes] in
            if let size = try? FileManager.default.attributesOfItem(atPath: logFileURL.path)[.size] as? Int64,
               size > maxLogBytes {
                let rotated = directory.appendingPathComponent("macscp.log.old")
                try? FileManager.default.removeItem(at: rotated)
                try? FileManager.default.moveItem(at: logFileURL, to: rotated)
            }

            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }

    /// Writes the exported log text to `destination` (current log plus the
    /// previous rotation, newest last).
    func export(to destination: URL) throws {
        try combinedLogText().write(to: destination, atomically: true, encoding: .utf8)
    }

    private func combinedLogText() -> String {
        var text = ""
        let rotatedURL = logDirectory.appendingPathComponent("macscp.log.old")
        if let previous = try? String(contentsOf: rotatedURL, encoding: .utf8) {
            text += previous
        }
        if let current = try? String(contentsOf: logFileURL, encoding: .utf8) {
            text += current
        }
        if text.isEmpty {
            text = "(log file is empty — turn on Verbose Logging, reproduce the issue, then export again)\n"
        }
        return text
    }
}
