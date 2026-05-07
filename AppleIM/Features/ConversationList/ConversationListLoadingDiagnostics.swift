//
//  ConversationListLoadingDiagnostics.swift
//  AppleIM
//
//  Diagnostics for tracing conversation list loading latency.

import Foundation

nonisolated protocol ConversationListLoadingDiagnostics: Sendable {
    func log(_ message: String)
}

nonisolated struct AppConversationListLoadingDiagnostics: ConversationListLoadingDiagnostics {
    private let logger = AppLogger(category: .conversationList)

    func log(_ message: String) {
        logger.info(message)
    }
}
