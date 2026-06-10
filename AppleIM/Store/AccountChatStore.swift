//
//  AccountChatStore.swift
//  AppleIM
//
//  账号级聊天存储门面
//

import Foundation

/// 会话存储能力。
protocol ConversationStore: ConversationRepository, ConversationObservationRepository {}

/// 消息存储能力。
protocol MessageStore: MessageRepository, MessageObservationRepository, MessageSendRecoveryRepository, MessageCrashRecoveryRepository {}

/// 联系人存储能力。
protocol ContactStore: ContactRepository {}

/// 表情存储能力。
protocol EmojiStore: EmojiRepository {}

/// 会话 Store 实现。
///
/// 当前仍委托现有本地仓储执行事务和事件副作用，但对上层只暴露会话窄协议。
nonisolated struct ConversationStoreImpl: ConversationStore {
    private let repository: LocalChatRepository

    init(repository: LocalChatRepository) {
        self.repository = repository
    }

    func listConversations(for userID: UserID) async throws -> [Conversation] {
        try await repository.listConversations(for: userID)
    }

    func listConversations(for userID: UserID, limit: Int, after cursor: ConversationPageCursor?) async throws -> [Conversation] {
        try await repository.listConversations(for: userID, limit: limit, after: cursor)
    }

    func unreadConversationCount(for userID: UserID) async throws -> Int {
        try await repository.unreadConversationCount(for: userID)
    }

    func upsertConversation(_ record: ConversationRecord) async throws {
        try await repository.upsertConversation(record)
    }

    func markConversationRead(conversationID: ConversationID, userID: UserID) async throws {
        try await repository.markConversationRead(conversationID: conversationID, userID: userID)
    }

    func updateConversationPin(conversationID: ConversationID, userID: UserID, isPinned: Bool) async throws {
        try await repository.updateConversationPin(conversationID: conversationID, userID: userID, isPinned: isPinned)
    }

    func updateConversationMute(conversationID: ConversationID, userID: UserID, isMuted: Bool) async throws {
        try await repository.updateConversationMute(conversationID: conversationID, userID: userID, isMuted: isMuted)
    }

    func groupMembers(conversationID: ConversationID) async throws -> [GroupMember] {
        try await repository.groupMembers(conversationID: conversationID)
    }

    func currentMemberRole(conversationID: ConversationID, userID: UserID) async throws -> GroupMemberRole? {
        try await repository.currentMemberRole(conversationID: conversationID, userID: userID)
    }

    func groupAnnouncement(conversationID: ConversationID) async throws -> GroupAnnouncement? {
        try await repository.groupAnnouncement(conversationID: conversationID)
    }

    func updateGroupAnnouncement(conversationID: ConversationID, userID: UserID, text: String) async throws {
        try await repository.updateGroupAnnouncement(conversationID: conversationID, userID: userID, text: text)
    }

    func observeConversations(for userID: UserID, limit: Int) async throws -> DatabaseObservationStream<[Conversation]> {
        try await repository.observeConversations(for: userID, limit: limit)
    }

    func observeUnreadBadgeCount(for userID: UserID) async throws -> DatabaseObservationStream<Int> {
        try await repository.observeUnreadBadgeCount(for: userID)
    }
}

