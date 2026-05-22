//
//  ChatUseCaseCollaborators.swift
//  AppleIM
//
//  聊天用例内部协作者
//

import Foundation

/// 消息时间线读取协作者。
nonisolated struct ChatTimelineLoading: Sendable {
    private let userID: UserID
    private let conversationID: ConversationID
    private let messageRepository: any MessageTimelineRepository
    private let observationRepository: (any MessageObservationRepository)?
    private let conversationRepository: (any ConversationRepository)?
    private let rowMapper: ChatMessageRowMapper

    init(
        userID: UserID,
        conversationID: ConversationID,
        messageRepository: any MessageTimelineRepository,
        observationRepository: (any MessageObservationRepository)?,
        conversationRepository: (any ConversationRepository)?,
        rowMapper: ChatMessageRowMapper
    ) {
        self.userID = userID
        self.conversationID = conversationID
        self.messageRepository = messageRepository
        self.observationRepository = observationRepository
        self.conversationRepository = conversationRepository
        self.rowMapper = rowMapper
    }

    func loadInitialMessages(limit: Int) async throws -> ChatMessagePage {
        try await conversationRepository?.markConversationRead(conversationID: conversationID, userID: userID)
        return try await loadMessagePage(limit: limit, beforeSortSequence: nil)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        try await loadMessagePage(limit: limit, beforeSortSequence: beforeSortSequence)
    }

    func observeLatestMessages(limit: Int) async throws -> DatabaseObservationStream<[ChatMessageRowState]>? {
        guard let observationRepository else {
            return nil
        }
        return try await observationRepository
            .observeLatestMessages(conversationID: conversationID, limit: max(1, limit))
            .map { messages in
                messages
                    .sorted { $0.timeline.sortSequence < $1.timeline.sortSequence }
                    .map { rowMapper.row(from: $0) }
            }
    }

    private func loadMessagePage(limit: Int, beforeSortSequence: Int64?) async throws -> ChatMessagePage {
        let boundedLimit = max(1, limit)
        let messages = try await messageRepository.listMessages(
            conversationID: conversationID,
            limit: boundedLimit + 1,
            beforeSortSeq: beforeSortSequence
        )
        let visibleMessages = Array(messages.prefix(boundedLimit))
        let rows = visibleMessages
            .sorted { $0.timeline.sortSequence < $1.timeline.sortSequence }
            .map { rowMapper.row(from: $0) }

        return ChatMessagePage(
            rows: rows,
            hasMore: messages.count > boundedLimit,
            nextBeforeSortSequence: rows.first?.sortSequence
        )
    }
}

private extension MessageSendResult {
    var failureReason: MessageSendFailureReason? {
        guard case let .failure(reason) = self else {
            return nil
        }

        return reason
    }
}

/// 媒体消息发送协作者。
nonisolated struct ChatMediaMessageSending: Sendable {
    private let userID: UserID
    private let conversationID: ConversationID
    private let repository: any MessageRepository
    private let pendingJobRepository: (any PendingJobRepository)?
    private let mediaFileStore: (any MediaFileStoring)?
    private let mediaUploadService: any MediaUploadService
    private let sendService: any MessageSendService
    private let retryPolicy: MessageRetryPolicy
    private let rowMapper: ChatMessageRowMapper

    init(
        userID: UserID,
        conversationID: ConversationID,
        repository: any MessageRepository,
        pendingJobRepository: (any PendingJobRepository)?,
        mediaFileStore: (any MediaFileStoring)?,
        mediaUploadService: any MediaUploadService,
        sendService: any MessageSendService,
        retryPolicy: MessageRetryPolicy,
        rowMapper: ChatMessageRowMapper
    ) {
        self.userID = userID
        self.conversationID = conversationID
        self.repository = repository
        self.pendingJobRepository = pendingJobRepository
        self.mediaFileStore = mediaFileStore
        self.mediaUploadService = mediaUploadService
        self.sendService = sendService
        self.retryPolicy = retryPolicy
        self.rowMapper = rowMapper
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sendPreparedMediaMessage(operation: .image) {
            guard let mediaFileStore else {
                return nil
            }

            let now = Self.currentTimestamp()
            try await repository.clearDraft(conversationID: conversationID, userID: userID)
            let storedImage = try await mediaFileStore.saveImage(
                data: data,
                preferredFileExtension: preferredFileExtension
            )
            return try await repository.insertOutgoingImageMessage(
                OutgoingImageMessageInput(
                    userID: userID,
                    conversationID: conversationID,
                    senderID: userID,
                    image: storedImage.content,
                    localTime: now,
                    sortSequence: now
                )
            )
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sendPreparedMediaMessage(operation: .voice) {
            guard let mediaFileStore else {
                return nil
            }

            let now = Self.currentTimestamp()
            try await repository.clearDraft(conversationID: conversationID, userID: userID)
            let storedVoice = try await mediaFileStore.saveVoice(
                recordingURL: recording.fileURL,
                durationMilliseconds: recording.durationMilliseconds,
                preferredFileExtension: recording.fileExtension
            )
            return try await repository.insertOutgoingVoiceMessage(
                OutgoingVoiceMessageInput(
                    userID: userID,
                    conversationID: conversationID,
                    senderID: userID,
                    voice: storedVoice.content,
                    localTime: now,
                    sortSequence: now
                )
            )
        }
    }

    func sendVideo(fileURL: URL, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sendPreparedMediaMessage(operation: .video) {
            guard let mediaFileStore else {
                return nil
            }

            let now = Self.currentTimestamp()
            try await repository.clearDraft(conversationID: conversationID, userID: userID)
            let storedVideo = try await mediaFileStore.saveVideo(
                fileURL: fileURL,
                preferredFileExtension: preferredFileExtension
            )
            return try await repository.insertOutgoingVideoMessage(
                OutgoingVideoMessageInput(
                    userID: userID,
                    conversationID: conversationID,
                    senderID: userID,
                    video: storedVideo.content,
                    localTime: now,
                    sortSequence: now
                )
            )
        }
    }

    func sendFile(fileURL: URL) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sendPreparedMediaMessage(operation: .file) {
            guard let mediaFileStore else {
                return nil
            }

            let now = Self.currentTimestamp()
            try await repository.clearDraft(conversationID: conversationID, userID: userID)
            let storedFile = try await mediaFileStore.saveFile(fileURL: fileURL)
            return try await repository.insertOutgoingFileMessage(
                OutgoingFileMessageInput(
                    userID: userID,
                    conversationID: conversationID,
                    senderID: userID,
                    file: storedFile.content,
                    localTime: now,
                    sortSequence: now
                )
            )
        }
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

                    continuation.yield(rowMapper.row(from: insertedMessage))
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
                continuation.yield(rowMapper.row(from: message, uploadProgress: progress))
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
            continuation.yield(rowMapper.row(from: updatedMessage))
        }
    }

    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }
}

