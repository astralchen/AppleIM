//
//  GRDBNotificationRecords.swift
//  AppleIM
//
//  GRDB 通知设置表映射。
//

import Foundation
import GRDB

/// notification_setting 表的 GRDB 模型。
nonisolated struct NotificationSettingDatabaseRecord: FetchableRecord, TableRecord, Sendable {
    static let databaseTableName = "notification_setting"

    enum Columns {
        static let userID = Column("user_id")
        static let isEnabled = Column("is_enabled")
        static let showPreview = Column("show_preview")
        static let badgeEnabled = Column("badge_enabled")
        static let badgeIncludeMuted = Column("badge_include_muted")
        static let updatedAt = Column("updated_at")
    }

    let record: NotificationSettingRecord

    init(row: Row) throws {
        record = NotificationSettingRecord(
            userID: UserID(rawValue: row[Columns.userID]),
            isEnabled: row[Columns.isEnabled],
            showPreview: row[Columns.showPreview],
            badgeEnabled: row[Columns.badgeEnabled],
            badgeIncludeMuted: row[Columns.badgeIncludeMuted],
            updatedAt: row[Columns.updatedAt] ?? 0
        )
    }
}

extension NotificationSettingDatabaseRecord: PersistableRecord {
    init(record: NotificationSettingRecord) {
        self.record = record
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.userID] = record.userID.rawValue
        container[Columns.isEnabled] = record.isEnabled
        container[Columns.showPreview] = record.showPreview
        container[Columns.badgeEnabled] = record.badgeEnabled
        container[Columns.badgeIncludeMuted] = record.badgeIncludeMuted
        container[Columns.updatedAt] = record.updatedAt
    }

    /// 只允许更新角标相关列，避免动态列名扩大写入面。
    static func upsertBadgeSetting(
        userID: UserID,
        columnName: String,
        value: Bool,
        updatedAt: Int64,
        in db: Database
    ) throws {
        let column = try badgeColumn(named: columnName)
        let request = NotificationSettingDatabaseRecord
            .filter(Columns.userID == userID.rawValue)

        if try request.fetchOne(db) != nil {
            try request.updateAll(db, [
                column.set(to: value),
                Columns.updatedAt.set(to: updatedAt)
            ])
            return
        }

        let record = NotificationSettingRecord(
            userID: userID,
            isEnabled: true,
            showPreview: true,
            badgeEnabled: columnName == "badge_enabled" ? value : true,
            badgeIncludeMuted: columnName == "badge_include_muted" ? value : true,
            updatedAt: updatedAt
        )
        try NotificationSettingDatabaseRecord(record: record).insert(db)
    }

    private static func badgeColumn(named columnName: String) throws -> Column {
        switch columnName {
        case "badge_enabled":
            Columns.badgeEnabled
        case "badge_include_muted":
            Columns.badgeIncludeMuted
        default:
            throw ChatStoreError.missingColumn(columnName)
        }
    }
}
