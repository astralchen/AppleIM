//
//  LocalChatRepository.swift
//  AppleIM
//
//  本地聊天仓储
//  实现多个仓储协议，统一管理会话、消息、同步等数据操作

import Foundation

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

/// 本地聊天仓储
///
/// 聚合多个 DAO，实现会话、消息、同步等多个仓储协议
/// 所有操作通过 DatabaseActor 串行化执行
nonisolated struct LocalChatRepository: ConversationRepository, ContactRepository, NotificationSettingsRepository, MessageRepository, MessageSendRecoveryRepository, MessageCrashRecoveryRepository, PendingJobRepository, MediaIndexRepository, EmojiRepository, SyncStore {
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

    /// 批量插入初始会话
    ///
    /// 用于首次同步或数据恢复场景，批量写入会话记录
    ///
    /// - Parameter records: 会话记录列表
    /// - Throws: 数据库事务错误
    func insertInitialConversations(_ records: [ConversationRecord]) async throws {
        guard !records.isEmpty else { return }

        try await database.performTransaction(
            records.map(ConversationDAO.insertOrUpdateStatement(for:)),
            paths: paths
        )
    }

    /// 批量插入首次演示文本消息。
    func insertInitialTextMessages(_ messages: [InitialTextMessageInput]) async throws {
        guard !messages.isEmpty else { return }

        try await database.performTransaction(
            messages.flatMap(MessageDAO.insertInitialTextStatements),
            paths: paths
        )
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
        let extraStatements: [SQLiteStatement]
        if let extra {
            extraStatements = [try Self.updateConversationExtraStatement(conversationID: conversationID, extra: extra, updatedAt: now)]
        } else {
            extraStatements = []
        }
        try await database.performTransaction(
            [
                ConversationDAO.markReadStatement(conversationID: conversationID, userID: userID, updatedAt: now),
                MessageDAO.markIncomingMessagesReadStatement(conversationID: conversationID)
            ] + extraStatements,
            paths: paths
        )
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

        let statements = members.map { member in
            SQLiteStatement(
                """
                INSERT INTO conversation_member (
                    conversation_id,
                    member_id,
                    display_name,
                    role,
                    join_time,
                    extra_json
                ) VALUES (?, ?, ?, ?, ?, NULL)
                ON CONFLICT(conversation_id, member_id) DO UPDATE SET
                    display_name = excluded.display_name,
                    role = excluded.role,
                    join_time = excluded.join_time;
                """,
                parameters: [
                    .text(member.conversationID.rawValue),
                    .text(member.memberID.rawValue),
                    .text(member.displayName),
                    .integer(Int64(member.role.rawValue)),
                    .optionalInteger(member.joinTime)
                ]
            )
        }

        try await database.performTransaction(statements, paths: paths)
    }

    /// 查询群成员
    func groupMembers(conversationID: ConversationID) async throws -> [GroupMember] {
        let rows = try await database.query(
            """
            SELECT conversation_id, member_id, display_name, role, join_time
            FROM conversation_member
            WHERE conversation_id = ?
            ORDER BY role DESC, join_time ASC, id ASC;
            """,
            parameters: [.text(conversationID.rawValue)],
            paths: paths
        )

        return try rows.map(Self.groupMember(from:))
    }

    /// 查询当前用户群角色
    func currentMemberRole(conversationID: ConversationID, userID: UserID) async throws -> GroupMemberRole? {
        let rows = try await database.query(
            """
            SELECT role
            FROM conversation_member
            WHERE conversation_id = ? AND member_id = ?
            LIMIT 1;
            """,
            parameters: [
                .text(conversationID.rawValue),
                .text(userID.rawValue)
            ],
            paths: paths
        )

        guard let rawValue = rows.first?.int("role") else {
            return nil
        }
        return GroupMemberRole(rawValue: rawValue)
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
        let rows = try await database.query(
            """
            SELECT
                user_id,
                is_enabled,
                show_preview,
                badge_enabled,
                badge_include_muted,
                updated_at
            FROM notification_setting
            WHERE user_id = ?
            LIMIT 1;
            """,
            parameters: [.text(userID.rawValue)],
            paths: paths
        )

        guard let row = rows.first else {
            return .defaultSetting(for: userID)
        }

        return NotificationSettingRecord(
            userID: UserID(rawValue: try row.requiredString("user_id")),
            isEnabled: row.bool("is_enabled"),
            showPreview: row.bool("show_preview"),
            badgeEnabled: row.bool("badge_enabled"),
            badgeIncludeMuted: row.bool("badge_include_muted"),
            updatedAt: row.int64("updated_at") ?? 0
        )
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
        try await upsertBadgeSetting(
            userID: userID,
            column: "badge_enabled",
            value: isEnabled
        )
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
        try await upsertBadgeSetting(
            userID: userID,
            column: "badge_include_muted",
            value: includeMuted
        )
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
        let setting = try await notificationSetting(for: userID)
        let badgeCount: Int

        if setting.badgeEnabled {
            badgeCount = try await unreadBadgeCount(
                userID: userID,
                includeMuted: setting.badgeIncludeMuted
            )
        } else {
            badgeCount = 0
        }

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
        let result = MessageDAO.insertOutgoingTextStatements(input)
        try await database.performTransaction(result.statements, paths: paths)
        scheduleMessageIndex(messageID: result.message.id, userID: input.userID)
        scheduleConversationIndex(conversationID: input.conversationID, userID: input.userID)
        return result.message
    }

    func insertOutgoingImageMessage(_ input: OutgoingImageMessageInput) async throws -> StoredMessage {
        let result = MessageDAO.insertOutgoingImageStatements(input)
        try await database.performTransaction(result.statements, paths: paths)
        try await upsertMediaIndexRecords(Self.mediaIndexRecords(for: input.image, userID: input.userID, createdAt: input.localTime))
        scheduleConversationIndex(conversationID: input.conversationID, userID: input.userID)
        return result.message
    }

    func insertOutgoingVoiceMessage(_ input: OutgoingVoiceMessageInput) async throws -> StoredMessage {
        let result = MessageDAO.insertOutgoingVoiceStatements(input)
        try await database.performTransaction(result.statements, paths: paths)
        try await upsertMediaIndexRecords(Self.mediaIndexRecords(for: input.voice, userID: input.userID, createdAt: input.localTime))
        scheduleConversationIndex(conversationID: input.conversationID, userID: input.userID)
        return result.message
    }

    func insertOutgoingVideoMessage(_ input: OutgoingVideoMessageInput) async throws -> StoredMessage {
        let result = MessageDAO.insertOutgoingVideoStatements(input)
        try await database.performTransaction(result.statements, paths: paths)
        try await upsertMediaIndexRecords(Self.mediaIndexRecords(for: input.video, userID: input.userID, createdAt: input.localTime))
        scheduleConversationIndex(conversationID: input.conversationID, userID: input.userID)
        return result.message
    }

    func insertOutgoingFileMessage(_ input: OutgoingFileMessageInput) async throws -> StoredMessage {
        let result = MessageDAO.insertOutgoingFileStatements(input)
        try await database.performTransaction(result.statements, paths: paths)
        try await upsertMediaIndexRecords(Self.mediaIndexRecords(for: input.file, userID: input.userID, createdAt: input.localTime))
        scheduleConversationIndex(conversationID: input.conversationID, userID: input.userID)
        return result.message
    }

    func insertOutgoingEmojiMessage(_ input: OutgoingEmojiMessageInput) async throws -> StoredMessage {
        let result = MessageDAO.insertOutgoingEmojiStatements(input)
        try await database.performTransaction(result.statements, paths: paths)
        scheduleConversationIndex(conversationID: input.conversationID, userID: input.userID)
        return result.message
    }

    func listMessages(conversationID: ConversationID, limit: Int, beforeSortSeq: Int64?) async throws -> [StoredMessage] {
        try await messageDAO.listMessages(
            conversationID: conversationID,
            limit: limit,
            beforeSortSeq: beforeSortSeq
        )
    }

    func message(messageID: MessageID) async throws -> StoredMessage? {
        try await messageDAO.message(messageID: messageID)
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
        var statements = [
            Self.updateMessageSendStatusStatement(messageID: messageID, status: status, ack: ack)
        ]

        if let pendingJob {
            let now = Self.currentTimestamp()
            statements.append(
                Self.upsertPendingJobStatement(
                    pendingJob,
                    status: .pending,
                    retryCount: 0,
                    updatedAt: now,
                    createdAt: now
                )
            )
        }

        try await database.performTransaction(statements, paths: paths)
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

        var statements: [SQLiteStatement] = []
        var recoveredMessageCount = 0
        var pendingJobCount = 0
        var failedMessageCount = 0

        for message in interruptedMessages {
            switch message.type {
            case .text:
                guard let clientMessageID = message.clientMessageID else {
                    statements.append(Self.updateMessageSendStatusStatement(messageID: message.messageID, status: .failed, ack: nil))
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
                statements.append(Self.updateMessageSendStatusStatement(messageID: message.messageID, status: .pending, ack: nil))
                statements.append(
                    Self.upsertPendingJobStatement(
                        pendingJob,
                        status: .pending,
                        retryCount: 0,
                        updatedAt: now,
                        createdAt: now
                    )
                )
                recoveredMessageCount += 1
                pendingJobCount += 1
            case .image:
                guard let clientMessageID = message.clientMessageID, let mediaID = message.mediaID else {
                    statements.append(Self.updateMessageSendStatusStatement(messageID: message.messageID, status: .failed, ack: nil))
                    statements += Self.updateImageUploadStatusStatements(
                        messageID: message.messageID,
                        status: .failed,
                        uploadAck: nil,
                        updatedAt: now
                    )
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
                statements.append(Self.updateMessageSendStatusStatement(messageID: message.messageID, status: .pending, ack: nil))
                statements += Self.updateImageUploadStatusStatements(
                    messageID: message.messageID,
                    status: .pending,
                    uploadAck: nil,
                    updatedAt: now
                )
                statements.append(
                    Self.upsertPendingJobStatement(
                        pendingJob,
                        status: .pending,
                        retryCount: 0,
                        updatedAt: now,
                        createdAt: now
                    )
                )
                recoveredMessageCount += 1
                pendingJobCount += 1
            case .video:
                guard let clientMessageID = message.clientMessageID, let mediaID = message.mediaID else {
                    statements.append(Self.updateMessageSendStatusStatement(messageID: message.messageID, status: .failed, ack: nil))
                    statements += Self.updateVideoUploadStatusStatements(
                        messageID: message.messageID,
                        status: .failed,
                        uploadAck: nil,
                        updatedAt: now
                    )
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
                statements.append(Self.updateMessageSendStatusStatement(messageID: message.messageID, status: .pending, ack: nil))
                statements += Self.updateVideoUploadStatusStatements(
                    messageID: message.messageID,
                    status: .pending,
                    uploadAck: nil,
                    updatedAt: now
                )
                statements.append(
                    Self.upsertPendingJobStatement(
                        pendingJob,
                        status: .pending,
                        retryCount: 0,
                        updatedAt: now,
                        createdAt: now
                    )
                )
                recoveredMessageCount += 1
                pendingJobCount += 1
            case .file:
                guard let clientMessageID = message.clientMessageID, let mediaID = message.mediaID else {
                    statements.append(Self.updateMessageSendStatusStatement(messageID: message.messageID, status: .failed, ack: nil))
                    statements += Self.updateFileUploadStatusStatements(
                        messageID: message.messageID,
                        status: .failed,
                        uploadAck: nil,
                        updatedAt: now
                    )
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
                statements.append(Self.updateMessageSendStatusStatement(messageID: message.messageID, status: .pending, ack: nil))
                statements += Self.updateFileUploadStatusStatements(
                    messageID: message.messageID,
                    status: .pending,
                    uploadAck: nil,
                    updatedAt: now
                )
                statements.append(
                    Self.upsertPendingJobStatement(
                        pendingJob,
                        status: .pending,
                        retryCount: 0,
                        updatedAt: now,
                        createdAt: now
                    )
                )
                recoveredMessageCount += 1
                pendingJobCount += 1
            case .voice:
                statements.append(Self.updateMessageSendStatusStatement(messageID: message.messageID, status: .failed, ack: nil))
                statements += Self.updateVoiceUploadStatusStatements(
                    messageID: message.messageID,
                    status: .failed,
                    uploadAck: nil,
                    updatedAt: now
                )
                failedMessageCount += 1
            default:
                statements.append(Self.updateMessageSendStatusStatement(messageID: message.messageID, status: .failed, ack: nil))
                failedMessageCount += 1
            }
        }

        try await database.performTransaction(statements, paths: paths)

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
        guard let existingMessage = try await messageDAO.message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        guard
            existingMessage.type == .image,
            existingMessage.state.sendStatus == .failed,
            !existingMessage.state.isRevoked,
            !existingMessage.state.isDeleted
        else {
            throw ChatStoreError.messageCannotBeResent(messageID)
        }

        try await database.performTransaction(
            [Self.updateMessageSendStatusStatement(messageID: messageID, status: .sending, ack: nil)]
                + Self.updateImageUploadStatusStatements(
                    messageID: messageID,
                    status: .uploading,
                    uploadAck: nil,
                    updatedAt: Self.currentTimestamp()
                ),
            paths: paths
        )

        guard let updatedMessage = try await messageDAO.message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        return updatedMessage
    }

    func resendVideoMessage(messageID: MessageID) async throws -> StoredMessage {
        try await prepareMediaMessageForResend(
            messageID: messageID,
            expectedType: .video,
            uploadStatements: Self.updateVideoUploadStatusStatements
        )
    }

    func resendFileMessage(messageID: MessageID) async throws -> StoredMessage {
        try await prepareMediaMessageForResend(
            messageID: messageID,
            expectedType: .file,
            uploadStatements: Self.updateFileUploadStatusStatements
        )
    }

    private func prepareMediaMessageForResend(
        messageID: MessageID,
        expectedType: MessageType,
        uploadStatements: (MessageID, MediaUploadStatus, MediaUploadAck?, Int64) -> [SQLiteStatement]
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

        try await database.performTransaction(
            [Self.updateMessageSendStatusStatement(messageID: messageID, status: .sending, ack: nil)]
                + uploadStatements(messageID, .uploading, nil, Self.currentTimestamp()),
            paths: paths
        )

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
        let now = Self.currentTimestamp()
        var statements = [
            Self.updateMessageSendStatusStatement(messageID: messageID, status: sendStatus, ack: sendAck)
        ]
        statements += Self.updateImageUploadStatusStatements(
            messageID: messageID,
            status: uploadStatus,
            uploadAck: uploadAck,
            updatedAt: now
        )

        if let pendingJob {
            statements.append(
                Self.upsertPendingJobStatement(
                    pendingJob,
                    status: .pending,
                    retryCount: 0,
                    updatedAt: now,
                    createdAt: now
                )
            )
        }

        try await database.performTransaction(statements, paths: paths)
    }

    func updateVoiceUploadStatus(
        messageID: MessageID,
        uploadStatus: MediaUploadStatus,
        uploadAck: MediaUploadAck?,
        sendStatus: MessageSendStatus,
        sendAck: MessageSendAck?
    ) async throws {
        let now = Self.currentTimestamp()
        let statements = [
            Self.updateMessageSendStatusStatement(messageID: messageID, status: sendStatus, ack: sendAck)
        ] + Self.updateVoiceUploadStatusStatements(
            messageID: messageID,
            status: uploadStatus,
            uploadAck: uploadAck,
            updatedAt: now
        )

        try await database.performTransaction(statements, paths: paths)
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
            uploadStatements: Self.updateVideoUploadStatusStatements
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
            uploadStatements: Self.updateFileUploadStatusStatements
        )
    }

    private func updateMediaUploadStatus(
        messageID: MessageID,
        uploadStatus: MediaUploadStatus,
        uploadAck: MediaUploadAck?,
        sendStatus: MessageSendStatus,
        sendAck: MessageSendAck?,
        pendingJob: PendingJobInput?,
        uploadStatements: (MessageID, MediaUploadStatus, MediaUploadAck?, Int64) -> [SQLiteStatement]
    ) async throws {
        let now = Self.currentTimestamp()
        var statements = [
            Self.updateMessageSendStatusStatement(messageID: messageID, status: sendStatus, ack: sendAck)
        ] + uploadStatements(messageID, uploadStatus, uploadAck, now)

        if let pendingJob {
            statements.append(
                Self.upsertPendingJobStatement(
                    pendingJob,
                    status: .pending,
                    retryCount: 0,
                    updatedAt: now,
                    createdAt: now
                )
            )
        }

        try await database.performTransaction(statements, paths: paths)
    }

    func markVoicePlayed(messageID: MessageID) async throws {
        guard let storedMessage = try await messageDAO.message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        guard storedMessage.type == .voice else {
            return
        }

        try await database.execute(
            """
            UPDATE message
            SET read_status = ?
            WHERE message_id = ?
            AND msg_type = ?;
            """,
            parameters: [
                .integer(Int64(MessageReadStatus.read.rawValue)),
                .text(messageID.rawValue),
                .integer(Int64(MessageType.voice.rawValue))
            ],
            paths: paths
        )
    }

    func markMessageDeleted(messageID: MessageID, userID: UserID) async throws {
        guard let storedMessage = try await messageDAO.message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        let now = Self.currentTimestamp()
        try await database.performTransaction(
            [
                SQLiteStatement(
                    "UPDATE message SET is_deleted = 1 WHERE message_id = ?;",
                    parameters: [.text(messageID.rawValue)]
                ),
                Self.refreshConversationSummaryStatement(
                    conversationID: storedMessage.conversationID,
                    userID: userID,
                    updatedAt: now
                )
            ],
            paths: paths
        )
        scheduleMessageRemoval(messageID: messageID, userID: userID)
        scheduleConversationIndex(conversationID: storedMessage.conversationID, userID: userID)
    }

    func revokeMessage(messageID: MessageID, userID: UserID, replacementText: String) async throws -> StoredMessage {
        guard let storedMessage = try await messageDAO.message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        let now = Self.currentTimestamp()
        try await database.performTransaction(
            [
                SQLiteStatement(
                    "UPDATE message SET revoke_status = 1 WHERE message_id = ? AND is_deleted = 0;",
                    parameters: [.text(messageID.rawValue)]
                ),
                SQLiteStatement(
                    """
                    INSERT INTO message_revoke (
                        message_id,
                        operator_id,
                        revoke_time,
                        reason,
                        replace_text
                    ) VALUES (?, ?, ?, NULL, ?)
                    ON CONFLICT(message_id) DO UPDATE SET
                        operator_id = excluded.operator_id,
                        revoke_time = excluded.revoke_time,
                        replace_text = excluded.replace_text;
                    """,
                    parameters: [
                        .text(messageID.rawValue),
                        .text(userID.rawValue),
                        .integer(now),
                        .text(replacementText)
                    ]
                ),
                Self.refreshConversationSummaryStatement(
                    conversationID: storedMessage.conversationID,
                    userID: userID,
                    updatedAt: now
                )
            ],
            paths: paths
        )

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
        try await database.performTransaction(
            [
                SQLiteStatement(
                    """
                    INSERT INTO draft (
                        conversation_id,
                        text,
                        updated_at
                    ) VALUES (?, ?, ?)
                    ON CONFLICT(conversation_id) DO UPDATE SET
                        text = excluded.text,
                        updated_at = excluded.updated_at;
                    """,
                    parameters: [
                        .text(conversationID.rawValue),
                        .text(text),
                        .integer(now)
                    ]
                ),
                SQLiteStatement(
                    """
                    UPDATE conversation
                    SET
                        draft_text = ?,
                        sort_ts = (
                            SELECT COALESCE(MAX(existing.sort_ts), ?) + 1
                            FROM conversation AS existing
                            WHERE existing.user_id = ?
                        ),
                        updated_at = ?
                    WHERE conversation_id = ? AND user_id = ?;
                    """,
                    parameters: [
                        .text(text),
                        .integer(now),
                        .text(userID.rawValue),
                        .integer(now),
                        .text(conversationID.rawValue),
                        .text(userID.rawValue)
                    ]
                )
            ],
            paths: paths
        )
        scheduleConversationIndex(conversationID: conversationID, userID: userID)
    }

    func draft(conversationID: ConversationID, userID: UserID) async throws -> String? {
        let rows = try await database.query(
            """
            SELECT draft_text
            FROM conversation
            WHERE conversation_id = ? AND user_id = ?
            LIMIT 1;
            """,
            parameters: [
                .text(conversationID.rawValue),
                .text(userID.rawValue)
            ],
            paths: paths
        )

        return rows.first?.string("draft_text")
    }

    func clearDraft(conversationID: ConversationID, userID: UserID) async throws {
        let now = Self.currentTimestamp()
        try await database.performTransaction(
            [
                SQLiteStatement(
                    "DELETE FROM draft WHERE conversation_id = ?;",
                    parameters: [.text(conversationID.rawValue)]
                ),
                SQLiteStatement(
                    """
                    UPDATE conversation
                    SET draft_text = NULL, updated_at = ?
                    WHERE conversation_id = ? AND user_id = ?;
                    """,
                    parameters: [
                        .integer(now),
                        .text(conversationID.rawValue),
                        .text(userID.rawValue)
                    ]
                )
            ],
            paths: paths
        )
        scheduleConversationIndex(conversationID: conversationID, userID: userID)
    }

    // MARK: - PendingJobRepository

    func upsertPendingJob(_ input: PendingJobInput) async throws -> PendingJob {
        let now = Self.currentTimestamp()
        let statement = Self.upsertPendingJobStatement(input, status: .pending, retryCount: 0, updatedAt: now, createdAt: now)
        try await database.execute(
            statement.sql,
            parameters: statement.parameters,
            paths: paths
        )

        guard let job = try await pendingJob(id: input.id) else {
            throw ChatStoreError.missingColumn("pending_job")
        }

        return job
    }

    func pendingJob(id: String) async throws -> PendingJob? {
        let rows = try await database.query(
            """
            SELECT
                job_id,
                user_id,
                job_type,
                biz_key,
                payload_json,
                status,
                retry_count,
                max_retry_count,
                next_retry_at,
                updated_at,
                created_at
            FROM pending_job
            WHERE job_id = ?
            LIMIT 1;
            """,
            parameters: [.text(id)],
            paths: paths
        )

        guard let row = rows.first else {
            return nil
        }

        return try Self.pendingJob(from: row)
    }

    func recoverablePendingJobs(userID: UserID, now: Int64) async throws -> [PendingJob] {
        let rows = try await database.query(
            """
            SELECT
                job_id,
                user_id,
                job_type,
                biz_key,
                payload_json,
                status,
                retry_count,
                max_retry_count,
                next_retry_at,
                updated_at,
                created_at
            FROM pending_job
            WHERE user_id = ?
            AND status IN (?, ?)
            AND retry_count < max_retry_count
            AND (next_retry_at IS NULL OR next_retry_at <= ?)
            ORDER BY COALESCE(next_retry_at, created_at), created_at;
            """,
            parameters: [
                .text(userID.rawValue),
                .integer(Int64(PendingJobStatus.pending.rawValue)),
                .integer(Int64(PendingJobStatus.running.rawValue)),
                .integer(now)
            ],
            paths: paths
        )

        return try rows.map(Self.pendingJob(from:))
    }

    func schedulePendingJobRetry(jobID: String, nextRetryAt: Int64) async throws {
        let now = Self.currentTimestamp()
        try await database.execute(
            """
            UPDATE pending_job
            SET
                status = ?,
                retry_count = retry_count + 1,
                next_retry_at = ?,
                updated_at = ?
            WHERE job_id = ?
            AND retry_count < max_retry_count;
            """,
            parameters: [
                .integer(Int64(PendingJobStatus.pending.rawValue)),
                .integer(nextRetryAt),
                .integer(now),
                .text(jobID)
            ],
            paths: paths
        )
    }

    func updatePendingJobStatus(jobID: String, status: PendingJobStatus, nextRetryAt: Int64?) async throws {
        let now = Self.currentTimestamp()
        try await database.execute(
            """
            UPDATE pending_job
            SET
                status = ?,
                retry_count = CASE
                    WHEN ? = ? THEN retry_count + 1
                    ELSE retry_count
                END,
                next_retry_at = ?,
                updated_at = ?
            WHERE job_id = ?;
            """,
            parameters: [
                .integer(Int64(status.rawValue)),
                .integer(Int64(status.rawValue)),
                .integer(Int64(PendingJobStatus.failed.rawValue)),
                .optionalInteger(nextRetryAt),
                .integer(now),
                .text(jobID)
            ],
            paths: paths
        )
    }

    func hasConversations(for userID: UserID) async throws -> Bool {
        try await conversationDAO.countConversations(for: userID) > 0
    }

    // MARK: - MediaIndexRepository

    func upsertMediaIndexRecord(_ record: MediaIndexRecord) async throws {
        try await upsertMediaIndexRecords([record])
    }

    func mediaIndexRecord(mediaID: String, userID: UserID) async throws -> MediaIndexRecord? {
        let rows = try await database.query(
            """
            SELECT
                media_id,
                user_id,
                local_path,
                file_name,
                file_ext,
                size_bytes,
                md5,
                last_access_at,
                created_at
            FROM file_index
            WHERE media_id = ?
            AND user_id = ?
            LIMIT 1;
            """,
            parameters: [
                .text(mediaID),
                .text(userID.rawValue)
            ],
            in: .fileIndex,
            paths: paths
        )

        guard let row = rows.first else {
            return nil
        }

        return try Self.mediaIndexRecord(from: row)
    }

    func touchMediaIndexRecord(mediaID: String, userID: UserID, accessedAt: Int64) async throws {
        try await database.execute(
            """
            UPDATE file_index
            SET last_access_at = ?
            WHERE media_id = ?
            AND user_id = ?;
            """,
            parameters: [
                .integer(accessedAt),
                .text(mediaID),
                .text(userID.rawValue)
            ],
            in: .fileIndex,
            paths: paths
        )
    }

    func scanMissingMediaResources(userID: UserID) async throws -> [MissingMediaResource] {
        let rows = try await database.query(
            """
            SELECT
                media_id,
                user_id,
                owner_message_id,
                local_path,
                remote_url
            FROM media_resource
            WHERE user_id = ?
            AND local_path IS NOT NULL
            AND TRIM(local_path) <> ''
            AND remote_url IS NOT NULL
            AND TRIM(remote_url) <> ''
            ORDER BY updated_at DESC, created_at DESC;
            """,
            parameters: [.text(userID.rawValue)],
            paths: paths
        )

        var missingResources: [MissingMediaResource] = []
        for row in rows {
            let localPath = try row.requiredString("local_path")
            guard !FileManager.default.fileExists(atPath: localPath) else {
                continue
            }

            missingResources.append(
                MissingMediaResource(
                    mediaID: try row.requiredString("media_id"),
                    userID: UserID(rawValue: try row.requiredString("user_id")),
                    ownerMessageID: row.string("owner_message_id").map(MessageID.init(rawValue:)),
                    localPath: localPath,
                    remoteURL: try row.requiredString("remote_url")
                )
            )
        }

        return missingResources
    }

    func enqueueMediaDownloadJobsForMissingResources(userID: UserID) async throws -> [PendingJob] {
        let missingResources = try await scanMissingMediaResources(userID: userID)
        return try await enqueueMediaDownloadJobs(for: missingResources)
    }

    func rebuildMediaIndex(userID: UserID) async throws -> MediaIndexRebuildResult {
        let resourceRows = try await mediaResourceRowsForIndexRebuild(userID: userID)
        let rebuiltRecords = resourceRows.flatMap(Self.mediaIndexRecordsForExistingFiles)
        let missingResources = try await scanMissingMediaResources(userID: userID)

        try await database.performTransaction(
            [
                SQLiteStatement(
                    "DELETE FROM file_index WHERE user_id = ?;",
                    parameters: [.text(userID.rawValue)]
                )
            ] + rebuiltRecords.map(Self.upsertMediaIndexStatement),
            in: .fileIndex,
            paths: paths
        )

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
        let statements = missingResources.map {
            Self.markMediaDownloadPendingStatement($0, updatedAt: now)
        } + pendingJobInputs.map {
            Self.upsertPendingJobStatement(
                $0,
                status: .pending,
                retryCount: 0,
                updatedAt: now,
                createdAt: now
            )
        }

        try await database.performTransaction(statements, paths: paths)

        var jobs: [PendingJob] = []
        for input in pendingJobInputs {
            if let job = try await pendingJob(id: input.id) {
                jobs.append(job)
            }
        }

        return jobs
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
        let rows = try await database.query(
            """
            SELECT biz_key, cursor, seq, updated_at
            FROM sync_checkpoint
            WHERE biz_key = ?
            LIMIT 1;
            """,
            parameters: [.text(bizKey)],
            paths: paths
        )

        guard let row = rows.first else {
            return nil
        }

        return SyncCheckpoint(
            bizKey: try row.requiredString("biz_key"),
            cursor: row.string("cursor"),
            sequence: row.int64("seq"),
            updatedAt: row.int64("updated_at") ?? 0
        )
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
        var statements: [SQLiteStatement] = messagesToInsert.flatMap {
            Self.incomingTextMessageStatements($0, userID: userID, updatedAt: now)
        }

        let unreadIncrements = Dictionary(grouping: messagesToInsert.filter { $0.direction == .incoming }, by: \.conversationID)
            .mapValues(\.count)

        for conversationID in Set(messagesToInsert.map(\.conversationID)) {
            statements.append(
                Self.refreshConversationAfterSyncStatement(
                    conversationID: conversationID,
                    userID: userID,
                    unreadIncrement: unreadIncrements[conversationID] ?? 0,
                    updatedAt: now
                )
            )
        }

        let mentionedConversationIDs = Set(
            messagesToInsert
                .filter { $0.direction == .incoming && ($0.mentionsAll || $0.mentionedUserIDs.contains(userID)) }
                .map(\.conversationID)
        )
        for conversationID in mentionedConversationIDs {
            var extra = try await conversationExtra(conversationID: conversationID) ?? ConversationExtraContext()
            extra.hasUnreadMention = true
            statements.append(try Self.updateConversationExtraStatement(conversationID: conversationID, extra: extra, updatedAt: now))
        }

        let nextSequence = batch.nextSequence ?? sortedMessages.last?.sequence
        statements.append(
            Self.upsertSyncCheckpointStatement(
                bizKey: batch.bizKey,
                cursor: batch.nextCursor,
                sequence: nextSequence,
                updatedAt: now
            )
        )

        try await database.performTransaction(statements, paths: paths)
        let badgeCount = try await refreshApplicationBadge(userID: userID)

        await notifyIncomingMessages(
            messagesToInsert.filter { $0.direction == .incoming },
            userID: userID,
            badgeCount: badgeCount
        )

        for message in messagesToInsert {
            scheduleMessageIndex(messageID: message.messageID, userID: userID)
        }

        for conversationID in Set(messagesToInsert.map(\.conversationID)) {
            scheduleConversationIndex(conversationID: conversationID, userID: userID)
        }
        eventDispatcher.postConversationsDidChange(
            userID: userID,
            conversationIDs: Set(messagesToInsert.map(\.conversationID))
        )

        return SyncApplyResult(
            fetchedCount: batch.messages.count,
            insertedCount: messagesToInsert.count,
            skippedDuplicateCount: skippedDuplicateCount,
            checkpoint: SyncCheckpoint(
                bizKey: batch.bizKey,
                cursor: batch.nextCursor,
                sequence: nextSequence,
                updatedAt: now
            )
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
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let rows = try await database.query(
                """
                SELECT conversation_id, extra_json
                FROM conversation
                WHERE conversation_id IN (\(placeholders));
                """,
                parameters: chunk.map { .text($0.rawValue) },
                paths: paths
            )

            for row in rows {
                let conversationID = ConversationID(rawValue: try row.requiredString("conversation_id"))
                guard let json = row.string("extra_json"), let data = json.data(using: .utf8) else {
                    continue
                }
                extras[conversationID] = try JSONDecoder().decode(ConversationExtraContext.self, from: data)
            }
        }

        return extras
    }

    private func conversationExtra(conversationID: ConversationID) async throws -> ConversationExtraContext? {
        let rows = try await database.query(
            "SELECT extra_json FROM conversation WHERE conversation_id = ? LIMIT 1;",
            parameters: [.text(conversationID.rawValue)],
            paths: paths
        )

        guard let json = rows.first?.string("extra_json"), let data = json.data(using: .utf8) else {
            return nil
        }

        return try JSONDecoder().decode(ConversationExtraContext.self, from: data)
    }

    private func updateConversationExtra(
        conversationID: ConversationID,
        extra: ConversationExtraContext,
        updatedAt: Int64
    ) async throws {
        let statement = try Self.updateConversationExtraStatement(conversationID: conversationID, extra: extra, updatedAt: updatedAt)
        try await database.execute(statement.sql, parameters: statement.parameters, paths: paths)
    }

    private static func updateConversationExtraStatement(
        conversationID: ConversationID,
        extra: ConversationExtraContext,
        updatedAt: Int64
    ) throws -> SQLiteStatement {
        SQLiteStatement(
            """
            UPDATE conversation
            SET extra_json = ?, updated_at = ?
            WHERE conversation_id = ?;
            """,
            parameters: try updateConversationExtraStatementParameters(
                conversationID: conversationID,
                extra: extra,
                updatedAt: updatedAt
            )
        )
    }

    private static func updateConversationExtraStatementParameters(
        conversationID: ConversationID,
        extra: ConversationExtraContext,
        updatedAt: Int64
    ) throws -> [SQLiteValue] {
        let data = try JSONEncoder().encode(extra)
        let json = String(decoding: data, as: UTF8.self)
        return [
            .text(json),
            .integer(updatedAt),
            .text(conversationID.rawValue)
        ]
    }

    private static func groupMember(from row: SQLiteRow) throws -> GroupMember {
        let roleRawValue = try row.requiredInt("role")
        guard let role = GroupMemberRole(rawValue: roleRawValue) else {
            throw ChatStoreError.invalidConversationType(roleRawValue)
        }

        return GroupMember(
            conversationID: ConversationID(rawValue: try row.requiredString("conversation_id")),
            memberID: UserID(rawValue: try row.requiredString("member_id")),
            displayName: row.string("display_name") ?? "",
            role: role,
            joinTime: row.int64("join_time")
        )
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

    private func upsertBadgeSetting(userID: UserID, column: String, value: Bool) async throws {
        let now = Self.currentTimestamp()
        let insertedBadgeEnabled = column == "badge_enabled" ? value : true
        let insertedBadgeIncludeMuted = column == "badge_include_muted" ? value : true
        try await database.execute(
            """
            INSERT INTO notification_setting (
                user_id,
                is_enabled,
                show_preview,
                badge_enabled,
                badge_include_muted,
                updated_at
            ) VALUES (?, 1, 1, ?, ?, ?)
            ON CONFLICT(user_id) DO UPDATE SET
                \(column) = ?,
                updated_at = ?;
            """,
            parameters: [
                .text(userID.rawValue),
                .integer(insertedBadgeEnabled ? 1 : 0),
                .integer(insertedBadgeIncludeMuted ? 1 : 0),
                .integer(now),
                .integer(value ? 1 : 0),
                .integer(now)
            ],
            paths: paths
        )
    }

    private func unreadBadgeCount(userID: UserID, includeMuted: Bool) async throws -> Int {
        let rows = try await database.query(
            """
            SELECT COALESCE(SUM(unread_count), 0) AS badge_count
            FROM conversation
            WHERE user_id = ?
            AND is_hidden = 0
            AND (? = 1 OR is_muted = 0);
            """,
            parameters: [
                .text(userID.rawValue),
                .integer(includeMuted ? 1 : 0)
            ],
            paths: paths
        )

        return max(0, rows.first?.int("badge_count") ?? 0)
    }

    private func mediaResourceRowsForIndexRebuild(userID: UserID) async throws -> [SQLiteRow] {
        try await database.query(
            """
            SELECT
                media_id,
                user_id,
                local_path,
                thumb_path,
                size_bytes,
                md5,
                updated_at,
                created_at
            FROM media_resource
            WHERE user_id = ?
            ORDER BY updated_at DESC, created_at DESC;
            """,
            parameters: [.text(userID.rawValue)],
            paths: paths
        )
    }

    private func interruptedOutgoingMessages(userID: UserID) async throws -> [InterruptedOutgoingMessage] {
        let rows = try await database.query(
            """
            SELECT
                message.message_id,
                message.conversation_id,
                message.client_msg_id,
                message.msg_type,
                COALESCE(message_image.media_id, message_video.media_id, message_file.media_id) AS media_id
            FROM message
            INNER JOIN conversation ON conversation.conversation_id = message.conversation_id
            LEFT JOIN message_image ON message_image.content_id = message.content_id
            LEFT JOIN message_video ON message_video.content_id = message.content_id
            LEFT JOIN message_file ON message_file.content_id = message.content_id
            WHERE conversation.user_id = ?
            AND message.direction = ?
            AND message.send_status = ?
            AND message.is_deleted = 0
            ORDER BY message.local_time ASC, message.sort_seq ASC;
            """,
            parameters: [
                .text(userID.rawValue),
                .integer(Int64(MessageDirection.outgoing.rawValue)),
                .integer(Int64(MessageSendStatus.sending.rawValue))
            ],
            paths: paths
        )

        return try rows.map(Self.interruptedOutgoingMessage(from:))
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
        let rows = try await database.query(
            """
            SELECT title, is_muted
            FROM conversation
            WHERE conversation_id = ? AND user_id = ?
            LIMIT 1;
            """,
            parameters: [
                .text(conversationID.rawValue),
                .text(userID.rawValue)
            ],
            paths: paths
        )

        guard let row = rows.first else {
            return NotificationConversationContext(title: fallbackTitle, isMuted: false)
        }

        return NotificationConversationContext(
            title: row.string("title") ?? fallbackTitle,
            isMuted: row.bool("is_muted")
        )
    }

    private static func refreshConversationSummaryStatement(
        conversationID: ConversationID,
        userID: UserID,
        updatedAt: Int64
    ) -> SQLiteStatement {
        SQLiteStatement(
            """
            UPDATE conversation
            SET
                last_message_id = (
                    SELECT message.message_id
                    FROM message
                    WHERE message.conversation_id = conversation.conversation_id
                    AND message.is_deleted = 0
                    ORDER BY message.sort_seq DESC
                    LIMIT 1
                ),
                last_message_time = (
                    SELECT message.local_time
                    FROM message
                    WHERE message.conversation_id = conversation.conversation_id
                    AND message.is_deleted = 0
                    ORDER BY message.sort_seq DESC
                    LIMIT 1
                ),
                last_message_digest = COALESCE((
                    SELECT
                        CASE
                            WHEN message.revoke_status = 1 THEN COALESCE(message_revoke.replace_text, '')
                            WHEN message.msg_type = ? THEN '[图片]'
                            WHEN message.msg_type = ? THEN '[语音]'
                            WHEN message.msg_type = ? THEN '[视频]'
                            WHEN message.msg_type = ? THEN '[文件] ' || COALESCE(message_file.file_name, '')
                            ELSE COALESCE(message_text.text, '')
                        END
                    FROM message
                    LEFT JOIN message_text ON message_text.content_id = message.content_id
                    LEFT JOIN message_file ON message_file.content_id = message.content_id
                    LEFT JOIN message_revoke ON message_revoke.message_id = message.message_id
                    WHERE message.conversation_id = conversation.conversation_id
                    AND message.is_deleted = 0
                    ORDER BY message.sort_seq DESC
                    LIMIT 1
                ), ''),
                sort_ts = COALESCE((
                    SELECT message.sort_seq
                    FROM message
                    WHERE message.conversation_id = conversation.conversation_id
                    AND message.is_deleted = 0
                    ORDER BY message.sort_seq DESC
                    LIMIT 1
                ), sort_ts),
                updated_at = ?
            WHERE conversation_id = ? AND user_id = ?;
            """,
            parameters: [
                .integer(Int64(MessageType.image.rawValue)),
                .integer(Int64(MessageType.voice.rawValue)),
                .integer(Int64(MessageType.video.rawValue)),
                .integer(Int64(MessageType.file.rawValue)),
                .integer(updatedAt),
                .text(conversationID.rawValue),
                .text(userID.rawValue)
            ]
        )
    }

    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }

    private func upsertMediaIndexRecords(_ records: [MediaIndexRecord]) async throws {
        guard !records.isEmpty else {
            return
        }

        try await database.performTransaction(
            records.map(Self.upsertMediaIndexStatement),
            in: .fileIndex,
            paths: paths
        )
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

    private static func mediaIndexRecord(from row: SQLiteRow) throws -> MediaIndexRecord {
        MediaIndexRecord(
            mediaID: try row.requiredString("media_id"),
            userID: UserID(rawValue: try row.requiredString("user_id")),
            localPath: try row.requiredString("local_path"),
            fileName: row.string("file_name"),
            fileExtension: row.string("file_ext"),
            sizeBytes: row.int64("size_bytes"),
            md5: row.string("md5"),
            lastAccessAt: row.int64("last_access_at"),
            createdAt: try row.requiredInt64("created_at")
        )
    }

    private static func mediaIndexRecordsForExistingFiles(from row: SQLiteRow) -> [MediaIndexRecord] {
        guard
            let mediaID = row.string("media_id"),
            let userID = row.string("user_id")
        else {
            return []
        }

        let timestamp = row.int64("created_at") ?? row.int64("updated_at") ?? currentTimestamp()
        let md5 = row.string("md5")
        var records: [MediaIndexRecord] = []

        if let localPath = row.string("local_path"), FileManager.default.fileExists(atPath: localPath) {
            records.append(
                MediaIndexRecord(
                    mediaID: mediaID,
                    userID: UserID(rawValue: userID),
                    localPath: localPath,
                    fileName: fileName(from: localPath),
                    fileExtension: fileExtension(from: localPath, fallback: nil),
                    sizeBytes: existingFileSize(atPath: localPath) ?? row.int64("size_bytes"),
                    md5: md5,
                    lastAccessAt: timestamp,
                    createdAt: timestamp
                )
            )
        }

        if let thumbnailPath = row.string("thumb_path"), FileManager.default.fileExists(atPath: thumbnailPath) {
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

    private static func interruptedOutgoingMessage(from row: SQLiteRow) throws -> InterruptedOutgoingMessage {
        let typeRawValue = try row.requiredInt("msg_type")
        guard let type = MessageType(rawValue: typeRawValue) else {
            throw ChatStoreError.invalidMessageType(typeRawValue)
        }

        return InterruptedOutgoingMessage(
            messageID: MessageID(rawValue: try row.requiredString("message_id")),
            conversationID: ConversationID(rawValue: try row.requiredString("conversation_id")),
            clientMessageID: row.string("client_msg_id"),
            type: type,
            mediaID: row.string("media_id")
        )
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

    private static func upsertMediaIndexStatement(_ record: MediaIndexRecord) -> SQLiteStatement {
        SQLiteStatement(
            """
            INSERT INTO file_index (
                media_id,
                user_id,
                local_path,
                file_name,
                file_ext,
                size_bytes,
                md5,
                last_access_at,
                created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(media_id) DO UPDATE SET
                user_id = excluded.user_id,
                local_path = excluded.local_path,
                file_name = excluded.file_name,
                file_ext = excluded.file_ext,
                size_bytes = excluded.size_bytes,
                md5 = excluded.md5,
                last_access_at = excluded.last_access_at,
                created_at = file_index.created_at;
            """,
            parameters: [
                .text(record.mediaID),
                .text(record.userID.rawValue),
                .text(record.localPath),
                .optionalText(record.fileName),
                .optionalText(record.fileExtension),
                .optionalInteger(record.sizeBytes),
                .optionalText(record.md5),
                .optionalInteger(record.lastAccessAt),
                .integer(record.createdAt)
            ]
        )
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

    private static func markMediaDownloadPendingStatement(
        _ resource: MissingMediaResource,
        updatedAt: Int64
    ) -> SQLiteStatement {
        SQLiteStatement(
            """
            UPDATE media_resource
            SET
                download_status = 0,
                updated_at = ?
            WHERE media_id = ?
            AND user_id = ?;
            """,
            parameters: [
                .integer(updatedAt),
                .text(resource.mediaID),
                .text(resource.userID.rawValue)
            ]
        )
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

    private static func pendingJob(from row: SQLiteRow) throws -> PendingJob {
        let typeRawValue = try row.requiredInt("job_type")
        let statusRawValue = try row.requiredInt("status")

        guard let type = PendingJobType(rawValue: typeRawValue) else {
            throw ChatStoreError.invalidPendingJobType(typeRawValue)
        }

        guard let status = PendingJobStatus(rawValue: statusRawValue) else {
            throw ChatStoreError.invalidPendingJobStatus(statusRawValue)
        }

        return PendingJob(
            id: try row.requiredString("job_id"),
            userID: UserID(rawValue: try row.requiredString("user_id")),
            type: type,
            bizKey: row.string("biz_key"),
            payloadJSON: try row.requiredString("payload_json"),
            status: status,
            retryCount: try row.requiredInt("retry_count"),
            maxRetryCount: try row.requiredInt("max_retry_count"),
            nextRetryAt: row.int64("next_retry_at"),
            updatedAt: try row.requiredInt64("updated_at"),
            createdAt: try row.requiredInt64("created_at")
        )
    }

    private static func updateMessageSendStatusStatement(
        messageID: MessageID,
        status: MessageSendStatus,
        ack: MessageSendAck?
    ) -> SQLiteStatement {
        SQLiteStatement(
            """
            UPDATE message
            SET
                send_status = ?,
                server_msg_id = ?,
                seq = ?,
                server_time = ?
            WHERE message_id = ?;
            """,
            parameters: [
                .integer(Int64(status.rawValue)),
                .optionalText(ack?.serverMessageID),
                .optionalInteger(ack?.sequence),
                .optionalInteger(ack?.serverTime),
                .text(messageID.rawValue)
            ]
        )
    }

    private static func updateImageUploadStatusStatements(
        messageID: MessageID,
        status: MediaUploadStatus,
        uploadAck: MediaUploadAck?,
        updatedAt: Int64
    ) -> [SQLiteStatement] {
        updateMediaUploadStatusStatements(
            messageID: messageID,
            status: status,
            uploadAck: uploadAck,
            updatedAt: updatedAt,
            tableSpec: .image
        )
    }

    private static func updateVoiceUploadStatusStatements(
        messageID: MessageID,
        status: MediaUploadStatus,
        uploadAck: MediaUploadAck?,
        updatedAt: Int64
    ) -> [SQLiteStatement] {
        updateMediaUploadStatusStatements(
            messageID: messageID,
            status: status,
            uploadAck: uploadAck,
            updatedAt: updatedAt,
            tableSpec: .voice
        )
    }

    private static func updateVideoUploadStatusStatements(
        messageID: MessageID,
        status: MediaUploadStatus,
        uploadAck: MediaUploadAck?,
        updatedAt: Int64
    ) -> [SQLiteStatement] {
        updateMediaUploadStatusStatements(
            messageID: messageID,
            status: status,
            uploadAck: uploadAck,
            updatedAt: updatedAt,
            tableSpec: .video
        )
    }

    private static func updateFileUploadStatusStatements(
        messageID: MessageID,
        status: MediaUploadStatus,
        uploadAck: MediaUploadAck?,
        updatedAt: Int64
    ) -> [SQLiteStatement] {
        updateMediaUploadStatusStatements(
            messageID: messageID,
            status: status,
            uploadAck: uploadAck,
            updatedAt: updatedAt,
            tableSpec: .file
        )
    }

    private static func updateMediaUploadStatusStatements(
        messageID: MessageID,
        status: MediaUploadStatus,
        uploadAck: MediaUploadAck?,
        updatedAt: Int64,
        tableSpec: MediaUploadTableSpec
    ) -> [SQLiteStatement] {
        var contentParameters: [SQLiteValue] = [
            .integer(Int64(status.rawValue)),
            .optionalText(uploadAck?.cdnURL)
        ]
        if tableSpec.writesContentMD5 {
            contentParameters.append(.optionalText(uploadAck?.md5))
        }
        contentParameters.append(.text(messageID.rawValue))

        return [
            SQLiteStatement(
                """
                UPDATE \(tableSpec.contentTable)
                SET
                \(tableSpec.contentSetClause)
                WHERE content_id = (
                    SELECT content_id
                    FROM message
                    WHERE message_id = ?
                    LIMIT 1
                );
                """,
                parameters: contentParameters
            ),
            SQLiteStatement(
                """
                UPDATE media_resource
                SET
                    upload_status = ?,
                    remote_url = COALESCE(?, remote_url),
                    md5 = COALESCE(?, md5),
                    updated_at = ?
                WHERE owner_message_id = ?;
                """,
                parameters: [
                    .integer(Int64(status.rawValue)),
                    .optionalText(uploadAck?.cdnURL),
                    .optionalText(uploadAck?.md5),
                    .integer(updatedAt),
                    .text(messageID.rawValue)
                ]
            )
        ]
    }

    private struct MediaUploadTableSpec {
        let contentTable: String
        let writesContentMD5: Bool

        var contentSetClause: String {
            if writesContentMD5 {
                """
                    upload_status = ?,
                    cdn_url = COALESCE(?, cdn_url),
                    md5 = COALESCE(?, md5)
                """
            } else {
                """
                    upload_status = ?,
                    cdn_url = COALESCE(?, cdn_url)
                """
            }
        }

        static let image = MediaUploadTableSpec(contentTable: "message_image", writesContentMD5: true)
        static let voice = MediaUploadTableSpec(contentTable: "message_voice", writesContentMD5: false)
        static let video = MediaUploadTableSpec(contentTable: "message_video", writesContentMD5: true)
        static let file = MediaUploadTableSpec(contentTable: "message_file", writesContentMD5: true)
    }

    private static func upsertPendingJobStatement(
        _ input: PendingJobInput,
        status: PendingJobStatus,
        retryCount: Int,
        updatedAt: Int64,
        createdAt: Int64
    ) -> SQLiteStatement {
        SQLiteStatement(
            """
            INSERT INTO pending_job (
                job_id,
                user_id,
                job_type,
                biz_key,
                payload_json,
                status,
                retry_count,
                max_retry_count,
                next_retry_at,
                updated_at,
                created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(job_id) DO UPDATE SET
                payload_json = CASE
                    WHEN pending_job.status IN (?, ?) THEN pending_job.payload_json
                    ELSE excluded.payload_json
                END,
                status = CASE
                    WHEN pending_job.status IN (?, ?) THEN pending_job.status
                    ELSE excluded.status
                END,
                retry_count = CASE
                    WHEN pending_job.status IN (?, ?) THEN pending_job.retry_count
                    ELSE excluded.retry_count
                END,
                max_retry_count = CASE
                    WHEN pending_job.status IN (?, ?) THEN pending_job.max_retry_count
                    ELSE excluded.max_retry_count
                END,
                next_retry_at = CASE
                    WHEN pending_job.status IN (?, ?) THEN pending_job.next_retry_at
                    ELSE excluded.next_retry_at
                END,
                updated_at = CASE
                    WHEN pending_job.status IN (?, ?) THEN pending_job.updated_at
                    ELSE excluded.updated_at
                END;
            """,
            parameters: [
                .text(input.id),
                .text(input.userID.rawValue),
                .integer(Int64(input.type.rawValue)),
                .optionalText(input.bizKey),
                .text(input.payloadJSON),
                .integer(Int64(status.rawValue)),
                .integer(Int64(retryCount)),
                .integer(Int64(input.maxRetryCount)),
                .optionalInteger(input.nextRetryAt),
                .integer(updatedAt),
                .integer(createdAt),
                .integer(Int64(PendingJobStatus.success.rawValue)),
                .integer(Int64(PendingJobStatus.cancelled.rawValue)),
                .integer(Int64(PendingJobStatus.success.rawValue)),
                .integer(Int64(PendingJobStatus.cancelled.rawValue)),
                .integer(Int64(PendingJobStatus.success.rawValue)),
                .integer(Int64(PendingJobStatus.cancelled.rawValue)),
                .integer(Int64(PendingJobStatus.success.rawValue)),
                .integer(Int64(PendingJobStatus.cancelled.rawValue)),
                .integer(Int64(PendingJobStatus.success.rawValue)),
                .integer(Int64(PendingJobStatus.cancelled.rawValue)),
                .integer(Int64(PendingJobStatus.success.rawValue)),
                .integer(Int64(PendingJobStatus.cancelled.rawValue))
            ]
        )
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

        var clauses: [String] = []
        var parameters: [SQLiteValue] = []
        appendInClause(
            column: "client_msg_id",
            values: clientMessageIDs,
            clauses: &clauses,
            parameters: &parameters
        )
        appendInClause(
            column: "server_msg_id",
            values: serverMessageIDs,
            clauses: &clauses,
            parameters: &parameters
        )

        for (conversationID, sequences) in sequencesByConversation.sorted(by: { $0.key.rawValue < $1.key.rawValue }) where !sequences.isEmpty {
            let placeholders = Array(repeating: "?", count: sequences.count).joined(separator: ", ")
            clauses.append("(conversation_id = ? AND seq IN (\(placeholders)))")
            parameters.append(.text(conversationID.rawValue))
            parameters.append(contentsOf: sequences.map(SQLiteValue.integer))
        }

        guard !clauses.isEmpty else {
            return ExistingMessageDedupKeys()
        }

        let rows = try await database.query(
            """
            SELECT client_msg_id, server_msg_id, conversation_id, seq
            FROM message
            WHERE \(clauses.joined(separator: "\nOR "));
            """,
            parameters: parameters,
            paths: paths
        )

        var keys = ExistingMessageDedupKeys()
        for row in rows {
            if let clientMessageID = row.string("client_msg_id") {
                keys.clientMessageIDs.insert(clientMessageID)
            }
            if let serverMessageID = row.string("server_msg_id") {
                keys.serverMessageIDs.insert(serverMessageID)
            }
            if let conversationID = row.string("conversation_id"), let sequence = row.int64("seq") {
                keys.conversationSequences.insert(
                    ExistingMessageDedupKeys.sequenceKey(
                        conversationID: ConversationID(rawValue: conversationID),
                        sequence: sequence
                    )
                )
            }
        }

        return keys
    }

    private func appendInClause(
        column: String,
        values: [String],
        clauses: inout [String],
        parameters: inout [SQLiteValue]
    ) {
        let uniqueValues = Array(Set(values)).sorted()
        guard !uniqueValues.isEmpty else {
            return
        }

        let placeholders = Array(repeating: "?", count: uniqueValues.count).joined(separator: ", ")
        clauses.append("\(column) IN (\(placeholders))")
        parameters.append(contentsOf: uniqueValues.map(SQLiteValue.text))
    }

    private static func incomingTextMessageStatements(
        _ message: IncomingSyncMessage,
        userID: UserID,
        updatedAt: Int64
    ) -> [SQLiteStatement] {
        let contentID = "sync_text_\(message.messageID.rawValue)"

        return [
            SQLiteStatement(
                """
                INSERT OR IGNORE INTO conversation (
                    conversation_id,
                    user_id,
                    biz_type,
                    target_id,
                    title,
                    last_message_digest,
                    unread_count,
                    is_pinned,
                    is_muted,
                    is_hidden,
                    extra_json,
                    sort_ts,
                    updated_at,
                    created_at
                ) VALUES (?, ?, ?, ?, ?, '', 0, 0, 0, 0, NULL, ?, ?, ?);
                """,
                parameters: [
                    .text(message.conversationID.rawValue),
                    .text(userID.rawValue),
                    .integer(Int64(message.conversationType.rawValue)),
                    .text(message.senderID.rawValue),
                    .text(message.conversationTitle ?? message.senderID.rawValue),
                    .integer(message.sequence),
                    .integer(updatedAt),
                    .integer(updatedAt)
                ]
            ),
            SQLiteStatement(
                """
                INSERT INTO message_text (
                    content_id,
                    text,
                    mentions_json,
                    at_all,
                    rich_text_json
                ) VALUES (?, ?, ?, ?, NULL);
                """,
                parameters: [
                    .text(contentID),
                    .text(message.text),
                    .optionalText(Self.mentionsJSON(for: message.mentionedUserIDs)),
                    .integer(message.mentionsAll ? 1 : 0)
                ]
            ),
            MessageDAO.insertMessageRecordStatement(
                messageID: message.messageID,
                conversationID: message.conversationID,
                senderID: message.senderID,
                clientMessageID: message.clientMessageID,
                serverMessageID: message.serverMessageID,
                sequence: message.sequence,
                type: .text,
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
            )
        ]
    }

    private static func refreshConversationAfterSyncStatement(
        conversationID: ConversationID,
        userID: UserID,
        unreadIncrement: Int,
        updatedAt: Int64
    ) -> SQLiteStatement {
        SQLiteStatement(
            """
            UPDATE conversation
            SET
                last_message_id = (
                    SELECT message.message_id
                    FROM message
                    WHERE message.conversation_id = conversation.conversation_id
                    AND message.is_deleted = 0
                    ORDER BY message.sort_seq DESC
                    LIMIT 1
                ),
                last_message_time = (
                    SELECT COALESCE(message.server_time, message.local_time)
                    FROM message
                    WHERE message.conversation_id = conversation.conversation_id
                    AND message.is_deleted = 0
                    ORDER BY message.sort_seq DESC
                    LIMIT 1
                ),
                last_message_digest = COALESCE((
                    SELECT
                        CASE
                            WHEN message.revoke_status = 1 THEN COALESCE(message_revoke.replace_text, '')
                            ELSE COALESCE(message_text.text, '')
                        END
                    FROM message
                    LEFT JOIN message_text ON message_text.content_id = message.content_id
                    LEFT JOIN message_revoke ON message_revoke.message_id = message.message_id
                    WHERE message.conversation_id = conversation.conversation_id
                    AND message.is_deleted = 0
                    ORDER BY message.sort_seq DESC
                    LIMIT 1
                ), ''),
                sort_ts = COALESCE((
                    SELECT message.sort_seq
                    FROM message
                    WHERE message.conversation_id = conversation.conversation_id
                    AND message.is_deleted = 0
                    ORDER BY message.sort_seq DESC
                    LIMIT 1
                ), sort_ts),
                unread_count = unread_count + ?,
                updated_at = ?
            WHERE conversation_id = ? AND user_id = ?;
            """,
            parameters: [
                .integer(Int64(unreadIncrement)),
                .integer(updatedAt),
                .text(conversationID.rawValue),
                .text(userID.rawValue)
            ]
        )
    }

    private static func upsertSyncCheckpointStatement(
        bizKey: String,
        cursor: String?,
        sequence: Int64?,
        updatedAt: Int64
    ) -> SQLiteStatement {
        SQLiteStatement(
            """
            INSERT INTO sync_checkpoint (
                biz_key,
                cursor,
                seq,
                updated_at
            ) VALUES (?, ?, ?, ?)
            ON CONFLICT(biz_key) DO UPDATE SET
                cursor = excluded.cursor,
                seq = excluded.seq,
                updated_at = excluded.updated_at;
            """,
            parameters: [
                .text(bizKey),
                .optionalText(cursor),
                .optionalInteger(sequence),
                .integer(updatedAt)
            ]
        )
    }
}
