//
//  IMModels.swift
//  AppleIM
//

import Foundation

enum ConversationType: Int, Codable, Sendable {
    case single = 1
    case group = 2
    case system = 3
    case service = 4
}

enum MessageType: Int, Codable, Sendable {
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

enum MessageSendStatus: Int, Codable, Sendable {
    case pending = 0
    case sending = 1
    case success = 2
    case failed = 3
}

struct Conversation: Identifiable, Equatable, Sendable {
    let id: ConversationID
    let type: ConversationType
    let title: String
    let lastMessageDigest: String
    let lastMessageTimeText: String
    let unreadCount: Int
    let isPinned: Bool
    let isMuted: Bool
}
