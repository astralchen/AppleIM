//
//  DemoDataSeeder.swift
//  AppleIM
//

import Foundation

nonisolated enum DemoDataSeeder {
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
                isPinned: false,
                isMuted: false,
                isHidden: false,
                sortTimestamp: now - 7_200,
                updatedAt: now - 7_200,
                createdAt: now - 7_200
            )
        ]

        for record in records {
            try await repository.upsertConversation(record)
        }
    }
}
