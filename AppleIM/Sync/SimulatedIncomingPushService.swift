//
//  SimulatedIncomingPushService.swift
//  AppleIM
//
//  统一的模拟后台推送入口。
//

import Foundation

/// 模拟后台推送使用的仓储能力集合。
protocol SimulatedIncomingPushRepository: ConversationRepository, MessageRepository, SyncStore {
    func conversationRecord(conversationID: ConversationID, userID: UserID) async throws -> ConversationRecord?
}

extension LocalChatRepository: SimulatedIncomingPushRepository {}

/// 模拟后台推送目标。
nonisolated enum SimulatedIncomingPushTarget: Equatable, Sendable {
    /// 从当前账号会话中随机选择一个目标。
    case randomConversation
    /// 指定目标会话，主要用于测试和定向调试。
    case conversation(ConversationID)
}

/// 模拟后台推送请求。
nonisolated struct SimulatedIncomingPushRequest: Equatable, Sendable {
    /// 目标会话策略。
    let target: SimulatedIncomingPushTarget
    /// 固定消息数量；为空时从服务配置的范围中随机选择。
    let messageCount: Int?

    init(
        target: SimulatedIncomingPushTarget = .randomConversation,
        messageCount: Int? = nil
    ) {
        self.target = target
        self.messageCount = messageCount
    }
}

/// 模拟后台推送结果。
nonisolated struct SimulatedIncomingPushResult: Equatable, Sendable {
    /// 目标会话 ID。
    let conversationID: ConversationID
    /// 本次生成的同步消息。
    let messages: [IncomingSyncMessage]
    /// 实际插入数量。
    let insertedCount: Int
    /// 按本次推送计算出的会话最终状态。
    let finalConversation: Conversation
}

/// 聊天等上层用例依赖的后台推送能力。
protocol SimulatedIncomingPushing: Sendable {
    func simulateIncomingPush(_ request: SimulatedIncomingPushRequest) async throws -> SimulatedIncomingPushResult?
}

/// 为模拟后台推送批量分配单调递增序号。
///
/// 单个 actor 方法内不包含 await，避免读取和写入序号之间发生可重入交错。
private actor SimulatedIncomingPushSequenceAllocator {
    private var latestSequenceByConversation: [ConversationID: Int64] = [:]

    func allocateSequences(
        conversationID: ConversationID,
        latestStoredSequence: Int64?,
        now: Int64,
        count: Int
    ) -> [Int64] {
        let latestAllocatedSequence = latestSequenceByConversation[conversationID] ?? 0
        let latestStoredSequence = latestStoredSequence ?? 0
        let firstSequence = max(latestAllocatedSequence + 1, latestStoredSequence + 1, now)
        let sequences = (0..<count).map { firstSequence + Int64($0) }
        latestSequenceByConversation[conversationID] = sequences.last ?? latestAllocatedSequence
        return sequences
    }
}

