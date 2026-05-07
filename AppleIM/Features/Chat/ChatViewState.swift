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
    /// 视频缩略图路径
    let videoThumbnailPath: String?
    /// 视频本地路径
    let videoLocalPath: String?
    /// 视频时长（毫秒）
    let videoDurationMilliseconds: Int?
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
    /// 发送者头像 URL
    let senderAvatarURL: String?
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
    /// 语音本地路径
    let voiceLocalPath: String?
    /// 收到的语音是否未播放
    let isVoiceUnplayed: Bool
    /// 语音是否正在播放
    let isVoicePlaying: Bool

    init(
        id: MessageID,
        text: String,
        imageThumbnailPath: String?,
        videoThumbnailPath: String? = nil,
        videoLocalPath: String? = nil,
        videoDurationMilliseconds: Int? = nil,
        voiceDurationMilliseconds: Int?,
        sortSequence: Int64,
        timeText: String,
        statusText: String?,
        uploadProgress: Double?,
        senderAvatarURL: String? = nil,
        isOutgoing: Bool,
        canRetry: Bool,
        canDelete: Bool,
        canRevoke: Bool,
        isRevoked: Bool,
        voiceLocalPath: String? = nil,
        isVoiceUnplayed: Bool = false,
        isVoicePlaying: Bool = false
    ) {
        self.id = id
        self.text = text
        self.imageThumbnailPath = imageThumbnailPath
        self.videoThumbnailPath = videoThumbnailPath
        self.videoLocalPath = videoLocalPath
        self.videoDurationMilliseconds = videoDurationMilliseconds
        self.voiceDurationMilliseconds = voiceDurationMilliseconds
        self.sortSequence = sortSequence
        self.timeText = timeText
        self.statusText = statusText
        self.uploadProgress = uploadProgress
        self.senderAvatarURL = senderAvatarURL
        self.isOutgoing = isOutgoing
        self.canRetry = canRetry
        self.canDelete = canDelete
        self.canRevoke = canRevoke
        self.isRevoked = isRevoked
        self.voiceLocalPath = voiceLocalPath
        self.isVoiceUnplayed = isVoiceUnplayed
        self.isVoicePlaying = isVoicePlaying
    }

    /// 是否为图片消息
    var isImage: Bool {
        imageThumbnailPath != nil
    }

    /// 是否为视频消息
    var isVideo: Bool {
        videoThumbnailPath != nil || videoLocalPath != nil || videoDurationMilliseconds != nil
    }

    /// 是否为语音消息
    var isVoice: Bool {
        voiceDurationMilliseconds != nil
    }

    func withVoicePlayback(isPlaying: Bool, isUnplayed: Bool? = nil) -> ChatMessageRowState {
        ChatMessageRowState(
            id: id,
            text: text,
            imageThumbnailPath: imageThumbnailPath,
            videoThumbnailPath: videoThumbnailPath,
            videoLocalPath: videoLocalPath,
            videoDurationMilliseconds: videoDurationMilliseconds,
            voiceDurationMilliseconds: voiceDurationMilliseconds,
            sortSequence: sortSequence,
            timeText: timeText,
            statusText: statusText,
            uploadProgress: uploadProgress,
            senderAvatarURL: senderAvatarURL,
            isOutgoing: isOutgoing,
            canRetry: canRetry,
            canDelete: canDelete,
            canRevoke: canRevoke,
            isRevoked: isRevoked,
            voiceLocalPath: voiceLocalPath,
            isVoiceUnplayed: isUnplayed ?? isVoiceUnplayed,
            isVoicePlaying: isPlaying
        )
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
