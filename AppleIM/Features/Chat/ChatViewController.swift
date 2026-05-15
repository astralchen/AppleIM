//
//  ChatViewController.swift
//  AppleIM
//

import Combine
import AVKit
import UIKit

/// 待发送语音预览播放使用的本地占位 ID，避免影响消息列表播放态
private let pendingVoicePreviewMessageID = MessageID(rawValue: "__pending_voice_preview__")

/// 消息列表布局回调视图，让测试和运行时的 collectionView 自身布局也能推进首屏定位。
private final class ChatMessageCollectionView: UICollectionView {
    var onLayoutSubviews: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutSubviews?()
    }
}

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
    /// 判断布局变化前是否仍可视为贴底的容差；覆盖 estimated cell 高度稳定带来的像素级偏移。
    private static let bottomReanchorTolerance: CGFloat = 12

    /// 消息列表分区标识。
    nonisolated private enum Section: Hashable, Sendable {
        /// 聊天消息分区。
        case messages
    }

    /// 聊天页 ViewModel
    private let viewModel: ChatViewModel
    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()
    /// 消息列表 diffable 数据源
    private var dataSource: UICollectionViewDiffableDataSource<Section, MessageID>?
    /// 当前消息行缓存
    private var rowsByID: [MessageID: ChatMessageRowState] = [:]
    /// 最近一次渲染的消息行 ID 顺序
    private var lastRenderedRowIDs: [MessageID] = []
    /// 消息列表快照 apply 门控，防止 diffable data source 重入。
    private let snapshotRenderCoordinator = ChatSnapshotRenderCoordinator<ChatViewState>()
    /// 聊天 UI 耗时日志。
    private let logger = AppLogger(category: .chat)
    /// 语音按钮触摸是否仍处于按下状态
    private var isVoiceTouchActive = false
    /// 首屏消息已经渲染，但仍等待稳定布局后执行第一次贴底定位。
    private var needsInitialBottomPositioning = false
    /// 首屏贴底完成前临时隐藏消息列表，避免用户看到估算高度收敛带来的入场位移。
    private var isSuppressingInitialMessageAppearance = false
    /// 用户是否仍处于贴底阅读状态；composer 高度变化时用它维持最新消息可见
    private var shouldMaintainBottomPosition = true
    /// 用户正在拖拽或减速消息列表时，暂停自动贴底，避免底部反弹后抢回滚动位置。
    private var isUserControllingMessageScroll = false
    /// 是否正在从相册面板切换到系统键盘。
    private var isSwitchingPhotoLibraryInputToKeyboard = false
    /// 是否正在从表情面板切换到系统键盘。
    private var isSwitchingEmojiInputToKeyboard = false
    /// 自定义输入面板切换到系统键盘期间是否需要保持列表贴底。
    private var shouldStickToBottomDuringKeyboardInputSwitch = false
    /// 输入栏一次高度变化跨越 will/did 两个回调，这里暂存变化前的滚动状态。
    private var pendingInputBarLayoutTransaction: MessageLayoutTransaction?
    /// 动画贴底校正代次；用户开始拖动后让旧的延迟校正失效。
    private var bottomPositionCorrectionGeneration = 0
    /// 键盘布局 guide 后置稳定校正代次；避免首进页面呼出键盘时偶发遮挡最新消息。
    private var keyboardBottomCorrectionGeneration = 0
    /// 首屏贴底正在同步收敛，避免 collection view layoutSubviews 回调重入。
    private var isResolvingInitialBottomPositioning = false
    /// 历史消息插入锚点校正代次；用户继续滚动后让旧的延迟校正失效。
    private var prependScrollAnchorCorrectionGeneration = 0
#if DEBUG
    /// 测试用：记录最近一次贴底滚动是否请求动画。
    private(set) var lastScrollToBottomRequestedAnimationForTesting: Bool?