/// 统一模拟后台推送服务。
nonisolated struct SimulatedIncomingPushService: SimulatedIncomingPushing, Sendable {
    private static let simulatedIncomingTextSamples = [
        "模拟收到一条后台推送消息",
        "后台推送抵达一条新的测试消息",
        "这是一条统一入口生成的同步消息",
        "随机会话收到新的后台模拟消息",
        "模拟推送链路应立即刷新可见界面"
    ]

    private let userID: UserID
    private let messageCountRange: ClosedRange<Int>
    private let repositoryProvider: @Sendable () async throws -> any SimulatedIncomingPushRepository
    private let sequenceAllocator: SimulatedIncomingPushSequenceAllocator
    private let logger: AppLogger

    init(
        userID: UserID,
        storeProvider: ChatStoreProvider,
        messageCountRange: ClosedRange<Int> = 1...5,
        logger: AppLogger = AppLogger(category: .simulatedPush)
    ) {
        self.userID = userID
        self.messageCountRange = messageCountRange
        self.repositoryProvider = {
            try await storeProvider.repository()
        }
        self.sequenceAllocator = SimulatedIncomingPushSequenceAllocator()
        self.logger = logger
    }

    init(
        userID: UserID,
        repository: any SimulatedIncomingPushRepository,
        messageCountRange: ClosedRange<Int> = 1...5,
        logger: AppLogger = AppLogger(category: .simulatedPush)
    ) {
        self.userID = userID
        self.messageCountRange = messageCountRange
        self.repositoryProvider = {
            repository
        }
        self.sequenceAllocator = SimulatedIncomingPushSequenceAllocator()
        self.logger = logger
    }

    /// 触发一次模拟后台推送。
    func simulateIncomingPush(
        _ request: SimulatedIncomingPushRequest = SimulatedIncomingPushRequest()
    ) async throws -> SimulatedIncomingPushResult? {
        let startUptime = ProcessInfo.processInfo.systemUptime
        logger.info("SimulatedPush started target=\(request.target.logDescription)")

        let repositoryStartUptime = ProcessInfo.processInfo.systemUptime
        let repository = try await repositoryProvider()
        logger.info(
            "SimulatedPush repositoryReady elapsed=\(AppLogger.elapsedMilliseconds(since: repositoryStartUptime)) total=\(AppLogger.elapsedMilliseconds(since: startUptime))"
        )

        let conversationStartUptime = ProcessInfo.processInfo.systemUptime
        let conversations = try await repository.listConversations(for: userID)
        guard let selectedConversation = Self.selectConversation(from: conversations, target: request.target) else {
            logger.info(
                "SimulatedPush skipped reason=no-conversation elapsed=\(AppLogger.elapsedMilliseconds(since: conversationStartUptime)) total=\(AppLogger.elapsedMilliseconds(since: startUptime))"
            )
            return nil
        }
        logger.info(
            "SimulatedPush conversationSelected conversationID=\(Self.shortLogID(selectedConversation.id.rawValue)) elapsed=\(AppLogger.elapsedMilliseconds(since: conversationStartUptime)) total=\(AppLogger.elapsedMilliseconds(since: startUptime))"
        )

        let senderStartUptime = ProcessInfo.processInfo.systemUptime
        let senderID = try await resolveIncomingSenderID(for: selectedConversation, repository: repository)
        logger.info(
            "SimulatedPush senderResolved conversationID=\(Self.shortLogID(selectedConversation.id.rawValue)) senderID=\(Self.shortLogID(senderID.rawValue)) elapsed=\(AppLogger.elapsedMilliseconds(since: senderStartUptime)) total=\(AppLogger.elapsedMilliseconds(since: startUptime))"
        )

        let latestStartUptime = ProcessInfo.processInfo.systemUptime
        let latestMessage = try await repository.listMessages(
            conversationID: selectedConversation.id,
            limit: 1,
            beforeSortSeq: nil
        ).first
        logger.info(
            "SimulatedPush latestLoaded conversationID=\(Self.shortLogID(selectedConversation.id.rawValue)) elapsed=\(AppLogger.elapsedMilliseconds(since: latestStartUptime)) total=\(AppLogger.elapsedMilliseconds(since: startUptime))"
        )

        let messageCount = resolvedMessageCount(from: request)
        let sequenceStartUptime = ProcessInfo.processInfo.systemUptime
        let sequences = await sequenceAllocator.allocateSequences(
            conversationID: selectedConversation.id,
            latestStoredSequence: latestMessage?.timeline.sortSequence,
            now: Self.currentTimestamp(),
            count: messageCount
        )
        logger.info(
            "SimulatedPush sequencesAllocated conversationID=\(Self.shortLogID(selectedConversation.id.rawValue)) count=\(sequences.count) elapsed=\(AppLogger.elapsedMilliseconds(since: sequenceStartUptime)) total=\(AppLogger.elapsedMilliseconds(since: startUptime))"
        )

        let batchToken = UUID().uuidString
        let messages = sequences.enumerated().map { index, sequence in
            let messageToken = "\(batchToken)_\(index)"
            let messageID = MessageID(rawValue: "simulated_push_incoming_\(messageToken)")
            return IncomingSyncMessage(
                messageID: messageID,
                conversationID: selectedConversation.id,
                senderID: senderID,
                serverMessageID: "server_\(messageID.rawValue)",
                sequence: sequence,
                text: Self.simulatedIncomingText(messageToken: messageToken),
                serverTime: sequence,
                direction: .incoming,
                conversationTitle: selectedConversation.title,
                conversationType: selectedConversation.type
            )
        }

        let applyStartUptime = ProcessInfo.processInfo.systemUptime
        let applyResult = try await repository.applyIncomingSyncBatch(
            SyncBatch(messages: messages, nextCursor: nil, nextSequence: messages.last?.sequence),
            userID: userID
        )
        logger.info(
            "SimulatedPush batchApplied conversationID=\(Self.shortLogID(selectedConversation.id.rawValue)) count=\(messages.count) inserted=\(applyResult.insertedCount) elapsed=\(AppLogger.elapsedMilliseconds(since: applyStartUptime)) total=\(AppLogger.elapsedMilliseconds(since: startUptime))"
        )

        guard let latestIncomingMessage = messages.last, applyResult.insertedCount > 0 else {
            return nil
        }

        return SimulatedIncomingPushResult(
            conversationID: selectedConversation.id,
            messages: messages,
            insertedCount: applyResult.insertedCount,
            finalConversation: Self.finalConversation(
                from: selectedConversation,
                latestMessage: latestIncomingMessage,
                unreadIncrement: applyResult.insertedCount
            )
        )
    }

    private static func selectConversation(
        from conversations: [Conversation],
        target: SimulatedIncomingPushTarget
    ) -> Conversation? {
        switch target {
        case .randomConversation:
            conversations.randomElement()
        case let .conversation(conversationID):
            conversations.first { $0.id == conversationID }
        }
    }

    private func resolveIncomingSenderID(
        for conversation: Conversation,
        repository: any SimulatedIncomingPushRepository
    ) async throws -> UserID {
        switch conversation.type {
        case .single, .system, .service:
            if let record = try await repository.conversationRecord(conversationID: conversation.id, userID: userID) {
                return UserID(rawValue: record.targetID)
            }
            return userID
        case .group:
            let members = try await repository.groupMembers(conversationID: conversation.id)
            if let member = members.first(where: { $0.memberID != userID }) {
                return member.memberID
            }
            if let record = try await repository.conversationRecord(conversationID: conversation.id, userID: userID) {
                return UserID(rawValue: record.targetID)
            }
            return userID
        }
    }

    private func resolvedMessageCount(from request: SimulatedIncomingPushRequest) -> Int {
        if let messageCount = request.messageCount {
            return max(messageCount, 1)
        }

        return Int.random(in: messageCountRange)
    }

    private static func finalConversation(
        from conversation: Conversation,
        latestMessage: IncomingSyncMessage,
        unreadIncrement: Int
    ) -> Conversation {
        Conversation(
            id: conversation.id,
            type: conversation.type,
            title: conversation.title,
            avatarURL: conversation.avatarURL,
            lastMessageDigest: latestMessage.text,
            lastMessageTimeText: timeText(from: latestMessage.serverTime),
            unreadCount: conversation.unreadCount + unreadIncrement,
            isPinned: conversation.isPinned,
            isMuted: conversation.isMuted,
            draftText: conversation.draftText,
            sortTimestamp: latestMessage.serverTime,
            hasUnreadMention: conversation.hasUnreadMention
        )
    }

    private static func simulatedIncomingText(messageToken: String) -> String {
        let sample = simulatedIncomingTextSamples.randomElement() ?? "模拟收到一条后台推送消息"
        return "\(sample) #\(messageToken.prefix(6).lowercased())"
    }

    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }

    private static func timeText(from timestamp: Int64) -> String {
        ChatBridgeTimeFormatter.messageTimeText(from: timestamp)
    }

    private static func shortLogID(_ rawValue: String) -> String {
        String(rawValue.prefix(8))
    }
}

