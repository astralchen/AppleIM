//
//  LocalChatRepository.swift
//  AppleIM
//

import Foundation

nonisolated struct LocalChatRepository: ConversationRepository, MessageRepository {
    private let database: DatabaseActor
    private let paths: AccountStoragePaths
    private let conversationDAO: ConversationDAO
    private let messageDAO: MessageDAO

    init(database: DatabaseActor, paths: AccountStoragePaths) {
        self.database = database
        self.paths = paths
        self.conversationDAO = ConversationDAO(database: database, paths: paths)
        self.messageDAO = MessageDAO(database: database, paths: paths)
    }

    func listConversations(for userID: UserID) async throws -> [Conversation] {
        let records = try await conversationDAO.listConversations(for: userID)
        return records.map(Self.conversation(from:))
    }

    func upsertConversation(_ record: ConversationRecord) async throws {
        try await conversationDAO.upsert(record)
    }

    func markConversationRead(conversationID: ConversationID, userID: UserID) async throws {
        try await conversationDAO.markRead(conversationID: conversationID, userID: userID)
    }

    func insertOutgoingTextMessage(_ input: OutgoingTextMessageInput) async throws -> StoredMessage {
        let result = MessageDAO.insertOutgoingTextStatements(input)
        try await database.performTransaction(result.statements, paths: paths)
        return result.message
    }

    func listMessages(conversationID: ConversationID, limit: Int, beforeSortSeq: Int64?) async throws -> [StoredMessage] {
        try await messageDAO.listMessages(
            conversationID: conversationID,
            limit: limit,
            beforeSortSeq: beforeSortSeq
        )
    }

    func hasConversations(for userID: UserID) async throws -> Bool {
        try await conversationDAO.countConversations(for: userID) > 0
    }

    private static func conversation(from record: ConversationRecord) -> Conversation {
        Conversation(
            id: record.id,
            type: record.type,
            title: record.title,
            lastMessageDigest: record.lastMessageDigest,
            lastMessageTimeText: timeText(from: record.lastMessageTime),
            unreadCount: record.unreadCount,
            isPinned: record.isPinned,
            isMuted: record.isMuted
        )
    }

    private static func timeText(from timestamp: Int64?) -> String {
        guard let timestamp, timestamp > 0 else {
            return ""
        }

        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