#endif

    /// 自定义输入面板类型。
    private enum CustomInputPanel: Equatable {
        /// 图片库面板。
        case photoLibrary
        /// 表情面板。
        case emoji
    }

    /// 一次会影响消息可见区域的布局变化。
    private struct MessageLayoutTransaction {
        /// 变化发生前是否应该维持底部消息可见。
        let shouldStickToBottom: Bool
        /// 不贴底时保留用户当前阅读位置，避免输入栏变化把历史消息推走。
        let previousContentOffset: CGPoint
    }

    /// 上拉加载历史消息时用于保持阅读位置的旧消息锚点。
    private struct MessagePrependScrollAnchor {
        /// 快照前仍在屏幕内的旧消息 ID。
        let rowID: MessageID
        /// 快照前该旧消息在 collection view 内容坐标内的顶部位置。
        let previousMinY: CGFloat
        /// 快照前的滚动位置；恢复时在这个基础上叠加锚点位移。
        let previousContentOffsetY: CGFloat
    }

    /// 消息 collection view
    private lazy var collectionView: UICollectionView = {
        let collectionView = ChatMessageCollectionView(
            frame: .zero,
            collectionViewLayout: makeLayout()
        )
        collectionView.onLayoutSubviews = { [weak self] in
            self?.handleMessageCollectionLayoutDidUpdate()
        }
        return collectionView
    }()
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

    /// 窗口、安全区或输入栏完成布局后，继续保持最新消息不被底部输入区遮挡。
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCollectionViewOverlayInsets()
        if needsInitialBottomPositioning {
            _ = resolveInitialBottomPositioningIfPossible()
            return
        }
        let isLatestMessageVisibleAboveInputBar = isLatestRenderedMessageVisibleAboveInputBar()
        let shouldRestoreOccludedNearBottomMessage = isNearBottom()
            && !isLatestMessageVisibleAboveInputBar
        let shouldReanchorMaintainedBottomMessage = shouldMaintainBottomPosition
            && !isLatestMessageVisibleAboveInputBar
        guard
            !isUserControllingMessageScroll,
            !lastRenderedRowIDs.isEmpty,
            shouldReanchorMaintainedBottomMessage || shouldRestoreOccludedNearBottomMessage
        else { return }
        scrollToBottom(animated: false)
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
        view.backgroundColor = .systemBackground

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.contentInsetAdjustmentBehavior = .never
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
            topBannerStackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBannerStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBannerStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

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
            mentionPickerStackView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

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
        simulateIncomingButton.accessibilityLabel = "后台推送对方消息"
        navigationItem.rightBarButtonItem = simulateIncomingButton
    }

    /// 触发后台推送一条对方消息。
    @objc private func simulateIncomingTapped() {
        viewModel.simulateIncomingMessage()
    }

    /// 绑定输入栏按钮和文本变化回调
    private func configureInputBarCallbacks() {
        inputBarView.layoutDelegate = self
        inputBarView.addTarget(self, action: #selector(inputBarActionTriggered(_:)), for: .primaryActionTriggered)
        inputBarView.addTarget(self, action: #selector(inputBarActionTriggered(_:)), for: .editingChanged)
    }

    /// 处理输入栏按 Apple SDK target-action 形式发布的动作。
    @objc private func inputBarActionTriggered(_ sender: ChatInputBarView) {
        guard let action = sender.lastAction else { return }

        switch action {
        case let .textChanged(text):
            viewModel.composerTextChanged(text)
        case let .send(text):
            sendComposer(text: text)
        case .photoTapped:
            showPhotoLibraryInput()
        case .emojiTapped:
            showEmojiInput()
        case .keyboardInputRequested:
            showKeyboardInput()
        case let .attachmentRemoved(id):
            removePendingAttachment(id: id)
            photoLibraryInputView.removeSelection(assetID: id)
        case .voiceTouchDown:
            voiceButtonTouchDown()
        case .voiceTouchDragExit:
            voiceButtonTouchDragExit()
        case .voiceTouchDragEnter:
            voiceButtonTouchDragEnter()
        case .voiceTouchUpInside:
            voiceButtonTouchUpInside()
        case .voiceTouchUpOutside:
            voiceButtonTouchUpOutside()
        case .voiceTouchCancel:
            voiceButtonTouchCancel()
        case .voicePreviewCancel:
            cancelPendingVoicePreview()
        case .voicePreviewPlayToggle:
            togglePendingVoicePreviewPlayback()
        case .voicePreviewSend:
            sendPendingVoicePreview()
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
        NotificationCenter.default.chatStoreConversationChangesPublisher()
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard let self, view.window != nil else { return }
                viewModel.refreshAfterStoreChange(
                    userID: event.userID.rawValue,
                    conversationIDs: event.conversationIDs.map(\.rawValue)
                )
            }
            .store(in: &cancellables)
    }

    /// 键盘 frame 变化时同步布局，并在用户原本贴底阅读时维持最新消息可见。
    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        let isCompletingPhotoLibraryKeyboardSwitch = isSwitchingPhotoLibraryInputToKeyboard
            && !photoLibraryInputView.isHidden
        let isCompletingEmojiKeyboardSwitch = isSwitchingEmojiInputToKeyboard
            && !emojiPanelView.isHidden
        let isCompletingCustomInputKeyboardSwitch = isCompletingPhotoLibraryKeyboardSwitch
            || isCompletingEmojiKeyboardSwitch
        let shouldStickToBottom = isCompletingCustomInputKeyboardSwitch
            ? shouldStickToBottomDuringKeyboardInputSwitch
            : shouldStickToBottomForLayoutChange()
        let layoutTransaction = MessageLayoutTransaction(
            shouldStickToBottom: shouldStickToBottom,
            previousContentOffset: collectionView.contentOffset
        )
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        let rawCurve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
            ?? UIView.AnimationOptions.curveEaseInOut.rawValue
        let options = UIView.AnimationOptions(rawValue: rawCurve << 16)

        if isCompletingCustomInputKeyboardSwitch {
            inputBarKeyboardBottomConstraint?.isActive = true
            inputBarPhotoLibraryBottomConstraint?.isActive = false
            inputBarEmojiBottomConstraint?.isActive = false
        }
        if isCompletingPhotoLibraryKeyboardSwitch {
            photoLibraryInputBottomConstraint?.constant = 0
        }
        if isCompletingEmojiKeyboardSwitch {
            emojiPanelBottomConstraint?.constant = 0
        }

        let layoutChanges = { [weak self] in
            guard let self else { return }
            if isCompletingPhotoLibraryKeyboardSwitch {
                self.photoLibraryInputView.alpha = 0
            }
            if isCompletingEmojiKeyboardSwitch {
                self.emojiPanelView.alpha = 0
            }
            self.completeMessageLayoutTransaction(layoutTransaction, animated: false)
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            if isCompletingPhotoLibraryKeyboardSwitch {
                self.photoLibraryInputView.isHidden = true
                self.photoLibraryInputView.resetDismissGestureState()
                self.isSwitchingPhotoLibraryInputToKeyboard = false
                self.shouldStickToBottomDuringKeyboardInputSwitch = false
            }
            if isCompletingEmojiKeyboardSwitch {
                self.emojiPanelView.isHidden = true
                self.isSwitchingEmojiInputToKeyboard = false
                self.shouldStickToBottomDuringKeyboardInputSwitch = false
            }
            self.completeMessageLayoutTransaction(layoutTransaction, animated: false)
        }

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [options, .beginFromCurrentState, .allowUserInteraction],
            animations: layoutChanges,
            completion: completion
        )
        scheduleKeyboardBottomPositionCorrectionIfNeeded(
            shouldStickToBottom: layoutTransaction.shouldStickToBottom,
            duration: duration
        )
    }

    /// 创建并绑定图片库输入面板
    private func makePhotoLibraryInputView() -> ChatPhotoLibraryInputView {
        let inputView = ChatPhotoLibraryInputView(frame: .zero)
        inputView.inputDelegate = self
        return inputView
    }

    /// 创建并绑定表情输入面板
    private func makeEmojiPanelView() -> ChatEmojiPanelView {
        let panelView = ChatEmojiPanelView(frame: .zero)
        panelView.addTarget(self, action: #selector(emojiPanelActionTriggered(_:)), for: .primaryActionTriggered)
        return panelView
    }

    /// 处理表情面板按 target-action 形式发布的动作。
    @objc private func emojiPanelActionTriggered(_ sender: ChatEmojiPanelView) {
        guard let action = sender.lastAction else { return }

        switch action {
        case let .selected(emoji):
            viewModel.sendEmoji(emoji)
        case let .favoriteToggled(emoji, isFavorite):
            viewModel.toggleEmojiFavorite(emojiID: emoji.emojiID, isFavorite: isFavorite)
        }
    }

    /// 展示图片库输入面板
    private func showPhotoLibraryInput() {
        let layoutTransaction = beginMessageLayoutTransaction()
        isSwitchingPhotoLibraryInputToKeyboard = false
        isSwitchingEmojiInputToKeyboard = false
        shouldStickToBottomDuringKeyboardInputSwitch = false
        photoLibraryInputView.refreshAuthorization()

        if !emojiPanelView.isHidden {
            switchCustomInputPanel(
                from: .emoji,
                to: .photoLibrary,
                transaction: layoutTransaction
            )
            inputBarView.showPhotoLibraryInput()
            return
        }

        hideEmojiInput(animated: false)
        setPhotoLibraryInputVisible(true, animated: true, transaction: layoutTransaction)
        inputBarView.showPhotoLibraryInput()
    }

    /// 展示表情输入面板
    private func showEmojiInput() {
        let layoutTransaction = beginMessageLayoutTransaction()
        isSwitchingPhotoLibraryInputToKeyboard = false
        isSwitchingEmojiInputToKeyboard = false
        shouldStickToBottomDuringKeyboardInputSwitch = false
        viewModel.loadEmojiPanel()

        if !photoLibraryInputView.isHidden {
            switchCustomInputPanel(
                from: .photoLibrary,
                to: .emoji,
                transaction: layoutTransaction
            )
            inputBarView.showEmojiInput()
            return
        }

        hidePhotoLibraryInput(animated: false)
        setEmojiInputVisible(true, animated: true, transaction: layoutTransaction)
        inputBarView.showEmojiInput()
    }

    /// 从自定义输入面板切回系统键盘输入。
    private func showKeyboardInput() {
        if !photoLibraryInputView.isHidden {
            isSwitchingPhotoLibraryInputToKeyboard = true
            isSwitchingEmojiInputToKeyboard = false
            shouldStickToBottomDuringKeyboardInputSwitch = shouldStickToBottomForLayoutChange()
            inputBarView.showKeyboardInput()
            return
        }
        if !emojiPanelView.isHidden {
            isSwitchingPhotoLibraryInputToKeyboard = false
            isSwitchingEmojiInputToKeyboard = true
            shouldStickToBottomDuringKeyboardInputSwitch = shouldStickToBottomForLayoutChange()
            inputBarView.showKeyboardInput()
            return
        }

        isSwitchingPhotoLibraryInputToKeyboard = false
        isSwitchingEmojiInputToKeyboard = false
        shouldStickToBottomDuringKeyboardInputSwitch = false
        inputBarView.showKeyboardInput()
    }

    /// 隐藏图片库输入面板
    private func hidePhotoLibraryInput(animated: Bool, completion: (() -> Void)? = nil) {
        setPhotoLibraryInputVisible(
            false,
            animated: animated,
            transaction: beginMessageLayoutTransaction(),
            completion: completion
        )
    }

    /// 隐藏表情输入面板
    private func hideEmojiInput(animated: Bool, completion: (() -> Void)? = nil) {
        setEmojiInputVisible(
            false,
            animated: animated,
            transaction: beginMessageLayoutTransaction(),
            completion: completion
        )
    }

    /// 在两个自定义输入面板之间直接切换，避免先回落到键盘约束导致输入栏抖动。
    private func switchCustomInputPanel(
        from source: CustomInputPanel,
        to target: CustomInputPanel,
        transaction: MessageLayoutTransaction
    ) {
        switch target {
        case .photoLibrary:
            photoLibraryInputView.isHidden = false
            photoLibraryInputView.resetDismissGestureState()
            photoLibraryInputBottomConstraint?.constant = 0
            inputBarPhotoLibraryBottomConstraint?.constant = -8
        case .emoji:
            emojiPanelView.isHidden = false
            emojiPanelBottomConstraint?.constant = 0
            inputBarEmojiBottomConstraint?.constant = -8
        }

        inputBarKeyboardBottomConstraint?.isActive = false
        inputBarPhotoLibraryBottomConstraint?.isActive = target == .photoLibrary
        inputBarEmojiBottomConstraint?.isActive = target == .emoji

        let sourceView: UIView
        let targetView: UIView
        switch source {
        case .photoLibrary:
            sourceView = photoLibraryInputView
        case .emoji:
            sourceView = emojiPanelView
        }
        switch target {
        case .photoLibrary:
            targetView = photoLibraryInputView
        case .emoji:
            targetView = emojiPanelView
        }

        sourceView.isHidden = false
        sourceView.alpha = 1

        let layoutChanges = { [weak self] in
            guard let self else { return }
            sourceView.alpha = 0
            targetView.alpha = 1
            self.completeMessageLayoutTransaction(transaction, animated: false)
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            self.hideInactiveCustomInputPanel(source)
            self.completeMessageLayoutTransaction(transaction, animated: false)
        }

        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: layoutChanges,
            completion: completion
        )
    }

    /// 只隐藏已经不是当前输入目标的旧面板，避免快速连续切换时误藏新目标。
    private func hideInactiveCustomInputPanel(_ panel: CustomInputPanel) {
        switch panel {
        case .photoLibrary:
            guard inputBarPhotoLibraryBottomConstraint?.isActive != true else { return }
            photoLibraryInputView.isHidden = true
            photoLibraryInputView.resetDismissGestureState()
        case .emoji:
            guard inputBarEmojiBottomConstraint?.isActive != true else { return }
            emojiPanelView.isHidden = true
        }
    }

    /// 切换图片库输入面板布局
    private func setPhotoLibraryInputVisible(
        _ isVisible: Bool,
        animated: Bool,
        transaction: MessageLayoutTransaction,
        completion externalCompletion: (() -> Void)? = nil
    ) {
        setCustomInputPanelVisible(
            .photoLibrary,
            isVisible: isVisible,
            animated: animated,
            transaction: transaction,
            completion: externalCompletion
        )
    }

    /// 切换表情输入面板布局
    private func setEmojiInputVisible(
        _ isVisible: Bool,
        animated: Bool,
        transaction: MessageLayoutTransaction,
        completion externalCompletion: (() -> Void)? = nil
    ) {
        setCustomInputPanelVisible(
            .emoji,
            isVisible: isVisible,
            animated: animated,
            transaction: transaction,
            completion: externalCompletion
        )
    }

    /// 切换自定义输入面板布局
    private func setCustomInputPanelVisible(
        _ panel: CustomInputPanel,
        isVisible: Bool,
        animated: Bool,
        transaction: MessageLayoutTransaction,
        completion externalCompletion: (() -> Void)? = nil
    ) {
        let panelView: UIView
        let inputPanelConstraint: NSLayoutConstraint?
        let panelBottomConstraint: NSLayoutConstraint?

        switch panel {
        case .photoLibrary:
            panelView = photoLibraryInputView
            inputPanelConstraint = inputBarPhotoLibraryBottomConstraint
            panelBottomConstraint = photoLibraryInputBottomConstraint
        case .emoji:
            panelView = emojiPanelView
            inputPanelConstraint = inputBarEmojiBottomConstraint
            panelBottomConstraint = emojiPanelBottomConstraint
        }

        guard panelView.isHidden == isVisible else {
            externalCompletion?()
            return
        }

        if isVisible {
            panelView.isHidden = false
            panelBottomConstraint?.constant = 0
            inputPanelConstraint?.constant = -8
            if panel == .photoLibrary {
                photoLibraryInputView.resetDismissGestureState()
            }
        }

        inputBarKeyboardBottomConstraint?.isActive = !isVisible
        inputBarPhotoLibraryBottomConstraint?.isActive = panel == .photoLibrary && isVisible
        inputBarEmojiBottomConstraint?.isActive = panel == .emoji && isVisible

        let layoutChanges = { [weak self] in
            guard let self else { return }
            panelView.alpha = isVisible ? 1 : 0
            self.completeMessageLayoutTransaction(transaction, animated: false)
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            if !isVisible {
                panelView.isHidden = true
                if panel == .photoLibrary {
                    self.photoLibraryInputView.resetDismissGestureState()
                }
            }
            self.completeMessageLayoutTransaction(transaction, animated: false)
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
        let layoutTransaction = beginMessageLayoutTransaction()
        let clampedTranslation = max(0, translationY)
        inputBarPhotoLibraryBottomConstraint?.constant = -8
        photoLibraryInputBottomConstraint?.constant = clampedTranslation
        completeMessageLayoutTransaction(layoutTransaction, animated: false)
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
        let cellRegistration = UICollectionView.CellRegistration<ChatMessageCell, MessageID> { [weak self] cell, _, rowID in
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
                onReeditRevokedText: { [weak self] _, text in
                    self?.reeditRevokedText(text)
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

        dataSource = UICollectionViewDiffableDataSource<Section, MessageID>(
            collectionView: collectionView
        ) { (collectionView: UICollectionView, indexPath: IndexPath, rowID: MessageID) in
            collectionView.dequeueConfiguredReusableCell(
                using: cellRegistration,
                for: indexPath,
                item: rowID
            )
        }

        var snapshot = NSDiffableDataSourceSnapshot<Section, MessageID>()
        snapshot.appendSections([.messages])
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    private func reeditRevokedText(_ text: String) {
        inputBarView.showKeyboardInput()
        inputBarView.setText(text, animated: true)
        viewModel.composerTextChanged(text)
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

        // Diffable data source 的 item identifier 使用消息 ID；内容变化通过 changedRowIDs 触发 reload。
        let newRowIDs = state.rows.map(\.id)
        let isInitialMessageRender = previousRowIDs.isEmpty && !newRowIDs.isEmpty
        let isPrependingOlderMessages = previousRowIDs.first.map { newRowIDs.contains($0) } == true
            && newRowIDs.first != previousRowIDs.first
        let didAppendNewMessage = previousRowIDs.last.map { newRowIDs.contains($0) } == true
            && newRowIDs.last != previousRowIDs.last
        let previousContentHeight: CGFloat
        let previousContentOffsetY: CGFloat
        let layoutTransaction: MessageLayoutTransaction
        let prependScrollAnchor: MessagePrependScrollAnchor?
        if isPrependingOlderMessages {
            collectionView.layoutIfNeeded()
            // 上拉历史分页说明用户正在读旧消息，此时不能再沿用贴底状态，
            // 否则刷新 overlay inset 会先把列表拉到底部，导致捕获到错误锚点。
            shouldMaintainBottomPosition = false
            previousContentHeight = collectionView.contentSize.height
            previousContentOffsetY = collectionView.contentOffset.y
            layoutTransaction = beginMessageLayoutTransaction()
            prependScrollAnchor = capturePrependingOlderMessagesAnchor(previousRowIDs: previousRowIDs, newRowIDs: newRowIDs)
        } else {
            updateCollectionViewOverlayInsets()
            previousContentHeight = collectionView.contentSize.height
            previousContentOffsetY = collectionView.contentOffset.y
            layoutTransaction = beginMessageLayoutTransaction()
            prependScrollAnchor = nil
        }
        let changedRowIDs = state.rows.compactMap { row -> MessageID? in
            previousRowsByID[row.id] == row ? nil : row.id
        }
        let appendedCount = max(0, newRowIDs.count - previousRowIDs.count)

        // 缓存最新 row 内容，供 cell registration 和下一次 render diff 对比使用。
        rowsByID = Dictionary(uniqueKeysWithValues: state.rows.map { ($0.id, $0) })
        lastRenderedRowIDs = newRowIDs
        if isInitialMessageRender {
            needsInitialBottomPositioning = true
            setInitialMessageAppearanceSuppressed(true)
        } else if newRowIDs.isEmpty {
            // 空会话没有首屏贴底过程，不能沿用上一次非空列表的透明状态。
            needsInitialBottomPositioning = false
            setInitialMessageAppearanceSuppressed(false)
        }

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

        let hasOnlyVoicePlaybackChanges = Self.containsOnlyVoicePlaybackChanges(
            previousRows: previousRowIDs.compactMap { previousRowsByID[$0] },
            newRows: state.rows
        )
        let shouldAnimateSnapshot = !isInitialMessageRender
            && !didAppendNewMessage
            && !isPrependingOlderMessages
            && !hasOnlyVoicePlaybackChanges
        dataSource.apply(snapshot, animatingDifferences: shouldAnimateSnapshot) { [weak self] in
            guard let self else { return }

            self.collectionView.layoutIfNeeded()
            if !isPrependingOlderMessages {
                self.updateCollectionViewOverlayInsets()
            }

            // 上拉加载历史消息时，保持用户当前看到的第一条附近内容不跳动。
            if isPrependingOlderMessages {
                if let prependScrollAnchor {
                    self.schedulePrependingOlderMessagesAnchorCorrection(
                        prependScrollAnchor,
                        newRowIDs: newRowIDs
                    )
                } else {
                    // 锚点不可用时保留旧策略作为兜底，避免极端布局状态下完全丢失补偿。
                    let heightDelta = self.collectionView.contentSize.height - previousContentHeight
                    let adjustedOffsetY = previousContentOffsetY + heightDelta
                    self.collectionView.setContentOffset(
                        CGPoint(x: self.collectionView.contentOffset.x, y: adjustedOffsetY),
                        animated: false
                    )
                }
            } else if isInitialMessageRender {
                if !self.resolveInitialBottomPositioningIfPossible() {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.view.layoutIfNeeded()
                        _ = self.resolveInitialBottomPositioningIfPossible()
                    }
                }
            } else if shouldRevealAppendedMessage(didAppendNewMessage: didAppendNewMessage, rows: state.rows)
                || (layoutTransaction.shouldStickToBottom && !self.isLatestRenderedMessageVisibleAboveInputBar()) {
                // 新消息追加或用户原本接近底部时，维持聊天应用常见的贴底阅读体验。
                self.scrollToBottom(animated: didAppendNewMessage)
            } else {
                // 删除、撤回或收到对方消息时，用户若已经离开底部，保留原阅读位置。
                self.preserveMessageContentOffsetIfNeeded(layoutTransaction)
                self.scheduleMessageContentOffsetPreservationIfNeeded(layoutTransaction)
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
        updateCollectionViewOverlayInsets()
        guard let announcement else { return }

        var configuration = announcementButton.configuration
        configuration?.title = "公告：\(announcement.text)"
        configuration?.image = UIImage(systemName: announcement.canEdit ? "megaphone.fill" : "megaphone")
        configuration?.imagePadding = 6
        announcementButton.configuration = configuration
        updateCollectionViewOverlayInsets()
    }

    /// 渲染 @ 成员选择器
    private func renderMentionPicker(_ picker: ChatMentionPickerState?) {
        mentionPickerStackView.arrangedSubviews.forEach { view in
            mentionPickerStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard let picker, !picker.options.isEmpty else {
            mentionPickerStackView.isHidden = true
            updateCollectionViewOverlayInsets()
            return
        }

        for option in picker.options {
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.configuration = ChatBridgeDesignSystem.makeGlassButtonConfiguration(role: option.mentionsAll ? .primary : .secondary)
            var configuration = button.configuration
            configuration?.title = "@\(option.displayName)"
            configuration?.image = UIImage(systemName: option.mentionsAll ? "person.3.fill" : "person.fill")
            configuration?.imagePadding = 4
            button.configuration = configuration
            button.accessibilityIdentifier = "chat.mentionOption.\(option.id)"
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
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
        updateCollectionViewOverlayInsets()
        mentionPickerStackView.setNeedsLayout()
        view.layoutIfNeeded()
        mentionPickerStackView.layoutIfNeeded()
        mentionPickerStackView.arrangedSubviews.forEach { $0.layoutIfNeeded() }
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
        dataSource: UICollectionViewDiffableDataSource<Section, MessageID>,
        previousRowIDs: [MessageID],
        newRowIDs: [MessageID],
        changedRowIDs: [MessageID]
    ) -> NSDiffableDataSourceSnapshot<Section, MessageID> {
        // 首次渲染时没有旧数据可对比，直接创建完整快照。
        guard !previousRowIDs.isEmpty else {
            var snapshot = NSDiffableDataSourceSnapshot<Section, MessageID>()
            snapshot.appendSections([.messages])
            snapshot.appendItems(newRowIDs, toSection: .messages)
            return snapshot
        }

        // 只有存量消息的相对顺序保持一致时，才适合在当前快照上做增量更新。
        let oldSet = Set(previousRowIDs)
        let newSet = Set(newRowIDs)
        let survivingOldIDs = previousRowIDs.filter { newSet.contains($0) }
        let survivingNewIDs = newRowIDs.filter { oldSet.contains($0) }

        // 如果中间消息发生重排，用完整快照交给 diffable data source 重新计算差异。
        guard survivingOldIDs == survivingNewIDs else {
            var snapshot = NSDiffableDataSourceSnapshot<Section, MessageID>()
            snapshot.appendSections([.messages])
            snapshot.appendItems(newRowIDs, toSection: .messages)
            return snapshot
        }

        // 从当前 data source 取快照，保留 UIKit 已知的 item 状态。
        var snapshot = dataSource.snapshot()
        if !snapshot.sectionIdentifiers.contains(.messages) {
            snapshot.appendSections([.messages])
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
            var snapshot = NSDiffableDataSourceSnapshot<Section, MessageID>()
            snapshot.appendSections([.messages])
            snapshot.appendItems(newRowIDs, toSection: .messages)
            return snapshot
        }

        // 顶部新增的历史消息插到第一条存量消息之前；没有存量消息时直接追加。
        if !prefixIDs.isEmpty {
            if let firstSurvivingID = survivingNewIDs.first {
                snapshot.insertItems(prefixIDs, beforeItem: firstSurvivingID)
            } else {
                snapshot.appendItems(prefixIDs, toSection: .messages)
            }
        }

        // 底部新增消息保持自然顺序追加到列表末尾。
        if !suffixIDs.isEmpty {
            snapshot.appendItems(suffixIDs, toSection: .messages)
        }

        // 对内容变化但 ID 未变化的消息执行轻量 reconfigure，避免不必要的删除插入动画。
        let snapshotSet = Set(snapshot.itemIdentifiers)
        let reconfiguredIDs = changedRowIDs.filter { snapshotSet.contains($0) && currentSet.contains($0) }
        if !reconfiguredIDs.isEmpty {
            snapshot.reconfigureItems(reconfiguredIDs)
        }

        return snapshot
    }

    /// 判断本次更新是否只改变语音播放 UI 临时态，用于播放进度刷新时关闭 diffable 动画。
    static func containsOnlyVoicePlaybackChanges(
        previousRows: [ChatMessageRowState],
        newRows: [ChatMessageRowState]
    ) -> Bool {
        guard previousRows.map(\.id) == newRows.map(\.id) else {
            return false
        }

        var hasChangedRow = false
        for (previousRow, newRow) in zip(previousRows, newRows) where previousRow != newRow {
            hasChangedRow = true
            guard
                previousRow.content.kind == .voice,
                newRow.content.kind == .voice,
                rowWithoutVoicePlaybackState(previousRow) == rowWithoutVoicePlaybackState(newRow)
            else {
                return false
            }
        }

        return hasChangedRow
    }

    /// 去掉语音播放中的临时字段后再比较，保留消息持久内容和发送状态变化。
    private static func rowWithoutVoicePlaybackState(_ row: ChatMessageRowState) -> ChatMessageRowState {
        guard let voice = row.voiceContent else {
            return row
        }

        let normalizedVoice = ChatMessageRowContent.VoiceContent(
            localPath: voice.localPath,
            durationMilliseconds: voice.durationMilliseconds,
            isUnplayed: voice.isUnplayed,
            isPlaying: false,
            playbackProgress: 0,
            playbackElapsedMilliseconds: 0
        )
        return row.copy(content: .voice(normalizedVoice))
    }

    /// 捕获历史消息插入前的可见旧消息锚点。
    ///
    /// 不能只依赖 `contentSize` 高度差，因为 prepend 后旧消息的时间分隔符可能重算，
    /// 已存在 cell 自身高度会变化；用可见旧消息的内容坐标做锚点，才能保持屏幕位置稳定。
    private func capturePrependingOlderMessagesAnchor(
        previousRowIDs: [MessageID],
        newRowIDs: [MessageID]
    ) -> MessagePrependScrollAnchor? {
        let newIDSet = Set(newRowIDs)
        let visibleContentRect = CGRect(origin: collectionView.contentOffset, size: collectionView.bounds.size)
            .insetBy(dx: 0, dy: -1)
        let visibleIndexPaths = collectionView.indexPathsForVisibleItems.sorted { lhs, rhs in
            lhs.item < rhs.item
        }
        var firstPartiallyVisibleAnchor: MessagePrependScrollAnchor?

        for indexPath in visibleIndexPaths where indexPath.item < previousRowIDs.count {
            let rowID = previousRowIDs[indexPath.item]
            guard newIDSet.contains(rowID) else { continue }

            if let cell = collectionView.cellForItem(at: indexPath) {
                let anchor = MessagePrependScrollAnchor(
                    rowID: rowID,
                    previousMinY: cell.frame.minY,
                    previousContentOffsetY: collectionView.contentOffset.y
                )
                // 顶部第一条有时只露出时间分隔符的一小段，prepend 后分隔符重算会让它看似位移。
                // 优先锚定第一条完整进入可见区域的旧消息，更贴近用户实际正在阅读的内容。
                if cell.frame.minY >= visibleContentRect.minY {
                    return anchor
                }
                firstPartiallyVisibleAnchor = firstPartiallyVisibleAnchor ?? anchor
                continue
            }

            if let attributes = collectionView.layoutAttributesForItem(at: indexPath) {
                let anchor = MessagePrependScrollAnchor(
                    rowID: rowID,
                    previousMinY: attributes.frame.minY,
                    previousContentOffsetY: collectionView.contentOffset.y
                )
                if attributes.frame.minY >= visibleContentRect.minY {
                    return anchor
                }
                firstPartiallyVisibleAnchor = firstPartiallyVisibleAnchor ?? anchor
            }
        }
        if let firstPartiallyVisibleAnchor {
            return firstPartiallyVisibleAnchor
        }

        // `indexPathsForVisibleItems` 在 diffable apply 前后偶尔会短暂为空；
        // 这时直接从 layout attributes 找第一个落在可见区域内的旧消息，仍然能得到稳定锚点。
        for (index, rowID) in previousRowIDs.enumerated() where newIDSet.contains(rowID) {
            let indexPath = IndexPath(item: index, section: 0)
            guard
                let attributes = collectionView.layoutAttributesForItem(at: indexPath),
                attributes.frame.intersects(visibleContentRect)
            else { continue }

            return MessagePrependScrollAnchor(
                rowID: rowID,
                previousMinY: attributes.frame.minY,
                previousContentOffsetY: collectionView.contentOffset.y
            )
        }

        return nil
    }

    /// 安排历史消息 prepend 后的锚点校正。
    ///
    /// 第一轮在快照完成后立即修正，避免插入历史消息时旧内容被整体顶下去；
    /// 第二轮放到下一次主队列，是为了覆盖自适应 cell 从估算高度稳定到真实高度的情况。
    private func schedulePrependingOlderMessagesAnchorCorrection(
        _ anchor: MessagePrependScrollAnchor,
        newRowIDs: [MessageID]
    ) {
        prependScrollAnchorCorrectionGeneration += 1
        let correctionGeneration = prependScrollAnchorCorrectionGeneration
        restorePrependingOlderMessagesAnchor(
            anchor,
            newRowIDs: newRowIDs,
            generation: correctionGeneration
        )

        DispatchQueue.main.async { [weak self] in
            self?.restorePrependingOlderMessagesAnchor(
                anchor,
                newRowIDs: newRowIDs,
                generation: correctionGeneration
            )
        }
    }

    /// 按历史消息插入前捕获的旧消息锚点恢复滚动位置。
    ///
    /// 公式含义：旧 offset 加上同一条消息在内容坐标中的顶部位移，
    /// 让这条旧消息插入前后落在屏幕上的同一个 y 位置。
    private func restorePrependingOlderMessagesAnchor(
        _ anchor: MessagePrependScrollAnchor,
        newRowIDs: [MessageID],
        generation: Int
    ) {
        guard
            generation == prependScrollAnchorCorrectionGeneration,
            !isUserControllingMessageScroll,
            lastRenderedRowIDs == newRowIDs,
            let newIndex = newRowIDs.firstIndex(of: anchor.rowID)
        else { return }

        collectionView.layoutIfNeeded()
        guard let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: newIndex, section: 0)) else {
            return
        }
        let proposedOffsetY = anchor.previousContentOffsetY + attributes.frame.minY - anchor.previousMinY
        let targetOffsetY = clampedContentOffsetY(
            proposedOffsetY,
            visibleMessageHeight: messageVisibleHeight()
        )
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: targetOffsetY),
            animated: false
        )
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

    /// 消息列表自身完成布局时，也尝试消费首屏贴底状态。
    private func handleMessageCollectionLayoutDidUpdate() {
        // 首屏快照 apply 完成时，UICollectionView 的真实 cell 高度可能还没完全稳定。
        // 这里借 collectionView 自身的 layoutSubviews 再推进一次，避免只依赖外层 viewDidLayoutSubviews。
        guard needsInitialBottomPositioning, !isResolvingInitialBottomPositioning else { return }
        _ = resolveInitialBottomPositioningIfPossible()
    }

    /// 根据覆盖层刷新全屏消息列表的可滚动可见区域。
    private func updateCollectionViewOverlayInsets() {
        guard view.window != nil else {
            guard collectionView.contentInset != .zero else { return }
            collectionView.contentInset = .zero
            collectionView.verticalScrollIndicatorInsets = .zero
            return
        }
        guard collectionView.bounds.width > 0, collectionView.bounds.height > 0 else { return }

        let collectionFrame = collectionView.convert(collectionView.bounds, to: view)
        let bottomInset = max(0, collectionFrame.maxY - messageOverlayBottomVisibleY())
        let topInset = max(0, messageOverlayTopInset(in: collectionFrame))
        let targetInsets = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)

        guard collectionView.contentInset != targetInsets else { return }
        let previousContentOffset = collectionView.contentOffset
        // 先按旧 inset 计算“列表自身是否已经贴底”，因为键盘抬起后新的覆盖区域会立刻缩小可见高度；
        // 如果之后再调用 isNearBottom()，原本贴底的列表可能被误判成离底。
        let scrollViewVisibleBottomBeforeInset = collectionView.contentOffset.y
            + collectionView.bounds.height
            - collectionView.adjustedContentInset.bottom
        let wasAtScrollViewBottomBeforeInset = scrollViewVisibleBottomBeforeInset
            >= collectionView.contentSize.height - Self.bottomReanchorTolerance
        let shouldReanchorToBottom = !isUserControllingMessageScroll
            && !lastRenderedRowIDs.isEmpty
            // 键盘抬起会先改变覆盖区域，导致 isNearBottom 变 false；
            // 只有 scroll view 原本精确贴底时才用旧底部判断兜底，避免用户离底阅读被拉回。
            && (needsInitialBottomPositioning || shouldMaintainBottomPosition || isNearBottom() || wasAtScrollViewBottomBeforeInset)
        let shouldPreserveContentOffset = !needsInitialBottomPositioning && !shouldMaintainBottomPosition
        collectionView.contentInset = targetInsets
        collectionView.verticalScrollIndicatorInsets = targetInsets
        if shouldReanchorToBottom {
            // 输入栏、@ 选择器、键盘都会改变底部覆盖范围；贴底阅读时要用新的可见底部重新对齐最后一条。
            positionLatestMessageAtVisibleBottom(animated: false)
        } else if shouldPreserveContentOffset, collectionView.contentOffset != previousContentOffset {
            // 用户已经离底查看历史时，只接受 inset 更新，不接受 UIKit 自动调整后留下的 contentOffset 漂移。
            collectionView.setContentOffset(previousContentOffset, animated: false)
        }
    }

    /// 顶部公告作为覆盖层时，消息内容需要避开公告和安全区。
    private func messageOverlayTopInset(in collectionFrame: CGRect) -> CGFloat {
        let safeTopY = view.safeAreaInsets.top
        let hasVisibleBanner = topBannerStackView.arrangedSubviews.contains { !$0.isHidden }
        guard hasVisibleBanner else {
            return safeTopY - collectionFrame.minY
        }

        let bannerFrame = topBannerStackView.convert(topBannerStackView.bounds, to: view)
        return max(safeTopY, bannerFrame.maxY + 8) - collectionFrame.minY
    }

    /// 输入栏和 @ 选择器作为覆盖层时，消息内容只能显示到覆盖层上方。
    private func messageOverlayBottomVisibleY() -> CGFloat {
        let overlayView = mentionPickerStackView.isHidden ? inputBarView : mentionPickerStackView
        let overlayFrame = overlayView.convert(overlayView.bounds, to: view)
        return overlayFrame.minY - 8
    }

    /// 判断消息列表是否接近底部
    private func isNearBottom() -> Bool {
        let contentBottomY = collectionView.contentSize.height
        return messageVisibleBottomY() >= contentBottomY - 80
    }

    /// 开始一次会影响输入区域覆盖范围的布局事务。
    private func beginMessageLayoutTransaction() -> MessageLayoutTransaction {
        MessageLayoutTransaction(
            shouldStickToBottom: shouldStickToBottomForLayoutChange(),
            previousContentOffset: collectionView.contentOffset
        )
    }

    /// 完成布局事务：贴底阅读时露出最新消息，离底阅读时不抢走历史位置。
    private func completeMessageLayoutTransaction(_ transaction: MessageLayoutTransaction, animated: Bool) {
        view.layoutIfNeeded()
        updateCollectionViewOverlayInsets()
        if transaction.shouldStickToBottom {
            scrollToBottom(animated: animated)
        } else {
            preserveMessageContentOffsetIfNeeded(transaction)
        }
    }

    /// 用户手动离底后，输入栏或面板变化只能刷新 inset，不能把列表推回底部。
    private func preserveMessageContentOffsetIfNeeded(_ transaction: MessageLayoutTransaction) {
        guard
            !needsInitialBottomPositioning,
            !transaction.shouldStickToBottom,
            collectionView.contentOffset != transaction.previousContentOffset
        else { return }
        collectionView.setContentOffset(transaction.previousContentOffset, animated: false)
    }

    /// 自适应 cell 高度可能在快照完成后一轮才稳定；离底阅读时需要再校正一次，
    /// 防止收到对方消息后 UIKit 的布局稳定过程把用户正在看的历史位置向下推。
    private func scheduleMessageContentOffsetPreservationIfNeeded(_ transaction: MessageLayoutTransaction) {
        let correctionGeneration = bottomPositionCorrectionGeneration
        DispatchQueue.main.async { [weak self] in
            guard
                let self,
                correctionGeneration == self.bottomPositionCorrectionGeneration
            else { return }

            self.collectionView.layoutIfNeeded()
            self.preserveMessageContentOffsetIfNeeded(transaction)

            DispatchQueue.main.async { [weak self] in
                guard
                    let self,
                    correctionGeneration == self.bottomPositionCorrectionGeneration
                else { return }

                self.collectionView.layoutIfNeeded()
                self.preserveMessageContentOffsetIfNeeded(transaction)
            }
        }
    }

    /// 判断本次布局变化是否应该保持贴底。
    private func shouldStickToBottomForLayoutChange() -> Bool {
        guard !isUserControllingMessageScroll else { return false }
        if needsInitialBottomPositioning {
            // 首屏还没完成最终贴底时，键盘或输入栏高度变化仍属于入场布局；
            // 此时必须继续维护底部，否则首次点输入框可能把最新消息留在键盘后面。
            shouldMaintainBottomPosition = true
            return true
        }
        // 只有用户本来就在底部附近时才进入贴底维护，避免收到消息打断查看历史。
        let shouldStick = shouldMaintainBottomPosition || isNearBottom()
        if shouldStick {
            shouldMaintainBottomPosition = true
        }
        return shouldStick
    }

    /// 追加自己发出的消息需要立即露出；收到的消息只有用户原本在底部时才自动贴底。
    private func shouldRevealAppendedMessage(didAppendNewMessage: Bool, rows: [ChatMessageRowState]) -> Bool {
        guard didAppendNewMessage else { return false }
        return rows.last?.isOutgoing == true
    }

    /// 滚动到最新消息
    private func scrollToBottom(animated: Bool) {
        guard !lastRenderedRowIDs.isEmpty else { return }
#if DEBUG
        lastScrollToBottomRequestedAnimationForTesting = animated
#endif
        if animated {
            collectionView.layoutIfNeeded()
            updateCollectionViewOverlayInsets()
            positionLatestMessageAtVisibleBottom(animated: true)
            scheduleAnimatedBottomPositionCorrection(latestMessageID: lastRenderedRowIDs.last)
            // 程序化贴底表示用户仍在阅读最新消息，不能立刻清掉贴底状态；
            // 首进页面呼出键盘时，keyboardLayoutGuide 可能晚一轮才稳定，需要后续布局继续按贴底处理。
            shouldMaintainBottomPosition = !isUserControllingMessageScroll
            return
        }
        for pass in 0..<3 {
            collectionView.layoutIfNeeded()
            updateCollectionViewOverlayInsets()
            positionLatestMessageAtVisibleBottom(animated: animated && pass == 0)
        }
        // 只有用户拖拽/减速路径会主动关闭贴底；普通布局校正后仍保留状态，
        // 避免键盘或输入栏后续高度变化把最新消息留在覆盖区域下面。
        shouldMaintainBottomPosition = !isUserControllingMessageScroll
    }

    /// 动画贴底后安排无动画校正，覆盖图片/视频自适应高度晚于滚动动画稳定的情况。
    private func scheduleAnimatedBottomPositionCorrection(latestMessageID: MessageID?) {
        guard let latestMessageID else { return }
        bottomPositionCorrectionGeneration += 1
        let correctionGeneration = bottomPositionCorrectionGeneration
        DispatchQueue.main.async { [weak self] in
            self?.performAnimatedBottomPositionCorrectionIfNeeded(
                generation: correctionGeneration,
                latestMessageID: latestMessageID
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.performAnimatedBottomPositionCorrectionIfNeeded(
                generation: correctionGeneration,
                latestMessageID: latestMessageID
            )
        }
    }

    /// 执行动画后的贴底校正；只认同一条最新消息，避免旧动画抢回后续阅读位置。
    private func performAnimatedBottomPositionCorrectionIfNeeded(generation: Int, latestMessageID: MessageID) {
        guard
            generation == bottomPositionCorrectionGeneration,
            !isUserControllingMessageScroll,
            lastRenderedRowIDs.last == latestMessageID
        else { return }

        // 图片/视频 cell 从估算高度变成真实缩略图高度后，列表可能瞬间“不接近底部”；
        // 这属于布局尚未稳定，不代表用户主动离底，所以不能再用 isNearBottom 拦截校正。
        collectionView.layoutIfNeeded()
        updateCollectionViewOverlayInsets()
        positionLatestMessageAtVisibleBottom(animated: false)
    }

    /// 系统键盘的 `keyboardLayoutGuide` 有时会晚于 `keyboardWillChangeFrame` 动画事务稳定。
    /// 键盘出现前已经贴底时，额外在下一轮和动画结束后校正一次，避免最新消息停在输入栏后面。
    private func scheduleKeyboardBottomPositionCorrectionIfNeeded(shouldStickToBottom: Bool, duration: TimeInterval) {
        guard shouldStickToBottom || needsInitialBottomPositioning else { return }
        keyboardBottomCorrectionGeneration += 1
        let correctionGeneration = keyboardBottomCorrectionGeneration
        // 第一次 async 覆盖“keyboardWillChangeFrame 已到、keyboardLayoutGuide 下一轮才更新”的情况；
        // 第二次覆盖系统键盘动画结束后输入栏最终高度才稳定的情况。
        let correctionDelays: [TimeInterval] = [0, max(0.05, duration + 0.05)]

        for delay in correctionDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.performKeyboardBottomPositionCorrectionIfNeeded(
                    generation: correctionGeneration,
                    shouldStickToBottom: shouldStickToBottom
                )
            }
        }
    }

    /// 执行键盘后的贴底校正；只在原本贴底或首屏定位未完成时触发，不抢用户离底阅读位置。
    private func performKeyboardBottomPositionCorrectionIfNeeded(
        generation: Int,
        shouldStickToBottom: Bool
    ) {
        guard
            generation == keyboardBottomCorrectionGeneration,
            !isUserControllingMessageScroll,
            !lastRenderedRowIDs.isEmpty
        else { return }

        // 先让 inputBar 和 collectionView 吃掉 keyboardLayoutGuide 的最新约束结果，
        // 再刷新 overlay inset，否则会用旧的输入栏位置计算最后一条消息的可见底部。
        view.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        updateCollectionViewOverlayInsets()

        if needsInitialBottomPositioning {
            // 首屏定位尚未完成时，继续走首屏收敛逻辑；它会等 cell 和输入栏都有真实尺寸。
            _ = resolveInitialBottomPositioningIfPossible()
        } else if shouldStickToBottom || !isLatestRenderedMessageVisibleAboveInputBar() {
            // 正常贴底阅读时重新对齐；如果最新消息已经被输入栏遮住，也要兜底拉出可见区域。
            scrollToBottom(animated: false)
        }
    }

    /// 按当前 inset 把最新消息对齐到消息可见区域底部。
    private func positionLatestMessageAtVisibleBottom(animated: Bool) {
        let lastIndexPath = IndexPath(item: lastRenderedRowIDs.count - 1, section: 0)
        guard let attributes = collectionView.layoutAttributesForItem(at: lastIndexPath) else {
            let fallbackOffsetY = collectionView.contentSize.height - messageVisibleHeight()
            let targetOffsetY = clampedContentOffsetY(
                fallbackOffsetY,
                visibleMessageHeight: messageVisibleHeight()
            )
            collectionView.setContentOffset(
                CGPoint(x: collectionView.contentOffset.x, y: targetOffsetY),
                animated: animated
            )
            return
        }

        let proposedOffsetY = collectionView.contentOffset.y
            + attributes.frame.maxY
            - messageVisibleBottomY()
        let targetOffsetY = clampedContentOffsetY(
            proposedOffsetY,
            visibleMessageHeight: messageVisibleHeight()
        )
        guard abs(collectionView.contentOffset.y - targetOffsetY) > 1 else { return }
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: targetOffsetY),
            animated: animated
        )
    }

    /// 首屏贴底只在视图已经入窗且输入栏完成布局后消费，避免入场阶段出现二次位移。
    @discardableResult
    private func resolveInitialBottomPositioningIfPossible() -> Bool {
        guard needsInitialBottomPositioning, !lastRenderedRowIDs.isEmpty else { return false }
        guard view.window != nil, collectionView.bounds.height > 0 else {
            return false
        }

        isResolvingInitialBottomPositioning = true
        defer {
            isResolvingInitialBottomPositioning = false
        }

        view.layoutIfNeeded()
        guard inputBarView.bounds.height > 0 else { return false }

        collectionView.layoutIfNeeded()
        updateCollectionViewOverlayInsets()
        guard collectionView.contentSize.height > 0 else { return false }

        scrollToBottom(animated: false)
        positionContentBottomAtVisibleBottom(animated: false)
        let didFinishInitialBottomPositioning = isLatestRenderedMessageVisibleAboveInputBar()
        needsInitialBottomPositioning = !didFinishInitialBottomPositioning
        if didFinishInitialBottomPositioning {
            setInitialMessageAppearanceSuppressed(false)
        }
        return true
    }

    /// 控制首屏消息列表显隐；使用 alpha 保留 collection view 布局和 cell 生成，避免 isHidden 中断首屏定位。
    private func setInitialMessageAppearanceSuppressed(_ isSuppressed: Bool) {
        let targetAlpha: CGFloat = isSuppressed ? 0 : 1
        guard isSuppressingInitialMessageAppearance != isSuppressed || collectionView.alpha != targetAlpha else { return }
        isSuppressingInitialMessageAppearance = isSuppressed
        collectionView.alpha = targetAlpha
    }

    /// 判断最新消息 cell 是否已经真实生成，并位于输入栏覆盖区域上方。
    private func isLatestRenderedMessageVisibleAboveInputBar() -> Bool {
        guard !lastRenderedRowIDs.isEmpty else { return false }
        let lastIndexPath = IndexPath(item: lastRenderedRowIDs.count - 1, section: 0)
        guard let cell = collectionView.cellForItem(at: lastIndexPath) else { return false }

        let cellFrame = cell.convert(cell.bounds, to: view)
        let inputFrame = inputBarView.convert(inputBarView.bounds, to: view)
        return cellFrame.maxY <= inputFrame.minY + 1
    }

    /// 首屏估算高度稳定前，使用 contentSize 兜底对齐到底部，确保最后一条进入可见区域。
    private func positionContentBottomAtVisibleBottom(animated: Bool) {
        var previousContentHeight = CGFloat.nan
        for pass in 0..<8 {
            collectionView.layoutIfNeeded()
            let visibleHeight = messageVisibleHeight()
            let targetOffsetY = clampedContentOffsetY(
                collectionView.contentSize.height - visibleHeight,
                visibleMessageHeight: visibleHeight
            )
            if abs(collectionView.contentOffset.y - targetOffsetY) > 1 {
                collectionView.setContentOffset(
                    CGPoint(x: collectionView.contentOffset.x, y: targetOffsetY),
                    animated: animated && pass == 0
                )
            }
            collectionView.layoutIfNeeded()

            let didReachTarget = abs(collectionView.contentOffset.y - targetOffsetY) <= 1
            let didStabilizeHeight = previousContentHeight.isNaN
                ? false
                : abs(collectionView.contentSize.height - previousContentHeight) <= 1
            if didReachTarget && didStabilizeHeight {
                break
            }
            previousContentHeight = collectionView.contentSize.height
        }
    }

    /// 最新消息可见下边界，使用 content 坐标便于和 layout attributes 对齐。
    private func messageVisibleBottomY() -> CGFloat {
        let collectionFrame = collectionView.convert(collectionView.bounds, to: view)
        let insetVisibleBottomY = collectionFrame.maxY - collectionView.adjustedContentInset.bottom
        let overlayVisibleBottomY = view.window == nil
            ? insetVisibleBottomY
            : messageOverlayBottomVisibleY()
        let visibleBottomY = min(insetVisibleBottomY, overlayVisibleBottomY)
        return collectionView.contentOffset.y + max(0, visibleBottomY - collectionFrame.minY)
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
        )
        return min(max(proposedOffsetY, minOffsetY), maxOffsetY)
    }
}

