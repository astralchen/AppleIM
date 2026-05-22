//
//  SearchIndexActor.swift
//  AppleIM
//
//  Owns search.db FTS writes and rebuilds.

import Foundation
import GRDB

/// 联系人 FTS 搜索结果行。
nonisolated private struct ContactSearchResultRow: FetchableRecord, Sendable {
    let result: SearchResultRecord

    init(row: Row) throws {
        result = SearchResultRecord(
            kind: .contact,
            id: row["contact_id"] ?? "",
            title: row["title"] ?? "",
            subtitle: row["subtitle"] ?? "",
            conversationID: nil,
            messageID: nil
        )
    }
}

/// 会话 FTS 搜索结果行。
nonisolated private struct ConversationSearchResultRow: FetchableRecord, Sendable {
    let result: SearchResultRecord

    init(row: Row) throws {
        let rawConversationID: String = row["conversation_id"] ?? ""
        let conversationID = ConversationID(rawValue: rawConversationID)
        result = SearchResultRecord(
            kind: .conversation,
            id: conversationID.rawValue,
            title: row["title"] ?? "",
            subtitle: row["subtitle"] ?? "",
            conversationID: conversationID,
            messageID: nil
        )
    }
}

/// 文本消息 FTS 搜索结果行。
nonisolated private struct MessageSearchResultRow: FetchableRecord, Sendable {
    let result: SearchResultRecord

    init(row: Row) throws {
        let rawMessageID: String = row["message_id"] ?? ""
        let rawConversationID: String = row["conversation_id"] ?? ""
        let messageID = MessageID(rawValue: rawMessageID)
        let conversationID = ConversationID(rawValue: rawConversationID)
        result = SearchResultRecord(
            kind: .message,
            id: messageID.rawValue,
            title: row["text"] ?? "",
            subtitle: row["sender_id"] ?? "",
            conversationID: conversationID,
            messageID: messageID
        )
    }
}

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

        _ = try await database.write(in: .search, paths: paths) { db in
            try Table("contact_search").deleteAll(db)
            try Table("conversation_search").deleteAll(db)
            try Table("message_search").deleteAll(db)

            for row in contacts {
                try ContactSearchDatabaseRecord(row: row).insert(db)
            }
            for row in conversations {
                try ConversationSearchDatabaseRecord(row: row).insert(db)
            }
            for row in messages {
                try MessageSearchDatabaseRecord(row: row).insert(db)
            }
        }
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
                _ = try await database.write(in: .search, paths: paths) { db in
                    try Table("message_search")
                        .filter(Column("message_id") == messageID.rawValue)
                        .deleteAll(db)
                    try MessageSearchDatabaseRecord(row: row).insert(db)
                }
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
                _ = try await database.write(in: .search, paths: paths) { db in
                    try Table("conversation_search")
                        .filter(Column("conversation_id") == conversationID.rawValue)
                        .deleteAll(db)
                    try ConversationSearchDatabaseRecord(row: row).insert(db)
                }
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
        _ = try await database.write(in: .search, paths: paths) { db in
            try Table("message_search")
                .filter(Column("message_id") == messageID.rawValue)
                .deleteAll(db)
        }
    }

    /// 搜索联系人索引表
    private func searchContacts(expression: String, limit: Int) async throws -> [SearchResultRecord] {
        try await database.read(in: .search, paths: paths) { db in
            try ContactSearchResultRow.fetchAll(
                db,
                // 保留 FTS MATCH 手写 SQL：Query Interface 不覆盖 FTS 排名语义。
                sql: """
                SELECT contact_id, title, subtitle
                FROM contact_search
                WHERE contact_search MATCH ?
                ORDER BY rank
                LIMIT ?;
                """,
                arguments: [expression, Int64(limit)]
            )
            .map(\.result)
        }
    }

    /// 搜索会话索引表
    private func searchConversations(expression: String, limit: Int) async throws -> [SearchResultRecord] {
        try await database.read(in: .search, paths: paths) { db in
            try ConversationSearchResultRow.fetchAll(
                db,
                // 保留 FTS MATCH 手写 SQL：Query Interface 不覆盖 FTS 排名语义。
                sql: """
                SELECT conversation_id, title, subtitle
                FROM conversation_search
                WHERE conversation_search MATCH ?
                ORDER BY rank
                LIMIT ?;
                """,
                arguments: [expression, Int64(limit)]
            )
            .map(\.result)
        }
    }

    /// 搜索文本消息索引表
    private func searchMessages(expression: String, limit: Int) async throws -> [SearchResultRecord] {
        try await database.read(in: .search, paths: paths) { db in
            try MessageSearchResultRow.fetchAll(
                db,
                // 保留 FTS MATCH 手写 SQL：Query Interface 不覆盖 FTS 排名语义。
                sql: """
                SELECT message_id, conversation_id, sender_id, text
                FROM message_search
                WHERE message_search MATCH ?
                ORDER BY rank
                LIMIT ?;
                """,
                arguments: [expression, Int64(limit)]
            )
            .map(\.result)
        }
    }

    /// 生成当前用户可写入联系人索引的行数据
    private func contactIndexRows(userID: UserID) async throws -> [ContactIndexRow] {
        try await database.read(paths: paths) { db in
            try ContactDatabaseRecord
                .filter(ContactDatabaseRecord.Columns.userID == userID.rawValue)
                .filter(ContactDatabaseRecord.Columns.isDeleted == false)
                .fetchAll(db)
                .map(\.record)
                .map { record in
                    ContactIndexRow(
                        id: record.contactID.rawValue,
                        title: record.displayName,
                        subtitle: record.wxid
                    )
                }
        }
    }

    /// 生成当前用户可写入会话索引的行数据
    private func conversationIndexRows(userID: UserID) async throws -> [ConversationIndexRow] {
        try await database.read(paths: paths) { db in
            try ConversationDatabaseRecord
                .filter(ConversationDatabaseRecord.Columns.userID == userID.rawValue)
                .filter(ConversationDatabaseRecord.Columns.isHidden == false)
                .fetchAll(db)
                .map(\.record)
                .map { record in
                    ConversationIndexRow(
                        id: record.id,
                        title: record.title.isEmpty ? record.targetID : record.title,
                        subtitle: record.draftText ?? record.lastMessageDigest
                    )
                }
        }
    }

    /// 查询单个会话当前可写入索引的行数据
    private func conversationIndexRow(conversationID: ConversationID, userID: UserID) async throws -> ConversationIndexRow? {
        let record = try await database.read(paths: paths) { db in
            try ConversationDatabaseRecord
                .filter(ConversationDatabaseRecord.Columns.conversationID == conversationID.rawValue)
                .filter(ConversationDatabaseRecord.Columns.userID == userID.rawValue)
                .filter(ConversationDatabaseRecord.Columns.isHidden == false)
                .fetchOne(db)?
                .record
        }

        guard let record else {
            return nil
        }

        return ConversationIndexRow(
            id: record.id,
            title: record.title.isEmpty ? record.targetID : record.title,
            subtitle: record.draftText ?? record.lastMessageDigest
        )
    }

    /// 生成当前用户可写入文本消息索引的行数据
    ///
    /// 这里保留手写 SQL：需要跨 message、conversation、message_text 三表过滤，
    /// 且和 FTS 重建的批量路径强相关，Query Interface 版本可读性更差。
    private func messageIndexRows(userID: UserID) async throws -> [MessageIndexRow] {
        try await database.read(paths: paths) { db in
            try MessageIndexDatabaseRecord.fetchAll(
                db,
                sql: """
                SELECT message.message_id, message.conversation_id, message.sender_id, message_text.text
                FROM message
                INNER JOIN conversation ON conversation.conversation_id = message.conversation_id
                INNER JOIN message_text ON message_text.content_id = message.content_id
                WHERE conversation.user_id = ?
                AND message.msg_type = ?
                AND message.is_deleted = 0
                AND message.revoke_status = 0;
                """,
                arguments: [userID.rawValue, MessageType.text.rawValue]
            )
            .map(\.row)
        }
    }

    /// 查询单条消息当前可写入索引的行数据
    ///
    /// 这里保留手写 SQL，理由同批量重建：跨表条件集中，且只为 FTS 索引源服务。
    private func messageIndexRow(messageID: MessageID, userID: UserID) async throws -> MessageIndexRow? {
        try await database.read(paths: paths) { db in
            try MessageIndexDatabaseRecord.fetchOne(
                db,
                sql: """
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
                arguments: [userID.rawValue, messageID.rawValue, MessageType.text.rawValue]
            )?
            .row
        }
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

        _ = try await database.write(paths: paths) { db in
            let job = PendingJob(
                id: jobID,
                userID: userID,
                type: .searchIndexRepair,
                bizKey: bizKey,
                payloadJSON: payloadJSON,
                status: .pending,
                retryCount: 0,
                maxRetryCount: 3,
                nextRetryAt: nil,
                updatedAt: now,
                createdAt: now
            )
            try PendingJobDatabaseRecord.upsertRepairJob(job, in: db)
        }
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

/// 文本消息索引源查询行。
nonisolated private struct MessageIndexDatabaseRecord: FetchableRecord, Sendable {
    let row: MessageIndexRow

    init(row: Row) throws {
        self.row = MessageIndexRow(
            id: MessageID(rawValue: row["message_id"]),
            conversationID: ConversationID(rawValue: row["conversation_id"]),
            senderID: UserID(rawValue: row["sender_id"]),
            text: row["text"] ?? ""
        )
    }
}

/// contact_search FTS 写入模型。
nonisolated private struct ContactSearchDatabaseRecord: PersistableRecord, Sendable {
    static let databaseTableName = "contact_search"

    let row: ContactIndexRow

    func encode(to container: inout PersistenceContainer) throws {
        container["contact_id"] = row.id
        container["title"] = row.title
        container["subtitle"] = row.subtitle
    }
}

/// conversation_search FTS 写入模型。
nonisolated private struct ConversationSearchDatabaseRecord: PersistableRecord, Sendable {
    static let databaseTableName = "conversation_search"

    let row: ConversationIndexRow

    func encode(to container: inout PersistenceContainer) throws {
        container["conversation_id"] = row.id.rawValue
        container["title"] = row.title
        container["subtitle"] = row.subtitle
    }
}

/// message_search FTS 写入模型。
nonisolated private struct MessageSearchDatabaseRecord: PersistableRecord, Sendable {
    static let databaseTableName = "message_search"

    let row: MessageIndexRow

    func encode(to container: inout PersistenceContainer) throws {
        container["message_id"] = row.id.rawValue
        container["conversation_id"] = row.conversationID.rawValue
        container["sender_id"] = row.senderID.rawValue
        container["text"] = row.text
    }
}