private extension SimulatedIncomingPushTarget {
    nonisolated var logDescription: String {
        switch self {
        case .randomConversation:
            "random"
        case let .conversation(conversationID):
            "conversation:\(String(conversationID.rawValue.prefix(8)))"
        }
    }
}

/// 联系人资料模拟推送使用的仓储能力集合。
protocol SimulatedContactProfilePushRepository: ContactRepository, ConversationRepository {
    /// 查询指定账号下的完整会话记录，用于保留会话现有摘要、未读数和排序字段。
    func conversationRecord(conversationID: ConversationID, userID: UserID) async throws -> ConversationRecord?
    /// 按会话类型和目标 ID 查询完整会话记录，用于兼容本地已有群聊会话 ID。
    func conversationRecord(userID: UserID, type: ConversationType, targetID: String) async throws -> ConversationRecord?
}

extension LocalChatRepository: SimulatedContactProfilePushRepository {}

/// 联系人资料模拟推送结果。
nonisolated struct SimulatedContactProfilePushResult: Equatable, Sendable {
    /// 被修改的联系人 ID。
    let contactID: ContactID
    /// 被同步更新的已有会话 ID；没有已有会话时为空。
    let conversationID: ConversationID?
    /// 修改后的联系人记录。
    let contact: ContactRecord
}

