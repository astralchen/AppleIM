//
//  ChatStoreEventDispatcher.swift
//  AppleIM
//
//  聊天存储事件分发器
//  收口仓储事务完成后的搜索索引、通知、角标和 UI 刷新广播等副作用

import Foundation

/// 聊天存储副作用分发接口。
///
/// Repository 只决定何时发生了数据变化，具体副作用由该接口承接，便于测试和后续替换为任务队列。
protocol ChatStoreEventDispatching: Sendable {
    /// 设置 App 图标角标。
    func setApplicationBadgeNumber(_ count: Int) async
    /// 投递本地消息通知。
    func scheduleIncomingMessageNotifications(_ payloads: [IncomingMessageNotificationPayload]) async
    /// 尽力更新消息搜索索引。
    nonisolated func indexMessageBestEffort(messageID: MessageID, userID: UserID)
    /// 尽力移除消息搜索索引。
    nonisolated func removeMessageBestEffort(messageID: MessageID, userID: UserID)
    /// 尽力更新会话搜索索引。
    nonisolated func indexConversationBestEffort(conversationID: ConversationID, userID: UserID)
    /// 广播会话集合发生变化。
    nonisolated func postConversationsDidChange(userID: UserID, conversationIDs: Set<ConversationID>)
}

/// 生产环境聊天存储事件分发器。
nonisolated struct DefaultChatStoreEventDispatcher: ChatStoreEventDispatching {
    private let database: DatabaseActor
    private let paths: AccountStoragePaths
    private let localNotificationManager: (any LocalNotificationManaging)?
    private let applicationBadgeManager: (any ApplicationBadgeManaging)?

    init(
        database: DatabaseActor,
        paths: AccountStoragePaths,
        localNotificationManager: (any LocalNotificationManaging)? = nil,
        applicationBadgeManager: (any ApplicationBadgeManaging)? = nil
    ) {
        self.database = database
        self.paths = paths
        self.localNotificationManager = localNotificationManager
        self.applicationBadgeManager = applicationBadgeManager
    }

    func setApplicationBadgeNumber(_ count: Int) async {
        await applicationBadgeManager?.setApplicationIconBadgeNumber(count)
    }

    func scheduleIncomingMessageNotifications(_ payloads: [IncomingMessageNotificationPayload]) async {
        guard let localNotificationManager, !payloads.isEmpty else {
            return
        }

        for payload in payloads {
            try? await localNotificationManager.scheduleIncomingMessageNotification(payload)
        }
    }

    func indexMessageBestEffort(messageID: MessageID, userID: UserID) {
        let searchIndex = SearchIndexActor(database: database, paths: paths)
        Task {
            await searchIndex.indexMessageBestEffort(messageID: messageID, userID: userID)
        }
    }

    func removeMessageBestEffort(messageID: MessageID, userID: UserID) {
        let searchIndex = SearchIndexActor(database: database, paths: paths)
        Task {
            await searchIndex.removeMessageBestEffort(messageID: messageID, userID: userID)
        }
    }

    func indexConversationBestEffort(conversationID: ConversationID, userID: UserID) {
        let searchIndex = SearchIndexActor(database: database, paths: paths)
        Task {
            await searchIndex.indexConversationBestEffort(conversationID: conversationID, userID: userID)
        }
    }

    func postConversationsDidChange(userID: UserID, conversationIDs: Set<ConversationID>) {
        guard !conversationIDs.isEmpty else { return }

        let rawUserID = userID.rawValue
        let rawConversationIDs = conversationIDs.map(\.rawValue)
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .chatStoreConversationsDidChange,
                object: nil,
                userInfo: [
                    ChatStoreConversationChangeNotification.userIDKey: rawUserID,
                    ChatStoreConversationChangeNotification.conversationIDsKey: rawConversationIDs
                ]
            )
        }
    }
}
