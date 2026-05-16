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
/// - 用户动作通过 `UIControl` target-action 发布，读取 `lastAction` 获取动作载荷。
/// - 高度变化通过 `ChatInputBarLayoutDelegate` 协调。
@MainActor
final class ChatInputBarView: UIControl {
    /// 当前输入模式。
    private enum InputMode: Equatable {
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

    /// 最近一次发布的用户动作。
    private(set) var lastAction: ChatInputBarAction?
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

    /// 文本输入高度约束
    private var textInputHeightConstraint: NSLayoutConstraint?
    /// 自定义输入面板高度约束
    private var customPanelHeightConstraint: NSLayoutConstraint?
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
    /// 临时状态自动隐藏任务
    private var statusHideTask: Task<Void, Never>?
#if DEBUG
    /// 测试用：模拟 `resignFirstResponder()` 同步触发键盘 frame 通知。
    var keyboardDismissFrameNotificationHookForTesting: (() -> Void)?
#endif

    /// 当前输入文本
    var text: String {
        composerFieldView.text
    }

    /// 文本输入框是否正在编辑
    var isEditingText: Bool {
        composerFieldView.isEditingText
    }

    /// 当前是否可发送文本
    private var canSendText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 当前是否可发送文本或附件组合
    private var canSendComposition: Bool {
        !hasPendingVoicePreview && (canSendText || (hasPendingAttachment && !isPendingAttachmentLoading))
    }

    /// 当前是否可开始语音录制
    private var canRecordVoice: Bool {
        !hasPendingVoicePreview && !canSendText && !hasPendingAttachment && composerFieldView.isTextEditable
    }

    /// 输入区背景向底部安全区外延展的高度，模拟系统 TabBar 的连续材质。
    private static let bottomBackgroundExtension: CGFloat = 48
    /// 录音态输入胶囊高度，容纳 Apple Messages 风格的 52pt 停止按钮。
    private static let recordingInputHeight: CGFloat = 64

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
        guard abs(width - lastMeasuredTextWidth) > 0.5 else { return }
        lastMeasuredTextWidth = width
        updateTextViewHeight(animated: false)
    }

    /// 设置文本内容
    ///
    /// - Parameters:
    ///   - text: 要设置的文本
    ///   - animated: 是否动画更新高度
    func setText(_ text: String, animated: Bool) {
        guard composerFieldView.text != text else { return }
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
        isRecording = state.isRecording
        recordingStatusLabel.isHidden = true
        recordingStatusLabel.text = nil

        renderRecordingCapsule(state)
        composerFieldView.setTextEditable(!state.isRecording)
        updateTextViewHeight(animated: false)
        moreButton.isEnabled = !state.isRecording
        moreButton.isHidden = state.isRecording
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
        composerFieldView.clearCustomInputView()
        hideCustomPanel(animated: animated)
    }

    /// 在系统键盘动画事务里折叠保留的旧面板。
    func applyDeferredKeyboardPanelCollapse() {
        guard let panel = deferredKeyboardCollapsePanel else { return }
        panelView(for: panel)?.alpha = 0
        customPanelHeightConstraint?.constant = 0
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
        deferredKeyboardCollapsePanel = nil
    }

    /// 在系统键盘收起动画事务里展开目标自定义面板。
    func applyDeferredCustomPanelPresentation() {
        guard
            let panel = deferredCustomPanelPresentation,
            let targetHeight = customPanelHeight(for: panel)
        else { return }

        inputMode = panel
        customPanelContainerView.isHidden = false
        photoLibraryInputView?.isHidden = panel != .photoLibrary
        emojiPanelView?.isHidden = panel != .emoji
        photoLibraryInputView?.alpha = 1
        emojiPanelView?.alpha = 1
        customPanelHeightConstraint?.constant = targetHeight
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
        inputMode = .keyboard

        let changes = { [weak self] in
            guard let self else { return }
            self.photoLibraryInputView?.isHidden = true
            self.emojiPanelView?.isHidden = true
            self.customPanelHeightConstraint?.constant = 0
            self.customPanelContainerView.isHidden = true
        }
        performHeightChange(animated: animated, changes: changes)
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
            return ChatPhotoLibraryInputView.panelHeight
        case .emoji:
            guard emojiPanelView != nil else { return nil }
            return ChatEmojiPanelView.panelHeight
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
        hasPendingVoicePreview = true
        isPendingVoicePreviewPlaying = isPlaying
        pendingVoicePreviewDurationMilliseconds = durationMilliseconds
        pendingVoicePreviewPlaybackProgress = isPlaying ? min(1, max(0, playbackProgress)) : 0
        pendingVoicePreviewElapsedMilliseconds = isPlaying ? max(0, playbackElapsedMilliseconds) : 0
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

        NSLayoutConstraint.activate([
            inputSurfaceBackgroundView.topAnchor.constraint(equalTo: topAnchor),
            inputSurfaceBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputSurfaceBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputSurfaceBackgroundView.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: Self.bottomBackgroundExtension
            ),

            contentStackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            contentStackView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),

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
        hasPendingAttachment = !pendingAttachmentPreviewItems.isEmpty
        isPendingAttachmentLoading = pendingAttachmentPreviewItems.contains { $0.isLoading }
        attachmentPreviewRailView.render(pendingAttachmentPreviewItems)
        setAttachmentPreviewHidden(pendingAttachmentPreviewItems.isEmpty, animated: true)
        renderTrailingActionState()
        emit(.attachmentRemoved(id), for: .primaryActionTriggered)
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
        guard canRecordVoice else { return }
        emit(.voiceRecordTapped, for: .primaryActionTriggered)
    }

