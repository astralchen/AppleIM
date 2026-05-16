//
//  ChatPhotoLibraryInputView.swift
//  AppleIM
//

import UIKit
@preconcurrency import Photos
import UniformTypeIdentifiers

/// 图片库选择预览信息
@MainActor
struct ChatPhotoLibrarySelectionPreview {
    /// Photos 资源本地 ID
    let id: String
    /// 预览缩略图
    let image: UIImage?
    /// 预览标题
    let title: String
    /// 视频时长文本
    let durationText: String?
    /// 是否为视频资源
    let isVideo: Bool
}

/// 已准备完成、可进入聊天输入栏的媒体
@MainActor
struct ChatPhotoLibraryPreparedMedia {
    /// Photos 资源本地 ID
    let id: String
    /// 准备完成后的预览信息
    let preview: ChatPhotoLibrarySelectionPreview
    /// 聊天输入栏可发送的媒体
    let media: ChatComposerMedia
}

/// 图片库输入面板对外发布的用户动作。
@MainActor
enum ChatPhotoLibraryInputAction {
    /// 开始选择某个资源并进入准备态。
    case selectionStarted(ChatPhotoLibrarySelectionPreview)
    /// 资源准备完成。
    case selectionPrepared(ChatPhotoLibraryPreparedMedia)
    /// 取消选择某个资源。
    case selectionRemoved(String)
    /// 资源准备失败。
    case selectionFailed(id: String, message: String)
    /// 达到选择数量上限。
    case selectionLimitReached(String)
    /// 请求关闭图片库面板。
    case dismissRequested
}

/// 图片库输入面板生命周期与布局协调代理。
@MainActor
protocol ChatPhotoLibraryInputViewDelegate: AnyObject {
    func chatPhotoLibraryInputView(_ inputView: ChatPhotoLibraryInputView, didStartSelection preview: ChatPhotoLibrarySelectionPreview)
    func chatPhotoLibraryInputView(_ inputView: ChatPhotoLibraryInputView, didPrepareSelection preparedMedia: ChatPhotoLibraryPreparedMedia)
    func chatPhotoLibraryInputView(_ inputView: ChatPhotoLibraryInputView, didRemoveSelection id: String)
    func chatPhotoLibraryInputView(_ inputView: ChatPhotoLibraryInputView, didFailSelection id: String, message: String)
    func chatPhotoLibraryInputView(_ inputView: ChatPhotoLibraryInputView, didReachSelectionLimit message: String)
    func chatPhotoLibraryInputView(_ inputView: ChatPhotoLibraryInputView, didChangeDismissPanTranslation translationY: CGFloat)
    func chatPhotoLibraryInputViewDidRequestDismiss(_ inputView: ChatPhotoLibraryInputView)
}

/// 图片库多选状态
nonisolated struct ChatPhotoLibrarySelectionState {
    /// 选择切换结果
    enum ToggleResult: Equatable {
        /// 已选中
        case selected
        /// 已取消选择
        case deselected
        /// 已达到选择上限
        case limitReached
    }

    /// 最大可选择数量
    static let maxSelectionCount = 9
    /// 当前已选资源 ID，保留选择顺序
    private(set) var selectedAssetIDs: [String] = []

    /// 切换资源选择状态
    mutating func toggle(assetID: String) -> ToggleResult {
        if let existingIndex = selectedAssetIDs.firstIndex(of: assetID) {
            selectedAssetIDs.remove(at: existingIndex)
            return .deselected
        }

        guard selectedAssetIDs.count < Self.maxSelectionCount else {
            return .limitReached
        }

        selectedAssetIDs.append(assetID)
        return .selected
    }

    /// 移除指定资源选择
    mutating func remove(assetID: String) {
        selectedAssetIDs.removeAll { $0 == assetID }
    }

    /// 清空所有选择
    mutating func removeAll() {
        selectedAssetIDs.removeAll()
    }

    /// 判断资源是否已选中
    func contains(assetID: String) -> Bool {
        selectedAssetIDs.contains(assetID)
    }

    /// 返回资源的选择序号
    func selectionNumber(for assetID: String) -> Int? {
        selectedAssetIDs.firstIndex(of: assetID).map { $0 + 1 }
    }
}

