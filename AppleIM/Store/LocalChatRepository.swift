//
//  LocalChatRepository.swift
//  AppleIM
//
//  本地聊天仓储
//  实现多个仓储协议，统一管理会话、消息、同步等数据操作

import Combine
import Foundation
import GRDB

/// 通知会话上下文
///
/// 用于发送本地通知时携带会话信息
nonisolated private struct NotificationConversationContext: Equatable, Sendable {
    /// 会话标题（单聊为对方昵称，群聊为群名称）
    let title: String
    /// 是否免打扰
    let isMuted: Bool
}

/// 会话扩展信息，存储在 conversation.extra_json 中
nonisolated private struct ConversationExtraContext: Codable, Equatable, Sendable {
    var hasUnreadMention: Bool?
    var announcement: AnnouncementContext?

    init(hasUnreadMention: Bool? = nil, announcement: AnnouncementContext? = nil) {
        self.hasUnreadMention = hasUnreadMention
        self.announcement = announcement
    }

    enum CodingKeys: String, CodingKey {
        case hasUnreadMention = "has_unread_mention"
        case announcement = "group_announcement"
    }
}

extension Notification.Name {
    /// 聊天存储中的会话摘要、排序或未读状态发生变化。
    static let chatStoreConversationsDidChange = Notification.Name("ChatStoreConversationsDidChange")
}

nonisolated enum ChatStoreConversationChangeNotification {
    static let userIDKey = "userID"
    static let conversationIDsKey = "conversationIDs"
}

/// 群公告扩展信息
nonisolated private struct AnnouncementContext: Codable, Equatable, Sendable {
    let text: String
    let updatedBy: String
    let updatedAt: Int64

    enum CodingKeys: String, CodingKey {
        case text
        case updatedBy = "updated_by"
        case updatedAt = "updated_at"
    }
}

/// 中断的出站消息
///
/// 用于崩溃恢复，记录发送中状态的消息信息
nonisolated private struct InterruptedOutgoingMessage: Equatable, Sendable {
    /// 消息 ID
    let messageID: MessageID
    /// 会话 ID
    let conversationID: ConversationID
    /// 客户端消息 ID（用于幂等重发）
    let clientMessageID: String?
    /// 消息类型
    let type: MessageType
    /// 媒体资源 ID（图片、语音、视频、文件消息）
    let mediaID: String?
}

/// 崩溃恢复写入操作。
///
/// 恢复过程先在内存里计算动作，再一次性进入 GRDB 写事务，避免中途部分提交。
nonisolated private enum MessageRecoveryDatabaseOperation: Sendable {
    case sendStatus(MessageID, MessageSendStatus)
    case uploadStatus(MessageID, MediaUploadStatus, MediaUploadAck?, LocalChatRepository.MediaUploadTableSpec)
    case pendingJob(PendingJobInput)

    func apply(updatedAt: Int64, in db: Database) throws {
        switch self {
        case let .sendStatus(messageID, status):
            try LocalChatRepository.updateMessageSendStatus(messageID: messageID, status: status, ack: nil, in: db)
        case let .uploadStatus(messageID, status, ack, tableSpec):
            try LocalChatRepository.updateMediaUploadStatus(messageID: messageID, status: status, uploadAck: ack, updatedAt: updatedAt, tableSpec: tableSpec, in: db)
        case let .pendingJob(input):
            try LocalChatRepository.upsertPendingJob(input, status: .pending, retryCount: 0, updatedAt: updatedAt, createdAt: updatedAt, in: db)
        }
    }
}

/// 同步入库去重键集合。
nonisolated private struct ExistingMessageDedupKeys: Equatable, Sendable {
    var clientMessageIDs: Set<String> = []
    var serverMessageIDs: Set<String> = []
    var conversationSequences: Set<String> = []

    func containsDuplicate(for message: IncomingSyncMessage) -> Bool {
        if let clientMessageID = message.clientMessageID, clientMessageIDs.contains(clientMessageID) {
            return true
        }

        if let serverMessageID = message.serverMessageID, serverMessageIDs.contains(serverMessageID) {
            return true
        }

        return conversationSequences.contains(Self.sequenceKey(conversationID: message.conversationID, sequence: message.sequence))
    }

    static func sequenceKey(conversationID: ConversationID, sequence: Int64) -> String {
        "\(conversationID.rawValue)#\(sequence)"
    }
}

/// 同步去重查询的轻量行模型。
nonisolated private struct ExistingMessageDedupKeyRecord: Sendable {
    let clientMessageID: String?
    let serverMessageID: String?
    let conversationID: ConversationID?
    let sequence: Int64?

    init(
        clientMessageID: String?,
        serverMessageID: String?,
        conversationID: ConversationID?,
        sequence: Int64?
    ) {
        self.clientMessageID = clientMessageID
        self.serverMessageID = serverMessageID
        self.conversationID = conversationID
        self.sequence = sequence
    }
}


