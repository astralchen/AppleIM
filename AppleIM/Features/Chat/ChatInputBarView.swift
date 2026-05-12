//
//  ChatInputBarView.swift
//  AppleIM
//

import UIKit

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
/// ## 回调事件
///
/// - `onTextChanged`: 文本变化
/// - `onSend`: 发送消息
/// - `onPhotoTapped`: 点击相册按钮
/// - `onEmojiTapped`: 点击表情菜单项
/// - `onKeyboardInputRequested`: 从相册面板切回系统键盘输入
/// - `onAttachmentRemoved`: 移除附件
/// - `onVoiceTouchDown/DragExit/DragEnter/TouchUpInside/TouchUpOutside/TouchCancel`: 语音按钮触摸事件
/// - `onHeightWillChange/DidChange`: 高度变化事件
@MainActor
final class ChatInputBarView: UIView {
    /// 文本变化回调
    var onTextChanged: ((String) -> Void)?
    /// 发送当前输入内容回调
    var onSend: ((String) -> Void)?
    /// 点击相册按钮回调
    var onPhotoTapped: (() -> Void)?
    /// 点击表情菜单项回调
    var onEmojiTapped: (() -> Void)?
    /// 请求恢复系统键盘输入回调
    var onKeyboardInputRequested: (() -> Void)?
    /// 移除待发送附件回调
    var onAttachmentRemoved: ((String) -> Void)?
    /// 语音按钮按下回调
    var onVoiceTouchDown: (() -> Void)?
    /// 语音按钮拖出回调
    var onVoiceTouchDragExit: (() -> Void)?
    /// 语音按钮拖回回调
    var onVoiceTouchDragEnter: (() -> Void)?
    /// 语音按钮内部松开回调
    var onVoiceTouchUpInside: (() -> Void)?
    /// 语音按钮外部松开回调
    var onVoiceTouchUpOutside: (() -> Void)?
    /// 语音按钮触摸取消回调
    var onVoiceTouchCancel: (() -> Void)?
    /// 取消待发送语音预览回调
    var onVoicePreviewCancel: (() -> Void)?
    /// 播放或暂停待发送语音预览回调
    var onVoicePreviewPlayToggle: (() -> Void)?
    /// 发送待发送语音预览回调
    var onVoicePreviewSend: (() -> Void)?
    /// 高度变化前回调，返回是否需要保持贴底
    var onHeightWillChange: (() -> Bool)?
    /// 高度变化完成回调
    var onHeightDidChange: ((Bool) -> Void)?

    /// 玻璃质感输入栏容器
    private let glassContainerView = GlassContainerView(cornerRadius: ChatBridgeDesignSystem.RadiusToken.inputBar)
    /// 根内容栈
    private let contentStackView = UIStackView()
    /// 录音临时状态标签
    private let recordingStatusLabel = UILabel()
    /// 附件预览容器
    private let attachmentPreviewView = UIView()
    /// 附件预览横向滚动视图
    private let attachmentPreviewScrollView = UIScrollView()
    /// 附件预览内容栈
    private let attachmentPreviewStackView = UIStackView()
    /// 输入区域横向栈
    private let inputStackView = UIStackView()
    /// 更多操作按钮
    private let moreButton = UIButton(type: .system)
    /// 文本输入容器
    private let textInputContainerView = UIView()
    /// 文本输入材质背景
    private let textInputMaterialView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    /// 文本输入着色层
    private let textInputTintView = UIView()
    /// 消息文本输入框
    private let textView = UITextView()
    /// 文本输入占位标签
    private let textViewPlaceholderLabel = UILabel()
    /// 发送或语音操作按钮
    private let trailingActionButton = UIButton(type: .system)
    /// 录音状态胶囊容器
    private let recordingCapsuleView = UIView()
    /// 录音状态内容栈
    private let recordingStackView = UIStackView()
    /// 录音图标
    private let recordingIconView = UIImageView(image: UIImage(systemName: "mic.fill"))
    /// 录音时长标签
    private let recordingDurationLabel = UILabel()
    /// 录音音量电平视图
    private let recordingLevelMeterView = VoiceLevelMeterView()
    /// 录音提示标签
    private let recordingHintLabel = UILabel()
    /// 录音停止按钮
    private let recordingStopButton = UIButton(type: .system)
    /// 待发送语音预览胶囊
    private let voicePreviewCapsuleView = UIView()
    /// 待发送语音预览内容栈
    private let voicePreviewStackView = UIStackView()
    /// 待发送语音取消按钮
    private let voicePreviewCancelButton = UIButton(type: .system)
    /// 待发送语音播放按钮
    private let voicePreviewPlayButton = UIButton(type: .system)
    /// 待发送语音波形
    private let voicePreviewWaveformView = VoiceLevelMeterView()
    /// 待发送语音时长标签
    private let voicePreviewDurationLabel = UILabel()
    /// 待发送语音发送按钮
    private let voicePreviewSendButton = UIButton(type: .system)

