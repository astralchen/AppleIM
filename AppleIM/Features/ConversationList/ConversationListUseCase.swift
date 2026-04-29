//
//  ConversationListUseCase.swift
//  AppleIM
//
//  会话列表用例
//  封装会话列表的业务逻辑

import Foundation

/// 会话列表用例协议
protocol ConversationListUseCase: Sendable {
    /// 加载会话列表
    func loadConversations() async throws -> [ConversationListRowState]
}

/// 本地会话列表用例实现
nonisolated struct LocalConversationListUseCase: ConversationListUseCase {
    /// 用户 ID
    private let userID: UserID
    /// 存储提供者
    private let storeProvider: ChatStoreProvider

    init(userID: UserID, storeProvider: ChatStoreProvider) {
        self.userID = userID
        self.storeProvider = storeProvider
    }

    func loadConversations() async throws -> [ConversationListRowState] {
        let repository = try await storeProvider.repository()
        let conversations = try await repository.listConversations(for: userID)

        return conversations.map { conversation in
            let subtitle = conversation.draftText.map { "Draft: \($0)" } ?? conversation.lastMessageDigest

            return ConversationListRowState(
                id: conversation.id,
                title: conversation.title,
                subtitle: subtitle,
                timeText: conversation.lastMessageTimeText,
                unreadText: conversation.unreadCount > 0 ? "\(conversation.unreadCount)" : nil,
                isPinned: conversation.isPinned,
                isMuted: conversation.isMuted
            )
        }
    }
}

nonisolated struct PreviewConversationListUseCase: ConversationListUseCase {
    func loadConversations() async throws -> [ConversationListRowState] {
        try await Task.sleep(nanoseconds: 120_000_000)

        return [
            ConversationListRowState(
                id: "single_sondra",
                title: "Sondra",
                subtitle: "The MVVM baseline is ready.",
                timeText: "09:41",
                unreadText: "2",
                isPinned: true,
                isMuted: false
            ),
            ConversationListRowState(
                id: "group_core",
                title: "ChatBridge Core",
                subtitle: "Swift 6 strict concurrency is enabled.",
                timeText: "Yesterday",
                unreadText: nil,
                isPinned: false,
                isMuted: true
            )
        ]
    }
}
