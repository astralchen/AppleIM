//
//  ChatViewController.swift
//  AppleIM
//

import Combine
import AVKit
import UIKit

/// 聊天消息 section 标识
private let chatSection = "messages"

/// 聊天页控制器
@MainActor
final class ChatViewController: UIViewController {
    /// 聊天页 ViewModel
    private let viewModel: ChatViewModel
    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()
    /// 消息列表 diffable 数据源
    private var dataSource: UICollectionViewDiffableDataSource<String, String>?
    /// 当前消息行缓存
    private var rowsByID: [String: ChatMessageRowState] = [:]
    /// 最近一次渲染的消息行 ID 顺序
    private var lastRenderedRowIDs: [String] = []
    /// 语音按钮触摸是否仍处于按下状态
    private var isVoiceTouchActive = false

    /// 渐变背景
    private let backgroundView = GradientBackgroundView()
    /// 消息 collection view
    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: makeLayout()
    )
    /// 空消息提示
    private let emptyLabel = UILabel()
    /// 聊天输入栏
    private let inputBarView = ChatInputBarView()
    /// 图片库键盘输入视图
    private lazy var photoLibraryInputView = makePhotoLibraryInputView()
    /// 语音录制控制器
    private let voiceRecorder = VoiceRecordingController()
    /// 语音播放控制器
    private let voicePlaybackController = VoicePlaybackController()
    /// 待发送附件预览
    private var pendingAttachmentPreviews: [ChatPendingAttachmentPreviewItem] = []
    /// 待发送媒体内容缓存
    private var pendingComposerMediaByID: [String: ChatComposerMedia] = [:]

    /// 初始化聊天页
    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    /// 禁用 storyboard 初始化
    required init?(coder: NSCoder) {
        fatalError("Storyboard initialization is not supported.")
    }

    /// 配置聊天页并加载首屏消息
    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        configureDataSource()
        configureVoiceRecorder()
        configureVoicePlayback()
        bindViewModel()
        viewModel.load()
    }

    /// 页面消失时停止播放、取消任务并保存草稿
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        voicePlaybackController.stop()
        viewModel.cancel()
        viewModel.flushDraft(inputBarView.text)
    }

    /// 创建聊天页视图层级和约束
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

    /// 绑定输入栏按钮和文本变化回调
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

    /// 创建并绑定图片库输入视图
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

    /// 展示图片库键盘输入视图
    private func showPhotoLibraryInput() {
        inputBarView.setPhotoLibraryInputView(photoLibraryInputView)
        photoLibraryInputView.refreshAuthorization()
        inputBarView.showPhotoLibraryInput()
    }

    /// 发送当前文本和待发送附件
    private func sendComposer(text: String) {
        let media = pendingAttachmentPreviews.compactMap { pendingComposerMediaByID[$0.id] }
        pendingAttachmentPreviews.removeAll()
        pendingComposerMediaByID.removeAll()
        inputBarView.clearPendingAttachmentPreviews(animated: true)
        photoLibraryInputView.clearSelection()
        viewModel.sendComposer(media: media, text: text)
    }

    /// 新增或更新待发送附件预览
    private func upsertPendingAttachmentPreview(_ item: ChatPendingAttachmentPreviewItem) {
        if let index = pendingAttachmentPreviews.firstIndex(where: { $0.id == item.id }) {
            pendingAttachmentPreviews[index] = item
        } else {
            pendingAttachmentPreviews.append(item)
        }
        inputBarView.setPendingAttachmentPreviews(pendingAttachmentPreviews, animated: true)
    }

    /// 移除待发送附件
    private func removePendingAttachment(id: String) {
        pendingAttachmentPreviews.removeAll { $0.id == id }
        pendingComposerMediaByID[id] = nil
        inputBarView.setPendingAttachmentPreviews(pendingAttachmentPreviews, animated: true)
    }

    /// 绑定语音录制状态和完成回调
    private func configureVoiceRecorder() {
        voiceRecorder.onStateChange = { [weak self] state in
            self?.renderVoiceRecordingState(state)
        }
        voiceRecorder.onCompletion = { [weak self] completion in
            self?.handleVoiceRecordingCompletion(completion)
        }
    }

    /// 绑定语音播放回调
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

    /// 配置消息列表数据源
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

    /// 绑定聊天状态变化
    private func bindViewModel() {
        viewModel.statePublisher
            .sink { [weak self] state in
                self?.render(state)
            }
            .store(in: &cancellables)
    }

    /// 根据聊天页状态刷新消息列表和输入栏
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

    /// 构造可增量更新的消息快照
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

    /// 创建聊天消息列表布局
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

    /// 语音按钮按下时开始录音
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

    /// 语音按钮拖出时进入取消态
    @objc private func voiceButtonTouchDragExit() {
        voiceRecorder.updateCanceling(true)
    }

    /// 语音按钮拖回时退出取消态
    @objc private func voiceButtonTouchDragEnter() {
        voiceRecorder.updateCanceling(false)
    }

    /// 语音按钮在内部松开时发送录音
    @objc private func voiceButtonTouchUpInside() {
        isVoiceTouchActive = false
        voiceRecorder.finishRecording(cancelled: false)
    }

    /// 语音按钮在外部松开时取消录音
    @objc private func voiceButtonTouchUpOutside() {
        isVoiceTouchActive = false
        voiceRecorder.finishRecording(cancelled: true)
    }

    /// 语音按钮触摸取消时取消录音
    @objc private func voiceButtonTouchCancel() {
        isVoiceTouchActive = false
        voiceRecorder.finishRecording(cancelled: true)
    }

    /// 将录音状态渲染到输入栏
    private func renderVoiceRecordingState(_ state: VoiceRecordingState) {
        inputBarView.renderVoiceRecordingState(state)
    }

    /// 处理录音完成结果
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

    /// 播放或停止语音消息
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

    /// 使用系统播放器播放本地视频消息
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

    /// 展示短暂输入栏状态提示
    private func showTransientRecordingMessage(_ message: String) {
        inputBarView.showTransientStatus(message)
    }

    /// 判断消息列表是否接近底部
    private func isNearBottom() -> Bool {
        let visibleHeight = collectionView.bounds.height - collectionView.adjustedContentInset.top - collectionView.adjustedContentInset.bottom
        let maxOffsetY = collectionView.contentSize.height - visibleHeight + collectionView.adjustedContentInset.bottom
        return collectionView.contentOffset.y >= maxOffsetY - 80
    }

    /// 滚动到最新消息
    private func scrollToBottom(animated: Bool) {
        guard !lastRenderedRowIDs.isEmpty else { return }
        let lastIndexPath = IndexPath(item: lastRenderedRowIDs.count - 1, section: 0)
        collectionView.scrollToItem(at: lastIndexPath, at: .bottom, animated: animated)
    }
}

