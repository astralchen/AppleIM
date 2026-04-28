//
//  ChatStoreModels.swift
//  AppleIM
//

import Foundation

nonisolated enum ChatStoreError: Error, Equatable, Sendable {
    case missingColumn(String)
    case invalidConversationType(Int)
    case invalidMessageType(Int)
    case invalidMessageDirection(Int)
    case invalidMessageSendStatus(Int)
}

nonisolated struct ConversationRecord: Equatable, Sendable {
    let id: ConversationID
    let userID: UserID
    let type: ConversationType
    let targetID: String
    let title: String
    let avatarURL: String?
    let lastMessageID: MessageID?
    let lastMessageTime: Int64?
    let lastMessageDigest: String
    let unreadCount: Int
    let isPinned: Bool
    let isMuted: Bool
    let isHidden: Bool
    let sortTimestamp: Int64
    let updatedAt: Int64
    let createdAt: Int64
}

nonisolated struct OutgoingTextMessageInput: Equatable, Sendable {
    let userID: UserID
    let conversationID: ConversationID
    let senderID: UserID
    let text: String
    let localTime: Int64
    let messageID: MessageID?
    let clientMessageID: String?
    let sortSequence: Int64?

    init(
        userID: UserID,
        conversationID: ConversationID,
        senderID: UserID,
        text: String,
        localTime: Int64,
        messageID: MessageID? = nil,
        clientMessageID: String? = nil,
        sortSequence: Int64? = nil
    ) {
        self.userID = userID
        self.conversationID = conversationID
        self.senderID = senderID
        self.text = text
        self.localTime = localTime
        self.messageID = messageID
        self.clientMessageID = clientMessageID
        self.sortSequence = sortSequence
    }
}

protocol ConversationRepository: Sendable {
    func listConversations(for userID: UserID) async throws -> [Conversation]
    func upsertConversation(_ record: ConversationRecord) async throws
    func markConversationRead(conversationID: ConversationID, userID: UserID) async throws
}

protocol MessageRepository: Sendable {
    func insertOutgoingTextMessage(_ input: OutgoingTextMessageInput) async throws -> StoredMessage
    func listMessages(conversationID: ConversationID, limit: Int, beforeSortSeq: Int64?) async throws -> [StoredMessage]
}