/// 模拟后台推送联系人资料变更。
nonisolated struct SimulatedContactProfilePushService: Sendable {
    private let userID: UserID
    private let repositoryProvider: @Sendable () async throws -> any SimulatedContactProfilePushRepository
    private let logger: AppLogger

    init(
        userID: UserID,
        storeProvider: ChatStoreProvider,
        logger: AppLogger = AppLogger(category: .simulatedPush)
    ) {
        self.userID = userID
        self.repositoryProvider = {
            try await storeProvider.repository()
        }
        self.logger = logger
    }

    init(
        userID: UserID,
        repository: any SimulatedContactProfilePushRepository,
        logger: AppLogger = AppLogger(category: .simulatedPush)
    ) {
        self.userID = userID
        self.repositoryProvider = {
            repository
        }
        self.logger = logger
    }

    /// 随机修改一个好友或群聊联系人，并同步更新已存在会话的标题和头像。
    func simulateContactProfileChange() async throws -> SimulatedContactProfilePushResult? {
        let startUptime = ProcessInfo.processInfo.systemUptime
        logger.info("SimulatedContactProfilePush started")

        let repository = try await repositoryProvider()
        let contacts = try await repository.listContacts(for: userID)
            .filter { $0.type == .friend || $0.type == .group }
        guard let selectedContact = contacts.randomElement() else {
            logger.info("SimulatedContactProfilePush skipped reason=no-contact")
            return nil
        }

        let updatedContact = Self.updatedContact(from: selectedContact)
        try await repository.upsertContact(updatedContact)

        let conversationID = try await updateExistingConversationIfNeeded(
            contact: updatedContact,
            repository: repository
        )
        postProfileChange(contact: updatedContact, conversationID: conversationID)
        logger.info(
            "SimulatedContactProfilePush completed contactID=\(Self.shortLogID(updatedContact.contactID.rawValue)) conversationID=\(conversationID?.rawValue ?? "nil") elapsed=\(AppLogger.elapsedMilliseconds(since: startUptime))"
        )

        return SimulatedContactProfilePushResult(
            contactID: updatedContact.contactID,
            conversationID: conversationID,
            contact: updatedContact
        )
    }

    private func updateExistingConversationIfNeeded(
        contact: ContactRecord,
        repository: any SimulatedContactProfilePushRepository
    ) async throws -> ConversationID? {
        guard
            let conversationID = Self.conversationID(for: contact),
            let conversationType = contact.type.conversationType
        else {
            return nil
        }
        var existingConversation = try await repository.conversationRecord(conversationID: conversationID, userID: userID)
        if existingConversation == nil {
            existingConversation = try await repository.conversationRecord(userID: userID, type: conversationType, targetID: contact.wxid)
        }
        guard let existing = existingConversation else {
            return nil
        }

        let updatedConversation = ConversationRecord(
            id: existing.id,
            userID: existing.userID,
            type: existing.type,
            targetID: existing.targetID,
            title: Self.profileDisplayName(for: contact),
            avatarURL: contact.avatarURL,
            lastMessageID: existing.lastMessageID,
            lastMessageTime: existing.lastMessageTime,
            lastMessageDigest: existing.lastMessageDigest,
            unreadCount: existing.unreadCount,
            draftText: existing.draftText,
            isPinned: existing.isPinned,
            isMuted: existing.isMuted,
            isHidden: existing.isHidden,
            sortTimestamp: existing.sortTimestamp,
            updatedAt: max(Self.currentTimestamp(), existing.updatedAt + 1),
            createdAt: existing.createdAt
        )
        try await repository.upsertConversation(updatedConversation)
        return existing.id
    }

    private func postProfileChange(contact: ContactRecord, conversationID: ConversationID?) {
        let event = ContactProfileChangeEvent(
            userID: userID,
            contactID: contact.contactID,
            conversationID: conversationID,
            displayName: Self.profileDisplayName(for: contact),
            avatarURL: contact.avatarURL
        )
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .chatStoreContactProfileDidChange,
                object: nil,
                userInfo: event.userInfo
            )
            if let conversationID {
                NotificationCenter.default.post(
                    name: .chatStoreConversationsDidChange,
                    object: nil,
                    userInfo: [
                        ChatStoreConversationChangeNotification.userIDKey: userID.rawValue,
                        ChatStoreConversationChangeNotification.conversationIDsKey: [conversationID.rawValue]
                    ]
                )
            }
        }
    }

    private static func updatedContact(from contact: ContactRecord) -> ContactRecord {
        let token = String(UUID().uuidString.prefix(6)).lowercased()
        let timestamp = max(currentTimestamp(), contact.updatedAt + 1)
        let baseName = contact.type == .group ? "群聊资料" : "联系人资料"
        let updatedNickname = "\(baseName)-昵称-\(token)"
        let updatedRemark = contact.type == .group ? nil : "\(baseName)-备注-\(token)"
        return ContactRecord(
            contactID: contact.contactID,
            userID: contact.userID,
            wxid: contact.wxid,
            nickname: updatedNickname,
            remark: updatedRemark,
            avatarURL: "https://example.com/chatbridge/avatar/\(contact.contactID.rawValue)-\(token).png",
            type: contact.type,
            isStarred: !contact.isStarred,
            isBlocked: contact.isBlocked,
            isDeleted: contact.isDeleted,
            source: contact.source,
            extraJSON: contact.extraJSON,
            updatedAt: timestamp,
            createdAt: contact.createdAt
        )
    }

    private static func profileDisplayName(for contact: ContactRecord) -> String {
        switch contact.type {
        case .group:
            return contact.nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? contact.wxid
                : contact.nickname
        case .friend, .service, .system, .stranger:
            return contact.displayName
        }
    }

    private static func conversationID(for contact: ContactRecord) -> ConversationID? {
        switch contact.type {
        case .friend:
            ConversationID(rawValue: "single_\(contact.wxid)")
        case .group:
            ConversationID(rawValue: "group_\(contact.wxid)")
        case .service, .system, .stranger:
            nil
        }
    }

    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }

    private static func shortLogID(_ rawValue: String) -> String {
        String(rawValue.prefix(8))
    }
}