    /// 文本输入高度约束
    private var textInputHeightConstraint: NSLayoutConstraint?
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
    /// 是否正在展示相册输入视图
    private var isShowingPhotoLibraryInput = false
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

    /// 当前输入文本
    var text: String {
        textView.text ?? ""
    }

    /// 文本输入框是否正在编辑
    var isEditingText: Bool {
        textView.isFirstResponder
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
        !hasPendingVoicePreview && !canSendText && !hasPendingAttachment && textView.isEditable
    }

    /// 默认文本输入背景色
    private static var defaultTextInputTintColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.64)
                : UIColor.white.withAlphaComponent(0.70)
        }
    }

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

        let width = textView.bounds.width
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
        guard textView.text != text else { return }
        textView.text = text
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
        textView.isEditable = !state.isRecording
        moreButton.isEnabled = !state.isRecording
        moreButton.isHidden = state.isRecording || hasPendingVoicePreview
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
        recordingStatusLabel.isHidden = false
        recordingStatusLabel.text = message
        recordingStatusLabel.textColor = .secondaryLabel

        statusHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            self?.recordingStatusLabel.isHidden = true
        }
    }

    /// 切换到相册输入面板
    func showPhotoLibraryInput() {
        isShowingPhotoLibraryInput = true
        isWaitingForKeyboardInputTransition = false
        textView.inputView = nil
        textView.resignFirstResponder()
    }

    /// 切换到表情输入面板
    func showEmojiInput() {
        isShowingPhotoLibraryInput = false
        isWaitingForKeyboardInputTransition = false
        textView.inputView = nil
        textView.resignFirstResponder()
    }

    /// 切换回系统键盘输入
    func showKeyboardInput() {
        isShowingPhotoLibraryInput = false
        isWaitingForKeyboardInputTransition = false
        textView.inputView = nil
        textView.reloadInputViews()
        textView.becomeFirstResponder()
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
        rebuildAttachmentPreviewItems()
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
        rebuildAttachmentPreviewItems()
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
        textView.isEditable = false
        moreButton.isHidden = true
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
        textView.isEditable = true
        moreButton.isHidden = false
        setVoicePreviewHidden(true, animated: animated)
        renderTextViewPlaceholder()
        renderTrailingActionState()
    }

    /// 配置输入栏视图层级和约束
    private func configureView() {
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)

        glassContainerView.translatesAutoresizingMaskIntoConstraints = false

        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.axis = .vertical
        contentStackView.alignment = .fill
        contentStackView.spacing = 4

        inputStackView.translatesAutoresizingMaskIntoConstraints = false
        inputStackView.axis = .horizontal
        inputStackView.alignment = .bottom
        inputStackView.spacing = 8
        inputStackView.distribution = .fill

        configureMoreButton()
        configureAttachmentPreviewView()
        configureTextView()
        configureTrailingActionButton()
        configureRecordingCapsuleView()
        configureVoicePreviewCapsuleView()
        configureRecordingStatusLabel()

        addSubview(contentStackView)

        contentStackView.addArrangedSubview(recordingStatusLabel)
        contentStackView.addArrangedSubview(attachmentPreviewView)
        contentStackView.addArrangedSubview(inputStackView)
        attachmentPreviewView.isHidden = true

        inputStackView.addArrangedSubview(moreButton)
        inputStackView.addArrangedSubview(textInputContainerView)
        inputStackView.insertSubview(glassContainerView, belowSubview: textInputContainerView)

        let textInputHeightConstraint = textInputContainerView.heightAnchor.constraint(equalToConstant: 44)
        self.textInputHeightConstraint = textInputHeightConstraint

        NSLayoutConstraint.activate([
            contentStackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            contentStackView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),

            glassContainerView.topAnchor.constraint(equalTo: textInputContainerView.topAnchor),
            glassContainerView.leadingAnchor.constraint(equalTo: textInputContainerView.leadingAnchor),
            glassContainerView.trailingAnchor.constraint(equalTo: textInputContainerView.trailingAnchor),
            glassContainerView.bottomAnchor.constraint(equalTo: textInputContainerView.bottomAnchor),

            attachmentPreviewScrollView.topAnchor.constraint(equalTo: attachmentPreviewView.topAnchor, constant: 4),
            attachmentPreviewScrollView.leadingAnchor.constraint(equalTo: attachmentPreviewView.leadingAnchor),
            attachmentPreviewScrollView.trailingAnchor.constraint(equalTo: attachmentPreviewView.trailingAnchor),
            attachmentPreviewScrollView.bottomAnchor.constraint(equalTo: attachmentPreviewView.bottomAnchor, constant: -4),
            attachmentPreviewScrollView.heightAnchor.constraint(equalToConstant: 74),

            attachmentPreviewStackView.topAnchor.constraint(equalTo: attachmentPreviewScrollView.contentLayoutGuide.topAnchor),
            attachmentPreviewStackView.leadingAnchor.constraint(equalTo: attachmentPreviewScrollView.contentLayoutGuide.leadingAnchor),
            attachmentPreviewStackView.trailingAnchor.constraint(equalTo: attachmentPreviewScrollView.contentLayoutGuide.trailingAnchor),
            attachmentPreviewStackView.bottomAnchor.constraint(equalTo: attachmentPreviewScrollView.contentLayoutGuide.bottomAnchor),
            attachmentPreviewStackView.heightAnchor.constraint(equalTo: attachmentPreviewScrollView.frameLayoutGuide.heightAnchor),

            moreButton.widthAnchor.constraint(equalToConstant: 44),
            moreButton.heightAnchor.constraint(equalToConstant: 44),
            textInputHeightConstraint,

            textInputMaterialView.topAnchor.constraint(equalTo: textInputContainerView.topAnchor),
            textInputMaterialView.leadingAnchor.constraint(equalTo: textInputContainerView.leadingAnchor),
            textInputMaterialView.trailingAnchor.constraint(equalTo: textInputContainerView.trailingAnchor),
            textInputMaterialView.bottomAnchor.constraint(equalTo: textInputContainerView.bottomAnchor),

            textInputTintView.topAnchor.constraint(equalTo: textInputMaterialView.contentView.topAnchor),
            textInputTintView.leadingAnchor.constraint(equalTo: textInputMaterialView.contentView.leadingAnchor),
            textInputTintView.trailingAnchor.constraint(equalTo: textInputMaterialView.contentView.trailingAnchor),
            textInputTintView.bottomAnchor.constraint(equalTo: textInputMaterialView.contentView.bottomAnchor),

            textView.topAnchor.constraint(equalTo: textInputContainerView.topAnchor),
            textView.leadingAnchor.constraint(equalTo: textInputContainerView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: textInputContainerView.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: textInputContainerView.bottomAnchor),

            textViewPlaceholderLabel.leadingAnchor.constraint(equalTo: textInputContainerView.leadingAnchor, constant: 16),
            textViewPlaceholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingActionButton.leadingAnchor, constant: -8),
            textViewPlaceholderLabel.topAnchor.constraint(equalTo: textInputContainerView.topAnchor, constant: 11),

            trailingActionButton.trailingAnchor.constraint(equalTo: textInputContainerView.trailingAnchor, constant: -5),
            trailingActionButton.bottomAnchor.constraint(equalTo: textInputContainerView.bottomAnchor, constant: -5),
            trailingActionButton.widthAnchor.constraint(equalToConstant: 34),
            trailingActionButton.heightAnchor.constraint(equalToConstant: 34),

            recordingCapsuleView.topAnchor.constraint(equalTo: textInputContainerView.topAnchor),
            recordingCapsuleView.leadingAnchor.constraint(equalTo: textInputContainerView.leadingAnchor),
            recordingCapsuleView.trailingAnchor.constraint(equalTo: textInputContainerView.trailingAnchor),
            recordingCapsuleView.bottomAnchor.constraint(equalTo: textInputContainerView.bottomAnchor),

            recordingStackView.leadingAnchor.constraint(equalTo: recordingCapsuleView.leadingAnchor, constant: 14),
            recordingStackView.trailingAnchor.constraint(equalTo: recordingCapsuleView.trailingAnchor, constant: -14),
            recordingStackView.centerYAnchor.constraint(equalTo: recordingCapsuleView.centerYAnchor),
            recordingIconView.widthAnchor.constraint(equalToConstant: 24),
            recordingIconView.heightAnchor.constraint(equalToConstant: 24),
            recordingLevelMeterView.widthAnchor.constraint(equalToConstant: 72),
            recordingLevelMeterView.heightAnchor.constraint(equalToConstant: 20),
            recordingStopButton.widthAnchor.constraint(equalToConstant: 34),
            recordingStopButton.heightAnchor.constraint(equalToConstant: 34),

            voicePreviewCapsuleView.topAnchor.constraint(equalTo: textInputContainerView.topAnchor),
            voicePreviewCapsuleView.leadingAnchor.constraint(equalTo: textInputContainerView.leadingAnchor),
            voicePreviewCapsuleView.trailingAnchor.constraint(equalTo: textInputContainerView.trailingAnchor),
            voicePreviewCapsuleView.bottomAnchor.constraint(equalTo: textInputContainerView.bottomAnchor),

            voicePreviewStackView.leadingAnchor.constraint(equalTo: voicePreviewCapsuleView.leadingAnchor, constant: 8),
            voicePreviewStackView.trailingAnchor.constraint(equalTo: voicePreviewCapsuleView.trailingAnchor, constant: -8),
            voicePreviewStackView.centerYAnchor.constraint(equalTo: voicePreviewCapsuleView.centerYAnchor),
            voicePreviewCancelButton.widthAnchor.constraint(equalToConstant: 34),
            voicePreviewCancelButton.heightAnchor.constraint(equalToConstant: 34),
            voicePreviewPlayButton.widthAnchor.constraint(equalToConstant: 34),
            voicePreviewPlayButton.heightAnchor.constraint(equalToConstant: 34),
            voicePreviewWaveformView.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            voicePreviewWaveformView.heightAnchor.constraint(equalToConstant: 20),
            voicePreviewSendButton.widthAnchor.constraint(equalToConstant: 42),
            voicePreviewSendButton.heightAnchor.constraint(equalToConstant: 34)
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
        configuration.baseBackgroundColor = Self.defaultTextInputTintColor
        moreButton.configuration = configuration
        moreButton.layer.cornerRadius = 22
        ChatBridgeDesignSystem.ShadowToken.applyBubbleShadow(to: moreButton.layer)
        moreButton.accessibilityLabel = "More"
        moreButton.accessibilityIdentifier = "chat.moreButton"
        moreButton.setContentHuggingPriority(.required, for: .horizontal)
        moreButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.menu = makeMoreMenu()
    }

    /// 配置附件预览区域
    private func configureAttachmentPreviewView() {
        attachmentPreviewView.translatesAutoresizingMaskIntoConstraints = false
        attachmentPreviewView.accessibilityIdentifier = "chat.pendingAttachmentPreview"

        attachmentPreviewScrollView.translatesAutoresizingMaskIntoConstraints = false
        attachmentPreviewScrollView.showsHorizontalScrollIndicator = false
        attachmentPreviewScrollView.alwaysBounceHorizontal = true
        attachmentPreviewScrollView.alwaysBounceVertical = false
        attachmentPreviewScrollView.contentInsetAdjustmentBehavior = .never

        attachmentPreviewStackView.translatesAutoresizingMaskIntoConstraints = false
        attachmentPreviewStackView.axis = .horizontal
        attachmentPreviewStackView.alignment = .top
        attachmentPreviewStackView.spacing = 8

        attachmentPreviewView.addSubview(attachmentPreviewScrollView)
        attachmentPreviewScrollView.addSubview(attachmentPreviewStackView)
    }

    /// 配置文本输入区域
    private func configureTextView() {
        textInputContainerView.translatesAutoresizingMaskIntoConstraints = false
        textInputContainerView.clipsToBounds = true
        textInputContainerView.layer.cornerRadius = 22
        textInputContainerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textInputContainerView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        textInputMaterialView.translatesAutoresizingMaskIntoConstraints = false
        textInputMaterialView.clipsToBounds = true
        textInputMaterialView.layer.cornerRadius = 22
        textInputMaterialView.isUserInteractionEnabled = false

        textInputTintView.translatesAutoresizingMaskIntoConstraints = false
        textInputTintView.backgroundColor = Self.defaultTextInputTintColor
        textInputTintView.isUserInteractionEnabled = false

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.returnKeyType = .default
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 11, left: 16, bottom: 11, right: 52)
        textView.textContainer.lineFragmentPadding = 0
        textView.accessibilityIdentifier = "chat.messageInput"
        textView.delegate = self
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        textViewPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textViewPlaceholderLabel.text = "Message"
        textViewPlaceholderLabel.textColor = .placeholderText
        textViewPlaceholderLabel.font = .preferredFont(forTextStyle: .body)
        textViewPlaceholderLabel.adjustsFontForContentSizeCategory = true
        textViewPlaceholderLabel.isUserInteractionEnabled = false

        textInputContainerView.addSubview(textInputMaterialView)
        textInputMaterialView.contentView.addSubview(textInputTintView)
        textInputContainerView.addSubview(textView)
        textInputContainerView.addSubview(textViewPlaceholderLabel)
        textInputContainerView.addSubview(trailingActionButton)
        textInputContainerView.addSubview(recordingCapsuleView)
    }

    /// 配置尾部发送/语音按钮
    private func configureTrailingActionButton() {
        trailingActionButton.translatesAutoresizingMaskIntoConstraints = false
        trailingActionButton.setContentHuggingPriority(.required, for: .horizontal)
        trailingActionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        trailingActionButton.addTarget(self, action: #selector(voiceButtonTouchDown), for: .touchDown)
        trailingActionButton.addTarget(self, action: #selector(voiceButtonTouchDragExit), for: .touchDragExit)
        trailingActionButton.addTarget(self, action: #selector(voiceButtonTouchDragEnter), for: .touchDragEnter)
        trailingActionButton.addTarget(self, action: #selector(voiceButtonTouchUpInside), for: .touchUpInside)
        trailingActionButton.addTarget(self, action: #selector(voiceButtonTouchUpOutside), for: .touchUpOutside)
        trailingActionButton.addTarget(self, action: #selector(voiceButtonTouchCancel), for: .touchCancel)
        trailingActionButton.addTarget(self, action: #selector(sendButtonTapped), for: .touchUpInside)
    }

    /// 配置录音胶囊视图
    private func configureRecordingCapsuleView() {
        recordingCapsuleView.translatesAutoresizingMaskIntoConstraints = false
        recordingCapsuleView.isHidden = true
        recordingCapsuleView.isUserInteractionEnabled = true

        recordingStackView.translatesAutoresizingMaskIntoConstraints = false
        recordingStackView.axis = .horizontal
        recordingStackView.alignment = .center
        recordingStackView.spacing = 8

        recordingIconView.translatesAutoresizingMaskIntoConstraints = false
        recordingIconView.contentMode = .scaleAspectFit
        recordingIconView.tintColor = .systemBlue
        recordingIconView.setContentHuggingPriority(.required, for: .horizontal)

        recordingDurationLabel.translatesAutoresizingMaskIntoConstraints = false
        recordingDurationLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        recordingDurationLabel.adjustsFontForContentSizeCategory = true
        recordingDurationLabel.textColor = .label
        recordingDurationLabel.setContentHuggingPriority(.required, for: .horizontal)

        recordingLevelMeterView.translatesAutoresizingMaskIntoConstraints = false
        recordingLevelMeterView.accessibilityIdentifier = "chat.recordingWaveform"

        recordingHintLabel.translatesAutoresizingMaskIntoConstraints = false
        recordingHintLabel.font = .preferredFont(forTextStyle: .subheadline)
        recordingHintLabel.adjustsFontForContentSizeCategory = true
        recordingHintLabel.textColor = .secondaryLabel
        recordingHintLabel.numberOfLines = 1
        recordingHintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        recordingStopButton.translatesAutoresizingMaskIntoConstraints = false
        recordingStopButton.accessibilityLabel = "Stop Voice Recording"
        recordingStopButton.accessibilityIdentifier = "chat.voiceStopButton"
        recordingStopButton.addTarget(self, action: #selector(recordingStopButtonTapped), for: .touchUpInside)

        recordingCapsuleView.addSubview(recordingStackView)
        recordingStackView.addArrangedSubview(recordingIconView)
        recordingStackView.addArrangedSubview(recordingLevelMeterView)
        recordingStackView.addArrangedSubview(recordingDurationLabel)
        recordingStackView.addArrangedSubview(recordingHintLabel)
        recordingStackView.addArrangedSubview(recordingStopButton)
    }

    /// 配置待发送语音预览胶囊
    private func configureVoicePreviewCapsuleView() {
        voicePreviewCapsuleView.translatesAutoresizingMaskIntoConstraints = false
        voicePreviewCapsuleView.isHidden = true
        voicePreviewCapsuleView.isUserInteractionEnabled = true

        voicePreviewStackView.translatesAutoresizingMaskIntoConstraints = false
        voicePreviewStackView.axis = .horizontal
        voicePreviewStackView.alignment = .center
        voicePreviewStackView.spacing = 8

        configureCircleButton(
            voicePreviewCancelButton,
            imageName: "xmark",
            foregroundColor: .label,
            backgroundColor: UIColor.systemGray5,
            accessibilityLabel: "Cancel Voice Preview",
            accessibilityIdentifier: "chat.voicePreviewCancelButton"
        )
        voicePreviewCancelButton.addTarget(self, action: #selector(voicePreviewCancelButtonTapped), for: .touchUpInside)

        configureCircleButton(
            voicePreviewPlayButton,
            imageName: "play.fill",
            foregroundColor: .label,
            backgroundColor: UIColor.systemGray5,
            accessibilityLabel: "Play Voice Preview",
            accessibilityIdentifier: "chat.voicePreviewPlayButton"
        )
        voicePreviewPlayButton.addTarget(self, action: #selector(voicePreviewPlayButtonTapped), for: .touchUpInside)

        voicePreviewWaveformView.translatesAutoresizingMaskIntoConstraints = false
        voicePreviewWaveformView.accessibilityIdentifier = "chat.voicePreviewWaveform"
        voicePreviewWaveformView.tintColor = .systemGray
        voicePreviewWaveformView.seedPreviewSamples()
        voicePreviewWaveformView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        voicePreviewDurationLabel.translatesAutoresizingMaskIntoConstraints = false
        voicePreviewDurationLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        voicePreviewDurationLabel.adjustsFontForContentSizeCategory = true
        voicePreviewDurationLabel.textColor = .label
        voicePreviewDurationLabel.setContentHuggingPriority(.required, for: .horizontal)

        configureCircleButton(
            voicePreviewSendButton,
            imageName: "arrow.up",
            foregroundColor: .white,
            backgroundColor: .systemGreen,
            accessibilityLabel: "Send Voice Preview",
            accessibilityIdentifier: "chat.voicePreviewSendButton"
        )
        voicePreviewSendButton.addTarget(self, action: #selector(voicePreviewSendButtonTapped), for: .touchUpInside)

        textInputContainerView.addSubview(voicePreviewCapsuleView)
        voicePreviewCapsuleView.addSubview(voicePreviewStackView)
        voicePreviewStackView.addArrangedSubview(voicePreviewCancelButton)
        voicePreviewStackView.addArrangedSubview(voicePreviewPlayButton)
        voicePreviewStackView.addArrangedSubview(voicePreviewWaveformView)
        voicePreviewStackView.addArrangedSubview(voicePreviewDurationLabel)
        voicePreviewStackView.addArrangedSubview(voicePreviewSendButton)
    }

    /// 配置圆形图标按钮
    private func configureCircleButton(
        _ button: UIButton,
        imageName: String,
        foregroundColor: UIColor,
        backgroundColor: UIColor,
        accessibilityLabel: String,
        accessibilityIdentifier: String
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

    /// 配置录音状态标签
    private func configureRecordingStatusLabel() {
        recordingStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        recordingStatusLabel.font = .preferredFont(forTextStyle: .caption1)
        recordingStatusLabel.adjustsFontForContentSizeCategory = true
        recordingStatusLabel.textAlignment = .center
        recordingStatusLabel.textColor = .secondaryLabel
        recordingStatusLabel.isHidden = true
    }

    /// 重新构建附件预览项视图
    private func rebuildAttachmentPreviewItems() {
        attachmentPreviewStackView.arrangedSubviews.forEach { view in
            attachmentPreviewStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for item in pendingAttachmentPreviewItems {
            let itemView = PendingAttachmentPreviewItemView(item: item)
            itemView.onRemove = { [weak self] id in
                self?.removeAttachmentPreviewItem(id: id)
            }
            attachmentPreviewStackView.addArrangedSubview(itemView)
        }
    }

    /// 修正附件预览横向滚动视图的垂直偏移
    private func normalizeAttachmentPreviewScrollOffset() {
        let offset = attachmentPreviewScrollView.contentOffset
        guard abs(offset.y) > 0.5 else { return }
        attachmentPreviewScrollView.contentOffset = CGPoint(x: offset.x, y: 0)
    }

    /// 移除指定附件预览项
    private func removeAttachmentPreviewItem(id: String) {
        guard pendingAttachmentPreviewItems.contains(where: { $0.id == id }) else { return }
        pendingAttachmentPreviewItems.removeAll { $0.id == id }
        hasPendingAttachment = !pendingAttachmentPreviewItems.isEmpty
        isPendingAttachmentLoading = pendingAttachmentPreviewItems.contains { $0.isLoading }
        rebuildAttachmentPreviewItems()
        setAttachmentPreviewHidden(pendingAttachmentPreviewItems.isEmpty, animated: true)
        renderTrailingActionState()
        onAttachmentRemoved?(id)
    }

    /// 语音按钮按下事件
    @objc private func voiceButtonTouchDown() {
        guard canRecordVoice else { return }
        onVoiceTouchDown?()
    }

    /// 语音按钮拖出事件
    @objc private func voiceButtonTouchDragExit() {
        guard isRecording || canRecordVoice else { return }
        onVoiceTouchDragExit?()
    }

    /// 语音按钮拖回事件
    @objc private func voiceButtonTouchDragEnter() {
        guard isRecording || canRecordVoice else { return }
        onVoiceTouchDragEnter?()
    }

    /// 语音按钮内部松开事件
    @objc private func voiceButtonTouchUpInside() {
        guard isRecording || canRecordVoice else { return }
        onVoiceTouchUpInside?()
    }

    /// 语音按钮外部松开事件
    @objc private func voiceButtonTouchUpOutside() {
        guard isRecording || canRecordVoice else { return }
        onVoiceTouchUpOutside?()
    }

    /// 语音按钮触摸取消事件
    @objc private func voiceButtonTouchCancel() {
        guard isRecording || canRecordVoice else { return }
        onVoiceTouchCancel?()
    }

    /// 发送按钮点击事件
    @objc private func sendButtonTapped() {
        guard canSendComposition, textView.isEditable else { return }
        sendCurrentComposition()
    }

    /// 录音停止按钮点击事件
    @objc private func recordingStopButtonTapped() {
        guard isRecording else { return }
        onVoiceTouchUpInside?()
    }

    /// 待发送语音取消按钮点击事件
    @objc private func voicePreviewCancelButtonTapped() {
        guard hasPendingVoicePreview else { return }
        onVoicePreviewCancel?()
    }

    /// 待发送语音播放按钮点击事件
    @objc private func voicePreviewPlayButtonTapped() {
        guard hasPendingVoicePreview else { return }
        onVoicePreviewPlayToggle?()
    }

    /// 待发送语音发送按钮点击事件
    @objc private func voicePreviewSendButtonTapped() {
        guard hasPendingVoicePreview else { return }
        onVoicePreviewSend?()
    }

    /// 发送当前输入组合
    private func sendCurrentComposition() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || (hasPendingAttachment && !isPendingAttachmentLoading) else { return }

        textView.text = ""
        renderTextViewPlaceholder()
        renderTrailingActionState()
        updateTextViewHeight(animated: true)
        onTextChanged?("")
        onSend?(trimmedText)
    }

    /// 渲染尾部按钮的发送或录音状态
    private func renderTrailingActionState() {
        let showsSend = canSendComposition && textView.isEditable

        let hidesTrailingAction = isRecording || hasPendingVoicePreview
        trailingActionButton.alpha = hidesTrailingAction ? 0 : 1
        trailingActionButton.isAccessibilityElement = !hidesTrailingAction
        trailingActionButton.accessibilityElementsHidden = hidesTrailingAction
        trailingActionButton.isEnabled = isRecording || showsSend || canRecordVoice
        trailingActionButton.accessibilityLabel = showsSend ? "Send" : "Hold to Record Voice"
        trailingActionButton.accessibilityIdentifier = showsSend ? "chat.sendButton" : "chat.voiceButton"

        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: showsSend ? "arrow.up" : "mic")
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        configuration.baseForegroundColor = showsSend ? .white : .secondaryLabel
        configuration.baseBackgroundColor = showsSend
            ? UIColor.systemBlue
            : UIColor.clear
        trailingActionButton.configuration = configuration
    }

    /// 显示或隐藏附件预览区域
    private func setAttachmentPreviewHidden(_ isHidden: Bool, animated: Bool) {
        guard attachmentPreviewView.isHidden != isHidden else { return }

        let shouldStickToBottom = onHeightWillChange?() ?? false
        let layoutChanges = { [weak self] in
            guard let self else { return }
            self.attachmentPreviewView.isHidden = isHidden
            self.superview?.layoutIfNeeded()
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            self?.onHeightDidChange?(shouldStickToBottom)
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
        textView.isHidden = hidesTextInput
        textViewPlaceholderLabel.isHidden = hidesTextInput || !text.isEmpty
    }

    /// 渲染录音胶囊状态
    private func renderRecordingCapsule(_ state: VoiceRecordingState) {
        recordingCapsuleView.isHidden = !state.isRecording

        guard state.isRecording else {
            textInputTintView.backgroundColor = Self.defaultTextInputTintColor
            recordingLevelMeterView.powerLevel = 0
            return
        }

        let accentColor: UIColor = .systemRed
        textInputTintView.backgroundColor = Self.defaultTextInputTintColor
        recordingIconView.image = UIImage(systemName: state.isCanceling ? "xmark.circle.fill" : "mic.fill")
        recordingIconView.tintColor = accentColor
        recordingDurationLabel.text = Self.voiceDurationText(milliseconds: state.elapsedMilliseconds)
        recordingDurationLabel.textColor = accentColor
        recordingLevelMeterView.tintColor = accentColor
        recordingLevelMeterView.appendPowerLevel(state.averagePowerLevel)
        recordingHintLabel.text = state.isCanceling ? state.hintText : nil
        recordingHintLabel.textColor = state.isCanceling ? .systemRed : .secondaryLabel
        recordingHintLabel.isHidden = !state.isCanceling
        configureCircleButton(
            recordingStopButton,
            imageName: "stop.fill",
            foregroundColor: .systemRed,
            backgroundColor: UIColor.systemRed.withAlphaComponent(0.16),
            accessibilityLabel: "Stop Voice Recording",
            accessibilityIdentifier: "chat.voiceStopButton"
        )
    }

    /// 渲染待发送语音预览
    private func renderVoicePreviewCapsule() {
        voicePreviewDurationLabel.text = Self.voicePlaybackDurationText(
            elapsedMilliseconds: pendingVoicePreviewElapsedMilliseconds,
            durationMilliseconds: pendingVoicePreviewDurationMilliseconds,
            isPlaying: isPendingVoicePreviewPlaying
        )
        voicePreviewWaveformView.playbackProgress = pendingVoicePreviewPlaybackProgress
        let playImageName = isPendingVoicePreviewPlaying ? "pause.fill" : "play.fill"
        let playLabel = isPendingVoicePreviewPlaying ? "Pause Voice Preview" : "Play Voice Preview"
        configureCircleButton(
            voicePreviewPlayButton,
            imageName: playImageName,
            foregroundColor: .label,
            backgroundColor: UIColor.systemGray5,
            accessibilityLabel: playLabel,
            accessibilityIdentifier: "chat.voicePreviewPlayButton"
        )
    }

    /// 显示或隐藏待发送语音预览
    private func setVoicePreviewHidden(_ isHidden: Bool, animated: Bool) {
        guard voicePreviewCapsuleView.isHidden != isHidden else { return }
        voicePreviewCapsuleView.accessibilityElementsHidden = isHidden
        voicePreviewCancelButton.accessibilityIdentifier = isHidden ? nil : "chat.voicePreviewCancelButton"
        voicePreviewPlayButton.accessibilityIdentifier = isHidden ? nil : "chat.voicePreviewPlayButton"
        voicePreviewWaveformView.accessibilityIdentifier = isHidden ? nil : "chat.voicePreviewWaveform"
        voicePreviewSendButton.accessibilityIdentifier = isHidden ? nil : "chat.voicePreviewSendButton"

        let animations = { [weak self] in
            self?.voicePreviewCapsuleView.isHidden = isHidden
            self?.superview?.layoutIfNeeded()
        }

        if animated {
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: animations
            )
        } else {
            animations()
        }
    }

    /// 根据内容更新文本输入高度
    private func updateTextViewHeight(animated: Bool) {
        let maxHeight = maximumTextViewHeight()
        let fittingSize = CGSize(width: max(textView.bounds.width, 1), height: .greatestFiniteMagnitude)
        let measuredHeight = textView.sizeThatFits(fittingSize).height
        let targetHeight = min(max(44, ceil(measuredHeight)), maxHeight)

        guard textInputHeightConstraint?.constant != targetHeight else {
            textView.isScrollEnabled = measuredHeight > maxHeight
            return
        }

        let shouldStickToBottom = onHeightWillChange?() ?? false
        textView.isScrollEnabled = measuredHeight > maxHeight
        textInputHeightConstraint?.constant = targetHeight

        let layoutChanges = { [weak self] in
            guard let self else { return }
            self.superview?.layoutIfNeeded()
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            self?.onHeightDidChange?(shouldStickToBottom)
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

    /// 文本输入最大高度
    private func maximumTextViewHeight() -> CGFloat {
        let font = textView.font ?? .preferredFont(forTextStyle: .body)
        return ceil(font.lineHeight * 5 + textView.textContainerInset.top + textView.textContainerInset.bottom)
    }

    /// 格式化录音时长文本
    private static func voiceDurationText(milliseconds: Int) -> String {
        let seconds = max(0, milliseconds / 1_000)
        return "0:\(String(format: "%02d", seconds))"
    }

    /// 格式化语音播放时长文本
    private static func voicePlaybackDurationText(
        elapsedMilliseconds: Int,
        durationMilliseconds: Int,
        isPlaying: Bool
    ) -> String {
        let totalText = ChatMessageRowContent.voiceDurationDisplayText(milliseconds: durationMilliseconds)
        guard isPlaying else {
            return totalText
        }

        let elapsedText = ChatMessageRowContent.voiceElapsedDisplayText(milliseconds: elapsedMilliseconds)
        return "\(elapsedText)/\(totalText)"
    }

    /// 创建更多操作菜单
    private func makeMoreMenu() -> UIMenu {
        let emojiAction = UIAction(
            title: "表情",
            image: UIImage(systemName: "face.smiling")
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onEmojiTapped?()
            }
        }
        let photoAction = UIAction(
            title: "Choose Photo or Video",
            image: UIImage(systemName: "photo.on.rectangle")
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onPhotoTapped?()
            }
        }

        return UIMenu(children: [emojiAction, photoAction])
    }
}

/// 文本输入代理
extension ChatInputBarView: UITextViewDelegate {
    /// 开始编辑时从相册输入切回键盘
    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        if isShowingPhotoLibraryInput {
            if !isWaitingForKeyboardInputTransition {
                isWaitingForKeyboardInputTransition = true
                onKeyboardInputRequested?()
            }
            return false
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
        onTextChanged?(textView.text)
    }
}

/// 待发送附件预览项视图
@MainActor
private final class PendingAttachmentPreviewItemView: UIView {
    /// 移除附件回调
    var onRemove: ((String) -> Void)?

    /// 附件 ID
    private let itemID: String
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
        imageView.backgroundColor = ChatBridgeDesignSystem.ColorToken.appleMessageIncoming
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = ChatBridgeDesignSystem.RadiusToken.appleComposerAttachment

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.34)
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
        removeButton.backgroundColor = UIColor.systemGray.withAlphaComponent(0.88)
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
        onRemove?(itemID)
    }
}

/// 语音录制音量电平视图
@MainActor
private final class VoiceLevelMeterView: UIView {
    /// 最多保留的波形样本数量
    private static let maximumSampleCount = 42
    /// 波形高度样本，数组尾部是最新样本
    private var samples: [Double] = []
    /// 已裁剪的播放进度。
    private var playbackProgressValue: Double?
    /// 播放进度。录音电平视图为 nil，预览播放视图为 0...1。
    var playbackProgress: Double? {
        get {
            playbackProgressValue
        }
        set {
            playbackProgressValue = newValue.map { min(1, max(0, $0)) }
            setNeedsDisplay()
        }
    }

    /// 归一化音量值，范围 0...1
    var powerLevel: Double = 0 {
        didSet {
            powerLevel = max(0, min(1, powerLevel))
            samples = [powerLevel]
            playbackProgress = nil
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

    /// 追加新的实时音量样本，视觉上从右侧进入、旧样本向左移动。
    func appendPowerLevel(_ level: Double) {
        playbackProgress = nil
        let clampedLevel = max(0, min(1, level))
        samples.append(clampedLevel)
        if samples.count > Self.maximumSampleCount {
            samples.removeFirst(samples.count - Self.maximumSampleCount)
        }
        setNeedsDisplay()
    }

    /// 为待发送预览生成稳定波形。
    func seedPreviewSamples() {
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

        let visibleSamples = samples.isEmpty ? Array(repeating: powerLevel, count: 9) : samples
        let barCount = visibleSamples.count
        let spacing: CGFloat = 3
        let barWidth = max(2, min(4, (rect.width - CGFloat(barCount - 1) * spacing) / CGFloat(barCount)))
        let contentWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        let startX = max(0, rect.width - contentWidth)

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
}
