//
//  ChatServiceHub.swift
//  AppleIM
//
//  聊天用例
//  封装聊天页的业务逻辑，包括消息加载、发送、重试等

import Foundation

/// 聊天消息分页结果
nonisolated struct ChatMessagePage: Equatable, Sendable {
    /// 消息行数组
    let rows: [ChatMessageRowState]
    /// 是否还有更多消息
    let hasMore: Bool
    /// 下一页的游标
    let nextBeforeSortSequence: Int64?
}

/// 语音录制文件
nonisolated struct VoiceRecordingFile: Equatable, Sendable {
    /// 临时录音文件 URL
    let fileURL: URL
    /// 录音时长（毫秒）
    let durationMilliseconds: Int
    /// 文件扩展名
    let fileExtension: String?

    /// 初始化录音文件描述
    init(fileURL: URL, durationMilliseconds: Int, fileExtension: String? = "m4a") {
        self.fileURL = fileURL
        self.durationMilliseconds = durationMilliseconds
        self.fileExtension = fileExtension
    }
}

/// 输入栏中待发送的媒体附件草稿。
nonisolated enum ChatComposerMedia: Sendable {
    /// 待发送图片数据
    case image(data: Data, preferredFileExtension: String?)
    /// 待发送视频文件
    case video(fileURL: URL, preferredFileExtension: String?)
}

/// 待处理消息重试运行结果
nonisolated struct PendingMessageRetryRunResult: Equatable, Sendable {
    /// 扫描的任务数
    let scannedJobCount: Int
    /// 尝试重试的任务数
    let attemptedCount: Int
    /// 成功的任务数
    let successCount: Int
    /// 重新调度的任务数
    let rescheduledCount: Int
    /// 耗尽重试次数的任务数
    let exhaustedCount: Int
}

/// 群聊上下文
nonisolated struct GroupChatContext: Equatable, Sendable {
    let members: [GroupMember]
    let currentUserRole: GroupMemberRole
    let announcement: GroupAnnouncement?
}

/// 聊天用例协议
protocol ChatServiceHub: Sendable {
    /// 当前用例对应的账号 ID，用于过滤仓储层变更通知。
    var observedUserID: UserID? { get }
    /// 当前用例对应的会话 ID，用于过滤仓储层变更通知。
    var observedConversationID: ConversationID? { get }
    /// 加载首屏消息
    func loadInitialMessages() async throws -> ChatMessagePage
    /// 加载更早的消息
    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage
    /// 观察最新消息窗口。
    func observeLatestMessages(limit: Int) async throws -> DatabaseObservationStream<[ChatMessageRowState]>?
    /// 加载草稿
    func loadDraft() async throws -> String?
    /// 保存草稿
    func saveDraft(_ text: String) async throws
    /// 发送文本消息
    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error>
    /// 发送带 @ 元数据的文本消息
    func sendText(_ text: String, mentionedUserIDs: [UserID], mentionsAll: Bool) -> AsyncThrowingStream<ChatMessageRowState, Error>
    /// 加载群聊上下文；单聊返回 nil
    func loadGroupContext() async throws -> GroupChatContext?
    /// 更新群公告
    func updateGroupAnnouncement(_ text: String) async throws -> GroupAnnouncement?
    /// 发送图片消息
    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error>
    /// 发送语音消息
    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error>
    /// 发送视频消息
    func sendVideo(fileURL: URL, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error>
    /// 发送文件消息
    func sendFile(fileURL: URL) -> AsyncThrowingStream<ChatMessageRowState, Error>
    /// 加载表情面板状态
    func loadEmojiPanelState() async throws -> ChatEmojiPanelState
    /// 收藏或取消收藏表情
    func toggleEmojiFavorite(emojiID: String, isFavorite: Bool) async throws -> ChatEmojiPanelState
    /// 发送表情消息
    func sendEmoji(_ emoji: EmojiAssetRecord) -> AsyncThrowingStream<ChatMessageRowState, Error>
    /// 标记语音已播放
    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState?
    /// 触发当前会话的后台推送对方消息
    func simulateIncomingMessages() async throws -> [ChatMessageRowState]
    /// 重发消息
    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error>
    /// 删除消息
    func delete(messageID: MessageID) async throws
    /// 撤回消息
    func revoke(messageID: MessageID) async throws
}

extension ChatServiceHub {
    var observedUserID: UserID? {
        nil
    }

    var observedConversationID: ConversationID? {
        nil
    }

    func observeLatestMessages(limit: Int) async throws -> DatabaseObservationStream<[ChatMessageRowState]>? {
        nil
    }

    func sendText(_ text: String, mentionedUserIDs: [UserID], mentionsAll: Bool) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sendText(text)
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        Self.emptyRowStream()
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        Self.emptyRowStream()
    }

    func sendVideo(fileURL: URL, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        Self.emptyRowStream()
    }

    func sendFile(fileURL: URL) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        Self.emptyRowStream()
    }

    func loadGroupContext() async throws -> GroupChatContext? {
        nil
    }

    func updateGroupAnnouncement(_ text: String) async throws -> GroupAnnouncement? {
        nil
    }

    func simulateIncomingMessages() async throws -> [ChatMessageRowState] {
        []
    }

    func loadEmojiPanelState() async throws -> ChatEmojiPanelState {
        .empty
    }

    func toggleEmojiFavorite(emojiID: String, isFavorite: Bool) async throws -> ChatEmojiPanelState {
        .empty
    }

    func sendEmoji(_ emoji: EmojiAssetRecord) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        Self.emptyRowStream()
    }

    private static func emptyRowStream() -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

