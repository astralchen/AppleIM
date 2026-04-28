//
//  ConversationListUseCase.swift
//  AppleIM
//

import Foundation

protocol ConversationListUseCase: Sendable {
    func loadConversations() async throws -> [ConversationListRowState]
}

nonisolated struct LocalConversationListUseCase: ConversationListUseCase {
    private let userID: UserID
    private let storeProvider: ChatStoreProvider

    init(userID: UserID, storeProvider: ChatStoreProvider) {
        self.userID = userID
        self.storeProvider = storeProvider
    }

    func loadConversations() async throws -> [ConversationListRowState] {
        let repository = try await storeProvider.repository()
        let conversations = try await repository.listConversations(for: userID)

        return conversations.map { conversation in
            ConversationListRowState(
                id: conversation.id,
                title: conversation.title,
                subtitle: conversation.lastMessageDigest,
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
