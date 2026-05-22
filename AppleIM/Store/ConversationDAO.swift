//
//  ConversationDAO.swift
//  AppleIM
//
//  会话数据访问对象（DAO）
//  负责会话的增删改查操作

import Foundation
import GRDB

/// 会话 DAO
///
/// 负责会话表的数据库操作，支持 upsert、查询、置顶、免打扰等功能
nonisolated struct ConversationDAO: Sendable {
    /// 数据库 Actor
    private let database: DatabaseActor
    /// 账号存储路径
    private let paths: AccountStoragePaths

    init(database: DatabaseActor, paths: AccountStoragePaths) {
        self.database = database
        self.paths = paths
    }

    /// 插入或更新会话
    ///
    /// 使用 UPSERT 语法，存在则更新，不存在则插入
    ///
    /// - Parameter record: 会话记录
    /// - Throws: 数据库操作失败时抛出错误
    func upsert(_ record: ConversationRecord) async throws {
        _ = try await database.write(paths: paths) { db in
            try ConversationDatabaseRecord.upsertRecord(record, in: db)
        }
    }

    /// 查询会话列表
    ///
    /// 按置顶和排序时间戳降序排列，不包含隐藏的会话
    ///
    /// - Parameter userID: 用户 ID
    /// - Returns: 会话记录数组
    /// - Throws: 数据库查询失败时抛出错误
    func listConversations(for userID: UserID) async throws -> [ConversationRecord] {
        try await database.read(paths: paths) { db in
            try Self.visibleConversations(for: userID)
                .fetchAll(db)
                .map(\.record)
        }
    }

    /// 分页查询会话列表
    ///
    /// 按置顶、排序时间戳和会话 ID 降序排列，不包含隐藏的会话。使用游标分页避免新消息插入导致分页漂移。
    ///
    /// - Parameters:
    ///   - userID: 用户 ID
    ///   - limit: 查询数量
    ///   - cursor: 上一页最后一条会话的排序游标
    /// - Returns: 会话记录数组
    /// - Throws: 数据库查询失败时抛出错误
    func listConversations(for userID: UserID, limit: Int, after cursor: ConversationPageCursor?) async throws -> [ConversationRecord] {
        try await database.read(paths: paths) { db in
            var request = Self.visibleConversations(for: userID)
            if let cursor {
                let pinnedValue = cursor.isPinned ? 1 : 0
                let cursorPredicate =
                    ConversationDatabaseRecord.Columns.isPinned < pinnedValue
                    || (
                        ConversationDatabaseRecord.Columns.isPinned == pinnedValue
                        && ConversationDatabaseRecord.Columns.sortTimestamp < cursor.sortTimestamp
                    )
                    || (
                        ConversationDatabaseRecord.Columns.isPinned == pinnedValue
                        && ConversationDatabaseRecord.Columns.sortTimestamp == cursor.sortTimestamp
                        && ConversationDatabaseRecord.Columns.conversationID < cursor.conversationID.rawValue
                    )
                request = request.filter(cursorPredicate)
            }

            return try request
                .limit(max(limit, 0))
                .fetchAll(db)
                .map(\.record)
        }
    }

    /// 统计会话数量
    ///
    /// - Parameter userID: 用户 ID
    /// - Returns: 会话数量
    /// - Throws: 数据库查询失败时抛出错误
    func countConversations(for userID: UserID) async throws -> Int {
        try await database.read(paths: paths) { db in
            try ConversationDatabaseRecord
                .filter(ConversationDatabaseRecord.Columns.userID == userID.rawValue)
                .fetchCount(db)
        }
    }

    /// 根据账号、会话类型和目标 ID 查询会话。
    func conversation(userID: UserID, type: ConversationType, targetID: String) async throws -> ConversationRecord? {
        try await database.read(paths: paths) { db in
            try ConversationDatabaseRecord
                .filter(ConversationDatabaseRecord.Columns.userID == userID.rawValue)
                .filter(ConversationDatabaseRecord.Columns.type == type.rawValue)
                .filter(ConversationDatabaseRecord.Columns.targetID == targetID)
                .filter(ConversationDatabaseRecord.Columns.isHidden == false)
                .order(ConversationDatabaseRecord.Columns.sortTimestamp.desc, ConversationDatabaseRecord.Columns.conversationID.desc)
                .fetchOne(db)?
                .record
        }
    }

    /// 根据账号和会话 ID 查询会话记录。
    func conversation(conversationID: ConversationID, userID: UserID) async throws -> ConversationRecord? {
        try await database.read(paths: paths) { db in
            try ConversationDatabaseRecord
                .filter(ConversationDatabaseRecord.Columns.conversationID == conversationID.rawValue)
                .filter(ConversationDatabaseRecord.Columns.userID == userID.rawValue)
                .filter(ConversationDatabaseRecord.Columns.isHidden == false)
                .fetchOne(db)?
                .record
        }
    }

    /// 标记会话已读
    ///
    /// 将未读数清零
    ///
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - userID: 用户 ID
    /// - Throws: 数据库操作失败时抛出错误
    func markRead(conversationID: ConversationID, userID: UserID) async throws {
        let updatedAt = Self.currentTimestamp()
        _ = try await database.write(paths: paths) { db in
            try ConversationDatabaseRecord
                .filter(ConversationDatabaseRecord.Columns.conversationID == conversationID.rawValue)
                .filter(ConversationDatabaseRecord.Columns.userID == userID.rawValue)
                .updateAll(db, [
                    ConversationDatabaseRecord.Columns.unreadCount.set(to: 0),
                    ConversationDatabaseRecord.Columns.updatedAt.set(to: updatedAt)
                ])
        }
    }

    /// 更新会话置顶状态
    ///
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - userID: 用户 ID
    ///   - isPinned: 是否置顶
    /// - Throws: 数据库操作失败时抛出错误
    func updatePin(conversationID: ConversationID, userID: UserID, isPinned: Bool) async throws {
        try await updateFlag(
            column: ConversationDatabaseRecord.Columns.isPinned,
            value: isPinned,
            conversationID: conversationID,
            userID: userID
        )
    }

    /// 更新会话免打扰状态
    ///
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - userID: 用户 ID
    ///   - isMuted: 是否免打扰
    /// - Throws: 数据库操作失败时抛出错误
    func updateMute(conversationID: ConversationID, userID: UserID, isMuted: Bool) async throws {
        try await updateFlag(
            column: ConversationDatabaseRecord.Columns.isMuted,
            value: isMuted,
            conversationID: conversationID,
            userID: userID
        )
    }

    /// 更新会话标志位（通用方法）
    ///
    /// - Parameters:
    ///   - column: 列名
    ///   - value: 布尔值
    ///   - conversationID: 会话 ID
    ///   - userID: 用户 ID
    /// - Throws: 数据库操作失败时抛出错误
    private func updateFlag(column: Column, value: Bool, conversationID: ConversationID, userID: UserID) async throws {
        let updatedAt = Self.currentTimestamp()
        _ = try await database.write(paths: paths) { db in
            try ConversationDatabaseRecord
                .filter(ConversationDatabaseRecord.Columns.conversationID == conversationID.rawValue)
                .filter(ConversationDatabaseRecord.Columns.userID == userID.rawValue)
                .updateAll(db, [
                    column.set(to: value),
                    ConversationDatabaseRecord.Columns.updatedAt.set(to: updatedAt)
                ])
        }
    }

    /// 获取当前时间戳（秒）
    ///
    /// - Returns: Unix 时间戳
    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }

    /// 会话列表统一排序请求，确保全量和分页查询保持同一排序语义。
    static func visibleConversations(for userID: UserID) -> QueryInterfaceRequest<ConversationDatabaseRecord> {
        ConversationDatabaseRecord
            .filter(ConversationDatabaseRecord.Columns.userID == userID.rawValue)
            .filter(ConversationDatabaseRecord.Columns.isHidden == false)
            .order(
                ConversationDatabaseRecord.Columns.isPinned.desc,
                ConversationDatabaseRecord.Columns.sortTimestamp.desc,
                ConversationDatabaseRecord.Columns.conversationID.desc
            )
    }
}
