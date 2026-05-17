//
//  ChatComposerFieldView.swift
//  AppleIM
//

import UIKit

/// 文本输入胶囊向输入栏发布的局部动作。
enum ChatComposerFieldAction {
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
struct ChatComposerTextHeightMeasurement {
    /// 目标高度。
    let targetHeight: CGFloat
    /// 文本是否超过最大高度，需要滚动。
    let shouldScroll: Bool
}

/// 聊天文本输入胶囊。
@MainActor
final class ChatComposerFieldView: UIView {
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

