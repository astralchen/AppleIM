//
//  ConversationListUseCase.swift
//  AppleIM
//
//  会话列表用例
//  封装会话列表的业务逻辑

import Foundation

/// 会话列表分页结果
nonisolated struct ConversationListPage: Equatable, Sendable {
    /// 会话行列表
    let rows: [ConversationListRowState]
    /// 是否有更多数据
    let hasMore: Bool
    /// 下一页游标
    let nextCursor: ConversationPageCursor?
}

/// 会话列表模拟收消息结果
nonisolated struct ConversationListSimulationResult: Equatable, Sendable {
    /// 收到模拟消息的会话 ID
    let conversationID: ConversationID
    /// 本次插入的模拟消息数量
    let messageCount: Int
    /// 模拟写入后该会话的最终行状态
    let finalRow: ConversationListRowState
}

/// 会话列表用例协议
protocol ConversationListUseCase: Sendable {
    /// 加载会话列表
    ///
    /// - Returns: 会话列表行状态数组
    /// - Throws: 加载错误
    func loadConversations() async throws -> [ConversationListRowState]
    /// 分页加载会话列表
    ///
    /// - Parameters:
    ///   - limit: 每页数量
    ///   - cursor: 上一页最后一条会话的排序游标
    /// - Returns: 会话列表分页结果
    /// - Throws: 加载错误
    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage
    /// 更新会话置顶状态
    ///
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - isPinned: 是否置顶
    /// - Throws: 更新错误
    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws
    /// 更新会话免打扰状态
    ///
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - isMuted: 是否免打扰
    /// - Throws: 更新错误
    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws
    /// 模拟从随机会话收到若干条 incoming 文本消息。
    ///
    /// - Returns: 模拟结果；如果当前没有会话则返回 nil。
    /// - Throws: 存储访问错误
    func simulateIncomingMessages() async throws -> ConversationListSimulationResult?
}

extension ConversationListUseCase {
    func simulateIncomingMessages() async throws -> ConversationListSimulationResult? {
        nil
    }
}

