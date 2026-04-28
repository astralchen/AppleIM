//
//  ConversationDAO.swift
//  AppleIM
//

import Foundation

nonisolated struct ConversationDAO: Sendable {
    private let database: DatabaseActor
    private let paths: AccountStoragePaths

    init(database: DatabaseActor, paths: AccountStoragePaths) {
        self.database = database
        self.paths = paths
    }

    func upsert(_ record: ConversationRecord) async throws {
        try await database.execute(
            """
            INSERT INTO conversation (
                conversation_id,
                user_id,
                biz_type,
                target_id,
                title,
                avatar_url,
                last_message_id,
                last_message_time,
                last_message_digest,
                unread_count,
                is_pinned,
                is_muted,
                is_hidden,
                sort_ts,
                updated_at,
                created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(conversation_id) DO UPDATE SET
                user_id = excluded.user_id,
                biz_type = excluded.biz_type,
                target_id = excluded.target_id,
                title = excluded.title,
                avatar_url = excluded.avatar_url,
                last_message_id = excluded.last_message_id,
                last_message_time = excluded.last_message_time,
                last_message_digest = excluded.last_message_digest,
                unread_count = excluded.unread_count,
                is_pinned = excluded.is_pinned,
                is_muted = excluded.is_muted,
                is_hidden = excluded.is_hidden,
                sort_ts = excluded.sort_ts,
                updated_at = excluded.updated_at;
            """,
            parameters: Self.parameters(for: record),
            paths: paths
        )
    }

    func listConversations(for userID: UserID) async throws -> [ConversationRecord] {
        let rows = try await database.query(
            """
            SELECT
                conversation_id,
                user_id,
                biz_type,
                target_id,
                title,
                avatar_url,
                last_message_id,
                last_message_time,
                last_message_digest,
                unread_count,
                is_pinned,
                is_muted,
                is_hidden,
                sort_ts,
                updated_at,
                created_at
            FROM conversation
            WHERE user_id = ? AND is_hidden = 0
            ORDER BY is_pinned DESC, sort_ts DESC;
            """,
            parameters: [.text(userID.rawValue)],
            paths: paths
        )

        return try rows.map(Self.record(from:))
    }

    func countConversations(for userID: UserID) async throws -> Int {
        let rows = try await database.query(
            "SELECT COUNT(*) AS conversation_count FROM conversation WHERE user_id = ?;",
            parameters: [.text(userID.rawValue)],
            paths: paths
        )

        return try rows.first?.requiredInt("conversation_count") ?? 0
    }

    func markRead(conversationID: ConversationID, userID: UserID) async throws {
        try await database.execute(
            """
            UPDATE conversation
            SET unread_count = 0, updated_at = ?
            WHERE conversation_id = ? AND user_id = ?;
            """,
            parameters: [
                .integer(Self.currentTimestamp()),
                .text(conversationID.rawValue),
                .text(userID.rawValue)
            ],
            paths: paths
        )
    }

    func updatePin(conversationID: ConversationID, userID: UserID, isPinned: Bool) async throws {
        try await updateFlag(
            column: "is_pinned",
            value: isPinned,
            conversationID: conversationID,
            userID: userID
        )
    }

    func updateMute(conversationID: ConversationID, userID: UserID, isMuted: Bool) async throws {
        try await updateFlag(
            column: "is_muted",
            value: isMuted,
            conversationID: conversationID,
            userID: userID
        )
    }

    private func updateFlag(column: String, value: Bool, conversationID: ConversationID, userID: UserID) async throws {
        try await database.execute(
            """
            UPDATE conversation
            SET \(column) = ?, updated_at = ?
            WHERE conversation_id = ? AND user_id = ?;
            """,
            parameters: [
                .integer(value ? 1 : 0),
                .integer(Self.currentTimestamp()),
                .text(conversationID.rawValue),
                .text(userID.rawValue)
            ],
            paths: paths
        )
    }

    static func insertOrUpdateStatement(for record: ConversationRecord) -> SQLiteStatement {
        SQLiteStatement(
            """
            INSERT INTO conversation (
                conversation_id,
                user_id,
                biz_type,
                target_id,
                title,
                avatar_url,
                last_message_id,
                last_message_time,
                last_message_digest,
                unread_count,
                is_pinned,
                is_muted,
                is_hidden,
                sort_ts,
                updated_at,
                created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(conversation_id) DO UPDATE SET
                user_id = excluded.user_id,
                biz_type = excluded.biz_type,
                target_id = excluded.target_id,
                title = excluded.title,
                avatar_url = excluded.avatar_url,
                last_message_id = excluded.last_message_id,
                last_message_time = excluded.last_message_time,
                last_message_digest = excluded.last_message_digest,
                unread_count = excluded.unread_count,
                is_pinned = excluded.is_pinned,
                is_muted = excluded.is_muted,
                is_hidden = excluded.is_hidden,
                sort_ts = excluded.sort_ts,
                updated_at = excluded.updated_at;
            """,
            parameters: parameters(for: record)
        )
    }

    private static func parameters(for record: ConversationRecord) -> [SQLiteValue] {
        [
            .text(record.id.rawValue),
            .text(record.userID.rawValue),
            .integer(Int64(record.type.rawValue)),
            .text(record.targetID),
            .text(record.title),
            .optionalText(record.avatarURL),
            .optionalText(record.lastMessageID?.rawValue),
            .optionalInteger(record.lastMessageTime),
            .text(record.lastMessageDigest),
            .integer(Int64(record.unreadCount)),
            .integer(record.isPinned ? 1 : 0),
            .integer(record.isMuted ? 1 : 0),
            .integer(record.isHidden ? 1 : 0),
            .integer(record.sortTimestamp),
            .integer(record.updatedAt),
            .integer(record.createdAt)
        ]
    }

    private static func record(from row: SQLiteRow) throws -> ConversationRecord {
        let typeRawValue = try row.requiredInt("biz_type")

        guard let type = ConversationType(rawValue: typeRawValue) else {
            throw ChatStoreError.invalidConversationType(typeRawValue)
        }

        return ConversationRecord(
            id: ConversationID(rawValue: try row.requiredString("conversation_id")),
            userID: UserID(rawValue: try row.requiredString("user_id")),
            type: type,
            targetID: try row.requiredString("target_id"),
            title: row.string("title") ?? "",
            avatarURL: row.string("avatar_url"),
            lastMessageID: row.string("last_message_id").map(MessageID.init(rawValue:)),
            lastMessageTime: row.int64("last_message_time"),
            lastMessageDigest: row.string("last_message_digest") ?? "",
            unreadCount: try row.requiredInt("unread_count"),
            isPinned: row.bool("is_pinned"),
            isMuted: row.bool("is_muted"),
            isHidden: row.bool("is_hidden"),
            sortTimestamp: try row.requiredInt64("sort_ts"),
            updatedAt: row.int64("updated_at") ?? 0,
            createdAt: row.int64("created_at") ?? 0
        )
    }

    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }
}
