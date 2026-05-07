//
//  ChatPhotoLibraryInputView.swift
//  AppleIM
//

import UIKit
@preconcurrency import Photos
import UniformTypeIdentifiers

@MainActor
struct ChatPhotoLibrarySelectionPreview {
    let id: String
    let image: UIImage?
    let title: String
    let durationText: String?
    let isVideo: Bool
}

@MainActor
struct ChatPhotoLibraryPreparedMedia {
    let id: String
    let preview: ChatPhotoLibrarySelectionPreview
    let media: ChatComposerMedia
}

nonisolated struct ChatPhotoLibrarySelectionState {
    enum ToggleResult: Equatable {
        case selected
        case deselected
        case limitReached
    }

    static let maxSelectionCount = 9
    private(set) var selectedAssetIDs: [String] = []

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

    mutating func remove(assetID: String) {
        selectedAssetIDs.removeAll { $0 == assetID }
    }

    mutating func removeAll() {
        selectedAssetIDs.removeAll()
    }

    func contains(assetID: String) -> Bool {
        selectedAssetIDs.contains(assetID)
    }

    func selectionNumber(for assetID: String) -> Int? {
        selectedAssetIDs.firstIndex(of: assetID).map { $0 + 1 }
    }
}

@MainActor
final class ChatPhotoLibraryInputView: UIInputView {
    var onSelectionStarted: ((ChatPhotoLibrarySelectionPreview) -> Void)?
    var onSelectionPrepared: ((ChatPhotoLibraryPreparedMedia) -> Void)?
    var onSelectionRemoved: ((String) -> Void)?
    var onSelectionFailed: ((String, String) -> Void)?
    var onSelectionLimitReached: ((String) -> Void)?

    private static let panelHeight: CGFloat = 342
    private static let interItemSpacing: CGFloat = 2

    private let panelView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let tintView = UIView()
    private let grabberView = UIView()
    private let collectionView: UICollectionView
    private let statusView = UIView()
    private let statusLabel = UILabel()
    private let statusButton = UIButton(type: .system)
    private let imageManager = PHCachingImageManager()
    private let resourceManager = PHAssetResourceManager.default()

