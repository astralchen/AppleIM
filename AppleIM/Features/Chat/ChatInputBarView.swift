//
//  ChatInputBarView.swift
//  AppleIM
//

import UIKit

/// 聊天输入栏对外发布的用户动作。
@MainActor
enum ChatInputBarAction: Equatable {
    /// 文本发生变化。
    case textChanged(String)
    /// 请求发送当前文本或附件组合。
    case send(String)
    /// 请求展示相册输入面板。
    case photoTapped
    /// 请求展示表情输入面板。
    case emojiTapped
    /// 请求从自定义输入面板切回系统键盘。
    case keyboardInputRequested
    /// 移除待发送附件。
    case attachmentRemoved(String)
    /// 点按语音按钮开始录音。
    case voiceRecordTapped
    /// 点按停止按钮完成录音。
    case voiceRecordingStopTapped
    /// 取消待发送语音预览。
    case voicePreviewCancel
    /// 播放或暂停待发送语音预览。
    case voicePreviewPlayToggle
    /// 发送待发送语音预览。
    case voicePreviewSend
}

/// 聊天输入栏布局变化协调。
@MainActor
protocol ChatInputBarLayoutDelegate: AnyObject {
    /// 输入栏高度变化前询问外层是否需要保持消息列表贴底。
    func chatInputBarWillChangeHeight(_ inputBar: ChatInputBarView) -> Bool
    /// 输入栏高度变化后通知外层完成消息列表位置修正。
    func chatInputBar(_ inputBar: ChatInputBarView, didChangeHeightKeepingBottom shouldStickToBottom: Bool)
}

/// 待处理附件预览项
///
/// 用于在输入框上方展示待发送的图片或视频预览
@MainActor
struct ChatPendingAttachmentPreviewItem {
    /// 附件唯一标识
    let id: String
    /// 预览图片
    let image: UIImage?
    /// 标题（文件名或描述）
    let title: String
    /// 时长文本（视频消息）
    let durationText: String?
    /// 是否为视频
    let isVideo: Bool
    /// 是否正在加载
    let isLoading: Bool
}

/// 聊天输入框视图
///
/// ## 职责
///
/// 1. 管理文本输入和编辑
/// 2. 展示待发送附件预览
/// 3. 处理语音录制状态展示
/// 4. 切换发送按钮和语音按钮
/// 5. 支持相册输入视图切换
/// 6. 动态调整输入框高度（最多 5 行）
///
/// ## 并发安全
///
/// - 标记为 `@MainActor`，所有方法和属性访问都在主线程
///
/// ## 事件模型
///
/// - 用户动作通过 `onAction` 发布强类型动作载荷。
/// - 高度变化通过 `ChatInputBarLayoutDelegate` 协调。
@MainActor
final class ChatInputBarView: UIView {
    /// 当前输入模式。
    private typealias InputMode = ChatInputPanel

    /// 用户动作回调。
    var onAction: ((ChatInputBarAction) -> Void)?
    /// 文本变更拦截器，用于把已插入的 @ 成员当成一个整体编辑。
    var textChangeReplacementProvider: ((String, NSRange, String) -> ChatMentionDeletionReplacement?)?
    /// 布局变化协调代理。
    weak var layoutDelegate: ChatInputBarLayoutDelegate?

    /// 输入栏整条轻量材质背景。
    private let inputSurfaceBackgroundView = ChatInputSurfaceBackgroundView(
        style: .inputBar,
        accessibilityPrefix: "chat.inputBar"
    )
    /// 根内容栈
    private let contentStackView = UIStackView()
    /// 录音临时状态标签
    private let recordingStatusLabel = UILabel()
    /// 附件预览横向轨道
    private let attachmentPreviewRailView = ChatAttachmentPreviewRailView()
    /// 输入区域横向栈
    private let inputStackView = UIStackView()
    /// 更多操作按钮
    private let moreButton = UIButton(type: .system)
    /// 文本输入胶囊
    private let composerFieldView = ChatComposerFieldView()
    /// 自定义输入面板容器，和输入行共享同一个根材质背景。
    private let customPanelContainerView = UIView()
    /// 输入栏状态机，集中维护文本、附件、语音和面板状态。
    private var stateMachine = ChatInputBarStateMachine()

