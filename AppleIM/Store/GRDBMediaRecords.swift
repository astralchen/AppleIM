//
//  GRDBMediaRecords.swift
//  AppleIM
//
//  GRDB 内部表映射。
//

import Foundation
import GRDB

/// file_index 表的 GRDB 读取模型。
nonisolated struct MediaIndexDatabaseRecord: FetchableRecord, TableRecord, Sendable {
    static let databaseTableName = "file_index"

    enum Columns {
        static let mediaID = Column("media_id")
        static let userID = Column("user_id")
        static let localPath = Column("local_path")
        static let fileName = Column("file_name")
        static let fileExtension = Column("file_ext")
        static let sizeBytes = Column("size_bytes")
        static let md5 = Column("md5")
        static let lastAccessAt = Column("last_access_at")
        static let createdAt = Column("created_at")
    }

    let record: MediaIndexRecord

    init(row: Row) throws {
        record = MediaIndexRecord(
            mediaID: row[Columns.mediaID],
            userID: UserID(rawValue: row[Columns.userID]),
            localPath: row[Columns.localPath],
            fileName: row[Columns.fileName],
            fileExtension: row[Columns.fileExtension],
            sizeBytes: row[Columns.sizeBytes],
            md5: row[Columns.md5],
            lastAccessAt: row[Columns.lastAccessAt],
            createdAt: row[Columns.createdAt]
        )
    }
}

extension MediaIndexDatabaseRecord: PersistableRecord {
    init(record: MediaIndexRecord) {
        self.record = record
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.mediaID] = record.mediaID
        container[Columns.userID] = record.userID.rawValue
        container[Columns.localPath] = record.localPath
        container[Columns.fileName] = record.fileName
        container[Columns.fileExtension] = record.fileExtension
        container[Columns.sizeBytes] = record.sizeBytes
        container[Columns.md5] = record.md5
        container[Columns.lastAccessAt] = record.lastAccessAt
        container[Columns.createdAt] = record.createdAt
    }

    static func upsertRecord(_ record: MediaIndexRecord, in db: Database) throws {
        if try MediaIndexDatabaseRecord
            .filter(Columns.mediaID == record.mediaID)
            .fetchOne(db) != nil {
            try MediaIndexDatabaseRecord
                .filter(Columns.mediaID == record.mediaID)
                .updateAll(db, [
                    Columns.userID.set(to: record.userID.rawValue),
                    Columns.localPath.set(to: record.localPath),
                    Columns.fileName.set(to: record.fileName),
                    Columns.fileExtension.set(to: record.fileExtension),
                    Columns.sizeBytes.set(to: record.sizeBytes),
                    Columns.md5.set(to: record.md5),
                    Columns.lastAccessAt.set(to: record.lastAccessAt)
                ])
        } else {
            try MediaIndexDatabaseRecord(record: record).insert(db)
        }
    }
}

/// media_resource 表中用于缺失资源修复的 GRDB 读取模型。
nonisolated struct MissingMediaResourceDatabaseRecord: FetchableRecord, TableRecord, Sendable {
    static let databaseTableName = "media_resource"

    enum Columns {
        static let mediaID = Column("media_id")
        static let userID = Column("user_id")
        static let ownerMessageID = Column("owner_message_id")
        static let localPath = Column("local_path")
        static let remoteURL = Column("remote_url")
        static let updatedAt = Column("updated_at")
        static let createdAt = Column("created_at")
    }

    let resource: MissingMediaResource

    init(row: Row) throws {
        let ownerMessageID: String? = row[Columns.ownerMessageID]
        resource = MissingMediaResource(
            mediaID: row[Columns.mediaID],
            userID: UserID(rawValue: row[Columns.userID]),
            ownerMessageID: ownerMessageID.map(MessageID.init(rawValue:)),
            localPath: row[Columns.localPath],
            remoteURL: row[Columns.remoteURL]
        )
    }
}


