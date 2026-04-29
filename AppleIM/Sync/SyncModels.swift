//
//  SyncModels.swift
//  AppleIM
//

import Foundation

nonisolated struct SyncCheckpoint: Equatable, Sendable {
    let bizKey: String
    let cursor: String?
    let sequence: Int64?
    let updatedAt: Int64
}

nonisolated struct IncomingSyncMessage: Equatable, Sendable {
    let messageID: MessageID
    let conversationID: ConversationID
    let senderID: UserID
    let clientMessageID: String?
    let serverMessageID: String?
    let sequence: Int64
    let text: String
    let serverTime: Int64
    let localTime: Int64
    let direction: MessageDirection
    let conversationTitle: String?

    init(
        messageID: MessageID,
        conversationID: ConversationID,
        senderID: UserID,
        clientMessageID: String? = nil,
        serverMessageID: String?,
        sequence: Int64,
        text: String,
        serverTime: Int64,
        localTime: Int64? = nil,
        direction: MessageDirection = .incoming,
        conversationTitle: String? = nil
    ) {
        self.messageID = messageID
        self.conversationID = conversationID
        self.senderID = senderID
        self.clientMessageID = clientMessageID
        self.serverMessageID = serverMessageID
        self.sequence = sequence
        self.text = text
        self.serverTime = serverTime
        self.localTime = localTime ?? serverTime
        self.direction = direction
        self.conversationTitle = conversationTitle
    }
}

nonisolated struct SyncBatch: Equatable, Sendable {
    let bizKey: String
    let messages: [IncomingSyncMessage]
    let nextCursor: String?
    let nextSequence: Int64?
    let hasMore: Bool

    init(
        bizKey: String = SyncEngineActor.messageBizKey,
        messages: [IncomingSyncMessage],
        nextCursor: String?,
        nextSequence: Int64?,
        hasMore: Bool = false
    ) {
        self.bizKey = bizKey
        self.messages = messages
        self.nextCursor = nextCursor
        self.nextSequence = nextSequence
        self.hasMore = hasMore
    }
}

nonisolated struct SyncApplyResult: Equatable, Sendable {
    let fetchedCount: Int
    let insertedCount: Int
    let skippedDuplicateCount: Int
    let checkpoint: SyncCheckpoint
}

nonisolated struct SyncResult: Equatable, Sendable {
    let previousCheckpoint: SyncCheckpoint?
    let fetchedCount: Int
    let insertedCount: Int
    let skippedDuplicateCount: Int
    let checkpoint: SyncCheckpoint
}

nonisolated struct SyncRunResult: Equatable, Sendable {
    let batchCount: Int
    let fetchedCount: Int
    let insertedCount: Int
    let skippedDuplicateCount: Int
    let initialCheckpoint: SyncCheckpoint?
    let finalCheckpoint: SyncCheckpoint
}

nonisolated enum SyncEngineError: Error, Equatable, Sendable {
    case invalidMaxBatches
    case exceededMaxBatches(Int)
}

protocol SyncStore: Sendable {
    func syncCheckpoint(for bizKey: String) async throws -> SyncCheckpoint?
    func applyIncomingSyncBatch(_ batch: SyncBatch, userID: UserID) async throws -> SyncApplyResult
}
