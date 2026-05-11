//
//  ConversationDAO.swift
//  AppleIM
//
//  会话数据访问对象（DAO）
//  负责会话的增删改查操作

import Foundation

/// 会话 DAO
///
/// 负责会话表的数据库操作，支持 upsert、查询、置顶、免打扰等功能
nonisolated struct ConversationDAO: Sendable {
    /// 数据库 Actor
    private let database: DatabaseActor
    /// 账号存储路径
    private let paths: AccountStoragePaths

    init(database: DatabaseActor, paths: AccountStoragePaths) {
        self.database = database
        self.paths = paths
    }

    /// 插入或更新会话
    ///
    /// 使用 UPSERT 语法，存在则更新，不存在则插入
    ///
    /// - Parameter record: 会话记录
    /// - Throws: 数据库操作失败时抛出错误
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
                draft_text,
                is_pinned,
                is_muted,
                is_hidden,
                sort_ts,
                updated_at,
                created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                draft_text = excluded.draft_text,
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

    /// 查询会话列表
    ///
    /// 按置顶和排序时间戳降序排列，不包含隐藏的会话
    ///
    /// - Parameter userID: 用户 ID
    /// - Returns: 会话记录数组
    /// - Throws: 数据库查询失败时抛出错误
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
                draft_text,
                is_pinned,
                is_muted,
                is_hidden,
                sort_ts,
                updated_at,
                created_at
            FROM conversation
            WHERE user_id = ? AND is_hidden = 0
            ORDER BY is_pinned DESC, sort_ts DESC, conversation_id DESC;
            """,
            parameters: [.text(userID.rawValue)],
            paths: paths
        )

        return try rows.map(Self.record(from:))
    }

    /// 分页查询会话列表
    ///
    /// 按置顶、排序时间戳和会话 ID 降序排列，不包含隐藏的会话。使用游标分页避免新消息插入导致分页漂移。
    ///
    /// - Parameters:
    ///   - userID: 用户 ID
    ///   - limit: 查询数量
    ///   - cursor: 上一页最后一条会话的排序游标
    /// - Returns: 会话记录数组
    /// - Throws: 数据库查询失败时抛出错误
    func listConversations(for userID: UserID, limit: Int, after cursor: ConversationPageCursor?) async throws -> [ConversationRecord] {
        let cursorPredicate: String
        var parameters: [SQLiteValue] = [.text(userID.rawValue)]
        if let cursor {
            cursorPredicate = """

                AND (
                    is_pinned < ?
                    OR (is_pinned = ? AND sort_ts < ?)
                    OR (is_pinned = ? AND sort_ts = ? AND conversation_id < ?)
                )
            """
            let pinnedValue: Int64 = cursor.isPinned ? 1 : 0
            parameters.append(contentsOf: [
                .integer(pinnedValue),
                .integer(pinnedValue),
                .integer(cursor.sortTimestamp),
                .integer(pinnedValue),
                .integer(cursor.sortTimestamp),
                .text(cursor.conversationID.rawValue)
            ])
        } else {
            cursorPredicate = ""
        }
        parameters.append(.integer(Int64(max(limit, 0))))

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
                draft_text,
                is_pinned,
                is_muted,
                is_hidden,
                sort_ts,
                updated_at,
                created_at
            FROM conversation
            WHERE user_id = ? AND is_hidden = 0\(cursorPredicate)
            ORDER BY is_pinned DESC, sort_ts DESC, conversation_id DESC
            LIMIT ?;
            """,
            parameters: parameters,
            paths: paths
        )

        return try rows.map(Self.record(from:))
    }

    /// 统计会话数量
    ///
    /// - Parameter userID: 用户 ID
    /// - Returns: 会话数量
    /// - Throws: 数据库查询失败时抛出错误
    func countConversations(for userID: UserID) async throws -> Int {
        let rows = try await database.query(
            "SELECT COUNT(*) AS conversation_count FROM conversation WHERE user_id = ?;",
            parameters: [.text(userID.rawValue)],
            paths: paths
        )

        return try rows.first?.requiredInt("conversation_count") ?? 0
    }

    /// 标记会话已读
    ///
    /// 将未读数清零
    ///
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - userID: 用户 ID
    /// - Throws: 数据库操作失败时抛出错误
    func markRead(conversationID: ConversationID, userID: UserID) async throws {
        let statement = Self.markReadStatement(
            conversationID: conversationID,
            userID: userID,
            updatedAt: Self.currentTimestamp()
        )
        try await database.execute(
            statement.sql,
            parameters: statement.parameters,
            paths: paths
        )
    }

    /// 生成会话已读 SQL 语句
    ///
    /// 用于和消息已读状态在同一事务中提交。
    ///
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - userID: 用户 ID
    ///   - updatedAt: 更新时间戳
    /// - Returns: SQL 语句
    static func markReadStatement(conversationID: ConversationID, userID: UserID, updatedAt: Int64) -> SQLiteStatement {
        SQLiteStatement(
            """
            UPDATE conversation
            SET unread_count = 0, updated_at = ?
            WHERE conversation_id = ? AND user_id = ?;
            """,
            parameters: [
                .integer(updatedAt),
                .text(conversationID.rawValue),
                .text(userID.rawValue)
            ]
        )
    }

    /// 更新会话置顶状态
    ///
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - userID: 用户 ID
    ///   - isPinned: 是否置顶
    /// - Throws: 数据库操作失败时抛出错误
    func updatePin(conversationID: ConversationID, userID: UserID, isPinned: Bool) async throws {
        try await updateFlag(
            column: "is_pinned",
            value: isPinned,
            conversationID: conversationID,
            userID: userID
        )
    }

    /// 更新会话免打扰状态
    ///
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - userID: 用户 ID
    ///   - isMuted: 是否免打扰
    /// - Throws: 数据库操作失败时抛出错误
    func updateMute(conversationID: ConversationID, userID: UserID, isMuted: Bool) async throws {
        try await updateFlag(
            column: "is_muted",
            value: isMuted,
            conversationID: conversationID,
            userID: userID
        )
    }

    /// 更新会话标志位（通用方法）
    ///
    /// - Parameters:
    ///   - column: 列名
    ///   - value: 布尔值
    ///   - conversationID: 会话 ID
    ///   - userID: 用户 ID
    /// - Throws: 数据库操作失败时抛出错误
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

    /// 生成插入或更新会话的 SQL 语句
    ///
    /// 用于在事务中批量操作
    ///
    /// - Parameter record: 会话记录
    /// - Returns: SQL 语句
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
                draft_text,
                is_pinned,
                is_muted,
                is_hidden,
                sort_ts,
                updated_at,
                created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                draft_text = excluded.draft_text,
                is_pinned = excluded.is_pinned,
                is_muted = excluded.is_muted,
                is_hidden = excluded.is_hidden,
                sort_ts = excluded.sort_ts,
                updated_at = excluded.updated_at;
            """,
            parameters: parameters(for: record)
        )
    }

    /// 将会话记录转换为 SQL 参数数组
    ///
    /// - Parameter record: 会话记录
    /// - Returns: SQL 参数数组
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
            .optionalText(record.draftText),
            .integer(record.isPinned ? 1 : 0),
            .integer(record.isMuted ? 1 : 0),
            .integer(record.isHidden ? 1 : 0),
            .integer(record.sortTimestamp),
            .integer(record.updatedAt),
            .integer(record.createdAt)
        ]
    }

    /// 从数据库行构建会话记录
    ///
    /// - Parameter row: 数据库查询结果行
    /// - Returns: 会话记录
    /// - Throws: 数据格式错误时抛出错误
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
            draftText: row.string("draft_text"),
            isPinned: row.bool("is_pinned"),
            isMuted: row.bool("is_muted"),
            isHidden: row.bool("is_hidden"),
            sortTimestamp: try row.requiredInt64("sort_ts"),
            updatedAt: row.int64("updated_at") ?? 0,
            createdAt: row.int64("created_at") ?? 0
        )
    }

    /// 获取当前时间戳（秒）
    ///
    /// - Returns: Unix 时间戳
    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }
}
