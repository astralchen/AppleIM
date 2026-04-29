//
//  MessageDAO.swift
//  AppleIM
//

import Foundation

nonisolated struct MessageDAO: Sendable {
    private let database: DatabaseActor
    private let paths: AccountStoragePaths

    init(database: DatabaseActor, paths: AccountStoragePaths) {
        self.database = database
        self.paths = paths
    }

    func listMessages(conversationID: ConversationID, limit: Int, beforeSortSeq: Int64?) async throws -> [StoredMessage] {
        let rows = try await database.query(
            """
            SELECT
                message.message_id,
                message.conversation_id,
                message.sender_id,
                message.client_msg_id,
                message.server_msg_id,
                message.seq,
                message.msg_type,
                message.direction,
                message.send_status,
                message.server_time,
                message.revoke_status,
                message.is_deleted,
                message_revoke.replace_text,
                message.sort_seq,
                message.local_time,
                message_text.text
            FROM message
            LEFT JOIN message_text ON message_text.content_id = message.content_id
            LEFT JOIN message_revoke ON message_revoke.message_id = message.message_id
            WHERE message.conversation_id = ?
            AND (? IS NULL OR message.sort_seq < ?)
            AND message.is_deleted = 0
            ORDER BY message.sort_seq DESC
            LIMIT ?;
            """,
            parameters: [
                .text(conversationID.rawValue),
                .optionalInteger(beforeSortSeq),
                .optionalInteger(beforeSortSeq),
                .integer(Int64(limit))
            ],
            paths: paths
        )

        return try rows.map(Self.message(from:))
    }

    func message(messageID: MessageID) async throws -> StoredMessage? {
        let rows = try await database.query(
            """
            SELECT
                message.message_id,
                message.conversation_id,
                message.sender_id,
                message.client_msg_id,
                message.server_msg_id,
                message.seq,
                message.msg_type,
                message.direction,
                message.send_status,
                message.server_time,
                message.revoke_status,
                message.is_deleted,
                message_revoke.replace_text,
                message.sort_seq,
                message.local_time,
                message_text.text
            FROM message
            LEFT JOIN message_text ON message_text.content_id = message.content_id
            LEFT JOIN message_revoke ON message_revoke.message_id = message.message_id
            WHERE message.message_id = ?
            AND message.is_deleted = 0
            LIMIT 1;
            """,
            parameters: [.text(messageID.rawValue)],
            paths: paths
        )

        guard let row = rows.first else {
            return nil
        }

        return try Self.message(from: row)
    }

    func updateSendStatus(messageID: MessageID, status: MessageSendStatus, ack: MessageSendAck?) async throws {
        try await database.execute(
            """
            UPDATE message
            SET
                send_status = ?,
                server_msg_id = ?,
                seq = ?,
                server_time = ?
            WHERE message_id = ?;
            """,
            parameters: [
                .integer(Int64(status.rawValue)),
                .optionalText(ack?.serverMessageID),
                .optionalInteger(ack?.sequence),
                .optionalInteger(ack?.serverTime),
                .text(messageID.rawValue)
            ],
            paths: paths
        )
    }

    func prepareTextMessageForResend(messageID: MessageID) async throws -> StoredMessage {
        guard let existingMessage = try await message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        guard
            existingMessage.type == .text,
            existingMessage.sendStatus == .failed,
            !existingMessage.isRevoked,
            !existingMessage.isDeleted
        else {
            throw ChatStoreError.messageCannotBeResent(messageID)
        }

        try await updateSendStatus(messageID: messageID, status: .sending, ack: nil)

        guard let updatedMessage = try await message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        return updatedMessage
    }

    static func insertOutgoingTextStatements(_ input: OutgoingTextMessageInput) -> (message: StoredMessage, statements: [SQLiteStatement]) {
        let messageID = input.messageID ?? MessageID(rawValue: UUID().uuidString)
        let clientMessageID = input.clientMessageID ?? messageID.rawValue
        let contentID = "text_\(messageID.rawValue)"
        let sortSequence = input.sortSequence ?? input.localTime

        let message = StoredMessage(
            id: messageID,
            conversationID: input.conversationID,
            senderID: input.senderID,
            clientMessageID: clientMessageID,
            serverMessageID: nil,
            sequence: nil,
            type: .text,
            direction: .outgoing,
            sendStatus: .sending,
            serverTime: nil,
            isRevoked: false,
            isDeleted: false,
            revokeReplacementText: nil,
            text: input.text,
            sortSequence: sortSequence,
            localTime: input.localTime
        )

        return (
            message,
            [
                SQLiteStatement(
                    """
                    INSERT INTO message_text (
                        content_id,
                        text,
                        mentions_json,
                        at_all,
                        rich_text_json
                    ) VALUES (?, ?, NULL, 0, NULL);
                    """,
                    parameters: [
                        .text(contentID),
                        .text(input.text)
                    ]
                ),
                SQLiteStatement(
                    """
                    INSERT INTO message (
                        message_id,
                        conversation_id,
                        sender_id,
                        client_msg_id,
                        msg_type,
                        direction,
                        send_status,
                        delivery_status,
                        read_status,
                        revoke_status,
                        is_deleted,
                        content_table,
                        content_id,
                        sort_seq,
                        local_time
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, 0, 0, ?, ?, ?, ?);
                    """,
                    parameters: [
                        .text(message.id.rawValue),
                        .text(input.conversationID.rawValue),
                        .text(input.senderID.rawValue),
                        .text(clientMessageID),
                        .integer(Int64(MessageType.text.rawValue)),
                        .integer(Int64(MessageDirection.outgoing.rawValue)),
                        .integer(Int64(MessageSendStatus.sending.rawValue)),
                        .text("message_text"),
                        .text(contentID),
                        .integer(sortSequence),
                        .integer(input.localTime)
                    ]
                ),
                SQLiteStatement(
                    """
                    UPDATE conversation
                    SET
                        last_message_id = ?,
                        last_message_time = ?,
                        last_message_digest = ?,
                        sort_ts = ?,
                        updated_at = ?
                    WHERE conversation_id = ? AND user_id = ?;
                    """,
                    parameters: [
                        .text(message.id.rawValue),
                        .integer(input.localTime),
                        .text(input.text),
                        .integer(sortSequence),
                        .integer(input.localTime),
                        .text(input.conversationID.rawValue),
                        .text(input.userID.rawValue)
                    ]
                )
            ]
        )
    }

    private static func message(from row: SQLiteRow) throws -> StoredMessage {
        let typeRawValue = try row.requiredInt("msg_type")
        let directionRawValue = try row.requiredInt("direction")
        let sendStatusRawValue = try row.requiredInt("send_status")

        guard let type = MessageType(rawValue: typeRawValue) else {
            throw ChatStoreError.invalidMessageType(typeRawValue)
        }

        guard let direction = MessageDirection(rawValue: directionRawValue) else {
            throw ChatStoreError.invalidMessageDirection(directionRawValue)
        }

        guard let sendStatus = MessageSendStatus(rawValue: sendStatusRawValue) else {
            throw ChatStoreError.invalidMessageSendStatus(sendStatusRawValue)
        }

        return StoredMessage(
            id: MessageID(rawValue: try row.requiredString("message_id")),
            conversationID: ConversationID(rawValue: try row.requiredString("conversation_id")),
            senderID: UserID(rawValue: try row.requiredString("sender_id")),
            clientMessageID: row.string("client_msg_id"),
            serverMessageID: row.string("server_msg_id"),
            sequence: row.int64("seq"),
            type: type,
            direction: direction,
            sendStatus: sendStatus,
            serverTime: row.int64("server_time"),
            isRevoked: row.bool("revoke_status"),
            isDeleted: row.bool("is_deleted"),
            revokeReplacementText: row.string("replace_text"),
            text: row.string("text"),
            sortSequence: try row.requiredInt64("sort_seq"),
            localTime: try row.requiredInt64("local_time")
        )
    }
}
