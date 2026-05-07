//
//  DemoDataSeeder.swift
//  AppleIM
//
//  演示数据填充器
//  为新账号填充演示会话数据

import Foundation

/// 演示数据填充器
///
/// 在首次启动时为空账号填充演示会话，便于测试和演示
nonisolated enum DemoDataSeeder {
    /// 如果需要则填充演示数据
    ///
    /// 仅在账号没有任何会话时填充
    ///
    /// - Parameters:
    ///   - repository: 聊天仓储
    ///   - userID: 用户 ID
    static func seedIfNeeded(repository: LocalChatRepository, userID: UserID) async throws {
        guard try await !repository.hasConversations(for: userID) else {
            return
        }

        let now = Int64(Date().timeIntervalSince1970)

        let records = [
            ConversationRecord(
                id: "single_sondra",
                userID: userID,
                type: .single,
                targetID: "sondra",
                title: "Sondra",
                avatarURL: nil,
                lastMessageID: nil,
                lastMessageTime: now,
                lastMessageDigest: "Repository/DAO 链路已接入 SQLite。",
                unreadCount: 2,
                draftText: nil,
                isPinned: true,
                isMuted: false,
                isHidden: false,
                sortTimestamp: now,
                updatedAt: now,
                createdAt: now
            ),
            ConversationRecord(
                id: "group_core",
                userID: userID,
                type: .group,
                targetID: "chatbridge_core",
                title: "ChatBridge Core",
                avatarURL: nil,
                lastMessageID: nil,
                lastMessageTime: now - 1_800,
                lastMessageDigest: "Swift 6 严格并发检查保持开启。",
                unreadCount: 0,
                draftText: nil,
                isPinned: false,
                isMuted: true,
                isHidden: false,
                sortTimestamp: now - 1_800,
                updatedAt: now - 1_800,
                createdAt: now - 1_800
            ),
            ConversationRecord(
                id: "system_release",
                userID: userID,
                type: .system,
                targetID: "system",
                title: "系统通知",
                avatarURL: nil,
                lastMessageID: nil,
                lastMessageTime: now - 7_200,
                lastMessageDigest: "Sprint 1 本地存储收口中。",
                unreadCount: 0,
                draftText: nil,
                isPinned: false,
                isMuted: false,
                isHidden: false,
                sortTimestamp: now - 7_200,
                updatedAt: now - 7_200,
                createdAt: now - 7_200
            )
        ]

        try await repository.insertInitialConversations(records)
    }
}
