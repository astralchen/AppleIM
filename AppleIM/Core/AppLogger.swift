//
//  AppLogger.swift
//  AppleIM
//
//  轻量级统一日志封装

import Foundation
import OSLog

/// 应用日志级别
nonisolated enum AppLogLevel: Sendable {
    /// 调试信息
    case debug
    /// 一般信息
    case info
    /// 错误信息
    case error
}

/// 应用日志工具
///
/// 基于 OSLog 的轻量级日志封装，支持分类和级别
nonisolated struct AppLogger: Sendable {
    /// 日志分类
    enum Category: String, Sendable {
        /// 会话列表
        case conversationList = "ConversationList"
        /// 存储层
        case store = "Store"
    }

    /// 默认子系统标识
    private static let fallbackSubsystem = "com.sondra.AppleIM"
    /// OSLog Logger 实例
    private let logger: Logger

    /// 初始化
    ///
    /// - Parameter category: 日志分类
    init(category: Category) {
        let subsystem = Bundle.main.bundleIdentifier ?? Self.fallbackSubsystem
        self.logger = Logger(subsystem: subsystem, category: category.rawValue)
    }

    /// 记录调试信息
    ///
    /// - Parameter message: 日志消息（延迟求值）
    func debug(_ message: @autoclosure () -> String) {
        let resolvedMessage = message()
        logger.debug("\(resolvedMessage, privacy: .public)")
    }

    /// 记录一般信息
    ///
    /// - Parameter message: 日志消息（延迟求值）
    func info(_ message: @autoclosure () -> String) {
        let resolvedMessage = message()
        logger.info("\(resolvedMessage, privacy: .public)")
    }

    /// 记录错误信息
    ///
    /// - Parameter message: 日志消息（延迟求值）
    func error(_ message: @autoclosure () -> String) {
        let resolvedMessage = message()
        logger.error("\(resolvedMessage, privacy: .public)")
    }

    /// 记录指定级别的日志
    ///
    /// - Parameters:
    ///   - level: 日志级别
    ///   - message: 日志消息（延迟求值）
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

    /// 计算经过的毫秒数
    ///
    /// 用于性能测量，基于系统启动时间计算
    ///
    /// - Parameter startUptime: 起始系统启动时间
    /// - Returns: 格式化的毫秒数字符串（如 "123.4ms"）
    static func elapsedMilliseconds(since startUptime: TimeInterval) -> String {
        let milliseconds = (ProcessInfo.processInfo.systemUptime - startUptime) * 1_000
        return String(format: "%.1fms", milliseconds)
    }
}
