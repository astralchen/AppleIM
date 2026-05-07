//
//  ChatInputBarView.swift
//  AppleIM
//

import UIKit

@MainActor
struct ChatPendingAttachmentPreviewItem {
    let id: String
    let image: UIImage?
    let title: String
    let durationText: String?
    let isVideo: Bool
    let isLoading: Bool
}

@MainActor
final class ChatInputBarView: UIView {
    var onTextChanged: ((String) -> Void)?
    var onSend: ((String) -> Void)?
    var onPhotoTapped: (() -> Void)?
    var onAttachmentRemoved: ((String) -> Void)?
    var onVoiceTouchDown: (() -> Void)?
    var onVoiceTouchDragExit: (() -> Void)?
    var onVoiceTouchDragEnter: (() -> Void)?
    var onVoiceTouchUpInside: (() -> Void)?
    var onVoiceTouchUpOutside: (() -> Void)?
    var onVoiceTouchCancel: (() -> Void)?
    var onHeightWillChange: (() -> Bool)?
    var onHeightDidChange: ((Bool) -> Void)?

    private let glassContainerView = GlassContainerView(cornerRadius: ChatBridgeDesignSystem.RadiusToken.inputBar)
    private let contentStackView = UIStackView()
    private let recordingStatusLabel = UILabel()
    private let attachmentPreviewView = UIView()
    private let attachmentPreviewScrollView = UIScrollView()
    private let attachmentPreviewStackView = UIStackView()
    private let inputStackView = UIStackView()
    private let moreButton = UIButton(type: .system)
    private let textInputContainerView = UIView()
    private let textInputMaterialView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let textInputTintView = UIView()
    private let textView = UITextView()
    private let textViewPlaceholderLabel = UILabel()
    private let trailingActionButton = UIButton(type: .system)
    private let recordingCapsuleView = UIView()
    private let recordingStackView = UIStackView()
    private let recordingIconView = UIImageView(image: UIImage(systemName: "mic.fill"))
    private let recordingDurationLabel = UILabel()
    private let recordingLevelMeterView = VoiceLevelMeterView()
    private let recordingHintLabel = UILabel()

    private var textInputHeightConstraint: NSLayoutConstraint?
    private weak var photoLibraryInputView: UIView?
    private var isReturnKeySending = false
    private var isRecording = false
    private var isShowingPhotoLibraryInput = false
    private var hasPendingAttachment = false
    private var isPendingAttachmentLoading = false
    private var pendingAttachmentPreviewItems: [ChatPendingAttachmentPreviewItem] = []
    private var lastMeasuredTextWidth: CGFloat = 0
    private var statusHideTask: Task<Void, Never>?

    var text: String {
        textView.text ?? ""
    }

    var isEditingText: Bool {
        textView.isFirstResponder
    }

    private var canSendText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSendComposition: Bool {
        canSendText || (hasPendingAttachment && !isPendingAttachmentLoading)
    }

    private var canRecordVoice: Bool {
        !canSendText && !hasPendingAttachment && textView.isEditable
    }

