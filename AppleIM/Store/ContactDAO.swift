//
//  ContactDAO.swift
//  AppleIM
//
//  通讯录数据访问对象
//

import Foundation
import GRDB

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
        try await database.read(paths: paths) { db in
            try ContactDatabaseRecord
                .filter(ContactDatabaseRecord.Columns.userID == userID.rawValue)
                .filter(ContactDatabaseRecord.Columns.isDeleted == false)
                .order(sql: "type ASC, is_starred DESC, COALESCE(NULLIF(remark, ''), nickname, wxid) COLLATE NOCASE ASC, contact_id ASC")
                .fetchAll(db)
                .map(\.record)
        }
    }

    /// 查询联系人数量，包含已删除联系人，用于判断是否执行首次 seed。
    func countContacts(for userID: UserID) async throws -> Int {
        try await database.read(paths: paths) { db in
            try ContactDatabaseRecord
                .filter(ContactDatabaseRecord.Columns.userID == userID.rawValue)
                .fetchCount(db)
        }
    }

    /// 查询单个联系人。
    func contact(id contactID: ContactID, userID: UserID) async throws -> ContactRecord? {
        try await database.read(paths: paths) { db in
            try ContactDatabaseRecord
                .filter(ContactDatabaseRecord.Columns.contactID == contactID.rawValue)
                .filter(ContactDatabaseRecord.Columns.userID == userID.rawValue)
                .filter(ContactDatabaseRecord.Columns.isDeleted == false)
                .fetchOne(db)?
                .record
        }
    }

    /// 插入或更新联系人。
    func upsert(_ record: ContactRecord) async throws {
        _ = try await database.write(paths: paths) { db in
            try ContactDatabaseRecord.upsertRecord(record, in: db)
        }
    }

    /// 批量插入或更新联系人。
    func upsert(_ records: [ContactRecord]) async throws {
        guard !records.isEmpty else { return }
        _ = try await database.write(paths: paths) { db in
            for record in records {
                try ContactDatabaseRecord.upsertRecord(record, in: db)
            }
        }
    }

}