    /// 录音停止按钮点按事件
    private func voiceRecordingStopButtonTapped() {
        guard isRecording else { return }
        emit(.voiceRecordingStopTapped, for: .primaryActionTriggered)
    }

    /// 发送按钮点击事件
    private func sendButtonTapped() {
        guard canSendComposition, composerFieldView.isTextEditable else { return }
        sendCurrentComposition()
    }

    /// 待发送语音播放按钮点击事件
    private func voicePreviewPlayButtonTapped() {
        guard hasPendingVoicePreview else { return }
        emit(.voicePreviewPlayToggle, for: .primaryActionTriggered)
    }

    /// 待发送语音发送按钮点击事件
    private func voicePreviewSendButtonTapped() {
        guard hasPendingVoicePreview else { return }
        emit(.voicePreviewSend, for: .primaryActionTriggered)
    }

    /// 发送当前输入组合
    private func sendCurrentComposition() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || (hasPendingAttachment && !isPendingAttachmentLoading) else { return }

        composerFieldView.clearText()
        renderTextViewPlaceholder()
        renderTrailingActionState()
        updateTextViewHeight(animated: true)
        emit(.textChanged(""), for: .editingChanged)
        emit(.send(trimmedText), for: .primaryActionTriggered)
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
            self.superview?.layoutIfNeeded()
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            self.layoutDelegate?.chatInputBar(self, didChangeHeightKeepingBottom: shouldStickToBottom)
        }

        if animated {
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

        if animated {
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
    private func emit(_ action: ChatInputBarAction, for controlEvents: UIControl.Event) {
        lastAction = action
        sendActions(for: controlEvents)
    }

    /// 请求展示表情输入面板。
    func requestEmojiInput() {
        emit(.emojiTapped, for: .primaryActionTriggered)
    }

    /// 请求展示相册输入面板。
    func requestPhotoLibraryInput() {
        emit(.photoTapped, for: .primaryActionTriggered)
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
        emit(.voicePreviewCancel, for: .primaryActionTriggered)
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
                emit(.keyboardInputRequested, for: .primaryActionTriggered)
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
        renderTextViewPlaceholder()
        renderTrailingActionState()
        updateTextViewHeight(animated: true)
        emit(.textChanged(composerFieldView.text), for: .editingChanged)
    }
}

/// 文本输入胶囊向输入栏发布的局部动作。
private enum ChatComposerFieldAction {
    /// 点按语音按钮开始录音。
    case voiceRecordTapped
    /// 点按停止按钮完成录音。
    case voiceRecordingStopTapped
    /// 点击发送。
    case sendTapped
    /// 播放或暂停待发送语音预览。
    case voicePreviewPlayToggle
    /// 发送待发送语音预览。
    case voicePreviewSend
}

/// 文本输入高度测量结果。
private struct ChatComposerTextHeightMeasurement {
    /// 目标高度。
    let targetHeight: CGFloat
    /// 文本是否超过最大高度，需要滚动。
    let shouldScroll: Bool
}

/// 待发送附件预览横向轨道。
@MainActor
private final class ChatAttachmentPreviewRailView: UIView {
    /// 移除附件回调。
    var onRemoveItem: ((String) -> Void)?

    /// 横向滚动视图。
    private let scrollView = UIScrollView()
    /// 附件预览内容栈。
    private let stackView = UIStackView()
    /// 输入栏内容左右边距，用于让 rail 视觉上铺满整条输入区。
    private let horizontalOverflow: CGFloat = 12

    /// 初始化附件预览轨道。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    /// 从 storyboard/xib 初始化附件预览轨道。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    /// 渲染待发送附件预览。
    func render(_ items: [ChatPendingAttachmentPreviewItem]) {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for item in items {
            let itemView = PendingAttachmentPreviewItemView(item: item)
            itemView.addTarget(self, action: #selector(attachmentPreviewRemoveTriggered(_:)), for: .primaryActionTriggered)
            stackView.addArrangedSubview(itemView)
        }
    }

    /// 修正横向滚动视图的垂直偏移。
    func normalizeVerticalContentOffset() {
        let offset = scrollView.contentOffset
        guard abs(offset.y) > 0.5 else { return }
        scrollView.contentOffset = CGPoint(x: offset.x, y: 0)
    }

    /// 配置视图层级。
    private func configure() {
        backgroundColor = .clear
        accessibilityIdentifier = "chat.pendingAttachmentPreview"

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false
        scrollView.contentInsetAdjustmentBehavior = .never

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .top
        stackView.spacing = 8

        addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -horizontalOverflow),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: horizontalOverflow),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            scrollView.heightAnchor.constraint(equalToConstant: 74),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
    }

    /// 处理附件预览项移除动作。
    @objc private func attachmentPreviewRemoveTriggered(_ sender: UIControl) {
        guard let itemView = sender as? PendingAttachmentPreviewItemView else { return }
        onRemoveItem?(itemView.itemID)
    }
}