/// 本地会话列表用例实现
nonisolated struct LocalConversationListUseCase: ConversationListUseCase {
    /// 用户 ID
    private let userID: UserID
    /// 存储提供者
    private let storeProvider: ChatStoreProvider
    /// 统一模拟后台推送服务
    private let simulatedIncomingPushService: SimulatedIncomingPushService
    /// 日志
    private let logger: AppLogger

    /// 初始化
    ///
    /// - Parameters:
    ///   - userID: 用户 ID
    ///   - storeProvider: 存储提供者
    ///   - logger: 日志工具
    init(
        userID: UserID,
        storeProvider: ChatStoreProvider,
        simulatedIncomingPushService: SimulatedIncomingPushService? = nil,
        logger: AppLogger = AppLogger(category: .conversationList)
    ) {
        self.userID = userID
        self.storeProvider = storeProvider
        self.simulatedIncomingPushService = simulatedIncomingPushService
            ?? SimulatedIncomingPushService(userID: userID, storeProvider: storeProvider)
        self.logger = logger
    }

    /// 加载会话列表
    ///
    /// 从存储加载所有会话并转换为行状态
    ///
    /// - Returns: 会话列表行状态数组
    /// - Throws: 存储访问错误
    func loadConversations() async throws -> [ConversationListRowState] {
        let startUptime = ProcessInfo.processInfo.systemUptime
        logger.info("ConversationList useCase loadConversations requested")
        let repository = try await storeProvider.repository()
        let conversations = try await repository.listConversations(for: userID)
        logger.info(
            "ConversationList useCase loadConversations completed count=\(conversations.count) elapsed=\(AppLogger.elapsedMilliseconds(since: startUptime))"
        )

        return Self.rowStates(from: conversations)
    }

    /// 分页加载会话列表
    ///
    /// 从存储加载指定范围的会话并转换为行状态
    ///
    /// - Parameters:
    ///   - limit: 每页数量
    ///   - cursor: 上一页最后一条会话的排序游标
    /// - Returns: 会话列表分页结果（包含是否有更多数据）
    /// - Throws: 存储访问错误
    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        let startUptime = ProcessInfo.processInfo.systemUptime
        logger.info("ConversationList useCase page requested limit=\(limit) cursor=\(cursor?.conversationID.rawValue ?? "nil")")
        let repositoryStartUptime = ProcessInfo.processInfo.systemUptime
        let repository = try await storeProvider.repository()
        logger.info(
            "ConversationList useCase repository ready elapsed=\(AppLogger.elapsedMilliseconds(since: repositoryStartUptime))"
        )

        let requestedLimit = max(limit, 0)
        let queryStartUptime = ProcessInfo.processInfo.systemUptime
        let conversations = try await repository.listConversations(for: userID, limit: requestedLimit + 1, after: cursor)
        logger.info(
            "ConversationList useCase query completed fetched=\(conversations.count) requestedLimit=\(requestedLimit) elapsed=\(AppLogger.elapsedMilliseconds(since: queryStartUptime))"
        )

        let pageConversations = Array(conversations.prefix(requestedLimit))
        let rows = Self.rowStates(from: pageConversations)
        let hasMore = conversations.count > requestedLimit
        let nextCursor = pageConversations.last.map(ConversationPageCursor.init(conversation:))
        logger.info(
            "ConversationList useCase page completed rows=\(rows.count) hasMore=\(hasMore) totalElapsed=\(AppLogger.elapsedMilliseconds(since: startUptime))"
        )

        return ConversationListPage(
            rows: rows,
            hasMore: hasMore,
            nextCursor: nextCursor
        )
    }

    /// 更新会话置顶状态
    ///
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - isPinned: 是否置顶
    /// - Throws: 存储访问错误
    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {
        let repository = try await storeProvider.repository()
        try await repository.updateConversationPin(conversationID: conversationID, userID: userID, isPinned: isPinned)
    }

    /// 更新会话免打扰状态
    ///
    /// - Parameters:
    ///   - conversationID: 会话 ID
    ///   - isMuted: 是否免打扰
    /// - Throws: 存储访问错误
    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {
        let repository = try await storeProvider.repository()
        try await repository.updateConversationMute(conversationID: conversationID, userID: userID, isMuted: isMuted)
    }

    /// 从统一模拟后台推送入口随机写入 1...5 条 incoming 文本消息。
    func simulateIncomingMessages() async throws -> ConversationListSimulationResult? {
        let startUptime = ProcessInfo.processInfo.systemUptime
        guard let pushResult = try await simulatedIncomingPushService.simulateIncomingPush() else {
            return nil
        }
        let finalRow = Self.rowStates(from: [pushResult.finalConversation]).first
            ?? ConversationListRowState(
                id: pushResult.conversationID,
                title: pushResult.finalConversation.title,
                subtitle: pushResult.finalConversation.lastMessageDigest,
                timeText: pushResult.finalConversation.lastMessageTimeText,
                unreadText: pushResult.finalConversation.unreadCount > 0 ? "\(pushResult.finalConversation.unreadCount)" : nil,
                isPinned: pushResult.finalConversation.isPinned,
                isMuted: pushResult.finalConversation.isMuted
            )
        logger.info(
            "ConversationList simulateIncomingMessages completed conversationID=\(Self.shortLogID(pushResult.conversationID.rawValue)) count=\(pushResult.insertedCount) elapsed=\(AppLogger.elapsedMilliseconds(since: startUptime))"
        )

        return ConversationListSimulationResult(
            conversationID: pushResult.conversationID,
            messageCount: pushResult.insertedCount,
            finalRow: finalRow
        )
    }

    /// 将会话列表转换为行状态
    ///
    /// - Parameter conversations: 会话列表
    /// - Returns: 会话列表行状态数组
    static func rowStates(from conversations: [Conversation]) -> [ConversationListRowState] {
        return conversations.map { conversation in
            let mentionIndicatorText = conversation.hasUnreadMention ? "[有人@我]" : nil
            let baseSubtitle = conversation.draftText.map { "Draft: \($0)" } ?? conversation.lastMessageDigest
            let subtitle = mentionIndicatorText.map { "\($0) \(baseSubtitle)" } ?? baseSubtitle

            return ConversationListRowState(
                id: conversation.id,
                title: conversation.title,
                avatarURL: conversation.avatarURL,
                subtitle: subtitle,
                mentionIndicatorText: mentionIndicatorText,
                timeText: conversation.lastMessageTimeText,
                unreadText: conversation.unreadCount > 0 ? "\(conversation.unreadCount)" : nil,
                isPinned: conversation.isPinned,
                isMuted: conversation.isMuted
            )
        }
    }

    private static func timeText(from timestamp: Int64) -> String {
        ChatBridgeTimeFormatter.messageTimeText(from: timestamp)
    }

    private static func shortLogID(_ rawValue: String) -> String {
        String(rawValue.prefix(8))
    }
}

/// 预览会话列表用例实现
///
/// 用于 SwiftUI 预览和测试，返回模拟数据
nonisolated struct PreviewConversationListUseCase: ConversationListUseCase {
    /// 加载会话列表
    ///
    /// 返回模拟的会话列表数据
    ///
    /// - Returns: 模拟的会话列表行状态数组
    func loadConversations() async throws -> [ConversationListRowState] {
        try await Task.sleep(nanoseconds: 120_000_000)

        return [
            ConversationListRowState(
                id: "single_sondra",
                title: "Sondra",
                subtitle: "The MVVM baseline is ready.",
                timeText: "09:41",
                unreadText: "2",
                isPinned: true,
                isMuted: false
            ),
            ConversationListRowState(
                id: "group_core",
                title: "ChatBridge Core",
                subtitle: "Swift 6 strict concurrency is enabled.",
                timeText: "Yesterday",
                unreadText: nil,
                isPinned: false,
                isMuted: true
            )
        ]
    }

    /// 分页加载会话列表
    ///
    /// 从模拟数据中返回指定范围的会话
    ///
    /// - Parameters:
    ///   - limit: 每页数量
    ///   - cursor: 上一页最后一条会话的排序游标
    /// - Returns: 会话列表分页结果
    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        let rows = try await loadConversations()
        let requestedLimit = max(limit, 0)
        let startIndex = cursor
            .flatMap { cursor in rows.firstIndex { $0.id == cursor.conversationID } }
            .map { rows.index(after: $0) } ?? rows.startIndex
        let pageRows = Array(rows[startIndex...].prefix(requestedLimit))

        return ConversationListPage(
            rows: pageRows,
            hasMore: startIndex + pageRows.count < rows.count,
            nextCursor: pageRows.last.map { row in
                ConversationPageCursor(isPinned: row.isPinned, sortTimestamp: 0, conversationID: row.id)
            }
        )
    }

    /// 更新会话置顶状态（空实现）
    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    /// 更新会话免打扰状态（空实现）
    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}
}