    private var assets: PHFetchResult<PHAsset>?
    private var representedAssetIDs: [String] = []
    private var selectionState = ChatPhotoLibrarySelectionState()

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.panelHeight)
    }

    override init(frame: CGRect, inputViewStyle: UIInputView.Style) {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = Self.interItemSpacing
        layout.minimumInteritemSpacing = Self.interItemSpacing
        layout.sectionInset = .zero
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame.isEmpty ? CGRect(x: 0, y: 0, width: 0, height: Self.panelHeight) : frame, inputViewStyle: inputViewStyle)
        configureView()
        refreshAuthorization()
    }

    required init?(coder: NSCoder) {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = Self.interItemSpacing
        layout.minimumInteritemSpacing = Self.interItemSpacing
        layout.sectionInset = .zero
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(coder: coder)
        configureView()
        refreshAuthorization()
    }

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

    private func configureView() {
        backgroundColor = .clear
        allowsSelfSizing = false

        panelView.translatesAutoresizingMaskIntoConstraints = false
        panelView.clipsToBounds = true
        panelView.layer.cornerRadius = 32
        panelView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.black.withAlphaComponent(0.18)
                : UIColor.white.withAlphaComponent(0.34)
        }
        tintView.isUserInteractionEnabled = false

        grabberView.translatesAutoresizingMaskIntoConstraints = false
        grabberView.backgroundColor = UIColor.secondaryLabel.withAlphaComponent(0.38)
        grabberView.layer.cornerRadius = 3

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.contentInset = UIEdgeInsets(top: 18, left: 0, bottom: 0, right: 0)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ChatPhotoLibraryCell.self, forCellWithReuseIdentifier: ChatPhotoLibraryCell.reuseIdentifier)
        collectionView.accessibilityIdentifier = "chat.photoLibraryGrid"

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

        addSubview(panelView)
        panelView.contentView.addSubview(tintView)
        panelView.contentView.addSubview(collectionView)
        panelView.contentView.addSubview(grabberView)
        panelView.contentView.addSubview(statusView)
        statusView.addSubview(statusLabel)
        statusView.addSubview(statusButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.panelHeight),

            panelView.topAnchor.constraint(equalTo: topAnchor),
            panelView.leadingAnchor.constraint(equalTo: leadingAnchor),
            panelView.trailingAnchor.constraint(equalTo: trailingAnchor),
            panelView.bottomAnchor.constraint(equalTo: bottomAnchor),

            tintView.topAnchor.constraint(equalTo: panelView.contentView.topAnchor),
            tintView.leadingAnchor.constraint(equalTo: panelView.contentView.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: panelView.contentView.trailingAnchor),
            tintView.bottomAnchor.constraint(equalTo: panelView.contentView.bottomAnchor),

            grabberView.topAnchor.constraint(equalTo: panelView.contentView.topAnchor, constant: 14),
            grabberView.centerXAnchor.constraint(equalTo: panelView.contentView.centerXAnchor),
            grabberView.widthAnchor.constraint(equalToConstant: 54),
            grabberView.heightAnchor.constraint(equalToConstant: 6),

            collectionView.topAnchor.constraint(equalTo: panelView.contentView.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: panelView.contentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: panelView.contentView.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: panelView.contentView.bottomAnchor),

            statusView.topAnchor.constraint(equalTo: panelView.contentView.topAnchor),
            statusView.leadingAnchor.constraint(equalTo: panelView.contentView.leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: panelView.contentView.trailingAnchor),
            statusView.bottomAnchor.constraint(equalTo: panelView.contentView.bottomAnchor),

            statusLabel.centerYAnchor.constraint(equalTo: statusView.centerYAnchor, constant: -18),
            statusLabel.leadingAnchor.constraint(equalTo: statusView.layoutMarginsGuide.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: statusView.layoutMarginsGuide.trailingAnchor, constant: -20),

            statusButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            statusButton.centerXAnchor.constraint(equalTo: statusView.centerXAnchor)
        ])
    }

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
            collectionView.reloadData()
        }
    }

    private var statusButtonAction: (() -> Void)?

    private func showStatus(_ message: String, buttonTitle: String?, action: (() -> Void)?) {
        collectionView.isHidden = true
        statusView.isHidden = false
        statusLabel.text = message
        statusButton.setTitle(buttonTitle, for: .normal)
        statusButton.isHidden = buttonTitle == nil
        statusButtonAction = action
    }

    @objc private func statusButtonTapped() {
        statusButtonAction?()
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func asset(at indexPath: IndexPath) -> PHAsset? {
        guard let assets, indexPath.item < assets.count else { return nil }
        return assets.object(at: indexPath.item)
    }

    func removeSelection(assetID: String) {
        guard selectionState.contains(assetID: assetID) else { return }
        selectionState.remove(assetID: assetID)
        reloadAssetCell(assetID: assetID)
    }

    func clearSelection() {
        let selectedIDs = selectionState.selectedAssetIDs
        selectionState.removeAll()
        selectedIDs.forEach(reloadAssetCell(assetID:))
    }

    private func selectAsset(_ asset: PHAsset) {
        switch selectionState.toggle(assetID: asset.localIdentifier) {
        case .selected:
            reloadAssetCell(assetID: asset.localIdentifier)
        case .deselected:
            reloadAssetCell(assetID: asset.localIdentifier)
            onSelectionRemoved?(asset.localIdentifier)
            return
        case .limitReached:
            onSelectionLimitReached?("You can select up to 9 photos or videos.")
            return
        }

        onSelectionStarted?(
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
            self.onSelectionStarted?(preview)
            self.prepareMedia(for: asset, preview: preview)
        }
    }

    private func reloadAssetCell(assetID: String) {
        guard let index = representedAssetIDs.firstIndex(of: assetID) else { return }
        collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
    }

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

    private func prepareMedia(for asset: PHAsset, preview: ChatPhotoLibrarySelectionPreview) {
        switch asset.mediaType {
        case .image:
            prepareImage(for: asset, preview: preview)
        case .video:
            prepareVideo(for: asset, preview: preview)
        default:
            selectionState.remove(assetID: asset.localIdentifier)
            reloadAssetCell(assetID: asset.localIdentifier)
            onSelectionFailed?(asset.localIdentifier, "Unsupported media")
        }
    }

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
                    self.onSelectionFailed?(asset.localIdentifier, "Unable to load image")
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
                self.onSelectionPrepared?(
                    ChatPhotoLibraryPreparedMedia(
                        id: asset.localIdentifier,
                        preview: preparedPreview,
                        media: .image(data: data, preferredFileExtension: fileExtension)
                    )
                )
            }
        }
    }

    private func prepareVideo(for asset: PHAsset, preview: ChatPhotoLibrarySelectionPreview) {
        guard let resource = PHAssetResource.assetResources(for: asset).first(where: { resource in
            resource.type == .video || resource.type == .fullSizeVideo || resource.type == .pairedVideo
        }) else {
            selectionState.remove(assetID: asset.localIdentifier)
            reloadAssetCell(assetID: asset.localIdentifier)
            onSelectionFailed?(asset.localIdentifier, "Unable to load video")
            return
        }

        let originalExtension = URL(fileURLWithPath: resource.originalFilename).pathExtension
        let typeExtension = UTType(resource.uniformTypeIdentifier)?.preferredFilenameExtension
        let fileExtension = originalExtension.isEmpty ? (typeExtension ?? "mov") : originalExtension
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatBridgeVideoPick-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)

        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        ChatPhotoLibraryVideoFileIO.stream(
            resource,
            to: temporaryURL,
            resourceManager: resourceManager,
            options: options,
            completion: { [weak self, assetID = asset.localIdentifier, preview, fileExtension] result in
                guard let self, self.selectionState.contains(assetID: assetID) else {
                    if case .success(let url) = result {
                        try? FileManager.default.removeItem(at: url)
                    }
                    return
                }

                guard case .success(let url) = result else {
                    self.selectionState.remove(assetID: assetID)
                    self.reloadAssetCell(assetID: assetID)
                    self.onSelectionFailed?(assetID, "Unable to load video")
                    return
                }

                let preparedPreview = ChatPhotoLibrarySelectionPreview(
                    id: preview.id,
                    image: preview.image,
                    title: "Video ready",
                    durationText: preview.durationText,
                    isVideo: true
                )
                self.onSelectionPrepared?(
                    ChatPhotoLibraryPreparedMedia(
                        id: assetID,
                        preview: preparedPreview,
                        media: .video(fileURL: url, preferredFileExtension: fileExtension)
                    )
                )
            }
        )
    }

    fileprivate static func durationText(for asset: PHAsset) -> String? {
        guard asset.mediaType == .video else { return nil }
        let seconds = max(0, Int(asset.duration.rounded()))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

enum ChatPhotoLibraryVideoFileIO {
    enum StreamError: Error {
        case unableToOpenFile
        case unableToCloseFile
        case requestFailed
    }

    nonisolated static func makeDataReceivedHandler(fileHandle: FileHandle) -> (Data) -> Void {
        { data in
            fileHandle.write(data)
        }
    }

    nonisolated static func stream(
        _ resource: PHAssetResource,
        to temporaryURL: URL,
        resourceManager: PHAssetResourceManager,
        options: PHAssetResourceRequestOptions,
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
                    try? FileManager.default.removeItem(at: temporaryURL)
                    result = .failure(.unableToCloseFile)
                    Task { @MainActor in
                        completion(result)
                    }
                    return
                }

                if error == nil {
                    result = .success(temporaryURL)
                } else {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    result = .failure(.requestFailed)
                }

                Task { @MainActor in
                    completion(result)
                }
            }
        )
    }
}

