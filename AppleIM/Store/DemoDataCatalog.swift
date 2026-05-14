//
//  DemoDataCatalog.swift
//  AppleIM
//
//  本地演示聊天数据文件读取
//

import Foundation

/// 演示聊天数据目录协议。
protocol DemoDataCatalog: Sendable {
    /// 读取指定账号的演示聊天数据。
    nonisolated func demoData(for accountID: UserID, now: Int64) async throws -> DemoDataSeedData
}

/// 演示聊天数据目录错误。
nonisolated enum DemoDataCatalogError: Error, Equatable, Sendable {
    /// 演示数据文件缺失。
    case resourceMissing
    /// 演示数据文件为空。
    case empty
    /// 无效会话类型。
    case invalidConversationType(String)
    /// 无效消息方向。
    case invalidMessageDirection(String)
    /// 无效已读状态。
    case invalidMessageReadStatus(String)
    /// 无效群成员角色。
    case invalidGroupMemberRole(String)
}

/// 从 JSON 转换后的演示聊天数据。
nonisolated struct DemoDataSeedData: Equatable, Sendable {
    let conversations: [ConversationRecord]
    let messages: [InitialTextMessageInput]
    let groupMembers: [GroupMember]
    let groupAnnouncements: [DemoDataSeedGroupAnnouncement]

    static let empty = DemoDataSeedData(
        conversations: [],
        messages: [],
        groupMembers: [],
        groupAnnouncements: []
    )
}

/// 演示群公告输入。
nonisolated struct DemoDataSeedGroupAnnouncement: Equatable, Sendable {
    let conversationID: ConversationID
    let text: String
}

/// Bundle 演示聊天数据目录实现。
nonisolated struct BundleDemoDataCatalog: DemoDataCatalog {
    private let resourceURL: URL?

    init(bundle: Bundle = .main, resourceName: String = "mock_demo_data") {
        self.resourceURL = bundle.url(forResource: resourceName, withExtension: "json")
    }

    init(resourceURL: URL?) {
        self.resourceURL = resourceURL
    }

    nonisolated func demoData(for accountID: UserID, now: Int64) async throws -> DemoDataSeedData {
        guard let resourceURL else {
            throw DemoDataCatalogError.resourceMissing
        }

        let data = try Data(contentsOf: resourceURL)
        let entries = try JSONDecoder().decode([MockDemoDataAccountEntry].self, from: data)
        guard !entries.isEmpty else {
            throw DemoDataCatalogError.empty
        }
        guard let account = entries.first(where: { $0.accountID == accountID.rawValue }) else {
            return .empty
        }

        let messageEntries = account.messages + account.messageBatches.flatMap { $0.makeMessages(accountID: accountID.rawValue) }
        let messages = try messageEntries
            .map { try $0.makeInput(userID: accountID, now: now) }
            .sorted { $0.sortSequence < $1.sortSequence }
        let latestMessageByConversation = Dictionary(
            grouping: messages,
            by: \.conversationID
        ).compactMapValues { groupedMessages in
            groupedMessages.max { $0.sortSequence < $1.sortSequence }
        }
        let conversations = try account.conversations.map { entry in
            try entry.makeRecord(
                userID: accountID,
                now: now,
                latestMessage: latestMessageByConversation[ConversationID(rawValue: entry.id)]
            )
        }
        let groupMembers = try account.groupMembers.map { try $0.makeMember(now: now) }
        let groupAnnouncements = account.groupAnnouncements.map {
            DemoDataSeedGroupAnnouncement(conversationID: ConversationID(rawValue: $0.conversationID), text: $0.text)
        }

        return DemoDataSeedData(
            conversations: conversations,
            messages: messages,
            groupMembers: groupMembers,
            groupAnnouncements: groupAnnouncements
        )
    }
}

nonisolated private struct MockDemoDataAccountEntry: Decodable, Sendable {
    let accountID: String
    let conversations: [MockDemoConversationEntry]
    let messages: [MockDemoMessageEntry]
    let messageBatches: [MockDemoMessageBatchEntry]
    let groupMembers: [MockDemoGroupMemberEntry]
    let groupAnnouncements: [MockDemoGroupAnnouncementEntry]

    enum CodingKeys: String, CodingKey {
        case accountID
        case conversations
        case messages
        case messageBatches
        case groupMembers
        case groupAnnouncements
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accountID = try container.decode(String.self, forKey: .accountID)
        self.conversations = try container.decodeIfPresent([MockDemoConversationEntry].self, forKey: .conversations) ?? []
        self.messages = try container.decodeIfPresent([MockDemoMessageEntry].self, forKey: .messages) ?? []
        self.messageBatches = try container.decodeIfPresent([MockDemoMessageBatchEntry].self, forKey: .messageBatches) ?? []
        self.groupMembers = try container.decodeIfPresent([MockDemoGroupMemberEntry].self, forKey: .groupMembers) ?? []
        self.groupAnnouncements = try container.decodeIfPresent([MockDemoGroupAnnouncementEntry].self, forKey: .groupAnnouncements) ?? []
    }
}

