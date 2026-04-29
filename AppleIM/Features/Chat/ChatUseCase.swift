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

protocol ChatUseCase: Sendable {
    func loadInitialMessages() async throws -> ChatMessagePage
    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage
    func loadDraft() async throws -> String?
    func saveDraft(_ text: String) async throws
    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error>
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
    private let sendService: any MessageSendService

    init(
        userID: UserID,
        conversationID: ConversationID,
        repository: any MessageRepository,
        conversationRepository: (any ConversationRepository)? = nil,
        sendService: any MessageSendService
    ) {
        self.userID = userID
        self.conversationID = conversationID
        self.repository = repository
        self.conversationRepository = conversationRepository
        self.sendService = sendService
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

                    try await repository.updateMessageSendStatus(
                        messageID: insertedMessage.id,
                        status: finalStatus,
                        ack: ack
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
                    case .failure:
                        finalStatus = .failed
                        ack = nil
                    }

                    try await repository.updateMessageSendStatus(
                        messageID: sendingMessage.id,
                        status: finalStatus,
                        ack: ack
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

    nonisolated private static func row(from message: StoredMessage, currentUserID: UserID) -> ChatMessageRowState {
        let isOutgoing = message.senderID == currentUserID
        let isRevoked = message.isRevoked

        return ChatMessageRowState(
            id: message.id,
            text: isRevoked ? (message.revokeReplacementText ?? "你撤回了一条消息") : (message.text ?? ""),
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

nonisolated struct StoreBackedChatUseCase: ChatUseCase {
    private let userID: UserID
    private let conversationID: ConversationID
    private let storeProvider: ChatStoreProvider
    private let sendService: any MessageSendService

    init(
        userID: UserID,
        conversationID: ConversationID,
        storeProvider: ChatStoreProvider,
        sendService: any MessageSendService
    ) {
        self.userID = userID
        self.conversationID = conversationID
        self.storeProvider = storeProvider
        self.sendService = sendService
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        let repository = try await storeProvider.repository()
        let useCase = LocalChatUseCase(
            userID: userID,
            conversationID: conversationID,
            repository: repository,
            conversationRepository: repository,
            sendService: sendService
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
            sendService: sendService
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
            sendService: sendService
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
            sendService: sendService
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
                        sendService: sendService
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
                        sendService: sendService
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
            sendService: sendService
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
            sendService: sendService
        )
        try await useCase.revoke(messageID: messageID)
    }
}