/// 消息 Store 实现。
nonisolated struct MessageStoreImpl: MessageStore {
    private let repository: LocalChatRepository

    init(repository: LocalChatRepository) {
        self.repository = repository
    }

    func listMessages(conversationID: ConversationID, limit: Int, beforeSortSeq: Int64?) async throws -> [StoredMessage] {
        try await repository.listMessages(conversationID: conversationID, limit: limit, beforeSortSeq: beforeSortSeq)
    }

    func message(messageID: MessageID) async throws -> StoredMessage? {
        try await repository.message(messageID: messageID)
    }

    func saveDraft(conversationID: ConversationID, userID: UserID, text: String) async throws {
        try await repository.saveDraft(conversationID: conversationID, userID: userID, text: text)
    }

    func draft(conversationID: ConversationID, userID: UserID) async throws -> String? {
        try await repository.draft(conversationID: conversationID, userID: userID)
    }

    func clearDraft(conversationID: ConversationID, userID: UserID) async throws {
        try await repository.clearDraft(conversationID: conversationID, userID: userID)
    }

    func insertOutgoingTextMessage(_ input: OutgoingTextMessageInput) async throws -> StoredMessage {
        try await repository.insertOutgoingTextMessage(input)
    }

    func insertOutgoingImageMessage(_ input: OutgoingImageMessageInput) async throws -> StoredMessage {
        try await repository.insertOutgoingImageMessage(input)
    }

    func insertOutgoingVoiceMessage(_ input: OutgoingVoiceMessageInput) async throws -> StoredMessage {
        try await repository.insertOutgoingVoiceMessage(input)
    }

    func insertOutgoingVideoMessage(_ input: OutgoingVideoMessageInput) async throws -> StoredMessage {
        try await repository.insertOutgoingVideoMessage(input)
    }

    func insertOutgoingFileMessage(_ input: OutgoingFileMessageInput) async throws -> StoredMessage {
        try await repository.insertOutgoingFileMessage(input)
    }

    func insertOutgoingEmojiMessage(_ input: OutgoingEmojiMessageInput) async throws -> StoredMessage {
        try await repository.insertOutgoingEmojiMessage(input)
    }

    func updateMessageSendStatus(messageID: MessageID, status: MessageSendStatus, ack: MessageSendAck?) async throws {
        try await repository.updateMessageSendStatus(messageID: messageID, status: status, ack: ack)
    }

    func resendTextMessage(messageID: MessageID) async throws -> StoredMessage {
        try await repository.resendTextMessage(messageID: messageID)
    }

    func resendImageMessage(messageID: MessageID) async throws -> StoredMessage {
        try await repository.resendImageMessage(messageID: messageID)
    }

    func resendVideoMessage(messageID: MessageID) async throws -> StoredMessage {
        try await repository.resendVideoMessage(messageID: messageID)
    }

    func resendFileMessage(messageID: MessageID) async throws -> StoredMessage {
        try await repository.resendFileMessage(messageID: messageID)
    }

    func updateImageUploadStatus(
        messageID: MessageID,
        uploadStatus: MediaUploadStatus,
        uploadAck: MediaUploadAck?,
        sendStatus: MessageSendStatus,
        sendAck: MessageSendAck?,
        pendingJob: PendingJobInput?
    ) async throws {
        try await repository.updateImageUploadStatus(
            messageID: messageID,
            uploadStatus: uploadStatus,
            uploadAck: uploadAck,
            sendStatus: sendStatus,
            sendAck: sendAck,
            pendingJob: pendingJob
        )
    }

    func updateVoiceUploadStatus(
        messageID: MessageID,
        uploadStatus: MediaUploadStatus,
        uploadAck: MediaUploadAck?,
        sendStatus: MessageSendStatus,
        sendAck: MessageSendAck?
    ) async throws {
        try await repository.updateVoiceUploadStatus(
            messageID: messageID,
            uploadStatus: uploadStatus,
            uploadAck: uploadAck,
            sendStatus: sendStatus,
            sendAck: sendAck
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
        try await repository.updateVideoUploadStatus(
            messageID: messageID,
            uploadStatus: uploadStatus,
            uploadAck: uploadAck,
            sendStatus: sendStatus,
            sendAck: sendAck,
            pendingJob: pendingJob
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
        try await repository.updateFileUploadStatus(
            messageID: messageID,
            uploadStatus: uploadStatus,
            uploadAck: uploadAck,
            sendStatus: sendStatus,
            sendAck: sendAck,
            pendingJob: pendingJob
        )
    }

    func markVoicePlayed(messageID: MessageID) async throws {
        try await repository.markVoicePlayed(messageID: messageID)
    }

    func markMessageDeleted(messageID: MessageID, userID: UserID) async throws {
        try await repository.markMessageDeleted(messageID: messageID, userID: userID)
    }

    func revokeMessage(messageID: MessageID, userID: UserID, replacementText: String) async throws -> StoredMessage {
        try await repository.revokeMessage(messageID: messageID, userID: userID, replacementText: replacementText)
    }

    func observeLatestMessages(conversationID: ConversationID, limit: Int) async throws -> DatabaseObservationStream<[StoredMessage]> {
        try await repository.observeLatestMessages(conversationID: conversationID, limit: limit)
    }

    func updateMessageSendStatus(
        messageID: MessageID,
        status: MessageSendStatus,
        ack: MessageSendAck?,
        pendingJob: PendingJobInput?
    ) async throws {
        try await repository.updateMessageSendStatus(
            messageID: messageID,
            status: status,
            ack: ack,
            pendingJob: pendingJob
        )
    }

    func recoverInterruptedOutgoingMessages(
        userID: UserID,
        retryPolicy: MessageRetryPolicy,
        now: Int64
    ) async throws -> MessageCrashRecoveryResult {
        try await repository.recoverInterruptedOutgoingMessages(userID: userID, retryPolicy: retryPolicy, now: now)
    }
}

/// 联系人 Store 实现。
nonisolated struct ContactStoreImpl: ContactStore {
    private let repository: LocalChatRepository

    init(repository: LocalChatRepository) {
        self.repository = repository
    }

    func listContacts(for userID: UserID) async throws -> [ContactRecord] {
        try await repository.listContacts(for: userID)
    }

    func countContacts(for userID: UserID) async throws -> Int {
        try await repository.countContacts(for: userID)
    }

    func contact(id contactID: ContactID, userID: UserID) async throws -> ContactRecord? {
        try await repository.contact(id: contactID, userID: userID)
    }

    func upsertContact(_ record: ContactRecord) async throws {
        try await repository.upsertContact(record)
    }

    func upsertContacts(_ records: [ContactRecord]) async throws {
        try await repository.upsertContacts(records)
    }

    func conversationForContact(contactID: ContactID, userID: UserID) async throws -> Conversation {
        try await repository.conversationForContact(contactID: contactID, userID: userID)
    }
}

/// 通知设置 Store 实现。
nonisolated struct NotificationSettingsStoreImpl: NotificationSettingsRepository {
    private let repository: LocalChatRepository

    init(repository: LocalChatRepository) {
        self.repository = repository
    }

    func notificationSetting(for userID: UserID) async throws -> NotificationSettingRecord {
        try await repository.notificationSetting(for: userID)
    }

    func updateBadgeEnabled(userID: UserID, isEnabled: Bool) async throws {
        try await repository.updateBadgeEnabled(userID: userID, isEnabled: isEnabled)
    }

    func updateBadgeIncludeMuted(userID: UserID, includeMuted: Bool) async throws {
        try await repository.updateBadgeIncludeMuted(userID: userID, includeMuted: includeMuted)
    }

    func refreshApplicationBadge(userID: UserID) async throws -> Int {
        try await repository.refreshApplicationBadge(userID: userID)
    }
}

/// 待处理任务 Store 实现。
nonisolated struct PendingJobStoreImpl: PendingJobRepository {
    private let repository: LocalChatRepository

    init(repository: LocalChatRepository) {
        self.repository = repository
    }

    func upsertPendingJob(_ input: PendingJobInput) async throws -> PendingJob {
        try await repository.upsertPendingJob(input)
    }

    func pendingJob(id: String) async throws -> PendingJob? {
        try await repository.pendingJob(id: id)
    }

    func recoverablePendingJobs(userID: UserID, now: Int64) async throws -> [PendingJob] {
        try await repository.recoverablePendingJobs(userID: userID, now: now)
    }

    func schedulePendingJobRetry(jobID: String, nextRetryAt: Int64) async throws {
        try await repository.schedulePendingJobRetry(jobID: jobID, nextRetryAt: nextRetryAt)
    }

    func updatePendingJobStatus(jobID: String, status: PendingJobStatus, nextRetryAt: Int64?) async throws {
        try await repository.updatePendingJobStatus(jobID: jobID, status: status, nextRetryAt: nextRetryAt)
    }
}

/// 媒体索引 Store 实现。
nonisolated struct MediaIndexStoreImpl: MediaIndexRepository {
    private let repository: LocalChatRepository

    init(repository: LocalChatRepository) {
        self.repository = repository
    }

    func upsertMediaIndexRecord(_ record: MediaIndexRecord) async throws {
        try await repository.upsertMediaIndexRecord(record)
    }

    func mediaIndexRecord(mediaID: String, userID: UserID) async throws -> MediaIndexRecord? {
        try await repository.mediaIndexRecord(mediaID: mediaID, userID: userID)
    }

    func touchMediaIndexRecord(mediaID: String, userID: UserID, accessedAt: Int64) async throws {
        try await repository.touchMediaIndexRecord(mediaID: mediaID, userID: userID, accessedAt: accessedAt)
    }

    func scanMissingMediaResources(userID: UserID) async throws -> [MissingMediaResource] {
        try await repository.scanMissingMediaResources(userID: userID)
    }

    func enqueueMediaDownloadJobsForMissingResources(userID: UserID) async throws -> [PendingJob] {
        try await repository.enqueueMediaDownloadJobsForMissingResources(userID: userID)
    }

    func rebuildMediaIndex(userID: UserID) async throws -> MediaIndexRebuildResult {
        try await repository.rebuildMediaIndex(userID: userID)
    }
}

/// 表情 Store 实现。
nonisolated struct EmojiStoreImpl: EmojiStore {
    private let repository: LocalChatRepository

    init(repository: LocalChatRepository) {
        self.repository = repository
    }

    func upsertEmojiPackage(_ package: EmojiPackageRecord) async throws {
        try await repository.upsertEmojiPackage(package)
    }

    func upsertEmojiAsset(_ emoji: EmojiAssetRecord) async throws {
        try await repository.upsertEmojiAsset(emoji)
    }

    func listEmojiPackages(for userID: UserID) async throws -> [EmojiPackageRecord] {
        try await repository.listEmojiPackages(for: userID)
    }

    func listPackageEmojis(for userID: UserID, packageID: String) async throws -> [EmojiAssetRecord] {
        try await repository.listPackageEmojis(for: userID, packageID: packageID)
    }

    func listFavoriteEmojis(for userID: UserID) async throws -> [EmojiAssetRecord] {
        try await repository.listFavoriteEmojis(for: userID)
    }

    func listRecentEmojis(for userID: UserID, limit: Int) async throws -> [EmojiAssetRecord] {
        try await repository.listRecentEmojis(for: userID, limit: limit)
    }

    func emoji(emojiID: String, userID: UserID) async throws -> EmojiAssetRecord? {
        try await repository.emoji(emojiID: emojiID, userID: userID)
    }

    func setEmojiFavorite(emojiID: String, userID: UserID, isFavorite: Bool, updatedAt: Int64) async throws {
        try await repository.setEmojiFavorite(emojiID: emojiID, userID: userID, isFavorite: isFavorite, updatedAt: updatedAt)
    }

    func recordEmojiUsed(emojiID: String, userID: UserID, usedAt: Int64) async throws {
        try await repository.recordEmojiUsed(emojiID: emojiID, userID: userID, usedAt: usedAt)
    }
}

/// 同步 Store 实现。
nonisolated struct SyncStoreImpl: SyncStore {
    private let repository: LocalChatRepository

    init(repository: LocalChatRepository) {
        self.repository = repository
    }

    func syncCheckpoint(for bizKey: String) async throws -> SyncCheckpoint? {
        try await repository.syncCheckpoint(for: bizKey)
    }

    func applyIncomingSyncBatch(_ batch: SyncBatch, userID: UserID) async throws -> SyncApplyResult {
        try await repository.applyIncomingSyncBatch(batch, userID: userID)
    }
}

/// 当前账号下的 Store 能力入口。
///
/// 本类型组合各个窄 Store 实现，生产上层不再接收全能仓储。
nonisolated struct AccountChatStore: Sendable {
    let conversations: ConversationStoreImpl
    let messages: MessageStoreImpl
    let contacts: ContactStoreImpl
    let notificationSettings: NotificationSettingsStoreImpl
    let pendingJobs: PendingJobStoreImpl
    let mediaIndex: MediaIndexStoreImpl
    let emojis: EmojiStoreImpl
    let sync: SyncStoreImpl

    private let repositoryForMaintenance: LocalChatRepository

    init(repository: LocalChatRepository) {
        conversations = ConversationStoreImpl(repository: repository)
        messages = MessageStoreImpl(repository: repository)
        contacts = ContactStoreImpl(repository: repository)
        notificationSettings = NotificationSettingsStoreImpl(repository: repository)
        pendingJobs = PendingJobStoreImpl(repository: repository)
        mediaIndex = MediaIndexStoreImpl(repository: repository)
        emojis = EmojiStoreImpl(repository: repository)
        sync = SyncStoreImpl(repository: repository)
        repositoryForMaintenance = repository
    }

    var simulatedIncomingPushRepository: any SimulatedIncomingPushRepository {
        repositoryForMaintenance
    }

    var simulatedContactProfilePushRepository: any SimulatedContactProfilePushRepository {
        repositoryForMaintenance
    }

    var dataRepairRepository: LocalChatRepository {
        repositoryForMaintenance
    }
}