/// 本地聊天用例实现
nonisolated struct LocalChatServiceHub: ChatServiceHub {
    /// 首屏消息加载数量
    private static let initialMessageLimit = 50
    /// 最短语音发送时长
    private static let minimumVoiceDurationMilliseconds = 1_000

    /// 用户 ID
    private let userID: UserID
    /// 会话 ID
    private let conversationID: ConversationID
    /// 当前账号头像 URL
    private let currentUserAvatarURL: String?
    /// 会话头像 URL
    private let conversationAvatarURL: String?
    /// 消息仓储
    private let repository: any MessageRepository
    /// 会话仓储
    private let conversationRepository: (any ConversationRepository)?
    /// 待处理任务仓储
    private let pendingJobRepository: (any PendingJobRepository)?
    /// 表情仓储
    private let emojiRepository: (any EmojiRepository)?
    /// 消息发送服务
    private let sendService: any MessageSendService
    /// 媒体文件存储
    private let mediaFileStore: (any MediaFileStoring)?
    /// 媒体上传服务
    private let mediaUploadService: any MediaUploadService
    /// 重试策略
    private let retryPolicy: MessageRetryPolicy
    /// 统一模拟后台推送服务
    private let simulatedIncomingPushService: (any SimulatedIncomingPushing)?
    /// 消息行映射器
    private let rowMapper: ChatMessageRowMapper
    /// 消息时间线读取协作者
    private let timelineLoader: ChatTimelineLoading
    /// 草稿与文本消息发送协作者
    private let messageSender: ChatMessageSending
    /// 媒体消息发送协作者
    private let mediaMessageSender: ChatMediaMessageSending
    /// 聊天链路耗时日志
    private let logger = AppLogger(category: .chat)

    /// 初始化本地聊天用例
    init(
        userID: UserID,
        conversationID: ConversationID,
        currentUserAvatarURL: String? = nil,
        conversationAvatarURL: String? = nil,
        repository: any MessageRepository,
        conversationRepository: (any ConversationRepository)? = nil,
        pendingJobRepository: (any PendingJobRepository)? = nil,
        emojiRepository: (any EmojiRepository)? = nil,
        sendService: any MessageSendService,
        mediaFileStore: (any MediaFileStoring)? = nil,
        mediaUploadService: any MediaUploadService = MockMediaUploadService(),
        retryPolicy: MessageRetryPolicy = MessageRetryPolicy(),
        simulatedIncomingPushService: (any SimulatedIncomingPushing)? = nil
    ) {
        self.userID = userID
        self.conversationID = conversationID
        self.currentUserAvatarURL = currentUserAvatarURL
        self.conversationAvatarURL = conversationAvatarURL
        self.repository = repository
        self.conversationRepository = conversationRepository
        self.pendingJobRepository = pendingJobRepository
        self.emojiRepository = emojiRepository ?? (repository as? any EmojiRepository)
        self.sendService = sendService
        self.mediaFileStore = mediaFileStore
        self.mediaUploadService = mediaUploadService
        self.retryPolicy = retryPolicy
        let rowMapper = ChatMessageRowMapper(
            userID: userID,
            currentUserAvatarURL: currentUserAvatarURL,
            conversationAvatarURL: conversationAvatarURL
        )
        self.rowMapper = rowMapper
        self.timelineLoader = ChatTimelineLoading(
            userID: userID,
            conversationID: conversationID,
            messageRepository: repository,
            observationRepository: repository as? any MessageObservationRepository,
            conversationRepository: conversationRepository,
            rowMapper: rowMapper
        )
        self.messageSender = ChatMessageSending(
            userID: userID,
            conversationID: conversationID,
            repository: repository,
            conversationRepository: conversationRepository,
            pendingJobRepository: pendingJobRepository,
            recoveryRepository: repository as? any MessageSendRecoveryRepository,
            sendService: sendService,
            retryPolicy: retryPolicy,
            rowMapper: rowMapper
        )
        self.mediaMessageSender = ChatMediaMessageSending(
            userID: userID,
            conversationID: conversationID,
            repository: repository,
            pendingJobRepository: pendingJobRepository,
            mediaFileStore: mediaFileStore,
            mediaUploadService: mediaUploadService,
            sendService: sendService,
            retryPolicy: retryPolicy,
            rowMapper: rowMapper
        )
        if let simulatedIncomingPushService {
            self.simulatedIncomingPushService = simulatedIncomingPushService
        } else if let pushRepository = repository as? any SimulatedIncomingPushRepository {
            self.simulatedIncomingPushService = SimulatedIncomingPushService(userID: userID, repository: pushRepository)
        } else {
            self.simulatedIncomingPushService = nil
        }
    }

    var observedUserID: UserID? {
        userID
    }

    var observedConversationID: ConversationID? {
        conversationID
    }

    /// 加载首屏消息并标记会话已读
    func loadInitialMessages() async throws -> ChatMessagePage {
        try await timelineLoader.loadInitialMessages(limit: Self.initialMessageLimit)
    }

    /// 按游标加载更早消息
    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        try await timelineLoader.loadOlderMessages(beforeSortSequence: beforeSortSequence, limit: limit)
    }

    /// 观察当前会话最新消息窗口。
    func observeLatestMessages(limit: Int) async throws -> DatabaseObservationStream<[ChatMessageRowState]>? {
        try await timelineLoader.observeLatestMessages(limit: limit)
    }

    /// 加载当前会话草稿
    func loadDraft() async throws -> String? {
        try await messageSender.loadDraft()
    }

    /// 保存当前会话草稿
    func saveDraft(_ text: String) async throws {
        try await messageSender.saveDraft(text)
    }

    /// 加载群聊上下文
    func loadGroupContext() async throws -> GroupChatContext? {
        guard let conversationRepository else {
            return nil
        }

        let members = try await conversationRepository.groupMembers(conversationID: conversationID)
        guard !members.isEmpty else {
            return nil
        }

        return GroupChatContext(
            members: members,
            currentUserRole: try await conversationRepository.currentMemberRole(conversationID: conversationID, userID: userID) ?? .member,
            announcement: try await conversationRepository.groupAnnouncement(conversationID: conversationID)
        )
    }

    /// 更新群公告
    func updateGroupAnnouncement(_ text: String) async throws -> GroupAnnouncement? {
        guard let conversationRepository else {
            return nil
        }

        try await conversationRepository.updateGroupAnnouncement(
            conversationID: conversationID,
            userID: userID,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return try await conversationRepository.groupAnnouncement(conversationID: conversationID)
    }

    /// 发送文本消息并流式返回发送状态
    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sendText(text, mentionedUserIDs: [], mentionsAll: false)
    }

    /// 发送文本消息并携带群聊 @ 元数据
    func sendText(_ text: String, mentionedUserIDs: [UserID], mentionsAll: Bool) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        messageSender.sendText(text, mentionedUserIDs: mentionedUserIDs, mentionsAll: mentionsAll)
    }

    /// 发送图片消息并流式返回上传和发送状态
    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        mediaMessageSender.sendImage(data: data, preferredFileExtension: preferredFileExtension)
    }

    /// 发送语音消息并流式返回上传和发送状态
    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        guard recording.durationMilliseconds >= Self.minimumVoiceDurationMilliseconds else {
            return AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }

        return mediaMessageSender.sendVoice(recording: recording)
    }

    /// 发送视频消息并流式返回上传和发送状态
    func sendVideo(fileURL: URL, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        mediaMessageSender.sendVideo(fileURL: fileURL, preferredFileExtension: preferredFileExtension)
    }

    /// 发送文件消息并流式返回上传和发送状态
    func sendFile(fileURL: URL) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        mediaMessageSender.sendFile(fileURL: fileURL)
    }

    private func sendPreparedMediaMessage(
        operation: MediaUploadOperation,
        prepareMessage: @escaping @Sendable () async throws -> StoredMessage?
    ) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let insertedMessage = try await prepareMessage() else {
                        continuation.finish()
                        return
                    }

                    continuation.yield(row(from: insertedMessage, currentUserID: userID))
                    try await uploadAndSendMedia(insertedMessage, operation: operation, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func loadEmojiPanelState() async throws -> ChatEmojiPanelState {
        guard let emojiRepository else {
            return .empty
        }

        return try await emojiPanelState(from: emojiRepository)
    }

    func toggleEmojiFavorite(emojiID: String, isFavorite: Bool) async throws -> ChatEmojiPanelState {
        guard let emojiRepository else {
            return .empty
        }

        let now = Self.currentTimestamp()
        try await emojiRepository.setEmojiFavorite(
            emojiID: emojiID,
            userID: userID,
            isFavorite: isFavorite,
            updatedAt: now
        )
        return try await emojiPanelState(from: emojiRepository)
    }

    func sendEmoji(_ emoji: EmojiAssetRecord) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let now = Self.currentTimestamp()
                    try await repository.clearDraft(conversationID: conversationID, userID: userID)
                    let insertedMessage = try await repository.insertOutgoingEmojiMessage(
                        OutgoingEmojiMessageInput(
                            userID: userID,
                            conversationID: conversationID,
                            senderID: userID,
                            emoji: emoji.storedContent,
                            localTime: now,
                            sortSequence: now
                        )
                    )
                    try await emojiRepository?.recordEmojiUsed(
                        emojiID: emoji.emojiID,
                        userID: userID,
                        usedAt: now
                    )

                    continuation.yield(row(from: insertedMessage, currentUserID: userID))
                    let result = await sendService.sendEmoji(message: insertedMessage)
                    let finalStatus: MessageSendStatus
                    let ack: MessageSendAck?
                    switch result {
                    case let .success(successAck):
                        finalStatus = .success
                        ack = successAck
                    case .failure:
                        finalStatus = .failed
                        ack = nil
                    }
                    try await updateSendStatus(
                        messageID: insertedMessage.id,
                        status: finalStatus,
                        ack: ack,
                        pendingJob: nil
                    )
                    if let updatedMessage = try await repository.message(messageID: insertedMessage.id) {
                        continuation.yield(row(from: updatedMessage, currentUserID: userID))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// 标记语音消息已播放并返回更新后的行状态
    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        guard let existingMessage = try await repository.message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        guard existingMessage.type == .voice else {
            return nil
        }

        try await repository.markVoicePlayed(messageID: messageID)

        guard let updatedMessage = try await repository.message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        return row(from: updatedMessage, currentUserID: userID)
    }

    private func emojiPanelState(from emojiRepository: any EmojiRepository) async throws -> ChatEmojiPanelState {
        let packages = try await emojiRepository.listEmojiPackages(for: userID)
        var packageEmojisByPackageID: [String: [EmojiAssetRecord]] = [:]
        for package in packages {
            packageEmojisByPackageID[package.packageID] = try await emojiRepository.listPackageEmojis(
                for: userID,
                packageID: package.packageID
            )
        }

        return ChatEmojiPanelState(
            packages: packages,
            recentEmojis: try await emojiRepository.listRecentEmojis(for: userID, limit: 24),
            favoriteEmojis: try await emojiRepository.listFavoriteEmojis(for: userID),
            packageEmojisByPackageID: packageEmojisByPackageID
        )
    }

    /// 通过统一后台推送入口向当前会话写入对方消息。
    func simulateIncomingMessages() async throws -> [ChatMessageRowState] {
        guard let pushService = simulatedIncomingPushService else {
            return []
        }

        let startUptime = AppLogger.performanceSpan()
        let request = SimulatedIncomingPushRequest(target: .conversation(conversationID))
        guard let pushResult = try await pushService.simulateIncomingPush(request) else {
            return []
        }

        guard pushResult.conversationID == conversationID else {
            logger.info(
                "Chat peerPush missedCurrentConversation targetID=\(Self.shortLogID(pushResult.conversationID.rawValue)) currentID=\(Self.shortLogID(conversationID.rawValue)) count=\(pushResult.insertedCount) total=\(AppLogger.elapsedMilliseconds(since: startUptime))"
            )
            return []
        }

        if let conversationRepository {
            let logger = logger
            let resultConversationID = pushResult.conversationID
            let resultMessageID = pushResult.messages.last?.messageID
            Task {
                let readStartUptime = AppLogger.performanceSpan()
                do {
                    try await conversationRepository.markConversationRead(conversationID: resultConversationID, userID: userID)
                    logger.info(
                        "Chat peerPush markedRead messageID=\(Self.shortLogID(resultMessageID?.rawValue ?? "nil")) elapsed=\(AppLogger.elapsedMilliseconds(since: readStartUptime))"
                    )
                } catch {
                    logger.error(
                        "Chat peerPush markReadFailed messageID=\(Self.shortLogID(resultMessageID?.rawValue ?? "nil")) error=\(String(describing: type(of: error)))"
                    )
                }
            }
        }

        let rows = pushResult.messages.map { row(from: $0) }
        logger.info(
            "Chat peerPush rowsReturned conversationID=\(Self.shortLogID(conversationID.rawValue)) count=\(rows.count) total=\(AppLogger.elapsedMilliseconds(since: startUptime))"
        )
        return rows
    }

    /// 将模拟同步消息直接转换为聊天行状态，避免落库后再额外回查阻塞 UI。
    nonisolated private func row(from message: IncomingSyncMessage) -> ChatMessageRowState {
        ChatMessageRowState(
            id: message.messageID,
            content: .text(message.text),
            sortSequence: message.sequence,
            sentAt: message.serverTime,
            timeText: Self.timeText(from: message.serverTime),
            statusText: nil,
            uploadProgress: nil,
            senderAvatarURL: conversationAvatarURL,
            isOutgoing: message.senderID == userID,
            canRetry: false,
            canDelete: true,
            canRevoke: false
        )
    }

    /// 重发失败消息并流式返回重发状态
    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let existingMessage = try await repository.message(messageID: messageID) else {
                        throw ChatStoreError.messageNotFound(messageID)
                    }

                    if existingMessage.type == .image {
                        let sendingMessage = try await repository.resendImageMessage(messageID: messageID)
                        continuation.yield(row(from: sendingMessage, currentUserID: userID))
                        try await uploadAndSendMedia(sendingMessage, operation: .image, continuation: continuation)
                        continuation.finish()
                        return
                    }

                    if existingMessage.type == .video {
                        let sendingMessage = try await repository.resendVideoMessage(messageID: messageID)
                        continuation.yield(row(from: sendingMessage, currentUserID: userID))
                        try await uploadAndSendMedia(sendingMessage, operation: .video, continuation: continuation)
                        continuation.finish()
                        return
                    }

                    if existingMessage.type == .file {
                        let sendingMessage = try await repository.resendFileMessage(messageID: messageID)
                        continuation.yield(row(from: sendingMessage, currentUserID: userID))
                        try await uploadAndSendMedia(sendingMessage, operation: .file, continuation: continuation)
                        continuation.finish()
                        return
                    }

                    let sendingMessage = try await repository.resendTextMessage(messageID: messageID)
                    continuation.yield(row(from: sendingMessage, currentUserID: userID))

                    let result = await sendService.sendText(message: sendingMessage)
                    let finalStatus: MessageSendStatus
                    let ack: MessageSendAck?

                    switch result {
                    case let .success(successAck):
                        finalStatus = .success
                        ack = successAck
                        try await markResendJobSuccess(for: sendingMessage)
                    case .failure:
                        finalStatus = .failed
                        ack = nil
                    }

                    try await updateSendStatus(
                        messageID: sendingMessage.id,
                        status: finalStatus,
                        ack: ack,
                        pendingJob: finalStatus == .failed ? try makeResendJobInput(for: sendingMessage, failureReason: result.failureReason) : nil
                    )

                    if let updatedMessage = try await repository.message(messageID: sendingMessage.id) {
                        continuation.yield(row(from: updatedMessage, currentUserID: userID))
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// 删除消息
    func delete(messageID: MessageID) async throws {
        try await repository.markMessageDeleted(messageID: messageID, userID: userID)
    }

    /// 撤回消息
    func revoke(messageID: MessageID) async throws {
        _ = try await repository.revokeMessage(
            messageID: messageID,
            userID: userID,
            replacementText: "你撤回了一条消息"
        )
    }

    /// 更新消息发送状态并按需写入恢复任务
    private func updateSendStatus(
        messageID: MessageID,
        status: MessageSendStatus,
        ack: MessageSendAck?,
        pendingJob: PendingJobInput?
    ) async throws {
        if let recoveryRepository = repository as? any MessageSendRecoveryRepository {
            try await recoveryRepository.updateMessageSendStatus(
                messageID: messageID,
                status: status,
                ack: ack,
                pendingJob: pendingJob
            )
        } else {
            try await repository.updateMessageSendStatus(messageID: messageID, status: status, ack: ack)

            if let pendingJob, let pendingJobRepository {
                _ = try await pendingJobRepository.upsertPendingJob(pendingJob)
            }
        }
    }

    /// 创建重发任务输入参数
    ///
    /// - Parameters:
    ///   - message: 消息对象
    ///   - reason: 失败原因
    ///   - retryCount: 重试次数
    /// - Returns: 待处理任务输入参数
    private func makeResendJobInput(
        for message: StoredMessage,
        failureReason: MessageSendFailureReason?
    ) throws -> PendingJobInput? {
        guard pendingJobRepository != nil, let clientMessageID = message.delivery.clientMessageID else {
            return nil
        }

        return try PendingMessageJobFactory.messageResendInput(
            messageID: message.id,
            conversationID: message.conversationID,
            clientMessageID: clientMessageID,
            userID: userID,
            failureReason: failureReason,
            maxRetryCount: retryPolicy.maxRetryCount,
            nextRetryAt: retryPolicy.nextRetryAt(now: Self.currentTimestamp(), retryCount: 0)
        )
    }

    /// 标记重发任务成功
    ///
    /// - Parameter message: 消息对象
    private func markResendJobSuccess(for message: StoredMessage) async throws {
        guard let pendingJobRepository, let clientMessageID = message.delivery.clientMessageID else {
            return
        }

        try await pendingJobRepository.updatePendingJobStatus(
            jobID: PendingMessageJobFactory.messageResendJobID(clientMessageID: clientMessageID),
            status: .success,
            nextRetryAt: nil
        )
    }

    /// 上传媒体并发送消息体。
    private func uploadAndSendMedia(
        _ message: StoredMessage,
        operation: MediaUploadOperation,
        continuation: AsyncThrowingStream<ChatMessageRowState, Error>.Continuation
    ) async throws {
        try await operation.updateStatus(
            repository: repository,
            messageID: message.id,
            uploadStatus: .uploading,
            uploadAck: nil,
            sendStatus: .sending,
            sendAck: nil,
            pendingJob: nil
        )

        for await event in operation.upload(using: mediaUploadService, message: message) {
            switch event {
            case let .progress(progress):
                continuation.yield(row(from: message, currentUserID: userID, uploadProgress: progress))
            case let .completed(uploadAck):
                let result = await operation.send(using: sendService, message: message, upload: uploadAck)
                let finalStatus: MessageSendStatus
                let uploadStatus: MediaUploadStatus
                let sendAck: MessageSendAck?

                switch result {
                case let .success(ack):
                    finalStatus = .success
                    uploadStatus = .success
                    sendAck = ack
                    try await operation.markUploadJobSuccess(for: message, repository: pendingJobRepository)
                case .failure:
                    finalStatus = .failed
                    uploadStatus = .failed
                    sendAck = nil
                }

                try await operation.updateStatus(
                    repository: repository,
                    messageID: message.id,
                    uploadStatus: uploadStatus,
                    uploadAck: uploadAck,
                    sendStatus: finalStatus,
                    sendAck: sendAck,
                    pendingJob: finalStatus == .failed ? try operation.makeUploadJobInput(
                        for: message,
                        userID: userID,
                        repository: pendingJobRepository,
                        retryPolicy: retryPolicy,
                        failureReason: result.failureReason?.rawValue,
                        now: Self.currentTimestamp()
                    ) : nil
                )

                try await yieldStoredMessage(messageID: message.id, to: continuation)
                return
            case let .failed(reason):
                try await operation.updateStatus(
                    repository: repository,
                    messageID: message.id,
                    uploadStatus: .failed,
                    uploadAck: nil,
                    sendStatus: .failed,
                    sendAck: nil,
                    pendingJob: try operation.makeUploadJobInput(
                        for: message,
                        userID: userID,
                        repository: pendingJobRepository,
                        retryPolicy: retryPolicy,
                        failureReason: reason.rawValue,
                        now: Self.currentTimestamp()
                    )
                )

                try await yieldStoredMessage(messageID: message.id, to: continuation)
                return
            }
        }

        guard operation.marksEmptyUploadStreamAsFailure else { return }
        try await operation.updateStatus(
            repository: repository,
            messageID: message.id,
            uploadStatus: .failed,
            uploadAck: nil,
            sendStatus: .failed,
            sendAck: nil,
            pendingJob: try operation.makeUploadJobInput(
                for: message,
                userID: userID,
                repository: pendingJobRepository,
                retryPolicy: retryPolicy,
                failureReason: MediaUploadFailureReason.unknown.rawValue,
                now: Self.currentTimestamp()
            )
        )
        try await yieldStoredMessage(messageID: message.id, to: continuation)
    }

    private func yieldStoredMessage(
        messageID: MessageID,
        to continuation: AsyncThrowingStream<ChatMessageRowState, Error>.Continuation
    ) async throws {
        if let updatedMessage = try await repository.message(messageID: messageID) {
            continuation.yield(row(from: updatedMessage, currentUserID: userID))
        }
    }

    /// 当前秒级时间戳
    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }

    /// 已发送消息的可撤回窗口，单位为秒。
    nonisolated private static let revokeWindowSeconds: Int64 = 180

    /// 日志中使用的短 ID，避免输出过长的消息标识。
    nonisolated private static func shortLogID(_ rawValue: String) -> String {
        String(rawValue.prefix(8))
    }

    /// 将存储消息转换为聊天行状态
    nonisolated private func row(
        from message: StoredMessage,
        currentUserID: UserID,
        uploadProgress: Double? = nil
    ) -> ChatMessageRowState {
        let isOutgoing = message.senderID == currentUserID
        let isRevoked = message.state.isRevoked
        let senderAvatarURL = isOutgoing ? currentUserAvatarURL : conversationAvatarURL
        let now = Self.currentTimestamp()

        return ChatMessageRowState(
            id: message.id,
            content: Self.rowContent(
                for: message,
                isOutgoing: isOutgoing,
                isRevoked: isRevoked
            ),
            sortSequence: message.timeline.sortSequence,
            sentAt: message.timeline.localTime,
            timeText: Self.timeText(from: message.timeline.localTime),
            statusText: isRevoked ? nil : Self.statusText(for: message),
            uploadProgress: uploadProgress,
            senderAvatarURL: senderAvatarURL,
            isOutgoing: isOutgoing,
            canRetry: isOutgoing
                && (message.type == .text || message.type == .image || message.type == .video || message.type == .emoji)
                && message.state.sendStatus == .failed
                && !isRevoked,
            canDelete: !message.state.isDeleted,
            canRevoke: Self.canRevoke(
                message,
                isOutgoing: isOutgoing,
                isRevoked: isRevoked,
                now: now
            )
        )
    }

    /// 判断消息是否仍处于可撤回窗口。
    nonisolated private static func canRevoke(
        _ message: StoredMessage,
        isOutgoing: Bool,
        isRevoked: Bool,
        now: Int64
    ) -> Bool {
        guard isOutgoing,
              message.state.sendStatus == .success,
              !isRevoked,
              !message.state.isDeleted,
              isRevocableMessageType(message.type) else {
            return false
        }

        return now - message.timeline.localTime <= revokeWindowSeconds
    }

    /// 用户主动发送的业务消息类型支持撤回。
    nonisolated private static func isRevocableMessageType(_ type: MessageType) -> Bool {
        switch type {
        case .text, .image, .voice, .video, .file, .emoji:
            return true
        case .system, .revoked, .quote:
            return false
        }
    }

    /// 生成消息内容状态
    nonisolated private static func rowContent(
        for message: StoredMessage,
        isOutgoing: Bool,
        isRevoked: Bool
    ) -> ChatMessageRowContent {
        if isRevoked {
            let editableText = message.state.revokeEditableText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let allowsReedit = isOutgoing
                && message.type == .text
                && message.state.sendStatus == .success
                && editableText?.isEmpty == false
            return .revoked(
                ChatMessageRowContent.RevokedContent(
                    noticeText: message.state.revokeReplacementText ?? "你撤回了一条消息",
                    editableText: allowsReedit ? message.state.revokeEditableText : nil,
                    allowsReedit: allowsReedit
                )
            )
        }

        switch message.content {
        case let .image(image):
            return .image(
                ChatMessageRowContent.ImageContent(
                    thumbnailPath: image.thumbnailPath
                )
            )
        case let .voice(voice):
            return .voice(
                ChatMessageRowContent.VoiceContent(
                    localPath: voice.localPath,
                    durationMilliseconds: voice.durationMilliseconds,
                    isUnplayed: !isOutgoing && message.state.readStatus == .unread,
                    isPlaying: false
                )
            )
        case let .video(video):
            return .video(
                ChatMessageRowContent.VideoContent(
                    thumbnailPath: video.thumbnailPath,
                    localPath: video.localPath,
                    durationMilliseconds: video.durationMilliseconds
                )
            )
        case let .file(file):
            return .file(
                ChatMessageRowContent.FileContent(
                    fileName: file.fileName,
                    fileExtension: file.fileExtension,
                    localPath: file.localPath,
                    sizeBytes: file.sizeBytes
                )
            )
        case let .emoji(emoji):
            return .emoji(
                ChatMessageRowContent.EmojiContent(
                    emojiID: emoji.emojiID,
                    name: emoji.name,
                    localPath: emoji.localPath,
                    thumbPath: emoji.thumbPath,
                    cdnURL: emoji.cdnURL
                )
            )
        case let .text(text):
            return .text(text)
        case let .system(text), let .quote(text), let .revoked(text):
            return .text(text ?? "")
        }
    }

    /// 生成发出消息状态文本
    nonisolated private static func statusText(for message: StoredMessage) -> String? {
        guard message.state.direction == .outgoing else {
            return nil
        }

        switch message.state.sendStatus {
        case .pending:
            return "Pending"
        case .sending:
            return "Sending"
        case .success:
            return nil
        case .failed:
            return "Failed"
        }
    }

    /// 格式化消息时间
    nonisolated private static func timeText(from timestamp: Int64) -> String {
        ChatBridgeTimeFormatter.messageTimeText(from: timestamp)
    }
}

