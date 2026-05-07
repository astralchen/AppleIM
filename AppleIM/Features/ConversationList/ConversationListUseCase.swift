//
//  ConversationListUseCase.swift
//  AppleIM
//
//  会话列表用例
//  封装会话列表的业务逻辑

import Foundation

nonisolated struct ConversationListPage: Equatable, Sendable {
    let rows: [ConversationListRowState]
    let hasMore: Bool
}

/// 会话列表用例协议
protocol ConversationListUseCase: Sendable {
    /// 加载会话列表
    func loadConversations() async throws -> [ConversationListRowState]
    /// 分页加载会话列表
    func loadConversationPage(limit: Int, offset: Int) async throws -> ConversationListPage
    /// 更新会话置顶状态
    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws
    /// 更新会话免打扰状态
    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws
}

/// 本地会话列表用例实现
nonisolated struct LocalConversationListUseCase: ConversationListUseCase {
    /// 用户 ID
    private let userID: UserID
    /// 存储提供者
    private let storeProvider: ChatStoreProvider
    /// 日志
    private let logger: AppLogger

    init(
        userID: UserID,
        storeProvider: ChatStoreProvider,
        logger: AppLogger = AppLogger(category: .conversationList)
    ) {
        self.userID = userID
        self.storeProvider = storeProvider
        self.logger = logger
    }

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

    func loadConversationPage(limit: Int, offset: Int) async throws -> ConversationListPage {
        let startUptime = ProcessInfo.processInfo.systemUptime
        logger.info("ConversationList useCase page requested limit=\(limit) offset=\(offset)")
        let repositoryStartUptime = ProcessInfo.processInfo.systemUptime
        let repository = try await storeProvider.repository()
        logger.info(
            "ConversationList useCase repository ready elapsed=\(AppLogger.elapsedMilliseconds(since: repositoryStartUptime))"
        )

        let requestedLimit = max(limit, 0)
        let queryStartUptime = ProcessInfo.processInfo.systemUptime
        let conversations = try await repository.listConversations(for: userID, limit: requestedLimit + 1, offset: offset)
        logger.info(
            "ConversationList useCase query completed fetched=\(conversations.count) requestedLimit=\(requestedLimit) elapsed=\(AppLogger.elapsedMilliseconds(since: queryStartUptime))"
        )

        let pageConversations = Array(conversations.prefix(requestedLimit))
        let rows = Self.rowStates(from: pageConversations)
        let hasMore = conversations.count > requestedLimit
        logger.info(
            "ConversationList useCase page completed rows=\(rows.count) hasMore=\(hasMore) totalElapsed=\(AppLogger.elapsedMilliseconds(since: startUptime))"
        )

        return ConversationListPage(
            rows: rows,
            hasMore: hasMore
        )
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {
        let repository = try await storeProvider.repository()
        try await repository.updateConversationPin(conversationID: conversationID, userID: userID, isPinned: isPinned)
    }

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {
        let repository = try await storeProvider.repository()
        try await repository.updateConversationMute(conversationID: conversationID, userID: userID, isMuted: isMuted)
    }

    private static func rowStates(from conversations: [Conversation]) -> [ConversationListRowState] {
        return conversations.map { conversation in
            let subtitle = conversation.draftText.map { "Draft: \($0)" } ?? conversation.lastMessageDigest

            return ConversationListRowState(
                id: conversation.id,
                title: conversation.title,
                subtitle: subtitle,
                timeText: conversation.lastMessageTimeText,
                unreadText: conversation.unreadCount > 0 ? "\(conversation.unreadCount)" : nil,
                isPinned: conversation.isPinned,
                isMuted: conversation.isMuted
            )
        }
    }
}

nonisolated struct PreviewConversationListUseCase: ConversationListUseCase {
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

    func loadConversationPage(limit: Int, offset: Int) async throws -> ConversationListPage {
        let rows = try await loadConversations()
        let requestedLimit = max(limit, 0)
        let pageRows = Array(rows.dropFirst(offset).prefix(requestedLimit))

        return ConversationListPage(
            rows: pageRows,
            hasMore: offset + pageRows.count < rows.count
        )
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}
}