/// 聊天文本输入胶囊。
@MainActor
private final class ChatComposerFieldView: UIView {
    /// 输入胶囊保持初始高度对应的固定圆角，多行输入时不随高度继续增大。
    private static let cornerRadius: CGFloat = 22

    /// 文本输入代理。
    weak var textViewDelegate: UITextViewDelegate? {
        didSet {
            textView.delegate = textViewDelegate
        }
    }

    /// 输入胶囊动作回调。
    var onAction: ((ChatComposerFieldAction) -> Void)?

    /// 文本输入可读性填充层，不承担输入区材质背景职责。
    private let readableFillView = UIView()
    /// 消息文本输入框。
    private let textView = UITextView()
    /// 文本输入占位标签。
    private let placeholderLabel = UILabel()
    /// 发送或语音操作按钮。
    private let trailingActionButton = UIButton(type: .system)
    /// 录音状态胶囊。
    private let recordingCapsuleView = ChatRecordingCapsuleView()
    /// 待发送语音预览胶囊。
    private let voicePreviewCapsuleView = ChatVoicePreviewCapsuleView()
    /// 尾部按钮当前是否显示发送动作。
    private var trailingActionShowsSend = false

    /// 当前输入文本。
    var text: String {
        textView.text ?? ""
    }

    /// 文本输入框是否正在编辑。
    var isEditingText: Bool {
        textView.isFirstResponder
    }

    /// 文本输入是否可编辑。
    var isTextEditable: Bool {
        textView.isEditable
    }

    /// 当前文本输入宽度。
    var textInputWidth: CGFloat {
        textView.bounds.width
    }

    /// 初始化文本输入胶囊。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    /// 从 storyboard/xib 初始化文本输入胶囊。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    /// 设置文本内容。
    func setText(_ text: String) {
        textView.text = text
    }

    /// 清空文本内容。
    func clearText() {
        textView.text = ""
    }

    /// 设置文本输入可编辑状态。
    func setTextEditable(_ isEditable: Bool) {
        textView.isEditable = isEditable
    }

    /// 设置文本是否滚动。
    func setTextScrollEnabled(_ isScrollEnabled: Bool) {
        textView.isScrollEnabled = isScrollEnabled
    }

    /// 自定义输入面板展示前清理系统 inputView。
    func prepareForCustomInput() {
        textView.inputView = nil
        textView.resignFirstResponder()
    }

    /// 清理自定义 inputView。
    func clearCustomInputView() {
        textView.inputView = nil
    }

    /// 切回系统键盘。
    func showKeyboardInput() {
        textView.inputView = nil
        textView.reloadInputViews()
        textView.becomeFirstResponder()
    }

    /// 渲染文本输入和占位显隐。
    func renderTextInputVisibility(hidesTextInput: Bool) {
        textView.isHidden = hidesTextInput
        placeholderLabel.isHidden = hidesTextInput || !text.isEmpty
    }