/// 聊天页图片库输入面板
@MainActor
final class ChatPhotoLibraryInputView: UIControl {
    /// 最近一次发布的用户动作。
    private(set) var lastAction: ChatPhotoLibraryInputAction?
    /// 生命周期与布局协调代理。
    weak var inputDelegate: ChatPhotoLibraryInputViewDelegate?

    /// 面板固定高度
    static let panelHeight: CGFloat = 335
    /// 图片网格间距
    private static let interItemSpacing: CGFloat = 2
    /// 下滑关闭最小距离
    private static let dismissDistanceThreshold: CGFloat = 92
    /// 下滑关闭最小速度
    private static let dismissVelocityThreshold: CGFloat = 780
    /// 临时媒体文件管理服务，可在测试中替换。
    static var temporaryMediaFileManager: any TemporaryMediaFileManaging = DefaultTemporaryMediaFileManager.shared
    /// 系统风格的动态拖拽提示条颜色
    private static func grabberColor(for traits: UITraitCollection) -> UIColor {
        switch (traits.userInterfaceStyle, traits.accessibilityContrast) {
        case (.dark, .high):
            return UIColor.white.withAlphaComponent(0.84)
        case (.dark, _):
            return UIColor.white.withAlphaComponent(0.68)
        case (_, .high):
            return UIColor.black.withAlphaComponent(0.64)
        default:
            return UIColor.black.withAlphaComponent(0.48)
        }
    }

    /// 顶部拖拽提示条
    private let grabberView = UIView()
    /// 图片和视频网格
    private let collectionView: UICollectionView
    /// 授权或空状态容器
    private let statusView = UIView()
    /// 授权或空状态文案
    private let statusLabel = UILabel()
    /// 状态操作按钮
    private let statusButton = UIButton(type: .system)
    /// 下滑关闭手势
    private lazy var dismissPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
    /// Photos 图片请求管理器
    private let imageManager = PHCachingImageManager()
    /// Photos 资源文件请求管理器
    private let resourceManager = PHAssetResourceManager.default()

    /// 当前拉取到的 Photos 资源
    private var assets: PHFetchResult<PHAsset>?
    /// 当前网格展示的资源 ID 顺序
    private var representedAssetIDs: [String] = []
    /// 图片库网格 diffable 数据源。
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>?
    /// 当前多选状态
    private var selectionState = ChatPhotoLibrarySelectionState()
    /// 当前下滑关闭手势是否从顶部把手区域开始
    private var dismissPanStartedInHeader = false