    /// 文本输入高度约束
    private var textInputHeightConstraint: NSLayoutConstraint?
    /// 自定义输入面板高度约束
    private var customPanelHeightConstraint: NSLayoutConstraint?
    /// 根内容栈底部约束；自定义面板显示时贴到输入栏底部，普通输入模式保留底部边距。
    private var contentStackBottomConstraint: NSLayoutConstraint?
    /// 当前输入模式
    private var inputMode: InputMode = .keyboard
    /// 等待系统键盘动画接管时保留的旧自定义面板。
    private var deferredKeyboardCollapsePanel: InputMode?
    /// 等待系统键盘收起动画接管时准备展示的新自定义面板。
    private var deferredCustomPanelPresentation: InputMode?
    /// 已安装的图片库输入面板
    private weak var photoLibraryInputView: ChatPhotoLibraryInputView?
    /// 已安装的表情输入面板
    private weak var emojiPanelView: ChatEmojiPanelView?
    /// 是否正在录音
    private var isRecording = false
    /// 是否存在待发送语音预览
    private var hasPendingVoicePreview = false
    /// 待发送语音预览是否正在播放
    private var isPendingVoicePreviewPlaying = false
    /// 待发送语音预览时长
    private var pendingVoicePreviewDurationMilliseconds = 0
    /// 待发送语音预览播放进度
    private var pendingVoicePreviewPlaybackProgress: Double = 0
    /// 待发送语音预览已播放时长
    private var pendingVoicePreviewElapsedMilliseconds = 0
    /// 是否正在等待控制器完成相册面板到系统键盘的切换
    private var isWaitingForKeyboardInputTransition = false
    /// 是否存在待发送附件
    private var hasPendingAttachment = false
    /// 待发送附件是否仍在加载
    private var isPendingAttachmentLoading = false
    /// 当前待发送附件预览项
    private var pendingAttachmentPreviewItems: [ChatPendingAttachmentPreviewItem] = []
    /// 最近一次测量的文本宽度
    private var lastMeasuredTextWidth: CGFloat = 0
    /// 最近一次参与高度测量的文本。
    private var lastMeasuredText = ""
    /// 临时状态自动隐藏任务
    private var statusHideTask: Task<Void, Never>?
    /// 输入栏向底部安全区外延展时，内容需要避让的高度。
    private var bottomSafeAreaExtension: CGFloat = 0
#if DEBUG
    /// 测试用：模拟 `resignFirstResponder()` 同步触发键盘 frame 通知。
    var keyboardDismissFrameNotificationHookForTesting: (() -> Void)?
#endif

    /// 当前输入文本
    var text: String {
        stateMachine.renderState.text
    }

    /// 文本输入框是否正在编辑
    var isEditingText: Bool {
        composerFieldView.isEditingText
    }

    /// 当前是否可发送文本
    private var canSendText: Bool {
        stateMachine.canSendText
    }

    /// 当前是否可发送文本或附件组合
    private var canSendComposition: Bool {
        stateMachine.canSendComposition
    }

    /// 当前是否可开始语音录制
    private var canRecordVoice: Bool {
        stateMachine.canRecordVoice
    }

    /// 录音态输入胶囊高度，容纳 Apple Messages 风格的 52pt 停止按钮。
    private static let recordingInputHeight: CGFloat = 64
    /// 普通输入模式下，输入行底部保留的视觉呼吸空间。
    private static let defaultContentBottomInset: CGFloat = 6