    /// 渲染尾部发送或语音按钮。
    func renderTrailingAction(showsSend: Bool, hidesTrailingAction: Bool, isEnabled: Bool) {
        trailingActionShowsSend = showsSend
        trailingActionButton.alpha = hidesTrailingAction ? 0 : 1
        trailingActionButton.isAccessibilityElement = !hidesTrailingAction
        trailingActionButton.accessibilityElementsHidden = hidesTrailingAction
        trailingActionButton.isEnabled = isEnabled
        trailingActionButton.accessibilityLabel = showsSend ? "Send" : "Record Voice"
        trailingActionButton.accessibilityIdentifier = showsSend ? "chat.sendButton" : "chat.voiceButton"

        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: showsSend ? "arrow.up" : "mic")
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        configuration.baseForegroundColor = showsSend ? .white : .secondaryLabel
        configuration.baseBackgroundColor = showsSend ? UIColor.systemBlue : UIColor.clear
        trailingActionButton.configuration = configuration
    }

    /// 渲染录音状态。
    func renderRecording(_ state: VoiceRecordingState) {
        recordingCapsuleView.isHidden = !state.isRecording
        recordingCapsuleView.render(state)
    }

    /// 渲染待发送语音预览。
    func renderVoicePreview(
        durationMilliseconds: Int,
        isPlaying: Bool,
        playbackProgress: Double,
        elapsedMilliseconds: Int
    ) {
        voicePreviewCapsuleView.render(
            durationMilliseconds: durationMilliseconds,
            isPlaying: isPlaying,
            playbackProgress: playbackProgress,
            elapsedMilliseconds: elapsedMilliseconds
        )
    }

    /// 预备语音预览显隐变化，返回是否真的需要更新。
    func prepareVoicePreviewHidden(_ isHidden: Bool) -> Bool {
        guard voicePreviewCapsuleView.isHidden != isHidden else { return false }
        voicePreviewCapsuleView.setContentHidden(isHidden)
        return true
    }

    /// 应用语音预览显隐。
    func applyVoicePreviewHidden(_ isHidden: Bool) {
        voicePreviewCapsuleView.isHidden = isHidden
    }

    /// 测量文本输入高度。
    func measureTextHeight(maximumHeight: CGFloat) -> ChatComposerTextHeightMeasurement {
        let fittingSize = CGSize(width: max(textView.bounds.width, 1), height: .greatestFiniteMagnitude)
        let measuredHeight = textView.sizeThatFits(fittingSize).height
        let targetHeight = min(max(44, ceil(measuredHeight)), maximumHeight)
        return ChatComposerTextHeightMeasurement(
            targetHeight: targetHeight,
            shouldScroll: measuredHeight > maximumHeight
        )
    }

    /// 最大文本高度。
    func maximumTextHeight(maximumLineCount: Int) -> CGFloat {
        let font = textView.font ?? .preferredFont(forTextStyle: .body)
        return ceil(
            font.lineHeight * CGFloat(maximumLineCount)
                + textView.textContainerInset.top
                + textView.textContainerInset.bottom
        )
    }

    /// 配置视图层级。
    private func configure() {
        backgroundColor = .clear
        clipsToBounds = true
        layer.cornerRadius = Self.cornerRadius
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        readableFillView.translatesAutoresizingMaskIntoConstraints = false
        readableFillView.backgroundColor = ChatInputBarStyling.defaultTextInputTintColor
        readableFillView.isUserInteractionEnabled = false
        readableFillView.accessibilityIdentifier = "chat.textInputReadableFill"

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.returnKeyType = .default
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 11, left: 16, bottom: 11, right: 52)
        textView.textContainer.lineFragmentPadding = 0
        textView.accessibilityIdentifier = "chat.messageInput"
        textView.delegate = textViewDelegate
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.text = "Message"
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.isUserInteractionEnabled = false

        configureTrailingActionButton()
        configureRecordingCapsuleView()
        configureVoicePreviewCapsuleView()

        addSubview(readableFillView)
        addSubview(textView)
        addSubview(placeholderLabel)
        addSubview(trailingActionButton)
        addSubview(recordingCapsuleView)
        addSubview(voicePreviewCapsuleView)

        NSLayoutConstraint.activate([
            readableFillView.topAnchor.constraint(equalTo: topAnchor),
            readableFillView.leadingAnchor.constraint(equalTo: leadingAnchor),
            readableFillView.trailingAnchor.constraint(equalTo: trailingAnchor),
            readableFillView.bottomAnchor.constraint(equalTo: bottomAnchor),

            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),

            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingActionButton.leadingAnchor, constant: -8),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 11),

            trailingActionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            trailingActionButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            trailingActionButton.widthAnchor.constraint(equalToConstant: 34),
            trailingActionButton.heightAnchor.constraint(equalToConstant: 34),

            recordingCapsuleView.topAnchor.constraint(equalTo: topAnchor),
            recordingCapsuleView.leadingAnchor.constraint(equalTo: leadingAnchor),
            recordingCapsuleView.trailingAnchor.constraint(equalTo: trailingAnchor),
            recordingCapsuleView.bottomAnchor.constraint(equalTo: bottomAnchor),

            voicePreviewCapsuleView.topAnchor.constraint(equalTo: topAnchor),
            voicePreviewCapsuleView.leadingAnchor.constraint(equalTo: leadingAnchor),
            voicePreviewCapsuleView.trailingAnchor.constraint(equalTo: trailingAnchor),
            voicePreviewCapsuleView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// 配置尾部发送/语音按钮。
    private func configureTrailingActionButton() {
        trailingActionButton.translatesAutoresizingMaskIntoConstraints = false
        trailingActionButton.setContentHuggingPriority(.required, for: .horizontal)
        trailingActionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        trailingActionButton.addTarget(self, action: #selector(trailingActionButtonTapped), for: .touchUpInside)
    }

    /// 配置录音胶囊视图。
    private func configureRecordingCapsuleView() {
        recordingCapsuleView.translatesAutoresizingMaskIntoConstraints = false
        recordingCapsuleView.isHidden = true
        recordingCapsuleView.onStopTapped = { [weak self] in
            self?.onAction?(.voiceRecordingStopTapped)
        }
    }

    /// 配置待发送语音预览胶囊。
    private func configureVoicePreviewCapsuleView() {
        voicePreviewCapsuleView.translatesAutoresizingMaskIntoConstraints = false
        voicePreviewCapsuleView.isHidden = true
        voicePreviewCapsuleView.setContentHidden(true)
        voicePreviewCapsuleView.onPlayTapped = { [weak self] in
            self?.onAction?(.voicePreviewPlayToggle)
        }
        voicePreviewCapsuleView.onSendTapped = { [weak self] in
            self?.onAction?(.voicePreviewSend)
        }
    }

    /// 尾部按钮点击事件。
    @objc private func trailingActionButtonTapped() {
        onAction?(trailingActionShowsSend ? .sendTapped : .voiceRecordTapped)
    }
}