/// media_resource 表的 GRDB 写入模型。
nonisolated struct MediaResourceDatabaseRecord: FetchableRecord, PersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "media_resource"

    enum Columns {
        static let mediaID = Column("media_id")
        static let userID = Column("user_id")
        static let ownerMessageID = Column("owner_message_id")
        static let localPath = Column("local_path")
        static let remoteURL = Column("remote_url")
        static let thumbPath = Column("thumb_path")
        static let sizeBytes = Column("size_bytes")
        static let md5 = Column("md5")
        static let uploadStatus = Column("upload_status")
        static let downloadStatus = Column("download_status")
        static let updatedAt = Column("updated_at")
        static let createdAt = Column("created_at")
    }

    let mediaID: String
    let userID: UserID
    let ownerMessageID: MessageID?
    let localPath: String?
    let remoteURL: String?
    let thumbPath: String?
    let sizeBytes: Int64?
    let md5: String?
    let uploadStatus: MediaUploadStatus
    let downloadStatus: Int
    let updatedAt: Int64?
    let createdAt: Int64?

    init(
        mediaID: String,
        userID: UserID,
        ownerMessageID: MessageID?,
        localPath: String?,
        remoteURL: String?,
        thumbPath: String?,
        sizeBytes: Int64?,
        md5: String?,
        uploadStatus: MediaUploadStatus,
        downloadStatus: Int,
        updatedAt: Int64?,
        createdAt: Int64?
    ) {
        self.mediaID = mediaID
        self.userID = userID
        self.ownerMessageID = ownerMessageID
        self.localPath = localPath
        self.remoteURL = remoteURL
        self.thumbPath = thumbPath
        self.sizeBytes = sizeBytes
        self.md5 = md5
        self.uploadStatus = uploadStatus
        self.downloadStatus = downloadStatus
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }

    init(row: Row) throws {
        let uploadStatusRawValue: Int = row[Columns.uploadStatus] ?? MediaUploadStatus.pending.rawValue
        guard let uploadStatus = MediaUploadStatus(rawValue: uploadStatusRawValue) else {
            throw ChatStoreError.missingColumn("media_resource.upload_status")
        }
        let ownerMessageID: String? = row[Columns.ownerMessageID]
        self.init(
            mediaID: row[Columns.mediaID],
            userID: UserID(rawValue: row[Columns.userID]),
            ownerMessageID: ownerMessageID.map(MessageID.init(rawValue:)),
            localPath: row[Columns.localPath],
            remoteURL: row[Columns.remoteURL],
            thumbPath: row[Columns.thumbPath],
            sizeBytes: row[Columns.sizeBytes],
            md5: row[Columns.md5],
            uploadStatus: uploadStatus,
            downloadStatus: row[Columns.downloadStatus] ?? 0,
            updatedAt: row[Columns.updatedAt],
            createdAt: row[Columns.createdAt]
        )
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.mediaID] = mediaID
        container[Columns.userID] = userID.rawValue
        container[Columns.ownerMessageID] = ownerMessageID?.rawValue
        container[Columns.localPath] = localPath
        container[Columns.remoteURL] = remoteURL
        container[Columns.thumbPath] = thumbPath
        container[Columns.sizeBytes] = sizeBytes
        container[Columns.md5] = md5
        container[Columns.uploadStatus] = uploadStatus.rawValue
        container[Columns.downloadStatus] = downloadStatus
        container[Columns.updatedAt] = updatedAt
        container[Columns.createdAt] = createdAt
    }

    static func upsertUploadResource(_ record: MediaResourceDatabaseRecord, in db: Database) throws {
        if let existing = try MediaResourceDatabaseRecord
            .filter(Columns.mediaID == record.mediaID)
            .fetchOne(db) {
            try MediaResourceDatabaseRecord
                .filter(Columns.mediaID == record.mediaID)
                .updateAll(db, [
                    Columns.userID.set(to: record.userID.rawValue),
                    Columns.ownerMessageID.set(to: record.ownerMessageID?.rawValue),
                    Columns.localPath.set(to: record.localPath),
                    Columns.thumbPath.set(to: record.thumbPath ?? existing.thumbPath),
                    Columns.sizeBytes.set(to: record.sizeBytes),
                    Columns.md5.set(to: record.md5 ?? existing.md5),
                    Columns.uploadStatus.set(to: record.uploadStatus.rawValue),
                    Columns.updatedAt.set(to: record.updatedAt)
                ])
        } else {
            try record.insert(db)
        }
    }
}


nonisolated struct MediaResourceIndexRebuildDatabaseRecord: FetchableRecord, TableRecord, Sendable {
    static let databaseTableName = "media_resource"

    enum Columns {
        static let mediaID = Column("media_id")
        static let userID = Column("user_id")
        static let localPath = Column("local_path")
        static let thumbPath = Column("thumb_path")
        static let sizeBytes = Column("size_bytes")
        static let md5 = Column("md5")
        static let updatedAt = Column("updated_at")
        static let createdAt = Column("created_at")
    }

    let mediaID: String?
    let userID: String?
    let localPath: String?
    let thumbPath: String?
    let sizeBytes: Int64?
    let md5: String?
    let updatedAt: Int64?
    let createdAt: Int64?

    init(row: Row) throws {
        mediaID = row[Columns.mediaID]
        userID = row[Columns.userID]
        localPath = row[Columns.localPath]
        thumbPath = row[Columns.thumbPath]
        sizeBytes = row[Columns.sizeBytes]
        md5 = row[Columns.md5]
        updatedAt = row[Columns.updatedAt]
        createdAt = row[Columns.createdAt]
    }
}
