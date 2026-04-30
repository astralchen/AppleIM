//
//  ChatViewController.swift
//  AppleIM
//

import Combine
import PhotosUI
import UIKit
import UniformTypeIdentifiers

private let chatSection = "messages"

@MainActor
final class ChatViewController: UIViewController {
    private let viewModel: ChatViewModel
    private var cancellables = Set<AnyCancellable>()
    private var dataSource: UICollectionViewDiffableDataSource<String, String>?
    private var rowsByID: [String: ChatMessageRowState] = [:]
    private var lastRenderedRowIDs: [String] = []
    private var isVoiceTouchActive = false

    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: makeLayout()
    )
    private let emptyLabel = UILabel()
    private let inputContainerView = UIView()
    private let recordingStatusLabel = UILabel()
    private let inputStackView = UIStackView()
    private let photoButton = UIButton(type: .system)
    private let voiceButton = UIButton(type: .system)
    private let textField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let voiceRecorder = VoiceRecordingController()
    private let voicePlaybackController = VoicePlaybackController()

    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Storyboard initialization is not supported.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        configureDataSource()
        configureVoiceRecorder()
        configureVoicePlayback()
        bindViewModel()
        viewModel.load()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        voicePlaybackController.stop()
        viewModel.cancel()
        viewModel.flushDraft(textField.text ?? "")
    }

    private func configureView() {
        view.backgroundColor = .systemGroupedBackground

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.delegate = self

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "No messages yet"
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true

        inputContainerView.translatesAutoresizingMaskIntoConstraints = false
        inputContainerView.backgroundColor = .secondarySystemGroupedBackground
        inputContainerView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 10,
            leading: 16,
            bottom: 10,
            trailing: 16
        )

        inputStackView.translatesAutoresizingMaskIntoConstraints = false
        inputStackView.axis = .horizontal
        inputStackView.alignment = .center
        inputStackView.spacing = 12
        inputStackView.distribution = .fill

        photoButton.translatesAutoresizingMaskIntoConstraints = false
        var photoButtonConfiguration = UIButton.Configuration.plain()
        photoButtonConfiguration.image = UIImage(systemName: "photo")
        photoButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(
            top: 8,
            leading: 8,
            bottom: 8,
            trailing: 8
        )
        photoButton.configuration = photoButtonConfiguration
        photoButton.accessibilityLabel = "Choose Photo"
        photoButton.setContentHuggingPriority(.required, for: .horizontal)
        photoButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        photoButton.addTarget(self, action: #selector(photoButtonTapped), for: .touchUpInside)

        voiceButton.translatesAutoresizingMaskIntoConstraints = false
        var voiceButtonConfiguration = UIButton.Configuration.plain()
        voiceButtonConfiguration.image = UIImage(systemName: "mic")
        voiceButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(
            top: 8,
            leading: 8,
            bottom: 8,
            trailing: 8
        )
        voiceButton.configuration = voiceButtonConfiguration
        voiceButton.accessibilityLabel = "Hold to Record Voice"
        voiceButton.setContentHuggingPriority(.required, for: .horizontal)
        voiceButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        voiceButton.addTarget(self, action: #selector(voiceButtonTouchDown), for: .touchDown)
        voiceButton.addTarget(self, action: #selector(voiceButtonTouchDragExit), for: .touchDragExit)
        voiceButton.addTarget(self, action: #selector(voiceButtonTouchDragEnter), for: .touchDragEnter)
        voiceButton.addTarget(self, action: #selector(voiceButtonTouchUpInside), for: .touchUpInside)
        voiceButton.addTarget(self, action: #selector(voiceButtonTouchUpOutside), for: .touchUpOutside)
        voiceButton.addTarget(self, action: #selector(voiceButtonTouchCancel), for: .touchCancel)

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.borderStyle = .roundedRect
        textField.placeholder = "Message"
        textField.returnKeyType = .send
        textField.delegate = self
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.addTarget(self, action: #selector(textFieldEditingChanged), for: .editingChanged)

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        var sendButtonConfiguration = UIButton.Configuration.plain()
        sendButtonConfiguration.title = "Send"
        sendButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(
            top: 8,
            leading: 10,
            bottom: 8,
            trailing: 10
        )
        sendButtonConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .preferredFont(forTextStyle: .headline)
            return attributes
        }
        sendButton.configuration = sendButtonConfiguration
        sendButton.setContentHuggingPriority(.required, for: .horizontal)
        sendButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        sendButton.addTarget(self, action: #selector(sendButtonTapped), for: .touchUpInside)

        recordingStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        recordingStatusLabel.font = .preferredFont(forTextStyle: .caption1)
        recordingStatusLabel.adjustsFontForContentSizeCategory = true
        recordingStatusLabel.textAlignment = .center
        recordingStatusLabel.textColor = .secondaryLabel
        recordingStatusLabel.isHidden = true

        view.addSubview(collectionView)
        view.addSubview(emptyLabel)
        view.addSubview(inputContainerView)
        inputContainerView.addSubview(recordingStatusLabel)
        inputContainerView.addSubview(inputStackView)
        inputStackView.addArrangedSubview(photoButton)
        inputStackView.addArrangedSubview(voiceButton)
        inputStackView.addArrangedSubview(textField)
        inputStackView.addArrangedSubview(sendButton)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: inputContainerView.topAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),

            inputContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputContainerView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            recordingStatusLabel.leadingAnchor.constraint(equalTo: inputContainerView.layoutMarginsGuide.leadingAnchor),
            recordingStatusLabel.trailingAnchor.constraint(equalTo: inputContainerView.layoutMarginsGuide.trailingAnchor),
            recordingStatusLabel.topAnchor.constraint(equalTo: inputContainerView.layoutMarginsGuide.topAnchor),

            inputStackView.leadingAnchor.constraint(equalTo: inputContainerView.layoutMarginsGuide.leadingAnchor),
            inputStackView.trailingAnchor.constraint(equalTo: inputContainerView.layoutMarginsGuide.trailingAnchor),
            inputStackView.topAnchor.constraint(equalTo: recordingStatusLabel.bottomAnchor, constant: 4),
            inputStackView.bottomAnchor.constraint(equalTo: inputContainerView.layoutMarginsGuide.bottomAnchor),

            photoButton.widthAnchor.constraint(equalToConstant: 44),
            photoButton.heightAnchor.constraint(equalToConstant: 44),
            voiceButton.widthAnchor.constraint(equalToConstant: 44),
            voiceButton.heightAnchor.constraint(equalToConstant: 44),
            textField.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            sendButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            sendButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 64)
        ])
    }

    private func configureVoiceRecorder() {
        voiceRecorder.onStateChange = { [weak self] state in
            self?.renderVoiceRecordingState(state)
        }
        voiceRecorder.onCompletion = { [weak self] completion in
            self?.handleVoiceRecordingCompletion(completion)
        }
    }

    private func configureVoicePlayback() {
        voicePlaybackController.onStarted = { [weak self] messageID in
            self?.viewModel.voicePlaybackStarted(messageID: messageID)
        }
        voicePlaybackController.onStopped = { [weak self] messageID in
            self?.viewModel.voicePlaybackStopped(messageID: messageID)
        }
        voicePlaybackController.onFailed = { [weak self] messageID in
            self?.viewModel.voicePlaybackStopped(messageID: messageID)
            self?.showTransientRecordingMessage("Unable to play voice")
        }
    }

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<ChatMessageCell, String> { [weak self] cell, _, rowID in
            guard let self, let row = self.rowsByID[rowID] else { return }
            cell.configure(
                row: row,
                onRetry: { [weak self] messageID in
                    self?.viewModel.resend(messageID: messageID)
                },
                onDelete: { [weak self] messageID in
                    self?.viewModel.delete(messageID: messageID)
                },
                onRevoke: { [weak self] messageID in
                    self?.viewModel.revoke(messageID: messageID)
                },
                onPlayVoice: { [weak self] row in
                    self?.handleVoicePlayback(row)
                }
            )
        }

        dataSource = UICollectionViewDiffableDataSource<String, String>(
            collectionView: collectionView
        ) { (collectionView: UICollectionView, indexPath: IndexPath, rowID: String) in
            collectionView.dequeueConfiguredReusableCell(
                using: cellRegistration,
                for: indexPath,
                item: rowID
            )
        }

        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        snapshot.appendSections([chatSection])
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    private func bindViewModel() {
        viewModel.statePublisher
            .sink { [weak self] state in
                self?.render(state)
            }
            .store(in: &cancellables)
    }

    private func render(_ state: ChatViewState) {
        title = state.title
        emptyLabel.text = state.emptyMessage
        emptyLabel.isHidden = !state.isEmpty || state.phase == .loading

        if !textField.isFirstResponder, textField.text != state.draftText {
            textField.text = state.draftText
        }

        let previousRowIDs = lastRenderedRowIDs
        let previousContentHeight = collectionView.contentSize.height
        let previousContentOffsetY = collectionView.contentOffset.y
        let wasNearBottom = isNearBottom()
        let newRowIDs = state.rows.map(\.diffIdentifier)
        let isInitialMessageRender = previousRowIDs.isEmpty && !newRowIDs.isEmpty
        let isPrependingOlderMessages = previousRowIDs.first.map { newRowIDs.contains($0) } == true
            && newRowIDs.first != previousRowIDs.first
        let didAppendNewMessage = previousRowIDs.last.map { newRowIDs.contains($0) } == true
            && newRowIDs.last != previousRowIDs.last

        rowsByID = Dictionary(uniqueKeysWithValues: state.rows.map { ($0.diffIdentifier, $0) })
        lastRenderedRowIDs = newRowIDs

        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        snapshot.appendSections([chatSection])
        snapshot.appendItems(newRowIDs, toSection: chatSection)
        dataSource?.apply(snapshot, animatingDifferences: true) { [weak self] in
            guard let self else { return }

            self.collectionView.layoutIfNeeded()

            if isPrependingOlderMessages {
                let heightDelta = self.collectionView.contentSize.height - previousContentHeight
                let adjustedOffsetY = previousContentOffsetY + heightDelta
                self.collectionView.setContentOffset(
                    CGPoint(x: self.collectionView.contentOffset.x, y: adjustedOffsetY),
                    animated: false
                )
            } else if isInitialMessageRender || didAppendNewMessage || wasNearBottom {
                self.scrollToBottom(animated: !isInitialMessageRender)
            }
        }
    }

    private func makeLayout() -> UICollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(72)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)

        return UICollectionViewCompositionalLayout(section: section)
    }

    @objc private func sendButtonTapped() {
        sendCurrentText()
    }

    @objc private func photoButtonTapped() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func voiceButtonTouchDown() {
        isVoiceTouchActive = true
        Task { [weak self] in
            await self?.voiceRecorder.beginRecording()
            guard let self, !self.isVoiceTouchActive, self.voiceRecorder.isRecording else {
                return
            }
            self.voiceRecorder.finishRecording(cancelled: true)
        }
    }

    @objc private func voiceButtonTouchDragExit() {
        voiceRecorder.updateCanceling(true)
    }

    @objc private func voiceButtonTouchDragEnter() {
        voiceRecorder.updateCanceling(false)
    }

    @objc private func voiceButtonTouchUpInside() {
        isVoiceTouchActive = false
        voiceRecorder.finishRecording(cancelled: false)
    }

    @objc private func voiceButtonTouchUpOutside() {
        isVoiceTouchActive = false
        voiceRecorder.finishRecording(cancelled: true)
    }

    @objc private func voiceButtonTouchCancel() {
        isVoiceTouchActive = false
        voiceRecorder.finishRecording(cancelled: true)
    }

    @objc private func textFieldEditingChanged() {
        viewModel.saveDraft(textField.text ?? "")
    }

    private func sendCurrentText() {
        let text = textField.text ?? ""
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        textField.text = nil
        viewModel.saveDraft("")
        viewModel.sendText(trimmedText)
    }

    private func renderVoiceRecordingState(_ state: VoiceRecordingState) {
        recordingStatusLabel.isHidden = !state.isRecording && state.hintText == "Hold to talk"
        recordingStatusLabel.text = state.isRecording
            ? "\(state.hintText) · \(voiceDurationText(milliseconds: state.elapsedMilliseconds))"
            : state.hintText
        recordingStatusLabel.textColor = state.isCanceling ? .systemRed : .secondaryLabel

        let microphoneImageName = state.isRecording ? "mic.fill" : "mic"
        voiceButton.configuration?.image = UIImage(systemName: microphoneImageName)
        voiceButton.tintColor = state.isCanceling ? .systemRed : .systemBlue
        textField.isEnabled = !state.isRecording
        sendButton.isEnabled = !state.isRecording
        photoButton.isEnabled = !state.isRecording
    }

    private func handleVoiceRecordingCompletion(_ completion: VoiceRecordingCompletion) {
        switch completion {
        case let .send(recording):
            viewModel.sendVoice(recording: recording)
        case .tooShort:
            showTransientRecordingMessage("Voice too short")
        case .permissionDenied:
            showTransientRecordingMessage("Microphone access denied")
        case .failed:
            showTransientRecordingMessage("Unable to record")
        case .cancelled:
            showTransientRecordingMessage("Voice cancelled")
        }
    }

    private func handleVoicePlayback(_ row: ChatMessageRowState) {
        guard row.isVoice else { return }

        if row.isVoicePlaying {
            voicePlaybackController.stop()
            return
        }

        guard let localPath = row.voiceLocalPath else {
            showTransientRecordingMessage("Voice file unavailable")
            return
        }

        voicePlaybackController.play(messageID: row.id, fileURL: URL(fileURLWithPath: localPath))
    }

    private func showTransientRecordingMessage(_ message: String) {
        recordingStatusLabel.isHidden = false
        recordingStatusLabel.text = message
        recordingStatusLabel.textColor = .secondaryLabel

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            self?.recordingStatusLabel.isHidden = true
        }
    }

    private func voiceDurationText(milliseconds: Int) -> String {
        let seconds = max(0, milliseconds / 1_000)
        let tenths = max(0, (milliseconds % 1_000) / 100)
        return "\(seconds).\(tenths)s"
    }

    private func isNearBottom() -> Bool {
        let visibleHeight = collectionView.bounds.height - collectionView.adjustedContentInset.top - collectionView.adjustedContentInset.bottom
        let maxOffsetY = collectionView.contentSize.height - visibleHeight + collectionView.adjustedContentInset.bottom
        return collectionView.contentOffset.y >= maxOffsetY - 80
    }

    private func scrollToBottom(animated: Bool) {
        guard !lastRenderedRowIDs.isEmpty else { return }
        let lastIndexPath = IndexPath(item: lastRenderedRowIDs.count - 1, section: 0)
        collectionView.scrollToItem(at: lastIndexPath, at: .bottom, animated: animated)
    }
}

