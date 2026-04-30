//
//  DatabaseSchema.swift
//  AppleIM
//
//  数据库 Schema 定义
//  定义数据库表结构和初始化脚本

import Foundation

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

/// 数据库迁移脚本
///
/// 包含 SQL 语句和版本信息
nonisolated struct MigrationScript: Equatable, Sendable {
    /// 脚本 ID
    let id: String
    /// 目标数据库
    let database: DatabaseFileKind
    /// Schema 版本号
    let version: Int
    /// SQL 语句数组
    let statements: [String]
}

/// 数据库 Schema
///
/// 定义当前 Schema 版本和初始化脚本
///
/// ## 重要说明
///
/// - 所有表都使用 TEXT 类型存储 ID，便于跨平台兼容
/// - 时间戳统一使用 INTEGER 存储毫秒级 Unix 时间戳
/// - 消息表和内容表分离，支持多种消息类型扩展
/// - 使用 sort_seq 字段统一排序，避免依赖时间戳
nonisolated enum DatabaseSchema {
    /// 当前 Schema 版本
    static let currentVersion = 2

    /// 增量迁移脚本元数据
    static let migrationScripts: [MigrationScript] = [
        MigrationScript(
            id: "002_notification_badge_settings",
            database: .main,
            version: 2,
            statements: []
        )
    ]

    /// 所有已知脚本元数据
    static let allScripts: [MigrationScript] = initialScripts + migrationScripts

    /// 初始化脚本数组
    static let initialScripts: [MigrationScript] = [
        MigrationScript(
            id: "001_main_core_tables",
            database: .main,
            version: 1,
            statements: [
                """
                CREATE TABLE IF NOT EXISTS migration_meta (
                    schema_version INTEGER NOT NULL,
                    last_migration_id TEXT,
                    last_vacuum_at INTEGER,
                    last_integrity_check_at INTEGER,
                    fts_rebuild_version INTEGER DEFAULT 0
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS user (
                    user_id TEXT PRIMARY KEY,
                    wxid TEXT UNIQUE,
                    nickname TEXT,
                    avatar_url TEXT,
                    gender INTEGER,
                    region TEXT,
                    signature TEXT,
                    remark TEXT,
                    mobile TEXT,
                    extra_json TEXT,
                    updated_at INTEGER,
                    created_at INTEGER
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS contact (
                    contact_id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    wxid TEXT NOT NULL,
                    nickname TEXT,
                    remark TEXT,
                    avatar_url TEXT,
                    type INTEGER NOT NULL,
                    is_starred INTEGER DEFAULT 0,
                    is_blocked INTEGER DEFAULT 0,
                    is_deleted INTEGER DEFAULT 0,
                    source INTEGER,
                    extra_json TEXT,
                    updated_at INTEGER,
                    created_at INTEGER
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS conversation (
                    conversation_id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    biz_type INTEGER NOT NULL,
                    target_id TEXT NOT NULL,
                    title TEXT,
                    avatar_url TEXT,
                    last_message_id TEXT,
                    last_message_time INTEGER,
                    last_message_digest TEXT,
                    unread_count INTEGER DEFAULT 0,
                    draft_text TEXT,
                    is_pinned INTEGER DEFAULT 0,
                    is_muted INTEGER DEFAULT 0,
                    is_hidden INTEGER DEFAULT 0,
                    sort_ts INTEGER NOT NULL,
                    extra_json TEXT,
                    updated_at INTEGER,
                    created_at INTEGER
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS conversation_member (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    conversation_id TEXT NOT NULL,
                    member_id TEXT NOT NULL,
                    display_name TEXT,
                    role INTEGER DEFAULT 0,
                    join_time INTEGER,
                    extra_json TEXT,
                    UNIQUE(conversation_id, member_id)
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS message (
                    message_id TEXT PRIMARY KEY,
                    local_id INTEGER UNIQUE,
                    conversation_id TEXT NOT NULL,
                    sender_id TEXT NOT NULL,
                    client_msg_id TEXT UNIQUE,
                    server_msg_id TEXT,
                    seq INTEGER,
                    msg_type INTEGER NOT NULL,
                    direction INTEGER NOT NULL,
                    send_status INTEGER NOT NULL,
                    delivery_status INTEGER DEFAULT 0,
                    read_status INTEGER DEFAULT 0,
                    revoke_status INTEGER DEFAULT 0,
                    is_deleted INTEGER DEFAULT 0,
                    quoted_message_id TEXT,
                    reply_to_message_id TEXT,
                    content_table TEXT,
                    content_id TEXT,
                    sort_seq INTEGER NOT NULL,
                    server_time INTEGER,
                    local_time INTEGER NOT NULL,
                    edit_version INTEGER DEFAULT 0,
                    extra_json TEXT
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS message_text (
                    content_id TEXT PRIMARY KEY,
                    text TEXT NOT NULL,
                    mentions_json TEXT,
                    at_all INTEGER DEFAULT 0,
                    rich_text_json TEXT
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS message_image (
                    content_id TEXT PRIMARY KEY,
                    media_id TEXT,
                    width INTEGER,
                    height INTEGER,
                    size_bytes INTEGER,
                    local_path TEXT,
                    thumb_path TEXT,
                    cdn_url TEXT,
                    md5 TEXT,
                    format TEXT,
                    upload_status INTEGER DEFAULT 0,
                    download_status INTEGER DEFAULT 0
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS message_voice (
                    content_id TEXT PRIMARY KEY,
                    media_id TEXT,
                    duration_ms INTEGER,
                    size_bytes INTEGER,
                    local_path TEXT,
                    cdn_url TEXT,
                    format TEXT,
                    transcript TEXT,
                    upload_status INTEGER DEFAULT 0,
                    download_status INTEGER DEFAULT 0
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS message_video (
                    content_id TEXT PRIMARY KEY,
                    media_id TEXT,
                    duration_ms INTEGER,
                    width INTEGER,
                    height INTEGER,
                    size_bytes INTEGER,
                    local_path TEXT,
                    thumb_path TEXT,
                    cdn_url TEXT,
                    md5 TEXT,
                    upload_status INTEGER DEFAULT 0,
                    download_status INTEGER DEFAULT 0
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS message_file (
                    content_id TEXT PRIMARY KEY,
                    media_id TEXT,
                    file_name TEXT,
                    file_ext TEXT,
                    size_bytes INTEGER,
                    local_path TEXT,
                    cdn_url TEXT,
                    md5 TEXT,
                    upload_status INTEGER DEFAULT 0,
                    download_status INTEGER DEFAULT 0
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS message_receipt (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    message_id TEXT NOT NULL,
                    user_id TEXT NOT NULL,
                    receipt_type INTEGER NOT NULL,
                    receipt_time INTEGER,
                    UNIQUE(message_id, user_id, receipt_type)
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS message_revoke (
                    message_id TEXT PRIMARY KEY,
                    operator_id TEXT NOT NULL,
                    revoke_time INTEGER NOT NULL,
                    reason TEXT,
                    replace_text TEXT
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS media_resource (
                    media_id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    owner_message_id TEXT,
                    local_path TEXT,
                    remote_url TEXT,
                    thumb_path TEXT,
                    size_bytes INTEGER,
                    md5 TEXT,
                    upload_status INTEGER DEFAULT 0,
                    download_status INTEGER DEFAULT 0,
                    updated_at INTEGER,
                    created_at INTEGER
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS draft (
                    conversation_id TEXT PRIMARY KEY,
                    text TEXT,
                    updated_at INTEGER
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS sync_checkpoint (
                    biz_key TEXT PRIMARY KEY,
                    cursor TEXT,
                    seq INTEGER,
                    updated_at INTEGER
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS pending_job (
                    job_id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    job_type INTEGER NOT NULL,
                    biz_key TEXT,
                    payload_json TEXT,
                    status INTEGER NOT NULL,
                    retry_count INTEGER DEFAULT 0,
                    max_retry_count INTEGER DEFAULT 3,
                    next_retry_at INTEGER,
                    updated_at INTEGER,
                    created_at INTEGER
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS conversation_setting (
                    conversation_id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    is_pinned INTEGER DEFAULT 0,
                    is_muted INTEGER DEFAULT 0,
                    updated_at INTEGER
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS notification_setting (
                    user_id TEXT PRIMARY KEY,
                    is_enabled INTEGER DEFAULT 1,
                    show_preview INTEGER DEFAULT 1,
                    badge_enabled INTEGER DEFAULT 1,
                    badge_include_muted INTEGER DEFAULT 1,
                    updated_at INTEGER
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS blacklist (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id TEXT NOT NULL,
                    blocked_user_id TEXT NOT NULL,
                    created_at INTEGER,
                    UNIQUE(user_id, blocked_user_id)
                );
                """,
                "CREATE INDEX IF NOT EXISTS idx_contact_user_wxid ON contact(user_id, wxid);",
                "CREATE INDEX IF NOT EXISTS idx_contact_user_updated ON contact(user_id, updated_at);",
                "CREATE INDEX IF NOT EXISTS idx_conversation_user_sort ON conversation(user_id, is_pinned DESC, sort_ts DESC);",
                "CREATE INDEX IF NOT EXISTS idx_conversation_user_target ON conversation(user_id, target_id);",
                "CREATE INDEX IF NOT EXISTS idx_member_conversation ON conversation_member(conversation_id);",
                "CREATE INDEX IF NOT EXISTS idx_message_conversation_sort ON message(conversation_id, sort_seq DESC);",
                "CREATE INDEX IF NOT EXISTS idx_message_conversation_server ON message(conversation_id, server_time DESC);",
                "CREATE INDEX IF NOT EXISTS idx_message_client_msg_id ON message(client_msg_id);",
                "CREATE INDEX IF NOT EXISTS idx_message_server_msg_id ON message(server_msg_id);",
                "CREATE INDEX IF NOT EXISTS idx_receipt_message ON message_receipt(message_id);"
            ]
        ),
        MigrationScript(
            id: "001_search_tables",
            database: .search,
            version: 1,
            statements: [
                """
                CREATE TABLE IF NOT EXISTS search_index_meta (
                    key TEXT PRIMARY KEY,
                    value TEXT,
                    updated_at INTEGER
                );
                """,
                """
                CREATE VIRTUAL TABLE IF NOT EXISTS message_search
                USING fts5(message_id, conversation_id, sender_id, text, tokenize = 'unicode61');
                """,
                """
                CREATE VIRTUAL TABLE IF NOT EXISTS contact_search
                USING fts5(contact_id, title, subtitle, tokenize = 'unicode61');
                """,
                """
                CREATE VIRTUAL TABLE IF NOT EXISTS conversation_search
                USING fts5(conversation_id, title, subtitle, tokenize = 'unicode61');
                """
            ]
        ),
        MigrationScript(
            id: "001_file_index_tables",
            database: .fileIndex,
            version: 1,
            statements: [
                """
                CREATE TABLE IF NOT EXISTS file_index (
                    media_id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    local_path TEXT NOT NULL,
                    file_name TEXT,
                    file_ext TEXT,
                    size_bytes INTEGER,
                    md5 TEXT,
                    last_access_at INTEGER,
                    created_at INTEGER
                );
                """,
                "CREATE INDEX IF NOT EXISTS idx_file_index_user ON file_index(user_id, last_access_at DESC);"
            ]
        )
    ]
}
