//
//  DatabaseSchema.swift
//  AppleIM
//
//  当前数据库基线 Schema。
//

import Foundation
import GRDB

/// 数据库文件类型
///
/// 项目使用多个 SQLite 数据库文件分离不同类型的数据
nonisolated enum DatabaseFileKind: String, Codable, CaseIterable, Sendable {
    /// 主数据库（用户、会话、消息等核心数据）
    case main
    /// 搜索数据库（FTS 全文搜索索引）
    case search
    /// 文件索引数据库（媒体文件元数据）
    case fileIndex
}

/// 数据库 Schema
///
/// 定义当前完整基线，不维护历史迁移链。
///
/// ## 重要说明
///
/// - 所有表都使用 TEXT 类型存储 ID，便于跨平台兼容
/// - 时间戳统一使用 INTEGER 存储毫秒级 Unix 时间戳
/// - 消息表和内容表分离，支持多种消息类型扩展
/// - 使用 sort_seq 字段统一排序，避免依赖时间戳
nonisolated enum DatabaseSchema {
    /// 当前 Schema 版本。
    static let currentVersion = 9

    /// 每个数据库必须存在的核心表。
    static let requiredTables: [DatabaseFileKind: Set<String>] = [
        .main: [
            "user",
            "contact",
            "conversation",
            "conversation_member",
            "message",
            "message_text",
            "message_image",
            "message_voice",
            "message_video",
            "message_file",
            "message_emoji",
            "message_revoke",
            "media_resource",
            "draft",
            "pending_job",
            "sync_checkpoint",
            "notification_setting",
            "emoji_package",
            "emoji_store"
        ],
        .search: [
            "contact_search",
            "conversation_search",
            "message_search"
        ],
        .fileIndex: [
            "file_index"
        ]
    ]

    /// 用少量关键字段识别旧 schema；不做补列，缺字段即重建。
    static let requiredColumns: [DatabaseFileKind: [String: Set<String>]] = [
        .main: [
            "notification_setting": ["user_id", "badge_enabled", "badge_include_muted"],
            "message": ["message_id", "conversation_id", "content_table", "content_id", "sort_seq"],
            "message_voice": ["content_id", "played_at"],
            "conversation": ["conversation_id", "user_id", "sort_ts"],
            "media_resource": ["media_id", "owner_message_id", "updated_at"],
            "pending_job": ["job_id", "user_id", "status", "next_retry_at"]
        ],
        .search: [
            "contact_search": ["contact_id", "title", "subtitle"],
            "conversation_search": ["conversation_id", "title", "subtitle"],
            "message_search": ["message_id", "conversation_id", "sender_id", "text"]
        ],
        .fileIndex: [
            "file_index": ["media_id", "user_id", "last_access_at"]
        ]
    ]

    /// 应用当前完整基线 schema。
    static func applyBaseline(to db: Database, kind: DatabaseFileKind) throws {
        switch kind {
        case .main:
            try applyMainBaseline(to: db)
        case .search:
            try applySearchBaseline(to: db)
        case .fileIndex:
            try applyFileIndexBaseline(to: db)
        }
    }
}

private extension DatabaseSchema {
    nonisolated static func applyMainBaseline(to db: Database) throws {
        try createMainTables(in: db)
        try createMainIndexes(in: db)
    }

    nonisolated static func applySearchBaseline(to db: Database) throws {
        try db.create(table: "search_index_meta", options: .ifNotExists) { table in
            table.primaryKey("key", .text)
            table.column("value", .text)
            table.column("updated_at", .integer)
        }
        try createSearchFTSTables(in: db)
    }

    nonisolated static func applyFileIndexBaseline(to db: Database) throws {
        try db.create(table: "file_index", options: .ifNotExists) { table in
            table.primaryKey("media_id", .text)
            table.column("user_id", .text).notNull()
            table.column("local_path", .text).notNull()
            table.column("file_name", .text)
            table.column("file_ext", .text)
            table.column("size_bytes", .integer)
            table.column("md5", .text)
            table.column("last_access_at", .integer)
            table.column("created_at", .integer)
        }
        try createIndex(db, "idx_file_index_user", on: "file_index", columns: ["user_id", "last_access_at"])
    }