extension ChatViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendCurrentText()
        return false
    }
}

extension ChatViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard let provider = results.first?.itemProvider else {
            return
        }

        let typeIdentifier = provider.registeredTypeIdentifiers.first { identifier in
            UTType(identifier)?.conforms(to: .image) == true
        } ?? UTType.image.identifier
        let fileExtension = UTType(typeIdentifier)?.preferredFilenameExtension

        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] data, _ in
            guard let data else { return }

            Task { @MainActor in
                self?.viewModel.sendImage(data: data, preferredFileExtension: fileExtension)
            }
        }
    }
}

extension ChatViewController: UICollectionViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let topThreshold = -scrollView.adjustedContentInset.top + 120

        if scrollView.contentOffset.y <= topThreshold {
            viewModel.loadOlderMessagesIfNeeded()
        }
    }
}

private extension ChatMessageRowState {
    var diffIdentifier: String {
        let voiceDurationText = voiceDurationMilliseconds.map { String($0) } ?? ""
        let progressText = uploadProgress.map { String(Int($0 * 100)) } ?? ""
        let retryText = canRetry ? "retry" : "no-retry"
        let revokeText = canRevoke ? "revoke" : "no-revoke"
        let revokeStatusText = isRevoked ? "revoked" : "normal"
        let voiceUnreadText = isVoiceUnplayed ? "voice-unplayed" : "voice-played"
        let voicePlayingText = isVoicePlaying ? "voice-playing" : "voice-stopped"

        return [
            id.rawValue,
            text,
            imageThumbnailPath ?? "",
            voiceLocalPath ?? "",
            voiceDurationText,
            statusText ?? "",
            progressText,
            retryText,
            revokeText,
            revokeStatusText,
            voiceUnreadText,
            voicePlayingText
        ].joined(separator: "|")
    }
}

