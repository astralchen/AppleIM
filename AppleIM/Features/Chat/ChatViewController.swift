//
//  ChatViewController.swift
//  AppleIM
//

import Combine
import AVKit
import UIKit

/// 聊天消息 section 标识
private let chatSection = "messages"
/// 待发送语音预览播放使用的本地占位 ID，避免影响消息列表播放态
private let pendingVoicePreviewMessageID = MessageID(rawValue: "__pending_voice_preview__")

/// 串行化 diffable data source 快照 apply，避免 UIKit apply 队列重入。
@MainActor
final class ChatSnapshotRenderCoordinator<State> {
    private typealias Render = (_ state: State, _ completion: @escaping () -> Void) -> Void

    private struct PendingApply {
        let state: State
        let render: Render
    }

    private var pendingApply: PendingApply?
    private(set) var isApplying = false

    func apply(
        _ state: State,
        render: @escaping (_ state: State, _ completion: @escaping () -> Void) -> Void
    ) {
        if isApplying {
            pendingApply = PendingApply(state: state, render: render)
            return
        }

        isApplying = true
        render(state) { [weak self] in
            self?.complete()
        }
    }

    private func complete() {
        guard let pendingApply else {
            isApplying = false
            return
        }

        self.pendingApply = nil
        pendingApply.render(pendingApply.state) { [weak self] in
            self?.complete()
        }
    }
}

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
    /// 消息列表快照 apply 门控，防止 diffable data source 重入。
    private let snapshotRenderCoordinator = ChatSnapshotRenderCoordinator<ChatViewState>()
    /// 聊天 UI 耗时日志。
    private let logger = AppLogger(category: .chat)
    /// 语音按钮触摸是否仍处于按下状态
    private var isVoiceTouchActive = false
    /// 用户是否仍处于贴底阅读状态；composer 高度变化时用它维持最新消息可见
    private var shouldMaintainBottomPosition = true
    /// 是否正在从相册面板切换到系统键盘。
    private var isSwitchingPhotoLibraryInputToKeyboard = false
    /// 相册面板切换到系统键盘期间是否需要保持列表贴底。
    private var shouldStickToBottomDuringKeyboardInputSwitch = false

    /// 渐变背景
    private let backgroundView = GradientBackgroundView()
    /// 消息 collection view
    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: makeLayout()
    )
    /// 空消息提示
    private let emptyLabel = UILabel()
    /// 群公告顶部入口
    private let announcementButton = UIButton(type: .system)
    /// 顶部信息栈
    private let topBannerStackView = UIStackView()
    /// @ 成员选择器
    private let mentionPickerStackView = UIStackView()
    /// 最近一次渲染的群公告状态
    private var currentGroupAnnouncement: ChatGroupAnnouncementState?
    /// 聊天输入栏
    private let inputBarView = ChatInputBarView()
    /// 图片库输入面板
    private lazy var photoLibraryInputView = makePhotoLibraryInputView()
    /// 表情输入面板
    private lazy var emojiPanelView = makeEmojiPanelView()
    /// 输入栏贴系统键盘约束
    private var inputBarKeyboardBottomConstraint: NSLayoutConstraint?
    /// 输入栏贴图片库面板约束
    private var inputBarPhotoLibraryBottomConstraint: NSLayoutConstraint?
    /// 图片库面板底部约束
    private var photoLibraryInputBottomConstraint: NSLayoutConstraint?
    /// 输入栏贴表情面板约束
    private var inputBarEmojiBottomConstraint: NSLayoutConstraint?
    /// 表情面板底部约束
    private var emojiPanelBottomConstraint: NSLayoutConstraint?
    /// 语音录制控制器
    private let voiceRecorder = VoiceRecordingController()
    /// 语音播放控制器
    private let voicePlaybackController = VoicePlaybackController()
    /// 待发送附件预览
    private var pendingAttachmentPreviews: [ChatPendingAttachmentPreviewItem] = []
    /// 待发送媒体内容缓存
    private var pendingComposerMediaByID: [String: ChatComposerMedia] = [:]
    /// 待确认发送的本地语音录音
    private var pendingVoiceRecording: VoiceRecordingFile?

    /// 初始化聊天页
    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    /// 禁用 storyboard 初始化
    required init?(coder: NSCoder) {
        fatalError("Storyboard initialization is not supported.")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// 配置聊天页并加载首屏消息
    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItem()
        configureView()
        configureDataSource()
        configureVoiceRecorder()
        configureVoicePlayback()
        observeKeyboard()
        bindConversationStoreNotifications()
        bindViewModel()
        viewModel.load()
    }

    /// 页面消失时停止播放、取消任务并保存草稿
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        voicePlaybackController.stop()
        removePendingVoiceRecordingFile()
        inputBarView.clearPendingVoicePreview(animated: false)
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

        topBannerStackView.translatesAutoresizingMaskIntoConstraints = false
        topBannerStackView.axis = .vertical
        topBannerStackView.spacing = 8
        topBannerStackView.layoutMargins = UIEdgeInsets(top: 8, left: 12, bottom: 0, right: 12)
        topBannerStackView.isLayoutMarginsRelativeArrangement = true

        announcementButton.configuration = ChatBridgeDesignSystem.makeGlassButtonConfiguration(role: .secondary)
        announcementButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        announcementButton.contentHorizontalAlignment = .leading
        announcementButton.accessibilityIdentifier = "chat.groupAnnouncementButton"
        announcementButton.isHidden = true
        announcementButton.addTarget(self, action: #selector(groupAnnouncementTapped), for: .touchUpInside)
        topBannerStackView.addArrangedSubview(announcementButton)

        mentionPickerStackView.translatesAutoresizingMaskIntoConstraints = false
        mentionPickerStackView.axis = .horizontal
        mentionPickerStackView.alignment = .center
        mentionPickerStackView.spacing = 8
        mentionPickerStackView.layoutMargins = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        mentionPickerStackView.isLayoutMarginsRelativeArrangement = true
        mentionPickerStackView.isHidden = true
        mentionPickerStackView.accessibilityIdentifier = "chat.mentionPicker"

        inputBarView.translatesAutoresizingMaskIntoConstraints = false
        photoLibraryInputView.translatesAutoresizingMaskIntoConstraints = false
        photoLibraryInputView.isHidden = true
        photoLibraryInputView.accessibilityIdentifier = "chat.photoLibraryInputPanel"
        emojiPanelView.translatesAutoresizingMaskIntoConstraints = false
        emojiPanelView.isHidden = true
        configureInputBarCallbacks()

        view.addSubview(topBannerStackView)
        view.addSubview(collectionView)
        view.addSubview(emptyLabel)
        view.addSubview(mentionPickerStackView)
        view.addSubview(inputBarView)
        view.addSubview(photoLibraryInputView)
        view.addSubview(emojiPanelView)

        let inputBarKeyboardBottomConstraint = inputBarView.bottomAnchor.constraint(
            equalTo: view.keyboardLayoutGuide.topAnchor,
            constant: -8
        )
        let inputBarPhotoLibraryBottomConstraint = inputBarView.bottomAnchor.constraint(
            equalTo: photoLibraryInputView.topAnchor,
            constant: -8
        )
        let photoLibraryInputHeightConstraint = photoLibraryInputView.heightAnchor.constraint(
            equalToConstant: ChatPhotoLibraryInputView.panelHeight
        )
        let photoLibraryInputBottomConstraint = photoLibraryInputView.bottomAnchor.constraint(
            equalTo: view.bottomAnchor
        )
        let inputBarEmojiBottomConstraint = inputBarView.bottomAnchor.constraint(
            equalTo: emojiPanelView.topAnchor,
            constant: -8
        )
        let emojiPanelHeightConstraint = emojiPanelView.heightAnchor.constraint(
            equalToConstant: ChatEmojiPanelView.panelHeight
        )
        let emojiPanelBottomConstraint = emojiPanelView.bottomAnchor.constraint(
            equalTo: view.bottomAnchor
        )
        self.inputBarKeyboardBottomConstraint = inputBarKeyboardBottomConstraint
        self.inputBarPhotoLibraryBottomConstraint = inputBarPhotoLibraryBottomConstraint
        self.photoLibraryInputBottomConstraint = photoLibraryInputBottomConstraint
        self.inputBarEmojiBottomConstraint = inputBarEmojiBottomConstraint
        self.emojiPanelBottomConstraint = emojiPanelBottomConstraint

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            topBannerStackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBannerStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBannerStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            collectionView.topAnchor.constraint(equalTo: topBannerStackView.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: mentionPickerStackView.topAnchor, constant: -8),

            emptyLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),

            inputBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            inputBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            inputBarKeyboardBottomConstraint,

            mentionPickerStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mentionPickerStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mentionPickerStackView.bottomAnchor.constraint(equalTo: inputBarView.topAnchor, constant: -8),

            photoLibraryInputView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            photoLibraryInputView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            photoLibraryInputBottomConstraint,
            photoLibraryInputHeightConstraint,

            emojiPanelView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emojiPanelView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emojiPanelBottomConstraint,
            emojiPanelHeightConstraint
        ])
    }

    /// 配置聊天页导航栏操作。
    private func configureNavigationItem() {
        navigationItem.largeTitleDisplayMode = .never

        let simulateIncomingButton = UIBarButtonItem(
            image: UIImage(systemName: "message.fill"),
            style: .plain,
            target: self,
            action: #selector(simulateIncomingTapped)
        )
        simulateIncomingButton.accessibilityIdentifier = "chat.simulateIncomingButton"
        simulateIncomingButton.accessibilityLabel = "模拟接收消息"
        navigationItem.rightBarButtonItem = simulateIncomingButton
    }

    /// 模拟接收一条对方消息。
    @objc private func simulateIncomingTapped() {
        viewModel.simulateIncomingMessage()
    }

    /// 绑定输入栏按钮和文本变化回调
    private func configureInputBarCallbacks() {
        inputBarView.onTextChanged = { [weak self] text in
            self?.viewModel.composerTextChanged(text)
        }
        inputBarView.onSend = { [weak self] text in
            self?.sendComposer(text: text)
        }
        inputBarView.onPhotoTapped = { [weak self] in
            self?.showPhotoLibraryInput()
        }
        inputBarView.onEmojiTapped = { [weak self] in
            self?.showEmojiInput()
        }
        inputBarView.onKeyboardInputRequested = { [weak self] in
            self?.showKeyboardInput()
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
        inputBarView.onVoicePreviewCancel = { [weak self] in
            self?.cancelPendingVoicePreview()
        }
        inputBarView.onVoicePreviewPlayToggle = { [weak self] in
            self?.togglePendingVoicePreviewPlayback()
        }
        inputBarView.onVoicePreviewSend = { [weak self] in
            self?.sendPendingVoicePreview()
        }
        inputBarView.onHeightWillChange = { [weak self] in
            self?.shouldStickToBottomForLayoutChange() ?? false
        }
        inputBarView.onHeightDidChange = { [weak self] shouldStickToBottom in
            guard shouldStickToBottom else { return }
            self?.scrollToBottom(animated: false)
        }
    }

    /// 展示群公告详情，并在有权限时允许编辑。
    @objc private func groupAnnouncementTapped() {
        guard let currentGroupAnnouncement else { return }

        let alertController = UIAlertController(
            title: "群公告",
            message: currentGroupAnnouncement.text,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "关闭", style: .cancel))

        if currentGroupAnnouncement.canEdit {
            alertController.addTextField { textField in
                textField.text = currentGroupAnnouncement.text
                textField.placeholder = "输入群公告"
                textField.accessibilityIdentifier = "chat.groupAnnouncementEditor"
            }
            alertController.addAction(
                UIAlertAction(title: "保存", style: .default) { [weak self, weak alertController] _ in
                    let text = alertController?.textFields?.first?.text ?? ""
                    self?.viewModel.updateGroupAnnouncement(text)
                }
            )
        }

        present(alertController, animated: true)
    }

    /// 监听系统键盘布局变化，保持底部消息不被输入区域遮挡。
    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    /// 监听仓储层会话变更，当前聊天命中时刷新消息列表。
    private func bindConversationStoreNotifications() {
        NotificationCenter.default.publisher(for: .chatStoreConversationsDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self, view.window != nil else { return }
                let userID = notification.userInfo?[ChatStoreConversationChangeNotification.userIDKey] as? String
                let conversationIDs = notification.userInfo?[ChatStoreConversationChangeNotification.conversationIDsKey] as? [String] ?? []
                viewModel.refreshAfterStoreChange(userID: userID, conversationIDs: conversationIDs)
            }
            .store(in: &cancellables)
    }

    /// 键盘 frame 变化时同步布局，并在用户原本贴底阅读时维持最新消息可见。
    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        let isCompletingPhotoLibraryKeyboardSwitch = isSwitchingPhotoLibraryInputToKeyboard
            && !photoLibraryInputView.isHidden
        let shouldStickToBottom = isCompletingPhotoLibraryKeyboardSwitch
            ? shouldStickToBottomDuringKeyboardInputSwitch
            : shouldStickToBottomForLayoutChange()
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        let rawCurve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
            ?? UIView.AnimationOptions.curveEaseInOut.rawValue
        let options = UIView.AnimationOptions(rawValue: rawCurve << 16)

        if isCompletingPhotoLibraryKeyboardSwitch {
            inputBarKeyboardBottomConstraint?.isActive = true
            inputBarPhotoLibraryBottomConstraint?.isActive = false
            photoLibraryInputBottomConstraint?.constant = 0
        }

        let layoutChanges = { [weak self] in
            guard let self else { return }
            if isCompletingPhotoLibraryKeyboardSwitch {
                self.photoLibraryInputView.alpha = 0
            }
            self.view.layoutIfNeeded()
            if shouldStickToBottom {
                self.scrollToBottom(animated: false)
            }
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            if isCompletingPhotoLibraryKeyboardSwitch {
                self.photoLibraryInputView.isHidden = true
                self.photoLibraryInputView.resetDismissGestureState()
                self.isSwitchingPhotoLibraryInputToKeyboard = false
                self.shouldStickToBottomDuringKeyboardInputSwitch = false
            }
            if shouldStickToBottom {
                self.scrollToBottom(animated: false)
            }
        }

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [options, .beginFromCurrentState, .allowUserInteraction],
            animations: layoutChanges,
            completion: completion
        )
    }

    /// 创建并绑定图片库输入面板
    private func makePhotoLibraryInputView() -> ChatPhotoLibraryInputView {
        let inputView = ChatPhotoLibraryInputView(frame: .zero)

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
        inputView.onDismissPanChanged = { [weak self] translationY in
            self?.applyPhotoLibraryDismissPanTranslation(translationY)
        }
        inputView.onDismissRequested = { [weak self] in
            self?.hidePhotoLibraryInput(animated: true)
        }

        return inputView
    }

    /// 创建并绑定表情输入面板
    private func makeEmojiPanelView() -> ChatEmojiPanelView {
        let panelView = ChatEmojiPanelView(frame: .zero)
        panelView.onEmojiSelected = { [weak self] emoji in
            self?.viewModel.sendEmoji(emoji)
        }
        panelView.onFavoriteToggled = { [weak self] emoji, isFavorite in
            self?.viewModel.toggleEmojiFavorite(emojiID: emoji.emojiID, isFavorite: isFavorite)
        }
        return panelView
    }

    /// 展示图片库输入面板
    private func showPhotoLibraryInput() {
        let shouldStickToBottom = shouldStickToBottomForLayoutChange()
        isSwitchingPhotoLibraryInputToKeyboard = false
        shouldStickToBottomDuringKeyboardInputSwitch = false
        hideEmojiInput(animated: false)
        photoLibraryInputView.refreshAuthorization()
        setPhotoLibraryInputVisible(true, animated: true, shouldStickToBottom: shouldStickToBottom)
        inputBarView.showPhotoLibraryInput()
    }

    /// 展示表情输入面板
    private func showEmojiInput() {
        let shouldStickToBottom = shouldStickToBottomForLayoutChange()
        isSwitchingPhotoLibraryInputToKeyboard = false
        shouldStickToBottomDuringKeyboardInputSwitch = false
        hidePhotoLibraryInput(animated: false)
        viewModel.loadEmojiPanel()
        setEmojiInputVisible(true, animated: true, shouldStickToBottom: shouldStickToBottom)
        inputBarView.showEmojiInput()
    }

    /// 从图片库输入面板切回系统键盘输入
    private func showKeyboardInput() {
        hideEmojiInput(animated: false)
        guard !photoLibraryInputView.isHidden else {
            inputBarView.showKeyboardInput()
            return
        }

        isSwitchingPhotoLibraryInputToKeyboard = true
        shouldStickToBottomDuringKeyboardInputSwitch = shouldStickToBottomForLayoutChange()
        inputBarView.showKeyboardInput()
    }

    /// 隐藏图片库输入面板
    private func hidePhotoLibraryInput(animated: Bool, completion: (() -> Void)? = nil) {
        setPhotoLibraryInputVisible(
            false,
            animated: animated,
            shouldStickToBottom: shouldStickToBottomForLayoutChange(),
            completion: completion
        )
    }

    /// 隐藏表情输入面板
    private func hideEmojiInput(animated: Bool, completion: (() -> Void)? = nil) {
        setEmojiInputVisible(
            false,
            animated: animated,
            shouldStickToBottom: shouldStickToBottomForLayoutChange(),
            completion: completion
        )
    }

    /// 切换图片库输入面板布局
    private func setPhotoLibraryInputVisible(
        _ isVisible: Bool,
        animated: Bool,
        shouldStickToBottom: Bool,
        completion externalCompletion: (() -> Void)? = nil
    ) {
        guard photoLibraryInputView.isHidden == isVisible else {
            externalCompletion?()
            return
        }

        if isVisible {
            photoLibraryInputView.isHidden = false
            photoLibraryInputView.resetDismissGestureState()
            photoLibraryInputBottomConstraint?.constant = 0
            inputBarPhotoLibraryBottomConstraint?.constant = -8
        }

        inputBarKeyboardBottomConstraint?.isActive = !isVisible
        inputBarPhotoLibraryBottomConstraint?.isActive = isVisible
        inputBarEmojiBottomConstraint?.isActive = false

        let layoutChanges = { [weak self] in
            guard let self else { return }
            self.photoLibraryInputView.alpha = isVisible ? 1 : 0
            self.view.layoutIfNeeded()
            if shouldStickToBottom {
                self.scrollToBottom(animated: false)
            }
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            if !isVisible {
                self.photoLibraryInputView.isHidden = true
                self.photoLibraryInputView.resetDismissGestureState()
            }
            if shouldStickToBottom {
                self.scrollToBottom(animated: false)
            }
            externalCompletion?()
        }

        if animated {
            UIView.animate(
                withDuration: 0.25,
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

    /// 切换表情输入面板布局
    private func setEmojiInputVisible(
        _ isVisible: Bool,
        animated: Bool,
        shouldStickToBottom: Bool,
        completion externalCompletion: (() -> Void)? = nil
    ) {
        guard emojiPanelView.isHidden == isVisible else {
            externalCompletion?()
            return
        }

        if isVisible {
            emojiPanelView.isHidden = false
            emojiPanelBottomConstraint?.constant = 0
            inputBarEmojiBottomConstraint?.constant = -8
        }

        inputBarKeyboardBottomConstraint?.isActive = !isVisible
        inputBarPhotoLibraryBottomConstraint?.isActive = false
        inputBarEmojiBottomConstraint?.isActive = isVisible

        let layoutChanges = { [weak self] in
            guard let self else { return }
            self.emojiPanelView.alpha = isVisible ? 1 : 0
            self.view.layoutIfNeeded()
            if shouldStickToBottom {
                self.scrollToBottom(animated: false)
            }
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            if !isVisible {
                self.emojiPanelView.isHidden = true
            }
            if shouldStickToBottom {
                self.scrollToBottom(animated: false)
            }
            externalCompletion?()
        }

        if animated {
            UIView.animate(
                withDuration: 0.25,
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

    /// 应用图片库面板下滑过程中的整体位移
    private func applyPhotoLibraryDismissPanTranslation(_ translationY: CGFloat) {
        let shouldStickToBottom = shouldStickToBottomForLayoutChange()
        let clampedTranslation = max(0, translationY)
        inputBarPhotoLibraryBottomConstraint?.constant = -8
        photoLibraryInputBottomConstraint?.constant = clampedTranslation
        view.layoutIfNeeded()
        if shouldStickToBottom {
            scrollToBottom(animated: false)
        }
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
            if messageID == pendingVoicePreviewMessageID {
                self?.renderPendingVoicePreview(isPlaying: true, progress: nil)
                return
            }
            self?.viewModel.voicePlaybackStarted(messageID: messageID)
        }
        voicePlaybackController.onStopped = { [weak self] messageID in
            if messageID == pendingVoicePreviewMessageID {
                self?.renderPendingVoicePreview(isPlaying: false, progress: nil)
                return
            }
            self?.viewModel.voicePlaybackStopped(messageID: messageID)
        }
        voicePlaybackController.onFailed = { [weak self] messageID in
            if messageID == pendingVoicePreviewMessageID {
                self?.renderPendingVoicePreview(isPlaying: false, progress: nil)
                self?.showTransientRecordingMessage("Unable to play voice")
                return
            }
            self?.viewModel.voicePlaybackStopped(messageID: messageID)
            self?.showTransientRecordingMessage("Unable to play voice")
        }
        voicePlaybackController.onProgress = { [weak self] messageID, progress in
            if messageID == pendingVoicePreviewMessageID {
                self?.renderPendingVoicePreview(isPlaying: true, progress: progress)
                return
            }
            self?.viewModel.voicePlaybackProgress(messageID: messageID, progress: progress)
        }
    }

    /// 配置消息列表数据源
    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<ChatMessageCell, String> { [weak self] cell, _, rowID in
            guard let self, let row = self.rowsByID[rowID] else { return }
            let actions = ChatMessageCellActions(
                onRetry: { [weak self] messageID in
                    self?.viewModel.resend(messageID: messageID)
                },
                onDelete: { [weak self] messageID in
                    self?.confirmDelete(messageID: messageID)
                },
                onRevoke: { [weak self] messageID in
                    self?.confirmRevoke(messageID: messageID)
                },
                onPlayVoice: { [weak self] row in
                    self?.handleVoicePlayback(row)
                },
                onPlayVideo: { [weak self] row in
                    self?.handleVideoPlayback(row)
                }
            )
            cell.configure(row: row, actions: actions)
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

    private func confirmDelete(messageID: MessageID) {
        let alertController = UIAlertController(
            title: "Delete Message?",
            message: "This message will be removed from this device.",
            preferredStyle: .alert
        )
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        cancelAction.setValue("chat.cancelMessageAction", forKey: "accessibilityIdentifier")
        let deleteAction = UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.viewModel.delete(messageID: messageID)
        }
        deleteAction.setValue("chat.confirmDeleteMessage", forKey: "accessibilityIdentifier")

        alertController.addAction(cancelAction)
        alertController.addAction(deleteAction)
        present(alertController, animated: true)
    }

    private func confirmRevoke(messageID: MessageID) {
        let alertController = UIAlertController(
            title: "Revoke Message?",
            message: "Everyone in this local conversation will see a revoke notice.",
            preferredStyle: .alert
        )
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        cancelAction.setValue("chat.cancelMessageAction", forKey: "accessibilityIdentifier")
        let revokeAction = UIAlertAction(title: "Revoke", style: .destructive) { [weak self] _ in
            self?.viewModel.revoke(messageID: messageID)
        }
        revokeAction.setValue("chat.confirmRevokeMessage", forKey: "accessibilityIdentifier")

        alertController.addAction(cancelAction)
        alertController.addAction(revokeAction)
        present(alertController, animated: true)
    }

    /// 绑定聊天状态变化
    private func bindViewModel() {
        viewModel.statePublisher
            .sink { [weak self] state in
                self?.render(state)
            }
            .store(in: &cancellables)
    }

    /// 将最新的聊天页状态渲染到 UIKit 视图层。
    ///
    /// 这个方法集中处理状态到界面的单向同步：先刷新导航标题、空态和输入栏，
    /// 再计算消息列表的增量快照，最后根据消息插入位置决定是否保持当前位置或滚动到底部。
    private func render(_ state: ChatViewState) {
        let renderStartUptime = ProcessInfo.processInfo.systemUptime
        logger.debug("ChatViewController render started rows=\(state.rows.count)")

        // 同步不依赖 collection view diff 的轻量 UI 状态。
        title = state.title
        emptyLabel.text = state.emptyMessage
        emptyLabel.isHidden = !state.isEmpty || state.phase == .loading
        renderGroupAnnouncement(state.groupAnnouncement)
        renderMentionPicker(state.mentionPicker)
        emojiPanelView.render(state.emojiPanel)

        // 用户正在输入时不覆盖输入框内容，避免 Combine 状态回放打断编辑。
        if !inputBarView.isEditingText, inputBarView.text != state.draftText {
            inputBarView.setText(state.draftText, animated: false)
        }

        snapshotRenderCoordinator.apply(state) { [weak self] state, completion in
            self?.renderMessageSnapshot(state) { [weak self] in
                self?.logger.debug(
                    "ChatViewController render completed rows=\(state.rows.count) elapsed=\(AppLogger.elapsedMilliseconds(since: renderStartUptime))"
                )
                completion()
            } ?? completion()
        }
    }

    /// 串行应用消息列表快照；调用方负责保证同一时间只有一次 apply 正在进行。
    private func renderMessageSnapshot(_ state: ChatViewState, completion: @escaping () -> Void) {
        // 在应用新快照前记录旧列表状态，用于判断本次渲染属于首屏、上拉加载还是新消息追加。
        let previousRowsByID = rowsByID
        let previousRowIDs = lastRenderedRowIDs
        let previousContentHeight = collectionView.contentSize.height
        let previousContentOffsetY = collectionView.contentOffset.y
        let wasNearBottom = shouldStickToBottomForLayoutChange()

        // Diffable data source 的 item identifier 使用消息 ID；内容变化通过 changedRowIDs 触发 reload。
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
        let appendedCount = max(0, newRowIDs.count - previousRowIDs.count)

        // 缓存最新 row 内容，供 cell registration 和下一次 render diff 对比使用。
        rowsByID = Dictionary(uniqueKeysWithValues: state.rows.map { ($0.id.rawValue, $0) })
        lastRenderedRowIDs = newRowIDs

        guard let dataSource else {
            completion()
            return
        }

        let snapshotStartUptime = ProcessInfo.processInfo.systemUptime
        logger.debug(
            "ChatViewController snapshot apply started rows=\(newRowIDs.count) appended=\(appendedCount) changed=\(changedRowIDs.count) initial=\(isInitialMessageRender) prepending=\(isPrependingOlderMessages) didAppend=\(didAppendNewMessage)"
        )
        let snapshot = makeIncrementalSnapshot(
            dataSource: dataSource,
            previousRowIDs: previousRowIDs,
            newRowIDs: newRowIDs,
            changedRowIDs: changedRowIDs
        )

        dataSource.apply(snapshot, animatingDifferences: !isInitialMessageRender) { [weak self] in
            guard let self else { return }

            self.collectionView.layoutIfNeeded()

            // 上拉加载历史消息时，保持用户当前看到的第一条附近内容不跳动。
            if isPrependingOlderMessages {
                let heightDelta = self.collectionView.contentSize.height - previousContentHeight
                let adjustedOffsetY = previousContentOffsetY + heightDelta
                self.collectionView.setContentOffset(
                    CGPoint(x: self.collectionView.contentOffset.x, y: adjustedOffsetY),
                    animated: false
                )
            } else if isInitialMessageRender || didAppendNewMessage || wasNearBottom {
                // 首屏、新消息追加或用户原本接近底部时，维持聊天应用常见的贴底阅读体验。
                self.scrollToBottom(animated: !isInitialMessageRender)
            }

            self.logger.debug(
                "ChatViewController snapshot apply completed rows=\(newRowIDs.count) appended=\(appendedCount) changed=\(changedRowIDs.count) elapsed=\(AppLogger.elapsedMilliseconds(since: snapshotStartUptime))"
            )
            completion()
        }
    }

    /// 渲染群公告入口
    private func renderGroupAnnouncement(_ announcement: ChatGroupAnnouncementState?) {
        currentGroupAnnouncement = announcement
        announcementButton.isHidden = announcement == nil
        guard let announcement else { return }

        var configuration = announcementButton.configuration
        configuration?.title = "公告：\(announcement.text)"
        configuration?.image = UIImage(systemName: announcement.canEdit ? "megaphone.fill" : "megaphone")
        configuration?.imagePadding = 6
        announcementButton.configuration = configuration
    }

    /// 渲染 @ 成员选择器
    private func renderMentionPicker(_ picker: ChatMentionPickerState?) {
        mentionPickerStackView.arrangedSubviews.forEach { view in
            mentionPickerStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard let picker, !picker.options.isEmpty else {
            mentionPickerStackView.isHidden = true
            return
        }

        for option in picker.options {
            let button = UIButton(type: .system)
            button.configuration = ChatBridgeDesignSystem.makeGlassButtonConfiguration(role: option.mentionsAll ? .primary : .secondary)
            var configuration = button.configuration
            configuration?.title = "@\(option.displayName)"
            configuration?.image = UIImage(systemName: option.mentionsAll ? "person.3.fill" : "person.fill")
            configuration?.imagePadding = 4
            button.configuration = configuration
            button.accessibilityIdentifier = "chat.mentionOption.\(option.id)"
            button.addAction(UIAction { [weak self] _ in
                if option.mentionsAll {
                    self?.viewModel.selectMentionsAll()
                } else if let userID = option.userID {
                    self?.viewModel.selectMention(userID: userID)
                }
            }, for: .touchUpInside)
            mentionPickerStackView.addArrangedSubview(button)
        }
        mentionPickerStackView.isHidden = false
    }

    /// 根据新旧消息 ID 构造消息列表快照。
    ///
    /// 优先在当前 data source 快照上执行两端插入、删除和内容重载；当存量消息顺序变化，
    /// 或新增消息出现在列表中间时，回退为完整快照以保证 diffable data source 的最终顺序正确。
    ///
    /// - Parameters:
    ///   - dataSource: 当前消息列表使用的 diffable data source。
    ///   - previousRowIDs: 上一次渲染的消息 ID 顺序。
    ///   - newRowIDs: 本次需要渲染的消息 ID 顺序。
    ///   - changedRowIDs: ID 不变但内容发生变化的消息 ID。
    /// - Returns: 可直接应用到消息列表 data source 的快照。
    private func makeIncrementalSnapshot(
        dataSource: UICollectionViewDiffableDataSource<String, String>,
        previousRowIDs: [String],
        newRowIDs: [String],
        changedRowIDs: [String]
    ) -> NSDiffableDataSourceSnapshot<String, String> {
        // 首次渲染时没有旧数据可对比，直接创建完整快照。
        guard !previousRowIDs.isEmpty else {
            var snapshot = NSDiffableDataSourceSnapshot<String, String>()
            snapshot.appendSections([chatSection])
            snapshot.appendItems(newRowIDs, toSection: chatSection)
            return snapshot
        }

        // 只有存量消息的相对顺序保持一致时，才适合在当前快照上做增量更新。
        let oldSet = Set(previousRowIDs)
        let newSet = Set(newRowIDs)
        let survivingOldIDs = previousRowIDs.filter { newSet.contains($0) }
        let survivingNewIDs = newRowIDs.filter { oldSet.contains($0) }

        // 如果中间消息发生重排，用完整快照交给 diffable data source 重新计算差异。
        guard survivingOldIDs == survivingNewIDs else {
            var snapshot = NSDiffableDataSourceSnapshot<String, String>()
            snapshot.appendSections([chatSection])
            snapshot.appendItems(newRowIDs, toSection: chatSection)
            return snapshot
        }

        // 从当前 data source 取快照，保留 UIKit 已知的 item 状态。
        var snapshot = dataSource.snapshot()
        if !snapshot.sectionIdentifiers.contains(chatSection) {
            snapshot.appendSections([chatSection])
        }

        // 先删除已经不在新列表里的消息，避免后续插入时和旧 item 冲突。
        let currentIDs = snapshot.itemIdentifiers
        let currentSet = Set(currentIDs)
        let removedIDs = currentIDs.filter { !newSet.contains($0) }
        if !removedIDs.isEmpty {
            snapshot.deleteItems(removedIDs)
        }

        // 仅支持列表两端新增：顶部 prepend 历史消息，底部 append 新消息。
        let prefixIDs = Array(newRowIDs.prefix { !oldSet.contains($0) })
        let suffixIDs = Array(newRowIDs.reversed().prefix { !oldSet.contains($0) }.reversed())
        let insertedIDs = newRowIDs.filter { !currentSet.contains($0) }
        let edgeInsertedIDs = prefixIDs + suffixIDs

        // 如果新增项出现在列表中间，回退完整快照以保证顺序正确。
        guard insertedIDs == edgeInsertedIDs else {
            var snapshot = NSDiffableDataSourceSnapshot<String, String>()
            snapshot.appendSections([chatSection])
            snapshot.appendItems(newRowIDs, toSection: chatSection)
            return snapshot
        }

        // 顶部新增的历史消息插到第一条存量消息之前；没有存量消息时直接追加。
        if !prefixIDs.isEmpty {
            if let firstSurvivingID = survivingNewIDs.first {
                snapshot.insertItems(prefixIDs, beforeItem: firstSurvivingID)
            } else {
                snapshot.appendItems(prefixIDs, toSection: chatSection)
            }
        }

        // 底部新增消息保持自然顺序追加到列表末尾。
        if !suffixIDs.isEmpty {
            snapshot.appendItems(suffixIDs, toSection: chatSection)
        }

        // 对内容变化但 ID 未变化的消息执行轻量 reconfigure，避免不必要的删除插入动画。
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
        case let .completed(recording):
            pendingVoiceRecording = recording
            inputBarView.setPendingVoicePreview(
                durationMilliseconds: recording.durationMilliseconds,
                isPlaying: false,
                animated: true
            )
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

    /// 取消待发送语音预览
    private func cancelPendingVoicePreview() {
        voicePlaybackController.stop()
        removePendingVoiceRecordingFile()
        inputBarView.clearPendingVoicePreview(animated: true)
        showTransientRecordingMessage("Voice cancelled")
    }

    /// 播放或停止待发送语音预览
    private func togglePendingVoicePreviewPlayback() {
        guard let pendingVoiceRecording else { return }

        if voicePlaybackController.isPlaying(messageID: pendingVoicePreviewMessageID) {
            voicePlaybackController.stop()
            return
        }

        voicePlaybackController.play(
            messageID: pendingVoicePreviewMessageID,
            fileURL: pendingVoiceRecording.fileURL
        )
    }

    /// 发送待确认的语音预览
    private func sendPendingVoicePreview() {
        guard let recording = pendingVoiceRecording else { return }
        voicePlaybackController.stop()
        pendingVoiceRecording = nil
        inputBarView.clearPendingVoicePreview(animated: true)
        viewModel.sendVoice(recording: recording)
    }

    /// 重新渲染待发送语音预览播放态
    private func renderPendingVoicePreview(isPlaying: Bool, progress: VoicePlaybackProgress?) {
        guard let pendingVoiceRecording else { return }
        inputBarView.setPendingVoicePreview(
            durationMilliseconds: pendingVoiceRecording.durationMilliseconds,
            isPlaying: isPlaying,
            playbackProgress: progress?.fraction ?? 0,
            playbackElapsedMilliseconds: progress?.elapsedMilliseconds ?? 0,
            animated: false
        )
    }

    /// 删除未发送的待确认语音文件
    private func removePendingVoiceRecordingFile() {
        guard let recording = pendingVoiceRecording else { return }
        pendingVoiceRecording = nil
        try? FileManager.default.removeItem(at: recording.fileURL)
    }

    /// 播放或停止语音消息
    private func handleVoicePlayback(_ row: ChatMessageRowState) {
        guard let voice = row.voiceContent else { return }

        if voice.isPlaying {
            voicePlaybackController.stop()
            return
        }

        guard !voice.localPath.isEmpty else {
            showTransientRecordingMessage("Voice file unavailable")
            return
        }

        voicePlaybackController.play(messageID: row.id, fileURL: URL(fileURLWithPath: voice.localPath))
    }

    /// 使用系统播放器播放本地视频消息
    private func handleVideoPlayback(_ row: ChatMessageRowState) {
        guard case let .video(video) = row.content else { return }
        guard FileManager.default.fileExists(atPath: video.localPath) else {
            showTransientRecordingMessage("Video file unavailable")
            return
        }

        let playerViewController = AVPlayerViewController()
        playerViewController.player = AVPlayer(url: URL(fileURLWithPath: video.localPath))
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
        let contentBottomY = collectionView.contentSize.height - collectionView.adjustedContentInset.bottom
        return messageVisibleBottomY() >= contentBottomY - 80
    }

    /// 判断本次布局变化是否应该保持贴底。
    private func shouldStickToBottomForLayoutChange() -> Bool {
        let shouldStick = shouldMaintainBottomPosition || isNearBottom()
        if shouldStick {
            shouldMaintainBottomPosition = true
        }
        return shouldStick
    }

    /// 滚动到最新消息
    private func scrollToBottom(animated: Bool) {
        shouldMaintainBottomPosition = true
        guard !lastRenderedRowIDs.isEmpty else { return }
        collectionView.layoutIfNeeded()
        let lastIndexPath = IndexPath(item: lastRenderedRowIDs.count - 1, section: 0)
        guard let attributes = collectionView.layoutAttributesForItem(at: lastIndexPath) else {
            collectionView.scrollToItem(at: lastIndexPath, at: .bottom, animated: animated)
            return
        }

        let proposedOffsetY = collectionView.contentOffset.y
            + attributes.frame.maxY
            - messageVisibleBottomY()
        let targetOffsetY = clampedContentOffsetY(
            proposedOffsetY,
            visibleMessageHeight: messageVisibleHeight()
        )
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: targetOffsetY),
            animated: animated
        )
    }

    /// 最新消息可见下边界，使用 content 坐标便于和 layout attributes 对齐。
    private func messageVisibleBottomY() -> CGFloat {
        let collectionVisibleBottomY = collectionView.contentOffset.y
            + collectionView.bounds.height
            - collectionView.adjustedContentInset.bottom
        let inputBarVisibleTopY = collectionView.convert(
            CGPoint(x: inputBarView.bounds.minX, y: inputBarView.bounds.minY),
            from: inputBarView
        ).y - 8
        return min(collectionVisibleBottomY, inputBarVisibleTopY)
    }

    /// 当前消息可见区域高度；输入栏覆盖列表时，合法最大偏移需要用这个高度计算。
    private func messageVisibleHeight() -> CGFloat {
        max(1, messageVisibleBottomY() - collectionView.contentOffset.y)
    }

    /// 将目标滚动位置限制在 scroll view 合法范围内，避免短列表出现无效偏移。
    private func clampedContentOffsetY(
        _ proposedOffsetY: CGFloat,
        visibleMessageHeight: CGFloat
    ) -> CGFloat {
        let minOffsetY = -collectionView.adjustedContentInset.top
        let maxOffsetY = max(
            minOffsetY,
            collectionView.contentSize.height
                - visibleMessageHeight
                + collectionView.adjustedContentInset.bottom
        )
        return min(max(proposedOffsetY, minOffsetY), maxOffsetY)
    }
}

/// 聊天消息列表滚动回调
extension ChatViewController: UICollectionViewDelegate {
    /// 用户开始拖动时取消程序化贴底动画，避免新消息追加后的滚动动画抢回手势。
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        collectionView.layer.removeAllAnimations()
        shouldMaintainBottomPosition = isNearBottom()
    }

    /// 滚动到顶部附近时加载更早消息
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating {
            shouldMaintainBottomPosition = isNearBottom()
        }

        guard !snapshotRenderCoordinator.isApplying else { return }

        let topThreshold = -scrollView.adjustedContentInset.top + 120

        if scrollView.contentOffset.y <= topThreshold {
            viewModel.loadOlderMessagesIfNeeded()
        }
    }
}

/// 消息行 diff 辅助
extension ChatMessageRowState {
    /// 用于触发 cell reconfigure 的稳定差异标识
    var diffIdentifier: String {
        let progressText = uploadProgress.map { String(Int($0 * 100)) } ?? ""
        let retryText = canRetry ? "retry" : "no-retry"
        let revokeText = canRevoke ? "revoke" : "no-revoke"

        return [
            id.rawValue,
            "\(content)",
            senderAvatarURL ?? "",
            statusText ?? "",
            progressText,
            retryText,
            revokeText
        ].joined(separator: "|")
    }
}
