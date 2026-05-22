//
//  NotificationSettingsStore.swift
//  AppleIM
//
//  通知设置与角标计数的 GRDB 存储协作者。
//

import Combine
import Foundation
import GRDB

/// 收敛 notification_setting 表读写和角标聚合查询，避免 Repository 直接承担表级细节。
nonisolated struct NotificationSettingsStore: Sendable {
    private let database: DatabaseActor
    private let paths: AccountStoragePaths

    init(database: DatabaseActor, paths: AccountStoragePaths) {
        self.database = database
        self.paths = paths
    }

    /// 读取用户通知设置；缺省时返回业务默认值。
    func setting(for userID: UserID) async throws -> NotificationSettingRecord {
        try await database.read(paths: paths) { db in
            try Self.setting(for: userID, db: db)
        }
    }

    /// 更新角标开关。
    func updateBadgeEnabled(userID: UserID, isEnabled: Bool) async throws {
        try await upsertBadgeSetting(
            userID: userID,
            columnName: "badge_enabled",
            value: isEnabled
        )
    }

    /// 更新角标是否包含免打扰会话。
    func updateBadgeIncludeMuted(userID: UserID, includeMuted: Bool) async throws {
        try await upsertBadgeSetting(
            userID: userID,
            columnName: "badge_include_muted",
            value: includeMuted
        )
    }

    /// 按当前通知设置计算账号级角标数。
    func badgeCount(for userID: UserID) async throws -> Int {
        try await database.read(paths: paths) { db in
            let setting = try Self.setting(for: userID, db: db)
            guard setting.badgeEnabled else {
                return 0
            }
            return try Self.badgeCount(userID: userID, includeMuted: setting.badgeIncludeMuted, db: db)
        }
    }

    /// 观察账号级角标数。
    func observeBadgeCount(for userID: UserID) async throws -> AnyPublisher<Int, Error> {
        let observation = try await database.observe(paths: paths) { db in
            let setting = try Self.setting(for: userID, db: db)
            guard setting.badgeEnabled else {
                return 0
            }
            return try Self.badgeCount(userID: userID, includeMuted: setting.badgeIncludeMuted, db: db)
        }
        return observation.publisher
    }

    private func upsertBadgeSetting(userID: UserID, columnName: String, value: Bool) async throws {
        let now = Self.currentTimestamp()
        try await database.write(paths: paths) { db in
            try NotificationSettingDatabaseRecord.upsertBadgeSetting(
                userID: userID,
                columnName: columnName,
                value: value,
                updatedAt: now,
                in: db
            )
        }
    }

    private static func setting(for userID: UserID, db: Database) throws -> NotificationSettingRecord {
        try NotificationSettingDatabaseRecord
            .filter(NotificationSettingDatabaseRecord.Columns.userID == userID.rawValue)
            .fetchOne(db)?
            .record ?? .defaultSetting(for: userID)
    }

    private static func badgeCount(userID: UserID, includeMuted: Bool, db: Database) throws -> Int {
        var request = ConversationDatabaseRecord
            .filter(ConversationDatabaseRecord.Columns.userID == userID.rawValue)
            .filter(ConversationDatabaseRecord.Columns.isHidden == false)

        if !includeMuted {
            request = request.filter(ConversationDatabaseRecord.Columns.isMuted == false)
        }

        let badgeCount = try Int.fetchOne(
            db,
            request.select(sum(ConversationDatabaseRecord.Columns.unreadCount))
        )
        return max(0, badgeCount ?? 0)
    }

    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