/// 聊天输入栏高度变化协调
extension ChatViewController: ChatInputBarLayoutDelegate {
    func chatInputBarWillChangeHeight(_ inputBar: ChatInputBarView) -> Bool {
        let transaction = beginMessageLayoutTransaction()
        pendingInputBarLayoutTransaction = transaction
        return transaction.shouldStickToBottom
    }

    func chatInputBar(_ inputBar: ChatInputBarView, didChangeHeightKeepingBottom shouldStickToBottom: Bool) {
        let transaction = pendingInputBarLayoutTransaction ?? MessageLayoutTransaction(
            shouldStickToBottom: shouldStickToBottom,
            previousContentOffset: collectionView.contentOffset
        )
        pendingInputBarLayoutTransaction = nil
        completeMessageLayoutTransaction(transaction, animated: false)
    }
}

/// 图片库输入面板生命周期回调
extension ChatViewController: ChatPhotoLibraryInputViewDelegate {
    func chatPhotoLibraryInputView(_ inputView: ChatPhotoLibraryInputView, didStartSelection preview: ChatPhotoLibrarySelectionPreview) {
        upsertPendingAttachmentPreview(
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

    func chatPhotoLibraryInputView(_ inputView: ChatPhotoLibraryInputView, didPrepareSelection preparedMedia: ChatPhotoLibraryPreparedMedia) {
        pendingComposerMediaByID[preparedMedia.id] = preparedMedia.media
        upsertPendingAttachmentPreview(
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

    func chatPhotoLibraryInputView(_ inputView: ChatPhotoLibraryInputView, didRemoveSelection id: String) {
        removePendingAttachment(id: id)
    }

    func chatPhotoLibraryInputView(_ inputView: ChatPhotoLibraryInputView, didFailSelection id: String, message: String) {
        removePendingAttachment(id: id)
        showTransientRecordingMessage(message)
    }

    func chatPhotoLibraryInputView(_ inputView: ChatPhotoLibraryInputView, didReachSelectionLimit message: String) {
        showTransientRecordingMessage(message)
    }

    func chatPhotoLibraryInputView(_ inputView: ChatPhotoLibraryInputView, didChangeDismissPanTranslation translationY: CGFloat) {
        applyPhotoLibraryDismissPanTranslation(translationY)
    }

    func chatPhotoLibraryInputViewDidRequestDismiss(_ inputView: ChatPhotoLibraryInputView) {
        hidePhotoLibraryInput(animated: true)
    }
}

/// 聊天消息列表滚动回调
extension ChatViewController: UICollectionViewDelegate {
    /// 首屏快照可能先更新 item 数量、后回调 apply completion；可见 cell 生成时也要尝试完成贴底。
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard needsInitialBottomPositioning else { return }
        _ = resolveInitialBottomPositioningIfPossible()
    }

    /// 用户开始拖动时取消程序化贴底动画，避免新消息追加后的滚动动画抢回手势。
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        collectionView.layer.removeAllAnimations()
        bottomPositionCorrectionGeneration += 1
        prependScrollAnchorCorrectionGeneration += 1
        isUserControllingMessageScroll = true
        shouldMaintainBottomPosition = false
    }

    /// 滚动到顶部附近时加载更早消息
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let topThreshold = -scrollView.adjustedContentInset.top + 120
        if scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating {
            shouldMaintainBottomPosition = false
        } else if scrollView.contentOffset.y <= topThreshold, !needsInitialBottomPositioning {
            // 历史分页可能由测试或代码直接把列表推到顶部触发；即使没有用户拖拽回调，
            // 进入顶部阅读也必须清掉旧的贴底状态，避免 prepend 时被重新拉回底部。
            shouldMaintainBottomPosition = false
        }

        guard !snapshotRenderCoordinator.isApplying, !needsInitialBottomPositioning else { return }

        if scrollView.contentOffset.y <= topThreshold {
            viewModel.loadOlderMessagesIfNeeded()
        }
    }

    /// 用户拖拽结束且不会继续减速时，根据最终位置恢复是否贴底。
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        finishUserMessageScrollInteraction()
    }

    /// 减速结束后，根据最终位置恢复是否贴底。
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finishUserMessageScrollInteraction()
    }

    /// 结束用户滚动控制；只有最终仍接近底部时才重新启用自动贴底。
    private func finishUserMessageScrollInteraction() {
        isUserControllingMessageScroll = false
        shouldMaintainBottomPosition = isNearBottom()
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