/// 待处理消息任务重试运行器
nonisolated struct PendingMessageRetryRunner: Sendable {
    /// 用户 ID
    private let userID: UserID
    /// 消息仓储
    private let messageRepository: any MessageRepository
    /// 待处理任务仓储
    private let pendingJobRepository: any PendingJobRepository
    /// 消息发送服务
    private let sendService: any MessageSendService
    /// 媒体上传服务
    private let mediaUploadService: any MediaUploadService
    /// 重试策略
    private let retryPolicy: MessageRetryPolicy

    /// 初始化待处理任务重试运行器
    init(
        userID: UserID,
        messageRepository: any MessageRepository,
        pendingJobRepository: any PendingJobRepository,
        sendService: any MessageSendService,
        mediaUploadService: any MediaUploadService = MockMediaUploadService(),
        retryPolicy: MessageRetryPolicy = MessageRetryPolicy()
    ) {
        self.userID = userID
        self.messageRepository = messageRepository
        self.pendingJobRepository = pendingJobRepository
        self.sendService = sendService
        self.mediaUploadService = mediaUploadService
        self.retryPolicy = retryPolicy
    }

    /// 运行到期的待处理任务
    ///
    /// 扫描所有到期的重发任务并尝试重试
    ///
    /// - Parameter now: 当前时间戳
    /// - Returns: 运行结果统计
    func runDueJobs(now: Int64 = Int64(Date().timeIntervalSince1970)) async throws -> PendingMessageRetryRunResult {
        let jobs = try await pendingJobRepository.recoverablePendingJobs(userID: userID, now: now)
        var attemptedCount = 0
        var successCount = 0
        var rescheduledCount = 0
        var exhaustedCount = 0

        for job in jobs {
            guard job.retryCount < job.maxRetryCount else {
                exhaustedCount += 1
                try await pendingJobRepository.updatePendingJobStatus(jobID: job.id, status: .failed, nextRetryAt: nil)
                continue
            }

            switch job.type {
            case .messageResend:
                let result = try await runMessageResendJob(job, now: now)
                attemptedCount += result.attempted ? 1 : 0
                successCount += result.succeeded ? 1 : 0
                rescheduledCount += result.rescheduled ? 1 : 0
                exhaustedCount += result.exhausted ? 1 : 0
            case .imageUpload, .videoUpload, .fileUpload:
                guard let operation = MediaUploadOperation(jobType: job.type) else {
                    continue
                }
                let result = try await runMediaUploadJob(job, operation: operation, now: now)
                attemptedCount += result.attempted ? 1 : 0
                successCount += result.succeeded ? 1 : 0
                rescheduledCount += result.rescheduled ? 1 : 0
                exhaustedCount += result.exhausted ? 1 : 0
            default:
                continue
            }
        }

        return PendingMessageRetryRunResult(
            scannedJobCount: jobs.count,
            attemptedCount: attemptedCount,
            successCount: successCount,
            rescheduledCount: rescheduledCount,
            exhaustedCount: exhaustedCount
        )
    }

    /// 执行文本消息重发任务
    private func runMessageResendJob(_ job: PendingJob, now: Int64 = Int64(Date().timeIntervalSince1970)) async throws -> PendingJobAttemptResult {
        guard case let .messageResend(payload) = try job.decodedPayload() else {
            throw ChatStoreError.missingColumn("pending_job_payload")
        }
        let messageID = MessageID(rawValue: payload.messageID)

        guard let message = try await messageRepository.message(messageID: messageID) else {
            try await pendingJobRepository.updatePendingJobStatus(jobID: job.id, status: .cancelled, nextRetryAt: nil)
            return PendingJobAttemptResult(attempted: false, succeeded: false, rescheduled: false, exhausted: true)
        }

        try await pendingJobRepository.updatePendingJobStatus(jobID: job.id, status: .running, nextRetryAt: nil)
        try await messageRepository.updateMessageSendStatus(messageID: messageID, status: .sending, ack: nil)

        let result = await sendService.sendText(message: message)
        switch result {
        case let .success(ack):
            try await messageRepository.updateMessageSendStatus(messageID: messageID, status: .success, ack: ack)
            try await pendingJobRepository.updatePendingJobStatus(jobID: job.id, status: .success, nextRetryAt: nil)
            return PendingJobAttemptResult(attempted: true, succeeded: true, rescheduled: false, exhausted: false)
        case .failure:
            try await messageRepository.updateMessageSendStatus(messageID: messageID, status: .failed, ack: nil)
            return try await retryOrExhaust(job, now: now)
        }
    }

    /// 执行媒体上传恢复任务
    private func runMediaUploadJob(
        _ job: PendingJob,
        operation: MediaUploadOperation,
        now: Int64 = Int64(Date().timeIntervalSince1970)
    ) async throws -> PendingJobAttemptResult {
        guard case let .mediaUpload(payload) = try job.decodedPayload() else {
            throw ChatStoreError.missingColumn("pending_job_payload")
        }
        let messageID = MessageID(rawValue: payload.messageID)

        guard let message = try await messageRepository.message(messageID: messageID) else {
            try await pendingJobRepository.updatePendingJobStatus(jobID: job.id, status: .cancelled, nextRetryAt: nil)
            return PendingJobAttemptResult(attempted: false, succeeded: false, rescheduled: false, exhausted: true)
        }

        try await pendingJobRepository.updatePendingJobStatus(jobID: job.id, status: .running, nextRetryAt: nil)
        try await operation.updateStatus(
            repository: messageRepository,
            messageID: messageID,
            uploadStatus: .uploading,
            uploadAck: nil,
            sendStatus: .sending,
            sendAck: nil,
            pendingJob: nil
        )

        for await event in operation.upload(using: mediaUploadService, message: message) {
            switch event {
            case .progress:
                continue
            case let .completed(uploadAck):
                let result = await operation.send(using: sendService, message: message, upload: uploadAck)

                switch result {
                case let .success(sendAck):
                    try await operation.updateStatus(
                        repository: messageRepository,
                        messageID: messageID,
                        uploadStatus: .success,
                        uploadAck: uploadAck,
                        sendStatus: .success,
                        sendAck: sendAck,
                        pendingJob: nil
                    )
                    try await pendingJobRepository.updatePendingJobStatus(jobID: job.id, status: .success, nextRetryAt: nil)
                    return PendingJobAttemptResult(attempted: true, succeeded: true, rescheduled: false, exhausted: false)
                case .failure:
                    try await operation.updateStatus(
                        repository: messageRepository,
                        messageID: messageID,
                        uploadStatus: .failed,
                        uploadAck: uploadAck,
                        sendStatus: .failed,
                        sendAck: nil,
                        pendingJob: nil
                    )
                    return try await retryOrExhaust(job, now: now)
                }
            case .failed:
                try await operation.updateStatus(
                    repository: messageRepository,
                    messageID: messageID,
                    uploadStatus: .failed,
                    uploadAck: nil,
                    sendStatus: .failed,
                    sendAck: nil,
                    pendingJob: nil
                )
                return try await retryOrExhaust(job, now: now)
            }
        }

        try await operation.updateStatus(
            repository: messageRepository,
            messageID: messageID,
            uploadStatus: .failed,
            uploadAck: nil,
            sendStatus: .failed,
            sendAck: nil,
            pendingJob: nil
        )
        return try await retryOrExhaust(job, now: now)
    }

    /// 根据重试次数重新调度或标记耗尽
    private func retryOrExhaust(_ job: PendingJob, now: Int64) async throws -> PendingJobAttemptResult {
        if job.retryCount + 1 >= job.maxRetryCount {
            try await pendingJobRepository.updatePendingJobStatus(jobID: job.id, status: .failed, nextRetryAt: nil)
            return PendingJobAttemptResult(attempted: true, succeeded: false, rescheduled: false, exhausted: true)
        }

        let nextRetryAt = retryPolicy.nextRetryAt(now: now, retryCount: job.retryCount + 1)
        try await pendingJobRepository.schedulePendingJobRetry(jobID: job.id, nextRetryAt: nextRetryAt)
        return PendingJobAttemptResult(attempted: true, succeeded: false, rescheduled: true, exhausted: false)
    }
}