    /// 输入面板固有尺寸
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.panelHeight)
    }

    /// 判断下滑关闭手势是否应该开始
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dismissPanGesture else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }

        let location = gestureRecognizer.location(in: self)
        dismissPanStartedInHeader = location.y <= 64

        let velocity = dismissPanGesture.velocity(in: self)
        let isMostlyVerticalDown = velocity.y > abs(velocity.x)
        guard isMostlyVerticalDown else { return false }

        return dismissPanStartedInHeader || isCollectionViewAtTop()
    }

    /// 初始化图片库输入面板
    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = Self.interItemSpacing
        layout.minimumInteritemSpacing = Self.interItemSpacing
        layout.sectionInset = .zero
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame.isEmpty ? CGRect(x: 0, y: 0, width: 0, height: Self.panelHeight) : frame)
        configureView()
    }

    /// 从 storyboard/xib 初始化图片库输入视图
    required init?(coder: NSCoder) {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = Self.interItemSpacing
        layout.minimumInteritemSpacing = Self.interItemSpacing
        layout.sectionInset = .zero
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(coder: coder)
        configureView()
    }

    /// 刷新照片库授权状态并加载资源
    func refreshAuthorization() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch status {
        case .authorized, .limited:
            loadAssets()
        case .notDetermined:
            showStatus("Allow photo access to choose images and videos.", buttonTitle: nil, action: nil)
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshAuthorization()
                }
            }
        case .denied, .restricted:
            showStatus(
                "Photo access is disabled.",
                buttonTitle: "Open Settings",
                action: { [weak self] in
                    self?.openSettings()
                }
            )
        @unknown default:
            showStatus("Photo access is unavailable.", buttonTitle: nil, action: nil)
        }
    }

    /// 配置面板视图层级和约束
    private func configureView() {
        backgroundColor = .clear
        clipsToBounds = true
        layer.cornerRadius = 22
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer.cornerCurve = .continuous

        grabberView.translatesAutoresizingMaskIntoConstraints = false
        grabberView.backgroundColor = UIColor { traits in
            Self.grabberColor(for: traits)
        }
        grabberView.layer.cornerRadius = 3
        grabberView.layer.shadowColor = UIColor.black.cgColor
        grabberView.layer.shadowOpacity = 0.18
        grabberView.layer.shadowRadius = 2
        grabberView.layer.shadowOffset = CGSize(width: 0, height: 1)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.contentInset = .zero
        collectionView.delegate = self
        collectionView.accessibilityIdentifier = "chat.photoLibraryGrid"
        configureDataSource()

        statusView.translatesAutoresizingMaskIntoConstraints = false
        statusView.isHidden = true

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        statusButton.translatesAutoresizingMaskIntoConstraints = false
        statusButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        statusButton.addTarget(self, action: #selector(statusButtonTapped), for: .touchUpInside)

        dismissPanGesture.delegate = self
        addGestureRecognizer(dismissPanGesture)
        collectionView.panGestureRecognizer.require(toFail: dismissPanGesture)

        addSubview(collectionView)
        addSubview(grabberView)
        addSubview(statusView)
        statusView.addSubview(statusLabel)
        statusView.addSubview(statusButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.panelHeight),

            grabberView.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            grabberView.centerXAnchor.constraint(equalTo: centerXAnchor),
            grabberView.widthAnchor.constraint(equalToConstant: 54),
            grabberView.heightAnchor.constraint(equalToConstant: 6),

            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),

            statusView.topAnchor.constraint(equalTo: topAnchor),
            statusView.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusView.bottomAnchor.constraint(equalTo: bottomAnchor),

            statusLabel.centerYAnchor.constraint(equalTo: statusView.centerYAnchor, constant: -18),
            statusLabel.leadingAnchor.constraint(equalTo: statusView.layoutMarginsGuide.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: statusView.layoutMarginsGuide.trailingAnchor, constant: -20),

            statusButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            statusButton.centerXAnchor.constraint(equalTo: statusView.centerXAnchor)
        ])
    }

    /// 重置下滑手势带来的临时位移
    func resetDismissGestureState() {
        notifyDismissPanChanged(0)
    }

    /// 根据下滑距离和速度判断是否关闭
    static func shouldDismissForPan(translationY: CGFloat, velocityY: CGFloat) -> Bool {
        translationY > dismissDistanceThreshold || velocityY > dismissVelocityThreshold
    }

    /// 处理下滑关闭手势
    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        let translationY = max(0, gesture.translation(in: self).y)

        switch gesture.state {
        case .began, .changed:
            clampCollectionViewToTopIfNeeded()
            notifyDismissPanChanged(translationY)
        case .ended:
            let velocityY = gesture.velocity(in: self).y
            if Self.shouldDismissForPan(translationY: translationY, velocityY: velocityY) {
                emit(.dismissRequested)
                inputDelegate?.chatPhotoLibraryInputViewDidRequestDismiss(self)
            } else {
                animateDismissGestureReset()
            }
        case .cancelled, .failed:
            animateDismissGestureReset()
        default:
            break
        }
    }

    /// 下滑未达到关闭阈值时回弹
    private func animateDismissGestureReset() {
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: { [weak self] in
                self?.resetDismissGestureState()
            }
        )
    }

    /// 判断滚动网格是否位于顶部
    private func isCollectionViewAtTop() -> Bool {
        guard !collectionView.isHidden else { return true }
        return collectionView.contentOffset.y <= -collectionView.adjustedContentInset.top + 1
    }

    /// 关闭手势接管后，避免网格继续橡皮筋下拉露出空白
    private func clampCollectionViewToTopIfNeeded() {
        let topOffsetY = -collectionView.adjustedContentInset.top
        guard collectionView.contentOffset.y < topOffsetY else { return }
        collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: topOffsetY), animated: false)
    }

    /// 加载最近的图片和视频资源
    private func loadAssets() {
        let options = PHFetchOptions()
        options.fetchLimit = 180
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )

        let fetchResult = PHAsset.fetchAssets(with: options)
        assets = fetchResult
        representedAssetIDs = (0..<fetchResult.count).map { fetchResult.object(at: $0).localIdentifier }
        collectionView.isHidden = fetchResult.count == 0
        statusView.isHidden = fetchResult.count != 0
        if fetchResult.count == 0 {
            showStatus("No recent photos or videos.", buttonTitle: nil, action: nil)
        } else {
            statusButtonAction = nil
            applyAssetSnapshot()
        }
    }

    /// 配置图片库网格数据源。
    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<ChatPhotoLibraryCell, String> { [weak self] cell, indexPath, assetID in
            guard
                let self,
                let asset = self.asset(at: indexPath),
                asset.localIdentifier == assetID
            else {
                return
            }

            cell.configure(
                asset: asset,
                imageManager: self.imageManager,
                selectionNumber: self.selectionState.selectionNumber(for: assetID)
            )
        }

        dataSource = UICollectionViewDiffableDataSource<Int, String>(
            collectionView: collectionView
        ) { collectionView, indexPath, assetID in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: assetID)
        }
    }

    /// 应用当前资源快照。
    private func applyAssetSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(representedAssetIDs, toSection: 0)
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    /// 状态按钮点击动作
    private var statusButtonAction: (() -> Void)?

    /// 展示授权、空状态或错误提示
    private func showStatus(_ message: String, buttonTitle: String?, action: (() -> Void)?) {
        collectionView.isHidden = true
        statusView.isHidden = false
        statusLabel.text = message
        statusButton.setTitle(buttonTitle, for: .normal)
        statusButton.isHidden = buttonTitle == nil
        statusButtonAction = action
    }

    /// 执行当前状态按钮动作
    @objc private func statusButtonTapped() {
        statusButtonAction?()
    }

    /// 打开系统设置页
    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// 根据 indexPath 获取 Photos 资源
    private func asset(at indexPath: IndexPath) -> PHAsset? {
        guard let assets, indexPath.item < assets.count else { return nil }
        return assets.object(at: indexPath.item)
    }

    /// 外部移除已选资源
    func removeSelection(assetID: String) {
        guard selectionState.contains(assetID: assetID) else { return }
        selectionState.remove(assetID: assetID)
        reloadAssetCell(assetID: assetID)
    }

    /// 外部清空所有选择
    func clearSelection() {
        let selectedIDs = selectionState.selectedAssetIDs
        selectionState.removeAll()
        selectedIDs.forEach(reloadAssetCell(assetID:))
    }

    /// 选择或取消选择资源并开始准备媒体
    private func selectAsset(_ asset: PHAsset) {
        switch selectionState.toggle(assetID: asset.localIdentifier) {
        case .selected:
            reloadAssetCell(assetID: asset.localIdentifier)
        case .deselected:
            reloadAssetCell(assetID: asset.localIdentifier)
            emit(.selectionRemoved(asset.localIdentifier))
            inputDelegate?.chatPhotoLibraryInputView(self, didRemoveSelection: asset.localIdentifier)
            return
        case .limitReached:
            notifySelectionLimitReached("You can select up to 9 photos or videos.")
            return
        }

        notifySelectionStarted(
            ChatPhotoLibrarySelectionPreview(
                id: asset.localIdentifier,
                image: nil,
                title: asset.mediaType == .video ? "Preparing video..." : "Preparing image...",
                durationText: Self.durationText(for: asset),
                isVideo: asset.mediaType == .video
            )
        )
        requestPreview(for: asset) { [weak self] preview in
            guard let self, self.selectionState.contains(assetID: asset.localIdentifier) else { return }
            self.notifySelectionStarted(preview)
            self.prepareMedia(for: asset, preview: preview)
        }
    }

    /// 刷新指定资源对应的单元格
    private func reloadAssetCell(assetID: String) {
        guard let index = representedAssetIDs.firstIndex(of: assetID) else { return }
        if var snapshot = dataSource?.snapshot(), snapshot.indexOfItem(assetID) != nil {
            snapshot.reloadItems([assetID])
            dataSource?.apply(snapshot, animatingDifferences: false)
        } else {
            collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
        }
    }

    /// 请求用于输入栏展示的缩略图预览
    private func requestPreview(
        for asset: PHAsset,
        completion: @escaping (ChatPhotoLibrarySelectionPreview) -> Void
    ) {
        let targetSize = CGSize(width: 240, height: 240)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true

        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            let preview = ChatPhotoLibrarySelectionPreview(
                id: asset.localIdentifier,
                image: image,
                title: asset.mediaType == .video ? "Preparing video..." : "Preparing image...",
                durationText: Self.durationText(for: asset),
                isVideo: asset.mediaType == .video
            )
            Task { @MainActor in
                completion(preview)
            }
        }
    }

    /// 根据资源类型准备图片或视频媒体
    private func prepareMedia(for asset: PHAsset, preview: ChatPhotoLibrarySelectionPreview) {
        switch asset.mediaType {
        case .image:
            prepareImage(for: asset, preview: preview)
        case .video:
            prepareVideo(for: asset, preview: preview)
        default:
            selectionState.remove(assetID: asset.localIdentifier)
            reloadAssetCell(assetID: asset.localIdentifier)
            notifySelectionFailed(id: asset.localIdentifier, message: "Unsupported media")
        }
    }

    /// 读取图片二进制数据并生成发送媒体
    private func prepareImage(for asset: PHAsset, preview: ChatPhotoLibrarySelectionPreview) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current

        imageManager.requestImageDataAndOrientation(for: asset, options: options) { [weak self] data, typeIdentifier, _, _ in
            Task { @MainActor in
                guard let self, self.selectionState.contains(assetID: asset.localIdentifier) else { return }
                guard let data else {
                    self.selectionState.remove(assetID: asset.localIdentifier)
                    self.reloadAssetCell(assetID: asset.localIdentifier)
                    self.notifySelectionFailed(id: asset.localIdentifier, message: "Unable to load image")
                    return
                }

                let fileExtension = typeIdentifier
                    .flatMap { UTType($0)?.preferredFilenameExtension }
                    ?? "jpg"
                let preparedPreview = ChatPhotoLibrarySelectionPreview(
                    id: preview.id,
                    image: preview.image,
                    title: "Image ready",
                    durationText: nil,
                    isVideo: false
                )
                self.notifySelectionPrepared(
                    ChatPhotoLibraryPreparedMedia(
                        id: asset.localIdentifier,
                        preview: preparedPreview,
                        media: .image(data: data, preferredFileExtension: fileExtension)
                    )
                )
            }
        }
    }

    /// 将视频资源流式写入临时文件并生成发送媒体
    private func prepareVideo(for asset: PHAsset, preview: ChatPhotoLibrarySelectionPreview) {
        guard let resource = PHAssetResource.assetResources(for: asset).first(where: { resource in
            resource.type == .video || resource.type == .fullSizeVideo || resource.type == .pairedVideo
        }) else {
            selectionState.remove(assetID: asset.localIdentifier)
            reloadAssetCell(assetID: asset.localIdentifier)
            notifySelectionFailed(id: asset.localIdentifier, message: "Unable to load video")
            return
        }

        let originalExtension = URL(fileURLWithPath: resource.originalFilename).pathExtension
        let typeExtension = UTType(resource.uniformTypeIdentifier)?.preferredFilenameExtension
        let fileExtension = originalExtension.isEmpty ? (typeExtension ?? "mov") : originalExtension
        let temporaryURL = Self.temporaryMediaFileManager.makeTemporaryFileURL(
            prefix: "ChatBridgeVideoPick",
            fileExtension: fileExtension
        )

        Self.temporaryMediaFileManager.createEmptyFile(at: temporaryURL)

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        ChatPhotoLibraryVideoFileIO.stream(
            resource,
            to: temporaryURL,
            resourceManager: resourceManager,
            options: options,
            temporaryFileManager: Self.temporaryMediaFileManager,
            completion: { [weak self, assetID = asset.localIdentifier, preview, fileExtension] result in
                guard let self, self.selectionState.contains(assetID: assetID) else {
                    if case .success(let url) = result {
                        Self.temporaryMediaFileManager.removeFileIfExists(at: url)
                    }
                    return
                }

                guard case .success(let url) = result else {
                    self.selectionState.remove(assetID: assetID)
                    self.reloadAssetCell(assetID: assetID)
                    self.notifySelectionFailed(id: assetID, message: "Unable to load video")
                    return
                }

                let preparedPreview = ChatPhotoLibrarySelectionPreview(
                    id: preview.id,
                    image: preview.image,
                    title: "Video ready",
                    durationText: preview.durationText,
                    isVideo: true
                )
                self.notifySelectionPrepared(
                    ChatPhotoLibraryPreparedMedia(
                        id: assetID,
                        preview: preparedPreview,
                        media: .video(fileURL: url, preferredFileExtension: fileExtension)
                    )
                )
            }
        )
    }

    /// 发布图片库输入面板动作。
    private func emit(_ action: ChatPhotoLibraryInputAction) {
        lastAction = action
        sendActions(for: .primaryActionTriggered)
    }

    /// 通知外层下滑关闭位移变化。
    func notifyDismissPanChanged(_ translationY: CGFloat) {
        inputDelegate?.chatPhotoLibraryInputView(self, didChangeDismissPanTranslation: translationY)
    }

    /// 通知外层资源开始选择。
    private func notifySelectionStarted(_ preview: ChatPhotoLibrarySelectionPreview) {
        emit(.selectionStarted(preview))
        inputDelegate?.chatPhotoLibraryInputView(self, didStartSelection: preview)
    }

    /// 通知外层资源准备完成。
    private func notifySelectionPrepared(_ preparedMedia: ChatPhotoLibraryPreparedMedia) {
        emit(.selectionPrepared(preparedMedia))
        inputDelegate?.chatPhotoLibraryInputView(self, didPrepareSelection: preparedMedia)
    }

    /// 通知外层资源准备失败。
    private func notifySelectionFailed(id: String, message: String) {
        emit(.selectionFailed(id: id, message: message))
        inputDelegate?.chatPhotoLibraryInputView(self, didFailSelection: id, message: message)
    }

    /// 通知外层达到选择数量上限。
    private func notifySelectionLimitReached(_ message: String) {
        emit(.selectionLimitReached(message))
        inputDelegate?.chatPhotoLibraryInputView(self, didReachSelectionLimit: message)
    }

    /// 格式化视频时长文本
    fileprivate static func durationText(for asset: PHAsset) -> String? {
        guard asset.mediaType == .video else { return nil }
        let seconds = max(0, Int(asset.duration.rounded()))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

/// 图片库视频文件流式写入工具
enum ChatPhotoLibraryVideoFileIO {
    /// 视频流式写入错误
    enum StreamError: Error {
        /// 无法打开临时文件
        case unableToOpenFile
        /// 无法关闭临时文件
        case unableToCloseFile
        /// Photos 资源请求失败
        case requestFailed
    }

    /// 创建资源数据接收回调
    nonisolated static func makeDataReceivedHandler(fileHandle: FileHandle) -> (Data) -> Void {
        { data in
            fileHandle.write(data)
        }
    }

    /// 将 Photos 视频资源流式写入临时文件
    nonisolated static func stream(
        _ resource: PHAssetResource,
        to temporaryURL: URL,
        resourceManager: PHAssetResourceManager,
        options: PHAssetResourceRequestOptions,
        temporaryFileManager: any TemporaryMediaFileManaging = DefaultTemporaryMediaFileManager.shared,
        completion: @escaping @MainActor (Result<URL, StreamError>) -> Void
    ) {
        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forWritingTo: temporaryURL)
        } catch {
            Task { @MainActor in
                completion(.failure(.unableToOpenFile))
            }
            return
        }

        resourceManager.requestData(
            for: resource,
            options: options,
            dataReceivedHandler: makeDataReceivedHandler(fileHandle: fileHandle),
            completionHandler: { error in
                let result: Result<URL, StreamError>
                do {
                    try fileHandle.close()
                } catch {
                    temporaryFileManager.removeFileIfExists(at: temporaryURL)
                    result = .failure(.unableToCloseFile)
                    Task { @MainActor in
                        completion(result)
                    }
                    return
                }

                if error == nil {
                    result = .success(temporaryURL)
                } else {
                    temporaryFileManager.removeFileIfExists(at: temporaryURL)
                    result = .failure(.requestFailed)
                }

                Task { @MainActor in
                    completion(result)
                }
            }
        )
    }
}

