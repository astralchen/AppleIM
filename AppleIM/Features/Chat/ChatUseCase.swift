//
//  ChatUseCase.swift
//  AppleIM
//

import Foundation

nonisolated struct ChatMessagePage: Equatable, Sendable {
    let rows: [ChatMessageRowState]
    let hasMore: Bool
    let nextBeforeSortSequence: Int64?
}

nonisolated private struct MessageResendPendingJobPayload: Codable, Equatable, Sendable {
    let messageID: String
    let conversationID: String
    let clientMessageID: String
    let lastFailureReason: MessageSendFailureReason?
}

nonisolated struct PendingMessageRetryRunResult: Equatable, Sendable {
    let scannedJobCount: Int
    let attemptedCount: Int
    let successCount: Int
    let rescheduledCount: Int
    let exhaustedCount: Int
}

protocol ChatUseCase: Sendable {
    func loadInitialMessages() async throws -> ChatMessagePage
    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage
    func loadDraft() async throws -> String?
    func saveDraft(_ text: String) async throws
    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error>
    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error>
    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error>
    func delete(messageID: MessageID) async throws
    func revoke(messageID: MessageID) async throws
}

nonisolated struct LocalChatUseCase: ChatUseCase {
    private static let initialMessageLimit = 50

    private let userID: UserID
    private let conversationID: ConversationID
    private let repository: any MessageRepository
    private let conversationRepository: (any ConversationRepository)?
    private let pendingJobRepository: (any PendingJobRepository)?
    private let sendService: any MessageSendService
    private let mediaFileStore: (any MediaFileStoring)?
    private let retryPolicy: MessageRetryPolicy

    init(
        userID: UserID,
        conversationID: ConversationID,
        repository: any MessageRepository,
        conversationRepository: (any ConversationRepository)? = nil,
        pendingJobRepository: (any PendingJobRepository)? = nil,
        sendService: any MessageSendService,
        mediaFileStore: (any MediaFileStoring)? = nil,
        retryPolicy: MessageRetryPolicy = MessageRetryPolicy()
    ) {
        self.userID = userID
        self.conversationID = conversationID
        self.repository = repository
        self.conversationRepository = conversationRepository
        self.pendingJobRepository = pendingJobRepository
        self.sendService = sendService
        self.mediaFileStore = mediaFileStore
        self.retryPolicy = retryPolicy
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        try await conversationRepository?.markConversationRead(conversationID: conversationID, userID: userID)

        return try await loadMessagePage(limit: Self.initialMessageLimit, beforeSortSequence: nil)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        try await loadMessagePage(limit: limit, beforeSortSequence: beforeSortSequence)
    }

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
            .map { Self.row(from: $0, currentUserID: userID) }

        return ChatMessagePage(
            rows: rows,
            hasMore: messages.count > boundedLimit,
            nextBeforeSortSequence: rows.first?.sortSequence
        )
    }

    func loadDraft() async throws -> String? {
        try await repository.draft(conversationID: conversationID, userID: userID)
    }

    func saveDraft(_ text: String) async throws {
        try await repository.saveDraft(conversationID: conversationID, userID: userID, text: text)
    }

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return AsyncThrowingStream { continuation in
            guard !trimmedText.isEmpty else {
                continuation.finish()
                return
            }

            let task = Task {
                do {
                    let now = Int64(Date().timeIntervalSince1970)
                    try await repository.clearDraft(conversationID: conversationID, userID: userID)
                    let insertedMessage = try await repository.insertOutgoingTextMessage(
                        OutgoingTextMessageInput(
                            userID: userID,
                            conversationID: conversationID,
                            senderID: userID,
                            text: trimmedText,
                            localTime: now,
                            sortSequence: now
                        )
                    )

                    continuation.yield(Self.row(from: insertedMessage, currentUserID: userID))

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
                        continuation.yield(Self.row(from: updatedMessage, currentUserID: userID))
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

                    continuation.yield(Self.row(from: insertedMessage, currentUserID: userID))
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

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let sendingMessage = try await repository.resendTextMessage(messageID: messageID)
                    continuation.yield(Self.row(from: sendingMessage, currentUserID: userID))

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
                        continuation.yield(Self.row(from: updatedMessage, currentUserID: userID))
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

    func delete(messageID: MessageID) async throws {
        try await repository.markMessageDeleted(messageID: messageID, userID: userID)
    }

    func revoke(messageID: MessageID) async throws {
        _ = try await repository.revokeMessage(
            messageID: messageID,
            userID: userID,
            replacementText: "你撤回了一条消息"
        )
    }

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

    private func makeResendJobInput(
        for message: StoredMessage,
        failureReason: MessageSendFailureReason?
    ) throws -> PendingJobInput? {
        guard pendingJobRepository != nil, let clientMessageID = message.clientMessageID else {
            return nil
        }

        let payload = MessageResendPendingJobPayload(
            messageID: message.id.rawValue,
            conversationID: message.conversationID.rawValue,
            clientMessageID: clientMessageID,
            lastFailureReason: failureReason
        )
        let payloadData = try JSONEncoder().encode(payload)

        guard let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            return nil
        }

        return PendingJobInput(
            id: Self.resendJobID(clientMessageID: clientMessageID),
            userID: userID,
            type: .messageResend,
            bizKey: clientMessageID,
            payloadJSON: payloadJSON,
            maxRetryCount: retryPolicy.maxRetryCount,
            nextRetryAt: retryPolicy.nextRetryAt(now: Self.currentTimestamp(), retryCount: 0)
        )
    }

    private func markResendJobSuccess(for message: StoredMessage) async throws {
        guard let pendingJobRepository, let clientMessageID = message.clientMessageID else {
            return
        }

        try await pendingJobRepository.updatePendingJobStatus(
            jobID: Self.resendJobID(clientMessageID: clientMessageID),
            status: .success,
            nextRetryAt: nil
        )
    }

    private static func resendJobID(clientMessageID: String) -> String {
        "message_resend_\(clientMessageID)"
    }

    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }

    nonisolated private static func row(from message: StoredMessage, currentUserID: UserID) -> ChatMessageRowState {
        let isOutgoing = message.senderID == currentUserID
        let isRevoked = message.isRevoked

        return ChatMessageRowState(
            id: message.id,
            text: isRevoked ? (message.revokeReplacementText ?? "你撤回了一条消息") : (message.text ?? ""),
            imageThumbnailPath: isRevoked ? nil : message.image?.thumbnailPath,
            sortSequence: message.sortSequence,
            timeText: timeText(from: message.localTime),
            statusText: isRevoked ? nil : statusText(for: message),
            isOutgoing: isOutgoing,
            canRetry: isOutgoing && message.type == .text && message.sendStatus == .failed && !isRevoked,
            canDelete: !message.isDeleted,
            canRevoke: isOutgoing && message.type == .text && message.sendStatus == .success && !isRevoked,
            isRevoked: isRevoked
        )
    }

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

    nonisolated private static func timeText(from timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

nonisolated struct PendingMessageRetryRunner: Sendable {
    private let userID: UserID
    private let messageRepository: any MessageRepository
    private let pendingJobRepository: any PendingJobRepository
    private let sendService: any MessageSendService
    private let retryPolicy: MessageRetryPolicy

    init(
        userID: UserID,
        messageRepository: any MessageRepository,
        pendingJobRepository: any PendingJobRepository,
        sendService: any MessageSendService,
        retryPolicy: MessageRetryPolicy = MessageRetryPolicy()
    ) {
        self.userID = userID
        self.messageRepository = messageRepository
        self.pendingJobRepository = pendingJobRepository
        self.sendService = sendService
        self.retryPolicy = retryPolicy
    }

    func runDueJobs(now: Int64 = Int64(Date().timeIntervalSince1970)) async throws -> PendingMessageRetryRunResult {
        let jobs = try await pendingJobRepository.recoverablePendingJobs(userID: userID, now: now)
        var attemptedCount = 0
        var successCount = 0
        var rescheduledCount = 0
        var exhaustedCount = 0

        for job in jobs where job.type == .messageResend {
            guard job.retryCount < job.maxRetryCount else {
                exhaustedCount += 1
                try await pendingJobRepository.updatePendingJobStatus(jobID: job.id, status: .failed, nextRetryAt: nil)
                continue
            }

            let payload = try JSONDecoder().decode(MessageResendPendingJobPayload.self, from: Data(job.payloadJSON.utf8))
            let messageID = MessageID(rawValue: payload.messageID)

            guard let message = try await messageRepository.message(messageID: messageID) else {
                exhaustedCount += 1
                try await pendingJobRepository.updatePendingJobStatus(jobID: job.id, status: .cancelled, nextRetryAt: nil)
                continue
            }

            attemptedCount += 1
            try await pendingJobRepository.updatePendingJobStatus(jobID: job.id, status: .running, nextRetryAt: nil)
            try await messageRepository.updateMessageSendStatus(messageID: messageID, status: .sending, ack: nil)

            let result = await sendService.sendText(message: message)
            switch result {
            case let .success(ack):
                successCount += 1
                try await messageRepository.updateMessageSendStatus(messageID: messageID, status: .success, ack: ack)
                try await pendingJobRepository.updatePendingJobStatus(jobID: job.id, status: .success, nextRetryAt: nil)
            case .failure:
                try await messageRepository.updateMessageSendStatus(messageID: messageID, status: .failed, ack: nil)

                if job.retryCount + 1 >= job.maxRetryCount {
                    exhaustedCount += 1
                    try await pendingJobRepository.updatePendingJobStatus(jobID: job.id, status: .failed, nextRetryAt: nil)
                } else {
                    rescheduledCount += 1
                    let nextRetryAt = retryPolicy.nextRetryAt(now: now, retryCount: job.retryCount + 1)
                    try await pendingJobRepository.schedulePendingJobRetry(jobID: job.id, nextRetryAt: nextRetryAt)
                }
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
}

private extension MessageSendResult {
    var failureReason: MessageSendFailureReason? {
        guard case let .failure(reason) = self else {
            return nil
        }

        return reason
    }
}

nonisolated struct StoreBackedChatUseCase: ChatUseCase {
    private let userID: UserID
    private let conversationID: ConversationID
    private let storeProvider: ChatStoreProvider
    private let sendService: any MessageSendService
    private let mediaFileStore: any MediaFileStoring

    init(
        userID: UserID,
        conversationID: ConversationID,
        storeProvider: ChatStoreProvider,
        sendService: any MessageSendService,
        mediaFileStore: any MediaFileStoring
    ) {
        self.userID = userID
        self.conversationID = conversationID
        self.storeProvider = storeProvider
        self.sendService = sendService
        self.mediaFileStore = mediaFileStore
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        let repository = try await storeProvider.repository()
        let useCase = LocalChatUseCase(
            userID: userID,
            conversationID: conversationID,
            repository: repository,
            conversationRepository: repository,
            pendingJobRepository: repository,
            sendService: sendService,
            mediaFileStore: mediaFileStore
        )
        return try await useCase.loadInitialMessages()
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        let repository = try await storeProvider.repository()
        let useCase = LocalChatUseCase(
            userID: userID,
            conversationID: conversationID,
            repository: repository,
            conversationRepository: repository,
            pendingJobRepository: repository,
            sendService: sendService,
            mediaFileStore: mediaFileStore
        )
        return try await useCase.loadOlderMessages(beforeSortSequence: beforeSortSequence, limit: limit)
    }

    func loadDraft() async throws -> String? {
        let repository = try await storeProvider.repository()
        let useCase = LocalChatUseCase(
            userID: userID,
            conversationID: conversationID,
            repository: repository,
            conversationRepository: repository,
            pendingJobRepository: repository,
            sendService: sendService,
            mediaFileStore: mediaFileStore
        )
        return try await useCase.loadDraft()
    }

    func saveDraft(_ text: String) async throws {
        let repository = try await storeProvider.repository()
        let useCase = LocalChatUseCase(
            userID: userID,
            conversationID: conversationID,
            repository: repository,
            conversationRepository: repository,
            pendingJobRepository: repository,
            sendService: sendService,
            mediaFileStore: mediaFileStore
        )
        try await useCase.saveDraft(text)
    }

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let repository = try await storeProvider.repository()
                    let useCase = LocalChatUseCase(
                        userID: userID,
                        conversationID: conversationID,
                        repository: repository,
                        conversationRepository: repository,
                        pendingJobRepository: repository,
                        sendService: sendService,
                        mediaFileStore: mediaFileStore
                    )

                    for try await row in useCase.sendText(text) {
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

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let repository = try await storeProvider.repository()
                    let useCase = LocalChatUseCase(
                        userID: userID,
                        conversationID: conversationID,
                        repository: repository,
                        conversationRepository: repository,
                        pendingJobRepository: repository,
                        sendService: sendService,
                        mediaFileStore: mediaFileStore
                    )

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

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let repository = try await storeProvider.repository()
                    let useCase = LocalChatUseCase(
                        userID: userID,
                        conversationID: conversationID,
                        repository: repository,
                        conversationRepository: repository,
                        pendingJobRepository: repository,
                        sendService: sendService,
                        mediaFileStore: mediaFileStore
                    )

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

    func delete(messageID: MessageID) async throws {
        let repository = try await storeProvider.repository()
        let useCase = LocalChatUseCase(
            userID: userID,
            conversationID: conversationID,
            repository: repository,
            conversationRepository: repository,
            pendingJobRepository: repository,
            sendService: sendService,
            mediaFileStore: mediaFileStore
        )
        try await useCase.delete(messageID: messageID)
    }

    func revoke(messageID: MessageID) async throws {
        let repository = try await storeProvider.repository()
        let useCase = LocalChatUseCase(
            userID: userID,
            conversationID: conversationID,
            repository: repository,
            conversationRepository: repository,
            pendingJobRepository: repository,
            sendService: sendService,
            mediaFileStore: mediaFileStore
        )
        try await useCase.revoke(messageID: messageID)
    }
}