/// 待发送附件预览项视图
@MainActor
private final class PendingAttachmentPreviewItemView: UIControl {
    /// 附件 ID
    fileprivate let itemID: String
    /// 附件缩略图
    private let imageView = UIImageView()
    /// 底部遮罩
    private let overlayView = UIView()
    /// 媒体类型图标
    private let iconView = UIImageView()
    /// 视频时长标签
    private let durationLabel = UILabel()
    /// 加载指示器
    private let spinner = UIActivityIndicatorView(style: .medium)
    /// 移除按钮
    private let removeButton = UIButton(type: .system)

    /// 根据附件预览项初始化视图
    init(item: ChatPendingAttachmentPreviewItem) {
        itemID = item.id
        super.init(frame: .zero)
        configureView()
        configure(item: item)
    }

    /// 从 storyboard/xib 初始化附件预览视图
    required init?(coder: NSCoder) {
        itemID = ""
        super.init(coder: coder)
        configureView()
    }

    /// 应用附件预览内容
    private func configure(item: ChatPendingAttachmentPreviewItem) {
        accessibilityIdentifier = "chat.pendingAttachmentPreviewItem.\(item.id)"
        accessibilityLabel = item.title
        imageView.image = item.image
        iconView.image = UIImage(systemName: item.isVideo ? "play.fill" : "photo.fill")
        durationLabel.text = item.durationText
        durationLabel.isHidden = item.durationText == nil
        removeButton.isEnabled = !item.isLoading
        removeButton.alpha = item.isLoading ? 0.45 : 1

        if item.isLoading {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
    }

    /// 配置预览视图层级、样式和约束
    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.36)
                : UIColor.systemFill.withAlphaComponent(0.14)
        }
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = ChatBridgeDesignSystem.RadiusToken.appleComposerAttachment

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        overlayView.isUserInteractionEnabled = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        durationLabel.textColor = .white
        durationLabel.adjustsFontSizeToFitWidth = true
        durationLabel.minimumScaleFactor = 0.76
        durationLabel.textAlignment = .right

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        spinner.color = .white

        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.accessibilityLabel = "Remove Attachment"
        removeButton.accessibilityIdentifier = "chat.removeAttachmentButton.\(itemID)"
        removeButton.configuration = nil
        removeButton.backgroundColor = UIColor.systemGray.withAlphaComponent(0.62)
        removeButton.tintColor = .white
        removeButton.clipsToBounds = true
        removeButton.layer.cornerRadius = 12
        removeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        removeButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 12, weight: .bold),
            forImageIn: .normal
        )
        removeButton.addTarget(self, action: #selector(removeButtonTapped), for: .touchUpInside)

        addSubview(imageView)
        imageView.addSubview(overlayView)
        overlayView.addSubview(iconView)
        overlayView.addSubview(durationLabel)
        imageView.addSubview(spinner)
        addSubview(removeButton)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 74),
            heightAnchor.constraint(equalToConstant: 74),

            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 66),
            imageView.heightAnchor.constraint(equalToConstant: 66),

            overlayView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            overlayView.heightAnchor.constraint(equalToConstant: 22),

            iconView.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 12),
            iconView.heightAnchor.constraint(equalToConstant: 12),

            durationLabel.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -5),
            durationLabel.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor),
            durationLabel.leadingAnchor.constraint(greaterThanOrEqualTo: iconView.trailingAnchor, constant: 4),

            spinner.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),

            removeButton.topAnchor.constraint(equalTo: topAnchor),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 24),
            removeButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    /// 点击移除附件按钮
    @objc private func removeButtonTapped() {
        guard removeButton.isEnabled else { return }
        sendActions(for: .primaryActionTriggered)
    }
}

/// 输入栏通用视觉参数。
@MainActor
private enum ChatInputBarStyling {
    /// 默认文本输入背景色。
    static var defaultTextInputTintColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.54)
                : UIColor.white.withAlphaComponent(0.58)
        }
    }
}

/// 输入栏内圆形图标按钮的统一样式。
@MainActor
private enum ChatInputBarControlStyling {
    /// 配置圆形图标按钮。
    static func configureCircleButton(
        _ button: UIButton,
        imageName: String,
        foregroundColor: UIColor,
        backgroundColor: UIColor,
        accessibilityLabel: String,
        accessibilityIdentifier: String?
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: imageName)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        configuration.baseForegroundColor = foregroundColor
        configuration.baseBackgroundColor = backgroundColor
        button.configuration = configuration
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityIdentifier = accessibilityIdentifier
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
}

/// 输入栏语音时长文案格式化。
private enum ChatInputBarVoiceFormatting {
    /// 格式化录音时长文本。
    static func recordingDurationText(milliseconds: Int) -> String {
        let seconds = max(0, milliseconds / 1_000)
        return "0:\(String(format: "%02d", seconds))"
    }

