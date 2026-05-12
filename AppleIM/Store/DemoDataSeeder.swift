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
        let now = Int64(Date().timeIntervalSince1970)
        let hasConversations = try await repository.hasConversations(for: userID)

        if !hasConversations {
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
            try await repository.insertInitialTextMessages(initialMessages(userID: userID, now: now))
        }

        try await seedContactsIfNeeded(repository: repository, userID: userID)
        try await repository.upsertGroupMembers([
            GroupMember(
                conversationID: "group_core",
                memberID: userID,
                displayName: "Me",
                role: .admin,
                joinTime: now - 3_600
            ),
            GroupMember(
                conversationID: "group_core",
                memberID: "sondra",
                displayName: "Sondra",
                role: .owner,
                joinTime: now - 3_500
            ),
            GroupMember(
                conversationID: "group_core",
                memberID: "qa_ming",
                displayName: "明明",
                role: .member,
                joinTime: now - 3_400
            ),
            GroupMember(
                conversationID: "group_core",
                memberID: "ios_yan",
                displayName: "Yan",
                role: .member,
                joinTime: now - 3_300
            )
        ])
        try await repository.updateGroupAnnouncement(
            conversationID: "group_core",
            userID: userID,
            text: "群聊 P1 本地闭环演示：公告、@ 成员与会话提示已接入。"
        )
        try await seedEmojiIfNeeded(repository: repository, userID: userID, now: now)
    }

    /// 如果当前账号没有联系人，则从本地 JSON 模拟通讯录填充。
    static func seedContactsIfNeeded(
        repository: LocalChatRepository,
        userID: UserID,
        catalog: any ContactCatalog = BundleContactCatalog()
    ) async throws {
        guard try await repository.countContacts(for: userID) == 0 else {
            return
        }

        let contacts = try await catalog.contacts(for: userID)
        try await repository.upsertContacts(contacts)
    }

    private static func initialMessages(userID: UserID, now: Int64) -> [InitialTextMessageInput] {
        [
            InitialTextMessageInput(
                userID: userID,
                conversationID: "single_sondra",
                senderID: "sondra",
                text: "本地账号存储已准备完成。",
                localTime: now - 90,
                messageID: "seed_single_sondra_1",
                serverMessageID: "server_seed_single_sondra_1",
                sequence: now - 90,
                direction: .incoming,
                readStatus: .unread,
                sortSequence: now - 90
            ),
            InitialTextMessageInput(
                userID: userID,
                conversationID: "single_sondra",
                senderID: "sondra",
                text: "Repository/DAO 链路已接入 SQLite。",
                localTime: now,
                messageID: "seed_single_sondra_2",
                serverMessageID: "server_seed_single_sondra_2",
                sequence: now,
                direction: .incoming,
                readStatus: .unread,
                sortSequence: now
            ),
            InitialTextMessageInput(
                userID: userID,
                conversationID: "group_core",
                senderID: "ios_yan",
                text: "Swift 6 严格并发检查保持开启。",
                localTime: now - 1_800,
                messageID: "seed_group_core_1",
                serverMessageID: "server_seed_group_core_1",
                sequence: now - 1_800,
                direction: .incoming,
                readStatus: .read,
                sortSequence: now - 1_800
            ),
            InitialTextMessageInput(
                userID: userID,
                conversationID: "system_release",
                senderID: "system",
                text: "Sprint 1 本地存储收口中。",
                localTime: now - 7_200,
                messageID: "seed_system_release_1",
                serverMessageID: "server_seed_system_release_1",
                sequence: now - 7_200,
                direction: .incoming,
                readStatus: .read,
                sortSequence: now - 7_200
            )
        ]
    }

    private static func seedEmojiIfNeeded(repository: LocalChatRepository, userID: UserID, now: Int64) async throws {
        let packageID = "chatbridge_default_emoji"
        try await repository.upsertEmojiPackage(
            EmojiPackageRecord(
                packageID: packageID,
                userID: userID,
                title: "ChatBridge",
                author: "ChatBridge",
                coverURL: nil,
                localCoverPath: nil,
                version: 1,
                status: .downloaded,
                sortOrder: 0,
                createdAt: now,
                updatedAt: now
            )
        )

        let names = [
            ("cb_smile", "Smile"),
            ("cb_wave", "Wave"),
            ("cb_ok", "OK"),
            ("cb_party", "Party"),
            ("cb_thanks", "Thanks"),
            ("cb_heart", "Heart"),
            ("cb_working", "Working"),
            ("cb_done", "Done")
        ]

        for (index, item) in names.enumerated() {
            try await repository.upsertEmojiAsset(
                EmojiAssetRecord(
                    emojiID: item.0,
                    userID: userID,
                    packageID: packageID,
                    emojiType: .package,
                    name: item.1,
                    md5: nil,
                    localPath: nil,
                    thumbPath: nil,
                    cdnURL: nil,
                    width: 128,
                    height: 128,
                    sizeBytes: nil,
                    useCount: 0,
                    lastUsedAt: nil,
                    isFavorite: index < 2,
                    isDeleted: false,
                    extraJSON: nil,
                    createdAt: now + Int64(index),
                    updatedAt: now + Int64(index)
                )
            )
        }
    }
}
