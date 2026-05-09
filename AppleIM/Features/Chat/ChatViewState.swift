//
//  ChatViewState.swift
//  AppleIM
//
//  聊天页视图状态
//  定义聊天页的 UI 状态和消息行状态

import Foundation

/// 聊天消息行内容
///
/// 按消息类型隔离展示属性，避免把不同类型的可选字段平铺到行状态中。
nonisolated enum ChatMessageRowContent: Hashable, Sendable {
    nonisolated enum Kind: Hashable, Sendable {
        case text
        case image
        case voice
        case video
        case file
        case revoked
    }

    nonisolated struct ImageContent: Hashable, Sendable {
        let thumbnailPath: String
    }

    nonisolated struct VoiceContent: Hashable, Sendable {
        let localPath: String
        let durationMilliseconds: Int
        let isUnplayed: Bool
        let isPlaying: Bool
    }

    nonisolated struct VideoContent: Hashable, Sendable {
        let thumbnailPath: String
        let localPath: String
        let durationMilliseconds: Int
    }

    nonisolated struct FileContent: Hashable, Sendable {
        let fileName: String
        let fileExtension: String?
        let localPath: String
        let sizeBytes: Int64
    }

    case text(String)
    case image(ImageContent)
    case voice(VoiceContent)
    case video(VideoContent)
    case file(FileContent)
    case revoked(String)

    var kind: Kind {
        switch self {
        case .text:
            return .text
        case .image:
            return .image
        case .voice:
            return .voice
        case .video:
            return .video
        case .file:
            return .file
        case .revoked:
            return .revoked
        }
    }

    var accessibilityText: String {
        switch self {
        case let .text(text), let .revoked(text):
            return text
        case .image:
            return "Image"
        case let .voice(voice):
            return "Voice \(Self.durationText(milliseconds: voice.durationMilliseconds))"
        case .video:
            return "Video"
        case let .file(file):
            return file.fileName
        }
    }

    static func durationText(milliseconds: Int) -> String {
        let seconds = max(1, Int((Double(milliseconds) / 1_000.0).rounded()))
        return "\(seconds)s"
    }
}

/// 聊天消息行状态
///
/// 用于 UI 展示的消息行数据，包含公共行信息和按类型隔离的内容 payload。
nonisolated struct ChatMessageRowState: Identifiable, Hashable, Sendable {
    /// 消息 ID
    let id: MessageID
    /// 消息内容
    let content: ChatMessageRowContent
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

    init(
        id: MessageID,
        content: ChatMessageRowContent,
        sortSequence: Int64,
        timeText: String,
        statusText: String?,
        uploadProgress: Double?,
        senderAvatarURL: String? = nil,
        isOutgoing: Bool,
        canRetry: Bool,
        canDelete: Bool,
        canRevoke: Bool
    ) {
        self.id = id
        self.content = content
        self.sortSequence = sortSequence
        self.timeText = timeText
        self.statusText = statusText
        self.uploadProgress = uploadProgress
        self.senderAvatarURL = senderAvatarURL
        self.isOutgoing = isOutgoing
        self.canRetry = canRetry
        self.canDelete = canDelete
        self.canRevoke = canRevoke
    }

    func withVoicePlayback(isPlaying: Bool, isUnplayed: Bool? = nil) -> ChatMessageRowState {
        guard let voice = voiceContent else {
            return self
        }

        let updatedVoice = ChatMessageRowContent.VoiceContent(
            localPath: voice.localPath,
            durationMilliseconds: voice.durationMilliseconds,
            isUnplayed: isUnplayed ?? voice.isUnplayed,
            isPlaying: isPlaying
        )

        return ChatMessageRowState(
            id: id,
            content: .voice(updatedVoice),
            sortSequence: sortSequence,
            timeText: timeText,
            statusText: statusText,
            uploadProgress: uploadProgress,
            senderAvatarURL: senderAvatarURL,
            isOutgoing: isOutgoing,
            canRetry: canRetry,
            canDelete: canDelete,
            canRevoke: canRevoke
        )
    }

    var voiceContent: ChatMessageRowContent.VoiceContent? {
        if case let .voice(voice) = content {
            return voice
        }
        return nil
    }
}

/// 聊天页群公告状态
nonisolated struct ChatGroupAnnouncementState: Equatable, Sendable {
    let text: String
    let canEdit: Bool
}

/// @ 成员选项
nonisolated struct ChatMentionOptionState: Identifiable, Equatable, Sendable {
    let id: String
    let userID: UserID?
    let displayName: String
    let mentionsAll: Bool
}

/// @ 成员选择器状态
nonisolated struct ChatMentionPickerState: Equatable, Sendable {
    let options: [ChatMentionOptionState]
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
    /// 群公告
    var groupAnnouncement: ChatGroupAnnouncementState?
    /// @ 成员选择器
    var mentionPicker: ChatMentionPickerState?

    /// 是否为空
    var isEmpty: Bool {
        rows.isEmpty
    }
}
