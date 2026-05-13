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
nonisolated struct SimulatedIncomingPushService: Sendable {
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
            latestStoredSequence: latestMessage?.sortSequence,
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
