//
//  AppLogger.swift
//  AppleIM
//
//  Lightweight unified logging wrapper.

import Foundation
import OSLog

nonisolated enum AppLogLevel: Sendable {
    case debug
    case info
    case error
}

nonisolated struct AppLogger: Sendable {
    enum Category: String, Sendable {
        case conversationList = "ConversationList"
        case store = "Store"
    }

    private static let fallbackSubsystem = "com.sondra.AppleIM"
    private let logger: Logger

    init(category: Category) {
        let subsystem = Bundle.main.bundleIdentifier ?? Self.fallbackSubsystem
        self.logger = Logger(subsystem: subsystem, category: category.rawValue)
    }

    func debug(_ message: @autoclosure () -> String) {
        let resolvedMessage = message()
        logger.debug("\(resolvedMessage, privacy: .public)")
    }

    func info(_ message: @autoclosure () -> String) {
        let resolvedMessage = message()
        logger.info("\(resolvedMessage, privacy: .public)")
    }

    func error(_ message: @autoclosure () -> String) {
        let resolvedMessage = message()
        logger.error("\(resolvedMessage, privacy: .public)")
    }

    func log(_ level: AppLogLevel, _ message: @autoclosure () -> String) {
        switch level {
        case .debug:
            debug(message())
        case .info:
            info(message())
        case .error:
            error(message())
        }
    }

    static func elapsedMilliseconds(since startUptime: TimeInterval) -> String {
        let milliseconds = (ProcessInfo.processInfo.systemUptime - startUptime) * 1_000
        return String(format: "%.1fms", milliseconds)
    }
}
