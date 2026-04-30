//
//  LocalChatRepository.swift
//  AppleIM
//
//  本地聊天仓储
//  实现多个仓储协议，统一管理会话、消息、同步等数据操作

import Foundation

nonisolated private struct MediaDownloadPendingJobPayload: Codable, Equatable, Sendable {
    let mediaID: String
    let ownerMessageID: String?
    let localPath: String
    let remoteURL: String
}

nonisolated private struct NotificationConversationContext: Equatable, Sendable {
    let title: String
    let isMuted: Bool
}

/// 本地聊天仓储
///
/// 聚合多个 DAO，实现会话、消息、同步等多个仓储协议
/// 所有操作通过 DatabaseActor 串行化执行
nonisolated struct LocalChatRepository: ConversationRepository, NotificationSettingsRepository, MessageRepository, MessageSendRecoveryRepository, PendingJobRepository, MediaIndexRepository, SyncStore {
    /// 数据库 Actor
    private let database: DatabaseActor
    /// 账号存储路径
    private let paths: AccountStoragePaths
    /// 会话 DAO
    private let conversationDAO: ConversationDAO
    /// 消息 DAO
    private let messageDAO: MessageDAO
    /// 本地通知管理器
    private let localNotificationManager: (any LocalNotificationManaging)?
    /// App 角标管理器
    private let applicationBadgeManager: (any ApplicationBadgeManaging)?

    init(
        database: DatabaseActor,
        paths: AccountStoragePaths,
        localNotificationManager: (any LocalNotificationManaging)? = nil,
        applicationBadgeManager: (any ApplicationBadgeManaging)? = nil
    ) {
        self.database = database
        self.paths = paths
        self.conversationDAO = ConversationDAO(database: database, paths: paths)
        self.messageDAO = MessageDAO(database: database, paths: paths)
        self.localNotificationManager = localNotificationManager
        self.applicationBadgeManager = applicationBadgeManager
    }

    // MARK: - ConversationRepository

    func listConversations(for userID: UserID) async throws -> [Conversation] {
        let records = try await conversationDAO.listConversations(for: userID)
        return records.map(Self.conversation(from:))
    }

    func upsertConversation(_ record: ConversationRecord) async throws {
        try await conversationDAO.upsert(record)
        scheduleConversationIndex(conversationID: record.id, userID: record.userID)
        _ = try await refreshApplicationBadge(userID: record.userID)
    }

    func markConversationRead(conversationID: ConversationID, userID: UserID) async throws {
        try await conversationDAO.markRead(conversationID: conversationID, userID: userID)
        _ = try await refreshApplicationBadge(userID: userID)
    }

    // MARK: - NotificationSettingsRepository

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

    func updateBadgeEnabled(userID: UserID, isEnabled: Bool) async throws {
        try await upsertBadgeSetting(
            userID: userID,
            column: "badge_enabled",
            value: isEnabled
        )
        _ = try await refreshApplicationBadge(userID: userID)
    }

    func updateBadgeIncludeMuted(userID: UserID, includeMuted: Bool) async throws {
        try await upsertBadgeSetting(
            userID: userID,
            column: "badge_include_muted",
            value: includeMuted
        )
        _ = try await refreshApplicationBadge(userID: userID)
    }

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

        if let applicationBadgeManager {
            await applicationBadgeManager.setApplicationIconBadgeNumber(badgeCount)
        }

        return badgeCount
    }

    // MARK: - MessageRepository

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

    func resendTextMessage(messageID: MessageID) async throws -> StoredMessage {
        try await messageDAO.prepareTextMessageForResend(messageID: messageID)
    }

    func resendImageMessage(messageID: MessageID) async throws -> StoredMessage {
        guard let existingMessage = try await messageDAO.message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        guard
            existingMessage.type == .image,
            existingMessage.sendStatus == .failed,
            !existingMessage.isRevoked,
            !existingMessage.isDeleted
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
        var messagesToInsert: [IncomingSyncMessage] = []
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

            if try await containsDuplicateIncomingMessage(message) {
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

    private static func conversation(from record: ConversationRecord) -> Conversation {
        Conversation(
            id: record.id,
            type: record.type,
            title: record.title,
            lastMessageDigest: record.lastMessageDigest,
            lastMessageTimeText: timeText(from: record.lastMessageTime),
            unreadCount: record.unreadCount,
            isPinned: record.isPinned,
            isMuted: record.isMuted,
            draftText: record.draftText
        )
    }

    private static func timeText(from timestamp: Int64?) -> String {
        guard let timestamp, timestamp > 0 else {
            return ""
        }

        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
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

    private func notifyIncomingMessages(_ messages: [IncomingSyncMessage], userID: UserID, badgeCount: Int) async {
        guard let localNotificationManager, !messages.isEmpty else {
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

            try? await localNotificationManager.scheduleIncomingMessageNotification(
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
                updated_at = ?
            WHERE conversation_id = ? AND user_id = ?;
            """,
            parameters: [
                .integer(Int64(MessageType.image.rawValue)),
                .integer(Int64(MessageType.voice.rawValue)),
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
        let searchIndex = SearchIndexActor(database: database, paths: paths)
        Task {
            await searchIndex.indexMessageBestEffort(messageID: messageID, userID: userID)
        }
    }

    private func scheduleMessageRemoval(messageID: MessageID, userID: UserID) {
        let searchIndex = SearchIndexActor(database: database, paths: paths)
        Task {
            await searchIndex.removeMessageBestEffort(messageID: messageID, userID: userID)
        }
    }

    private func scheduleConversationIndex(conversationID: ConversationID, userID: UserID) {
        let searchIndex = SearchIndexActor(database: database, paths: paths)
        Task {
            await searchIndex.indexConversationBestEffort(conversationID: conversationID, userID: userID)
        }
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

    private static func mediaIndexRecords(
        for image: StoredImageContent,
        userID: UserID,
        createdAt: Int64
    ) -> [MediaIndexRecord] {
        [
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let payloadData = try encoder.encode(payload)

        guard let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            throw ChatStoreError.missingColumn("media_download_payload")
        }

        return PendingJobInput(
            id: mediaDownloadJobID(mediaID: resource.mediaID),
            userID: resource.userID,
            type: .mediaDownload,
            bizKey: resource.mediaID,
            payloadJSON: payloadJSON,
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
        [
            SQLiteStatement(
                """
                UPDATE message_image
                SET
                    upload_status = ?,
                    cdn_url = COALESCE(?, cdn_url),
                    md5 = COALESCE(?, md5)
                WHERE content_id = (
                    SELECT content_id
                    FROM message
                    WHERE message_id = ?
                    LIMIT 1
                );
                """,
                parameters: [
                    .integer(Int64(status.rawValue)),
                    .optionalText(uploadAck?.cdnURL),
                    .optionalText(uploadAck?.md5),
                    .text(messageID.rawValue)
                ]
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

    private static func updateVoiceUploadStatusStatements(
        messageID: MessageID,
        status: MediaUploadStatus,
        uploadAck: MediaUploadAck?,
        updatedAt: Int64
    ) -> [SQLiteStatement] {
        [
            SQLiteStatement(
                """
                UPDATE message_voice
                SET
                    upload_status = ?,
                    cdn_url = COALESCE(?, cdn_url)
                WHERE content_id = (
                    SELECT content_id
                    FROM message
                    WHERE message_id = ?
                    LIMIT 1
                );
                """,
                parameters: [
                    .integer(Int64(status.rawValue)),
                    .optionalText(uploadAck?.cdnURL),
                    .text(messageID.rawValue)
                ]
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
                payload_json = excluded.payload_json,
                status = CASE
                    WHEN pending_job.status IN (?, ?) THEN pending_job.status
                    ELSE excluded.status
                END,
                retry_count = CASE
                    WHEN pending_job.status IN (?, ?) THEN pending_job.retry_count
                    ELSE excluded.retry_count
                END,
                max_retry_count = excluded.max_retry_count,
                next_retry_at = CASE
                    WHEN pending_job.status IN (?, ?) THEN pending_job.next_retry_at
                    ELSE excluded.next_retry_at
                END,
                updated_at = excluded.updated_at;
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
                .integer(Int64(PendingJobStatus.cancelled.rawValue))
            ]
        )
    }

    private func containsDuplicateIncomingMessage(_ message: IncomingSyncMessage) async throws -> Bool {
        let rows = try await database.query(
            """
            SELECT message_id
            FROM message
            WHERE
                (? IS NOT NULL AND client_msg_id = ?)
                OR (? IS NOT NULL AND server_msg_id = ?)
                OR (conversation_id = ? AND seq = ?)
            LIMIT 1;
            """,
            parameters: [
                .optionalText(message.clientMessageID),
                .optionalText(message.clientMessageID),
                .optionalText(message.serverMessageID),
                .optionalText(message.serverMessageID),
                .text(message.conversationID.rawValue),
                .integer(message.sequence)
            ],
            paths: paths
        )

        return !rows.isEmpty
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

        let sequenceKey = "\(message.conversationID.rawValue)#\(message.sequence)"
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
                    sort_ts,
                    updated_at,
                    created_at
                ) VALUES (?, ?, ?, ?, ?, '', 0, 0, 0, 0, ?, ?, ?);
                """,
                parameters: [
                    .text(message.conversationID.rawValue),
                    .text(userID.rawValue),
                    .integer(Int64(ConversationType.single.rawValue)),
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
                ) VALUES (?, ?, NULL, 0, NULL);
                """,
                parameters: [
                    .text(contentID),
                    .text(message.text)
                ]
            ),
            SQLiteStatement(
                """
                INSERT INTO message (
                    message_id,
                    conversation_id,
                    sender_id,
                    client_msg_id,
                    server_msg_id,
                    seq,
                    msg_type,
                    direction,
                    send_status,
                    delivery_status,
                    read_status,
                    revoke_status,
                    is_deleted,
                    content_table,
                    content_id,
                    sort_seq,
                    server_time,
                    local_time
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, 0, ?, ?, ?, ?, ?);
                """,
                parameters: [
                    .text(message.messageID.rawValue),
                    .text(message.conversationID.rawValue),
                    .text(message.senderID.rawValue),
                    .optionalText(message.clientMessageID),
                    .optionalText(message.serverMessageID),
                    .integer(message.sequence),
                    .integer(Int64(MessageType.text.rawValue)),
                    .integer(Int64(message.direction.rawValue)),
                    .integer(Int64(MessageSendStatus.success.rawValue)),
                    .text("message_text"),
                    .text(contentID),
                    .integer(message.sequence),
                    .integer(message.serverTime),
                    .integer(message.localTime)
                ]
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
