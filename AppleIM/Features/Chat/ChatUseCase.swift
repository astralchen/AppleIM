//
//  ChatUseCase.swift
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
protocol ChatUseCase: Sendable {
    /// 加载首屏消息
    func loadInitialMessages() async throws -> ChatMessagePage
    /// 加载更早的消息
    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage
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
    /// 标记语音已播放
    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState?
    /// 模拟接收一条对方文本消息
    func simulateIncomingTextMessage() async throws -> ChatMessageRowState?
    /// 重发消息
    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error>
    /// 删除消息
    func delete(messageID: MessageID) async throws
    /// 撤回消息
    func revoke(messageID: MessageID) async throws
}

extension ChatUseCase {
    func sendText(_ text: String, mentionedUserIDs: [UserID], mentionsAll: Bool) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sendText(text)
    }

    func loadGroupContext() async throws -> GroupChatContext? {
        nil
    }

    func updateGroupAnnouncement(_ text: String) async throws -> GroupAnnouncement? {
        nil
    }

    func simulateIncomingTextMessage() async throws -> ChatMessageRowState? {
        nil
    }
}

/// 本地聊天用例实现
nonisolated struct LocalChatUseCase: ChatUseCase {
    /// 首屏消息加载数量
    private static let initialMessageLimit = 50
    /// 最短语音发送时长
    private static let minimumVoiceDurationMilliseconds = 1_000
    /// 模拟对方发送文本消息使用的固定发送者 ID
    private static let simulatedIncomingSenderID = UserID(rawValue: "__chatbridge_simulated_peer__")
    /// 模拟接收消息候选文本
    private static let simulatedIncomingTextSamples = [
        "模拟收到一条来自对方的新消息",
        "对方刚刚补充了一句测试消息",
        "这是一条从同步链路抵达的模拟消息",
        "收到新的对方消息，界面应该自动追加",
        "对方发来一条随机模拟文本"
    ]

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
    /// 消息发送服务
    private let sendService: any MessageSendService
    /// 媒体文件存储
    private let mediaFileStore: (any MediaFileStoring)?
    /// 媒体上传服务
    private let mediaUploadService: any MediaUploadService
    /// 重试策略
    private let retryPolicy: MessageRetryPolicy

    /// 初始化本地聊天用例
    init(
        userID: UserID,
        conversationID: ConversationID,
        currentUserAvatarURL: String? = nil,
        conversationAvatarURL: String? = nil,
        repository: any MessageRepository,
        conversationRepository: (any ConversationRepository)? = nil,
        pendingJobRepository: (any PendingJobRepository)? = nil,
        sendService: any MessageSendService,
        mediaFileStore: (any MediaFileStoring)? = nil,
        mediaUploadService: any MediaUploadService = MockMediaUploadService(),
        retryPolicy: MessageRetryPolicy = MessageRetryPolicy()
    ) {
        self.userID = userID
        self.conversationID = conversationID
        self.currentUserAvatarURL = currentUserAvatarURL
        self.conversationAvatarURL = conversationAvatarURL
        self.repository = repository
        self.conversationRepository = conversationRepository
        self.pendingJobRepository = pendingJobRepository
        self.sendService = sendService
        self.mediaFileStore = mediaFileStore
        self.mediaUploadService = mediaUploadService
        self.retryPolicy = retryPolicy
    }

    /// 加载首屏消息并标记会话已读
    func loadInitialMessages() async throws -> ChatMessagePage {
        try await conversationRepository?.markConversationRead(conversationID: conversationID, userID: userID)

        return try await loadMessagePage(limit: Self.initialMessageLimit, beforeSortSequence: nil)
    }

    /// 按游标加载更早消息
    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        try await loadMessagePage(limit: limit, beforeSortSequence: beforeSortSequence)
    }

    /// 加载消息分页
    ///
    /// - Parameters:
    ///   - limit: 每页数量
    ///   - beforeSortSequence: 游标（在此序号之前的消息）
    /// - Returns: 消息分页结果
    private func loadMessagePage(limit: Int, beforeSortSequence: Int64?) async throws -> ChatMessagePage {
        let boundedLimit = max(1, limit)
        let messages = try await repository.listMessages(
            conversationID: conversationID,
            limit: boundedLimit + 1,
            beforeSortSeq: beforeSortSequence
        )
        let visibleMessages = Array(messages.prefix(boundedLimit))
        let rows = visibleMessages
            .sorted { $0.sortSequence < $1.sortSequence }
            .map { row(from: $0, currentUserID: userID) }

        return ChatMessagePage(
            rows: rows,
            hasMore: messages.count > boundedLimit,
            nextBeforeSortSequence: rows.first?.sortSequence
        )
    }

    /// 加载当前会话草稿
    func loadDraft() async throws -> String? {
        try await repository.draft(conversationID: conversationID, userID: userID)
    }

    /// 保存当前会话草稿
    func saveDraft(_ text: String) async throws {
        try await repository.saveDraft(conversationID: conversationID, userID: userID, text: text)
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
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return AsyncThrowingStream { continuation in
            guard !trimmedText.isEmpty else {
                continuation.finish()
                return
            }

            let task = Task {
                do {
                    if mentionsAll {
                        let role = try await conversationRepository?.currentMemberRole(conversationID: conversationID, userID: userID)
                        guard role?.canManageAnnouncement == true else {
                            throw GroupChatError.permissionDenied
                        }
                    }

                    let now = Int64(Date().timeIntervalSince1970)
                    try await repository.clearDraft(conversationID: conversationID, userID: userID)
                    let insertedMessage = try await repository.insertOutgoingTextMessage(
                        OutgoingTextMessageInput(
                            userID: userID,
                            conversationID: conversationID,
                            senderID: userID,
                            text: trimmedText,
                            localTime: now,
                            mentionedUserIDs: mentionedUserIDs,
                            mentionsAll: mentionsAll,
                            sortSequence: now
                        )
                    )

                    continuation.yield(row(from: insertedMessage, currentUserID: userID))

                    let result = await sendService.sendText(message: insertedMessage)
                    let finalStatus: MessageSendStatus
                    let ack: MessageSendAck?

                    switch result {
                    case let .success(successAck):
                        finalStatus = .success
                        ack = successAck
                        try await repository.clearDraft(conversationID: conversationID, userID: userID)
                    case .failure:
                        finalStatus = .failed
                        ack = nil
                    }

                    try await updateSendStatus(
                        messageID: insertedMessage.id,
                        status: finalStatus,
                        ack: ack,
                        pendingJob: finalStatus == .failed ? try makeResendJobInput(for: insertedMessage, failureReason: result.failureReason) : nil
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

    /// 发送图片消息并流式返回上传和发送状态
    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let mediaFileStore else {
                        continuation.finish()
                        return
                    }

                    let now = Int64(Date().timeIntervalSince1970)
                    try await repository.clearDraft(conversationID: conversationID, userID: userID)
                    let storedImage = try await mediaFileStore.saveImage(
                        data: data,
                        preferredFileExtension: preferredFileExtension
                    )
                    let insertedMessage = try await repository.insertOutgoingImageMessage(
                        OutgoingImageMessageInput(
                            userID: userID,
                            conversationID: conversationID,
                            senderID: userID,
                            image: storedImage.content,
                            localTime: now,
                            sortSequence: now
                        )
                    )

                    continuation.yield(row(from: insertedMessage, currentUserID: userID))
                    try await uploadAndSendImage(insertedMessage, continuation: continuation)
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

    /// 发送语音消息并流式返回上传和发送状态
    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            guard recording.durationMilliseconds >= Self.minimumVoiceDurationMilliseconds else {
                continuation.finish()
                return
            }

            let task = Task {
                do {
                    guard let mediaFileStore else {
                        continuation.finish()
                        return
                    }

                    let now = Int64(Date().timeIntervalSince1970)
                    try await repository.clearDraft(conversationID: conversationID, userID: userID)
                    let storedVoice = try await mediaFileStore.saveVoice(
                        recordingURL: recording.fileURL,
                        durationMilliseconds: recording.durationMilliseconds,
                        preferredFileExtension: recording.fileExtension
                    )
                    let insertedMessage = try await repository.insertOutgoingVoiceMessage(
                        OutgoingVoiceMessageInput(
                            userID: userID,
                            conversationID: conversationID,
                            senderID: userID,
                            voice: storedVoice.content,
                            localTime: now,
                            sortSequence: now
                        )
                    )

                    continuation.yield(row(from: insertedMessage, currentUserID: userID))
                    try await uploadAndSendVoice(insertedMessage, continuation: continuation)
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

    /// 发送视频消息并流式返回上传和发送状态
    func sendVideo(fileURL: URL, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let mediaFileStore else {
                        continuation.finish()
                        return
                    }

                    let now = Int64(Date().timeIntervalSince1970)
                    try await repository.clearDraft(conversationID: conversationID, userID: userID)
                    let storedVideo = try await mediaFileStore.saveVideo(
                        fileURL: fileURL,
                        preferredFileExtension: preferredFileExtension
                    )
                    let insertedMessage = try await repository.insertOutgoingVideoMessage(
                        OutgoingVideoMessageInput(
                            userID: userID,
                            conversationID: conversationID,
                            senderID: userID,
                            video: storedVideo.content,
                            localTime: now,
                            sortSequence: now
                        )
                    )

                    continuation.yield(row(from: insertedMessage, currentUserID: userID))
                    try await uploadAndSendVideo(insertedMessage, continuation: continuation)
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

    /// 发送文件消息并流式返回上传和发送状态
    func sendFile(fileURL: URL) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let mediaFileStore else {
                        continuation.finish()
                        return
                    }

                    let now = Int64(Date().timeIntervalSince1970)
                    try await repository.clearDraft(conversationID: conversationID, userID: userID)
                    let storedFile = try await mediaFileStore.saveFile(fileURL: fileURL)
                    let insertedMessage = try await repository.insertOutgoingFileMessage(
                        OutgoingFileMessageInput(
                            userID: userID,
                            conversationID: conversationID,
                            senderID: userID,
                            file: storedFile.content,
                            localTime: now,
                            sortSequence: now
                        )
                    )

                    continuation.yield(row(from: insertedMessage, currentUserID: userID))
                    try await uploadAndSendFile(insertedMessage, continuation: continuation)
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

    /// 模拟服务端同步到一条对方文本消息，并返回可直接渲染的行状态。
    func simulateIncomingTextMessage() async throws -> ChatMessageRowState? {
        guard let syncStore = repository as? any SyncStore else {
            return nil
        }

        let latestMessages = try await repository.listMessages(
            conversationID: conversationID,
            limit: 1,
            beforeSortSeq: nil
        )
        let latestMessage = latestMessages.first
        let sequence = max((latestMessage?.sortSequence ?? 0) + 1, Self.currentTimestamp())
        let messageToken = UUID().uuidString
        let messageID = MessageID(rawValue: "simulated_incoming_\(messageToken)")
        let text = Self.simulatedIncomingText(messageToken: messageToken)
        let batch = SyncBatch(
            messages: [
                IncomingSyncMessage(
                    messageID: messageID,
                    conversationID: conversationID,
                    senderID: Self.simulatedIncomingSenderID,
                    serverMessageID: "server_\(messageID.rawValue)",
                    sequence: sequence,
                    text: text,
                    serverTime: sequence,
                    direction: .incoming
                )
            ],
            nextCursor: nil,
            nextSequence: sequence
        )

        _ = try await syncStore.applyIncomingSyncBatch(batch, userID: userID)
        try await conversationRepository?.markConversationRead(conversationID: conversationID, userID: userID)
        guard let storedMessage = try await repository.message(messageID: messageID) else {
            return nil
        }

        return row(from: storedMessage, currentUserID: userID)
    }

    private static func simulatedIncomingText(messageToken: String) -> String {
        let sample = simulatedIncomingTextSamples.randomElement() ?? "模拟收到一条来自对方的新消息"
        return "\(sample) #\(messageToken.prefix(6).lowercased())"
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
                        try await uploadAndSendImage(sendingMessage, continuation: continuation)
                        continuation.finish()
                        return
                    }

                    if existingMessage.type == .video {
                        let sendingMessage = try await repository.resendVideoMessage(messageID: messageID)
                        continuation.yield(row(from: sendingMessage, currentUserID: userID))
                        try await uploadAndSendVideo(sendingMessage, continuation: continuation)
                        continuation.finish()
                        return
                    }

                    if existingMessage.type == .file {
                        let sendingMessage = try await repository.resendFileMessage(messageID: messageID)
                        continuation.yield(row(from: sendingMessage, currentUserID: userID))
                        try await uploadAndSendFile(sendingMessage, continuation: continuation)
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
        guard pendingJobRepository != nil, let clientMessageID = message.clientMessageID else {
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
        guard let pendingJobRepository, let clientMessageID = message.clientMessageID else {
            return
        }

        try await pendingJobRepository.updatePendingJobStatus(
            jobID: PendingMessageJobFactory.messageResendJobID(clientMessageID: clientMessageID),
            status: .success,
            nextRetryAt: nil
        )
    }

    /// 上传图片并发送图片消息体
    ///
    /// 图片已完成本地落盘和消息入库，这里只负责上传、ack 和失败恢复任务。
    private func uploadAndSendImage(
        _ message: StoredMessage,
        continuation: AsyncThrowingStream<ChatMessageRowState, Error>.Continuation
    ) async throws {
        try await repository.updateImageUploadStatus(
            messageID: message.id,
            uploadStatus: .uploading,
            uploadAck: nil,
            sendStatus: .sending,
            sendAck: nil,
            pendingJob: nil
        )

        for await event in mediaUploadService.uploadImage(message: message) {
            switch event {
            case let .progress(progress):
                continuation.yield(row(from: message, currentUserID: userID, uploadProgress: progress))
            case let .completed(uploadAck):
                let result = await sendService.sendImage(message: message, upload: uploadAck)
                let finalStatus: MessageSendStatus
                let imageUploadStatus: MediaUploadStatus
                let sendAck: MessageSendAck?

                switch result {
                case let .success(ack):
                    finalStatus = .success
                    imageUploadStatus = .success
                    sendAck = ack
                    try await markImageUploadJobSuccess(for: message)
                case .failure:
                    finalStatus = .failed
                    imageUploadStatus = .failed
                    sendAck = nil
                }

                try await repository.updateImageUploadStatus(
                    messageID: message.id,
                    uploadStatus: imageUploadStatus,
                    uploadAck: uploadAck,
                    sendStatus: finalStatus,
                    sendAck: sendAck,
                    pendingJob: finalStatus == .failed ? try makeImageUploadJobInput(
                        for: message,
                        failureReason: result.failureReason?.rawValue
                    ) : nil
                )

                if let updatedMessage = try await repository.message(messageID: message.id) {
                    continuation.yield(row(from: updatedMessage, currentUserID: userID))
                }
                return
            case let .failed(reason):
                try await repository.updateImageUploadStatus(
                    messageID: message.id,
                    uploadStatus: .failed,
                    uploadAck: nil,
                    sendStatus: .failed,
                    sendAck: nil,
                    pendingJob: try makeImageUploadJobInput(for: message, failureReason: reason.rawValue)
                )

                if let updatedMessage = try await repository.message(messageID: message.id) {
                    continuation.yield(row(from: updatedMessage, currentUserID: userID))
                }
                return
            }
        }

        try await repository.updateImageUploadStatus(
            messageID: message.id,
            uploadStatus: .failed,
            uploadAck: nil,
            sendStatus: .failed,
            sendAck: nil,
            pendingJob: try makeImageUploadJobInput(for: message, failureReason: MediaUploadFailureReason.unknown.rawValue)
        )

        if let updatedMessage = try await repository.message(messageID: message.id) {
            continuation.yield(row(from: updatedMessage, currentUserID: userID))
        }
    }

    /// 上传语音并发送语音消息体
    ///
    /// 语音已完成本地落盘和消息入库，这里只负责上传、ack 和最终状态。
    private func uploadAndSendVoice(
        _ message: StoredMessage,
        continuation: AsyncThrowingStream<ChatMessageRowState, Error>.Continuation
    ) async throws {
        try await repository.updateVoiceUploadStatus(
            messageID: message.id,
            uploadStatus: .uploading,
            uploadAck: nil,
            sendStatus: .sending,
            sendAck: nil
        )

        for await event in mediaUploadService.uploadVoice(message: message) {
            switch event {
            case let .progress(progress):
                continuation.yield(row(from: message, currentUserID: userID, uploadProgress: progress))
            case let .completed(uploadAck):
                let result = await sendService.sendVoice(message: message, upload: uploadAck)
                let finalStatus: MessageSendStatus
                let voiceUploadStatus: MediaUploadStatus
                let sendAck: MessageSendAck?

                switch result {
                case let .success(ack):
                    finalStatus = .success
                    voiceUploadStatus = .success
                    sendAck = ack
                case .failure:
                    finalStatus = .failed
                    voiceUploadStatus = .failed
                    sendAck = nil
                }

                try await repository.updateVoiceUploadStatus(
                    messageID: message.id,
                    uploadStatus: voiceUploadStatus,
                    uploadAck: uploadAck,
                    sendStatus: finalStatus,
                    sendAck: sendAck
                )

                if let updatedMessage = try await repository.message(messageID: message.id) {
                    continuation.yield(row(from: updatedMessage, currentUserID: userID))
                }
                return
            case .failed:
                try await repository.updateVoiceUploadStatus(
                    messageID: message.id,
                    uploadStatus: .failed,
                    uploadAck: nil,
                    sendStatus: .failed,
                    sendAck: nil
                )

                if let updatedMessage = try await repository.message(messageID: message.id) {
                    continuation.yield(row(from: updatedMessage, currentUserID: userID))
                }
                return
            }
        }

        try await repository.updateVoiceUploadStatus(
            messageID: message.id,
            uploadStatus: .failed,
            uploadAck: nil,
            sendStatus: .failed,
            sendAck: nil
        )

        if let updatedMessage = try await repository.message(messageID: message.id) {
            continuation.yield(row(from: updatedMessage, currentUserID: userID))
        }
    }

    /// 上传视频并发送视频消息体
    ///
    /// 视频已完成本地落盘和消息入库，这里负责上传、发送 ack 和失败恢复任务。
    private func uploadAndSendVideo(
        _ message: StoredMessage,
        continuation: AsyncThrowingStream<ChatMessageRowState, Error>.Continuation
    ) async throws {
        try await repository.updateVideoUploadStatus(
            messageID: message.id,
            uploadStatus: .uploading,
            uploadAck: nil,
            sendStatus: .sending,
            sendAck: nil,
            pendingJob: nil
        )

        for await event in mediaUploadService.uploadVideo(message: message) {
            switch event {
            case let .progress(progress):
                continuation.yield(row(from: message, currentUserID: userID, uploadProgress: progress))
            case let .completed(uploadAck):
                let result = await sendService.sendVideo(message: message, upload: uploadAck)
                let finalStatus: MessageSendStatus
                let videoUploadStatus: MediaUploadStatus
                let sendAck: MessageSendAck?

                switch result {
                case let .success(ack):
                    finalStatus = .success
                    videoUploadStatus = .success
                    sendAck = ack
                    try await markVideoUploadJobSuccess(for: message)
                case .failure:
                    finalStatus = .failed
                    videoUploadStatus = .failed
                    sendAck = nil
                }

                try await repository.updateVideoUploadStatus(
                    messageID: message.id,
                    uploadStatus: videoUploadStatus,
                    uploadAck: uploadAck,
                    sendStatus: finalStatus,
                    sendAck: sendAck,
                    pendingJob: finalStatus == .failed ? try makeVideoUploadJobInput(
                        for: message,
                        failureReason: result.failureReason?.rawValue
                    ) : nil
                )

                if let updatedMessage = try await repository.message(messageID: message.id) {
                    continuation.yield(row(from: updatedMessage, currentUserID: userID))
                }
                return
            case let .failed(reason):
                try await repository.updateVideoUploadStatus(
                    messageID: message.id,
                    uploadStatus: .failed,
                    uploadAck: nil,
                    sendStatus: .failed,
                    sendAck: nil,
                    pendingJob: try makeVideoUploadJobInput(for: message, failureReason: reason.rawValue)
                )

                if let updatedMessage = try await repository.message(messageID: message.id) {
                    continuation.yield(row(from: updatedMessage, currentUserID: userID))
                }
                return
            }
        }
    }

    /// 上传文件并发送文件消息体
    ///
    /// 文件已完成本地落盘和消息入库，这里负责上传、发送 ack 和失败恢复任务。
    private func uploadAndSendFile(
        _ message: StoredMessage,
        continuation: AsyncThrowingStream<ChatMessageRowState, Error>.Continuation
    ) async throws {
        try await repository.updateFileUploadStatus(
            messageID: message.id,
            uploadStatus: .uploading,
            uploadAck: nil,
            sendStatus: .sending,
            sendAck: nil,
            pendingJob: nil
        )

        for await event in mediaUploadService.uploadFile(message: message) {
            switch event {
            case let .progress(progress):
                continuation.yield(row(from: message, currentUserID: userID, uploadProgress: progress))
            case let .completed(uploadAck):
                let result = await sendService.sendFile(message: message, upload: uploadAck)
                let finalStatus: MessageSendStatus
                let fileUploadStatus: MediaUploadStatus
                let sendAck: MessageSendAck?

                switch result {
                case let .success(ack):
                    finalStatus = .success
                    fileUploadStatus = .success
                    sendAck = ack
                    try await markFileUploadJobSuccess(for: message)
                case .failure:
                    finalStatus = .failed
                    fileUploadStatus = .failed
                    sendAck = nil
                }

                try await repository.updateFileUploadStatus(
                    messageID: message.id,
                    uploadStatus: fileUploadStatus,
                    uploadAck: uploadAck,
                    sendStatus: finalStatus,
                    sendAck: sendAck,
                    pendingJob: finalStatus == .failed ? try makeFileUploadJobInput(
                        for: message,
                        failureReason: result.failureReason?.rawValue
                    ) : nil
                )

                if let updatedMessage = try await repository.message(messageID: message.id) {
                    continuation.yield(row(from: updatedMessage, currentUserID: userID))
                }
                return
            case let .failed(reason):
                try await repository.updateFileUploadStatus(
                    messageID: message.id,
                    uploadStatus: .failed,
                    uploadAck: nil,
                    sendStatus: .failed,
                    sendAck: nil,
                    pendingJob: try makeFileUploadJobInput(for: message, failureReason: reason.rawValue)
                )

                if let updatedMessage = try await repository.message(messageID: message.id) {
                    continuation.yield(row(from: updatedMessage, currentUserID: userID))
                }
                return
            }
        }
    }

    /// 创建图片上传恢复任务输入参数
    private func makeImageUploadJobInput(
        for message: StoredMessage,
        failureReason: String?
    ) throws -> PendingJobInput? {
        guard
            pendingJobRepository != nil,
            let clientMessageID = message.clientMessageID,
            let image = message.image
        else {
            return nil
        }

        return try PendingMessageJobFactory.imageUploadInput(
            messageID: message.id,
            conversationID: message.conversationID,
            clientMessageID: clientMessageID,
            mediaID: image.mediaID,
            userID: userID,
            failureReason: failureReason,
            maxRetryCount: retryPolicy.maxRetryCount,
            nextRetryAt: retryPolicy.nextRetryAt(now: Self.currentTimestamp(), retryCount: 0)
        )
    }

    /// 标记图片上传恢复任务成功
    private func markImageUploadJobSuccess(for message: StoredMessage) async throws {
        guard let pendingJobRepository, let clientMessageID = message.clientMessageID else {
            return
        }

        try await pendingJobRepository.updatePendingJobStatus(
            jobID: PendingMessageJobFactory.imageUploadJobID(clientMessageID: clientMessageID),
            status: .success,
            nextRetryAt: nil
        )
    }

    /// 创建视频上传恢复任务输入参数
    private func makeVideoUploadJobInput(
        for message: StoredMessage,
        failureReason: String?
    ) throws -> PendingJobInput? {
        guard
            pendingJobRepository != nil,
            let clientMessageID = message.clientMessageID,
            let video = message.video
        else {
            return nil
        }

        return try PendingMessageJobFactory.videoUploadInput(
            messageID: message.id,
            conversationID: message.conversationID,
            clientMessageID: clientMessageID,
            mediaID: video.mediaID,
            userID: userID,
            failureReason: failureReason,
            maxRetryCount: retryPolicy.maxRetryCount,
            nextRetryAt: retryPolicy.nextRetryAt(now: Self.currentTimestamp(), retryCount: 0)
        )
    }

    /// 创建文件上传恢复任务输入参数
    private func makeFileUploadJobInput(
        for message: StoredMessage,
        failureReason: String?
    ) throws -> PendingJobInput? {
        guard
            pendingJobRepository != nil,
            let clientMessageID = message.clientMessageID,
            let file = message.file
        else {
            return nil
        }

        return try PendingMessageJobFactory.fileUploadInput(
            messageID: message.id,
            conversationID: message.conversationID,
            clientMessageID: clientMessageID,
            mediaID: file.mediaID,
            userID: userID,
            failureReason: failureReason,
            maxRetryCount: retryPolicy.maxRetryCount,
            nextRetryAt: retryPolicy.nextRetryAt(now: Self.currentTimestamp(), retryCount: 0)
        )
    }

    /// 标记视频上传恢复任务成功
    private func markVideoUploadJobSuccess(for message: StoredMessage) async throws {
        guard let pendingJobRepository, let clientMessageID = message.clientMessageID else {
            return
        }

        try await pendingJobRepository.updatePendingJobStatus(
            jobID: PendingMessageJobFactory.videoUploadJobID(clientMessageID: clientMessageID),
            status: .success,
            nextRetryAt: nil
        )
    }

    /// 标记文件上传恢复任务成功
    private func markFileUploadJobSuccess(for message: StoredMessage) async throws {
        guard let pendingJobRepository, let clientMessageID = message.clientMessageID else {
            return
        }

        try await pendingJobRepository.updatePendingJobStatus(
            jobID: PendingMessageJobFactory.fileUploadJobID(clientMessageID: clientMessageID),
            status: .success,
            nextRetryAt: nil
        )
    }

    /// 当前秒级时间戳
    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }

    /// 将存储消息转换为聊天行状态
    nonisolated private func row(
        from message: StoredMessage,
        currentUserID: UserID,
        uploadProgress: Double? = nil
    ) -> ChatMessageRowState {
        let isOutgoing = message.senderID == currentUserID
        let isRevoked = message.isRevoked
        let senderAvatarURL = isOutgoing ? currentUserAvatarURL : conversationAvatarURL

        return ChatMessageRowState(
            id: message.id,
            content: Self.rowContent(
                for: message,
                isOutgoing: isOutgoing,
                isRevoked: isRevoked
            ),
            sortSequence: message.sortSequence,
            sentAt: message.localTime,
            timeText: Self.timeText(from: message.localTime),
            statusText: isRevoked ? nil : Self.statusText(for: message),
            uploadProgress: uploadProgress,
            senderAvatarURL: senderAvatarURL,
            isOutgoing: isOutgoing,
            canRetry: isOutgoing
                && (message.type == .text || message.type == .image || message.type == .video)
                && message.sendStatus == .failed
                && !isRevoked,
            canDelete: !message.isDeleted,
            canRevoke: isOutgoing && message.type == .text && message.sendStatus == .success && !isRevoked
        )
    }

    /// 生成消息内容状态
    nonisolated private static func rowContent(
        for message: StoredMessage,
        isOutgoing: Bool,
        isRevoked: Bool
    ) -> ChatMessageRowContent {
        if isRevoked {
            return .revoked(message.revokeReplacementText ?? "你撤回了一条消息")
        }

        switch message.type {
        case .image:
            if let image = message.image {
                return .image(
                    ChatMessageRowContent.ImageContent(
                        thumbnailPath: image.thumbnailPath
                    )
                )
            }
        case .voice:
            if let voice = message.voice {
                return .voice(
                    ChatMessageRowContent.VoiceContent(
                        localPath: voice.localPath,
                        durationMilliseconds: voice.durationMilliseconds,
                        isUnplayed: !isOutgoing && message.readStatus == .unread,
                        isPlaying: false
                    )
                )
            }
        case .video:
            if let video = message.video {
                return .video(
                    ChatMessageRowContent.VideoContent(
                        thumbnailPath: video.thumbnailPath,
                        localPath: video.localPath,
                        durationMilliseconds: video.durationMilliseconds
                    )
                )
            }
        case .file:
            if let file = message.file {
                return .file(
                    ChatMessageRowContent.FileContent(
                        fileName: file.fileName,
                        fileExtension: file.fileExtension,
                        localPath: file.localPath,
                        sizeBytes: file.sizeBytes
                    )
                )
            }
        case .text, .system, .emoji, .quote, .revoked:
            break
        }

        return .text(message.text ?? "")
    }

    /// 生成发出消息状态文本
    nonisolated private static func statusText(for message: StoredMessage) -> String? {
        guard message.direction == .outgoing else {
            return nil
        }

        switch message.sendStatus {
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
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
            case .imageUpload:
                let result = try await runImageUploadJob(job, now: now)
                attemptedCount += result.attempted ? 1 : 0
                successCount += result.succeeded ? 1 : 0
                rescheduledCount += result.rescheduled ? 1 : 0
                exhaustedCount += result.exhausted ? 1 : 0
            case .videoUpload:
                let result = try await runVideoUploadJob(job, now: now)
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
        let payload = try JSONDecoder().decode(MessageResendPendingJobPayload.self, from: Data(job.payloadJSON.utf8))
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

    /// 执行图片上传恢复任务
    private func runImageUploadJob(_ job: PendingJob, now: Int64 = Int64(Date().timeIntervalSince1970)) async throws -> PendingJobAttemptResult {
        let payload = try JSONDecoder().decode(ImageUploadPendingJobPayload.self, from: Data(job.payloadJSON.utf8))
        let messageID = MessageID(rawValue: payload.messageID)

        guard let message = try await messageRepository.message(messageID: messageID) else {
            try await pendingJobRepository.updatePendingJobStatus(jobID: job.id, status: .cancelled, nextRetryAt: nil)
            return PendingJobAttemptResult(attempted: false, succeeded: false, rescheduled: false, exhausted: true)
        }

        try await pendingJobRepository.updatePendingJobStatus(jobID: job.id, status: .running, nextRetryAt: nil)
        try await messageRepository.updateImageUploadStatus(
            messageID: messageID,
            uploadStatus: .uploading,
            uploadAck: nil,
            sendStatus: .sending,
            sendAck: nil,
            pendingJob: nil
        )

        for await event in mediaUploadService.uploadImage(message: message) {
            switch event {
            case .progress:
                continue
            case let .completed(uploadAck):
                let result = await sendService.sendImage(message: message, upload: uploadAck)

                switch result {
                case let .success(sendAck):
                    try await messageRepository.updateImageUploadStatus(
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
                    try await messageRepository.updateImageUploadStatus(
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
                try await messageRepository.updateImageUploadStatus(
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

        try await messageRepository.updateImageUploadStatus(
            messageID: messageID,
            uploadStatus: .failed,
            uploadAck: nil,
            sendStatus: .failed,
            sendAck: nil,
            pendingJob: nil
        )
        return try await retryOrExhaust(job, now: now)
    }

    /// 执行视频上传恢复任务
    private func runVideoUploadJob(_ job: PendingJob, now: Int64 = Int64(Date().timeIntervalSince1970)) async throws -> PendingJobAttemptResult {
        let payload = try JSONDecoder().decode(VideoUploadPendingJobPayload.self, from: Data(job.payloadJSON.utf8))
        let messageID = MessageID(rawValue: payload.messageID)

        guard let message = try await messageRepository.message(messageID: messageID) else {
            try await pendingJobRepository.updatePendingJobStatus(jobID: job.id, status: .cancelled, nextRetryAt: nil)
            return PendingJobAttemptResult(attempted: false, succeeded: false, rescheduled: false, exhausted: true)
        }

        try await pendingJobRepository.updatePendingJobStatus(jobID: job.id, status: .running, nextRetryAt: nil)
        try await messageRepository.updateVideoUploadStatus(
            messageID: messageID,
            uploadStatus: .uploading,
            uploadAck: nil,
            sendStatus: .sending,
            sendAck: nil,
            pendingJob: nil
        )

        for await event in mediaUploadService.uploadVideo(message: message) {
            switch event {
            case .progress:
                continue
            case let .completed(uploadAck):
                let result = await sendService.sendVideo(message: message, upload: uploadAck)

                switch result {
                case let .success(sendAck):
                    try await messageRepository.updateVideoUploadStatus(
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
                    try await messageRepository.updateVideoUploadStatus(
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
                try await messageRepository.updateVideoUploadStatus(
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

        try await messageRepository.updateVideoUploadStatus(
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
nonisolated struct StoreBackedChatUseCase: ChatUseCase {
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

    /// 初始化基于存储 Provider 的聊天用例
    init(
        userID: UserID,
        conversationID: ConversationID,
        currentUserAvatarURL: String? = nil,
        conversationAvatarURL: String? = nil,
        storeProvider: ChatStoreProvider,
        sendService: any MessageSendService,
        mediaFileStore: any MediaFileStoring,
        mediaUploadService: any MediaUploadService = MockMediaUploadService()
    ) {
        self.userID = userID
        self.conversationID = conversationID
        self.currentUserAvatarURL = currentUserAvatarURL
        self.conversationAvatarURL = conversationAvatarURL
        self.storeProvider = storeProvider
        self.sendService = sendService
        self.mediaFileStore = mediaFileStore
        self.mediaUploadService = mediaUploadService
    }

    /// 加载首屏消息
    func loadInitialMessages() async throws -> ChatMessagePage {
        let repository = try await storeProvider.repository()
        let useCase = makeLocalUseCase(repository: repository)
        return try await useCase.loadInitialMessages()
    }

    /// 按游标加载更早消息
    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        let repository = try await storeProvider.repository()
        let useCase = makeLocalUseCase(repository: repository)
        return try await useCase.loadOlderMessages(beforeSortSequence: beforeSortSequence, limit: limit)
    }

    /// 加载当前会话草稿
    func loadDraft() async throws -> String? {
        let repository = try await storeProvider.repository()
        let useCase = makeLocalUseCase(repository: repository)
        return try await useCase.loadDraft()
    }

    /// 保存当前会话草稿
    func saveDraft(_ text: String) async throws {
        let repository = try await storeProvider.repository()
        let useCase = makeLocalUseCase(repository: repository)
        try await useCase.saveDraft(text)
    }

    /// 发送文本消息并透传本地用例的状态流
    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sendText(text, mentionedUserIDs: [], mentionsAll: false)
    }

    /// 发送带 @ 元数据的文本消息并透传本地用例的状态流
    func sendText(_ text: String, mentionedUserIDs: [UserID], mentionsAll: Bool) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let repository = try await storeProvider.repository()
                    let useCase = makeLocalUseCase(repository: repository)

                    for try await row in useCase.sendText(text, mentionedUserIDs: mentionedUserIDs, mentionsAll: mentionsAll) {
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

    /// 加载群聊上下文
    func loadGroupContext() async throws -> GroupChatContext? {
        let repository = try await storeProvider.repository()
        let useCase = makeLocalUseCase(repository: repository)
        return try await useCase.loadGroupContext()
    }

    /// 更新群公告
    func updateGroupAnnouncement(_ text: String) async throws -> GroupAnnouncement? {
        let repository = try await storeProvider.repository()
        let useCase = makeLocalUseCase(repository: repository)
        return try await useCase.updateGroupAnnouncement(text)
    }

    /// 发送图片消息并透传本地用例的状态流
    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let repository = try await storeProvider.repository()
                    let useCase = makeLocalUseCase(repository: repository)

                    for try await row in useCase.sendImage(data: data, preferredFileExtension: preferredFileExtension) {
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

    /// 发送语音消息并透传本地用例的状态流
    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let repository = try await storeProvider.repository()
                    let useCase = makeLocalUseCase(repository: repository)

                    for try await row in useCase.sendVoice(recording: recording) {
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

    /// 发送视频消息并透传本地用例的状态流
    func sendVideo(fileURL: URL, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let repository = try await storeProvider.repository()
                    let useCase = makeLocalUseCase(repository: repository)

                    for try await row in useCase.sendVideo(fileURL: fileURL, preferredFileExtension: preferredFileExtension) {
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

    /// 发送文件消息并透传本地用例的状态流
    func sendFile(fileURL: URL) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let repository = try await storeProvider.repository()
                    let useCase = makeLocalUseCase(repository: repository)

                    for try await row in useCase.sendFile(fileURL: fileURL) {
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

    /// 标记语音消息已播放
    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        let repository = try await storeProvider.repository()
        let useCase = makeLocalUseCase(repository: repository)
        return try await useCase.markVoicePlayed(messageID: messageID)
    }

    /// 模拟接收一条对方文本消息。
    func simulateIncomingTextMessage() async throws -> ChatMessageRowState? {
        let repository = try await storeProvider.repository()
        let useCase = makeLocalUseCase(repository: repository)
        return try await useCase.simulateIncomingTextMessage()
    }

    /// 重发失败消息并透传本地用例的状态流
    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let repository = try await storeProvider.repository()
                    let useCase = makeLocalUseCase(repository: repository)

                    for try await row in useCase.resend(messageID: messageID) {
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

    /// 删除消息
    func delete(messageID: MessageID) async throws {
        let repository = try await storeProvider.repository()
        let useCase = makeLocalUseCase(repository: repository)
        try await useCase.delete(messageID: messageID)
    }

    /// 撤回消息
    func revoke(messageID: MessageID) async throws {
        let repository = try await storeProvider.repository()
        let useCase = makeLocalUseCase(repository: repository)
        try await useCase.revoke(messageID: messageID)
    }

    /// 基于最新 repository 创建本地聊天用例
    private func makeLocalUseCase(repository: LocalChatRepository) -> LocalChatUseCase {
        LocalChatUseCase(
            userID: userID,
            conversationID: conversationID,
            currentUserAvatarURL: currentUserAvatarURL,
            conversationAvatarURL: conversationAvatarURL,
            repository: repository,
            conversationRepository: repository,
            pendingJobRepository: repository,
            sendService: sendService,
            mediaFileStore: mediaFileStore,
            mediaUploadService: mediaUploadService
        )
    }
}