/// 单个待处理任务尝试结果
nonisolated private struct PendingJobAttemptResult: Equatable, Sendable {
    /// 是否实际发起尝试
    let attempted: Bool
    /// 是否重试成功
    let succeeded: Bool
    /// 是否已重新调度
    let rescheduled: Bool
    /// 是否已耗尽重试次数
    let exhausted: Bool
}

/// 媒体上传操作类型，集中描述不同媒体的上传、发送和状态更新差异。
nonisolated enum MediaUploadOperation: Sendable {
    case image
    case voice
    case video
    case file

    init?(jobType: PendingJobType) {
        switch jobType {
        case .imageUpload:
            self = .image
        case .videoUpload:
            self = .video
        case .fileUpload:
            self = .file
        default:
            return nil
        }
    }

    var marksEmptyUploadStreamAsFailure: Bool {
        switch self {
        case .image, .voice:
            return true
        case .video, .file:
            return false
        }
    }

    func upload(using service: any MediaUploadService, message: StoredMessage) -> AsyncStream<MediaUploadEvent> {
        switch self {
        case .image:
            return service.uploadImage(message: message)
        case .voice:
            return service.uploadVoice(message: message)
        case .video:
            return service.uploadVideo(message: message)
        case .file:
            return service.uploadFile(message: message)
        }
    }

    func send(
        using service: any MessageSendService,
        message: StoredMessage,
        upload: MediaUploadAck
    ) async -> MessageSendResult {
        switch self {
        case .image:
            return await service.sendImage(message: message, upload: upload)
        case .voice:
            return await service.sendVoice(message: message, upload: upload)
        case .video:
            return await service.sendVideo(message: message, upload: upload)
        case .file:
            return await service.sendFile(message: message, upload: upload)
        }
    }

    func updateStatus(
        repository: any MessageRepository,
        messageID: MessageID,
        uploadStatus: MediaUploadStatus,
        uploadAck: MediaUploadAck?,
        sendStatus: MessageSendStatus,
        sendAck: MessageSendAck?,
        pendingJob: PendingJobInput?
    ) async throws {
        switch self {
        case .image:
            try await repository.updateImageUploadStatus(
                messageID: messageID,
                uploadStatus: uploadStatus,
                uploadAck: uploadAck,
                sendStatus: sendStatus,
                sendAck: sendAck,
                pendingJob: pendingJob
            )
        case .voice:
            try await repository.updateVoiceUploadStatus(
                messageID: messageID,
                uploadStatus: uploadStatus,
                uploadAck: uploadAck,
                sendStatus: sendStatus,
                sendAck: sendAck
            )
        case .video:
            try await repository.updateVideoUploadStatus(
                messageID: messageID,
                uploadStatus: uploadStatus,
                uploadAck: uploadAck,
                sendStatus: sendStatus,
                sendAck: sendAck,
                pendingJob: pendingJob
            )
        case .file:
            try await repository.updateFileUploadStatus(
                messageID: messageID,
                uploadStatus: uploadStatus,
                uploadAck: uploadAck,
                sendStatus: sendStatus,
                sendAck: sendAck,
                pendingJob: pendingJob
            )
        }
    }

    func makeUploadJobInput(
        for message: StoredMessage,
        userID: UserID,
        repository: (any PendingJobRepository)?,
        retryPolicy: MessageRetryPolicy,
        failureReason: String?,
        now: Int64
    ) throws -> PendingJobInput? {
        guard
            repository != nil,
            let clientMessageID = message.delivery.clientMessageID,
            let mediaID = mediaID(from: message)
        else {
            return nil
        }

        let nextRetryAt = retryPolicy.nextRetryAt(now: now, retryCount: 0)
        switch self {
        case .image:
            return try PendingMessageJobFactory.imageUploadInput(
                messageID: message.id,
                conversationID: message.conversationID,
                clientMessageID: clientMessageID,
                mediaID: mediaID,
                userID: userID,
                failureReason: failureReason,
                maxRetryCount: retryPolicy.maxRetryCount,
                nextRetryAt: nextRetryAt
            )
        case .video:
            return try PendingMessageJobFactory.videoUploadInput(
                messageID: message.id,
                conversationID: message.conversationID,
                clientMessageID: clientMessageID,
                mediaID: mediaID,
                userID: userID,
                failureReason: failureReason,
                maxRetryCount: retryPolicy.maxRetryCount,
                nextRetryAt: nextRetryAt
            )
        case .file:
            return try PendingMessageJobFactory.fileUploadInput(
                messageID: message.id,
                conversationID: message.conversationID,
                clientMessageID: clientMessageID,
                mediaID: mediaID,
                userID: userID,
                failureReason: failureReason,
                maxRetryCount: retryPolicy.maxRetryCount,
                nextRetryAt: nextRetryAt
            )
        case .voice:
            return nil
        }
    }

    func markUploadJobSuccess(
        for message: StoredMessage,
        repository: (any PendingJobRepository)?
    ) async throws {
        guard let repository, let clientMessageID = message.delivery.clientMessageID else {
            return
        }

        guard let jobID = jobID(clientMessageID: clientMessageID) else {
            return
        }

        try await repository.updatePendingJobStatus(jobID: jobID, status: .success, nextRetryAt: nil)
    }

    private func mediaID(from message: StoredMessage) -> String? {
        switch (self, message.content) {
        case let (.image, .image(image)):
            return image.mediaID
        case let (.video, .video(video)):
            return video.mediaID
        case let (.file, .file(file)):
            return file.mediaID
        default:
            return nil
        }
    }

    private func jobID(clientMessageID: String) -> String? {
        switch self {
        case .image:
            return PendingMessageJobFactory.imageUploadJobID(clientMessageID: clientMessageID)
        case .video:
            return PendingMessageJobFactory.videoUploadJobID(clientMessageID: clientMessageID)
        case .file:
            return PendingMessageJobFactory.fileUploadJobID(clientMessageID: clientMessageID)
        case .voice:
            return nil
        }
    }
}

