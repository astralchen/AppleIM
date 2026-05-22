//
//  GRDBEmojiRecords.swift
//  AppleIM
//
//  GRDB 内部表映射。
//

import Foundation
import GRDB

/// emoji_package 表的 GRDB 读取模型。
nonisolated struct EmojiPackageDatabaseRecord: FetchableRecord, TableRecord, Sendable {
    static let databaseTableName = "emoji_package"

    enum Columns {
        static let packageID = Column("package_id")
        static let userID = Column("user_id")
        static let title = Column("title")
        static let author = Column("author")
        static let coverURL = Column("cover_url")
        static let localCoverPath = Column("local_cover_path")
        static let version = Column("version")
        static let status = Column("status")
        static let sortOrder = Column("sort_order")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }

    let record: EmojiPackageRecord

    init(row: Row) throws {
        let statusRawValue: Int = row[Columns.status] ?? EmojiPackageStatus.notDownloaded.rawValue
        guard let status = EmojiPackageStatus(rawValue: statusRawValue) else {
            throw ChatStoreError.invalidEmojiPackageStatus(statusRawValue)
        }

        record = EmojiPackageRecord(
            packageID: row[Columns.packageID],
            userID: UserID(rawValue: row[Columns.userID]),
            title: row[Columns.title],
            author: row[Columns.author],
            coverURL: row[Columns.coverURL],
            localCoverPath: row[Columns.localCoverPath],
            version: row[Columns.version] ?? 0,
            status: status,
            sortOrder: row[Columns.sortOrder] ?? 0,
            createdAt: row[Columns.createdAt] ?? 0,
            updatedAt: row[Columns.updatedAt] ?? 0
        )
    }
}

/// emoji_store 表的 GRDB 读取模型。
nonisolated struct EmojiAssetDatabaseRecord: FetchableRecord, TableRecord, Sendable {
    static let databaseTableName = "emoji_store"

    enum Columns {
        static let emojiID = Column("emoji_id")
        static let userID = Column("user_id")
        static let packageID = Column("package_id")
        static let emojiType = Column("emoji_type")
        static let name = Column("name")
        static let md5 = Column("md5")
        static let localPath = Column("local_path")
        static let thumbPath = Column("thumb_path")
        static let cdnURL = Column("cdn_url")
        static let width = Column("width")
        static let height = Column("height")
        static let sizeBytes = Column("size_bytes")
        static let useCount = Column("use_count")
        static let lastUsedAt = Column("last_used_at")
        static let isFavorite = Column("is_favorite")
        static let isDeleted = Column("is_deleted")
        static let extraJSON = Column("extra_json")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }

    let record: EmojiAssetRecord

    init(row: Row) throws {
        let typeRawValue: Int = row[Columns.emojiType]
        guard let emojiType = EmojiType(rawValue: typeRawValue) else {
            throw ChatStoreError.invalidEmojiType(typeRawValue)
        }

        record = EmojiAssetRecord(
            emojiID: row[Columns.emojiID],
            userID: UserID(rawValue: row[Columns.userID]),
            packageID: row[Columns.packageID],
            emojiType: emojiType,
            name: row[Columns.name],
            md5: row[Columns.md5],
            localPath: row[Columns.localPath],
            thumbPath: row[Columns.thumbPath],
            cdnURL: row[Columns.cdnURL],
            width: row[Columns.width],
            height: row[Columns.height],
            sizeBytes: row[Columns.sizeBytes],
            useCount: row[Columns.useCount] ?? 0,
            lastUsedAt: row[Columns.lastUsedAt],
            isFavorite: row[Columns.isFavorite],
            isDeleted: row[Columns.isDeleted],
            extraJSON: row[Columns.extraJSON],
            createdAt: row[Columns.createdAt] ?? 0,
            updatedAt: row[Columns.updatedAt] ?? 0
        )
    }
}


