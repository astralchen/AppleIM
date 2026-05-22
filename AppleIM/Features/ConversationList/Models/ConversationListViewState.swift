//
//  ConversationListViewState.swift
//  AppleIM
//
//  会话列表视图状态
//  定义会话列表的 UI 状态和会话行状态

import Foundation

/// 会话列表行状态
///
/// 用于 UI 展示的会话行数据
nonisolated struct ConversationListRowState: Identifiable, Equatable, Sendable {
    /// 会话 ID
    let id: ConversationID
    /// 会话标题
    let title: String
    /// 会话头像 URL
    let avatarURL: String?
    /// 副标题（最后一条消息摘要或草稿）
    let subtitle: String
    /// @ 当前用户提示文本
    let mentionIndicatorText: String?
    /// 时间文本
    let timeText: String
    /// 未读数文本
    let unreadText: String?
    /// 是否置顶
    let isPinned: Bool
    /// 是否免打扰
    let isMuted: Bool

    init(
        id: ConversationID,
        title: String,
        avatarURL: String? = nil,
        subtitle: String,
        mentionIndicatorText: String? = nil,
        timeText: String,
        unreadText: String?,
        isPinned: Bool,
        isMuted: Bool
    ) {
        self.id = id
        self.title = title
        self.avatarURL = avatarURL
        self.subtitle = subtitle
        self.mentionIndicatorText = mentionIndicatorText
        self.timeText = timeText
        self.unreadText = unreadText
        self.isPinned = isPinned
        self.isMuted = isMuted
    }
}

/// 会话列表视图状态
///
/// 包含会话列表的所有 UI 状态
nonisolated struct ConversationListViewState: Equatable, Sendable {
    /// 列表渲染意图，用于让 UI 区分用户可见动作和后台校准刷新。
    enum RenderIntent: Equatable, Sendable {
        /// 默认渲染，不携带特殊动画意图。
        case idle
        /// 首屏或显式加载。
        case initialLoad
        /// 后台刷新或校准，不应触发列表位移动画。
        case backgroundRefresh
        /// 模拟推送的乐观更新，可保留一次轻微移动动画。
        case simulatedIncoming
        /// 本地状态更新，例如进入会话时清未读。
        case localMutation
        /// 分页追加。
        case pagination
    }

    /// 加载阶段
    enum LoadingPhase: Equatable, Sendable {
        /// 空闲
        case idle
        /// 加载中
        case loading
        /// 已加载
        case loaded
        /// 加载失败
        case failed(String)
    }

    /// 页面标题
    var title = "ChatBridge"
    /// 加载阶段
    var phase: LoadingPhase = .idle
    /// 会话行数组
    var rows: [ConversationListRowState] = []
    /// 是否正在加载下一页
    var isLoadingMore = false
    /// 是否还有更多会话可加载
    var hasMoreRows = false
    /// 空列表提示
    var emptyMessage = "No conversations yet"
    /// 最近一次状态发布的渲染意图
    var renderIntent: RenderIntent = .idle

    /// 是否为空
    var isEmpty: Bool {
        rows.isEmpty
    }
}
