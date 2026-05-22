//
//  EmojiDAO.swift
//  AppleIM
//

import Foundation
import GRDB

/// 表情数据访问对象。
nonisolated struct EmojiDAO: Sendable {
    private let database: DatabaseActor
    private let paths: AccountStoragePaths

    init(database: DatabaseActor, paths: AccountStoragePaths) {
        self.database = database
        self.paths = paths
    }

    func upsertPackage(_ package: EmojiPackageRecord) async throws {
        _ = try await database.write(paths: paths) { db in
            try EmojiPackageDatabaseRecord.upsertRecord(package, in: db)
        }
    }

    func upsertEmoji(_ emoji: EmojiAssetRecord) async throws {
        _ = try await database.write(paths: paths) { db in
            try EmojiAssetDatabaseRecord.upsertRecord(emoji, in: db)
        }
    }

    func listPackages(for userID: UserID) async throws -> [EmojiPackageRecord] {
        try await database.read(paths: paths) { db in
            try EmojiPackageDatabaseRecord
                .filter(EmojiPackageDatabaseRecord.Columns.userID == userID.rawValue)
                .order(
                    EmojiPackageDatabaseRecord.Columns.sortOrder.asc,
                    EmojiPackageDatabaseRecord.Columns.updatedAt.desc,
                    EmojiPackageDatabaseRecord.Columns.packageID.asc
                )
                .fetchAll(db)
                .map(\.record)
        }
    }

    func listEmojis(userID: UserID, packageID: String) async throws -> [EmojiAssetRecord] {
        try await database.read(paths: paths) { db in
            try EmojiAssetDatabaseRecord
                .filter(EmojiAssetDatabaseRecord.Columns.userID == userID.rawValue)
                .filter(EmojiAssetDatabaseRecord.Columns.packageID == packageID)
                .filter(EmojiAssetDatabaseRecord.Columns.isDeleted == false)
                .order(EmojiAssetDatabaseRecord.Columns.createdAt.asc, EmojiAssetDatabaseRecord.Columns.emojiID.asc)
                .fetchAll(db)
                .map(\.record)
        }
    }

    func listFavoriteEmojis(for userID: UserID) async throws -> [EmojiAssetRecord] {
        try await database.read(paths: paths) { db in
            try EmojiAssetDatabaseRecord
                .filter(EmojiAssetDatabaseRecord.Columns.userID == userID.rawValue)
                .filter(EmojiAssetDatabaseRecord.Columns.isFavorite == true)
                .filter(EmojiAssetDatabaseRecord.Columns.isDeleted == false)
                .order(
                    EmojiAssetDatabaseRecord.Columns.updatedAt.desc,
                    EmojiAssetDatabaseRecord.Columns.createdAt.desc,
                    EmojiAssetDatabaseRecord.Columns.emojiID.asc
                )
                .fetchAll(db)
                .map(\.record)
        }
    }

    func listRecentEmojis(for userID: UserID, limit: Int) async throws -> [EmojiAssetRecord] {
        try await database.read(paths: paths) { db in
            try EmojiAssetDatabaseRecord
                .filter(EmojiAssetDatabaseRecord.Columns.userID == userID.rawValue)
                .filter(EmojiAssetDatabaseRecord.Columns.lastUsedAt != nil)
                .filter(EmojiAssetDatabaseRecord.Columns.isDeleted == false)
                .order(
                    EmojiAssetDatabaseRecord.Columns.lastUsedAt.desc,
                    EmojiAssetDatabaseRecord.Columns.useCount.desc,
                    EmojiAssetDatabaseRecord.Columns.emojiID.asc
                )
                .limit(max(0, limit))
                .fetchAll(db)
                .map(\.record)
        }
    }

    func emoji(emojiID: String, userID: UserID) async throws -> EmojiAssetRecord? {
        try await database.read(paths: paths) { db in
            try EmojiAssetDatabaseRecord
                .filter(EmojiAssetDatabaseRecord.Columns.emojiID == emojiID)
                .filter(EmojiAssetDatabaseRecord.Columns.userID == userID.rawValue)
                .filter(EmojiAssetDatabaseRecord.Columns.isDeleted == false)
                .fetchOne(db)?
                .record
        }
    }

    func setFavorite(emojiID: String, userID: UserID, isFavorite: Bool, updatedAt: Int64) async throws {
        _ = try await database.write(paths: paths) { db in
            try Self.availableEmoji(emojiID: emojiID, userID: userID)
                .updateAll(db, [
                    EmojiAssetDatabaseRecord.Columns.isFavorite.set(to: isFavorite),
                    EmojiAssetDatabaseRecord.Columns.updatedAt.set(to: updatedAt)
                ])
        }
    }

    func recordUsed(emojiID: String, userID: UserID, usedAt: Int64) async throws {
        _ = try await database.write(paths: paths) { db in
            try Self.availableEmoji(emojiID: emojiID, userID: userID)
                .updateAll(db, [
                    EmojiAssetDatabaseRecord.Columns.useCount += 1,
                    EmojiAssetDatabaseRecord.Columns.lastUsedAt.set(to: usedAt),
                    EmojiAssetDatabaseRecord.Columns.updatedAt.set(to: usedAt)
                ])
        }
    }

    private static func availableEmoji(emojiID: String, userID: UserID) -> QueryInterfaceRequest<EmojiAssetDatabaseRecord> {
        EmojiAssetDatabaseRecord
            .filter(EmojiAssetDatabaseRecord.Columns.emojiID == emojiID)
            .filter(EmojiAssetDatabaseRecord.Columns.userID == userID.rawValue)
            .filter(EmojiAssetDatabaseRecord.Columns.isDeleted == false)
    }
}