extension EmojiPackageDatabaseRecord: PersistableRecord {
    init(record: EmojiPackageRecord) {
        self.record = record
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.packageID] = record.packageID
        container[Columns.userID] = record.userID.rawValue
        container[Columns.title] = record.title
        container[Columns.author] = record.author
        container[Columns.coverURL] = record.coverURL
        container[Columns.localCoverPath] = record.localCoverPath
        container[Columns.version] = record.version
        container[Columns.status] = record.status.rawValue
        container[Columns.sortOrder] = record.sortOrder
        container[Columns.createdAt] = record.createdAt
        container[Columns.updatedAt] = record.updatedAt
    }

    @discardableResult
    static func upsertRecord(_ record: EmojiPackageRecord, in db: Database) throws -> EmojiPackageRecord {
        let databaseRecord = try EmojiPackageDatabaseRecord(record: record)
            .upsertAndFetch(db, updating: .noColumnUnlessSpecified) { excluded in
                [
                    Columns.userID.set(to: excluded[Columns.userID]),
                    Columns.title.set(to: excluded[Columns.title]),
                    Columns.author.set(to: excluded[Columns.author]),
                    Columns.coverURL.set(to: excluded[Columns.coverURL]),
                    Columns.localCoverPath.set(to: excluded[Columns.localCoverPath]),
                    Columns.version.set(to: excluded[Columns.version]),
                    Columns.status.set(to: excluded[Columns.status]),
                    Columns.sortOrder.set(to: excluded[Columns.sortOrder]),
                    Columns.updatedAt.set(to: excluded[Columns.updatedAt])
                ]
            }
        return databaseRecord.record
    }
}

extension EmojiAssetDatabaseRecord: PersistableRecord {
    init(record: EmojiAssetRecord) {
        self.record = record
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.emojiID] = record.emojiID
        container[Columns.userID] = record.userID.rawValue
        container[Columns.packageID] = record.packageID
        container[Columns.emojiType] = record.emojiType.rawValue
        container[Columns.name] = record.name
        container[Columns.md5] = record.md5
        container[Columns.localPath] = record.localPath
        container[Columns.thumbPath] = record.thumbPath
        container[Columns.cdnURL] = record.cdnURL
        container[Columns.width] = record.width
        container[Columns.height] = record.height
        container[Columns.sizeBytes] = record.sizeBytes
        container[Columns.useCount] = record.useCount
        container[Columns.lastUsedAt] = record.lastUsedAt
        container[Columns.isFavorite] = record.isFavorite
        container[Columns.isDeleted] = record.isDeleted
        container[Columns.extraJSON] = record.extraJSON
        container[Columns.createdAt] = record.createdAt
        container[Columns.updatedAt] = record.updatedAt
    }

    @discardableResult
    static func upsertRecord(_ record: EmojiAssetRecord, in db: Database) throws -> EmojiAssetRecord {
        let databaseRecord = try EmojiAssetDatabaseRecord(record: record)
            .upsertAndFetch(db, updating: .noColumnUnlessSpecified) { excluded in
                [
                    Columns.userID.set(to: excluded[Columns.userID]),
                    Columns.packageID.set(to: excluded[Columns.packageID]),
                    Columns.emojiType.set(to: excluded[Columns.emojiType]),
                    Columns.name.set(to: excluded[Columns.name]),
                    Columns.md5.set(to: excluded[Columns.md5]),
                    Columns.localPath.set(to: excluded[Columns.localPath]),
                    Columns.thumbPath.set(to: excluded[Columns.thumbPath]),
                    Columns.cdnURL.set(to: excluded[Columns.cdnURL]),
                    Columns.width.set(to: excluded[Columns.width]),
                    Columns.height.set(to: excluded[Columns.height]),
                    Columns.sizeBytes.set(to: excluded[Columns.sizeBytes]),
                    Columns.useCount.set(to: excluded[Columns.useCount]),
                    Columns.lastUsedAt.set(to: excluded[Columns.lastUsedAt]),
                    Columns.isFavorite.set(to: excluded[Columns.isFavorite]),
                    Columns.isDeleted.set(to: excluded[Columns.isDeleted]),
                    Columns.extraJSON.set(to: excluded[Columns.extraJSON]),
                    Columns.updatedAt.set(to: excluded[Columns.updatedAt])
                ]
            }
        return databaseRecord.record
    }
}

