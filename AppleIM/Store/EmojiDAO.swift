//
//  EmojiDAO.swift
//  AppleIM
//

import Foundation

/// 表情数据访问对象。
nonisolated struct EmojiDAO: Sendable {
    private let database: DatabaseActor
    private let paths: AccountStoragePaths

    init(database: DatabaseActor, paths: AccountStoragePaths) {
        self.database = database
        self.paths = paths
    }

    func upsertPackage(_ package: EmojiPackageRecord) async throws {
        let statement = Self.upsertPackageStatement(package)
        try await database.execute(statement.sql, parameters: statement.parameters, paths: paths)
    }

    func upsertEmoji(_ emoji: EmojiAssetRecord) async throws {
        let statement = Self.upsertEmojiStatement(emoji)
        try await database.execute(statement.sql, parameters: statement.parameters, paths: paths)
    }

    func listPackages(for userID: UserID) async throws -> [EmojiPackageRecord] {
        let rows = try await database.query(
            """
            SELECT
                package_id,
                user_id,
                title,
                author,
                cover_url,
                local_cover_path,
                version,
                status,
                sort_order,
                created_at,
                updated_at
            FROM emoji_package
            WHERE user_id = ?
            ORDER BY sort_order ASC, updated_at DESC, package_id ASC;
            """,
            parameters: [.text(userID.rawValue)],
            paths: paths
        )
        return try rows.map(Self.package(from:))
    }

    func listEmojis(userID: UserID, packageID: String) async throws -> [EmojiAssetRecord] {
        let rows = try await database.query(
            """
            SELECT \(Self.emojiColumns)
            FROM emoji_store
            WHERE user_id = ?
            AND package_id = ?
            AND is_deleted = 0
            ORDER BY created_at ASC, emoji_id ASC;
            """,
            parameters: [.text(userID.rawValue), .text(packageID)],
            paths: paths
        )
        return try rows.map(Self.emoji(from:))
    }

    func listFavoriteEmojis(for userID: UserID) async throws -> [EmojiAssetRecord] {
        let rows = try await database.query(
            """
            SELECT \(Self.emojiColumns)
            FROM emoji_store INDEXED BY idx_emoji_user_favorite
            WHERE user_id = ?
            AND is_favorite = 1
            AND is_deleted = 0
            ORDER BY updated_at DESC, created_at DESC, emoji_id ASC;
            """,
            parameters: [.text(userID.rawValue)],
            paths: paths
        )
        return try rows.map(Self.emoji(from:))
    }

    func listRecentEmojis(for userID: UserID, limit: Int) async throws -> [EmojiAssetRecord] {
        let rows = try await database.query(
            """
            SELECT \(Self.emojiColumns)
            FROM emoji_store INDEXED BY idx_emoji_user_recent
            WHERE user_id = ?
            AND last_used_at IS NOT NULL
            AND is_deleted = 0
            ORDER BY last_used_at DESC, use_count DESC, emoji_id ASC
            LIMIT ?;
            """,
            parameters: [.text(userID.rawValue), .integer(Int64(max(0, limit)))],
            paths: paths
        )
        return try rows.map(Self.emoji(from:))
    }

    func emoji(emojiID: String, userID: UserID) async throws -> EmojiAssetRecord? {
        let rows = try await database.query(
            """
            SELECT \(Self.emojiColumns)
            FROM emoji_store
            WHERE emoji_id = ?
            AND user_id = ?
            AND is_deleted = 0
            LIMIT 1;
            """,
            parameters: [.text(emojiID), .text(userID.rawValue)],
            paths: paths
        )
        return try rows.first.map(Self.emoji(from:))
    }

    func setFavorite(emojiID: String, userID: UserID, isFavorite: Bool, updatedAt: Int64) async throws {
        try await database.execute(
            """
            UPDATE emoji_store
            SET is_favorite = ?,
                updated_at = ?
            WHERE emoji_id = ?
            AND user_id = ?
            AND is_deleted = 0;
            """,
            parameters: [
                .integer(isFavorite ? 1 : 0),
                .integer(updatedAt),
                .text(emojiID),
                .text(userID.rawValue)
            ],
            paths: paths
        )
    }

    func recordUsed(emojiID: String, userID: UserID, usedAt: Int64) async throws {
        try await database.execute(
            """
            UPDATE emoji_store
            SET use_count = use_count + 1,
                last_used_at = ?,
                updated_at = ?
            WHERE emoji_id = ?
            AND user_id = ?
            AND is_deleted = 0;
            """,
            parameters: [
                .integer(usedAt),
                .integer(usedAt),
                .text(emojiID),
                .text(userID.rawValue)
            ],
            paths: paths
        )
    }

    static func upsertPackageStatement(_ package: EmojiPackageRecord) -> SQLiteStatement {
        SQLiteStatement(
            """
            INSERT INTO emoji_package (
                package_id,
                user_id,
                title,
                author,
                cover_url,
                local_cover_path,
                version,
                status,
                sort_order,
                created_at,
                updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(package_id) DO UPDATE SET
                user_id = excluded.user_id,
                title = excluded.title,
                author = excluded.author,
                cover_url = excluded.cover_url,
                local_cover_path = excluded.local_cover_path,
                version = excluded.version,
                status = excluded.status,
                sort_order = excluded.sort_order,
                updated_at = excluded.updated_at;
            """,
            parameters: [
                .text(package.packageID),
                .text(package.userID.rawValue),
                .text(package.title),
                .optionalText(package.author),
                .optionalText(package.coverURL),
                .optionalText(package.localCoverPath),
                .integer(Int64(package.version)),
                .integer(Int64(package.status.rawValue)),
                .integer(Int64(package.sortOrder)),
                .integer(package.createdAt),
                .integer(package.updatedAt)
            ]
        )
    }

    static func upsertEmojiStatement(_ emoji: EmojiAssetRecord) -> SQLiteStatement {
        SQLiteStatement(
            """
            INSERT INTO emoji_store (
                emoji_id,
                user_id,
                package_id,
                emoji_type,
                name,
                md5,
                local_path,
                thumb_path,
                cdn_url,
                width,
                height,
                size_bytes,
                use_count,
                last_used_at,
                is_favorite,
                is_deleted,
                extra_json,
                created_at,
                updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(emoji_id) DO UPDATE SET
                user_id = excluded.user_id,
                package_id = excluded.package_id,
                emoji_type = excluded.emoji_type,
                name = excluded.name,
                md5 = excluded.md5,
                local_path = excluded.local_path,
                thumb_path = excluded.thumb_path,
                cdn_url = excluded.cdn_url,
                width = excluded.width,
                height = excluded.height,
                size_bytes = excluded.size_bytes,
                use_count = excluded.use_count,
                last_used_at = excluded.last_used_at,
                is_favorite = excluded.is_favorite,
                is_deleted = excluded.is_deleted,
                extra_json = excluded.extra_json,
                updated_at = excluded.updated_at;
            """,
            parameters: [
                .text(emoji.emojiID),
                .text(emoji.userID.rawValue),
                .optionalText(emoji.packageID),
                .integer(Int64(emoji.emojiType.rawValue)),
                .optionalText(emoji.name),
                .optionalText(emoji.md5),
                .optionalText(emoji.localPath),
                .optionalText(emoji.thumbPath),
                .optionalText(emoji.cdnURL),
                .optionalInteger(emoji.width.map(Int64.init)),
                .optionalInteger(emoji.height.map(Int64.init)),
                .optionalInteger(emoji.sizeBytes),
                .integer(Int64(emoji.useCount)),
                .optionalInteger(emoji.lastUsedAt),
                .integer(emoji.isFavorite ? 1 : 0),
                .integer(emoji.isDeleted ? 1 : 0),
                .optionalText(emoji.extraJSON),
                .integer(emoji.createdAt),
                .integer(emoji.updatedAt)
            ]
        )
    }

    private static let emojiColumns = """
        emoji_id,
        user_id,
        package_id,
        emoji_type,
        name,
        md5,
        local_path,
        thumb_path,
        cdn_url,
        width,
        height,
        size_bytes,
        use_count,
        last_used_at,
        is_favorite,
        is_deleted,
        extra_json,
        created_at,
        updated_at
    """

    private static func package(from row: SQLiteRow) throws -> EmojiPackageRecord {
        let statusRawValue = row.int("status") ?? EmojiPackageStatus.notDownloaded.rawValue
        guard let status = EmojiPackageStatus(rawValue: statusRawValue) else {
            throw ChatStoreError.invalidEmojiPackageStatus(statusRawValue)
        }

        return EmojiPackageRecord(
            packageID: try row.requiredString("package_id"),
            userID: UserID(rawValue: try row.requiredString("user_id")),
            title: try row.requiredString("title"),
            author: row.string("author"),
            coverURL: row.string("cover_url"),
            localCoverPath: row.string("local_cover_path"),
            version: row.int("version") ?? 0,
            status: status,
            sortOrder: row.int("sort_order") ?? 0,
            createdAt: row.int64("created_at") ?? 0,
            updatedAt: row.int64("updated_at") ?? 0
        )
    }

    private static func emoji(from row: SQLiteRow) throws -> EmojiAssetRecord {
        let typeRawValue = try row.requiredInt("emoji_type")
        guard let emojiType = EmojiType(rawValue: typeRawValue) else {
            throw ChatStoreError.invalidEmojiType(typeRawValue)
        }

        return EmojiAssetRecord(
            emojiID: try row.requiredString("emoji_id"),
            userID: UserID(rawValue: try row.requiredString("user_id")),
            packageID: row.string("package_id"),
            emojiType: emojiType,
            name: row.string("name"),
            md5: row.string("md5"),
            localPath: row.string("local_path"),
            thumbPath: row.string("thumb_path"),
            cdnURL: row.string("cdn_url"),
            width: row.int("width"),
            height: row.int("height"),
            sizeBytes: row.int64("size_bytes"),
            useCount: row.int("use_count") ?? 0,
            lastUsedAt: row.int64("last_used_at"),
            isFavorite: row.bool("is_favorite"),
            isDeleted: row.bool("is_deleted"),
            extraJSON: row.string("extra_json"),
            createdAt: row.int64("created_at") ?? 0,
            updatedAt: row.int64("updated_at") ?? 0
        )
    }
}