private final class ChatMessageCell: UICollectionViewCell, UIContextMenuInteractionDelegate {
    private let bubbleView = UIView()
    private let stackView = UIStackView()
    private let thumbnailImageView = UIImageView()
    private let voiceStackView = UIStackView()
    private let voicePlaybackButton = UIButton(type: .system)
    private let voiceDurationLabel = UILabel()
    private let voiceUnreadDotView = UIView()
    private let messageLabel = UILabel()
    private let metadataLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    private var row: ChatMessageRowState?
    private var retryMessageID: MessageID?
    private var onRetry: ((MessageID) -> Void)?
    private var onDelete: ((MessageID) -> Void)?
    private var onRevoke: ((MessageID) -> Void)?
    private var onPlayVoice: ((ChatMessageRowState) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        row = nil
        retryMessageID = nil
        onRetry = nil
        onDelete = nil
        onRevoke = nil
        onPlayVoice = nil
    }

    func configure(
        row: ChatMessageRowState,
        onRetry: @escaping (MessageID) -> Void,
        onDelete: @escaping (MessageID) -> Void,
        onRevoke: @escaping (MessageID) -> Void,
        onPlayVoice: @escaping (ChatMessageRowState) -> Void
    ) {
        self.row = row
        retryMessageID = row.id
        self.onRetry = onRetry
        self.onDelete = onDelete
        self.onRevoke = onRevoke
        self.onPlayVoice = onPlayVoice

        let voiceTintColor: UIColor = row.isOutgoing && !row.isRevoked ? .white : .systemBlue
        voiceStackView.isHidden = !row.isVoice
        voicePlaybackButton.setImage(UIImage(systemName: row.isVoicePlaying ? "pause.fill" : "play.fill"), for: .normal)
        voicePlaybackButton.tintColor = voiceTintColor
        voicePlaybackButton.accessibilityLabel = row.isVoicePlaying ? "Stop Voice" : "Play Voice"
        voiceDurationLabel.text = Self.voiceDurationText(milliseconds: row.voiceDurationMilliseconds ?? 0)
        voiceDurationLabel.textColor = row.isOutgoing && !row.isRevoked ? .white : .label
        voiceUnreadDotView.isHidden = !row.isVoiceUnplayed

        messageLabel.text = row.isImage ? "Image unavailable" : row.text
        messageLabel.isHidden = row.isVoice || (row.isImage && row.imageThumbnailPath != nil)
        thumbnailImageView.isHidden = !row.isImage

        if let thumbnailPath = row.imageThumbnailPath {
            thumbnailImageView.image = UIImage(contentsOfFile: thumbnailPath)
            messageLabel.isHidden = thumbnailImageView.image != nil
        } else {
            thumbnailImageView.image = nil
        }

        let progressText = row.uploadProgress.map { "Uploading \(Int($0 * 100))%" }
        metadataLabel.text = [row.timeText, progressText ?? row.statusText].compactMap { $0 }.joined(separator: " · ")
        bubbleView.backgroundColor = row.isRevoked ? .tertiarySystemGroupedBackground : (row.isOutgoing ? .systemBlue : .secondarySystemGroupedBackground)
        messageLabel.textColor = row.isOutgoing && !row.isRevoked ? .white : .label
        metadataLabel.textColor = row.isOutgoing && !row.isRevoked ? .white.withAlphaComponent(0.75) : .secondaryLabel
        retryButton.isHidden = !row.canRetry
        retryButton.tintColor = row.isOutgoing ? .white : .systemBlue

        leadingConstraint?.isActive = !row.isOutgoing
        trailingConstraint?.isActive = row.isOutgoing
    }