    private static var defaultTextInputTintColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.64)
                : UIColor.white.withAlphaComponent(0.70)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
        renderReturnMode()
        renderTrailingActionState()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
        renderReturnMode()
        renderTrailingActionState()
    }

    deinit {
        statusHideTask?.cancel()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        defer { normalizeAttachmentPreviewScrollOffset() }

        let width = textView.bounds.width
        guard abs(width - lastMeasuredTextWidth) > 0.5 else { return }
        lastMeasuredTextWidth = width
        updateTextViewHeight(animated: false)
    }

    func setText(_ text: String, animated: Bool) {
        guard textView.text != text else { return }
        textView.text = text
        renderTextViewPlaceholder()
        renderTrailingActionState()
        updateTextViewHeight(animated: animated)
    }

    func renderVoiceRecordingState(_ state: VoiceRecordingState) {
        isRecording = state.isRecording
        recordingStatusLabel.isHidden = true
        recordingStatusLabel.text = nil

        renderRecordingCapsule(state)
        textView.isEditable = !state.isRecording
        moreButton.isEnabled = !state.isRecording
        renderTextViewPlaceholder()
        renderTrailingActionState()
    }

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

    func setPhotoLibraryInputView(_ view: UIView?) {
        photoLibraryInputView = view
        if isShowingPhotoLibraryInput {
            textView.inputView = view
            textView.reloadInputViews()
        }
    }

    func showPhotoLibraryInput() {
        isShowingPhotoLibraryInput = true
        textView.inputView = photoLibraryInputView
        textView.becomeFirstResponder()
        textView.reloadInputViews()
    }

    func showKeyboardInput() {
        isShowingPhotoLibraryInput = false
        textView.inputView = nil
        textView.becomeFirstResponder()
        textView.reloadInputViews()
    }

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

    func setPendingAttachmentPreviews(_ items: [ChatPendingAttachmentPreviewItem], animated: Bool) {
        pendingAttachmentPreviewItems = items
        hasPendingAttachment = !items.isEmpty
        isPendingAttachmentLoading = items.contains { $0.isLoading }
        rebuildAttachmentPreviewItems()
        normalizeAttachmentPreviewScrollOffset()
        setAttachmentPreviewHidden(items.isEmpty, animated: animated)
        renderTrailingActionState()
    }

    func clearPendingAttachmentPreview(animated: Bool) {
        clearPendingAttachmentPreviews(animated: animated)
    }

    func clearPendingAttachmentPreviews(animated: Bool) {
        pendingAttachmentPreviewItems.removeAll()
        hasPendingAttachment = false
        isPendingAttachmentLoading = false
        rebuildAttachmentPreviewItems()
        normalizeAttachmentPreviewScrollOffset()
        setAttachmentPreviewHidden(true, animated: animated)
        renderTrailingActionState()
    }

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
        configureRecordingStatusLabel()

        addSubview(glassContainerView)
        glassContainerView.contentView.addSubview(contentStackView)

        contentStackView.addArrangedSubview(recordingStatusLabel)
        contentStackView.addArrangedSubview(attachmentPreviewView)
        contentStackView.addArrangedSubview(inputStackView)
        attachmentPreviewView.isHidden = true

        inputStackView.addArrangedSubview(moreButton)
        inputStackView.addArrangedSubview(textInputContainerView)

        let textInputHeightConstraint = textInputContainerView.heightAnchor.constraint(equalToConstant: 44)
        self.textInputHeightConstraint = textInputHeightConstraint

        NSLayoutConstraint.activate([
            glassContainerView.topAnchor.constraint(equalTo: topAnchor),
            glassContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            contentStackView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),

            attachmentPreviewScrollView.topAnchor.constraint(equalTo: attachmentPreviewView.topAnchor, constant: 4),
            attachmentPreviewScrollView.leadingAnchor.constraint(equalTo: attachmentPreviewView.leadingAnchor),
            attachmentPreviewScrollView.trailingAnchor.constraint(equalTo: attachmentPreviewView.trailingAnchor),
            attachmentPreviewScrollView.bottomAnchor.constraint(equalTo: attachmentPreviewView.bottomAnchor, constant: -4),
            attachmentPreviewScrollView.heightAnchor.constraint(equalToConstant: 82),

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
            recordingLevelMeterView.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    private func configureMoreButton() {
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        var configuration = ChatBridgeDesignSystem.makeGlassButtonConfiguration(role: .circularTool)
        configuration.image = UIImage(systemName: "plus")
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        moreButton.configuration = configuration
        moreButton.accessibilityLabel = "More"
        moreButton.accessibilityIdentifier = "chat.moreButton"
        moreButton.setContentHuggingPriority(.required, for: .horizontal)
        moreButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        moreButton.showsMenuAsPrimaryAction = true
    }

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

    private func configureRecordingCapsuleView() {
        recordingCapsuleView.translatesAutoresizingMaskIntoConstraints = false
        recordingCapsuleView.isHidden = true
        recordingCapsuleView.isUserInteractionEnabled = false

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

        recordingHintLabel.translatesAutoresizingMaskIntoConstraints = false
        recordingHintLabel.font = .preferredFont(forTextStyle: .subheadline)
        recordingHintLabel.adjustsFontForContentSizeCategory = true
        recordingHintLabel.textColor = .secondaryLabel
        recordingHintLabel.numberOfLines = 1
        recordingHintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        recordingCapsuleView.addSubview(recordingStackView)
        recordingStackView.addArrangedSubview(recordingIconView)
        recordingStackView.addArrangedSubview(recordingDurationLabel)
        recordingStackView.addArrangedSubview(recordingLevelMeterView)
        recordingStackView.addArrangedSubview(recordingHintLabel)
    }

    private func configureRecordingStatusLabel() {
        recordingStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        recordingStatusLabel.font = .preferredFont(forTextStyle: .caption1)
        recordingStatusLabel.adjustsFontForContentSizeCategory = true
        recordingStatusLabel.textAlignment = .center
        recordingStatusLabel.textColor = .secondaryLabel
        recordingStatusLabel.isHidden = true
    }

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

    private func normalizeAttachmentPreviewScrollOffset() {
        let offset = attachmentPreviewScrollView.contentOffset
        guard abs(offset.y) > 0.5 else { return }
        attachmentPreviewScrollView.contentOffset = CGPoint(x: offset.x, y: 0)
    }

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

    @objc private func voiceButtonTouchDown() {
        guard canRecordVoice else { return }
        onVoiceTouchDown?()
    }

    @objc private func voiceButtonTouchDragExit() {
        guard isRecording || canRecordVoice else { return }
        onVoiceTouchDragExit?()
    }

    @objc private func voiceButtonTouchDragEnter() {
        guard isRecording || canRecordVoice else { return }
        onVoiceTouchDragEnter?()
    }

    @objc private func voiceButtonTouchUpInside() {
        guard isRecording || canRecordVoice else { return }
        onVoiceTouchUpInside?()
    }

    @objc private func voiceButtonTouchUpOutside() {
        guard isRecording || canRecordVoice else { return }
        onVoiceTouchUpOutside?()
    }

    @objc private func voiceButtonTouchCancel() {
        guard isRecording || canRecordVoice else { return }
        onVoiceTouchCancel?()
    }

    @objc private func sendButtonTapped() {
        guard canSendComposition, textView.isEditable else { return }
        sendCurrentComposition()
    }

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

    private func renderReturnMode() {
        textView.returnKeyType = isReturnKeySending ? .send : .default
        moreButton.menu = makeMoreMenu()
        moreButton.accessibilityValue = isReturnKeySending ? "Return Sends On" : "Return Sends Off"
    }

    private func renderTrailingActionState() {
        let showsSend = canSendComposition && textView.isEditable

        trailingActionButton.alpha = isRecording ? 0 : 1
        trailingActionButton.isAccessibilityElement = !isRecording
        trailingActionButton.accessibilityElementsHidden = isRecording
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

    private func renderTextViewPlaceholder() {
        textView.isHidden = isRecording
        textViewPlaceholderLabel.isHidden = isRecording || !text.isEmpty
    }

    private func renderRecordingCapsule(_ state: VoiceRecordingState) {
        recordingCapsuleView.isHidden = !state.isRecording

        guard state.isRecording else {
            textInputTintView.backgroundColor = Self.defaultTextInputTintColor
            recordingLevelMeterView.powerLevel = 0
            return
        }

        let accentColor: UIColor = state.isCanceling ? .systemRed : .systemBlue
        textInputTintView.backgroundColor = UIColor { traits in
            let alpha: CGFloat = traits.userInterfaceStyle == .dark ? 0.24 : 0.12
            return accentColor.withAlphaComponent(alpha)
        }
        recordingIconView.image = UIImage(systemName: state.isCanceling ? "xmark.circle.fill" : "mic.fill")
        recordingIconView.tintColor = accentColor
        recordingDurationLabel.text = Self.voiceDurationText(milliseconds: state.elapsedMilliseconds)
        recordingDurationLabel.textColor = state.isCanceling ? .systemRed : .label
        recordingLevelMeterView.tintColor = accentColor
        recordingLevelMeterView.powerLevel = state.averagePowerLevel
        recordingHintLabel.text = state.hintText
        recordingHintLabel.textColor = state.isCanceling ? .systemRed : .secondaryLabel
    }

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

    private func maximumTextViewHeight() -> CGFloat {
        let font = textView.font ?? .preferredFont(forTextStyle: .body)
        return ceil(font.lineHeight * 5 + textView.textContainerInset.top + textView.textContainerInset.bottom)
    }

    private static func voiceDurationText(milliseconds: Int) -> String {
        let seconds = max(0, milliseconds / 1_000)
        let tenths = max(0, (milliseconds % 1_000) / 100)
        return "\(seconds).\(tenths)s"
    }

    private func makeMoreMenu() -> UIMenu {
        let photoAction = UIAction(
            title: "Choose Photo or Video",
            image: UIImage(systemName: "photo.on.rectangle")
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onPhotoTapped?()
            }
        }

        let returnAction = UIAction(
            title: "Return Sends",
            image: UIImage(systemName: isReturnKeySending ? "paperplane.fill" : "arrow.turn.down.left"),
            state: isReturnKeySending ? .on : .off
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isReturnKeySending.toggle()
                self.renderReturnMode()
                self.textView.reloadInputViews()
            }
        }

        return UIMenu(children: [photoAction, returnAction])
    }
}