    nonisolated static func createMainTables(in db: Database) throws {
        try db.create(table: "user", options: .ifNotExists) { table in
            table.primaryKey("user_id", .text)
            table.column("wxid", .text).unique()
            table.column("nickname", .text)
            table.column("avatar_url", .text)
            table.column("gender", .integer)
            table.column("region", .text)
            table.column("signature", .text)
            table.column("remark", .text)
            table.column("mobile", .text)
            table.column("extra_json", .text)
            table.column("updated_at", .integer)
            table.column("created_at", .integer)
        }

        try db.create(table: "contact", options: .ifNotExists) { table in
            table.primaryKey("contact_id", .text)
            table.column("user_id", .text).notNull()
            table.column("wxid", .text).notNull()
            table.column("nickname", .text)
            table.column("remark", .text)
            table.column("avatar_url", .text)
            table.column("type", .integer).notNull()
            table.column("is_starred", .integer).defaults(to: 0)
            table.column("is_blocked", .integer).defaults(to: 0)
            table.column("is_deleted", .integer).defaults(to: 0)
            table.column("source", .integer)
            table.column("extra_json", .text)
            table.column("updated_at", .integer)
            table.column("created_at", .integer)
        }

        try db.create(table: "conversation", options: .ifNotExists) { table in
            table.primaryKey("conversation_id", .text)
            table.column("user_id", .text).notNull()
            table.column("biz_type", .integer).notNull()
            table.column("target_id", .text).notNull()
            table.column("title", .text)
            table.column("avatar_url", .text)
            table.column("last_message_id", .text)
            table.column("last_message_time", .integer)
            table.column("last_message_digest", .text)
            table.column("unread_count", .integer).defaults(to: 0)
            table.column("draft_text", .text)
            table.column("is_pinned", .integer).defaults(to: 0)
            table.column("is_muted", .integer).defaults(to: 0)
            table.column("is_hidden", .integer).defaults(to: 0)
            table.column("sort_ts", .integer).notNull()
            table.column("extra_json", .text)
            table.column("updated_at", .integer)
            table.column("created_at", .integer)
        }

        try db.create(table: "conversation_member", options: .ifNotExists) { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("conversation_id", .text).notNull()
            table.column("member_id", .text).notNull()
            table.column("display_name", .text)
            table.column("role", .integer).defaults(to: 0)
            table.column("join_time", .integer)
            table.column("extra_json", .text)
            table.uniqueKey(["conversation_id", "member_id"])
        }

        try db.create(table: "message", options: .ifNotExists) { table in
            table.primaryKey("message_id", .text)
            table.column("local_id", .integer).unique()
            table.column("conversation_id", .text).notNull()
            table.column("sender_id", .text).notNull()
            table.column("client_msg_id", .text).unique()
            table.column("server_msg_id", .text)
            table.column("seq", .integer)
            table.column("msg_type", .integer).notNull()
            table.column("direction", .integer).notNull()
            table.column("send_status", .integer).notNull()
            table.column("delivery_status", .integer).defaults(to: 0)
            table.column("read_status", .integer).defaults(to: 0)
            table.column("revoke_status", .integer).defaults(to: 0)
            table.column("is_deleted", .integer).defaults(to: 0)
            table.column("quoted_message_id", .text)
            table.column("reply_to_message_id", .text)
            table.column("content_table", .text)
            table.column("content_id", .text)
            table.column("sort_seq", .integer).notNull()
            table.column("server_time", .integer)
            table.column("local_time", .integer).notNull()
            table.column("edit_version", .integer).defaults(to: 0)
            table.column("extra_json", .text)
        }

        try db.create(table: "message_text", options: .ifNotExists) { table in
            table.primaryKey("content_id", .text)
            table.column("text", .text).notNull()
            table.column("mentions_json", .text)
            table.column("at_all", .integer).defaults(to: 0)
            table.column("rich_text_json", .text)
        }

        try db.create(table: "message_image", options: .ifNotExists) { table in
            table.primaryKey("content_id", .text)
            table.column("media_id", .text)
            table.column("width", .integer)
            table.column("height", .integer)
            table.column("size_bytes", .integer)
            table.column("local_path", .text)
            table.column("thumb_path", .text)
            table.column("cdn_url", .text)
            table.column("md5", .text)
            table.column("format", .text)
            table.column("upload_status", .integer).defaults(to: 0)
            table.column("download_status", .integer).defaults(to: 0)
        }

        try db.create(table: "message_voice", options: .ifNotExists) { table in
            table.primaryKey("content_id", .text)
            table.column("media_id", .text)
            table.column("duration_ms", .integer)
            table.column("size_bytes", .integer)
            table.column("local_path", .text)
            table.column("cdn_url", .text)
            table.column("format", .text)
            table.column("transcript", .text)
            table.column("played_at", .integer)
            table.column("upload_status", .integer).defaults(to: 0)
            table.column("download_status", .integer).defaults(to: 0)
        }

        try db.create(table: "message_video", options: .ifNotExists) { table in
            table.primaryKey("content_id", .text)
            table.column("media_id", .text)
            table.column("duration_ms", .integer)
            table.column("width", .integer)
            table.column("height", .integer)
            table.column("size_bytes", .integer)
            table.column("local_path", .text)
            table.column("thumb_path", .text)
            table.column("cdn_url", .text)
            table.column("md5", .text)
            table.column("upload_status", .integer).defaults(to: 0)
            table.column("download_status", .integer).defaults(to: 0)
        }

        try db.create(table: "message_file", options: .ifNotExists) { table in
            table.primaryKey("content_id", .text)
            table.column("media_id", .text)
            table.column("file_name", .text)
            table.column("file_ext", .text)
            table.column("size_bytes", .integer)
            table.column("local_path", .text)
            table.column("cdn_url", .text)
            table.column("md5", .text)
            table.column("upload_status", .integer).defaults(to: 0)
            table.column("download_status", .integer).defaults(to: 0)
        }

        try db.create(table: "message_receipt", options: .ifNotExists) { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("message_id", .text).notNull()
            table.column("user_id", .text).notNull()
            table.column("receipt_type", .integer).notNull()
            table.column("receipt_time", .integer)
            table.uniqueKey(["message_id", "user_id", "receipt_type"])
        }

        try db.create(table: "message_revoke", options: .ifNotExists) { table in
            table.primaryKey("message_id", .text)
            table.column("operator_id", .text).notNull()
            table.column("revoke_time", .integer).notNull()
            table.column("reason", .text)
            table.column("replace_text", .text)
        }

        try db.create(table: "media_resource", options: .ifNotExists) { table in
            table.primaryKey("media_id", .text)
            table.column("user_id", .text).notNull()
            table.column("owner_message_id", .text)
            table.column("local_path", .text)
            table.column("remote_url", .text)
            table.column("thumb_path", .text)
            table.column("size_bytes", .integer)
            table.column("md5", .text)
            table.column("upload_status", .integer).defaults(to: 0)
            table.column("download_status", .integer).defaults(to: 0)
            table.column("updated_at", .integer)
            table.column("created_at", .integer)
        }

        try db.create(table: "draft", options: .ifNotExists) { table in
            table.primaryKey("conversation_id", .text)
            table.column("text", .text)
            table.column("updated_at", .integer)
        }

        try db.create(table: "sync_checkpoint", options: .ifNotExists) { table in
            table.primaryKey("biz_key", .text)
            table.column("cursor", .text)
            table.column("seq", .integer)
            table.column("updated_at", .integer)
        }

        try db.create(table: "pending_job", options: .ifNotExists) { table in
            table.primaryKey("job_id", .text)
            table.column("user_id", .text).notNull()
            table.column("job_type", .integer).notNull()
            table.column("biz_key", .text)
            table.column("payload_json", .text)
            table.column("status", .integer).notNull()
            table.column("retry_count", .integer).defaults(to: 0)
            table.column("max_retry_count", .integer).defaults(to: 3)
            table.column("next_retry_at", .integer)
            table.column("updated_at", .integer)
            table.column("created_at", .integer)
        }

        try db.create(table: "conversation_setting", options: .ifNotExists) { table in
            table.primaryKey("conversation_id", .text)
            table.column("user_id", .text).notNull()
            table.column("is_pinned", .integer).defaults(to: 0)
            table.column("is_muted", .integer).defaults(to: 0)
            table.column("updated_at", .integer)
        }

        try db.create(table: "notification_setting", options: .ifNotExists) { table in
            table.primaryKey("user_id", .text)
            table.column("is_enabled", .integer).defaults(to: 1)
            table.column("show_preview", .integer).defaults(to: 1)
            table.column("badge_enabled", .integer).defaults(to: 1)
            table.column("badge_include_muted", .integer).defaults(to: 1)
            table.column("updated_at", .integer)
        }

        try db.create(table: "blacklist", options: .ifNotExists) { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("user_id", .text).notNull()
            table.column("blocked_user_id", .text).notNull()
            table.column("created_at", .integer)
            table.uniqueKey(["user_id", "blocked_user_id"])
        }

        try db.create(table: "emoji_package", options: .ifNotExists) { table in
            table.primaryKey("package_id", .text)
            table.column("user_id", .text).notNull()
            table.column("title", .text).notNull()
            table.column("author", .text)
            table.column("cover_url", .text)
            table.column("local_cover_path", .text)
            table.column("version", .integer).defaults(to: 0)
            table.column("status", .integer).defaults(to: 0)
            table.column("sort_order", .integer).defaults(to: 0)
            table.column("created_at", .integer)
            table.column("updated_at", .integer)
        }

        try db.create(table: "emoji_store", options: .ifNotExists) { table in
            table.primaryKey("emoji_id", .text)
            table.column("user_id", .text).notNull()
            table.column("package_id", .text)
            table.column("emoji_type", .integer).notNull()
            table.column("name", .text)
            table.column("md5", .text)
            table.column("local_path", .text)
            table.column("thumb_path", .text)
            table.column("cdn_url", .text)
            table.column("width", .integer)
            table.column("height", .integer)
            table.column("size_bytes", .integer)
            table.column("use_count", .integer).defaults(to: 0)
            table.column("last_used_at", .integer)
            table.column("is_favorite", .integer).defaults(to: 0)
            table.column("is_deleted", .integer).defaults(to: 0)
            table.column("extra_json", .text)
            table.column("created_at", .integer)
            table.column("updated_at", .integer)
        }

        try db.create(table: "message_emoji", options: .ifNotExists) { table in
            table.primaryKey("content_id", .text)
            table.column("emoji_id", .text).notNull()
            table.column("package_id", .text)
            table.column("emoji_type", .integer).notNull()
            table.column("name", .text)
            table.column("local_path", .text)
            table.column("thumb_path", .text)
            table.column("cdn_url", .text)
            table.column("width", .integer)
            table.column("height", .integer)
            table.column("size_bytes", .integer)
        }
    }