/// 图片库网格布局代理
extension ChatPhotoLibraryInputView: UICollectionViewDelegateFlowLayout {
    /// 点击资源时切换选择状态
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let asset = asset(at: indexPath) else { return }
        selectAsset(asset)
    }

    /// 按三列网格计算资源单元格尺寸
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let totalSpacing = Self.interItemSpacing * 2
        let side = floor((collectionView.bounds.width - totalSpacing) / 3)
        return CGSize(width: side, height: side)
    }
}

/// 图片库面板手势协调
extension ChatPhotoLibraryInputView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}

/// 图片库资源单元格
@MainActor
private final class ChatPhotoLibraryCell: UICollectionViewCell {
    /// 缩略图视图
    private let imageView = UIImageView()
    /// 视频时长标签
    private let durationLabel = UILabel()
    /// 视频底部渐变遮罩
    private let gradientView = UIView()
    /// 视频播放图标
    private let videoIconView = UIImageView(image: UIImage(systemName: "play.fill"))
    /// 选择序号徽标
    private let selectionBadgeView = UILabel()
    /// 选中边框
    private let selectionBorderView = UIView()
    /// 当前缩略图请求 ID
    private var requestID: PHImageRequestID?
    /// 当前单元格代表的资源 ID
    private var representedAssetID: String?

