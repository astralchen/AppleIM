//
//  ChatInputBarStateMachine.swift
//  AppleIM
//

import Foundation

/// 输入栏内部事件。
@MainActor
enum ChatInputBarEvent: Equatable {
    /// 设置输入文本。
    case setText(String)
    /// 设置待发送附件。
    case setAttachments([ChatPendingAttachmentPreviewItem])
    /// 切换输入面板。
    case showPanel(ChatInputPanel)
    /// 设置录音状态。
    case setVoiceRecording(VoiceRecordingState)
    /// 结束录音态。
    case clearVoiceRecording
    /// 设置待发送语音预览。
    case setVoicePreview(ChatVoicePreviewState)
    /// 清除待发送语音预览。
    case clearVoicePreview
    /// 请求发送当前组合内容。
    case sendComposition
    /// 请求开始录音。
    case voiceRecordTapped
    /// 请求停止录音。
    case voiceRecordingStopTapped
    /// 请求取消语音预览。
    case voicePreviewCancel
    /// 请求播放或暂停语音预览。
    case voicePreviewPlayToggle
    /// 请求发送语音预览。
    case voicePreviewSend
    /// 设置临时状态文案。
    case setTransientStatus(String?)
}

/// 聊天输入栏状态机。
@MainActor
struct ChatInputBarStateMachine {
    /// 当前渲染快照。
    private(set) var renderState: ChatInputBarRenderState

    /// 初始化输入栏状态机。
    init(renderState: ChatInputBarRenderState = .initial) {
        self.renderState = renderState
    }

    /// 处理输入栏事件并返回转换结果。
    @discardableResult
    mutating func reduce(_ event: ChatInputBarEvent) -> ChatInputBarTransition {
        let previous = renderState
        var action: ChatInputBarAction?
        var animation: ChatInputBarRenderAnimation = .none

        switch event {
        case let .setText(text):
            guard renderState.isTextEditable else {
                return .unchanged(renderState)
            }
            renderState.text = text

        case let .setAttachments(items):
            guard !isRecording else {
                return .unchanged(renderState)
            }
            renderState.attachments = items

        case let .showPanel(panel):
            guard canSwitchPanel(to: panel) else {
                return .unchanged(renderState)
            }
            renderState.panel = panel
            if previous.panel != panel {
                animation = .panelTransition(from: previous.panel, to: panel)
            }

        case let .setVoiceRecording(recordingState):
            if recordingState.isRecording {
                renderState.voicePresentation = .recording(recordingState)
                renderState.isTextEditable = false
                renderState.panel = .keyboard
            } else if case .recording = renderState.voicePresentation {
                renderState.voicePresentation = .idle
                renderState.isTextEditable = true
            }

        case .clearVoiceRecording:
            if case .recording = renderState.voicePresentation {
                renderState.voicePresentation = .idle
                renderState.isTextEditable = true
            }

        case let .setVoicePreview(preview):
            renderState.voicePresentation = .preview(preview.normalized)
            renderState.isTextEditable = false
            renderState.panel = .keyboard

        case .clearVoicePreview:
            if case .preview = renderState.voicePresentation {
                renderState.voicePresentation = .idle
                renderState.isTextEditable = true
            }

        case .sendComposition:
            guard canSendComposition else {
                return .unchanged(renderState)
            }
            let trimmedText = renderState.text.trimmingCharacters(in: .whitespacesAndNewlines)
            renderState.text = ""
            renderState.attachments = []
            action = .send(trimmedText)

        case .voiceRecordTapped:
            guard canRecordVoice else {
                return .unchanged(renderState)
            }
            action = .voiceRecordTapped

        case .voiceRecordingStopTapped:
            guard isRecording else {
                return .unchanged(renderState)
            }
            action = .voiceRecordingStopTapped

        case .voicePreviewCancel:
            guard hasVoicePreview else {
                return .unchanged(renderState)
            }
            action = .voicePreviewCancel

        case .voicePreviewPlayToggle:
            guard hasVoicePreview else {
                return .unchanged(renderState)
            }
            action = .voicePreviewPlayToggle

        case .voicePreviewSend:
            guard hasVoicePreview else {
                return .unchanged(renderState)
            }
            action = .voicePreviewSend

        case let .setTransientStatus(message):
            renderState.transientStatus = message
            animation = .heightChange
        }

        renderState.trailingAction = makeTrailingAction()
        return ChatInputBarTransition(renderState: renderState, action: action, animation: animation)
    }

    /// 当前是否存在可发送文本。
    var canSendText: Bool {
        !renderState.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 当前是否可以发送文本或附件组合。
    var canSendComposition: Bool {
        guard case .idle = renderState.voicePresentation else { return false }
        return canSendText || hasReadyAttachment
    }

    /// 当前是否可以开始录音。
    var canRecordVoice: Bool {
        guard case .idle = renderState.voicePresentation else { return false }
        return !canSendText && renderState.attachments.isEmpty && renderState.isTextEditable
    }

    /// 当前是否正在录音。
    var isRecording: Bool {
        if case .recording = renderState.voicePresentation {
            return true
        }
        return false
    }

    /// 当前是否存在待发送语音预览。
    var hasVoicePreview: Bool {
        if case .preview = renderState.voicePresentation {
            return true
        }
        return false
    }

    /// 当前是否存在仍在加载的附件。
    var hasLoadingAttachment: Bool {
        renderState.attachments.contains { $0.isLoading }
    }

    /// 当前是否存在可发送附件。
    var hasReadyAttachment: Bool {
        !renderState.attachments.isEmpty && !hasLoadingAttachment
    }

    /// 计算尾部主操作。
    private func makeTrailingAction() -> ChatInputBarTrailingAction {
        switch renderState.voicePresentation {
        case .idle:
            if canSendComposition {
                return .send(isEnabled: true)
            }
            return .recordVoice(isEnabled: canRecordVoice)
        case .recording, .preview:
            return .hidden
        }
    }

    /// 是否允许切换到目标面板。
    private func canSwitchPanel(to panel: ChatInputPanel) -> Bool {
        if panel == .keyboard {
            return true
        }
        guard case .idle = renderState.voicePresentation else {
            return false
        }
        return renderState.isTextEditable
    }
}