    /// 格式化语音播放时长文本。
    static func playbackDurationText(
        elapsedMilliseconds: Int,
        durationMilliseconds: Int,
        isPlaying: Bool
    ) -> String {
        let totalText = ChatMessageRowContent.voiceDurationDisplayText(milliseconds: durationMilliseconds)
        guard isPlaying else {
            return "+ \(totalText)"
        }

        let elapsedText = ChatMessageRowContent.voiceElapsedDisplayText(milliseconds: elapsedMilliseconds)
        return "+ \(elapsedText)/\(totalText)"
    }
}

/// 录音中的输入胶囊内容。
@MainActor
private final class ChatRecordingCapsuleView: UIView {
    /// 停止录音回调。
    var onStopTapped: (() -> Void)?

    /// 录音状态内容栈。
    private let stackView = UIStackView()
    /// 录音音量电平视图。
    private let levelMeterView = VoiceLevelMeterView()
    /// 录音时长标签。
    private let durationLabel = UILabel()
    /// 录音提示标签。
    private let hintLabel = UILabel()
    /// 录音停止按钮。
    private let stopButton = UIButton(type: .system)

    /// 初始化录音胶囊。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    /// 从 storyboard/xib 初始化录音胶囊。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    /// 渲染录音状态。
    func render(_ state: VoiceRecordingState) {
        guard state.isRecording else {
            levelMeterView.powerLevel = 0
            hintLabel.isHidden = true
            return
        }

        let accentColor: UIColor = .systemRed
        durationLabel.text = ChatInputBarVoiceFormatting.recordingDurationText(milliseconds: state.elapsedMilliseconds)
        durationLabel.textColor = accentColor
        levelMeterView.tintColor = accentColor
        levelMeterView.appendPowerLevel(state.averagePowerLevel)
        hintLabel.text = state.isCanceling ? state.hintText : nil
        hintLabel.textColor = state.isCanceling ? .systemRed : .secondaryLabel
        hintLabel.isHidden = !state.isCanceling
    }