extension ChatPhotoLibraryInputView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        representedAssetIDs.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ChatPhotoLibraryCell.reuseIdentifier,
            for: indexPath
        )
        guard let mediaCell = cell as? ChatPhotoLibraryCell, let asset = asset(at: indexPath) else {
            return cell
        }

        mediaCell.configure(
            asset: asset,
            imageManager: imageManager,
            selectionNumber: selectionState.selectionNumber(for: asset.localIdentifier)
        )
        return mediaCell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let asset = asset(at: indexPath) else { return }
        selectAsset(asset)
    }

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

@MainActor
private final class ChatPhotoLibraryCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatPhotoLibraryCell"

    private let imageView = UIImageView()
    private let durationLabel = UILabel()
    private let gradientView = UIView()
    private let videoIconView = UIImageView(image: UIImage(systemName: "play.fill"))
    private let selectionBadgeView = UILabel()
    private let selectionBorderView = UIView()
    private var requestID: PHImageRequestID?
    private var representedAssetID: String?

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

    private func configureView() {
        contentView.backgroundColor = .secondarySystemGroupedBackground
        contentView.clipsToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true

        gradientView.translatesAutoresizingMaskIntoConstraints = false
        gradientView.backgroundColor = UIColor.black.withAlphaComponent(0.34)
        gradientView.isUserInteractionEnabled = false

        videoIconView.translatesAutoresizingMaskIntoConstraints = false
        videoIconView.tintColor = .white
        videoIconView.contentMode = .scaleAspectFit

        selectionBorderView.translatesAutoresizingMaskIntoConstraints = false
        selectionBorderView.isUserInteractionEnabled = false
        selectionBorderView.layer.borderColor = UIColor.systemBlue.cgColor
        selectionBorderView.layer.borderWidth = 3
        selectionBorderView.isHidden = true

        selectionBadgeView.translatesAutoresizingMaskIntoConstraints = false
        selectionBadgeView.backgroundColor = .systemBlue
        selectionBadgeView.textColor = .white
        selectionBadgeView.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        selectionBadgeView.textAlignment = .center
        selectionBadgeView.layer.cornerRadius = 12
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
            gradientView.heightAnchor.constraint(equalToConstant: 28),

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

            selectionBadgeView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
            selectionBadgeView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -7),
            selectionBadgeView.widthAnchor.constraint(equalToConstant: 24),
            selectionBadgeView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
}