    /// 初始化资源单元格
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    /// 从 storyboard/xib 初始化资源单元格
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    /// 复用前取消图片请求并重置 UI
    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        durationLabel.text = nil
        selectionBadgeView.text = nil
        selectionBadgeView.isHidden = true
        selectionBorderView.isHidden = true
        representedAssetID = nil
        if let requestID {
            PHImageManager.default().cancelImageRequest(requestID)
        }
        requestID = nil
    }

    /// 根据 Photos 资源和选择序号配置单元格
    func configure(asset: PHAsset, imageManager: PHCachingImageManager, selectionNumber: Int?) {
        representedAssetID = asset.localIdentifier
        accessibilityIdentifier = "chat.photoLibraryCell.\(asset.localIdentifier)"
        accessibilityLabel = asset.mediaType == .video
            ? "Video \(ChatPhotoLibraryInputView.durationText(for: asset) ?? "")"
            : "Photo"
        if let selectionNumber {
            accessibilityValue = "Selected \(selectionNumber)"
        } else {
            accessibilityValue = nil
        }

        let isVideo = asset.mediaType == .video
        gradientView.isHidden = !isVideo
        durationLabel.isHidden = !isVideo
        videoIconView.isHidden = !isVideo
        durationLabel.text = ChatPhotoLibraryInputView.durationText(for: asset)
        selectionBadgeView.isHidden = selectionNumber == nil
        selectionBorderView.isHidden = selectionNumber == nil
        selectionBadgeView.text = selectionNumber.map(String.init)

        let scale = UIScreen.main.scale
        let targetSize = CGSize(width: max(bounds.width, 96) * scale, height: max(bounds.height, 96) * scale)
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        requestID = imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, _ in
            Task { @MainActor in
                guard let self, self.representedAssetID == asset.localIdentifier else { return }
                self.imageView.image = image
            }
        }
    }

    /// 配置单元格视图层级、样式和约束
    private func configureView() {
        contentView.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.46)
                : UIColor.systemFill.withAlphaComponent(0.18)
        }
        contentView.clipsToBounds = true
        contentView.layer.cornerRadius = ChatBridgeDesignSystem.RadiusToken.appleComposerAttachment
        contentView.layer.cornerCurve = .continuous

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true

        gradientView.translatesAutoresizingMaskIntoConstraints = false
        gradientView.backgroundColor = UIColor.black.withAlphaComponent(0.28)
        gradientView.isUserInteractionEnabled = false

        videoIconView.translatesAutoresizingMaskIntoConstraints = false
        videoIconView.tintColor = .white
        videoIconView.contentMode = .scaleAspectFit

        selectionBorderView.translatesAutoresizingMaskIntoConstraints = false
        selectionBorderView.isUserInteractionEnabled = false
        selectionBorderView.layer.borderColor = ChatBridgeDesignSystem.ColorToken.appleMessageOutgoing.cgColor
        selectionBorderView.layer.borderWidth = 3
        selectionBorderView.layer.cornerRadius = ChatBridgeDesignSystem.RadiusToken.appleComposerAttachment
        selectionBorderView.layer.cornerCurve = .continuous
        selectionBorderView.isHidden = true

        selectionBadgeView.translatesAutoresizingMaskIntoConstraints = false
        selectionBadgeView.backgroundColor = ChatBridgeDesignSystem.ColorToken.appleMessageOutgoing
        selectionBadgeView.textColor = .white
        selectionBadgeView.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        selectionBadgeView.textAlignment = .center
        selectionBadgeView.layer.cornerRadius = 13
        selectionBadgeView.layer.masksToBounds = true
        selectionBadgeView.isHidden = true

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        durationLabel.textColor = .white
        durationLabel.adjustsFontSizeToFitWidth = true
        durationLabel.minimumScaleFactor = 0.7
        durationLabel.textAlignment = .right

        contentView.addSubview(imageView)
        contentView.addSubview(gradientView)
        contentView.addSubview(videoIconView)
        contentView.addSubview(durationLabel)
        contentView.addSubview(selectionBorderView)
        contentView.addSubview(selectionBadgeView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            gradientView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            gradientView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            gradientView.heightAnchor.constraint(equalToConstant: 30),

            videoIconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            videoIconView.centerYAnchor.constraint(equalTo: gradientView.centerYAnchor),
            videoIconView.widthAnchor.constraint(equalToConstant: 14),
            videoIconView.heightAnchor.constraint(equalToConstant: 14),

            durationLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            durationLabel.centerYAnchor.constraint(equalTo: gradientView.centerYAnchor),
            durationLabel.leadingAnchor.constraint(greaterThanOrEqualTo: videoIconView.trailingAnchor, constant: 6),

            selectionBorderView.topAnchor.constraint(equalTo: contentView.topAnchor),
            selectionBorderView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            selectionBorderView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            selectionBorderView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            selectionBadgeView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            selectionBadgeView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            selectionBadgeView.widthAnchor.constraint(equalToConstant: 26),
            selectionBadgeView.heightAnchor.constraint(equalToConstant: 26)
        ])
    }
}