    /// 配置视图层级。
    private func configure() {
        backgroundColor = .clear
        accessibilityIdentifier = "chat.recordingCapsule"
        isOpaque = false
        isUserInteractionEnabled = true

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 14

        levelMeterView.translatesAutoresizingMaskIntoConstraints = false
        levelMeterView.tintColor = .systemRed
        levelMeterView.accessibilityIdentifier = "chat.recordingWaveform"
        levelMeterView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        levelMeterView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        durationLabel.adjustsFontForContentSizeCategory = true
        durationLabel.textColor = .systemRed
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = .preferredFont(forTextStyle: .subheadline)
        hintLabel.adjustsFontForContentSizeCategory = true
        hintLabel.textColor = .secondaryLabel
        hintLabel.numberOfLines = 1
        hintLabel.isHidden = true
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        ChatInputBarControlStyling.configureCircleButton(
            stopButton,
            imageName: "stop.fill",
            foregroundColor: .systemRed,
            backgroundColor: UIColor.systemRed.withAlphaComponent(0.16),
            accessibilityLabel: "Stop Voice Recording",
            accessibilityIdentifier: "chat.voiceStopButton"
        )
        var stopConfiguration = stopButton.configuration
        stopConfiguration?.image = UIImage(
            systemName: "stop.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        )
        stopConfiguration?.contentInsets = .zero
        stopButton.configuration = stopConfiguration
        stopButton.addTarget(self, action: #selector(stopButtonTapped), for: .touchUpInside)

        addSubview(stackView)
        stackView.addArrangedSubview(levelMeterView)
        stackView.addArrangedSubview(durationLabel)
        stackView.addArrangedSubview(hintLabel)
        stackView.addArrangedSubview(stopButton)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            levelMeterView.heightAnchor.constraint(equalToConstant: 24),
            stopButton.widthAnchor.constraint(equalToConstant: 52),
            stopButton.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    /// 点击停止录音。
    @objc private func stopButtonTapped() {
        onStopTapped?()
    }
}

/// 待发送语音预览的输入胶囊内容。
@MainActor
private final class ChatVoicePreviewCapsuleView: UIView {
    /// 播放或暂停预览回调。
    var onPlayTapped: (() -> Void)?
    /// 发送预览回调。
    var onSendTapped: (() -> Void)?

    /// 待发送语音预览内容栈。
    private let stackView = UIStackView()
    /// 待发送语音播放按钮。
    private let playButton = UIButton(type: .system)
    /// 待发送语音波形。
    private let waveformView = VoiceLevelMeterView()
    /// 待发送语音时长标签。
    private let durationLabel = UILabel()
    /// 待发送语音发送按钮。
    private let sendButton = UIButton(type: .system)

    /// 初始化语音预览胶囊。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    /// 从 storyboard/xib 初始化语音预览胶囊。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    /// 渲染待发送语音预览。
    func render(
        durationMilliseconds: Int,
        isPlaying: Bool,
        playbackProgress: Double,
        elapsedMilliseconds: Int
    ) {
        durationLabel.text = ChatInputBarVoiceFormatting.playbackDurationText(
            elapsedMilliseconds: elapsedMilliseconds,
            durationMilliseconds: durationMilliseconds,
            isPlaying: isPlaying
        )
        waveformView.playbackProgress = playbackProgress
        ChatInputBarControlStyling.configureCircleButton(
            playButton,
            imageName: isPlaying ? "pause.fill" : "play.fill",
            foregroundColor: .label,
            backgroundColor: UIColor.systemGray5,
            accessibilityLabel: isPlaying ? "Pause Voice Preview" : "Play Voice Preview",
            accessibilityIdentifier: isHidden ? nil : "chat.voicePreviewPlayButton"
        )
    }

    /// 隐藏或恢复内容层辅助标识。
    func setContentHidden(_ isHidden: Bool) {
        accessibilityElementsHidden = isHidden
        isUserInteractionEnabled = !isHidden
        playButton.accessibilityIdentifier = isHidden ? nil : "chat.voicePreviewPlayButton"
        waveformView.accessibilityIdentifier = isHidden ? nil : "chat.voicePreviewWaveform"
        sendButton.accessibilityIdentifier = isHidden ? nil : "chat.voicePreviewSendButton"
    }

    /// 配置视图层级。
    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8

        ChatInputBarControlStyling.configureCircleButton(
            playButton,
            imageName: "play.fill",
            foregroundColor: .label,
            backgroundColor: UIColor.systemGray5,
            accessibilityLabel: "Play Voice Preview",
            accessibilityIdentifier: "chat.voicePreviewPlayButton"
        )
        playButton.addTarget(self, action: #selector(playButtonTapped), for: .touchUpInside)

        waveformView.translatesAutoresizingMaskIntoConstraints = false
        waveformView.accessibilityIdentifier = "chat.voicePreviewWaveform"
        waveformView.tintColor = .systemGray
        waveformView.seedPreviewSamples()
        waveformView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        durationLabel.adjustsFontForContentSizeCategory = true
        durationLabel.textColor = .label
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)

        ChatInputBarControlStyling.configureCircleButton(
            sendButton,
            imageName: "arrow.up",
            foregroundColor: .white,
            backgroundColor: .systemGreen,
            accessibilityLabel: "Send Voice Preview",
            accessibilityIdentifier: "chat.voicePreviewSendButton"
        )
        sendButton.addTarget(self, action: #selector(sendButtonTapped), for: .touchUpInside)

        addSubview(stackView)
        stackView.addArrangedSubview(playButton)
        stackView.addArrangedSubview(waveformView)
        stackView.addArrangedSubview(durationLabel)
        stackView.addArrangedSubview(sendButton)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 34),
            playButton.heightAnchor.constraint(equalToConstant: 34),
            waveformView.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            waveformView.heightAnchor.constraint(equalToConstant: 20),
            sendButton.widthAnchor.constraint(equalToConstant: 42),
            sendButton.heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    /// 点击播放或暂停预览。
    @objc private func playButtonTapped() {
        onPlayTapped?()
    }

    /// 点击发送预览。
    @objc private func sendButtonTapped() {
        onSendTapped?()
    }
}

/// 语音录制音量电平视图
@MainActor
private final class VoiceLevelMeterView: UIView {
    /// 最多保留的波形样本数量
    private static let maximumSampleCount = 42
    /// 实时录音音量采样间隔，和 `VoiceRecordingController` 的 meter timer 保持一致。
    private static let recordingSampleInterval: CFTimeInterval = 0.1
    /// 波形高度样本，数组尾部是最新样本
    private var samples: [Double] = []
    /// 已裁剪的播放进度。
    private var playbackProgressValue: Double?
    /// 录音态滚动动画。
    private var recordingDisplayLink: CADisplayLink?
    /// 录音态柱形左移相位，范围 0...1。
    private var recordingScrollPhase: CGFloat = 0
    /// 上一帧动画时间戳。
    private var lastDisplayLinkTimestamp: CFTimeInterval = 0
    /// 播放进度。录音电平视图为 nil，预览播放视图为 0...1。
    var playbackProgress: Double? {
        get {
            playbackProgressValue
        }
        set {
            playbackProgressValue = newValue.map { min(1, max(0, $0)) }
            if playbackProgressValue != nil {
                stopRecordingAnimation()
            }
            setNeedsDisplay()
        }
    }

    /// 归一化音量值，范围 0...1
    var powerLevel: Double = 0 {
        didSet {
            powerLevel = max(0, min(1, powerLevel))
            samples = [powerLevel]
            playbackProgress = nil
            stopRecordingAnimation()
            setNeedsDisplay()
        }
    }

    /// 初始化音量电平视图
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    /// 从 storyboard/xib 初始化音量电平视图
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }

    /// 视图离开窗口时停止动画，避免隐藏状态空跑。
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            stopRecordingAnimation()
            return
        }

        if playbackProgress == nil, samples.count > 1 {
            startRecordingAnimationIfNeeded()
        }
    }

