//
//  SearchIndexActor.swift
//  AppleIM
//
//  Owns search.db FTS writes and rebuilds.

import Foundation

/// 搜索索引 Actor
///
/// 负责写入和查询 `search.db` 中的 FTS 表，并在失败时登记异步修复任务。
actor SearchIndexActor {
    /// 数据库访问 Actor
    private let database: DatabaseActor
    /// 当前账号的数据库路径集合
    private let paths: AccountStoragePaths

    /// 初始化搜索索引 Actor
    init(database: DatabaseActor, paths: AccountStoragePaths) {
        self.database = database
        self.paths = paths
    }

    /// 全量重建当前用户的联系人、会话和文本消息索引
    func rebuildAll(userID: UserID) async throws {
        let conversations = try await conversationIndexRows(userID: userID)
        let contacts = try await contactIndexRows(userID: userID)
        let messages = try await messageIndexRows(userID: userID)

        var statements = [
            SQLiteStatement("DELETE FROM contact_search;"),
            SQLiteStatement("DELETE FROM conversation_search;"),
            SQLiteStatement("DELETE FROM message_search;")
        ]

        statements += contacts.map(Self.upsertContactSearchStatement)
        statements += conversations.map(Self.upsertConversationSearchStatement)
        statements += messages.map(Self.upsertMessageSearchStatement)

        try await database.performTransaction(statements, in: .search, paths: paths)
    }

    /// 按关键词搜索联系人、会话和消息
    func search(query: String, limit: Int) async throws -> [SearchResultRecord] {
        let expression = Self.matchExpression(for: query)
        guard !expression.isEmpty else {
            return []
        }

        async let contacts = searchContacts(expression: expression, limit: limit)
        async let conversations = searchConversations(expression: expression, limit: limit)
        async let messages = searchMessages(expression: expression, limit: limit)

        return try await contacts + conversations + messages
    }

    /// 尽力为单条消息重建索引，失败时写入修复任务
    func indexMessageBestEffort(messageID: MessageID, userID: UserID) async {
        do {
            if let row = try await messageIndexRow(messageID: messageID, userID: userID) {
                try await database.performTransaction(
                    [
                        SQLiteStatement(
                            "DELETE FROM message_search WHERE message_id = ?;",
                            parameters: [.text(messageID.rawValue)]
                        ),
                        Self.upsertMessageSearchStatement(row)
                    ],
                    in: .search,
                    paths: paths
                )
            } else {
                try await removeMessage(messageID: messageID)
            }
        } catch {
            try? await enqueueRepairJob(
                userID: userID,
                scope: "message",
                messageID: messageID,
                conversationID: nil
            )
        }
    }

    /// 尽力移除单条消息索引，失败时写入修复任务
    func removeMessageBestEffort(messageID: MessageID, userID: UserID) async {
        do {
            try await removeMessage(messageID: messageID)
        } catch {
            try? await enqueueRepairJob(
                userID: userID,
                scope: "message",
                messageID: messageID,
                conversationID: nil
            )
        }
    }

    /// 尽力为单个会话重建索引，失败时写入修复任务
    func indexConversationBestEffort(conversationID: ConversationID, userID: UserID) async {
        do {
            if let row = try await conversationIndexRow(conversationID: conversationID, userID: userID) {
                try await database.performTransaction(
                    [
                        SQLiteStatement(
                            "DELETE FROM conversation_search WHERE conversation_id = ?;",
                            parameters: [.text(conversationID.rawValue)]
                        ),
                        Self.upsertConversationSearchStatement(row)
                    ],
                    in: .search,
                    paths: paths
                )
            }
        } catch {
            try? await enqueueRepairJob(
                userID: userID,
                scope: "conversation",
                messageID: nil,
                conversationID: conversationID
            )
        }
    }

    /// 从 FTS 消息索引中删除一条消息
    private func removeMessage(messageID: MessageID) async throws {
        try await database.execute(
            "DELETE FROM message_search WHERE message_id = ?;",
            parameters: [.text(messageID.rawValue)],
            in: .search,
            paths: paths
        )
    }

    /// 搜索联系人索引表
    private func searchContacts(expression: String, limit: Int) async throws -> [SearchResultRecord] {
        let rows = try await database.query(
            """
            SELECT contact_id, title, subtitle
            FROM contact_search
            WHERE contact_search MATCH ?
            ORDER BY rank
            LIMIT ?;
            """,
            parameters: [.text(expression), .integer(Int64(limit))],
            in: .search,
            paths: paths
        )

        return rows.map {
            SearchResultRecord(
                kind: .contact,
                id: $0.string("contact_id") ?? "",
                title: $0.string("title") ?? "",
                subtitle: $0.string("subtitle") ?? "",
                conversationID: nil,
                messageID: nil
            )
        }
    }

    /// 搜索会话索引表
    private func searchConversations(expression: String, limit: Int) async throws -> [SearchResultRecord] {
        let rows = try await database.query(
            """
            SELECT conversation_id, title, subtitle
            FROM conversation_search
            WHERE conversation_search MATCH ?
            ORDER BY rank
            LIMIT ?;
            """,
            parameters: [.text(expression), .integer(Int64(limit))],
            in: .search,
            paths: paths
        )

        return rows.map {
            let conversationID = ConversationID(rawValue: $0.string("conversation_id") ?? "")
            return SearchResultRecord(
                kind: .conversation,
                id: conversationID.rawValue,
                title: $0.string("title") ?? "",
                subtitle: $0.string("subtitle") ?? "",
                conversationID: conversationID,
                messageID: nil
            )
        }
    }

    /// 搜索文本消息索引表
    private func searchMessages(expression: String, limit: Int) async throws -> [SearchResultRecord] {
        let rows = try await database.query(
            """
            SELECT message_id, conversation_id, sender_id, text
            FROM message_search
            WHERE message_search MATCH ?
            ORDER BY rank
            LIMIT ?;
            """,
            parameters: [.text(expression), .integer(Int64(limit))],
            in: .search,
            paths: paths
        )

        return rows.map {
            let messageID = MessageID(rawValue: $0.string("message_id") ?? "")
            let conversationID = ConversationID(rawValue: $0.string("conversation_id") ?? "")
            return SearchResultRecord(
                kind: .message,
                id: messageID.rawValue,
                title: $0.string("text") ?? "",
                subtitle: $0.string("sender_id") ?? "",
                conversationID: conversationID,
                messageID: messageID
            )
        }
    }

    /// 生成当前用户可写入联系人索引的行数据
    private func contactIndexRows(userID: UserID) async throws -> [ContactIndexRow] {
        let rows = try await database.query(
            """
            SELECT contact_id, COALESCE(NULLIF(remark, ''), nickname, wxid) AS title, wxid AS subtitle
            FROM contact
            WHERE user_id = ? AND is_deleted = 0;
            """,
            parameters: [.text(userID.rawValue)],
            paths: paths
        )

        return rows.compactMap { row in
            guard let id = row.string("contact_id") else { return nil }
            return ContactIndexRow(
                id: id,
                title: row.string("title") ?? "",
                subtitle: row.string("subtitle") ?? ""
            )
        }
    }

    /// 生成当前用户可写入会话索引的行数据
    private func conversationIndexRows(userID: UserID) async throws -> [ConversationIndexRow] {
        let rows = try await database.query(
            """
            SELECT conversation_id, COALESCE(title, target_id) AS title, COALESCE(draft_text, last_message_digest, '') AS subtitle
            FROM conversation
            WHERE user_id = ? AND is_hidden = 0;
            """,
            parameters: [.text(userID.rawValue)],
            paths: paths
        )

        return rows.compactMap { row in
            guard let id = row.string("conversation_id") else { return nil }
            return ConversationIndexRow(
                id: ConversationID(rawValue: id),
                title: row.string("title") ?? "",
                subtitle: row.string("subtitle") ?? ""
            )
        }
    }

    /// 查询单个会话当前可写入索引的行数据
    private func conversationIndexRow(conversationID: ConversationID, userID: UserID) async throws -> ConversationIndexRow? {
        let rows = try await database.query(
            """
            SELECT conversation_id, COALESCE(title, target_id) AS title, COALESCE(draft_text, last_message_digest, '') AS subtitle
            FROM conversation
            WHERE conversation_id = ? AND user_id = ? AND is_hidden = 0
            LIMIT 1;
            """,
            parameters: [.text(conversationID.rawValue), .text(userID.rawValue)],
            paths: paths
        )

        guard let row = rows.first else {
            return nil
        }

        return ConversationIndexRow(
            id: conversationID,
            title: row.string("title") ?? "",
            subtitle: row.string("subtitle") ?? ""
        )
    }

    /// 生成当前用户可写入文本消息索引的行数据
    private func messageIndexRows(userID: UserID) async throws -> [MessageIndexRow] {
        let rows = try await database.query(
            """
            SELECT message.message_id, message.conversation_id, message.sender_id, message_text.text
            FROM message
            INNER JOIN conversation ON conversation.conversation_id = message.conversation_id
            INNER JOIN message_text ON message_text.content_id = message.content_id
            WHERE conversation.user_id = ?
            AND message.msg_type = ?
            AND message.is_deleted = 0
            AND message.revoke_status = 0;
            """,
            parameters: [
                .text(userID.rawValue),
                .integer(Int64(MessageType.text.rawValue))
            ],
            paths: paths
        )

        return rows.compactMap(Self.messageIndexRow)
    }

    /// 查询单条消息当前可写入索引的行数据
    private func messageIndexRow(messageID: MessageID, userID: UserID) async throws -> MessageIndexRow? {
        let rows = try await database.query(
            """
            SELECT message.message_id, message.conversation_id, message.sender_id, message_text.text
            FROM message
            INNER JOIN conversation ON conversation.conversation_id = message.conversation_id
            INNER JOIN message_text ON message_text.content_id = message.content_id
            WHERE conversation.user_id = ?
            AND message.message_id = ?
            AND message.msg_type = ?
            AND message.is_deleted = 0
            AND message.revoke_status = 0
            LIMIT 1;
            """,
            parameters: [
                .text(userID.rawValue),
                .text(messageID.rawValue),
                .integer(Int64(MessageType.text.rawValue))
            ],
            paths: paths
        )

        return rows.first.flatMap(Self.messageIndexRow)
    }

    /// 将索引失败的对象登记为待处理修复任务
    private func enqueueRepairJob(
        userID: UserID,
        scope: String,
        messageID: MessageID?,
        conversationID: ConversationID?
    ) async throws {
        let payload = SearchIndexRepairPendingJobPayload(
            scope: scope,
            messageID: messageID?.rawValue,
            conversationID: conversationID?.rawValue
        )
        let payloadJSON = try PendingJobPayload.searchIndexRepair(payload).encodedJSON()
        let now = Int64(Date().timeIntervalSince1970)
        let bizKey = [scope, messageID?.rawValue, conversationID?.rawValue]
            .compactMap { $0 }
            .joined(separator: ":")
        let jobID = "search_index_repair_\(bizKey)"

        try await database.execute(
            """
            INSERT INTO pending_job (
                job_id,
                user_id,
                job_type,
                biz_key,
                payload_json,
                status,
                retry_count,
                max_retry_count,
                next_retry_at,
                updated_at,
                created_at
            ) VALUES (?, ?, ?, ?, ?, ?, 0, 3, NULL, ?, ?)
            ON CONFLICT(job_id) DO UPDATE SET
                payload_json = excluded.payload_json,
                status = excluded.status,
                updated_at = excluded.updated_at;
            """,
            parameters: [
                .text(jobID),
                .text(userID.rawValue),
                .integer(Int64(PendingJobType.searchIndexRepair.rawValue)),
                .text(bizKey),
                .text(payloadJSON),
                .integer(Int64(PendingJobStatus.pending.rawValue)),
                .integer(now),
                .integer(now)
            ],
            paths: paths
        )
    }

    /// 将用户输入转换为 SQLite FTS MATCH 表达式
    private static func matchExpression(for query: String) -> String {
        var tokens: [String] = []

        for rawToken in query.split(whereSeparator: \.isWhitespace) {
            var scalars = String.UnicodeScalarView()

            for scalar in rawToken.unicodeScalars {
                if scalar.properties.isAlphabetic || scalar.properties.numericType != nil || scalar.value == 95 {
                    scalars.append(scalar)
                }
            }

            guard !scalars.isEmpty else {
                continue
            }

            tokens.append(String(scalars) + "*")

            if tokens.count == 6 {
                break
            }
        }

        return tokens.joined(separator: " ")
    }

    /// 将数据库行转换为消息索引行
    private static func messageIndexRow(from row: SQLiteRow) -> MessageIndexRow? {
        guard
            let messageID = row.string("message_id"),
            let conversationID = row.string("conversation_id"),
            let senderID = row.string("sender_id")
        else {
            return nil
        }

        return MessageIndexRow(
            id: MessageID(rawValue: messageID),
            conversationID: ConversationID(rawValue: conversationID),
            senderID: UserID(rawValue: senderID),
            text: row.string("text") ?? ""
        )
    }

    /// 构造联系人索引 upsert 语句
    private static func upsertContactSearchStatement(_ row: ContactIndexRow) -> SQLiteStatement {
        SQLiteStatement(
            """
            INSERT INTO contact_search (contact_id, title, subtitle)
            VALUES (?, ?, ?);
            """,
            parameters: [.text(row.id), .text(row.title), .text(row.subtitle)]
        )
    }

    /// 构造会话索引 upsert 语句
    private static func upsertConversationSearchStatement(_ row: ConversationIndexRow) -> SQLiteStatement {
        SQLiteStatement(
            """
            INSERT INTO conversation_search (conversation_id, title, subtitle)
            VALUES (?, ?, ?);
            """,
            parameters: [.text(row.id.rawValue), .text(row.title), .text(row.subtitle)]
        )
    }

    /// 构造消息索引 upsert 语句
    private static func upsertMessageSearchStatement(_ row: MessageIndexRow) -> SQLiteStatement {
        SQLiteStatement(
            """
            INSERT INTO message_search (message_id, conversation_id, sender_id, text)
            VALUES (?, ?, ?, ?);
            """,
            parameters: [
                .text(row.id.rawValue),
                .text(row.conversationID.rawValue),
                .text(row.senderID.rawValue),
                .text(row.text)
            ]
        )
    }
}

/// 联系人搜索索引行
nonisolated private struct ContactIndexRow: Equatable, Sendable {
    /// 联系人 ID
    let id: String
    /// 搜索标题
    let title: String
    /// 搜索副标题
    let subtitle: String
}

/// 会话搜索索引行
nonisolated private struct ConversationIndexRow: Equatable, Sendable {
    /// 会话 ID
    let id: ConversationID
    /// 搜索标题
    let title: String
    /// 搜索副标题
    let subtitle: String
}

/// 消息搜索索引行
nonisolated private struct MessageIndexRow: Equatable, Sendable {
    /// 消息 ID
    let id: MessageID
    /// 所属会话 ID
    let conversationID: ConversationID
    /// 发送者 ID
    let senderID: UserID
    /// 可检索文本
    let text: String
}