    /// 初始化输入栏
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
        renderTrailingActionState()
    }

    /// 从 storyboard/xib 初始化输入栏
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
        renderTrailingActionState()
    }

    /// 取消临时状态隐藏任务
    deinit {
        statusHideTask?.cancel()
    }

    /// 布局变化时重新测量文本输入高度
    override func layoutSubviews() {
        super.layoutSubviews()
        defer { normalizeAttachmentPreviewScrollOffset() }

        let width = composerFieldView.textInputWidth
        let text = composerFieldView.text
        guard abs(width - lastMeasuredTextWidth) > 0.5 || text != lastMeasuredText else { return }
        lastMeasuredTextWidth = width
        lastMeasuredText = text
        updateTextViewHeight(animated: false)
    }

    /// 设置文本内容
    ///
    /// - Parameters:
    ///   - text: 要设置的文本
    ///   - animated: 是否动画更新高度
    func setText(_ text: String, animated: Bool) {
        guard composerFieldView.text != text else { return }
        stateMachine.reduce(.setText(text))
        composerFieldView.setText(text)
        renderTextViewPlaceholder()
        renderTrailingActionState()
        updateTextViewHeight(animated: animated)
    }

    /// 渲染语音录制状态
    ///
    /// 根据录制状态更新 UI：
    /// - 显示/隐藏录制胶囊视图
    /// - 更新录制时长
    /// - 更新音量电平计
    /// - 更新取消提示
    ///
    /// - Parameter state: 语音录制状态
    func renderVoiceRecordingState(_ state: VoiceRecordingState) {
        let event: ChatInputBarEvent = state.isRecording ? .setVoiceRecording(state) : .clearVoiceRecording
        stateMachine.reduce(event)
        isRecording = state.isRecording
        recordingStatusLabel.isHidden = true
        recordingStatusLabel.text = nil
        moreButton.isEnabled = !state.isRecording
        moreButton.isHidden = state.isRecording

        renderRecordingCapsule(state)
        composerFieldView.setTextEditable(!state.isRecording)
        updateTextViewHeight(animated: false)
        renderMoreButtonState(animated: false)
        renderTextViewPlaceholder()
        renderTrailingActionState()
    }

    /// 显示临时状态消息
    ///
    /// 在录制状态标签位置显示临时消息，1.4 秒后自动隐藏
    ///
    /// - Parameter message: 要显示的消息文本
    func showTransientStatus(_ message: String) {
        statusHideTask?.cancel()
        let wasHidden = recordingStatusLabel.isHidden
        let changes = { [weak self] in
            guard let self else { return }
            self.recordingStatusLabel.isHidden = false
            self.recordingStatusLabel.text = message
            self.recordingStatusLabel.textColor = .secondaryLabel
        }
        if wasHidden {
            performHeightChange(animated: false, changes: changes)
        } else {
            changes()
        }

        statusHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            self?.hideTransientStatusIfNeeded()
        }
    }

    /// 切换到相册输入面板。
    @discardableResult
    func showPhotoLibraryInput() -> Bool {
        showCustomInputPanel(.photoLibrary)
    }

    /// 切换到表情输入面板。
    @discardableResult
    func showEmojiInput() -> Bool {
        showCustomInputPanel(.emoji)
    }

    /// 切换回系统键盘输入
    @discardableResult
    func showKeyboardInput() -> Bool {
        isWaitingForKeyboardInputTransition = false
        deferredCustomPanelPresentation = nil
        stateMachine.reduce(.showPanel(.keyboard))

        let shouldDeferCustomPanelCollapse = inputMode.isCustomPanel && !customPanelContainerView.isHidden
        if shouldDeferCustomPanelCollapse {
            // 这里不能先把自定义面板高度收成 0：keyboardLayoutGuide 往往要等键盘通知后一轮才稳定，
            // 提前折叠会让输入栏先落回屏幕底部，再被系统键盘抬起，用户看到的就是一次明显抖动。
            // 所以先把模式切回键盘以允许 UITextView 成为 first responder，但旧面板仍作为过渡桥留在原位。
            deferredKeyboardCollapsePanel = inputMode
            inputMode = .keyboard
        } else {
            hideCustomPanel(animated: true)
        }

        composerFieldView.showKeyboardInput()
        return shouldDeferCustomPanelCollapse
    }

    /// 仅关闭自定义输入面板，不主动唤起系统键盘。
    func hideCustomInputPanel(animated: Bool) {
        isWaitingForKeyboardInputTransition = false
        deferredKeyboardCollapsePanel = nil
        deferredCustomPanelPresentation = nil
        stateMachine.reduce(.showPanel(.keyboard))
        composerFieldView.clearCustomInputView()
        hideCustomPanel(animated: animated)
    }

    /// 在系统键盘动画事务里折叠保留的旧面板。
    func applyDeferredKeyboardPanelCollapse() {
        guard let panel = deferredKeyboardCollapsePanel else { return }
        panelView(for: panel)?.alpha = 0
        panelView(for: panel)?.isHidden = true
        customPanelHeightConstraint?.constant = 0
        setContentStackExtendsToBottom(false)
    }

    /// 系统键盘动画结束后真正隐藏旧面板。
    func finalizeDeferredKeyboardPanelCollapse() {
        guard let panel = deferredKeyboardCollapsePanel else { return }
        // 只在仍处于键盘模式时收尾；如果用户快速切到了另一个面板，不能把新的目标面板一起藏掉。
        guard inputMode == .keyboard else {
            deferredKeyboardCollapsePanel = nil
            return
        }

        panelView(for: panel)?.isHidden = true
        panelView(for: panel)?.alpha = 1
        customPanelHeightConstraint?.constant = 0
        customPanelContainerView.isHidden = true
        setContentStackExtendsToBottom(false)
        deferredKeyboardCollapsePanel = nil
    }

    /// 在系统键盘收起动画事务里展开目标自定义面板。
    func applyDeferredCustomPanelPresentation() {
        guard
            let panel = deferredCustomPanelPresentation,
            let targetHeight = customPanelHeight(for: panel)
        else { return }

        stateMachine.reduce(.showPanel(panel))
        inputMode = panel
        customPanelContainerView.isHidden = false
        photoLibraryInputView?.isHidden = panel != .photoLibrary
        emojiPanelView?.isHidden = panel != .emoji
        photoLibraryInputView?.alpha = 1
        emojiPanelView?.alpha = 1
        customPanelHeightConstraint?.constant = targetHeight
        setContentStackExtendsToBottom(true)
    }

    /// 系统键盘收起动画结束后清理延迟展示状态。
    func finalizeDeferredCustomPanelPresentation() {
        guard let panel = deferredCustomPanelPresentation else { return }
        // 快速连续切换时，只在当前仍是这次目标面板时收尾，避免误改新目标的可见状态。
        if inputMode == panel {
            hideInactiveCustomPanel(panel == .photoLibrary ? .emoji : .photoLibrary, expectedCurrentPanel: panel)
        }
        deferredCustomPanelPresentation = nil
    }

    /// 安装图片库输入面板，由输入栏统一承载背景和布局。
    func installPhotoLibraryInputView(_ inputView: ChatPhotoLibraryInputView) {
        if let photoLibraryInputView, photoLibraryInputView !== inputView {
            photoLibraryInputView.removeFromSuperview()
        }
        photoLibraryInputView = inputView
        installCustomPanelView(inputView)
        inputView.isHidden = inputMode != .photoLibrary
    }

    /// 安装表情输入面板，由输入栏统一承载背景和布局。
    func installEmojiPanelView(_ panelView: ChatEmojiPanelView) {
        if let emojiPanelView, emojiPanelView !== panelView {
            emojiPanelView.removeFromSuperview()
        }
        emojiPanelView = panelView
        installCustomPanelView(panelView)
        panelView.isHidden = inputMode != .emoji
    }

    /// 设置输入栏需要覆盖的底部安全区高度。
    func setCustomPanelBottomSafeAreaExtension(_ extensionHeight: CGFloat) {
        let normalizedHeight = max(0, extensionHeight.rounded(.toNearestOrAwayFromZero))
        guard bottomSafeAreaExtension != normalizedHeight else { return }

        bottomSafeAreaExtension = normalizedHeight
        setContentStackExtendsToBottom(inputMode.isCustomPanel || deferredCustomPanelPresentation != nil)
        let visiblePanel: InputMode?
        if inputMode.isCustomPanel {
            visiblePanel = inputMode
        } else {
            visiblePanel = deferredKeyboardCollapsePanel
        }
        guard
            let visiblePanel,
            let targetHeight = customPanelHeight(for: visiblePanel)
        else { return }

        customPanelHeightConstraint?.constant = targetHeight
    }

    /// 把自定义输入面板安装到统一输入区内容容器。
    private func installCustomPanelView(_ panelView: UIView) {
        guard panelView.superview !== customPanelContainerView else { return }

        panelView.removeFromSuperview()
        panelView.translatesAutoresizingMaskIntoConstraints = false
        customPanelContainerView.addSubview(panelView)
        NSLayoutConstraint.activate([
            panelView.topAnchor.constraint(equalTo: customPanelContainerView.topAnchor),
            panelView.leadingAnchor.constraint(equalTo: customPanelContainerView.leadingAnchor),
            panelView.trailingAnchor.constraint(equalTo: customPanelContainerView.trailingAnchor),
            panelView.bottomAnchor.constraint(equalTo: customPanelContainerView.bottomAnchor)
        ])
    }

    /// 切换到指定自定义输入面板。
    @discardableResult
    private func showCustomInputPanel(_ panel: InputMode) -> Bool {
        isWaitingForKeyboardInputTransition = false
        deferredKeyboardCollapsePanel = nil

        guard panel.isCustomPanel else { return false }
        let transition = stateMachine.reduce(.showPanel(panel))
        guard transition.renderState.panel == panel else { return false }

        if inputMode == .keyboard && composerFieldView.isEditingText {
            // 从系统键盘切到自定义面板时，不能立刻展开面板高度；否则输入栏会跟随内部高度先顶起，
            // 随后 keyboardLayoutGuide 再下落，两个动画事务分离就会形成用户看到的强抖动。
            // 这里只记录目标面板并让 UITextView 退键盘，真正展开交给控制器放进 keyboardWillChangeFrame。
            deferredCustomPanelPresentation = panel
#if DEBUG
            keyboardDismissFrameNotificationHookForTesting?()
#endif
            composerFieldView.prepareForCustomInput()
            return true
        }

        deferredCustomPanelPresentation = nil
        composerFieldView.prepareForCustomInput()
        showCustomPanel(panel, animated: true)
        return false
    }

    /// 展示指定自定义输入面板，并让统一背景覆盖输入行和面板。
    private func showCustomPanel(_ panel: InputMode, animated: Bool) {
        let previousMode = inputMode
        deferredKeyboardCollapsePanel = nil
        deferredCustomPanelPresentation = nil
        stateMachine.reduce(.showPanel(panel))
        inputMode = panel

        guard let targetHeight = customPanelHeight(for: panel) else {
            return
        }

        let sourcePanel = previousMode.isCustomPanel && previousMode != panel ? previousMode : nil
        let targetView = panelView(for: panel)
        let sourceView = sourcePanel.flatMap { panelView(for: $0) }
        let hasLayoutChange = previousMode != panel
            || customPanelContainerView.isHidden
            || customPanelHeightConstraint?.constant != targetHeight

        if let sourceView {
            sourceView.isHidden = false
            sourceView.alpha = 1
            targetView?.isHidden = false
            targetView?.alpha = 0
        }

        let changes = { [weak self] in
            guard let self else { return }
            if sourceView == nil {
                self.photoLibraryInputView?.isHidden = panel != .photoLibrary
                self.emojiPanelView?.isHidden = panel != .emoji
                targetView?.alpha = 1
            } else {
                // 面板之间直接切换时保留来源面板到动画结束，避免输入区中途露出空洞或高度跳变。
                sourceView?.alpha = 0
                targetView?.alpha = 1
            }
            self.customPanelContainerView.isHidden = false
            self.customPanelHeightConstraint?.constant = targetHeight
            self.setContentStackExtendsToBottom(true)
        }
        let completion = { [weak self] in
            guard let self else { return }
            self.hideInactiveCustomPanel(sourcePanel, expectedCurrentPanel: panel)
        }

        guard hasLayoutChange else {
            changes()
            completion()
            return
        }
        performHeightChange(animated: animated, changes: changes, completion: completion)
    }

    /// 隐藏当前自定义输入面板，恢复只显示输入行和待发送预览。
    private func hideCustomPanel(animated: Bool) {
        guard inputMode.isCustomPanel || !customPanelContainerView.isHidden else { return }
        deferredKeyboardCollapsePanel = nil
        deferredCustomPanelPresentation = nil
        stateMachine.reduce(.showPanel(.keyboard))
        inputMode = .keyboard

        let changes = { [weak self] in
            guard let self else { return }
            self.photoLibraryInputView?.isHidden = true
            self.emojiPanelView?.isHidden = true
            self.customPanelHeightConstraint?.constant = 0
            self.customPanelContainerView.isHidden = true
            self.setContentStackExtendsToBottom(false)
        }
        performHeightChange(animated: animated, changes: changes)
    }

    /// 自定义输入面板显示时让内容栈贴到输入栏真实底部，普通输入模式保留底部边距。
    private func setContentStackExtendsToBottom(_ extendsToBottom: Bool) {
        let contentBottomInset = Self.defaultContentBottomInset + bottomSafeAreaExtension
        contentStackBottomConstraint?.constant = extendsToBottom ? 0 : -contentBottomInset
    }

    /// 查找指定输入面板对应的内容视图。
    private func panelView(for panel: InputMode) -> UIView? {
        switch panel {
        case .photoLibrary:
            return photoLibraryInputView
        case .emoji:
            return emojiPanelView
        case .keyboard:
            return nil
        }
    }

    /// 读取指定输入面板的稳定高度；面板未安装时返回 nil，避免提前改变布局。
    private func customPanelHeight(for panel: InputMode) -> CGFloat? {
        switch panel {
        case .photoLibrary:
            guard photoLibraryInputView != nil else { return nil }
            return ChatPhotoLibraryInputView.panelHeight + bottomSafeAreaExtension
        case .emoji:
            guard emojiPanelView != nil else { return nil }
            return ChatEmojiPanelView.panelHeight + bottomSafeAreaExtension
        case .keyboard:
            return nil
        }
    }

    /// 隐藏已经退出当前输入目标的旧面板，防止快速连续切换时误藏新面板。
    private func hideInactiveCustomPanel(_ panel: InputMode?, expectedCurrentPanel: InputMode) {
        guard
            let panel,
            panel != expectedCurrentPanel,
            inputMode == expectedCurrentPanel
        else { return }

        panelView(for: panel)?.isHidden = true
        panelView(for: panel)?.alpha = 1
    }

    /// 设置单个待发送附件预览
    func setPendingAttachmentPreview(
        image: UIImage?,
        title: String,
        durationText: String?,
        isVideo: Bool,
        isLoading: Bool,
        animated: Bool
    ) {
        setPendingAttachmentPreviews([
            ChatPendingAttachmentPreviewItem(
                id: "single",
                image: image,
                title: title,
                durationText: durationText,
                isVideo: isVideo,
                isLoading: isLoading
            )
        ], animated: animated)
    }

    /// 设置多个待发送附件预览
    func setPendingAttachmentPreviews(_ items: [ChatPendingAttachmentPreviewItem], animated: Bool) {
        stateMachine.reduce(.setAttachments(items))
        pendingAttachmentPreviewItems = items
        hasPendingAttachment = !items.isEmpty
        isPendingAttachmentLoading = items.contains { $0.isLoading }
        attachmentPreviewRailView.render(items)
        normalizeAttachmentPreviewScrollOffset()
        setAttachmentPreviewHidden(items.isEmpty, animated: animated)
        renderTrailingActionState()
    }

    /// 清空单个待发送附件预览
    func clearPendingAttachmentPreview(animated: Bool) {
        clearPendingAttachmentPreviews(animated: animated)
    }

    /// 清空所有待发送附件预览
    func clearPendingAttachmentPreviews(animated: Bool) {
        stateMachine.reduce(.setAttachments([]))
        pendingAttachmentPreviewItems.removeAll()
        hasPendingAttachment = false
        isPendingAttachmentLoading = false
        attachmentPreviewRailView.render([])
        normalizeAttachmentPreviewScrollOffset()
        setAttachmentPreviewHidden(true, animated: animated)
        renderTrailingActionState()
    }

    /// 展示待发送语音预览。
    ///
    /// 录音完成后先进入预览态，用户可以取消、播放确认或手动发送。
    func setPendingVoicePreview(
        durationMilliseconds: Int,
        isPlaying: Bool,
        playbackProgress: Double = 0,
        playbackElapsedMilliseconds: Int = 0,
        animated: Bool
    ) {
        let previewState = ChatVoicePreviewState(
            durationMilliseconds: durationMilliseconds,
            isPlaying: isPlaying,
            playbackProgress: playbackProgress,
            playbackElapsedMilliseconds: playbackElapsedMilliseconds
        ).normalized
        stateMachine.reduce(.setVoicePreview(previewState))
        hasPendingVoicePreview = true
        isPendingVoicePreviewPlaying = previewState.isPlaying
        pendingVoicePreviewDurationMilliseconds = previewState.durationMilliseconds
        pendingVoicePreviewPlaybackProgress = previewState.playbackProgress
        pendingVoicePreviewElapsedMilliseconds = previewState.playbackElapsedMilliseconds
        composerFieldView.setTextEditable(false)
        moreButton.isHidden = false
        renderMoreButtonState(animated: animated)
        renderVoicePreviewCapsule()
        setVoicePreviewHidden(false, animated: animated)
        renderTextViewPlaceholder()
        renderTrailingActionState()
    }

    /// 清空待发送语音预览并恢复普通输入态。
    func clearPendingVoicePreview(animated: Bool) {
        stateMachine.reduce(.clearVoicePreview)
        hasPendingVoicePreview = false
        isPendingVoicePreviewPlaying = false
        pendingVoicePreviewDurationMilliseconds = 0
        pendingVoicePreviewPlaybackProgress = 0
        pendingVoicePreviewElapsedMilliseconds = 0
        composerFieldView.setTextEditable(true)
        moreButton.isHidden = false
        renderMoreButtonState(animated: animated)
        setVoicePreviewHidden(true, animated: animated)
        renderTextViewPlaceholder()
        renderTrailingActionState()
    }

    /// 配置输入栏视图层级和约束
    private func configureView() {
        backgroundColor = .clear
        insetsLayoutMarginsFromSafeArea = false
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)

        inputSurfaceBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.axis = .vertical
        contentStackView.alignment = .fill
        contentStackView.spacing = 4
        customPanelContainerView.translatesAutoresizingMaskIntoConstraints = false
        customPanelContainerView.backgroundColor = .clear
        customPanelContainerView.clipsToBounds = true
        customPanelContainerView.isHidden = true

        inputStackView.translatesAutoresizingMaskIntoConstraints = false
        inputStackView.axis = .horizontal
        inputStackView.alignment = .bottom
        inputStackView.spacing = 8
        inputStackView.distribution = .fill

        configureMoreButton()
        configureAttachmentPreviewRailView()
        configureComposerFieldView()
        configureRecordingStatusLabel()

        addSubview(inputSurfaceBackgroundView)
        addSubview(contentStackView)

        contentStackView.addArrangedSubview(recordingStatusLabel)
        contentStackView.addArrangedSubview(attachmentPreviewRailView)
        contentStackView.addArrangedSubview(inputStackView)
        contentStackView.addArrangedSubview(customPanelContainerView)
        attachmentPreviewRailView.isHidden = true

        inputStackView.addArrangedSubview(moreButton)
        inputStackView.addArrangedSubview(composerFieldView)

        let textInputHeightConstraint = composerFieldView.heightAnchor.constraint(equalToConstant: 44)
        self.textInputHeightConstraint = textInputHeightConstraint
        let customPanelHeightConstraint = customPanelContainerView.heightAnchor.constraint(equalToConstant: 0)
        self.customPanelHeightConstraint = customPanelHeightConstraint
        let contentStackBottomConstraint = contentStackView.bottomAnchor.constraint(
            equalTo: bottomAnchor,
            constant: -Self.defaultContentBottomInset
        )
        self.contentStackBottomConstraint = contentStackBottomConstraint

        NSLayoutConstraint.activate([
            inputSurfaceBackgroundView.topAnchor.constraint(equalTo: topAnchor),
            inputSurfaceBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputSurfaceBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputSurfaceBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            contentStackView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            contentStackBottomConstraint,

            moreButton.widthAnchor.constraint(equalToConstant: 44),
            moreButton.heightAnchor.constraint(equalToConstant: 44),
            textInputHeightConstraint,
            customPanelHeightConstraint
        ])
    }

    /// 配置更多操作按钮
    private func configureMoreButton() {
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "plus")
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        configuration.baseForegroundColor = .label
        configuration.baseBackgroundColor = ChatInputBarStyling.defaultTextInputTintColor
        moreButton.configuration = configuration
        moreButton.layer.cornerRadius = 22
        moreButton.layer.shadowColor = UIColor.black.cgColor
        moreButton.layer.shadowOpacity = 0.025
        moreButton.layer.shadowRadius = 6
        moreButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        moreButton.accessibilityLabel = "More"
        moreButton.accessibilityIdentifier = "chat.moreButton"
        moreButton.setContentHuggingPriority(.required, for: .horizontal)
        moreButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.menu = makeMoreMenu()
        moreButton.addTarget(self, action: #selector(moreButtonTapped), for: .touchUpInside)
    }

    /// 配置附件预览轨道
    private func configureAttachmentPreviewRailView() {
        attachmentPreviewRailView.translatesAutoresizingMaskIntoConstraints = false
        attachmentPreviewRailView.onRemoveItem = { [weak self] id in
            self?.removeAttachmentPreviewItem(id: id)
        }
    }

    /// 配置文本输入胶囊
    private func configureComposerFieldView() {
        composerFieldView.translatesAutoresizingMaskIntoConstraints = false
        composerFieldView.textViewDelegate = self
        composerFieldView.onAction = { [weak self] action in
            self?.handleComposerFieldAction(action)
        }
    }

    /// 配置录音状态标签
    private func configureRecordingStatusLabel() {
        recordingStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        recordingStatusLabel.font = .preferredFont(forTextStyle: .caption1)
        recordingStatusLabel.adjustsFontForContentSizeCategory = true
        recordingStatusLabel.textAlignment = .center
        recordingStatusLabel.textColor = .secondaryLabel
        recordingStatusLabel.isHidden = true
    }

    /// 修正附件预览横向滚动视图的垂直偏移
    private func normalizeAttachmentPreviewScrollOffset() {
        attachmentPreviewRailView.normalizeVerticalContentOffset()
    }

    /// 移除指定附件预览项
    private func removeAttachmentPreviewItem(id: String) {
        guard pendingAttachmentPreviewItems.contains(where: { $0.id == id }) else { return }
        pendingAttachmentPreviewItems.removeAll { $0.id == id }
        stateMachine.reduce(.setAttachments(pendingAttachmentPreviewItems))
        hasPendingAttachment = !pendingAttachmentPreviewItems.isEmpty
        isPendingAttachmentLoading = pendingAttachmentPreviewItems.contains { $0.isLoading }
        attachmentPreviewRailView.render(pendingAttachmentPreviewItems)
        setAttachmentPreviewHidden(pendingAttachmentPreviewItems.isEmpty, animated: true)
        renderTrailingActionState()
        publish(.attachmentRemoved(id))
    }

    /// 处理文本输入胶囊发布的动作
    private func handleComposerFieldAction(_ action: ChatComposerFieldAction) {
        switch action {
        case .voiceRecordTapped:
            voiceRecordButtonTapped()
        case .voiceRecordingStopTapped:
            voiceRecordingStopButtonTapped()
        case .sendTapped:
            sendButtonTapped()
        case .voicePreviewPlayToggle:
            voicePreviewPlayButtonTapped()
        case .voicePreviewSend:
            voicePreviewSendButtonTapped()
        }
    }

    /// 语音按钮点按事件
    private func voiceRecordButtonTapped() {
        publish(stateMachine.reduce(.voiceRecordTapped).action)
    }

    /// 录音停止按钮点按事件
    private func voiceRecordingStopButtonTapped() {
        publish(stateMachine.reduce(.voiceRecordingStopTapped).action)
    }

    /// 发送按钮点击事件
    private func sendButtonTapped() {
        guard canSendComposition, composerFieldView.isTextEditable else { return }
        sendCurrentComposition()
    }

    /// 待发送语音播放按钮点击事件
    private func voicePreviewPlayButtonTapped() {
        publish(stateMachine.reduce(.voicePreviewPlayToggle).action)
    }

    /// 待发送语音发送按钮点击事件
    private func voicePreviewSendButtonTapped() {
        publish(stateMachine.reduce(.voicePreviewSend).action)
    }

    /// 发送当前输入组合
    private func sendCurrentComposition() {
        let transition = stateMachine.reduce(.sendComposition)
        guard let action = transition.action else { return }

        composerFieldView.clearText()
        renderTextViewPlaceholder()
        renderTrailingActionState()
        updateTextViewHeight(animated: true)
        publish(.textChanged(""))
        publish(action)
    }

    /// 渲染尾部按钮的发送或录音状态
    private func renderTrailingActionState() {
        let showsSend = canSendComposition && composerFieldView.isTextEditable

        let hidesTrailingAction = isRecording || hasPendingVoicePreview
        composerFieldView.renderTrailingAction(
            showsSend: showsSend,
            hidesTrailingAction: hidesTrailingAction,
            isEnabled: isRecording || showsSend || canRecordVoice
        )
    }

    /// 显示或隐藏附件预览区域
    private func setAttachmentPreviewHidden(_ isHidden: Bool, animated: Bool) {
        guard attachmentPreviewRailView.isHidden != isHidden else { return }

        let shouldStickToBottom = layoutDelegate?.chatInputBarWillChangeHeight(self) ?? false
        let layoutChanges = { [weak self] in
            guard let self else { return }
            self.attachmentPreviewRailView.isHidden = isHidden
            self.superview?.layoutIfNeeded()
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            self.layoutDelegate?.chatInputBar(self, didChangeHeightKeepingBottom: shouldStickToBottom)
        }

        if animated {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: layoutChanges,
                completion: completion
            )
        } else {
            layoutChanges()
            completion(true)
        }
    }

    /// 渲染文本输入占位状态
    private func renderTextViewPlaceholder() {
        let hidesTextInput = isRecording || hasPendingVoicePreview
        composerFieldView.renderTextInputVisibility(hidesTextInput: hidesTextInput)
    }

    /// 渲染录音胶囊状态
    private func renderRecordingCapsule(_ state: VoiceRecordingState) {
        composerFieldView.renderRecording(state)
    }

    /// 渲染待发送语音预览
    private func renderVoicePreviewCapsule() {
        composerFieldView.renderVoicePreview(
            durationMilliseconds: pendingVoicePreviewDurationMilliseconds,
            isPlaying: isPendingVoicePreviewPlaying,
            playbackProgress: pendingVoicePreviewPlaybackProgress,
            elapsedMilliseconds: pendingVoicePreviewElapsedMilliseconds
        )
    }

    /// 显示或隐藏待发送语音预览
    private func setVoicePreviewHidden(_ isHidden: Bool, animated: Bool) {
        guard composerFieldView.prepareVoicePreviewHidden(isHidden) else { return }

        let animations = { [weak self] in
            guard let self else { return }
            self.composerFieldView.applyVoicePreviewHidden(isHidden)
        }
        performHeightChange(animated: animated, duration: 0.18, changes: animations)
    }

    /// 根据内容更新文本输入高度
    private func updateTextViewHeight(animated: Bool) {
        let targetHeight: CGFloat
        let shouldScroll: Bool
        if isRecording {
            targetHeight = Self.recordingInputHeight
            shouldScroll = false
        } else {
            let measurement = composerFieldView.measureTextHeight(maximumHeight: maximumTextViewHeight())
            targetHeight = measurement.targetHeight
            shouldScroll = measurement.shouldScroll
        }

        guard textInputHeightConstraint?.constant != targetHeight else {
            composerFieldView.setTextScrollEnabled(shouldScroll)
            return
        }

        let shouldStickToBottom = layoutDelegate?.chatInputBarWillChangeHeight(self) ?? false
        composerFieldView.setTextScrollEnabled(shouldScroll)
        textInputHeightConstraint?.constant = targetHeight

        let layoutChanges = { [weak self] in
            guard let self else { return }
            self.layoutIfNeeded()
            self.superview?.layoutIfNeeded()
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            self.layoutDelegate?.chatInputBar(self, didChangeHeightKeepingBottom: shouldStickToBottom)
        }

        if animated && window != nil {
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: layoutChanges,
                completion: completion
            )
        } else {
            layoutChanges()
            completion(true)
        }
    }

    /// 隐藏临时状态时也通知控制器，因为状态标签是竖向栈的一部分。
    private func hideTransientStatusIfNeeded() {
        guard !recordingStatusLabel.isHidden else { return }
        performHeightChange(animated: false) { [weak self] in
            guard let self else { return }
            self.recordingStatusLabel.isHidden = true
        }
    }

    /// 统一通知输入栏整体高度变化，控制器据此维护消息底部不被输入栏遮挡。
    private func performHeightChange(
        animated: Bool,
        duration: TimeInterval = 0.2,
        changes: @escaping () -> Void,
        completion externalCompletion: (() -> Void)? = nil
    ) {
        let shouldStickToBottom = layoutDelegate?.chatInputBarWillChangeHeight(self) ?? false
        let layoutChanges = { [weak self] in
            changes()
            self?.superview?.layoutIfNeeded()
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            self.layoutDelegate?.chatInputBar(self, didChangeHeightKeepingBottom: shouldStickToBottom)
            externalCompletion?()
        }

        if animated && window != nil {
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: layoutChanges,
                completion: completion
            )
        } else {
            layoutChanges()
            completion(true)
        }
    }

    /// 文本输入最大高度
    private func maximumTextViewHeight() -> CGFloat {
        composerFieldView.maximumTextHeight(maximumLineCount: 5)
    }

    /// 发布输入栏用户动作。
    private func publish(_ action: ChatInputBarAction?) {
        guard let action else { return }
        onAction?(action)
    }

    /// 请求展示表情输入面板。
    func requestEmojiInput() {
        publish(.emojiTapped)
    }

    /// 请求展示相册输入面板。
    func requestPhotoLibraryInput() {
        publish(.photoTapped)
    }

    /// 创建更多操作菜单
    private func makeMoreMenu() -> UIMenu {
        let emojiAction = UIAction(
            title: "表情",
            image: UIImage(systemName: "face.smiling")
        ) { [weak self] _ in
            Task { @MainActor in
                self?.requestEmojiInput()
            }
        }
        let photoAction = UIAction(
            title: "相册",
            image: UIImage(systemName: "photo.on.rectangle")
        ) { [weak self] _ in
            Task { @MainActor in
                self?.requestPhotoLibraryInput()
            }
        }

        return UIMenu(children: [emojiAction, photoAction])
    }

    /// 点击更多按钮。预览态下该按钮变为删除待发送语音。
    @objc private func moreButtonTapped() {
        guard hasPendingVoicePreview else { return }
        publish(stateMachine.reduce(.voicePreviewCancel).action)
    }

    /// 根据当前语音预览态渲染更多按钮。
    private func renderMoreButtonState(animated: Bool) {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "plus")
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        configuration.baseForegroundColor = .label
        configuration.baseBackgroundColor = ChatInputBarStyling.defaultTextInputTintColor
        moreButton.configuration = configuration
        moreButton.accessibilityIdentifier = "chat.moreButton"

        let changes = { [weak self] in
            guard let self else { return }
            if self.hasPendingVoicePreview {
                self.moreButton.transform = CGAffineTransform(rotationAngle: .pi / 4)
                self.moreButton.accessibilityLabel = "Delete Voice Preview"
            } else {
                self.moreButton.transform = .identity
                self.moreButton.accessibilityLabel = "More"
            }
        }

        moreButton.showsMenuAsPrimaryAction = !hasPendingVoicePreview
        moreButton.menu = hasPendingVoicePreview ? nil : makeMoreMenu()

        if animated {
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: changes
            )
        } else {
            changes()
        }
    }
}

