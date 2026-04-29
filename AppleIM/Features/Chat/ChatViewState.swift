//
//  ChatViewState.swift
//  AppleIM
//
//  聊天页视图状态
//  定义聊天页的 UI 状态和消息行状态

import Foundation

/// 聊天消息行状态
///
/// 用于 UI 展示的消息行数据，包含显示所需的所有信息
nonisolated struct ChatMessageRowState: Identifiable, Hashable, Sendable {
    /// 消息 ID
    let id: MessageID
    /// 文本内容
    let text: String
    /// 图片缩略图路径
    let imageThumbnailPath: String?
    /// 语音时长（毫秒）
    let voiceDurationMilliseconds: Int?
    /// 排序序号
    let sortSequence: Int64
    /// 时间文本
    let timeText: String
    /// 状态文本（发送中、失败等）
    let statusText: String?
    /// 上传进度（0.0-1.0）
    let uploadProgress: Double?
    /// 是否为发出的消息
    let isOutgoing: Bool
    /// 是否可以重试
    let canRetry: Bool
    /// 是否可以删除
    let canDelete: Bool
    /// 是否可以撤回
    let canRevoke: Bool
    /// 是否已撤回
    let isRevoked: Bool

    /// 是否为图片消息
    var isImage: Bool {
        imageThumbnailPath != nil
    }

    /// 是否为语音消息
    var isVoice: Bool {
        voiceDurationMilliseconds != nil
    }
}

/// 聊天页视图状态
///
/// 包含聊天页的所有 UI 状态，满足 Sendable 协议
nonisolated struct ChatViewState: Equatable, Sendable {
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

    /// 聊天标题
    var title: String
    /// 加载阶段
    var phase: LoadingPhase = .idle
    /// 消息行数组
    var rows: [ChatMessageRowState] = []
    /// 草稿文本
    var draftText = ""
    /// 空消息提示
    var emptyMessage = "No messages yet"
    /// 是否正在加载更早的消息
    var isLoadingOlderMessages = false
    /// 是否还有更多消息
    var hasMoreOlderMessages = true
    /// 分页错误消息
    var paginationErrorMessage: String?

    /// 是否为空
    var isEmpty: Bool {
        rows.isEmpty
    }
}