    /// 追加新的实时音量样本，视觉上从右侧进入、旧样本向左移动。
    func appendPowerLevel(_ level: Double) {
        playbackProgressValue = nil
        let clampedLevel = max(0, min(1, level))
        samples.append(clampedLevel)
        if samples.count > Self.maximumSampleCount {
            samples.removeFirst(samples.count - Self.maximumSampleCount)
        }
        recordingScrollPhase = 0
        lastDisplayLinkTimestamp = 0
        startRecordingAnimationIfNeeded()
        setNeedsDisplay()
    }

    /// 为待发送预览生成稳定波形。
    func seedPreviewSamples() {
        stopRecordingAnimation()
        samples = (0..<Self.maximumSampleCount).map { index in
            let phase = Double(index) / Double(max(Self.maximumSampleCount - 1, 1))
            return 0.18 + 0.66 * abs(sin(phase * .pi * 2.4))
        }
        playbackProgress = 0
        setNeedsDisplay()
    }

    /// 绘制音量柱形图
    override func draw(_ rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }

        let visibleSamples = visibleSamplesForDrawing()
        let barCount = visibleSamples.count
        let spacing: CGFloat = 3
        let layoutBarCount = playbackProgress == nil ? max(barCount - 1, 1) : barCount
        let barWidth = max(2, min(4, (rect.width - CGFloat(layoutBarCount - 1) * spacing) / CGFloat(layoutBarCount)))
        let barPitch = barWidth + spacing
        let contentWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        let startX = playbackProgress == nil
            ? -recordingScrollPhase * barPitch
            : max(0, rect.width - contentWidth)

        for (index, sample) in visibleSamples.enumerated() {
            let progress = CGFloat(index) / CGFloat(max(barCount - 1, 1))
            let centerWeight = 0.38 + 0.62 * sin(progress * .pi)
            let heightScale = 0.22 + 0.78 * CGFloat(sample) * centerWeight
            let barHeight = max(4, rect.height * heightScale)
            let x = startX + CGFloat(index) * (barWidth + spacing)
            let y = (rect.height - barHeight) / 2
            let path = UIBezierPath(
                roundedRect: CGRect(x: x, y: y, width: barWidth, height: barHeight),
                cornerRadius: barWidth / 2
            )
            let ageAlpha: CGFloat
            if let playbackProgress {
                let activeSamples = Int(ceil(CGFloat(barCount) * CGFloat(playbackProgress)))
                ageAlpha = index < activeSamples ? 0.92 : 0.3
            } else {
                ageAlpha = 0.3 + 0.62 * CGFloat(index + 1) / CGFloat(barCount)
            }
            let color = tintColor.withAlphaComponent(ageAlpha)
            color.setFill()
            path.fill()
        }
    }

    /// 当前绘制用样本。录音态需要铺满可用宽度，避免实时样本少时右侧留空。
    private func visibleSamplesForDrawing() -> [Double] {
        if playbackProgress != nil {
            return samples.isEmpty ? Array(repeating: powerLevel, count: 9) : samples
        }

        let currentSamples = samples.isEmpty ? [powerLevel] : samples
        guard currentSamples.count < Self.maximumSampleCount else {
            return currentSamples + [currentSamples.last ?? powerLevel]
        }

        let paddingCount = Self.maximumSampleCount - currentSamples.count
        let seedLevel = max(0.12, min(0.28, currentSamples.first ?? powerLevel))
        let paddingSamples = (0..<paddingCount).map { index in
            let phase = Double(index) / Double(max(paddingCount - 1, 1))
            return seedLevel * (0.72 + 0.28 * abs(sin(phase * .pi * 2)))
        }
        let paddedSamples = paddingSamples + currentSamples
        return paddedSamples + [paddedSamples.last ?? seedLevel]
    }

    /// 启动录音态显示刷新。
    private func startRecordingAnimationIfNeeded() {
        guard window != nil, recordingDisplayLink == nil else { return }
        let displayLink = CADisplayLink(target: self, selector: #selector(recordingAnimationDidTick(_:)))
        displayLink.add(to: .main, forMode: .common)
        recordingDisplayLink = displayLink
    }

    /// 停止录音态显示刷新。
    private func stopRecordingAnimation() {
        recordingDisplayLink?.invalidate()
        recordingDisplayLink = nil
        recordingScrollPhase = 0
        lastDisplayLinkTimestamp = 0
    }

    /// 推进录音态波形滚动相位。
    @objc private func recordingAnimationDidTick(_ displayLink: CADisplayLink) {
        let elapsed: CFTimeInterval
        if lastDisplayLinkTimestamp > 0 {
            elapsed = max(0, displayLink.timestamp - lastDisplayLinkTimestamp)
        } else {
            elapsed = displayLink.duration
        }

        lastDisplayLinkTimestamp = displayLink.timestamp
        let phaseDelta = CGFloat(elapsed / Self.recordingSampleInterval)
        recordingScrollPhase = min(0.98, recordingScrollPhase + phaseDelta)
        setNeedsDisplay()
    }
}