/// 文本输入代理
extension ChatInputBarView: UITextViewDelegate {
    /// 开始编辑时从自定义输入面板切回键盘
    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        if inputMode.isCustomPanel {
            if !isWaitingForKeyboardInputTransition {
                isWaitingForKeyboardInputTransition = true
                publish(.keyboardInputRequested)
            }
            return false
        }
        if deferredCustomPanelPresentation != nil {
            // 上一次键盘收起通知如果没有参与面板展开，旧 pending 不能留到下一次键盘弹起通知里；
            // 用户重新点输入框时以系统键盘为准，避免面板和键盘被下一轮通知同时显示。
            deferredCustomPanelPresentation = nil
        }
        if isWaitingForKeyboardInputTransition {
            return false
        }
        return true
    }

    /// 文本变化时刷新占位、按钮和高度
    func textViewDidChange(_ textView: UITextView) {
        let currentText = textView.text ?? ""
        if textView.markedTextRange == nil {
            // 中文输入法组词期间不能重设 attributedText，否则会打断系统 marked text。
            composerFieldView.refreshMentionHighlight()
        }
        applyTextChange(currentText, selectedRange: nil)
    }

    /// 系统写入文本前，允许业务层把命中的 @ token 替换为整段删除。
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let currentText = textView.text ?? ""
        guard let replacement = textChangeReplacementProvider?(currentText, range, text) else {
            return true
        }

        composerFieldView.setText(replacement.text, selectedRange: replacement.selectedRange)
        applyTextChange(replacement.text, selectedRange: replacement.selectedRange)
        return false
    }

    /// 应用文本变更并向控制器发布最新草稿。
    private func applyTextChange(_ currentText: String, selectedRange: NSRange?) {
        if composerFieldView.text != currentText {
            if let selectedRange {
                composerFieldView.setText(currentText, selectedRange: selectedRange)
            } else {
                composerFieldView.setText(currentText)
            }
        }
        stateMachine.reduce(.setText(currentText))
        setNeedsLayout()
        renderTextViewPlaceholder()
        renderTrailingActionState()
        updateTextViewHeight(animated: true)
        publish(.textChanged(currentText))
    }
}
