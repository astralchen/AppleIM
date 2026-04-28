//
//  ChatUseCase.swift
//  AppleIM
//

import Foundation

protocol ChatUseCase: Sendable {
    func loadInitialMessages() async throws -> [ChatMessageRowState]
    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error>
}

nonisolated struct LocalChatUseCase: ChatUseCase {
    private let userID: UserID
    private let conversationID: ConversationID
    private let repository: any MessageRepository
    private let sendService: any MessageSendService

    init(
        userID: UserID,
        conversationID: ConversationID,
        repository: any MessageRepository,
        sendService: any MessageSendService
    ) {
        self.userID = userID
        self.conversationID = conversationID
        self.repository = repository
        self.sendService = sendService
    }

    func loadInitialMessages() async throws -> [ChatMessageRowState] {
        let messages = try await repository.listMessages(
            conversationID: conversationID,
            limit: 50,
            beforeSortSeq: nil
        )

        return messages
            .sorted { $0.sortSequence < $1.sortSequence }
            .map { Self.row(from: $0, currentUserID: userID) }
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
                    let finalStatus: MessageSendStatus = result == .success ? .success : .failed
                    try await repository.updateMessageSendStatus(
                        messageID: insertedMessage.id,
                        status: finalStatus
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

    nonisolated private static func row(from message: StoredMessage, currentUserID: UserID) -> ChatMessageRowState {
        ChatMessageRowState(
            id: message.id,
            text: message.text ?? "",
            timeText: timeText(from: message.localTime),
            statusText: statusText(for: message),
            isOutgoing: message.senderID == currentUserID
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

    func loadInitialMessages() async throws -> [ChatMessageRowState] {
        let repository = try await storeProvider.repository()
        let useCase = LocalChatUseCase(
            userID: userID,
            conversationID: conversationID,
            repository: repository,
            sendService: sendService
        )
        return try await useCase.loadInitialMessages()
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
}
