//
//  ConversationListLoadingDiagnostics.swift
//  AppleIM
//
//  Diagnostics for tracing conversation list loading latency.

import Foundation

/// 会话列表加载诊断协议
///
/// 用于在不耦合具体日志实现的前提下记录加载链路耗时与状态。
nonisolated protocol ConversationListLoadingDiagnostics: Sendable {
    /// 记录一条诊断消息
    func log(_ message: String)
}

/// 基于应用日志系统的会话列表加载诊断实现
nonisolated struct AppConversationListLoadingDiagnostics: ConversationListLoadingDiagnostics {
    /// 会话列表日志分类
    private let logger = AppLogger(category: .conversationList)

    /// 写入 info 级别诊断日志
    func log(_ message: String) {
        logger.info(message)
    }
}
