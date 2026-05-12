//
//  ContactDAO.swift
//  AppleIM
//
//  通讯录数据访问对象
//

import Foundation

/// 联系人 DAO
nonisolated struct ContactDAO: Sendable {
    private let database: DatabaseActor
    private let paths: AccountStoragePaths

    init(database: DatabaseActor, paths: AccountStoragePaths) {
        self.database = database
        self.paths = paths
    }

    /// 查询当前账号未删除的联系人。
    func listContacts(for userID: UserID) async throws -> [ContactRecord] {
        let rows = try await database.query(
            """
            SELECT
                contact_id,
                user_id,
                wxid,
                nickname,
                remark,
                avatar_url,
                type,
                is_starred,
                is_blocked,
                is_deleted,
                source,
                extra_json,
                updated_at,
                created_at
            FROM contact
            WHERE user_id = ? AND is_deleted = 0
            ORDER BY type ASC, is_starred DESC, COALESCE(NULLIF(remark, ''), nickname, wxid) COLLATE NOCASE ASC, contact_id ASC;
            """,
            parameters: [.text(userID.rawValue)],
            paths: paths
        )

        return try rows.map(Self.record(from:))
    }

    /// 查询联系人数量，包含已删除联系人，用于判断是否执行首次 seed。
    func countContacts(for userID: UserID) async throws -> Int {
        let rows = try await database.query(
            "SELECT COUNT(*) AS contact_count FROM contact WHERE user_id = ?;",
            parameters: [.text(userID.rawValue)],
            paths: paths
        )

        return rows.first?.int("contact_count") ?? 0
    }

    /// 查询单个联系人。
    func contact(id contactID: ContactID, userID: UserID) async throws -> ContactRecord? {
        let rows = try await database.query(
            """
            SELECT
                contact_id,
                user_id,
                wxid,
                nickname,
                remark,
                avatar_url,
                type,
                is_starred,
                is_blocked,
                is_deleted,
                source,
                extra_json,
                updated_at,
                created_at
            FROM contact
            WHERE contact_id = ? AND user_id = ? AND is_deleted = 0
            LIMIT 1;
            """,
            parameters: [
                .text(contactID.rawValue),
                .text(userID.rawValue)
            ],
            paths: paths
        )

        return try rows.first.map(Self.record(from:))
    }

    /// 插入或更新联系人。
    func upsert(_ record: ContactRecord) async throws {
        let statement = Self.insertOrUpdateStatement(for: record)
        try await database.execute(statement.sql, parameters: statement.parameters, paths: paths)
    }

    /// 批量插入或更新联系人。
    func upsert(_ records: [ContactRecord]) async throws {
        guard !records.isEmpty else { return }
        try await database.performTransaction(records.map(Self.insertOrUpdateStatement(for:)), paths: paths)
    }

    static func insertOrUpdateStatement(for record: ContactRecord) -> SQLiteStatement {
        SQLiteStatement(
            """
            INSERT INTO contact (
                contact_id,
                user_id,
                wxid,
                nickname,
                remark,
                avatar_url,
                type,
                is_starred,
                is_blocked,
                is_deleted,
                source,
                extra_json,
                updated_at,
                created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(contact_id) DO UPDATE SET
                user_id = excluded.user_id,
                wxid = excluded.wxid,
                nickname = excluded.nickname,
                remark = excluded.remark,
                avatar_url = excluded.avatar_url,
                type = excluded.type,
                is_starred = excluded.is_starred,
                is_blocked = excluded.is_blocked,
                is_deleted = excluded.is_deleted,
                source = excluded.source,
                extra_json = excluded.extra_json,
                updated_at = excluded.updated_at;
            """,
            parameters: [
                .text(record.contactID.rawValue),
                .text(record.userID.rawValue),
                .text(record.wxid),
                .text(record.nickname),
                .optionalText(record.remark),
                .optionalText(record.avatarURL),
                .integer(Int64(record.type.rawValue)),
                .integer(record.isStarred ? 1 : 0),
                .integer(record.isBlocked ? 1 : 0),
                .integer(record.isDeleted ? 1 : 0),
                .optionalInteger(record.source.map(Int64.init)),
                .optionalText(record.extraJSON),
                .integer(record.updatedAt),
                .integer(record.createdAt)
            ]
        )
    }

    private static func record(from row: SQLiteRow) throws -> ContactRecord {
        let rawType = try row.requiredInt("type")
        guard let type = ContactType(rawValue: rawType) else {
            throw ContactStoreError.invalidContactType(rawType)
        }

        return ContactRecord(
            contactID: ContactID(rawValue: try row.requiredString("contact_id")),
            userID: UserID(rawValue: try row.requiredString("user_id")),
            wxid: try row.requiredString("wxid"),
            nickname: row.string("nickname") ?? "",
            remark: row.string("remark"),
            avatarURL: row.string("avatar_url"),
            type: type,
            isStarred: row.bool("is_starred"),
            isBlocked: row.bool("is_blocked"),
            isDeleted: row.bool("is_deleted"),
            source: row.int("source"),
            extraJSON: row.string("extra_json"),
            updatedAt: row.int64("updated_at") ?? 0,
            createdAt: row.int64("created_at") ?? 0
        )
    }
}

