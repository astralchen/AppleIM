//
//  LocalNotificationManager.swift
//  AppleIM
//
//  本地通知管理
//  负责授权、前台展示策略和新消息通知投递

import Foundation
@preconcurrency import UserNotifications

/// 收到新消息后的本地通知载荷
nonisolated struct IncomingMessageNotificationPayload: Equatable, Sendable {
    /// 当前账号 ID
    let userID: UserID
    /// 会话 ID
    let conversationID: ConversationID
    /// 消息 ID
    let messageID: MessageID
    /// 通知标题
    let title: String
    /// 消息摘要
    let messageDigest: String
    /// 会话是否免打扰
    let isMuted: Bool
    /// 全局通知是否开启
    let isEnabled: Bool
    /// 是否展示消息预览
    let showPreview: Bool
    /// 隐藏预览时使用的通用正文
    let hiddenPreviewText: String

    init(
        userID: UserID,
        conversationID: ConversationID,
        messageID: MessageID,
        title: String,
        messageDigest: String,
        isMuted: Bool,
        isEnabled: Bool,
        showPreview: Bool,
        hiddenPreviewText: String = "收到一条新消息"
    ) {
        self.userID = userID
        self.conversationID = conversationID
        self.messageID = messageID
        self.title = title
        self.messageDigest = messageDigest
        self.isMuted = isMuted
        self.isEnabled = isEnabled
        self.showPreview = showPreview
        self.hiddenPreviewText = hiddenPreviewText
    }

    var notificationBody: String {
        showPreview ? messageDigest : hiddenPreviewText
    }
}

/// 本地通知管理协议
protocol LocalNotificationManaging: Sendable {
    /// 请求通知授权
    func requestAuthorization() async throws -> Bool
    /// 调度收到新消息的本地通知
    func scheduleIncomingMessageNotification(_ payload: IncomingMessageNotificationPayload) async throws
}

/// 基于 UserNotifications 的本地通知管理器
final class UserNotificationCenterNotificationManager: NSObject, LocalNotificationManaging, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func scheduleIncomingMessageNotification(_ payload: IncomingMessageNotificationPayload) async throws {
        guard payload.isEnabled, !payload.isMuted else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = payload.title.isEmpty ? "ChatBridge" : payload.title
        content.body = payload.notificationBody
        content.sound = .default
        content.userInfo = [
            "user_id": payload.userID.rawValue,
            "conversation_id": payload.conversationID.rawValue,
            "message_id": payload.messageID.rawValue
        ]

        let request = UNNotificationRequest(
            identifier: "incoming_\(payload.conversationID.rawValue)_\(payload.messageID.rawValue)",
            content: content,
            trigger: nil
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }
}