/// 本地聊天仓储
///
/// 聚合多个 DAO，实现会话、消息、同步等多个仓储协议
/// 所有操作通过 DatabaseActor 串行化执行
nonisolated struct LocalChatRepository: ConversationRepository, ConversationObservationRepository, ContactRepository, NotificationSettingsRepository, MessageRepository, MessageObservationRepository, MessageSendRecoveryRepository, MessageCrashRecoveryRepository, PendingJobRepository, MediaIndexRepository, EmojiRepository, SyncStore {
    /// 数据库 Actor
    private let database: DatabaseActor
    /// 账号存储路径
    private let paths: AccountStoragePaths
    /// 会话 DAO
    private let conversationDAO: ConversationDAO
    /// 联系人 DAO
    private let contactDAO: ContactDAO
    /// 消息 DAO
    private let messageDAO: MessageDAO
    /// 表情 DAO
    private let emojiDAO: EmojiDAO
    /// 通知设置与角标存储协作者
    private let notificationSettingsStore: NotificationSettingsStore
    /// 事务后事件分发器
    private let eventDispatcher: any ChatStoreEventDispatching

    init(
        database: DatabaseActor,
        paths: AccountStoragePaths,
        localNotificationManager: (any LocalNotificationManaging)? = nil,
        applicationBadgeManager: (any ApplicationBadgeManaging)? = nil,
        eventDispatcher: (any ChatStoreEventDispatching)? = nil
    ) {
        self.database = database
        self.paths = paths
        self.conversationDAO = ConversationDAO(database: database, paths: paths)
        self.contactDAO = ContactDAO(database: database, paths: paths)
        self.messageDAO = MessageDAO(database: database, paths: paths)
        self.emojiDAO = EmojiDAO(database: database, paths: paths)
        self.notificationSettingsStore = NotificationSettingsStore(database: database, paths: paths)
        self.eventDispatcher = eventDispatcher ?? DefaultChatStoreEventDispatcher(
            database: database,
            paths: paths,
            localNotificationManager: localNotificationManager,
            applicationBadgeManager: applicationBadgeManager
        )
    }

    // MARK: - ConversationRepository

    /// 查询用户的所有会话
    ///
    /// - Parameter userID: 用户 ID
    /// - Returns: 会话列表，按置顶和时间排序
    /// - Throws: 数据库查询错误
    func listConversations(for userID: UserID) async throws -> [Conversation] {
        let records = try await conversationDAO.listConversations(for: userID)
        let extras = try await conversationExtras(conversationIDs: records.map(\.id))
        return records.map { Self.conversation(from: $0, extra: extras[$0.id]) }
    }

    /// 分页查询用户的会话列表
    ///
    /// - Parameters:
    ///   - userID: 用户 ID
    ///   - limit: 每页数量
    ///   - cursor: 上一页最后一条会话的排序游标
    /// - Returns: 会话列表
    /// - Throws: 数据库查询错误
    func listConversations(for userID: UserID, limit: Int, after cursor: ConversationPageCursor?) async throws -> [Conversation] {
        let records = try await conversationDAO.listConversations(for: userID, limit: limit, after: cursor)
        let extras = try await conversationExtras(conversationIDs: records.map(\.id))
        return records.map { Self.conversation(from: $0, extra: extras[$0.id]) }
    }

    /// 观察账号首屏会话列表。
    func observeConversations(for userID: UserID, limit: Int) async throws -> AnyPublisher<[Conversation], Error> {
        let boundedLimit = max(1, limit)
        let observation = try await database.observe(paths: paths) { db in
            let records = try ConversationDAO.visibleConversations(for: userID)
                .limit(boundedLimit)
                .fetchAll(db)
            return try Self.conversations(from: records)
        }
        return observation.publisher
    }

    /// 查询账号下所有可见会话的未读总数。
    func unreadConversationCount(for userID: UserID) async throws -> Int {
        try await database.read(paths: paths) { db in
            try Self.unreadConversationCount(userID: userID, db: db)
        }
    }

    /// 观察账号级未读角标数。
    func observeUnreadBadgeCount(for userID: UserID) async throws -> AnyPublisher<Int, Error> {
        try await notificationSettingsStore.observeBadgeCount(for: userID)
    }

    /// 插入或更新会话
    ///
    /// 流程：
    /// 1. 写入会话记录
    /// 2. 调度搜索索引更新
    /// 3. 刷新应用角标
    ///
    /// - Parameter record: 会话记录
    /// - Throws: 数据库写入错误
    func upsertConversation(_ record: ConversationRecord) async throws {
        try await conversationDAO.upsert(record)
        scheduleConversationIndex(conversationID: record.id, userID: record.userID)
        _ = try await refreshApplicationBadge(userID: record.userID)
    }

    /// 查询指定账号下的完整会话记录，用于需要 targetID 等存储字段的 store/service 层逻辑。
    func conversationRecord(conversationID: ConversationID, userID: UserID) async throws -> ConversationRecord? {
        try await conversationDAO.conversation(conversationID: conversationID, userID: userID)
    }

    /// 按会话类型和目标 ID 查询完整会话记录。
    func conversationRecord(userID: UserID, type: ConversationType, targetID: String) async throws -> ConversationRecord? {
        try await conversationDAO.conversation(userID: userID, type: type, targetID: targetID)
    }

    /// 批量插入初始会话
    ///
    /// 用于首次同步或数据恢复场景，批量写入会话记录
    ///
    /// - Parameter records: 会话记录列表
    /// - Throws: 数据库事务错误
    func insertInitialConversations(_ records: [ConversationRecord]) async throws {
        guard !records.isEmpty else { return }

        _ = try await database.write(paths: paths) { db in
            for record in records {
                try ConversationDatabaseRecord.upsertRecord(record, in: db)
            }
        }
    }

    /// 批量插入首次演示文本消息。
    func insertInitialTextMessages(_ messages: [InitialTextMessageInput]) async throws {
        guard !messages.isEmpty else { return }

        let plans = messages.map(MessageDAO.makeInitialTextWritePlan)
        _ = try await database.write(paths: paths) { db in
            for plan in plans {
                try plan.write(in: db)
            }
        }
    }

    /// 标记会话已读
    ///
    /// 清空会话未读数，并刷新应用角标
    ///
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - userID: 用户 ID
    /// - Throws: 数据库更新错误
    func markConversationRead(conversationID: ConversationID, userID: UserID) async throws {
        let now = Self.currentTimestamp()
        let extra = try await conversationExtra(conversationID: conversationID).map {
            var mutable = $0
            mutable.hasUnreadMention = false
            return mutable
        }
        _ = try await database.write(paths: paths) { db in
            try ConversationDatabaseRecord
                .filter(ConversationDatabaseRecord.Columns.conversationID == conversationID.rawValue)
                .filter(ConversationDatabaseRecord.Columns.userID == userID.rawValue)
                .updateAll(db, [
                    ConversationDatabaseRecord.Columns.unreadCount.set(to: 0),
                    ConversationDatabaseRecord.Columns.updatedAt.set(to: now)
                ])

            try MessageDatabaseRecord
                .filter(MessageDatabaseRecord.Columns.conversationID == conversationID.rawValue)
                .filter(MessageDatabaseRecord.Columns.direction == MessageDirection.incoming.rawValue)
                .filter(MessageDatabaseRecord.Columns.readStatus == MessageReadStatus.unread.rawValue)
                .filter(MessageDatabaseRecord.Columns.isDeleted == false)
                .updateAll(db, MessageDatabaseRecord.Columns.readStatus.set(to: MessageReadStatus.read.rawValue))

            if let extra {
                try Self.updateConversationExtra(conversationID: conversationID, extra: extra, updatedAt: now, in: db)
            }
        }
        _ = try await refreshApplicationBadge(userID: userID)
        eventDispatcher.postConversationsDidChange(userID: userID, conversationIDs: [conversationID])
    }

    /// 更新会话置顶状态
    ///
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - userID: 用户 ID
    ///   - isPinned: 是否置顶
    /// - Throws: 数据库更新错误
    func updateConversationPin(conversationID: ConversationID, userID: UserID, isPinned: Bool) async throws {
        try await conversationDAO.updatePin(conversationID: conversationID, userID: userID, isPinned: isPinned)
    }

    /// 更新会话免打扰状态
    ///
    /// 更新后刷新应用角标（免打扰会话可能不计入角标）
    ///
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - userID: 用户 ID
    ///   - isMuted: 是否免打扰
    /// - Throws: 数据库更新错误
    func updateConversationMute(conversationID: ConversationID, userID: UserID, isMuted: Bool) async throws {
        try await conversationDAO.updateMute(conversationID: conversationID, userID: userID, isMuted: isMuted)
        _ = try await refreshApplicationBadge(userID: userID)
    }

    /// 批量写入群成员
    func upsertGroupMembers(_ members: [GroupMember]) async throws {
        guard !members.isEmpty else { return }

        _ = try await database.write(paths: paths) { db in
            for member in members {
                try GroupMemberDatabaseRecord.upsertRecord(member, in: db)
            }
        }
    }

    /// 查询群成员
    func groupMembers(conversationID: ConversationID) async throws -> [GroupMember] {
        try await database.read(paths: paths) { db in
            try GroupMemberDatabaseRecord
                .filter(GroupMemberDatabaseRecord.Columns.conversationID == conversationID.rawValue)
                .order(
                    GroupMemberDatabaseRecord.Columns.role.desc,
                    GroupMemberDatabaseRecord.Columns.joinTime.asc,
                    GroupMemberDatabaseRecord.Columns.id.asc
                )
                .fetchAll(db)
                .map(\.member)
        }
    }

    /// 查询当前用户群角色
    func currentMemberRole(conversationID: ConversationID, userID: UserID) async throws -> GroupMemberRole? {
        try await database.read(paths: paths) { db in
            try GroupMemberDatabaseRecord
                .filter(GroupMemberDatabaseRecord.Columns.conversationID == conversationID.rawValue)
                .filter(GroupMemberDatabaseRecord.Columns.memberID == userID.rawValue)
                .fetchOne(db)?
                .member
                .role
        }
    }

    /// 查询群公告
    func groupAnnouncement(conversationID: ConversationID) async throws -> GroupAnnouncement? {
        guard let extra = try await conversationExtra(conversationID: conversationID),
              let announcement = extra.announcement else {
            return nil
        }

        return GroupAnnouncement(
            conversationID: conversationID,
            text: announcement.text,
            updatedBy: UserID(rawValue: announcement.updatedBy),
            updatedAt: announcement.updatedAt
        )
    }

    /// 更新群公告
    func updateGroupAnnouncement(conversationID: ConversationID, userID: UserID, text: String) async throws {
        guard try await currentMemberRole(conversationID: conversationID, userID: userID)?.canManageAnnouncement == true else {
            throw GroupChatError.permissionDenied
        }

        var extra = try await conversationExtra(conversationID: conversationID) ?? ConversationExtraContext()
        let now = Self.currentTimestamp()
        extra.announcement = AnnouncementContext(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            updatedBy: userID.rawValue,
            updatedAt: now
        )
        try await updateConversationExtra(conversationID: conversationID, extra: extra, updatedAt: now)
    }

    // MARK: - ContactRepository

    /// 查询当前账号未删除联系人。
    func listContacts(for userID: UserID) async throws -> [ContactRecord] {
        try await contactDAO.listContacts(for: userID)
    }

    /// 统计当前账号联系人数量。
    func countContacts(for userID: UserID) async throws -> Int {
        try await contactDAO.countContacts(for: userID)
    }

    /// 查询单个联系人。
    func contact(id contactID: ContactID, userID: UserID) async throws -> ContactRecord? {
        try await contactDAO.contact(id: contactID, userID: userID)
    }

    /// 插入或更新联系人。
    func upsertContact(_ record: ContactRecord) async throws {
        try await contactDAO.upsert(record)
    }

    /// 批量插入或更新联系人。
    func upsertContacts(_ records: [ContactRecord]) async throws {
        try await contactDAO.upsert(records)
    }

    /// 获取联系人对应会话；没有会话时创建本地空会话。
    func conversationForContact(contactID: ContactID, userID: UserID) async throws -> Conversation {
        guard let contact = try await contact(id: contactID, userID: userID) else {
            throw ContactStoreError.contactNotFound(contactID)
        }

        guard let conversationType = contact.type.conversationType else {
            throw ContactStoreError.unsupportedContactType(contact.type)
        }

        if let existing = try await conversationDAO.conversation(userID: userID, type: conversationType, targetID: contact.wxid) {
            return Self.conversation(from: existing)
        }

        let now = Self.currentTimestamp()
        let conversationID = Self.conversationID(for: contact)
        let record = ConversationRecord(
            id: conversationID,
            userID: userID,
            type: conversationType,
            targetID: contact.wxid,
            title: contact.displayName,
            avatarURL: contact.avatarURL,
            lastMessageID: nil,
            lastMessageTime: nil,
            lastMessageDigest: "No messages yet",
            unreadCount: 0,
            draftText: nil,
            isPinned: false,
            isMuted: false,
            isHidden: false,
            sortTimestamp: now,
            updatedAt: now,
            createdAt: now
        )

        try await conversationDAO.upsert(record)
        scheduleConversationIndex(conversationID: record.id, userID: userID)
        eventDispatcher.postConversationsDidChange(userID: userID, conversationIDs: [record.id])
        return Self.conversation(from: record)
    }

    // MARK: - NotificationSettingsRepository

    /// 获取用户的通知设置
    ///
    /// 如果数据库中不存在记录，返回默认设置（全部开启）
    ///
    /// - Parameter userID: 用户 ID
    /// - Returns: 通知设置记录
    /// - Throws: 数据库查询错误
    func notificationSetting(for userID: UserID) async throws -> NotificationSettingRecord {
        try await notificationSettingsStore.setting(for: userID)
    }

    /// 更新应用角标是否启用
    ///
    /// 更新后立即刷新应用角标数字
    ///
    /// - Parameters:
    ///   - userID: 用户 ID
    ///   - isEnabled: 是否启用角标
    /// - Throws: 数据库更新错误
    func updateBadgeEnabled(userID: UserID, isEnabled: Bool) async throws {
        try await notificationSettingsStore.updateBadgeEnabled(userID: userID, isEnabled: isEnabled)
        _ = try await refreshApplicationBadge(userID: userID)
    }

    /// 更新角标是否包含免打扰会话
    ///
    /// 更新后立即刷新应用角标数字
    ///
    /// - Parameters:
    ///   - userID: 用户 ID
    ///   - includeMuted: 是否包含免打扰会话的未读数
    /// - Throws: 数据库更新错误
    func updateBadgeIncludeMuted(userID: UserID, includeMuted: Bool) async throws {
        try await notificationSettingsStore.updateBadgeIncludeMuted(userID: userID, includeMuted: includeMuted)
        _ = try await refreshApplicationBadge(userID: userID)
    }

    /// 刷新应用角标
    ///
    /// 根据通知设置计算未读数，并更新应用图标角标
    ///
    /// - Parameter userID: 用户 ID
    /// - Returns: 计算后的角标数字
    /// - Throws: 数据库查询错误
    func refreshApplicationBadge(userID: UserID) async throws -> Int {
        let badgeCount = try await notificationSettingsStore.badgeCount(for: userID)
        await eventDispatcher.setApplicationBadgeNumber(badgeCount)

        return badgeCount
    }

    // MARK: - MessageRepository

    /// 插入出站文本消息
    ///
    /// 流程：
    /// 1. 生成消息和内容表 SQL 语句
    /// 2. 事务写入数据库
    /// 3. 调度搜索索引更新
    /// 4. 调度会话索引更新
    ///
    /// - Parameter input: 文本消息输入
    /// - Returns: 已存储的消息
    /// - Throws: 数据库事务错误
    func insertOutgoingTextMessage(_ input: OutgoingTextMessageInput) async throws -> StoredMessage {
        let plan = MessageDAO.makeOutgoingTextWritePlan(input)
        try await writeMessagePlan(plan)
        scheduleMessageIndex(messageID: plan.message.id, userID: input.userID)
        scheduleConversationIndex(conversationID: input.conversationID, userID: input.userID)
        return plan.message
    }

    func insertOutgoingImageMessage(_ input: OutgoingImageMessageInput) async throws -> StoredMessage {
        let plan = MessageDAO.makeOutgoingImageWritePlan(input)
        try await writeMessagePlan(plan)
        try await upsertMediaIndexRecords(Self.mediaIndexRecords(for: input.image, userID: input.userID, createdAt: input.localTime))
        scheduleConversationIndex(conversationID: input.conversationID, userID: input.userID)
        return plan.message
    }

    func insertOutgoingVoiceMessage(_ input: OutgoingVoiceMessageInput) async throws -> StoredMessage {
        let plan = MessageDAO.makeOutgoingVoiceWritePlan(input)
        try await writeMessagePlan(plan)
        try await upsertMediaIndexRecords(Self.mediaIndexRecords(for: input.voice, userID: input.userID, createdAt: input.localTime))
        scheduleConversationIndex(conversationID: input.conversationID, userID: input.userID)
        return plan.message
    }

    func insertOutgoingVideoMessage(_ input: OutgoingVideoMessageInput) async throws -> StoredMessage {
        let plan = MessageDAO.makeOutgoingVideoWritePlan(input)
        try await writeMessagePlan(plan)
        try await upsertMediaIndexRecords(Self.mediaIndexRecords(for: input.video, userID: input.userID, createdAt: input.localTime))
        scheduleConversationIndex(conversationID: input.conversationID, userID: input.userID)
        return plan.message
    }

    func insertOutgoingFileMessage(_ input: OutgoingFileMessageInput) async throws -> StoredMessage {
        let plan = MessageDAO.makeOutgoingFileWritePlan(input)
        try await writeMessagePlan(plan)
        try await upsertMediaIndexRecords(Self.mediaIndexRecords(for: input.file, userID: input.userID, createdAt: input.localTime))
        scheduleConversationIndex(conversationID: input.conversationID, userID: input.userID)
        return plan.message
    }

    func insertOutgoingEmojiMessage(_ input: OutgoingEmojiMessageInput) async throws -> StoredMessage {
        let plan = MessageDAO.makeOutgoingEmojiWritePlan(input)
        try await writeMessagePlan(plan)
        scheduleConversationIndex(conversationID: input.conversationID, userID: input.userID)
        return plan.message
    }

    func listMessages(conversationID: ConversationID, limit: Int, beforeSortSeq: Int64?) async throws -> [StoredMessage] {
        try await messageDAO.listMessages(
            conversationID: conversationID,
            limit: limit,
            beforeSortSeq: beforeSortSeq
        )
    }

    /// 观察聊天页最新消息窗口。
    ///
    /// 历史分页仍使用显式游标查询；这里仅用于同步最新一页内容，避免观察刷新重置历史分页窗口。
    func observeLatestMessages(conversationID: ConversationID, limit: Int) async throws -> AnyPublisher<[StoredMessage], Error> {
        try await messageDAO.observeLatestMessages(conversationID: conversationID, limit: max(1, limit))
    }

    func message(messageID: MessageID) async throws -> StoredMessage? {
        try await messageDAO.message(messageID: messageID)
    }

    private func writeMessagePlan(_ plan: MessageWritePlan) async throws {
        _ = try await database.write(paths: paths) { db in
            try plan.write(in: db)
        }
    }

    func updateMessageSendStatus(messageID: MessageID, status: MessageSendStatus, ack: MessageSendAck?) async throws {
        try await updateMessageSendStatus(messageID: messageID, status: status, ack: ack, pendingJob: nil)
    }

    // MARK: - MessageSendRecoveryRepository

    func updateMessageSendStatus(
        messageID: MessageID,
        status: MessageSendStatus,
        ack: MessageSendAck?,
        pendingJob: PendingJobInput?
    ) async throws {
        let now = Self.currentTimestamp()
        _ = try await database.write(paths: paths) { db in
            try Self.updateMessageSendStatus(messageID: messageID, status: status, ack: ack, in: db)
            if let pendingJob {
                try Self.upsertPendingJob(pendingJob, status: .pending, retryCount: 0, updatedAt: now, createdAt: now, in: db)
            }
        }
    }

    // MARK: - MessageCrashRecoveryRepository

    func recoverInterruptedOutgoingMessages(
        userID: UserID,
        retryPolicy: MessageRetryPolicy,
        now: Int64
    ) async throws -> MessageCrashRecoveryResult {
        let interruptedMessages = try await interruptedOutgoingMessages(userID: userID)
        guard !interruptedMessages.isEmpty else {
            return MessageCrashRecoveryResult(
                scannedMessageCount: 0,
                recoveredMessageCount: 0,
                pendingJobCount: 0,
                failedMessageCount: 0
            )
        }

        var operations: [MessageRecoveryDatabaseOperation] = []
        var recoveredMessageCount = 0
        var pendingJobCount = 0
        var failedMessageCount = 0

        for message in interruptedMessages {
            switch message.type {
            case .text:
                guard let clientMessageID = message.clientMessageID else {
                    operations.append(.sendStatus(message.messageID, .failed))
                    failedMessageCount += 1
                    continue
                }

                let pendingJob = try PendingMessageJobFactory.messageResendInput(
                    messageID: message.messageID,
                    conversationID: message.conversationID,
                    clientMessageID: clientMessageID,
                    userID: userID,
                    failureReason: .ackMissing,
                    maxRetryCount: retryPolicy.maxRetryCount,
                    nextRetryAt: now
                )
                operations.append(.sendStatus(message.messageID, .pending))
                operations.append(.pendingJob(pendingJob))
                recoveredMessageCount += 1
                pendingJobCount += 1
            case .image:
                guard let clientMessageID = message.clientMessageID, let mediaID = message.mediaID else {
                    operations.append(.sendStatus(message.messageID, .failed))
                    operations.append(.uploadStatus(message.messageID, .failed, nil, .image))
                    failedMessageCount += 1
                    continue
                }

                let pendingJob = try PendingMessageJobFactory.imageUploadInput(
                    messageID: message.messageID,
                    conversationID: message.conversationID,
                    clientMessageID: clientMessageID,
                    mediaID: mediaID,
                    userID: userID,
                    failureReason: "interrupted",
                    maxRetryCount: retryPolicy.maxRetryCount,
                    nextRetryAt: now
                )
                operations.append(.sendStatus(message.messageID, .pending))
                operations.append(.uploadStatus(message.messageID, .pending, nil, .image))
                operations.append(.pendingJob(pendingJob))
                recoveredMessageCount += 1
                pendingJobCount += 1
            case .video:
                guard let clientMessageID = message.clientMessageID, let mediaID = message.mediaID else {
                    operations.append(.sendStatus(message.messageID, .failed))
                    operations.append(.uploadStatus(message.messageID, .failed, nil, .video))
                    failedMessageCount += 1
                    continue
                }

                let pendingJob = try PendingMessageJobFactory.videoUploadInput(
                    messageID: message.messageID,
                    conversationID: message.conversationID,
                    clientMessageID: clientMessageID,
                    mediaID: mediaID,
                    userID: userID,
                    failureReason: "interrupted",
                    maxRetryCount: retryPolicy.maxRetryCount,
                    nextRetryAt: now
                )
                operations.append(.sendStatus(message.messageID, .pending))
                operations.append(.uploadStatus(message.messageID, .pending, nil, .video))
                operations.append(.pendingJob(pendingJob))
                recoveredMessageCount += 1
                pendingJobCount += 1
            case .file:
                guard let clientMessageID = message.clientMessageID, let mediaID = message.mediaID else {
                    operations.append(.sendStatus(message.messageID, .failed))
                    operations.append(.uploadStatus(message.messageID, .failed, nil, .file))
                    failedMessageCount += 1
                    continue
                }

                let pendingJob = try PendingMessageJobFactory.fileUploadInput(
                    messageID: message.messageID,
                    conversationID: message.conversationID,
                    clientMessageID: clientMessageID,
                    mediaID: mediaID,
                    userID: userID,
                    failureReason: "interrupted",
                    maxRetryCount: retryPolicy.maxRetryCount,
                    nextRetryAt: now
                )
                operations.append(.sendStatus(message.messageID, .pending))
                operations.append(.uploadStatus(message.messageID, .pending, nil, .file))
                operations.append(.pendingJob(pendingJob))
                recoveredMessageCount += 1
                pendingJobCount += 1
            case .voice:
                operations.append(.sendStatus(message.messageID, .failed))
                operations.append(.uploadStatus(message.messageID, .failed, nil, .voice))
                failedMessageCount += 1
            default:
                operations.append(.sendStatus(message.messageID, .failed))
                failedMessageCount += 1
            }
        }

        let operationsForTransaction = operations
        _ = try await database.write(paths: paths) { db in
            for operation in operationsForTransaction {
                try operation.apply(updatedAt: now, in: db)
            }
        }

        return MessageCrashRecoveryResult(
            scannedMessageCount: interruptedMessages.count,
            recoveredMessageCount: recoveredMessageCount,
            pendingJobCount: pendingJobCount,
            failedMessageCount: failedMessageCount
        )
    }

    func resendTextMessage(messageID: MessageID) async throws -> StoredMessage {
        try await messageDAO.prepareTextMessageForResend(messageID: messageID)
    }

    func resendImageMessage(messageID: MessageID) async throws -> StoredMessage {
        return try await prepareMediaMessageForResend(
            messageID: messageID,
            expectedType: .image,
            tableSpec: .image
        )
    }

    func resendVideoMessage(messageID: MessageID) async throws -> StoredMessage {
        try await prepareMediaMessageForResend(
            messageID: messageID,
            expectedType: .video,
            tableSpec: .video
        )
    }

    func resendFileMessage(messageID: MessageID) async throws -> StoredMessage {
        try await prepareMediaMessageForResend(
            messageID: messageID,
            expectedType: .file,
            tableSpec: .file
        )
    }

    private func prepareMediaMessageForResend(
        messageID: MessageID,
        expectedType: MessageType,
        tableSpec: MediaUploadTableSpec
    ) async throws -> StoredMessage {
        guard let existingMessage = try await messageDAO.message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        guard
            existingMessage.type == expectedType,
            existingMessage.state.sendStatus == .failed,
            !existingMessage.state.isRevoked,
            !existingMessage.state.isDeleted
        else {
            throw ChatStoreError.messageCannotBeResent(messageID)
        }

        let now = Self.currentTimestamp()
        _ = try await database.write(paths: paths) { db in
            try Self.updateMessageSendStatus(messageID: messageID, status: .sending, ack: nil, in: db)
            try Self.updateMediaUploadStatus(messageID: messageID, status: .uploading, uploadAck: nil, updatedAt: now, tableSpec: tableSpec, in: db)
        }

        guard let updatedMessage = try await messageDAO.message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        return updatedMessage
    }

    func updateImageUploadStatus(
        messageID: MessageID,
        uploadStatus: MediaUploadStatus,
        uploadAck: MediaUploadAck?,
        sendStatus: MessageSendStatus,
        sendAck: MessageSendAck?,
        pendingJob: PendingJobInput?
    ) async throws {
        try await updateMediaUploadStatus(
            messageID: messageID,
            uploadStatus: uploadStatus,
            uploadAck: uploadAck,
            sendStatus: sendStatus,
            sendAck: sendAck,
            pendingJob: pendingJob,
            tableSpec: .image
        )
    }

    func updateVoiceUploadStatus(
        messageID: MessageID,
        uploadStatus: MediaUploadStatus,
        uploadAck: MediaUploadAck?,
        sendStatus: MessageSendStatus,
        sendAck: MessageSendAck?
    ) async throws {
        try await updateMediaUploadStatus(
            messageID: messageID,
            uploadStatus: uploadStatus,
            uploadAck: uploadAck,
            sendStatus: sendStatus,
            sendAck: sendAck,
            pendingJob: nil,
            tableSpec: .voice
        )
    }

    func updateVideoUploadStatus(
        messageID: MessageID,
        uploadStatus: MediaUploadStatus,
        uploadAck: MediaUploadAck?,
        sendStatus: MessageSendStatus,
        sendAck: MessageSendAck?,
        pendingJob: PendingJobInput?
    ) async throws {
        try await updateMediaUploadStatus(
            messageID: messageID,
            uploadStatus: uploadStatus,
            uploadAck: uploadAck,
            sendStatus: sendStatus,
            sendAck: sendAck,
            pendingJob: pendingJob,
            tableSpec: .video
        )
    }

    func updateFileUploadStatus(
        messageID: MessageID,
        uploadStatus: MediaUploadStatus,
        uploadAck: MediaUploadAck?,
        sendStatus: MessageSendStatus,
        sendAck: MessageSendAck?,
        pendingJob: PendingJobInput?
    ) async throws {
        try await updateMediaUploadStatus(
            messageID: messageID,
            uploadStatus: uploadStatus,
            uploadAck: uploadAck,
            sendStatus: sendStatus,
            sendAck: sendAck,
            pendingJob: pendingJob,
            tableSpec: .file
        )
    }

    private func updateMediaUploadStatus(
        messageID: MessageID,
        uploadStatus: MediaUploadStatus,
        uploadAck: MediaUploadAck?,
        sendStatus: MessageSendStatus,
        sendAck: MessageSendAck?,
        pendingJob: PendingJobInput?,
        tableSpec: MediaUploadTableSpec
    ) async throws {
        let now = Self.currentTimestamp()
        _ = try await database.write(paths: paths) { db in
            try Self.updateMessageSendStatus(messageID: messageID, status: sendStatus, ack: sendAck, in: db)
            try Self.updateMediaUploadStatus(messageID: messageID, status: uploadStatus, uploadAck: uploadAck, updatedAt: now, tableSpec: tableSpec, in: db)
            if let pendingJob {
                try Self.upsertPendingJob(pendingJob, status: .pending, retryCount: 0, updatedAt: now, createdAt: now, in: db)
            }
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws {
        guard let storedMessage = try await messageDAO.message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        guard storedMessage.type == .voice else {
            return
        }

        _ = try await database.write(paths: paths) { db in
            try MessageDatabaseRecord
                .filter(MessageDatabaseRecord.Columns.messageID == messageID.rawValue)
                .filter(MessageDatabaseRecord.Columns.messageType == MessageType.voice.rawValue)
                .updateAll(db, MessageDatabaseRecord.Columns.readStatus.set(to: MessageReadStatus.read.rawValue))
        }
    }

    func markMessageDeleted(messageID: MessageID, userID: UserID) async throws {
        guard let storedMessage = try await messageDAO.message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        let now = Self.currentTimestamp()
        _ = try await database.write(paths: paths) { db in
            try MessageDatabaseRecord
                .filter(MessageDatabaseRecord.Columns.messageID == messageID.rawValue)
                .updateAll(db, MessageDatabaseRecord.Columns.isDeleted.set(to: true))

            try Self.refreshConversationSummary(
                conversationID: storedMessage.conversationID,
                userID: userID,
                updatedAt: now,
                in: db
            )
        }
        scheduleMessageRemoval(messageID: messageID, userID: userID)
        scheduleConversationIndex(conversationID: storedMessage.conversationID, userID: userID)
    }

    func revokeMessage(messageID: MessageID, userID: UserID, replacementText: String) async throws -> StoredMessage {
        guard let storedMessage = try await messageDAO.message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        let now = Self.currentTimestamp()
        _ = try await database.write(paths: paths) { db in
            try MessageDatabaseRecord
                .filter(MessageDatabaseRecord.Columns.messageID == messageID.rawValue)
                .filter(MessageDatabaseRecord.Columns.isDeleted == false)
                .updateAll(db, MessageDatabaseRecord.Columns.revokeStatus.set(to: 1))

            try MessageRevokeDatabaseRecord.upsertRecord(
                MessageRevokeDatabaseRecord(
                    messageID: messageID,
                    operatorID: userID,
                    revokeTime: now,
                    replaceText: replacementText
                ),
                in: db
            )

            try Self.refreshConversationSummary(
                conversationID: storedMessage.conversationID,
                userID: userID,
                updatedAt: now,
                in: db
            )
        }

        guard let updatedMessage = try await messageDAO.message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        scheduleMessageRemoval(messageID: messageID, userID: userID)
        scheduleConversationIndex(conversationID: storedMessage.conversationID, userID: userID)
        return updatedMessage
    }

    func saveDraft(conversationID: ConversationID, userID: UserID, text: String) async throws {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            try await clearDraft(conversationID: conversationID, userID: userID)
            return
        }

        let now = Self.currentTimestamp()
        _ = try await database.write(paths: paths) { db in
            try DraftDatabaseRecord.upsertRecord(
                DraftDatabaseRecord(conversationID: conversationID, text: text, updatedAt: now),
                in: db
            )

            let maxSortTimestamp = try Int64.fetchOne(
                db,
                ConversationDatabaseRecord
                    .filter(ConversationDatabaseRecord.Columns.userID == userID.rawValue)
                    .select(max(ConversationDatabaseRecord.Columns.sortTimestamp))
            ) ?? now

            try ConversationDatabaseRecord
                .filter(ConversationDatabaseRecord.Columns.conversationID == conversationID.rawValue)
                .filter(ConversationDatabaseRecord.Columns.userID == userID.rawValue)
                .updateAll(db, [
                    ConversationDatabaseRecord.Columns.draftText.set(to: text),
                    ConversationDatabaseRecord.Columns.sortTimestamp.set(to: maxSortTimestamp + 1),
                    ConversationDatabaseRecord.Columns.updatedAt.set(to: now)
                ])
        }
        scheduleConversationIndex(conversationID: conversationID, userID: userID)
    }

    func draft(conversationID: ConversationID, userID: UserID) async throws -> String? {
        try await database.read(paths: paths) { db in
            try ConversationDatabaseRecord
                .filter(ConversationDatabaseRecord.Columns.conversationID == conversationID.rawValue)
                .filter(ConversationDatabaseRecord.Columns.userID == userID.rawValue)
                .fetchOne(db)?
                .record
                .draftText
        }
    }

    func clearDraft(conversationID: ConversationID, userID: UserID) async throws {
        let now = Self.currentTimestamp()
        _ = try await database.write(paths: paths) { db in
            try Table("draft")
                .filter(Column("conversation_id") == conversationID.rawValue)
                .deleteAll(db)

            try ConversationDatabaseRecord
                .filter(ConversationDatabaseRecord.Columns.conversationID == conversationID.rawValue)
                .filter(ConversationDatabaseRecord.Columns.userID == userID.rawValue)
                .updateAll(db, [
                    ConversationDatabaseRecord.Columns.draftText.set(to: nil as String?),
                    ConversationDatabaseRecord.Columns.updatedAt.set(to: now)
                ])
        }
        scheduleConversationIndex(conversationID: conversationID, userID: userID)
    }

    // MARK: - PendingJobRepository

    func upsertPendingJob(_ input: PendingJobInput) async throws -> PendingJob {
        let now = Self.currentTimestamp()
        return try await database.write(paths: paths) { db in
            let job = PendingJob(
                id: input.id,
                userID: input.userID,
                type: input.type,
                bizKey: input.bizKey,
                payloadJSON: input.payloadJSON,
                status: .pending,
                retryCount: 0,
                maxRetryCount: input.maxRetryCount,
                nextRetryAt: input.nextRetryAt,
                updatedAt: now,
                createdAt: now
            )
            return try PendingJobDatabaseRecord.upsertNonTerminalJob(job, in: db)
        }
    }

    func pendingJob(id: String) async throws -> PendingJob? {
        try await database.read(paths: paths) { db in
            try PendingJobDatabaseRecord
                .filter(PendingJobDatabaseRecord.Columns.jobID == id)
                .fetchOne(db)?
                .job
        }
    }

    func recoverablePendingJobs(userID: UserID, now: Int64) async throws -> [PendingJob] {
        try await database.read(paths: paths) { db in
            try PendingJobDatabaseRecord
                .filter(PendingJobDatabaseRecord.Columns.userID == userID.rawValue)
                .filter([PendingJobStatus.pending.rawValue, PendingJobStatus.running.rawValue].contains(PendingJobDatabaseRecord.Columns.status))
                .filter(PendingJobDatabaseRecord.Columns.retryCount < PendingJobDatabaseRecord.Columns.maxRetryCount)
                .filter((PendingJobDatabaseRecord.Columns.nextRetryAt == nil) || (PendingJobDatabaseRecord.Columns.nextRetryAt <= now))
                .order(literal: "COALESCE(next_retry_at, created_at), created_at")
                .fetchAll(db)
                .map(\.job)
        }
    }

    func schedulePendingJobRetry(jobID: String, nextRetryAt: Int64) async throws {
        let now = Self.currentTimestamp()
        _ = try await database.write(paths: paths) { db in
            try PendingJobDatabaseRecord
                .filter(PendingJobDatabaseRecord.Columns.jobID == jobID)
                .filter(PendingJobDatabaseRecord.Columns.retryCount < PendingJobDatabaseRecord.Columns.maxRetryCount)
                .updateAll(db, [
                    PendingJobDatabaseRecord.Columns.status.set(to: PendingJobStatus.pending.rawValue),
                    PendingJobDatabaseRecord.Columns.retryCount += 1,
                    PendingJobDatabaseRecord.Columns.nextRetryAt.set(to: nextRetryAt),
                    PendingJobDatabaseRecord.Columns.updatedAt.set(to: now)
                ])
        }
    }

    func updatePendingJobStatus(jobID: String, status: PendingJobStatus, nextRetryAt: Int64?) async throws {
        let now = Self.currentTimestamp()
        _ = try await database.write(paths: paths) { db in
            var assignments: [ColumnAssignment] = [
                PendingJobDatabaseRecord.Columns.status.set(to: status.rawValue),
                PendingJobDatabaseRecord.Columns.nextRetryAt.set(to: nextRetryAt),
                PendingJobDatabaseRecord.Columns.updatedAt.set(to: now)
            ]
            if status == .failed {
                assignments.append(PendingJobDatabaseRecord.Columns.retryCount += 1)
            }

            try PendingJobDatabaseRecord
                .filter(PendingJobDatabaseRecord.Columns.jobID == jobID)
                .updateAll(db, assignments)
        }
    }

    func hasConversations(for userID: UserID) async throws -> Bool {
        try await conversationDAO.countConversations(for: userID) > 0
    }

    // MARK: - MediaIndexRepository

    func upsertMediaIndexRecord(_ record: MediaIndexRecord) async throws {
        try await upsertMediaIndexRecords([record])
    }

    func mediaIndexRecord(mediaID: String, userID: UserID) async throws -> MediaIndexRecord? {
        try await database.read(in: .fileIndex, paths: paths) { db in
            try MediaIndexDatabaseRecord
                .filter(MediaIndexDatabaseRecord.Columns.mediaID == mediaID)
                .filter(MediaIndexDatabaseRecord.Columns.userID == userID.rawValue)
                .fetchOne(db)?
                .record
        }
    }

    func touchMediaIndexRecord(mediaID: String, userID: UserID, accessedAt: Int64) async throws {
        _ = try await database.write(in: .fileIndex, paths: paths) { db in
            try MediaIndexDatabaseRecord
                .filter(MediaIndexDatabaseRecord.Columns.mediaID == mediaID)
                .filter(MediaIndexDatabaseRecord.Columns.userID == userID.rawValue)
                .updateAll(db, MediaIndexDatabaseRecord.Columns.lastAccessAt.set(to: accessedAt))
        }
    }

    func scanMissingMediaResources(userID: UserID) async throws -> [MissingMediaResource] {
        let resources = try await database.read(paths: paths) { db in
            try MissingMediaResourceDatabaseRecord
                .filter(MissingMediaResourceDatabaseRecord.Columns.userID == userID.rawValue)
                .filter(MissingMediaResourceDatabaseRecord.Columns.localPath != nil)
                .filter(literal: "TRIM(local_path) <> ''")
                .filter(MissingMediaResourceDatabaseRecord.Columns.remoteURL != nil)
                .filter(literal: "TRIM(remote_url) <> ''")
                .order(
                    MissingMediaResourceDatabaseRecord.Columns.updatedAt.desc,
                    MissingMediaResourceDatabaseRecord.Columns.createdAt.desc
                )
                .fetchAll(db)
                .map(\.resource)
        }

        return resources.filter { resource in
            !FileManager.default.fileExists(atPath: resource.localPath)
        }
    }

    func enqueueMediaDownloadJobsForMissingResources(userID: UserID) async throws -> [PendingJob] {
        let missingResources = try await scanMissingMediaResources(userID: userID)
        return try await enqueueMediaDownloadJobs(for: missingResources)
    }

    func rebuildMediaIndex(userID: UserID) async throws -> MediaIndexRebuildResult {
        let resourceRows = try await mediaResourceRowsForIndexRebuild(userID: userID)
        let rebuiltRecords = resourceRows.flatMap(Self.mediaIndexRecordsForExistingFiles)
        let missingResources = try await scanMissingMediaResources(userID: userID)

        _ = try await database.write(in: .fileIndex, paths: paths) { db in
            try MediaIndexDatabaseRecord
                .filter(MediaIndexDatabaseRecord.Columns.userID == userID.rawValue)
                .deleteAll(db)
            for record in rebuiltRecords {
                try MediaIndexDatabaseRecord.upsertRecord(record, in: db)
            }
        }

        let downloadJobs = try await enqueueMediaDownloadJobs(for: missingResources)

        return MediaIndexRebuildResult(
            scannedResourceCount: resourceRows.count,
            rebuiltIndexCount: rebuiltRecords.count,
            missingResourceCount: missingResources.count,
            createdDownloadJobCount: downloadJobs.count
        )
    }

    private func enqueueMediaDownloadJobs(for missingResources: [MissingMediaResource]) async throws -> [PendingJob] {
        guard !missingResources.isEmpty else {
            return []
        }

        let now = Self.currentTimestamp()
        let pendingJobInputs = try missingResources.map {
            try Self.mediaDownloadJobInput(for: $0, createdAt: now)
        }
        return try await database.write(paths: paths) { db in
            var jobs: [PendingJob] = []
            for resource in missingResources {
                try Self.markMediaDownloadPending(resource, updatedAt: now, in: db)
            }
            for input in pendingJobInputs {
                let job = try Self.upsertPendingJob(input, status: .pending, retryCount: 0, updatedAt: now, createdAt: now, in: db)
                jobs.append(job)
            }
            return jobs
        }
    }

    // MARK: - EmojiRepository

    func upsertEmojiPackage(_ package: EmojiPackageRecord) async throws {
        try await emojiDAO.upsertPackage(package)
    }

    func upsertEmojiAsset(_ emoji: EmojiAssetRecord) async throws {
        try await emojiDAO.upsertEmoji(emoji)
    }

    func listEmojiPackages(for userID: UserID) async throws -> [EmojiPackageRecord] {
        try await emojiDAO.listPackages(for: userID)
    }

    func listPackageEmojis(for userID: UserID, packageID: String) async throws -> [EmojiAssetRecord] {
        try await emojiDAO.listEmojis(userID: userID, packageID: packageID)
    }

    func listFavoriteEmojis(for userID: UserID) async throws -> [EmojiAssetRecord] {
        try await emojiDAO.listFavoriteEmojis(for: userID)
    }

    func listRecentEmojis(for userID: UserID, limit: Int) async throws -> [EmojiAssetRecord] {
        try await emojiDAO.listRecentEmojis(for: userID, limit: limit)
    }

    func emoji(emojiID: String, userID: UserID) async throws -> EmojiAssetRecord? {
        try await emojiDAO.emoji(emojiID: emojiID, userID: userID)
    }

    func setEmojiFavorite(emojiID: String, userID: UserID, isFavorite: Bool, updatedAt: Int64) async throws {
        try await emojiDAO.setFavorite(emojiID: emojiID, userID: userID, isFavorite: isFavorite, updatedAt: updatedAt)
    }

    func recordEmojiUsed(emojiID: String, userID: UserID, usedAt: Int64) async throws {
        try await emojiDAO.recordUsed(emojiID: emojiID, userID: userID, usedAt: usedAt)
    }

    // MARK: - SyncStore

    func syncCheckpoint(for bizKey: String) async throws -> SyncCheckpoint? {
        try await database.read(paths: paths) { db in
            try SyncCheckpointDatabaseRecord
                .filter(SyncCheckpointDatabaseRecord.Columns.bizKey == bizKey)
                .fetchOne(db)?
                .checkpoint
        }
    }

    func applyIncomingSyncBatch(_ batch: SyncBatch, userID: UserID) async throws -> SyncApplyResult {
        let sortedMessages = batch.messages.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.sequence == rhs.element.sequence {
                    return lhs.offset < rhs.offset
                }

                return lhs.element.sequence < rhs.element.sequence
            }
            .map(\.element)

        var seenClientMessageIDs = Set<String>()
        var seenServerMessageIDs = Set<String>()
        var seenConversationSequences = Set<String>()
        var dedupedMessages: [IncomingSyncMessage] = []
        var skippedDuplicateCount = 0

        for message in sortedMessages {
            guard Self.recordMessageDedupKeys(
                message,
                clientMessageIDs: &seenClientMessageIDs,
                serverMessageIDs: &seenServerMessageIDs,
                conversationSequences: &seenConversationSequences
            ) else {
                skippedDuplicateCount += 1
                continue
            }

            dedupedMessages.append(message)
        }

        let existingDedupKeys = try await existingMessageDedupKeys(for: dedupedMessages)
        var messagesToInsert: [IncomingSyncMessage] = []
        for message in dedupedMessages {
            if existingDedupKeys.containsDuplicate(for: message) {
                skippedDuplicateCount += 1
                continue
            }

            messagesToInsert.append(message)
        }

        let now = Self.currentTimestamp()
        let unreadIncrements = Dictionary(grouping: messagesToInsert.filter { $0.direction == .incoming }, by: \.conversationID)
            .mapValues(\.count)

        let mentionedConversationIDs = Set(
            messagesToInsert
                .filter { $0.direction == .incoming && ($0.mentionsAll || $0.mentionedUserIDs.contains(userID)) }
                .map(\.conversationID)
        )
        var mentionedExtras: [ConversationID: ConversationExtraContext] = [:]
        for conversationID in mentionedConversationIDs {
            var extra = try await conversationExtra(conversationID: conversationID) ?? ConversationExtraContext()
            extra.hasUnreadMention = true
            mentionedExtras[conversationID] = extra
        }

        let nextSequence = batch.nextSequence ?? sortedMessages.last?.sequence
        let checkpoint = SyncCheckpoint(
            bizKey: batch.bizKey,
            cursor: batch.nextCursor,
            sequence: nextSequence,
            updatedAt: now
        )
        let insertedMessages = messagesToInsert
        let changedConversationIDs = Set(insertedMessages.map(\.conversationID))
        let extrasForMentionedConversations = mentionedExtras

        _ = try await database.write(paths: paths) { db in
            for message in insertedMessages {
                try Self.insertIncomingTextMessage(message, userID: userID, updatedAt: now, in: db)
            }

            for conversationID in changedConversationIDs {
                try Self.refreshConversationAfterSync(
                    conversationID: conversationID,
                    userID: userID,
                    unreadIncrement: unreadIncrements[conversationID] ?? 0,
                    updatedAt: now,
                    in: db
                )
            }

            for (conversationID, extra) in extrasForMentionedConversations {
                try Self.updateConversationExtra(conversationID: conversationID, extra: extra, updatedAt: now, in: db)
            }

            try SyncCheckpointDatabaseRecord.upsertRecord(checkpoint, in: db)
        }
        let badgeCount = try await refreshApplicationBadge(userID: userID)

        await notifyIncomingMessages(
            messagesToInsert.filter { $0.direction == .incoming },
            userID: userID,
            badgeCount: badgeCount
        )

        for message in insertedMessages {
            scheduleMessageIndex(messageID: message.messageID, userID: userID)
        }

        for conversationID in changedConversationIDs {
            scheduleConversationIndex(conversationID: conversationID, userID: userID)
        }
        eventDispatcher.postConversationsDidChange(
            userID: userID,
            conversationIDs: changedConversationIDs
        )

        return SyncApplyResult(
            fetchedCount: batch.messages.count,
            insertedCount: insertedMessages.count,
            skippedDuplicateCount: skippedDuplicateCount,
            checkpoint: checkpoint
        )
    }

    // MARK: - Private Helpers

    private static func conversation(from record: ConversationRecord, extra: ConversationExtraContext? = nil) -> Conversation {
        Conversation(
            id: record.id,
            type: record.type,
            title: record.title,
            avatarURL: record.avatarURL,
            lastMessageDigest: record.lastMessageDigest,
            lastMessageTimeText: timeText(from: record.lastMessageTime),
            unreadCount: record.unreadCount,
            isPinned: record.isPinned,
            isMuted: record.isMuted,
            draftText: record.draftText,
            sortTimestamp: record.sortTimestamp,
            hasUnreadMention: extra?.hasUnreadMention == true
        )
    }

    private static func conversations(from records: [ConversationDatabaseRecord]) throws -> [Conversation] {
        try records.map { databaseRecord in
            let extra: ConversationExtraContext?
            if let json = databaseRecord.extraJSON, let data = json.data(using: .utf8) {
                extra = try JSONDecoder().decode(ConversationExtraContext.self, from: data)
            } else {
                extra = nil
            }
            return conversation(from: databaseRecord.record, extra: extra)
        }
    }

    private static func conversationID(for contact: ContactRecord) -> ConversationID {
        switch contact.type {
        case .friend:
            ConversationID(rawValue: "single_\(contact.wxid)")
        case .group:
            ConversationID(rawValue: "group_\(contact.wxid)")
        case .service, .system, .stranger:
            ConversationID(rawValue: "contact_\(contact.wxid)")
        }
    }

    private func conversationExtras(conversationIDs: [ConversationID]) async throws -> [ConversationID: ConversationExtraContext] {
        guard !conversationIDs.isEmpty else {
            return [:]
        }

        var seenIDs = Set<ConversationID>()
        let uniqueIDs = conversationIDs.filter { seenIDs.insert($0).inserted }
        var extras: [ConversationID: ConversationExtraContext] = [:]
        let chunkSize = 500

        for startIndex in stride(from: uniqueIDs.startIndex, to: uniqueIDs.endIndex, by: chunkSize) {
            let endIndex = uniqueIDs.index(startIndex, offsetBy: chunkSize, limitedBy: uniqueIDs.endIndex) ?? uniqueIDs.endIndex
            let chunk = Array(uniqueIDs[startIndex..<endIndex])
            let records = try await database.read(paths: paths) { db in
                try ConversationDatabaseRecord
                    .filter(chunk.map(\.rawValue).contains(ConversationDatabaseRecord.Columns.conversationID))
                    .fetchAll(db)
            }

            for record in records {
                guard let json = record.extraJSON, let data = json.data(using: .utf8) else {
                    continue
                }
                extras[record.record.id] = try JSONDecoder().decode(ConversationExtraContext.self, from: data)
            }
        }

        return extras
    }

    private func conversationExtra(conversationID: ConversationID) async throws -> ConversationExtraContext? {
        let record = try await database.read(paths: paths) { db in
            try ConversationDatabaseRecord
                .filter(ConversationDatabaseRecord.Columns.conversationID == conversationID.rawValue)
                .fetchOne(db)
        }

        guard let json = record?.extraJSON, let data = json.data(using: .utf8) else {
            return nil
        }

        return try JSONDecoder().decode(ConversationExtraContext.self, from: data)
    }

    private func updateConversationExtra(
        conversationID: ConversationID,
        extra: ConversationExtraContext,
        updatedAt: Int64
    ) async throws {
        _ = try await database.write(paths: paths) { db in
            try Self.updateConversationExtra(conversationID: conversationID, extra: extra, updatedAt: updatedAt, in: db)
        }
    }

    private static func updateConversationExtra(
        conversationID: ConversationID,
        extra: ConversationExtraContext,
        updatedAt: Int64,
        in db: Database
    ) throws {
        let data = try JSONEncoder().encode(extra)
        let json = String(decoding: data, as: UTF8.self)
        try ConversationDatabaseRecord
            .filter(ConversationDatabaseRecord.Columns.conversationID == conversationID.rawValue)
            .updateAll(db, [
                ConversationDatabaseRecord.Columns.extraJSON.set(to: json),
                ConversationDatabaseRecord.Columns.updatedAt.set(to: updatedAt)
            ])
    }

    private static func mentionsJSON(for userIDs: [UserID]) -> String? {
        let values = userIDs.map(\.rawValue)
        guard !values.isEmpty else {
            return nil
        }
        guard let data = try? JSONEncoder().encode(values) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func timeText(from timestamp: Int64?) -> String {
        guard let timestamp, timestamp > 0 else {
            return ""
        }

        return ChatBridgeTimeFormatter.messageTimeText(from: timestamp)
    }

    private static func unreadConversationCount(userID: UserID, db: Database) throws -> Int {
        let unreadCount = try Int.fetchOne(
            db,
            ConversationDatabaseRecord
                .filter(ConversationDatabaseRecord.Columns.userID == userID.rawValue)
                .filter(ConversationDatabaseRecord.Columns.isHidden == false)
                .select(sum(ConversationDatabaseRecord.Columns.unreadCount))
        )
        return max(0, unreadCount ?? 0)
    }

    private func mediaResourceRowsForIndexRebuild(userID: UserID) async throws -> [MediaResourceIndexRebuildDatabaseRecord] {
        try await database.read(paths: paths) { db in
            try MediaResourceIndexRebuildDatabaseRecord
                .filter(MediaResourceIndexRebuildDatabaseRecord.Columns.userID == userID.rawValue)
                .order(
                    MediaResourceIndexRebuildDatabaseRecord.Columns.updatedAt.desc,
                    MediaResourceIndexRebuildDatabaseRecord.Columns.createdAt.desc
                )
                .fetchAll(db)
        }
    }

    private func interruptedOutgoingMessages(userID: UserID) async throws -> [InterruptedOutgoingMessage] {
        try await database.read(paths: paths) { db in
            let conversations = try ConversationDatabaseRecord
                .filter(ConversationDatabaseRecord.Columns.userID == userID.rawValue)
                .fetchAll(db)

            var messages: [InterruptedOutgoingMessage] = []
            for conversation in conversations {
                let records = try MessageDatabaseRecord
                    .filter(MessageDatabaseRecord.Columns.conversationID == conversation.record.id.rawValue)
                    .filter(MessageDatabaseRecord.Columns.direction == MessageDirection.outgoing.rawValue)
                    .filter(MessageDatabaseRecord.Columns.sendStatus == MessageSendStatus.sending.rawValue)
                    .filter(MessageDatabaseRecord.Columns.isDeleted == false)
                    .order(MessageDatabaseRecord.Columns.localTime.asc, MessageDatabaseRecord.Columns.sortSequence.asc)
                    .fetchAll(db)

                for record in records {
                    messages.append(
                        InterruptedOutgoingMessage(
                            messageID: record.messageID,
                            conversationID: record.conversationID,
                            clientMessageID: record.clientMessageID,
                            type: record.messageType,
                            mediaID: try Self.mediaID(for: record, in: db)
                        )
                    )
                }
            }
            return messages
        }
    }

    private func notifyIncomingMessages(_ messages: [IncomingSyncMessage], userID: UserID, badgeCount: Int) async {
        guard !messages.isEmpty else {
            return
        }

        let setting: NotificationSettingRecord
        do {
            setting = try await notificationSetting(for: userID)
        } catch {
            return
        }

        guard setting.isEnabled else {
            return
        }

        var payloads: [IncomingMessageNotificationPayload] = []
        for message in messages {
            let fallbackTitle = message.conversationTitle ?? "ChatBridge"
            let context: NotificationConversationContext

            do {
                context = try await notificationConversationContext(
                    conversationID: message.conversationID,
                    userID: userID,
                    fallbackTitle: fallbackTitle
                )
            } catch {
                context = NotificationConversationContext(title: fallbackTitle, isMuted: false)
            }

            guard !context.isMuted else {
                continue
            }

            payloads.append(
                IncomingMessageNotificationPayload(
                    userID: userID,
                    conversationID: message.conversationID,
                    messageID: message.messageID,
                    title: context.title,
                    messageDigest: message.text,
                    isMuted: context.isMuted,
                    isEnabled: setting.isEnabled,
                    showPreview: setting.showPreview,
                    badgeCount: badgeCount
                )
            )
        }

        await eventDispatcher.scheduleIncomingMessageNotifications(payloads)
    }

    private func notificationConversationContext(
        conversationID: ConversationID,
        userID: UserID,
        fallbackTitle: String
    ) async throws -> NotificationConversationContext {
        let record = try await database.read(paths: paths) { db in
            try ConversationDatabaseRecord
                .filter(ConversationDatabaseRecord.Columns.conversationID == conversationID.rawValue)
                .filter(ConversationDatabaseRecord.Columns.userID == userID.rawValue)
                .fetchOne(db)?
                .record
        }

        guard let record else {
            return NotificationConversationContext(title: fallbackTitle, isMuted: false)
        }

        return NotificationConversationContext(
            title: record.title.isEmpty ? fallbackTitle : record.title,
            isMuted: record.isMuted
        )
    }

    private static func refreshConversationSummary(
        conversationID: ConversationID,
        userID: UserID,
        updatedAt: Int64,
        in db: Database
    ) throws {
        guard let latestMessage = try latestVisibleMessage(conversationID: conversationID, in: db) else {
            return
        }

        try ConversationDatabaseRecord
            .filter(ConversationDatabaseRecord.Columns.conversationID == conversationID.rawValue)
            .filter(ConversationDatabaseRecord.Columns.userID == userID.rawValue)
            .updateAll(db, [
                ConversationDatabaseRecord.Columns.lastMessageID.set(to: latestMessage.messageID.rawValue),
                ConversationDatabaseRecord.Columns.lastMessageTime.set(to: latestMessage.localTime),
                ConversationDatabaseRecord.Columns.lastMessageDigest.set(to: try messageDigest(for: latestMessage, in: db)),
                ConversationDatabaseRecord.Columns.sortTimestamp.set(to: latestMessage.sortSequence),
                ConversationDatabaseRecord.Columns.updatedAt.set(to: updatedAt)
            ])
    }

    private static func latestVisibleMessage(conversationID: ConversationID, in db: Database) throws -> MessageDatabaseRecord? {
        try MessageDatabaseRecord
            .filter(MessageDatabaseRecord.Columns.conversationID == conversationID.rawValue)
            .filter(MessageDatabaseRecord.Columns.isDeleted == false)
            .order(MessageDatabaseRecord.Columns.sortSequence.desc)
            .fetchOne(db)
    }

    private static func messageDigest(for message: MessageDatabaseRecord, in db: Database) throws -> String {
        if message.revokeStatus != 0 {
            return try MessageRevokeDatabaseRecord
                .filter(MessageRevokeDatabaseRecord.Columns.messageID == message.messageID.rawValue)
                .fetchOne(db)?
                .replaceText ?? ""
        }

        switch message.messageType {
        case .text, .system, .quote:
            return try MessageTextDatabaseRecord.fetchOne(db, key: message.contentID)?.text ?? ""
        case .image:
            return "[图片]"
        case .voice:
            return "[语音]"
        case .video:
            return "[视频]"
        case .file:
            let fileName = try MessageFileDatabaseRecord.fetchOne(db, key: message.contentID)?.fileName ?? ""
            return fileName.isEmpty ? "[文件]" : "[文件] \(fileName)"
        case .emoji:
            return "[表情]"
        case .revoked:
            return ""
        }
    }

    private static func mediaID(for message: MessageDatabaseRecord, in db: Database) throws -> String? {
        switch message.messageType {
        case .image:
            return try MessageImageDatabaseRecord.fetchOne(db, key: message.contentID)?.mediaID
        case .voice:
            return try MessageVoiceDatabaseRecord.fetchOne(db, key: message.contentID)?.mediaID
        case .video:
            return try MessageVideoDatabaseRecord.fetchOne(db, key: message.contentID)?.mediaID
        case .file:
            return try MessageFileDatabaseRecord.fetchOne(db, key: message.contentID)?.mediaID
        case .text, .emoji, .system, .quote, .revoked:
            return nil
        }
    }

    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }

    private func upsertMediaIndexRecords(_ records: [MediaIndexRecord]) async throws {
        guard !records.isEmpty else {
            return
        }

        _ = try await database.write(in: .fileIndex, paths: paths) { db in
            for record in records {
                try MediaIndexDatabaseRecord.upsertRecord(record, in: db)
            }
        }
    }

    private func scheduleMessageIndex(messageID: MessageID, userID: UserID) {
        eventDispatcher.indexMessageBestEffort(messageID: messageID, userID: userID)
    }

    private func scheduleMessageRemoval(messageID: MessageID, userID: UserID) {
        eventDispatcher.removeMessageBestEffort(messageID: messageID, userID: userID)
    }

    private func scheduleConversationIndex(conversationID: ConversationID, userID: UserID) {
        eventDispatcher.indexConversationBestEffort(conversationID: conversationID, userID: userID)
    }

    private static func mediaIndexRecordsForExistingFiles(from row: MediaResourceIndexRebuildDatabaseRecord) -> [MediaIndexRecord] {
        guard
            let mediaID = row.mediaID,
            let userID = row.userID
        else {
            return []
        }

        let timestamp = row.createdAt ?? row.updatedAt ?? currentTimestamp()
        let md5 = row.md5
        var records: [MediaIndexRecord] = []

        if let localPath = row.localPath, FileManager.default.fileExists(atPath: localPath) {
            records.append(
                MediaIndexRecord(
                    mediaID: mediaID,
                    userID: UserID(rawValue: userID),
                    localPath: localPath,
                    fileName: fileName(from: localPath),
                    fileExtension: fileExtension(from: localPath, fallback: nil),
                    sizeBytes: existingFileSize(atPath: localPath) ?? row.sizeBytes,
                    md5: md5,
                    lastAccessAt: timestamp,
                    createdAt: timestamp
                )
            )
        }

        if let thumbnailPath = row.thumbPath, FileManager.default.fileExists(atPath: thumbnailPath) {
            records.append(
                MediaIndexRecord(
                    mediaID: "\(mediaID)_thumb",
                    userID: UserID(rawValue: userID),
                    localPath: thumbnailPath,
                    fileName: fileName(from: thumbnailPath),
                    fileExtension: fileExtension(from: thumbnailPath, fallback: "jpg"),
                    sizeBytes: existingFileSize(atPath: thumbnailPath),
                    md5: nil,
                    lastAccessAt: timestamp,
                    createdAt: timestamp
                )
            )
        }

        return records
    }

    private static func mediaIndexRecords(
        for image: StoredImageContent,
        userID: UserID,
        createdAt: Int64
    ) -> [MediaIndexRecord] {
        return [
            MediaIndexRecord(
                mediaID: image.mediaID,
                userID: userID,
                localPath: image.localPath,
                fileName: fileName(from: image.localPath),
                fileExtension: fileExtension(from: image.localPath, fallback: image.format),
                sizeBytes: image.sizeBytes,
                md5: image.md5,
                lastAccessAt: createdAt,
                createdAt: createdAt
            ),
            MediaIndexRecord(
                mediaID: "\(image.mediaID)_thumb",
                userID: userID,
                localPath: image.thumbnailPath,
                fileName: fileName(from: image.thumbnailPath),
                fileExtension: fileExtension(from: image.thumbnailPath, fallback: "jpg"),
                sizeBytes: existingFileSize(atPath: image.thumbnailPath),
                md5: nil,
                lastAccessAt: createdAt,
                createdAt: createdAt
            )
        ]
    }

    private static func mediaIndexRecords(
        for voice: StoredVoiceContent,
        userID: UserID,
        createdAt: Int64
    ) -> [MediaIndexRecord] {
        [
            MediaIndexRecord(
                mediaID: voice.mediaID,
                userID: userID,
                localPath: voice.localPath,
                fileName: fileName(from: voice.localPath),
                fileExtension: fileExtension(from: voice.localPath, fallback: voice.format),
                sizeBytes: voice.sizeBytes,
                md5: nil,
                lastAccessAt: createdAt,
                createdAt: createdAt
            )
        ]
    }

    private static func mediaIndexRecords(
        for video: StoredVideoContent,
        userID: UserID,
        createdAt: Int64
    ) -> [MediaIndexRecord] {
        [
            MediaIndexRecord(
                mediaID: video.mediaID,
                userID: userID,
                localPath: video.localPath,
                fileName: fileName(from: video.localPath),
                fileExtension: fileExtension(from: video.localPath, fallback: nil),
                sizeBytes: video.sizeBytes,
                md5: video.md5,
                lastAccessAt: createdAt,
                createdAt: createdAt
            ),
            MediaIndexRecord(
                mediaID: "\(video.mediaID)_thumb",
                userID: userID,
                localPath: video.thumbnailPath,
                fileName: fileName(from: video.thumbnailPath),
                fileExtension: fileExtension(from: video.thumbnailPath, fallback: "jpg"),
                sizeBytes: existingFileSize(atPath: video.thumbnailPath),
                md5: nil,
                lastAccessAt: createdAt,
                createdAt: createdAt
            )
        ]
    }

    private static func mediaIndexRecords(
        for file: StoredFileContent,
        userID: UserID,
        createdAt: Int64
    ) -> [MediaIndexRecord] {
        [
            MediaIndexRecord(
                mediaID: file.mediaID,
                userID: userID,
                localPath: file.localPath,
                fileName: file.fileName,
                fileExtension: file.fileExtension,
                sizeBytes: file.sizeBytes,
                md5: file.md5,
                lastAccessAt: createdAt,
                createdAt: createdAt
            )
        ]
    }

    private static func mediaDownloadJobInput(
        for resource: MissingMediaResource,
        createdAt: Int64
    ) throws -> PendingJobInput {
        let payload = MediaDownloadPendingJobPayload(
            mediaID: resource.mediaID,
            ownerMessageID: resource.ownerMessageID?.rawValue,
            localPath: resource.localPath,
            remoteURL: resource.remoteURL
        )

        return PendingJobInput(
            id: mediaDownloadJobID(mediaID: resource.mediaID),
            userID: resource.userID,
            type: .mediaDownload,
            bizKey: resource.mediaID,
            payloadJSON: try PendingJobPayload.mediaDownload(payload).encodedJSON(),
            maxRetryCount: 3,
            nextRetryAt: createdAt
        )
    }

    private static func markMediaDownloadPending(
        _ resource: MissingMediaResource,
        updatedAt: Int64,
        in db: Database
    ) throws {
        try MediaResourceDatabaseRecord
            .filter(MediaResourceDatabaseRecord.Columns.mediaID == resource.mediaID)
            .filter(MediaResourceDatabaseRecord.Columns.userID == resource.userID.rawValue)
            .updateAll(db, [
                MediaResourceDatabaseRecord.Columns.downloadStatus.set(to: 0),
                MediaResourceDatabaseRecord.Columns.updatedAt.set(to: updatedAt)
            ])
    }

    private static func mediaDownloadJobID(mediaID: String) -> String {
        "media_download_\(mediaID)"
    }

    private static func fileName(from path: String) -> String? {
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        return fileName.isEmpty ? nil : fileName
    }

    private static func fileExtension(from path: String, fallback: String?) -> String? {
        let pathExtension = URL(fileURLWithPath: path).pathExtension
        if !pathExtension.isEmpty {
            return pathExtension.lowercased()
        }

        let sanitizedFallback = fallback?
            .trimmingCharacters(in: CharacterSet(charactersIn: ".").union(.whitespacesAndNewlines))
            .lowercased()

        return sanitizedFallback?.isEmpty == false ? sanitizedFallback : nil
    }

    private static func existingFileSize(atPath path: String) -> Int64? {
        guard
            FileManager.default.fileExists(atPath: path),
            let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber
        else {
            return nil
        }

        return size.int64Value
    }

    fileprivate static func updateMessageSendStatus(
        messageID: MessageID,
        status: MessageSendStatus,
        ack: MessageSendAck?,
        in db: Database
    ) throws {
        try MessageDatabaseRecord
            .filter(MessageDatabaseRecord.Columns.messageID == messageID.rawValue)
            .updateAll(db, [
                MessageDatabaseRecord.Columns.sendStatus.set(to: status.rawValue),
                MessageDatabaseRecord.Columns.serverMessageID.set(to: ack?.serverMessageID),
                MessageDatabaseRecord.Columns.sequence.set(to: ack?.sequence),
                MessageDatabaseRecord.Columns.serverTime.set(to: ack?.serverTime)
            ])
    }

    fileprivate static func updateMediaUploadStatus(
        messageID: MessageID,
        status: MediaUploadStatus,
        uploadAck: MediaUploadAck?,
        updatedAt: Int64,
        tableSpec: MediaUploadTableSpec,
        in db: Database
    ) throws {
        guard let message = try MessageDatabaseRecord
            .filter(MessageDatabaseRecord.Columns.messageID == messageID.rawValue)
            .fetchOne(db) else {
            return
        }

        var contentAssignments = [
            Column("upload_status").set(to: status.rawValue)
        ]
        if let cdnURL = uploadAck?.cdnURL {
            contentAssignments.append(Column("cdn_url").set(to: cdnURL))
        }
        if tableSpec.writesContentMD5, let md5 = uploadAck?.md5 {
            contentAssignments.append(Column("md5").set(to: md5))
        }
        try Table(tableSpec.contentTable)
            .filter(Column("content_id") == message.contentID)
            .updateAll(db, contentAssignments)

        var resourceAssignments = [
            MediaResourceDatabaseRecord.Columns.uploadStatus.set(to: status.rawValue),
            MediaResourceDatabaseRecord.Columns.updatedAt.set(to: updatedAt)
        ]
        if let cdnURL = uploadAck?.cdnURL {
            resourceAssignments.append(MediaResourceDatabaseRecord.Columns.remoteURL.set(to: cdnURL))
        }
        if let md5 = uploadAck?.md5 {
            resourceAssignments.append(MediaResourceDatabaseRecord.Columns.md5.set(to: md5))
        }
        try MediaResourceDatabaseRecord
            .filter(MediaResourceDatabaseRecord.Columns.ownerMessageID == messageID.rawValue)
            .updateAll(db, resourceAssignments)
    }

    @discardableResult
    fileprivate static func upsertPendingJob(
        _ input: PendingJobInput,
        status: PendingJobStatus,
        retryCount: Int,
        updatedAt: Int64,
        createdAt: Int64,
        in db: Database
    ) throws -> PendingJob {
        let job = PendingJob(
            id: input.id,
            userID: input.userID,
            type: input.type,
            bizKey: input.bizKey,
            payloadJSON: input.payloadJSON,
            status: status,
            retryCount: retryCount,
            maxRetryCount: input.maxRetryCount,
            nextRetryAt: input.nextRetryAt,
            updatedAt: updatedAt,
            createdAt: createdAt
        )
        return try PendingJobDatabaseRecord.upsertNonTerminalJob(job, in: db)
    }

    fileprivate struct MediaUploadTableSpec {
        let contentTable: String
        let writesContentMD5: Bool

        static let image = MediaUploadTableSpec(contentTable: "message_image", writesContentMD5: true)
        static let voice = MediaUploadTableSpec(contentTable: "message_voice", writesContentMD5: false)
        static let video = MediaUploadTableSpec(contentTable: "message_video", writesContentMD5: true)
        static let file = MediaUploadTableSpec(contentTable: "message_file", writesContentMD5: true)
    }

    private static func recordMessageDedupKeys(
        _ message: IncomingSyncMessage,
        clientMessageIDs: inout Set<String>,
        serverMessageIDs: inout Set<String>,
        conversationSequences: inout Set<String>
    ) -> Bool {
        if let clientMessageID = message.clientMessageID, clientMessageIDs.contains(clientMessageID) {
            return false
        }

        if let serverMessageID = message.serverMessageID, serverMessageIDs.contains(serverMessageID) {
            return false
        }

        let sequenceKey = ExistingMessageDedupKeys.sequenceKey(conversationID: message.conversationID, sequence: message.sequence)
        guard !conversationSequences.contains(sequenceKey) else {
            return false
        }

        if let clientMessageID = message.clientMessageID {
            clientMessageIDs.insert(clientMessageID)
        }

        if let serverMessageID = message.serverMessageID {
            serverMessageIDs.insert(serverMessageID)
        }

        conversationSequences.insert(sequenceKey)
        return true
    }

    private func existingMessageDedupKeys(for messages: [IncomingSyncMessage]) async throws -> ExistingMessageDedupKeys {
        guard !messages.isEmpty else {
            return ExistingMessageDedupKeys()
        }

        let clientMessageIDs = messages.compactMap(\.clientMessageID)
        let serverMessageIDs = messages.compactMap(\.serverMessageID)
        let sequencesByConversation = Dictionary(grouping: messages, by: \.conversationID).mapValues {
            Array(Set($0.map(\.sequence))).sorted()
        }

        guard !clientMessageIDs.isEmpty || !serverMessageIDs.isEmpty || !sequencesByConversation.isEmpty else {
            return ExistingMessageDedupKeys()
        }

        let rows = try await database.read(paths: paths) { db in
            try Self.existingMessageDedupRecords(
                clientMessageIDs: clientMessageIDs,
                serverMessageIDs: serverMessageIDs,
                sequencesByConversation: sequencesByConversation,
                in: db
            )
        }

        var keys = ExistingMessageDedupKeys()
        for row in rows {
            if let clientMessageID = row.clientMessageID {
                keys.clientMessageIDs.insert(clientMessageID)
            }
            if let serverMessageID = row.serverMessageID {
                keys.serverMessageIDs.insert(serverMessageID)
            }
            if let conversationID = row.conversationID, let sequence = row.sequence {
                keys.conversationSequences.insert(
                    ExistingMessageDedupKeys.sequenceKey(
                        conversationID: conversationID,
                        sequence: sequence
                    )
                )
            }
        }

        return keys
    }

    private static func existingMessageDedupRecords(
        clientMessageIDs: [String],
        serverMessageIDs: [String],
        sequencesByConversation: [ConversationID: [Int64]],
        in db: Database
    ) throws -> [ExistingMessageDedupKeyRecord] {
        var records: [MessageDatabaseRecord] = []

        for clientMessageID in Set(clientMessageIDs) {
            records.append(
                contentsOf: try MessageDatabaseRecord
                    .filter(MessageDatabaseRecord.Columns.clientMessageID == clientMessageID)
                    .fetchAll(db)
            )
        }

        for serverMessageID in Set(serverMessageIDs) {
            records.append(
                contentsOf: try MessageDatabaseRecord
                    .filter(MessageDatabaseRecord.Columns.serverMessageID == serverMessageID)
                    .fetchAll(db)
            )
        }

        for (conversationID, sequences) in sequencesByConversation {
            for sequence in Set(sequences) {
                records.append(
                    contentsOf: try MessageDatabaseRecord
                        .filter(MessageDatabaseRecord.Columns.conversationID == conversationID.rawValue)
                        .filter(MessageDatabaseRecord.Columns.sequence == sequence)
                        .fetchAll(db)
                )
            }
        }

        var seenMessageIDs: Set<MessageID> = []
        return records.compactMap { record in
            guard seenMessageIDs.insert(record.messageID).inserted else {
                return nil
            }

            return ExistingMessageDedupKeyRecord(
                clientMessageID: record.clientMessageID,
                serverMessageID: record.serverMessageID,
                conversationID: record.conversationID,
                sequence: record.sequence
            )
        }
    }

    private static func insertIncomingTextMessage(
        _ message: IncomingSyncMessage,
        userID: UserID,
        updatedAt: Int64,
        in db: Database
    ) throws {
        let contentID = "sync_text_\(message.messageID.rawValue)"

        if try ConversationDatabaseRecord
            .filter(ConversationDatabaseRecord.Columns.conversationID == message.conversationID.rawValue)
            .fetchOne(db) == nil {
            try ConversationDatabaseRecord(
                record: ConversationRecord(
                    id: message.conversationID,
                    userID: userID,
                    type: message.conversationType,
                    targetID: message.senderID.rawValue,
                    title: message.conversationTitle ?? message.senderID.rawValue,
                    avatarURL: nil,
                    lastMessageID: nil,
                    lastMessageTime: nil,
                    lastMessageDigest: "",
                    unreadCount: 0,
                    draftText: nil,
                    isPinned: false,
                    isMuted: false,
                    isHidden: false,
                    sortTimestamp: message.sequence,
                    updatedAt: updatedAt,
                    createdAt: updatedAt
                )
            ).insert(db)
        }

        try MessageTextDatabaseRecord(
            contentID: contentID,
            text: message.text,
            mentionsJSON: Self.mentionsJSON(for: message.mentionedUserIDs),
            atAll: message.mentionsAll,
            richTextJSON: nil
        ).insert(db)

        try MessageDatabaseRecord(
            messageID: message.messageID,
            conversationID: message.conversationID,
            senderID: message.senderID,
            clientMessageID: message.clientMessageID,
            serverMessageID: message.serverMessageID,
            sequence: message.sequence,
            messageType: .text,
            direction: message.direction,
            sendStatus: .success,
            deliveryStatus: 0,
            readStatus: .unread,
            revokeStatus: 0,
            isDeleted: false,
            contentTable: "message_text",
            contentID: contentID,
            sortSequence: message.sequence,
            serverTime: message.serverTime,
            localTime: message.localTime
        ).insert(db)
    }

    private static func refreshConversationAfterSync(
        conversationID: ConversationID,
        userID: UserID,
        unreadIncrement: Int,
        updatedAt: Int64,
        in db: Database
    ) throws {
        guard let latestMessage = try latestVisibleMessage(conversationID: conversationID, in: db) else {
            try ConversationDatabaseRecord
                .filter(ConversationDatabaseRecord.Columns.conversationID == conversationID.rawValue)
                .filter(ConversationDatabaseRecord.Columns.userID == userID.rawValue)
                .updateAll(db, [
                    ConversationDatabaseRecord.Columns.unreadCount += unreadIncrement,
                    ConversationDatabaseRecord.Columns.updatedAt.set(to: updatedAt)
                ])
            return
        }

        try ConversationDatabaseRecord
            .filter(ConversationDatabaseRecord.Columns.conversationID == conversationID.rawValue)
            .filter(ConversationDatabaseRecord.Columns.userID == userID.rawValue)
            .updateAll(db, [
                ConversationDatabaseRecord.Columns.lastMessageID.set(to: latestMessage.messageID.rawValue),
                ConversationDatabaseRecord.Columns.lastMessageTime.set(to: latestMessage.serverTime ?? latestMessage.localTime),
                ConversationDatabaseRecord.Columns.lastMessageDigest.set(to: try messageDigest(for: latestMessage, in: db)),
                ConversationDatabaseRecord.Columns.sortTimestamp.set(to: latestMessage.sortSequence),
                ConversationDatabaseRecord.Columns.unreadCount += unreadIncrement,
                ConversationDatabaseRecord.Columns.updatedAt.set(to: updatedAt)
            ])
    }
}
