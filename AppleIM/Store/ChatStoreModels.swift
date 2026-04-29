//
//  ChatStoreModels.swift
//  AppleIM
//

import Foundation

nonisolated enum ChatStoreError: Error, Equatable, Sendable {
    case missingColumn(String)
    case invalidConversationType(Int)
    case invalidMessageType(Int)
    case invalidMessageDirection(Int)
    case invalidMessageSendStatus(Int)
    case invalidPendingJobType(Int)
    case invalidPendingJobStatus(Int)
    case messageNotFound(MessageID)
    case messageCannotBeResent(MessageID)
}

nonisolated struct ConversationRecord: Equatable, Sendable {
    let id: ConversationID
    let userID: UserID
    let type: ConversationType
    let targetID: String
    let title: String
    let avatarURL: String?
    let lastMessageID: MessageID?
    let lastMessageTime: Int64?
    let lastMessageDigest: String
    let unreadCount: Int
    let draftText: String?
    let isPinned: Bool
    let isMuted: Bool
    let isHidden: Bool
    let sortTimestamp: Int64
    let updatedAt: Int64
    let createdAt: Int64
}

nonisolated struct OutgoingTextMessageInput: Equatable, Sendable {
    let userID: UserID
    let conversationID: ConversationID
    let senderID: UserID
    let text: String
    let localTime: Int64
    let messageID: MessageID?
    let clientMessageID: String?
    let sortSequence: Int64?

    init(
        userID: UserID,
        conversationID: ConversationID,
        senderID: UserID,
        text: String,
        localTime: Int64,
        messageID: MessageID? = nil,
        clientMessageID: String? = nil,
        sortSequence: Int64? = nil
    ) {
        self.userID = userID
        self.conversationID = conversationID
        self.senderID = senderID
        self.text = text
        self.localTime = localTime
        self.messageID = messageID
        self.clientMessageID = clientMessageID
        self.sortSequence = sortSequence
    }
}

nonisolated struct StoredImageContent: Equatable, Sendable {
    let mediaID: String
    let localPath: String
    let thumbnailPath: String
    let width: Int
    let height: Int
    let sizeBytes: Int64
    let format: String
}

nonisolated struct OutgoingImageMessageInput: Equatable, Sendable {
    let userID: UserID
    let conversationID: ConversationID
    let senderID: UserID
    let image: StoredImageContent
    let localTime: Int64
    let messageID: MessageID?
    let clientMessageID: String?
    let sortSequence: Int64?

    init(
        userID: UserID,
        conversationID: ConversationID,
        senderID: UserID,
        image: StoredImageContent,
        localTime: Int64,
        messageID: MessageID? = nil,
        clientMessageID: String? = nil,
        sortSequence: Int64? = nil
    ) {
        self.userID = userID
        self.conversationID = conversationID
        self.senderID = senderID
        self.image = image
        self.localTime = localTime
        self.messageID = messageID
        self.clientMessageID = clientMessageID
        self.sortSequence = sortSequence
    }
}

nonisolated enum PendingJobType: Int, Codable, Sendable {
    case messageResend = 1
    case imageUpload = 2
    case videoUpload = 3
    case fileUpload = 4
    case mediaDownload = 5
    case thumbnailGeneration = 6
    case searchIndexRepair = 7
    case messageCompensationSync = 8
}

nonisolated enum PendingJobStatus: Int, Codable, Sendable {
    case pending = 0
    case running = 1
    case success = 2
    case failed = 3
    case cancelled = 4
}

nonisolated struct PendingJob: Identifiable, Equatable, Sendable {
    let id: String
    let userID: UserID
    let type: PendingJobType
    let bizKey: String?
    let payloadJSON: String
    let status: PendingJobStatus
    let retryCount: Int
    let maxRetryCount: Int
    let nextRetryAt: Int64?
    let updatedAt: Int64
    let createdAt: Int64
}

nonisolated struct PendingJobInput: Equatable, Sendable {
    let id: String
    let userID: UserID
    let type: PendingJobType
    let bizKey: String?
    let payloadJSON: String
    let maxRetryCount: Int
    let nextRetryAt: Int64?

    init(
        id: String,
        userID: UserID,
        type: PendingJobType,
        bizKey: String?,
        payloadJSON: String,
        maxRetryCount: Int = 3,
        nextRetryAt: Int64? = nil
    ) {
        self.id = id
        self.userID = userID
        self.type = type
        self.bizKey = bizKey
        self.payloadJSON = payloadJSON
        self.maxRetryCount = maxRetryCount
        self.nextRetryAt = nextRetryAt
    }
}

protocol ConversationRepository: Sendable {
    func listConversations(for userID: UserID) async throws -> [Conversation]
    func upsertConversation(_ record: ConversationRecord) async throws
    func markConversationRead(conversationID: ConversationID, userID: UserID) async throws
}

protocol MessageRepository: Sendable {
    func insertOutgoingTextMessage(_ input: OutgoingTextMessageInput) async throws -> StoredMessage
    func insertOutgoingImageMessage(_ input: OutgoingImageMessageInput) async throws -> StoredMessage
    func listMessages(conversationID: ConversationID, limit: Int, beforeSortSeq: Int64?) async throws -> [StoredMessage]
    func message(messageID: MessageID) async throws -> StoredMessage?
    func updateMessageSendStatus(messageID: MessageID, status: MessageSendStatus, ack: MessageSendAck?) async throws
    func resendTextMessage(messageID: MessageID) async throws -> StoredMessage
    func markMessageDeleted(messageID: MessageID, userID: UserID) async throws
    func revokeMessage(messageID: MessageID, userID: UserID, replacementText: String) async throws -> StoredMessage
    func saveDraft(conversationID: ConversationID, userID: UserID, text: String) async throws
    func draft(conversationID: ConversationID, userID: UserID) async throws -> String?
    func clearDraft(conversationID: ConversationID, userID: UserID) async throws
}

protocol MessageSendRecoveryRepository: Sendable {
    func updateMessageSendStatus(
        messageID: MessageID,
        status: MessageSendStatus,
        ack: MessageSendAck?,
        pendingJob: PendingJobInput?
    ) async throws
}

protocol PendingJobRepository: Sendable {
    func upsertPendingJob(_ input: PendingJobInput) async throws -> PendingJob
    func pendingJob(id: String) async throws -> PendingJob?
    func recoverablePendingJobs(userID: UserID, now: Int64) async throws -> [PendingJob]
    func schedulePendingJobRetry(jobID: String, nextRetryAt: Int64) async throws
    func updatePendingJobStatus(jobID: String, status: PendingJobStatus, nextRetryAt: Int64?) async throws
}
