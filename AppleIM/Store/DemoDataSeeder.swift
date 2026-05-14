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
    static func seedIfNeeded(
        repository: LocalChatRepository,
        userID: UserID,
        catalog: any DemoDataCatalog = BundleDemoDataCatalog(),
        contactCatalog: any ContactCatalog = BundleContactCatalog()
    ) async throws {
        let now = Int64(Date().timeIntervalSince1970)
        let hasConversations = try await repository.hasConversations(for: userID)
        let demoData = try await catalog.demoData(for: userID, now: now)

        if !hasConversations {
            try await repository.insertInitialConversations(demoData.conversations)
            try await repository.insertInitialTextMessages(demoData.messages)
        }

        try await seedContactsIfNeeded(repository: repository, userID: userID, catalog: contactCatalog)
        try await repository.upsertGroupMembers(demoData.groupMembers)
        for announcement in demoData.groupAnnouncements {
            try await repository.updateGroupAnnouncement(
                conversationID: announcement.conversationID,
                userID: userID,
                text: announcement.text
            )
        }
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
