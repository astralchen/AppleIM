//
//  ChatInputBarView.swift
//  AppleIM
//

import UIKit

@MainActor
final class ChatInputBarView: UIView {
    var onTextChanged: ((String) -> Void)?
    var onSend: ((String) -> Void)?
    var onPhotoTapped: (() -> Void)?
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
    private let inputStackView = UIStackView()
    private let moreButton = UIButton(type: .system)
    private let voiceButton = UIButton(type: .system)
    private let textInputContainerView = UIView()
    private let textInputMaterialView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let textInputTintView = UIView()
    private let textView = UITextView()
    private let textViewPlaceholderLabel = UILabel()
    private let sendButton = UIButton(type: .system)

    private var textInputHeightConstraint: NSLayoutConstraint?
    private var isReturnKeySending = false
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
        renderReturnMode()
        renderSendButtonState()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
        renderReturnMode()
        renderSendButtonState()
    }

    deinit {
        statusHideTask?.cancel()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = textView.bounds.width
        guard abs(width - lastMeasuredTextWidth) > 0.5 else { return }
        lastMeasuredTextWidth = width
        updateTextViewHeight(animated: false)
    }

    func setText(_ text: String, animated: Bool) {
        guard textView.text != text else { return }
        textView.text = text
        renderTextViewPlaceholder()
        renderSendButtonState()
        updateTextViewHeight(animated: animated)
    }

    func renderVoiceRecordingState(_ state: VoiceRecordingState) {
        recordingStatusLabel.isHidden = !state.isRecording && state.hintText == "Hold to talk"
        recordingStatusLabel.text = state.isRecording
            ? "\(state.hintText) · \(Self.voiceDurationText(milliseconds: state.elapsedMilliseconds))"
            : state.hintText
        recordingStatusLabel.textColor = state.isCanceling ? .systemRed : .secondaryLabel

        let microphoneImageName = state.isRecording ? "mic.fill" : "mic"
        voiceButton.configuration?.image = UIImage(systemName: microphoneImageName)
        voiceButton.tintColor = state.isCanceling ? .systemRed : .systemBlue
        textView.isEditable = !state.isRecording
        moreButton.isEnabled = !state.isRecording
        renderSendButtonState()
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
        configureVoiceButton()
        configureTextView()
        configureSendButton()
        configureRecordingStatusLabel()

        addSubview(glassContainerView)
        glassContainerView.contentView.addSubview(contentStackView)

        contentStackView.addArrangedSubview(recordingStatusLabel)
        contentStackView.addArrangedSubview(inputStackView)

        inputStackView.addArrangedSubview(moreButton)
        inputStackView.addArrangedSubview(voiceButton)
        inputStackView.addArrangedSubview(textInputContainerView)
        inputStackView.addArrangedSubview(sendButton)

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

            moreButton.widthAnchor.constraint(equalToConstant: 44),
            moreButton.heightAnchor.constraint(equalToConstant: 44),
            voiceButton.widthAnchor.constraint(equalToConstant: 44),
            voiceButton.heightAnchor.constraint(equalToConstant: 44),
            textInputHeightConstraint,
            sendButton.widthAnchor.constraint(equalToConstant: 44),
            sendButton.heightAnchor.constraint(equalToConstant: 44),

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
            textViewPlaceholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textInputContainerView.trailingAnchor, constant: -16),
            textViewPlaceholderLabel.topAnchor.constraint(equalTo: textInputContainerView.topAnchor, constant: 11)
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

    private func configureVoiceButton() {
        voiceButton.translatesAutoresizingMaskIntoConstraints = false
        var configuration = ChatBridgeDesignSystem.makeGlassButtonConfiguration(role: .circularTool)
        configuration.image = UIImage(systemName: "mic")
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        voiceButton.configuration = configuration
        voiceButton.accessibilityLabel = "Hold to Record Voice"
        voiceButton.accessibilityIdentifier = "chat.voiceButton"
        voiceButton.setContentHuggingPriority(.required, for: .horizontal)
        voiceButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        voiceButton.addTarget(self, action: #selector(voiceButtonTouchDown), for: .touchDown)
        voiceButton.addTarget(self, action: #selector(voiceButtonTouchDragExit), for: .touchDragExit)
        voiceButton.addTarget(self, action: #selector(voiceButtonTouchDragEnter), for: .touchDragEnter)
        voiceButton.addTarget(self, action: #selector(voiceButtonTouchUpInside), for: .touchUpInside)
        voiceButton.addTarget(self, action: #selector(voiceButtonTouchUpOutside), for: .touchUpOutside)
        voiceButton.addTarget(self, action: #selector(voiceButtonTouchCancel), for: .touchCancel)
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
        textInputTintView.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.64)
                : UIColor.white.withAlphaComponent(0.70)
        }
        textInputTintView.isUserInteractionEnabled = false

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.returnKeyType = .default
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 11, left: 12, bottom: 11, right: 12)
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
    }

    private func configureSendButton() {
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.accessibilityLabel = "Send"
        sendButton.accessibilityIdentifier = "chat.sendButton"
        sendButton.setContentHuggingPriority(.required, for: .horizontal)
        sendButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        sendButton.addTarget(self, action: #selector(sendButtonTapped), for: .touchUpInside)
    }

    private func configureRecordingStatusLabel() {
        recordingStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        recordingStatusLabel.font = .preferredFont(forTextStyle: .caption1)
        recordingStatusLabel.adjustsFontForContentSizeCategory = true
        recordingStatusLabel.textAlignment = .center
        recordingStatusLabel.textColor = .secondaryLabel
        recordingStatusLabel.isHidden = true
    }

    @objc private func voiceButtonTouchDown() {
        onVoiceTouchDown?()
    }

    @objc private func voiceButtonTouchDragExit() {
        onVoiceTouchDragExit?()
    }

    @objc private func voiceButtonTouchDragEnter() {
        onVoiceTouchDragEnter?()
    }

    @objc private func voiceButtonTouchUpInside() {
        onVoiceTouchUpInside?()
    }

    @objc private func voiceButtonTouchUpOutside() {
        onVoiceTouchUpOutside?()
    }

    @objc private func voiceButtonTouchCancel() {
        onVoiceTouchCancel?()
    }

    @objc private func sendButtonTapped() {
        sendCurrentText()
    }

    private func sendCurrentText() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        textView.text = ""
        renderTextViewPlaceholder()
        renderSendButtonState()
        updateTextViewHeight(animated: true)
        onTextChanged?("")
        onSend?(trimmedText)
    }

    private func renderReturnMode() {
        textView.returnKeyType = isReturnKeySending ? .send : .default
        moreButton.menu = makeMoreMenu()
        moreButton.accessibilityValue = isReturnKeySending ? "Return Sends On" : "Return Sends Off"
    }

    private func renderSendButtonState() {
        let enabled = canSendText && textView.isEditable
        sendButton.isEnabled = enabled

        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "arrow.up")
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = enabled
            ? UIColor.systemBlue
            : UIColor.systemGray4.withAlphaComponent(0.86)
        sendButton.configuration = configuration
    }

    private func renderTextViewPlaceholder() {
        textViewPlaceholderLabel.isHidden = !text.isEmpty
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
    func textViewDidChange(_ textView: UITextView) {
        renderTextViewPlaceholder()
        renderSendButtonState()
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

        sendCurrentText()
        return false
    }
}