    private func configureView() {
        contentView.backgroundColor = .systemGroupedBackground

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.isUserInteractionEnabled = true
        bubbleView.layer.cornerRadius = 16
        bubbleView.layer.masksToBounds = true
        // 把菜单交互绑定到气泡本身，避免 UICollectionView 的 item 级菜单
        // 把整条 cell 当作 preview 源，从而生成灰色背景残影。
        bubbleView.addInteraction(UIContextMenuInteraction(delegate: self))

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 4

        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailImageView.contentMode = .scaleAspectFill
        thumbnailImageView.clipsToBounds = true
        thumbnailImageView.layer.cornerRadius = 10

        voiceStackView.translatesAutoresizingMaskIntoConstraints = false
        voiceStackView.axis = .horizontal
        voiceStackView.alignment = .center
        voiceStackView.spacing = 8

        voicePlaybackButton.translatesAutoresizingMaskIntoConstraints = false
        voicePlaybackButton.addTarget(self, action: #selector(voicePlaybackButtonTapped), for: .touchUpInside)

        voiceDurationLabel.font = .preferredFont(forTextStyle: .body)
        voiceDurationLabel.adjustsFontForContentSizeCategory = true

        voiceUnreadDotView.translatesAutoresizingMaskIntoConstraints = false
        voiceUnreadDotView.backgroundColor = .systemRed
        voiceUnreadDotView.layer.cornerRadius = 4
        voiceUnreadDotView.isHidden = true

        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0

        metadataLabel.font = .preferredFont(forTextStyle: .caption2)
        metadataLabel.adjustsFontForContentSizeCategory = true
        metadataLabel.numberOfLines = 1

        retryButton.setTitle("Retry", for: .normal)
        retryButton.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        retryButton.contentHorizontalAlignment = .leading
        retryButton.addTarget(self, action: #selector(retryButtonTapped), for: .touchUpInside)

        contentView.addSubview(bubbleView)
        bubbleView.addSubview(stackView)
        voiceStackView.addArrangedSubview(voicePlaybackButton)
        voiceStackView.addArrangedSubview(voiceDurationLabel)
        voiceStackView.addArrangedSubview(voiceUnreadDotView)
        stackView.addArrangedSubview(thumbnailImageView)
        stackView.addArrangedSubview(voiceStackView)
        stackView.addArrangedSubview(messageLabel)
        stackView.addArrangedSubview(metadataLabel)
        stackView.addArrangedSubview(retryButton)

        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.72),

            stackView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            stackView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            stackView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8),

            thumbnailImageView.widthAnchor.constraint(equalToConstant: 180),
            thumbnailImageView.heightAnchor.constraint(equalToConstant: 180),
            voicePlaybackButton.widthAnchor.constraint(equalToConstant: 28),
            voicePlaybackButton.heightAnchor.constraint(equalToConstant: 28),
            voiceUnreadDotView.widthAnchor.constraint(equalToConstant: 8),
            voiceUnreadDotView.heightAnchor.constraint(equalToConstant: 8)
        ])
    }

    @objc private func voicePlaybackButtonTapped() {
        guard let row else { return }
        onPlayVoice?(row)
    }

    @objc private func retryButtonTapped() {
        guard let retryMessageID else { return }
        onRetry?(retryMessageID)
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let row, row.canDelete || row.canRevoke else {
            return nil
        }

        return UIContextMenuConfiguration(identifier: row.diffIdentifier as NSString, previewProvider: nil) { [weak self] _ in
            var actions: [UIAction] = []

            if row.canRevoke {
                actions.append(
                    UIAction(title: "Revoke", image: UIImage(systemName: "arrow.uturn.backward")) { _ in
                        self?.onRevoke?(row.id)
                    }
                )
            }

            if row.canDelete {
                actions.append(
                    UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                        self?.onDelete?(row.id)
                    }
                )
            }

            return UIMenu(children: actions)
        }
    }

    private static func voiceDurationText(milliseconds: Int) -> String {
        let seconds = max(1, Int((Double(milliseconds) / 1_000.0).rounded()))
        return "\(seconds)s"
    }
}
