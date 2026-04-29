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

    func message(messageID: MessageID) async throws -> StoredMessage? {
        try await messageDAO.message(messageID: messageID)
    }

    func updateMessageSendStatus(messageID: MessageID, status: MessageSendStatus, ack: MessageSendAck?) async throws {
        try await messageDAO.updateSendStatus(messageID: messageID, status: status, ack: ack)
    }

    func resendTextMessage(messageID: MessageID) async throws -> StoredMessage {
        try await messageDAO.prepareTextMessageForResend(messageID: messageID)
    }

    func markMessageDeleted(messageID: MessageID, userID: UserID) async throws {
        guard let storedMessage = try await messageDAO.message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        let now = Self.currentTimestamp()
        try await database.performTransaction(
            [
                SQLiteStatement(
                    "UPDATE message SET is_deleted = 1 WHERE message_id = ?;",
                    parameters: [.text(messageID.rawValue)]
                ),
                Self.refreshConversationSummaryStatement(
                    conversationID: storedMessage.conversationID,
                    userID: userID,
                    updatedAt: now
                )
            ],
            paths: paths
        )
    }

    func revokeMessage(messageID: MessageID, userID: UserID, replacementText: String) async throws -> StoredMessage {
        guard let storedMessage = try await messageDAO.message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        let now = Self.currentTimestamp()
        try await database.performTransaction(
            [
                SQLiteStatement(
                    "UPDATE message SET revoke_status = 1 WHERE message_id = ? AND is_deleted = 0;",
                    parameters: [.text(messageID.rawValue)]
                ),
                SQLiteStatement(
                    """
                    INSERT INTO message_revoke (
                        message_id,
                        operator_id,
                        revoke_time,
                        reason,
                        replace_text
                    ) VALUES (?, ?, ?, NULL, ?)
                    ON CONFLICT(message_id) DO UPDATE SET
                        operator_id = excluded.operator_id,
                        revoke_time = excluded.revoke_time,
                        replace_text = excluded.replace_text;
                    """,
                    parameters: [
                        .text(messageID.rawValue),
                        .text(userID.rawValue),
                        .integer(now),
                        .text(replacementText)
                    ]
                ),
                Self.refreshConversationSummaryStatement(
                    conversationID: storedMessage.conversationID,
                    userID: userID,
                    updatedAt: now
                )
            ],
            paths: paths
        )

        guard let updatedMessage = try await messageDAO.message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        return updatedMessage
    }

    func saveDraft(conversationID: ConversationID, userID: UserID, text: String) async throws {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            try await clearDraft(conversationID: conversationID, userID: userID)
            return
        }

        let now = Self.currentTimestamp()
        try await database.performTransaction(
            [
                SQLiteStatement(
                    """
                    INSERT INTO draft (
                        conversation_id,
                        text,
                        updated_at
                    ) VALUES (?, ?, ?)
                    ON CONFLICT(conversation_id) DO UPDATE SET
                        text = excluded.text,
                        updated_at = excluded.updated_at;
                    """,
                    parameters: [
                        .text(conversationID.rawValue),
                        .text(text),
                        .integer(now)
                    ]
                ),
                SQLiteStatement(
                    """
                    UPDATE conversation
                    SET
                        draft_text = ?,
                        sort_ts = (
                            SELECT COALESCE(MAX(existing.sort_ts), ?) + 1
                            FROM conversation AS existing
                            WHERE existing.user_id = ?
                        ),
                        updated_at = ?
                    WHERE conversation_id = ? AND user_id = ?;
                    """,
                    parameters: [
                        .text(text),
                        .integer(now),
                        .text(userID.rawValue),
                        .integer(now),
                        .text(conversationID.rawValue),
                        .text(userID.rawValue)
                    ]
                )
            ],
            paths: paths
        )
    }

    func draft(conversationID: ConversationID, userID: UserID) async throws -> String? {
        let rows = try await database.query(
            """
            SELECT draft_text
            FROM conversation
            WHERE conversation_id = ? AND user_id = ?
            LIMIT 1;
            """,
            parameters: [
                .text(conversationID.rawValue),
                .text(userID.rawValue)
            ],
            paths: paths
        )

        return rows.first?.string("draft_text")
    }

    func clearDraft(conversationID: ConversationID, userID: UserID) async throws {
        let now = Self.currentTimestamp()
        try await database.performTransaction(
            [
                SQLiteStatement(
                    "DELETE FROM draft WHERE conversation_id = ?;",
                    parameters: [.text(conversationID.rawValue)]
                ),
                SQLiteStatement(
                    """
                    UPDATE conversation
                    SET draft_text = NULL, updated_at = ?
                    WHERE conversation_id = ? AND user_id = ?;
                    """,
                    parameters: [
                        .integer(now),
                        .text(conversationID.rawValue),
                        .text(userID.rawValue)
                    ]
                )
            ],
            paths: paths
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
            isMuted: record.isMuted,
            draftText: record.draftText
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

    private static func refreshConversationSummaryStatement(
        conversationID: ConversationID,
        userID: UserID,
        updatedAt: Int64
    ) -> SQLiteStatement {
        SQLiteStatement(
            """
            UPDATE conversation
            SET
                last_message_id = (
                    SELECT message.message_id
                    FROM message
                    WHERE message.conversation_id = conversation.conversation_id
                    AND message.is_deleted = 0
                    ORDER BY message.sort_seq DESC
                    LIMIT 1
                ),
                last_message_time = (
                    SELECT message.local_time
                    FROM message
                    WHERE message.conversation_id = conversation.conversation_id
                    AND message.is_deleted = 0
                    ORDER BY message.sort_seq DESC
                    LIMIT 1
                ),
                last_message_digest = COALESCE((
                    SELECT
                        CASE
                            WHEN message.revoke_status = 1 THEN COALESCE(message_revoke.replace_text, '')
                            ELSE COALESCE(message_text.text, '')
                        END
                    FROM message
                    LEFT JOIN message_text ON message_text.content_id = message.content_id
                    LEFT JOIN message_revoke ON message_revoke.message_id = message.message_id
                    WHERE message.conversation_id = conversation.conversation_id
                    AND message.is_deleted = 0
                    ORDER BY message.sort_seq DESC
                    LIMIT 1
                ), ''),
                sort_ts = COALESCE((
                    SELECT message.sort_seq
                    FROM message
                    WHERE message.conversation_id = conversation.conversation_id
                    AND message.is_deleted = 0
                    ORDER BY message.sort_seq DESC
                    LIMIT 1
                ), sort_ts),
                updated_at = ?
            WHERE conversation_id = ? AND user_id = ?;
            """,
            parameters: [
                .integer(updatedAt),
                .text(conversationID.rawValue),
                .text(userID.rawValue)
            ]
        )
    }

    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }
}