    nonisolated static func createMainIndexes(in db: Database) throws {
        try createIndex(db, "idx_contact_user_wxid", on: "contact", columns: ["user_id", "wxid"])
        try createIndex(db, "idx_contact_user_updated", on: "contact", columns: ["user_id", "updated_at"])
        try createIndex(
            db,
            "idx_contact_user_type_name",
            on: "contact",
            columns: ["user_id", "is_deleted", "type", "is_starred", "remark", "nickname", "wxid"]
        )
        try createIndex(db, "idx_conversation_user_sort", on: "conversation", columns: ["user_id", "is_pinned", "sort_ts"])
        try createIndex(
            db,
            "idx_conversation_user_visible_sort",
            on: "conversation",
            columns: ["user_id", "is_hidden", "is_pinned", "sort_ts"]
        )
        try createIndex(
            db,
            "idx_conversation_user_visible_cursor_sort",
            on: "conversation",
            columns: ["user_id", "is_hidden", "is_pinned", "sort_ts", "conversation_id"]
        )
        try createIndex(db, "idx_conversation_user_target", on: "conversation", columns: ["user_id", "target_id"])
        try createIndex(
            db,
            "idx_conversation_user_type_target",
            on: "conversation",
            columns: ["user_id", "biz_type", "target_id", "is_hidden"]
        )
        try createIndex(db, "idx_member_conversation", on: "conversation_member", columns: ["conversation_id"])
        try createIndex(db, "idx_message_conversation_sort", on: "message", columns: ["conversation_id", "sort_seq"])
        try createIndex(
            db,
            "idx_message_conversation_visible_sort",
            on: "message",
            columns: ["conversation_id", "is_deleted", "sort_seq"]
        )
        try createIndex(db, "idx_message_conversation_server", on: "message", columns: ["conversation_id", "server_time"])
        try createIndex(db, "idx_message_conversation_seq", on: "message", columns: ["conversation_id", "seq"])
        try createIndex(
            db,
            "idx_message_conversation_read_state",
            on: "message",
            columns: ["conversation_id", "direction", "read_status", "is_deleted"]
        )
        try createIndex(
            db,
            "idx_message_conversation_send_recovery",
            on: "message",
            columns: ["conversation_id", "direction", "send_status", "is_deleted", "local_time", "sort_seq"]
        )
        try createIndex(db, "idx_message_client_msg_id", on: "message", columns: ["client_msg_id"])
        try createIndex(db, "idx_message_server_msg_id", on: "message", columns: ["server_msg_id"])
        try createIndex(db, "idx_receipt_message", on: "message_receipt", columns: ["message_id"])
        try createIndex(
            db,
            "idx_pending_job_user_recoverable",
            on: "pending_job",
            columns: ["user_id", "status", "next_retry_at", "created_at"]
        )
        try createIndex(
            db,
            "idx_media_resource_user_updated",
            on: "media_resource",
            columns: ["user_id", "updated_at", "created_at"]
        )
        try createIndex(db, "idx_media_resource_owner_message", on: "media_resource", columns: ["owner_message_id"])
        try createIndex(
            db,
            "idx_emoji_package_user_sort",
            on: "emoji_package",
            columns: ["user_id", "sort_order", "updated_at"]
        )
        try createIndex(db, "idx_emoji_user_recent", on: "emoji_store", columns: ["user_id", "last_used_at"])
        try createIndex(db, "idx_emoji_user_favorite", on: "emoji_store", columns: ["user_id", "is_favorite", "updated_at"])
    }

    nonisolated static func createSearchFTSTables(in db: Database) throws {
        try db.execute(
            sql: """
            CREATE VIRTUAL TABLE IF NOT EXISTS message_search
            USING fts5(message_id, conversation_id, sender_id, text, tokenize = 'unicode61');
            """
        )
        try db.execute(
            sql: """
            CREATE VIRTUAL TABLE IF NOT EXISTS contact_search
            USING fts5(contact_id, title, subtitle, tokenize = 'unicode61');
            """
        )
        try db.execute(
            sql: """
            CREATE VIRTUAL TABLE IF NOT EXISTS conversation_search
            USING fts5(conversation_id, title, subtitle, tokenize = 'unicode61');
            """
        )
    }

    nonisolated static func createIndex(_ db: Database, _ name: String, on table: String, columns: [String]) throws {
        try db.create(index: name, on: table, columns: columns, options: .ifNotExists)
    }
}