/// 聊天消息列表滚动回调
extension ChatViewController: UICollectionViewDelegate {
    /// 滚动到顶部附近时加载更早消息
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let topThreshold = -scrollView.adjustedContentInset.top + 120

        if scrollView.contentOffset.y <= topThreshold {
            viewModel.loadOlderMessagesIfNeeded()
        }
    }
}

/// 消息行 diff 辅助
private extension ChatMessageRowState {
    /// 用于触发 cell reconfigure 的稳定差异标识
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
            senderAvatarURL ?? "",
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

/// 聊天消息单元格
private final class ChatMessageCell: UICollectionViewCell, UIContextMenuInteractionDelegate {
    /// 头像图片缓存
    private static let avatarImageCache = NSCache<NSString, UIImage>()

    /// 默认头像渐变背景
    private let avatarView = GradientBackgroundView()
    /// 头像图片
    private let avatarImageView = UIImageView()
    /// 头像占位文字
    private let avatarInitialLabel = UILabel()
    /// 消息气泡背景
    private let bubbleView = ChatBubbleBackgroundView()
    /// 气泡内容栈
    private let stackView = UIStackView()
    /// 图片或视频缩略图
    private let thumbnailImageView = UIImageView()
    /// 视频播放信息栈
    private let videoStackView = UIStackView()
    /// 视频播放按钮
    private let videoPlaybackButton = UIButton(type: .system)
    /// 视频时长标签
    private let videoDurationLabel = UILabel()
    /// 语音播放信息栈
    private let voiceStackView = UIStackView()
    /// 语音播放按钮
    private let voicePlaybackButton = UIButton(type: .system)
    /// 语音时长标签
    private let voiceDurationLabel = UILabel()
    /// 未播放语音红点
    private let voiceUnreadDotView = UIView()
    /// 文本消息标签
    private let messageLabel = UILabel()
    /// 时间、状态和上传进度标签
    private let metadataLabel = UILabel()
    /// 重试按钮
    private let retryButton = UIButton(type: .system)
    /// 收到消息头像左侧约束
    private var incomingAvatarLeadingConstraint: NSLayoutConstraint?
    /// 收到消息气泡左侧约束
    private var incomingBubbleLeadingConstraint: NSLayoutConstraint?
    /// 发出消息头像右侧约束
    private var outgoingAvatarTrailingConstraint: NSLayoutConstraint?
    /// 发出消息气泡右侧约束
    private var outgoingBubbleTrailingConstraint: NSLayoutConstraint?
    /// 当前头像加载任务
    private var avatarDataTask: URLSessionDataTask?
    /// 当前期望展示的头像 URL
    private var expectedAvatarURL: String?
    /// 当前绑定的消息行
    private var row: ChatMessageRowState?
    /// 当前可重试消息 ID
    private var retryMessageID: MessageID?
    /// 重试回调
    private var onRetry: ((MessageID) -> Void)?
    /// 删除回调
    private var onDelete: ((MessageID) -> Void)?
    /// 撤回回调
    private var onRevoke: ((MessageID) -> Void)?
    /// 语音播放回调
    private var onPlayVoice: ((ChatMessageRowState) -> Void)?
    /// 视频播放回调
    private var onPlayVideo: ((ChatMessageRowState) -> Void)?

    /// 初始化消息单元格
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    /// 从 storyboard/xib 初始化消息单元格
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    /// 复用前重置状态、回调和头像加载
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
        avatarDataTask?.cancel()
        avatarDataTask = nil
        expectedAvatarURL = nil
        avatarImageView.image = nil
        avatarImageView.isHidden = true
    }