/// 草稿与文本消息发送协作者。
nonisolated struct ChatMessageSending: Sendable {
    private let userID: UserID
    private let conversationID: ConversationID
    private let repository: any MessageTimelineRepository & MessageDraftRepository & MessageMutationRepository
    private let conversationRepository: (any ConversationRepository)?
    private let pendingJobRepository: (any PendingJobRepository)?
    private let recoveryRepository: (any MessageSendRecoveryRepository)?
    private let sendService: any MessageSendService
    private let retryPolicy: MessageRetryPolicy
    private let rowMapper: ChatMessageRowMapper
    private let logger = AppLogger(category: .chat)

    init(
        userID: UserID,
        conversationID: ConversationID,
        repository: any MessageTimelineRepository & MessageDraftRepository & MessageMutationRepository,
        conversationRepository: (any ConversationRepository)?,
        pendingJobRepository: (any PendingJobRepository)?,
        recoveryRepository: (any MessageSendRecoveryRepository)?,
        sendService: any MessageSendService,
        retryPolicy: MessageRetryPolicy,
        rowMapper: ChatMessageRowMapper
    ) {
        self.userID = userID
        self.conversationID = conversationID
        self.repository = repository
        self.conversationRepository = conversationRepository
        self.pendingJobRepository = pendingJobRepository
        self.recoveryRepository = recoveryRepository
        self.sendService = sendService
        self.retryPolicy = retryPolicy
        self.rowMapper = rowMapper
    }

    func loadDraft() async throws -> String? {
        try await repository.draft(conversationID: conversationID, userID: userID)
    }

    func saveDraft(_ text: String) async throws {
        try await repository.saveDraft(conversationID: conversationID, userID: userID, text: text)
    }

    func sendText(_ text: String, mentionedUserIDs: [UserID], mentionsAll: Bool) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return AsyncThrowingStream { continuation in
            guard !trimmedText.isEmpty else {
                continuation.finish()
                return
            }

            let task = Task {
                let startUptime = AppLogger.performanceSpan()
                do {
                    if mentionsAll {
                        let role = try await conversationRepository?.currentMemberRole(conversationID: conversationID, userID: userID)
                        guard role?.canManageAnnouncement == true else {
                            throw GroupChatError.permissionDenied
                        }
                    }

                    let now = Self.currentTimestamp()
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
                    continuation.yield(rowMapper.row(from: insertedMessage))

                    let result = await sendService.sendText(message: insertedMessage)
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

                    try await repository.clearDraft(conversationID: conversationID, userID: userID)
                    try await updateSendStatus(
                        messageID: insertedMessage.id,
                        status: finalStatus,
                        ack: ack,
                        pendingJob: finalStatus == .failed ? try makeResendJobInput(for: insertedMessage, failureReason: result.failureReason) : nil
                    )

                    if let updatedMessage = try await repository.message(messageID: insertedMessage.id) {
                        continuation.yield(rowMapper.row(from: updatedMessage))
                    }
                    continuation.finish()
                } catch {
                    logger.error("Chat sendText failed total=\(AppLogger.elapsedMilliseconds(since: startUptime)) error=\(String(describing: type(of: error)))")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func updateSendStatus(
        messageID: MessageID,
        status: MessageSendStatus,
        ack: MessageSendAck?,
        pendingJob: PendingJobInput?
    ) async throws {
        if let recoveryRepository {
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

    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }
}