nonisolated private struct MockDemoConversationEntry: Decodable, Sendable {
    let id: String
    let type: String
    let targetID: String
    let title: String
    let avatarURL: String?
    let unreadCount: Int
    let draftText: String?
    let isPinned: Bool
    let isMuted: Bool
    let isHidden: Bool
    let createdAtOffsetSeconds: Int64?
    let updatedAtOffsetSeconds: Int64?
    let lastMessageID: String?
    let lastMessageTimeOffsetSeconds: Int64?
    let lastMessageDigest: String?
    let sortTimestampOffsetSeconds: Int64?

    func makeRecord(
        userID: UserID,
        now: Int64,
        latestMessage: InitialTextMessageInput?
    ) throws -> ConversationRecord {
        let conversationType = try Self.conversationType(from: type)
        let createdAt = now + (createdAtOffsetSeconds ?? 0)
        let updatedAt = now + (updatedAtOffsetSeconds ?? createdAtOffsetSeconds ?? 0)
        let fallbackLastMessageTime = lastMessageTimeOffsetSeconds.map { now + $0 }
        let fallbackSortTimestamp = sortTimestampOffsetSeconds.map { now + $0 }

        return ConversationRecord(
            id: ConversationID(rawValue: id),
            userID: userID,
            type: conversationType,
            targetID: targetID,
            title: title,
            avatarURL: avatarURL,
            lastMessageID: latestMessage?.messageID ?? lastMessageID.map(MessageID.init(rawValue:)),
            lastMessageTime: latestMessage?.localTime ?? fallbackLastMessageTime,
            lastMessageDigest: latestMessage?.text ?? lastMessageDigest ?? "",
            unreadCount: unreadCount,
            draftText: draftText,
            isPinned: isPinned,
            isMuted: isMuted,
            isHidden: isHidden,
            sortTimestamp: latestMessage?.sortSequence ?? fallbackSortTimestamp ?? updatedAt,
            updatedAt: latestMessage?.localTime ?? updatedAt,
            createdAt: createdAt
        )
    }

    private static func conversationType(from value: String) throws -> ConversationType {
        switch value {
        case "single":
            return .single
        case "group":
            return .group
        case "system":
            return .system
        case "service":
            return .service
        default:
            throw DemoDataCatalogError.invalidConversationType(value)
        }
    }
}

nonisolated private struct MockDemoMessageEntry: Decodable, Sendable {
    let conversationID: String
    let senderID: String
    let text: String
    let localTimeOffsetSeconds: Int64
    let messageID: String
    let clientMessageID: String?
    let serverMessageID: String?
    let sequenceOffsetSeconds: Int64?
    let direction: String
    let readStatus: String
    let sortSequenceOffsetSeconds: Int64

    func makeInput(userID: UserID, now: Int64) throws -> InitialTextMessageInput {
        InitialTextMessageInput(
            userID: userID,
            conversationID: ConversationID(rawValue: conversationID),
            senderID: UserID(rawValue: senderID),
            text: text,
            localTime: now + localTimeOffsetSeconds,
            messageID: MessageID(rawValue: messageID),
            clientMessageID: clientMessageID,
            serverMessageID: serverMessageID,
            sequence: sequenceOffsetSeconds.map { now + $0 },
            direction: try Self.messageDirection(from: direction),
            readStatus: try Self.messageReadStatus(from: readStatus),
            sortSequence: now + sortSequenceOffsetSeconds
        )
    }

    private static func messageDirection(from value: String) throws -> MessageDirection {
        switch value {
        case "outgoing":
            return .outgoing
        case "incoming":
            return .incoming
        default:
            throw DemoDataCatalogError.invalidMessageDirection(value)
        }
    }

    private static func messageReadStatus(from value: String) throws -> MessageReadStatus {
        switch value {
        case "read":
            return .read
        case "unread":
            return .unread
        default:
            throw DemoDataCatalogError.invalidMessageReadStatus(value)
        }
    }
}

nonisolated private struct MockDemoMessageBatchEntry: Decodable, Sendable {
    let conversationID: String
    let incomingSenderID: String
    let outgoingSenderID: String?
    let count: Int
    let textPrefix: String
    let messageIDPrefix: String
    let serverMessageIDPrefix: String?
    let startOffsetSeconds: Int64
    let intervalSeconds: Int64
    let outgoingEvery: Int?

    func makeMessages(accountID: String) -> [MockDemoMessageEntry] {
        guard count > 0 else { return [] }

        return (1...count).map { index in
            let direction = outgoingEvery.map { $0 > 0 && index.isMultiple(of: $0) } == true ? "outgoing" : "incoming"
            let senderID = direction == "outgoing" ? (outgoingSenderID ?? accountID) : incomingSenderID
            let offset = startOffsetSeconds + Int64(index - 1) * intervalSeconds
            return MockDemoMessageEntry(
                conversationID: conversationID,
                senderID: senderID,
                text: "\(textPrefix) \(index)",
                localTimeOffsetSeconds: offset,
                messageID: "\(messageIDPrefix)_\(index)",
                clientMessageID: nil,
                serverMessageID: serverMessageIDPrefix.map { "\($0)_\(index)" },
                sequenceOffsetSeconds: offset,
                direction: direction,
                readStatus: direction == "incoming" ? "unread" : "read",
                sortSequenceOffsetSeconds: offset
            )
        }
    }
}

nonisolated private struct MockDemoGroupMemberEntry: Decodable, Sendable {
    let conversationID: String
    let memberID: String
    let displayName: String
    let role: String
    let joinTimeOffsetSeconds: Int64?

    func makeMember(now: Int64) throws -> GroupMember {
        GroupMember(
            conversationID: ConversationID(rawValue: conversationID),
            memberID: UserID(rawValue: memberID),
            displayName: displayName,
            role: try Self.groupMemberRole(from: role),
            joinTime: joinTimeOffsetSeconds.map { now + $0 }
        )
    }

    private static func groupMemberRole(from value: String) throws -> GroupMemberRole {
        switch value {
        case "member":
            return .member
        case "admin":
            return .admin
        case "owner":
            return .owner
        default:
            throw DemoDataCatalogError.invalidGroupMemberRole(value)
        }
    }
}

nonisolated private struct MockDemoGroupAnnouncementEntry: Decodable, Sendable {
    let conversationID: String
    let text: String
}
