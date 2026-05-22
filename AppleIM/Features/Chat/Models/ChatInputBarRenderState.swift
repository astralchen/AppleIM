//
//  ChatInputBarRenderState.swift
//  AppleIM
//

import UIKit

/// 输入栏当前承载的输入面板。
@MainActor
enum ChatInputPanel: Equatable {
    /// 系统键盘输入。
    case keyboard
    /// 图片库面板。
    case photoLibrary
    /// 表情面板。
    case emoji

    /// 是否为自定义输入面板。
    var isCustomPanel: Bool {
        self != .keyboard
    }
}

/// 待发送语音预览状态。
@MainActor
struct ChatVoicePreviewState: Equatable {
    /// 语音总时长。
    var durationMilliseconds: Int
    /// 当前是否正在播放。
    var isPlaying: Bool
    /// 播放进度，范围 0...1。
    var playbackProgress: Double
    /// 已播放时长。
    var playbackElapsedMilliseconds: Int

    /// 规范化后的状态。
    var normalized: ChatVoicePreviewState {
        ChatVoicePreviewState(
            durationMilliseconds: max(0, durationMilliseconds),
            isPlaying: isPlaying,
            playbackProgress: isPlaying ? min(1, max(0, playbackProgress)) : 0,
            playbackElapsedMilliseconds: isPlaying ? max(0, playbackElapsedMilliseconds) : 0
        )
    }
}

/// 输入栏语音区域展示状态。
@MainActor
enum ChatInputBarVoicePresentation: Equatable {
    /// 无语音态。
    case idle
    /// 正在录音。
    case recording(VoiceRecordingState)
    /// 待发送语音预览。
    case preview(ChatVoicePreviewState)
}

/// 输入栏尾部主操作。
@MainActor
enum ChatInputBarTrailingAction: Equatable {
    /// 显示录音按钮。
    case recordVoice(isEnabled: Bool)
    /// 显示发送按钮。
    case send(isEnabled: Bool)
    /// 隐藏尾部操作。
    case hidden
}

/// 输入栏渲染快照。
@MainActor
struct ChatInputBarRenderState: Equatable {
    /// 输入文本。
    var text: String
    /// 当前输入面板。
    var panel: ChatInputPanel
    /// 待发送附件预览。
    var attachments: [ChatPendingAttachmentPreviewItem]
    /// 语音展示状态。
    var voicePresentation: ChatInputBarVoicePresentation
    /// 尾部主操作。
    var trailingAction: ChatInputBarTrailingAction
    /// 文本是否可编辑。
    var isTextEditable: Bool
    /// 临时状态文案。
    var transientStatus: String?

    /// 空输入态。
    static var initial: ChatInputBarRenderState {
        ChatInputBarRenderState(
            text: "",
            panel: .keyboard,
            attachments: [],
            voicePresentation: .idle,
            trailingAction: .recordVoice(isEnabled: true),
            isTextEditable: true,
            transientStatus: nil
        )
    }
}

/// 输入栏渲染动画意图。
@MainActor
enum ChatInputBarRenderAnimation: Equatable {
    /// 无特殊动画。
    case none
    /// 面板切换动画。
    case panelTransition(from: ChatInputPanel, to: ChatInputPanel)
    /// 高度变化动画。
    case heightChange
}

/// 一次状态转换的结果。
@MainActor
struct ChatInputBarTransition: Equatable {
    /// 转换后的渲染快照。
    var renderState: ChatInputBarRenderState
    /// 本次需要发布给外层的动作。
    var action: ChatInputBarAction?
    /// 渲染动画意图。
    var animation: ChatInputBarRenderAnimation

    static func unchanged(_ renderState: ChatInputBarRenderState) -> ChatInputBarTransition {
        ChatInputBarTransition(renderState: renderState, action: nil, animation: .none)
    }
}

extension ChatPendingAttachmentPreviewItem: Equatable {
    static func == (lhs: ChatPendingAttachmentPreviewItem, rhs: ChatPendingAttachmentPreviewItem) -> Bool {
        lhs.id == rhs.id
            && lhs.image === rhs.image
            && lhs.title == rhs.title
            && lhs.durationText == rhs.durationText
            && lhs.isVideo == rhs.isVideo
            && lhs.isLoading == rhs.isLoading
    }
}
