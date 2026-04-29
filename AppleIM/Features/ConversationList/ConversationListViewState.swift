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
    /// 副标题（最后一条消息摘要或草稿）
    let subtitle: String
    /// 时间文本
    let timeText: String
    /// 未读数文本
    let unreadText: String?
    /// 是否置顶
    let isPinned: Bool
    /// 是否免打扰
    let isMuted: Bool
}

/// 会话列表视图状态
///
/// 包含会话列表的所有 UI 状态
nonisolated struct ConversationListViewState: Equatable, Sendable {
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
    /// 空列表提示
    var emptyMessage = "No conversations yet"

    /// 是否为空
    var isEmpty: Bool {
        rows.isEmpty
    }
}