/// MessageSendResult 扩展
private extension MessageSendResult {
    /// 发送失败原因
    var failureReason: MessageSendFailureReason? {
        guard case let .failure(reason) = self else {
            return nil
        }

        return reason
    }
}

/// 基于 ChatStoreProvider 的聊天用例代理
nonisolated struct StoreBackedChatServiceHub: ChatServiceHub {
    /// 用户 ID
    private let userID: UserID
    /// 会话 ID
    private let conversationID: ConversationID
    /// 当前账号头像 URL
    private let currentUserAvatarURL: String?
    /// 会话头像 URL
    private let conversationAvatarURL: String?
    /// 聊天存储 Provider
    private let storeProvider: ChatStoreProvider
    /// 消息发送服务
    private let sendService: any MessageSendService
    /// 媒体文件存储
    private let mediaFileStore: any MediaFileStoring
    /// 媒体上传服务
    private let mediaUploadService: any MediaUploadService
    /// 统一模拟后台推送服务
    private let simulatedIncomingPushService: any SimulatedIncomingPushing
    /// 本地用例缓存 Provider，避免每次调用重复构造完整依赖图。
    private let localUseCaseProvider: StoreBackedLocalChatServiceProvider

    var observedUserID: UserID? {
        userID
    }

    var observedConversationID: ConversationID? {
        conversationID
    }

    /// 初始化基于存储 Provider 的聊天用例
    init(
        userID: UserID,
        conversationID: ConversationID,
        currentUserAvatarURL: String? = nil,
        conversationAvatarURL: String? = nil,
        storeProvider: ChatStoreProvider,
        sendService: any MessageSendService,
        mediaFileStore: any MediaFileStoring,
        mediaUploadService: any MediaUploadService = MockMediaUploadService(),
        simulatedIncomingPushService: (any SimulatedIncomingPushing)? = nil
    ) {
        let resolvedSimulatedIncomingPushService = simulatedIncomingPushService
            ?? SimulatedIncomingPushService(userID: userID, storeProvider: storeProvider)
        self.userID = userID
        self.conversationID = conversationID
        self.currentUserAvatarURL = currentUserAvatarURL
        self.conversationAvatarURL = conversationAvatarURL
        self.storeProvider = storeProvider
        self.sendService = sendService
        self.mediaFileStore = mediaFileStore
        self.mediaUploadService = mediaUploadService
        self.simulatedIncomingPushService = resolvedSimulatedIncomingPushService
        self.localUseCaseProvider = StoreBackedLocalChatServiceProvider(
            userID: userID,
            conversationID: conversationID,
            currentUserAvatarURL: currentUserAvatarURL,
            conversationAvatarURL: conversationAvatarURL,
            sendService: sendService,
            mediaFileStore: mediaFileStore,
            mediaUploadService: mediaUploadService,
            simulatedIncomingPushService: resolvedSimulatedIncomingPushService
        )
    }

    /// 加载首屏消息
    func loadInitialMessages() async throws -> ChatMessagePage {
        try await withLocalUseCase { useCase in
            try await useCase.loadInitialMessages()
        }
    }

    /// 按游标加载更早消息
    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        try await withLocalUseCase { useCase in
            try await useCase.loadOlderMessages(beforeSortSequence: beforeSortSequence, limit: limit)
        }
    }

    /// 观察当前会话最新消息窗口。
    func observeLatestMessages(limit: Int) async throws -> DatabaseObservationStream<[ChatMessageRowState]>? {
        try await withLocalUseCase { useCase in
            try await useCase.observeLatestMessages(limit: limit)
        }
    }

    /// 加载当前会话草稿
    func loadDraft() async throws -> String? {
        try await withLocalUseCase { useCase in
            try await useCase.loadDraft()
        }
    }

    /// 保存当前会话草稿
    func saveDraft(_ text: String) async throws {
        try await withLocalUseCase { useCase in
            try await useCase.saveDraft(text)
        }
    }

    /// 发送文本消息并透传本地用例的状态流
    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sendText(text, mentionedUserIDs: [], mentionsAll: false)
    }

    /// 发送带 @ 元数据的文本消息并透传本地用例的状态流
    func sendText(_ text: String, mentionedUserIDs: [UserID], mentionsAll: Bool) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        localUseCaseStream { useCase in
            useCase.sendText(text, mentionedUserIDs: mentionedUserIDs, mentionsAll: mentionsAll)
        }
    }

    /// 加载群聊上下文
    func loadGroupContext() async throws -> GroupChatContext? {
        try await withLocalUseCase { useCase in
            try await useCase.loadGroupContext()
        }
    }

    /// 更新群公告
    func updateGroupAnnouncement(_ text: String) async throws -> GroupAnnouncement? {
        try await withLocalUseCase { useCase in
            try await useCase.updateGroupAnnouncement(text)
        }
    }

    /// 发送图片消息并透传本地用例的状态流
    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        localUseCaseStream { useCase in
            useCase.sendImage(data: data, preferredFileExtension: preferredFileExtension)
        }
    }

    /// 发送语音消息并透传本地用例的状态流
    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        localUseCaseStream { useCase in
            useCase.sendVoice(recording: recording)
        }
    }

    /// 发送视频消息并透传本地用例的状态流
    func sendVideo(fileURL: URL, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        localUseCaseStream { useCase in
            useCase.sendVideo(fileURL: fileURL, preferredFileExtension: preferredFileExtension)
        }
    }

    /// 发送文件消息并透传本地用例的状态流
    func sendFile(fileURL: URL) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        localUseCaseStream { useCase in
            useCase.sendFile(fileURL: fileURL)
        }
    }

    func loadEmojiPanelState() async throws -> ChatEmojiPanelState {
        try await withLocalUseCase { useCase in
            try await useCase.loadEmojiPanelState()
        }
    }

    func toggleEmojiFavorite(emojiID: String, isFavorite: Bool) async throws -> ChatEmojiPanelState {
        try await withLocalUseCase { useCase in
            try await useCase.toggleEmojiFavorite(emojiID: emojiID, isFavorite: isFavorite)
        }
    }

    func sendEmoji(_ emoji: EmojiAssetRecord) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        localUseCaseStream { useCase in
            useCase.sendEmoji(emoji)
        }
    }

    /// 标记语音消息已播放
    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        try await withLocalUseCase { useCase in
            try await useCase.markVoicePlayed(messageID: messageID)
        }
    }

    /// 触发当前会话的后台推送对方消息。
    func simulateIncomingMessages() async throws -> [ChatMessageRowState] {
        try await withLocalUseCase { useCase in
            try await useCase.simulateIncomingMessages()
        }
    }

    /// 重发失败消息并透传本地用例的状态流
    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        localUseCaseStream { useCase in
            useCase.resend(messageID: messageID)
        }
    }

    /// 删除消息
    func delete(messageID: MessageID) async throws {
        try await withLocalUseCase { useCase in
            try await useCase.delete(messageID: messageID)
        }
    }

    /// 撤回消息
    func revoke(messageID: MessageID) async throws {
        try await withLocalUseCase { useCase in
            try await useCase.revoke(messageID: messageID)
        }
    }

    /// 对最新 repository 解析出的本地用例执行一次异步操作。
    private func withLocalUseCase<Result>(
        _ operation: (LocalChatServiceHub) async throws -> Result
    ) async throws -> Result {
        let useCase = try await localUseCaseProvider.localUseCase(storeProvider: storeProvider)
        return try await operation(useCase)
    }

    /// 透传本地用例产生的消息状态流，同时保留取消语义。
    private func localUseCaseStream(
        _ makeStream: @escaping @MainActor @Sendable (LocalChatServiceHub) -> AsyncThrowingStream<ChatMessageRowState, Error>
    ) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let useCase = try await withLocalUseCase { useCase in
                        useCase
                    }

                    let stream = await makeStream(useCase)
                    for try await row in stream {
                        continuation.yield(row)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

}

