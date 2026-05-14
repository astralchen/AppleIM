//
//  ChatStoreConversationChangeEvent.swift
//  AppleIM
//
//  类型化会话变更事件
//  兼容现有 NotificationCenter 广播，同时给 UI 层提供结构化订阅入口

import Combine
import Foundation

/// 会话集合变更事件。
nonisolated struct ChatStoreConversationChangeEvent: Equatable, Sendable {
    /// 发生变更的账号 ID。
    let userID: UserID
    /// 发生变更的会话 ID。
    let conversationIDs: Set<ConversationID>

    init(userID: UserID, conversationIDs: Set<ConversationID>) {
        self.userID = userID
        self.conversationIDs = conversationIDs
    }

    init?(notification: Notification) {
        guard let rawUserID = notification.userInfo?[ChatStoreConversationChangeNotification.userIDKey] as? String else {
            return nil
        }

        let rawConversationIDs = notification.userInfo?[ChatStoreConversationChangeNotification.conversationIDsKey] as? [String] ?? []
        self.userID = UserID(rawValue: rawUserID)
        self.conversationIDs = Set(rawConversationIDs.map(ConversationID.init(rawValue:)))
    }
}

extension NotificationCenter {
    /// 兼容 NotificationCenter 桥接的类型化会话变更 publisher。
    func chatStoreConversationChangesPublisher() -> AnyPublisher<ChatStoreConversationChangeEvent, Never> {
        publisher(for: .chatStoreConversationsDidChange)
            .compactMap(ChatStoreConversationChangeEvent.init(notification:))
            .eraseToAnyPublisher()
    }
}