    /// 根据消息行配置气泡、媒体、状态和交互
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
        configureAvatar(for: row)

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

        incomingAvatarLeadingConstraint?.isActive = !row.isOutgoing
        incomingBubbleLeadingConstraint?.isActive = !row.isOutgoing
        outgoingAvatarTrailingConstraint?.isActive = row.isOutgoing
        outgoingBubbleTrailingConstraint?.isActive = row.isOutgoing
    }

    /// 配置单元格视图层级、样式和约束
    private func configureView() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.setColors(ChatBridgeDesignSystem.GradientToken.playfulAvatar)
        avatarView.layer.cornerRadius = 18
        avatarView.layer.masksToBounds = true
        avatarView.isAccessibilityElement = false

        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.isHidden = true
        avatarImageView.isAccessibilityElement = false

        avatarInitialLabel.translatesAutoresizingMaskIntoConstraints = false
        avatarInitialLabel.font = .preferredFont(forTextStyle: .caption1)
        avatarInitialLabel.adjustsFontForContentSizeCategory = true
        avatarInitialLabel.textColor = .white
        avatarInitialLabel.textAlignment = .center
        avatarInitialLabel.isAccessibilityElement = false

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

        contentView.addSubview(avatarView)
        avatarView.addSubview(avatarInitialLabel)
        avatarView.addSubview(avatarImageView)
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

        incomingAvatarLeadingConstraint = avatarView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor)
        incomingBubbleLeadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 8)
        outgoingAvatarTrailingConstraint = avatarView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor)
        outgoingBubbleTrailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: avatarView.leadingAnchor, constant: -8)

        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: bubbleView.topAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 36),
            avatarView.heightAnchor.constraint(equalToConstant: 36),

            avatarInitialLabel.topAnchor.constraint(equalTo: avatarView.topAnchor),
            avatarInitialLabel.leadingAnchor.constraint(equalTo: avatarView.leadingAnchor),
            avatarInitialLabel.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor),
            avatarInitialLabel.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor),

            avatarImageView.topAnchor.constraint(equalTo: avatarView.topAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: avatarView.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor),

            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.64),

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

    /// 配置发送者头像
    private func configureAvatar(for row: ChatMessageRowState) {
        avatarDataTask?.cancel()
        avatarDataTask = nil
        expectedAvatarURL = row.senderAvatarURL
        avatarInitialLabel.text = row.isOutgoing ? "Me" : "C"
        avatarImageView.image = nil
        avatarImageView.isHidden = true

        guard let avatarURL = row.senderAvatarURL?.trimmingCharacters(in: .whitespacesAndNewlines), !avatarURL.isEmpty else {
            return
        }

        let cacheKey = avatarURL as NSString
        if let cachedImage = Self.avatarImageCache.object(forKey: cacheKey) {
            avatarImageView.image = cachedImage
            avatarImageView.isHidden = false
            return
        }

        if let localImage = Self.localAvatarImage(from: avatarURL) {
            Self.avatarImageCache.setObject(localImage, forKey: cacheKey)
            avatarImageView.image = localImage
            avatarImageView.isHidden = false
            return
        }

        guard let url = URL(string: avatarURL), ["http", "https"].contains(url.scheme?.lowercased()) else {
            return
        }

        avatarDataTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else {
                return
            }

            Self.avatarImageCache.setObject(image, forKey: cacheKey)

            DispatchQueue.main.async {
                guard let self, self.expectedAvatarURL == avatarURL else {
                    return
                }

                self.avatarImageView.image = image
                self.avatarImageView.isHidden = false
            }
        }
        avatarDataTask?.resume()
    }

    /// 从本地路径或 file URL 加载头像
    private static func localAvatarImage(from value: String) -> UIImage? {
        if let url = URL(string: value), url.isFileURL {
            return UIImage(contentsOfFile: url.path)
        }

        guard !value.hasPrefix("http://"), !value.hasPrefix("https://") else {
            return nil
        }

        return UIImage(contentsOfFile: value)
    }

    /// 点击语音播放按钮
    @objc private func voicePlaybackButtonTapped() {
        guard let row else { return }
        onPlayVoice?(row)
    }

    /// 点击视频播放按钮
    @objc private func videoPlaybackButtonTapped() {
        guard let row else { return }
        onPlayVideo?(row)
    }

    /// 点击重试按钮
    @objc private func retryButtonTapped() {
        guard let retryMessageID else { return }
        onRetry?(retryMessageID)
    }

    /// 创建消息气泡上下文菜单
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

    /// 格式化语音或视频时长文本
    private static func voiceDurationText(milliseconds: Int) -> String {
        let seconds = max(1, Int((Double(milliseconds) / 1_000.0).rounded()))
        return "\(seconds)s"
    }

    /// 生成消息无障碍描述
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

    /// 获取图片或视频缩略图路径
    private func mediaThumbnailPath(for row: ChatMessageRowState) -> String? {
        row.imageThumbnailPath ?? row.videoThumbnailPath
    }
}