/// 为 StoreBackedChatServiceHub 缓存本地聊天用例。
private actor StoreBackedLocalChatServiceProvider {
    private let userID: UserID
    private let conversationID: ConversationID
    private let currentUserAvatarURL: String?
    private let conversationAvatarURL: String?
    private let sendService: any MessageSendService
    private let mediaFileStore: any MediaFileStoring
    private let mediaUploadService: any MediaUploadService
    private let simulatedIncomingPushService: any SimulatedIncomingPushing
    private var cachedUseCase: LocalChatServiceHub?

    init(
        userID: UserID,
        conversationID: ConversationID,
        currentUserAvatarURL: String?,
        conversationAvatarURL: String?,
        sendService: any MessageSendService,
        mediaFileStore: any MediaFileStoring,
        mediaUploadService: any MediaUploadService,
        simulatedIncomingPushService: any SimulatedIncomingPushing
    ) {
        self.userID = userID
        self.conversationID = conversationID
        self.currentUserAvatarURL = currentUserAvatarURL
        self.conversationAvatarURL = conversationAvatarURL
        self.sendService = sendService
        self.mediaFileStore = mediaFileStore
        self.mediaUploadService = mediaUploadService
        self.simulatedIncomingPushService = simulatedIncomingPushService
    }

    func localUseCase(storeProvider: ChatStoreProvider) async throws -> LocalChatServiceHub {
        if let cachedUseCase {
            return cachedUseCase
        }

        let accountStore = try await storeProvider.accountStore()
        let useCase = LocalChatServiceHub(
            userID: userID,
            conversationID: conversationID,
            currentUserAvatarURL: currentUserAvatarURL,
            conversationAvatarURL: conversationAvatarURL,
            repository: accountStore.messages,
            conversationRepository: accountStore.conversations,
            pendingJobRepository: accountStore.pendingJobs,
            emojiRepository: accountStore.emojis,
            sendService: sendService,
            mediaFileStore: mediaFileStore,
            mediaUploadService: mediaUploadService,
            simulatedIncomingPushService: simulatedIncomingPushService
        )
        cachedUseCase = useCase
        return useCase
    }
}
