//
//  ChatViewController.swift
//  AppleIM
//

import Combine
import AVKit
import UIKit

private let chatSection = "messages"

@MainActor
final class ChatViewController: UIViewController {
    private let viewModel: ChatViewModel
    private var cancellables = Set<AnyCancellable>()
    private var dataSource: UICollectionViewDiffableDataSource<String, String>?
    private var rowsByID: [String: ChatMessageRowState] = [:]
    private var lastRenderedRowIDs: [String] = []
    private var isVoiceTouchActive = false

    private let backgroundView = GradientBackgroundView()
    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: makeLayout()
    )
    private let emptyLabel = UILabel()
    private let inputBarView = ChatInputBarView()
    private lazy var photoLibraryInputView = makePhotoLibraryInputView()
    private let voiceRecorder = VoiceRecordingController()
    private let voicePlaybackController = VoicePlaybackController()
    private var pendingAttachmentPreviews: [ChatPendingAttachmentPreviewItem] = []
    private var pendingComposerMediaByID: [String: ChatComposerMedia] = [:]

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
        viewModel.flushDraft(inputBarView.text)
    }

    private func configureView() {
        view.backgroundColor = .systemGroupedBackground
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backgroundView)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.delegate = self
        collectionView.accessibilityIdentifier = "chat.collection"

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "No messages yet"
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true

        inputBarView.translatesAutoresizingMaskIntoConstraints = false
        configureInputBarCallbacks()

        view.addSubview(collectionView)
        view.addSubview(emptyLabel)
        view.addSubview(inputBarView)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: inputBarView.topAnchor, constant: -8),

            emptyLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),

            inputBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            inputBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            inputBarView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8)
        ])
    }

    private func configureInputBarCallbacks() {
        inputBarView.onTextChanged = { [weak self] text in
            self?.viewModel.saveDraft(text)
        }
        inputBarView.onSend = { [weak self] text in
            self?.sendComposer(text: text)
        }
        inputBarView.onPhotoTapped = { [weak self] in
            self?.showPhotoLibraryInput()
        }
        inputBarView.onAttachmentRemoved = { [weak self] id in
            self?.removePendingAttachment(id: id)
            self?.photoLibraryInputView.removeSelection(assetID: id)
        }
        inputBarView.onVoiceTouchDown = { [weak self] in
            self?.voiceButtonTouchDown()
        }
        inputBarView.onVoiceTouchDragExit = { [weak self] in
            self?.voiceButtonTouchDragExit()
        }
        inputBarView.onVoiceTouchDragEnter = { [weak self] in
            self?.voiceButtonTouchDragEnter()
        }
        inputBarView.onVoiceTouchUpInside = { [weak self] in
            self?.voiceButtonTouchUpInside()
        }
        inputBarView.onVoiceTouchUpOutside = { [weak self] in
            self?.voiceButtonTouchUpOutside()
        }
        inputBarView.onVoiceTouchCancel = { [weak self] in
            self?.voiceButtonTouchCancel()
        }
        inputBarView.onHeightWillChange = { [weak self] in
            self?.isNearBottom() ?? false
        }
        inputBarView.onHeightDidChange = { [weak self] shouldStickToBottom in
            guard shouldStickToBottom else { return }
            self?.scrollToBottom(animated: false)
        }
    }

    private func makePhotoLibraryInputView() -> ChatPhotoLibraryInputView {
        let inputView = ChatPhotoLibraryInputView(frame: .zero, inputViewStyle: .keyboard)

        inputView.onSelectionStarted = { [weak self] preview in
            self?.upsertPendingAttachmentPreview(
                ChatPendingAttachmentPreviewItem(
                    id: preview.id,
                    image: preview.image,
                    title: preview.title,
                    durationText: preview.durationText,
                    isVideo: preview.isVideo,
                    isLoading: true
                )
            )
        }
        inputView.onSelectionPrepared = { [weak self] preparedMedia in
            self?.pendingComposerMediaByID[preparedMedia.id] = preparedMedia.media
            self?.upsertPendingAttachmentPreview(
                ChatPendingAttachmentPreviewItem(
                    id: preparedMedia.id,
                    image: preparedMedia.preview.image,
                    title: preparedMedia.preview.title,
                    durationText: preparedMedia.preview.durationText,
                    isVideo: preparedMedia.preview.isVideo,
                    isLoading: false
                )
            )
        }
        inputView.onSelectionRemoved = { [weak self] id in
            self?.removePendingAttachment(id: id)
        }
        inputView.onSelectionFailed = { [weak self] id, message in
            self?.removePendingAttachment(id: id)
            self?.showTransientRecordingMessage(message)
        }
        inputView.onSelectionLimitReached = { [weak self] message in
            self?.showTransientRecordingMessage(message)
        }

        return inputView
    }

    private func showPhotoLibraryInput() {
        inputBarView.setPhotoLibraryInputView(photoLibraryInputView)
        photoLibraryInputView.refreshAuthorization()
        inputBarView.showPhotoLibraryInput()
    }

    private func sendComposer(text: String) {
        let media = pendingAttachmentPreviews.compactMap { pendingComposerMediaByID[$0.id] }
        pendingAttachmentPreviews.removeAll()
        pendingComposerMediaByID.removeAll()
        inputBarView.clearPendingAttachmentPreviews(animated: true)
        photoLibraryInputView.clearSelection()
        viewModel.sendComposer(media: media, text: text)
    }

    private func upsertPendingAttachmentPreview(_ item: ChatPendingAttachmentPreviewItem) {
        if let index = pendingAttachmentPreviews.firstIndex(where: { $0.id == item.id }) {
            pendingAttachmentPreviews[index] = item
        } else {
            pendingAttachmentPreviews.append(item)
        }
        inputBarView.setPendingAttachmentPreviews(pendingAttachmentPreviews, animated: true)
    }

    private func removePendingAttachment(id: String) {
        pendingAttachmentPreviews.removeAll { $0.id == id }
        pendingComposerMediaByID[id] = nil
        inputBarView.setPendingAttachmentPreviews(pendingAttachmentPreviews, animated: true)
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
                },
                onPlayVideo: { [weak self] row in
                    self?.handleVideoPlayback(row)
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

        if !inputBarView.isEditingText, inputBarView.text != state.draftText {
            inputBarView.setText(state.draftText, animated: false)
        }

        let previousRowsByID = rowsByID
        let previousRowIDs = lastRenderedRowIDs
        let previousContentHeight = collectionView.contentSize.height
        let previousContentOffsetY = collectionView.contentOffset.y
        let wasNearBottom = isNearBottom()
        let newRowIDs = state.rows.map { $0.id.rawValue }
        let isInitialMessageRender = previousRowIDs.isEmpty && !newRowIDs.isEmpty
        let isPrependingOlderMessages = previousRowIDs.first.map { newRowIDs.contains($0) } == true
            && newRowIDs.first != previousRowIDs.first
        let didAppendNewMessage = previousRowIDs.last.map { newRowIDs.contains($0) } == true
            && newRowIDs.last != previousRowIDs.last
        let changedRowIDs = state.rows.compactMap { row -> String? in
            let id = row.id.rawValue
            return previousRowsByID[id] == row ? nil : id
        }

        rowsByID = Dictionary(uniqueKeysWithValues: state.rows.map { ($0.id.rawValue, $0) })
        lastRenderedRowIDs = newRowIDs

        guard let dataSource else { return }

        let snapshot = makeIncrementalSnapshot(
            dataSource: dataSource,
            previousRowIDs: previousRowIDs,
            newRowIDs: newRowIDs,
            changedRowIDs: changedRowIDs
        )

        dataSource.apply(snapshot, animatingDifferences: !isInitialMessageRender) { [weak self] in
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

    private func makeIncrementalSnapshot(
        dataSource: UICollectionViewDiffableDataSource<String, String>,
        previousRowIDs: [String],
        newRowIDs: [String],
        changedRowIDs: [String]
    ) -> NSDiffableDataSourceSnapshot<String, String> {
        guard !previousRowIDs.isEmpty else {
            var snapshot = NSDiffableDataSourceSnapshot<String, String>()
            snapshot.appendSections([chatSection])
            snapshot.appendItems(newRowIDs, toSection: chatSection)
            return snapshot
        }

        let oldSet = Set(previousRowIDs)
        let newSet = Set(newRowIDs)
        let survivingOldIDs = previousRowIDs.filter { newSet.contains($0) }
        let survivingNewIDs = newRowIDs.filter { oldSet.contains($0) }

        guard survivingOldIDs == survivingNewIDs else {
            var snapshot = NSDiffableDataSourceSnapshot<String, String>()
            snapshot.appendSections([chatSection])
            snapshot.appendItems(newRowIDs, toSection: chatSection)
            return snapshot
        }

        var snapshot = dataSource.snapshot()
        if !snapshot.sectionIdentifiers.contains(chatSection) {
            snapshot.appendSections([chatSection])
        }

        let currentIDs = snapshot.itemIdentifiers
        let currentSet = Set(currentIDs)
        let removedIDs = currentIDs.filter { !newSet.contains($0) }
        if !removedIDs.isEmpty {
            snapshot.deleteItems(removedIDs)
        }

        let prefixIDs = Array(newRowIDs.prefix { !oldSet.contains($0) })
        let suffixIDs = Array(newRowIDs.reversed().prefix { !oldSet.contains($0) }.reversed())
        let insertedIDs = newRowIDs.filter { !currentSet.contains($0) }
        let edgeInsertedIDs = prefixIDs + suffixIDs

        guard insertedIDs == edgeInsertedIDs else {
            var snapshot = NSDiffableDataSourceSnapshot<String, String>()
            snapshot.appendSections([chatSection])
            snapshot.appendItems(newRowIDs, toSection: chatSection)
            return snapshot
        }

        if !prefixIDs.isEmpty {
            if let firstSurvivingID = survivingNewIDs.first {
                snapshot.insertItems(prefixIDs, beforeItem: firstSurvivingID)
            } else {
                snapshot.appendItems(prefixIDs, toSection: chatSection)
            }
        }

        if !suffixIDs.isEmpty {
            snapshot.appendItems(suffixIDs, toSection: chatSection)
        }

        let snapshotSet = Set(snapshot.itemIdentifiers)
        let reconfiguredIDs = changedRowIDs.filter { snapshotSet.contains($0) && currentSet.contains($0) }
        if !reconfiguredIDs.isEmpty {
            snapshot.reconfigureItems(reconfiguredIDs)
        }

        return snapshot
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

    private func renderVoiceRecordingState(_ state: VoiceRecordingState) {
        inputBarView.renderVoiceRecordingState(state)
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

    private func handleVideoPlayback(_ row: ChatMessageRowState) {
        guard row.isVideo else { return }
        guard let localPath = row.videoLocalPath, FileManager.default.fileExists(atPath: localPath) else {
            showTransientRecordingMessage("Video file unavailable")
            return
        }

        let playerViewController = AVPlayerViewController()
        playerViewController.player = AVPlayer(url: URL(fileURLWithPath: localPath))
        present(playerViewController, animated: true) {
            playerViewController.player?.play()
        }
    }

    private func showTransientRecordingMessage(_ message: String) {
        inputBarView.showTransientStatus(message)
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
        let videoDurationText = videoDurationMilliseconds.map { String($0) } ?? ""
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
            videoThumbnailPath ?? "",
            videoLocalPath ?? "",
            videoDurationText,
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
    private let bubbleView = ChatBubbleBackgroundView()
    private let stackView = UIStackView()
    private let thumbnailImageView = UIImageView()
    private let videoStackView = UIStackView()
    private let videoPlaybackButton = UIButton(type: .system)
    private let videoDurationLabel = UILabel()
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
    private var onPlayVideo: ((ChatMessageRowState) -> Void)?

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
        onPlayVideo = nil
        accessibilityIdentifier = nil
        accessibilityLabel = nil
        retryButton.accessibilityIdentifier = nil
    }

    func configure(
        row: ChatMessageRowState,
        onRetry: @escaping (MessageID) -> Void,
        onDelete: @escaping (MessageID) -> Void,
        onRevoke: @escaping (MessageID) -> Void,
        onPlayVoice: @escaping (ChatMessageRowState) -> Void,
        onPlayVideo: @escaping (ChatMessageRowState) -> Void
    ) {
        self.row = row
        retryMessageID = row.id
        self.onRetry = onRetry
        self.onDelete = onDelete
        self.onRevoke = onRevoke
        self.onPlayVoice = onPlayVoice
        self.onPlayVideo = onPlayVideo
        accessibilityIdentifier = "chat.messageCell.\(row.id.rawValue)"
        accessibilityLabel = Self.accessibilityLabel(for: row)

        let mediaTintColor: UIColor = row.isOutgoing && !row.isRevoked ? .white : .systemBlue
        videoStackView.isHidden = !row.isVideo
        videoPlaybackButton.tintColor = mediaTintColor
        videoPlaybackButton.accessibilityLabel = "Play Video"
        videoDurationLabel.text = Self.voiceDurationText(milliseconds: row.videoDurationMilliseconds ?? 0)
        videoDurationLabel.textColor = row.isOutgoing && !row.isRevoked ? .white : .label

        let voiceTintColor: UIColor = row.isOutgoing && !row.isRevoked ? .white : .systemBlue
        voiceStackView.isHidden = !row.isVoice
        voicePlaybackButton.setImage(UIImage(systemName: row.isVoicePlaying ? "pause.fill" : "play.fill"), for: .normal)
        voicePlaybackButton.tintColor = voiceTintColor
        voicePlaybackButton.accessibilityLabel = row.isVoicePlaying ? "Stop Voice" : "Play Voice"
        voiceDurationLabel.text = Self.voiceDurationText(milliseconds: row.voiceDurationMilliseconds ?? 0)
        voiceDurationLabel.textColor = row.isOutgoing && !row.isRevoked ? .white : .label
        voiceUnreadDotView.isHidden = !row.isVoiceUnplayed

        messageLabel.text = row.isImage ? "Image unavailable" : (row.isVideo ? "Video unavailable" : row.text)
        messageLabel.isHidden = row.isVoice || ((row.isImage || row.isVideo) && mediaThumbnailPath(for: row) != nil)
        thumbnailImageView.isHidden = !(row.isImage || row.isVideo)

        if let thumbnailPath = mediaThumbnailPath(for: row) {
            thumbnailImageView.image = UIImage(contentsOfFile: thumbnailPath)
            messageLabel.isHidden = thumbnailImageView.image != nil
        } else {
            thumbnailImageView.image = nil
        }

        let progressText = row.uploadProgress.map { "Uploading \(Int($0 * 100))%" }
        metadataLabel.text = [row.timeText, progressText ?? row.statusText].compactMap { $0 }.joined(separator: " · ")
        let bubbleStyle: ChatBubbleBackgroundView.Style = row.isRevoked ? .revoked : (row.isOutgoing ? .outgoing : .incoming)
        bubbleView.apply(style: bubbleStyle)
        messageLabel.textColor = row.isOutgoing && !row.isRevoked ? .white : .label
        metadataLabel.textColor = row.isOutgoing && !row.isRevoked ? .white.withAlphaComponent(0.75) : .secondaryLabel
        retryButton.isHidden = !row.canRetry
        retryButton.tintColor = row.isOutgoing ? .white : .systemBlue
        retryButton.accessibilityIdentifier = "chat.retryButton.\(row.id.rawValue)"

        leadingConstraint?.isActive = !row.isOutgoing
        trailingConstraint?.isActive = row.isOutgoing
    }

    private func configureView() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.isUserInteractionEnabled = true
        bubbleView.layer.cornerRadius = ChatBridgeDesignSystem.RadiusToken.messageBubble
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
        thumbnailImageView.layer.cornerRadius = ChatBridgeDesignSystem.RadiusToken.media

        voiceStackView.translatesAutoresizingMaskIntoConstraints = false
        voiceStackView.axis = .horizontal
        voiceStackView.alignment = .center
        voiceStackView.spacing = 8

        videoStackView.translatesAutoresizingMaskIntoConstraints = false
        videoStackView.axis = .horizontal
        videoStackView.alignment = .center
        videoStackView.spacing = 8

        videoPlaybackButton.translatesAutoresizingMaskIntoConstraints = false
        videoPlaybackButton.setImage(UIImage(systemName: "play.circle.fill"), for: .normal)
        videoPlaybackButton.addTarget(self, action: #selector(videoPlaybackButtonTapped), for: .touchUpInside)

        videoDurationLabel.font = .preferredFont(forTextStyle: .body)
        videoDurationLabel.adjustsFontForContentSizeCategory = true

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
        videoStackView.addArrangedSubview(videoPlaybackButton)
        videoStackView.addArrangedSubview(videoDurationLabel)
        voiceStackView.addArrangedSubview(voicePlaybackButton)
        voiceStackView.addArrangedSubview(voiceDurationLabel)
        voiceStackView.addArrangedSubview(voiceUnreadDotView)
        stackView.addArrangedSubview(thumbnailImageView)
        stackView.addArrangedSubview(videoStackView)
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
            videoPlaybackButton.widthAnchor.constraint(equalToConstant: 28),
            videoPlaybackButton.heightAnchor.constraint(equalToConstant: 28),
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

    @objc private func videoPlaybackButtonTapped() {
        guard let row else { return }
        onPlayVideo?(row)
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

    private static func accessibilityLabel(for row: ChatMessageRowState) -> String {
        let contentText = row.isVideo ? "Video" : (row.isImage ? "Image" : row.text)
        var parts = [contentText]

        if let statusText = row.statusText {
            parts.append(statusText)
        }

        if let uploadProgress = row.uploadProgress {
            parts.append("Uploading \(Int(uploadProgress * 100))%")
        }

        return parts.joined(separator: ", ")
    }

    private func mediaThumbnailPath(for row: ChatMessageRowState) -> String? {
        row.imageThumbnailPath ?? row.videoThumbnailPath
    }
}
