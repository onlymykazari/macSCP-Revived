//
//  Logger.swift
//  macSCP
//
//  Centralized logging using OSLog
//

import Foundation
import os.log

enum LogCategory: String {
    case app = "App"
    case sftp = "SFTP"
    case s3 = "S3"
    case keychain = "Keychain"
    case database = "Database"
    case ui = "UI"
    case network = "Network"
    case auth = "Auth"
}

enum LogLevel {
    case debug
    case info
    case warning
    case error

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }

    var prefix: String {
        switch self {
        case .debug: return "[DEBUG]"
        case .info: return "[INFO]"
        case .warning: return "[WARNING]"
        case .error: return "[ERROR]"
        }
    }
}

final class Logger {
    static let shared = Logger()

    private let subsystem = Bundle.main.bundleIdentifier ?? AppConstants.bundleIdentifier
    private var loggers: [LogCategory: os.Logger] = [:]

    private init() {
        for category in [LogCategory.app, .sftp, .s3, .keychain, .database, .ui, .network, .auth] {
            loggers[category] = os.Logger(subsystem: subsystem, category: category.rawValue)
        }
        writeLaunchMarker()
    }

    /// Marks a session boundary in the file log with the exact build identity.
    private func writeLaunchMarker() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        #if DEBUG
        let configuration = "Debug"
        #else
        let configuration = "Release"
        #endif
        FileLogStore.shared.write(
            level: .info,
            category: .app,
            message: "=== macSCP-Revived \(version) (build \(build), \(configuration)) launched ==="
        )
    }

    func log(
        _ message: String,
        level: LogLevel = .info,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let logger = loggers[category] ?? os.Logger(subsystem: subsystem, category: category.rawValue)
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "\(level.prefix) [\(fileName):\(line)] \(function) - \(message)"

        logger.log(level: level.osLogType, "\(logMessage)")
        FileLogStore.shared.write(level: level, category: category, message: logMessage)

        #if DEBUG
        print(logMessage)
        #endif
    }

    func debug(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, category: category, file: file, function: function, line: line)
    }

    func info(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }

    func warning(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, category: category, file: file, function: function, line: line)
    }

    func error(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }
}

// MARK: - Convenience Functions
func logDebug(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.debug(message, category: category, file: file, function: function, line: line)
}

func logInfo(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.info(message, category: category, file: file, function: function, line: line)
}

func logWarning(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.warning(message, category: category, file: file, function: function, line: line)
}

func logError(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.error(message, category: category, file: file, function: function, line: line)
}
