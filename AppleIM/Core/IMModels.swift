//
//  IMModels.swift
//  AppleIM
//

import Foundation

nonisolated enum ConversationType: Int, Codable, Sendable {
    case single = 1
    case group = 2
    case system = 3
    case service = 4
}

nonisolated enum MessageType: Int, Codable, Sendable {
    case text = 1
    case image = 2
    case voice = 3
    case video = 4
    case file = 5
    case system = 8
    case revoked = 9
    case emoji = 10
    case quote = 11
}

nonisolated enum MessageSendStatus: Int, Codable, Sendable {
    case pending = 0
    case sending = 1
    case success = 2
    case failed = 3
}

nonisolated enum MessageDirection: Int, Codable, Sendable {
    case outgoing = 1
    case incoming = 2
}

nonisolated struct Conversation: Identifiable, Equatable, Sendable {
    let id: ConversationID
    let type: ConversationType
    let title: String
    let lastMessageDigest: String
    let lastMessageTimeText: String
    let unreadCount: Int
    let isPinned: Bool
    let isMuted: Bool
    let draftText: String?
}

nonisolated struct StoredMessage: Identifiable, Equatable, Sendable {
    let id: MessageID
    let conversationID: ConversationID
    let senderID: UserID
    let clientMessageID: String?
    let serverMessageID: String?
    let sequence: Int64?
    let type: MessageType
    let direction: MessageDirection
    let sendStatus: MessageSendStatus
    let serverTime: Int64?
    let isRevoked: Bool
    let isDeleted: Bool
    let revokeReplacementText: String?
    let text: String?
    let sortSequence: Int64
    let localTime: Int64
}
