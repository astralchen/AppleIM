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

extension Notification.Name {
    /// 联系人资料变更后发出的本地 UI 刷新广播。
    static let chatStoreContactProfileDidChange = Notification.Name("ChatStoreContactProfileDidChange")
}

nonisolated enum ContactProfileChangeNotification {
    static let userIDKey = "userID"
    static let contactIDKey = "contactID"
    static let conversationIDKey = "conversationID"
    static let displayNameKey = "displayName"
    static let avatarURLKey = "avatarURL"
}

/// 联系人资料变更事件。
nonisolated struct ContactProfileChangeEvent: Equatable, Sendable {
    /// 发生变更的账号 ID。
    let userID: UserID
    /// 发生变更的联系人 ID。
    let contactID: ContactID
    /// 资料变更影响到的已有会话 ID；没有已有会话时为空。
    let conversationID: ConversationID?
    /// 最新显示名。
    let displayName: String
    /// 最新头像 URL。
    let avatarURL: String?

    init(
        userID: UserID,
        contactID: ContactID,
        conversationID: ConversationID?,
        displayName: String,
        avatarURL: String?
    ) {
        self.userID = userID
        self.contactID = contactID
        self.conversationID = conversationID
        self.displayName = displayName
        self.avatarURL = avatarURL
    }

    init?(notification: Notification) {
        guard
            let rawUserID = notification.userInfo?[ContactProfileChangeNotification.userIDKey] as? String,
            let rawContactID = notification.userInfo?[ContactProfileChangeNotification.contactIDKey] as? String,
            let displayName = notification.userInfo?[ContactProfileChangeNotification.displayNameKey] as? String
        else {
            return nil
        }

        self.userID = UserID(rawValue: rawUserID)
        self.contactID = ContactID(rawValue: rawContactID)
        if let rawConversationID = notification.userInfo?[ContactProfileChangeNotification.conversationIDKey] as? String {
            self.conversationID = ConversationID(rawValue: rawConversationID)
        } else {
            self.conversationID = nil
        }
        self.displayName = displayName
        self.avatarURL = notification.userInfo?[ContactProfileChangeNotification.avatarURLKey] as? String
    }

    var userInfo: [String: Any] {
        var userInfo: [String: Any] = [
            ContactProfileChangeNotification.userIDKey: userID.rawValue,
            ContactProfileChangeNotification.contactIDKey: contactID.rawValue,
            ContactProfileChangeNotification.displayNameKey: displayName
        ]
        if let conversationID {
            userInfo[ContactProfileChangeNotification.conversationIDKey] = conversationID.rawValue
        }
        if let avatarURL {
            userInfo[ContactProfileChangeNotification.avatarURLKey] = avatarURL
        }
        return userInfo
    }
}

extension NotificationCenter {
    /// 兼容 NotificationCenter 桥接的类型化联系人资料变更 publisher。
    func contactProfileChangesPublisher() -> AnyPublisher<ContactProfileChangeEvent, Never> {
        publisher(for: .chatStoreContactProfileDidChange)
            .compactMap(ContactProfileChangeEvent.init(notification:))
            .eraseToAnyPublisher()
    }
}