extension ChatInputBarView: UITextViewDelegate {
    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        if isShowingPhotoLibraryInput {
            showKeyboardInput()
        }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        renderTextViewPlaceholder()
        renderTrailingActionState()
        updateTextViewHeight(animated: true)
        onTextChanged?(textView.text)
    }

    func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        guard text == "\n", isReturnKeySending else {
            return true
        }

        sendCurrentComposition()
        return false
    }
}

@MainActor
private final class PendingAttachmentPreviewItemView: UIView {
    var onRemove: ((String) -> Void)?

    private let itemID: String
    private let imageView = UIImageView()
    private let overlayView = UIView()
    private let iconView = UIImageView()
    private let durationLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let removeButton = UIButton(type: .system)

    init(item: ChatPendingAttachmentPreviewItem) {
        itemID = item.id
        super.init(frame: .zero)
        configureView()
        configure(item: item)
    }

    required init?(coder: NSCoder) {
        itemID = ""
        super.init(coder: coder)
        configureView()
    }

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

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.backgroundColor = .secondarySystemGroupedBackground
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = ChatBridgeDesignSystem.RadiusToken.media

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.46)
        overlayView.isUserInteractionEnabled = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
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
        removeButton.backgroundColor = UIColor.black.withAlphaComponent(0.56)
        removeButton.tintColor = .white
        removeButton.clipsToBounds = true
        removeButton.layer.cornerRadius = 15
        removeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        removeButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold),
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
            widthAnchor.constraint(equalToConstant: 82),
            heightAnchor.constraint(equalToConstant: 82),

            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 72),
            imageView.heightAnchor.constraint(equalToConstant: 72),

            overlayView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            overlayView.heightAnchor.constraint(equalToConstant: 24),

            iconView.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 7),
            iconView.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 13),
            iconView.heightAnchor.constraint(equalToConstant: 13),

            durationLabel.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -6),
            durationLabel.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor),
            durationLabel.leadingAnchor.constraint(greaterThanOrEqualTo: iconView.trailingAnchor, constant: 4),

            spinner.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),

            removeButton.topAnchor.constraint(equalTo: topAnchor),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 30),
            removeButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    @objc private func removeButtonTapped() {
        guard removeButton.isEnabled else { return }
        onRemove?(itemID)
    }
}

@MainActor
private final class VoiceLevelMeterView: UIView {
    var powerLevel: Double = 0 {
        didSet {
            powerLevel = max(0, min(1, powerLevel))
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }

    override func draw(_ rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }

        let barCount = 9
        let spacing: CGFloat = 3
        let barWidth = max(2, (rect.width - CGFloat(barCount - 1) * spacing) / CGFloat(barCount))
        let activeIndex = Int(ceil(powerLevel * Double(barCount)))

        for index in 0..<barCount {
            let progress = CGFloat(index) / CGFloat(max(barCount - 1, 1))
            let heightScale = 0.32 + 0.68 * sin(progress * .pi)
            let barHeight = max(4, rect.height * heightScale)
            let x = CGFloat(index) * (barWidth + spacing)
            let y = (rect.height - barHeight) / 2
            let path = UIBezierPath(
                roundedRect: CGRect(x: x, y: y, width: barWidth, height: barHeight),
                cornerRadius: barWidth / 2
            )
            let color = index < activeIndex
                ? tintColor.withAlphaComponent(0.92)
                : UIColor.systemGray3.withAlphaComponent(0.72)
            color.setFill()
            path.fill()
        }
    }
}
