//
//  GRDBContactRecords.swift
//  AppleIM
//
//  GRDB 内部表映射。
//

import Foundation
import GRDB

/// contact 表的 GRDB 读取模型。
///
/// 只在 Store/DAO 内部使用，避免把 GRDB 协议扩散到业务模型。
nonisolated struct ContactDatabaseRecord: FetchableRecord, TableRecord, Sendable {
    static let databaseTableName = "contact"

    enum Columns {
        static let contactID = Column("contact_id")
        static let userID = Column("user_id")
        static let wxid = Column("wxid")
        static let nickname = Column("nickname")
        static let remark = Column("remark")
        static let avatarURL = Column("avatar_url")
        static let type = Column("type")
        static let isStarred = Column("is_starred")
        static let isBlocked = Column("is_blocked")
        static let isDeleted = Column("is_deleted")
        static let source = Column("source")
        static let extraJSON = Column("extra_json")
        static let updatedAt = Column("updated_at")
        static let createdAt = Column("created_at")
    }

    let record: ContactRecord

    init(row: Row) throws {
        let rawType: Int = row[Columns.type]
        guard let type = ContactType(rawValue: rawType) else {
            throw ContactStoreError.invalidContactType(rawType)
        }

        record = ContactRecord(
            contactID: ContactID(rawValue: row[Columns.contactID]),
            userID: UserID(rawValue: row[Columns.userID]),
            wxid: row[Columns.wxid],
            nickname: row[Columns.nickname] ?? "",
            remark: row[Columns.remark],
            avatarURL: row[Columns.avatarURL],
            type: type,
            isStarred: row[Columns.isStarred],
            isBlocked: row[Columns.isBlocked],
            isDeleted: row[Columns.isDeleted],
            source: row[Columns.source],
            extraJSON: row[Columns.extraJSON],
            updatedAt: row[Columns.updatedAt] ?? 0,
            createdAt: row[Columns.createdAt] ?? 0
        )
    }
}


extension ContactDatabaseRecord: PersistableRecord {
    init(record: ContactRecord) {
        self.record = record
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.contactID] = record.contactID.rawValue
        container[Columns.userID] = record.userID.rawValue
        container[Columns.wxid] = record.wxid
        container[Columns.nickname] = record.nickname
        container[Columns.remark] = record.remark
        container[Columns.avatarURL] = record.avatarURL
        container[Columns.type] = record.type.rawValue
        container[Columns.isStarred] = record.isStarred
        container[Columns.isBlocked] = record.isBlocked
        container[Columns.isDeleted] = record.isDeleted
        container[Columns.source] = record.source
        container[Columns.extraJSON] = record.extraJSON
        container[Columns.updatedAt] = record.updatedAt
        container[Columns.createdAt] = record.createdAt
    }

    @discardableResult
    static func upsertRecord(_ record: ContactRecord, in db: Database) throws -> ContactRecord {
        let databaseRecord = try ContactDatabaseRecord(record: record)
            .upsertAndFetch(db, updating: .noColumnUnlessSpecified) { excluded in
                [
                    Columns.userID.set(to: excluded[Columns.userID]),
                    Columns.wxid.set(to: excluded[Columns.wxid]),
                    Columns.nickname.set(to: excluded[Columns.nickname]),
                    Columns.remark.set(to: excluded[Columns.remark]),
                    Columns.avatarURL.set(to: excluded[Columns.avatarURL]),
                    Columns.type.set(to: excluded[Columns.type]),
                    Columns.isStarred.set(to: excluded[Columns.isStarred]),
                    Columns.isBlocked.set(to: excluded[Columns.isBlocked]),
                    Columns.isDeleted.set(to: excluded[Columns.isDeleted]),
                    Columns.source.set(to: excluded[Columns.source]),
                    Columns.extraJSON.set(to: excluded[Columns.extraJSON]),
                    Columns.updatedAt.set(to: excluded[Columns.updatedAt])
                ]
            }
        return databaseRecord.record
    }
}

