//
//  MediaMessageContentView.swift
//  AppleIM
//

import UIKit

/// 图片和视频消息内容视图
@MainActor
final class MediaMessageContentView: UIView, ChatMessageContentView {
    private enum Layout {
        static let maxDisplaySize = CGSize(width: 228, height: 304)
        static let fallbackDisplaySize = CGSize(width: 206, height: 152)
    }

    private let mediaContainerView = UIView()
    private let thumbnailImageView = UIImageView()
    private let videoOverlayView = UIView()
    private let videoGradientView = UIView()
    private let videoStackView = UIStackView()
    private let videoPlaybackButton = UIButton(type: .system)
    private let videoDurationLabel = UILabel()
    private let fallbackLabel = UILabel()
    private var mediaWidthConstraint: NSLayoutConstraint?
    private var mediaHeightConstraint: NSLayoutConstraint?
    private var row: ChatMessageRowState?
    private var isVideoMessage = false
    private var actions = ChatMessageCellActions.empty

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    func configure(
        row: ChatMessageRowState,
        style: ChatMessageContentStyle,
        actions: ChatMessageCellActions
    ) {
        self.row = row
        self.actions = actions

        let thumbnailPath: String?
        let isVideo: Bool
        let videoDurationMilliseconds: Int?

        switch row.content {
        case let .image(image):
            thumbnailPath = image.thumbnailPath
            isVideo = false
            videoDurationMilliseconds = nil
        case let .video(video):
            thumbnailPath = video.thumbnailPath
            isVideo = true
            videoDurationMilliseconds = video.durationMilliseconds
        default:
            thumbnailPath = nil
            isVideo = false
            videoDurationMilliseconds = nil
        }
        isVideoMessage = isVideo

        if let thumbnailPath {
            thumbnailImageView.image = UIImage(contentsOfFile: thumbnailPath)
        } else {
            thumbnailImageView.image = nil
        }
        updateMediaSize(for: thumbnailImageView.image?.size)

        thumbnailImageView.isHidden = thumbnailImageView.image == nil
        fallbackLabel.text = L10n.shared.tr(isVideo ? "chat.media.videoUnavailable" : "chat.media.imageUnavailable")
        fallbackLabel.textColor = style.textColor
        fallbackLabel.isHidden = thumbnailImageView.image != nil

        videoOverlayView.isHidden = !isVideo || thumbnailImageView.image == nil
        videoStackView.isHidden = !isVideo || thumbnailImageView.image == nil
        videoPlaybackButton.tintColor = .white
        videoPlaybackButton.accessibilityLabel = L10n.shared.tr("chat.media.playVideo.accessibility")
        videoDurationLabel.text = Self.durationText(milliseconds: videoDurationMilliseconds ?? 0)
        videoDurationLabel.textColor = .white
        accessibilityLabel = L10n.shared.tr(
            isVideo ? "chat.media.playVideo.accessibility" : "chat.media.image.accessibility"
        )
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true

        mediaContainerView.translatesAutoresizingMaskIntoConstraints = false
        mediaContainerView.clipsToBounds = true
        mediaContainerView.layer.cornerRadius = ChatBridgeDesignSystem.RadiusToken.appleMessageMedia
        mediaContainerView.backgroundColor = ChatBridgeDesignSystem.ColorToken.appleMessageIncoming
        mediaContainerView.isUserInteractionEnabled = true
        mediaContainerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(mediaContainerTapped)))

        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailImageView.contentMode = .scaleAspectFill
        thumbnailImageView.clipsToBounds = true

        videoOverlayView.translatesAutoresizingMaskIntoConstraints = false
        videoOverlayView.isUserInteractionEnabled = false

        videoGradientView.translatesAutoresizingMaskIntoConstraints = false
        videoGradientView.backgroundColor = UIColor.black.withAlphaComponent(0.38)
        videoGradientView.isUserInteractionEnabled = false

        videoStackView.translatesAutoresizingMaskIntoConstraints = false
        videoStackView.axis = .horizontal
        videoStackView.alignment = .center
        videoStackView.spacing = 8

        videoPlaybackButton.translatesAutoresizingMaskIntoConstraints = false
        videoPlaybackButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        videoPlaybackButton.addTarget(self, action: #selector(videoPlaybackButtonTapped), for: .touchUpInside)

        videoDurationLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        videoDurationLabel.adjustsFontForContentSizeCategory = true

        fallbackLabel.font = .preferredFont(forTextStyle: .subheadline)
        fallbackLabel.adjustsFontForContentSizeCategory = true
        fallbackLabel.numberOfLines = 0
        fallbackLabel.textAlignment = .center

        videoStackView.addArrangedSubview(videoPlaybackButton)
        videoStackView.addArrangedSubview(videoDurationLabel)
        addSubview(mediaContainerView)
        mediaContainerView.addSubview(thumbnailImageView)
        mediaContainerView.addSubview(fallbackLabel)
        mediaContainerView.addSubview(videoOverlayView)
        videoOverlayView.addSubview(videoGradientView)
        videoOverlayView.addSubview(videoStackView)

        NSLayoutConstraint.activate([
            mediaContainerView.topAnchor.constraint(equalTo: topAnchor),
            mediaContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mediaContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mediaContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            thumbnailImageView.topAnchor.constraint(equalTo: mediaContainerView.topAnchor),
            thumbnailImageView.leadingAnchor.constraint(equalTo: mediaContainerView.leadingAnchor),
            thumbnailImageView.trailingAnchor.constraint(equalTo: mediaContainerView.trailingAnchor),
            thumbnailImageView.bottomAnchor.constraint(equalTo: mediaContainerView.bottomAnchor),

            fallbackLabel.leadingAnchor.constraint(equalTo: mediaContainerView.leadingAnchor, constant: 12),
            fallbackLabel.trailingAnchor.constraint(equalTo: mediaContainerView.trailingAnchor, constant: -12),
            fallbackLabel.centerYAnchor.constraint(equalTo: mediaContainerView.centerYAnchor),

            videoOverlayView.leadingAnchor.constraint(equalTo: mediaContainerView.leadingAnchor),
            videoOverlayView.trailingAnchor.constraint(equalTo: mediaContainerView.trailingAnchor),
            videoOverlayView.bottomAnchor.constraint(equalTo: mediaContainerView.bottomAnchor),
            videoOverlayView.heightAnchor.constraint(equalToConstant: 34),

            videoGradientView.topAnchor.constraint(equalTo: videoOverlayView.topAnchor),
            videoGradientView.leadingAnchor.constraint(equalTo: videoOverlayView.leadingAnchor),
            videoGradientView.trailingAnchor.constraint(equalTo: videoOverlayView.trailingAnchor),
            videoGradientView.bottomAnchor.constraint(equalTo: videoOverlayView.bottomAnchor),

            videoStackView.trailingAnchor.constraint(equalTo: videoOverlayView.trailingAnchor, constant: -10),
            videoStackView.centerYAnchor.constraint(equalTo: videoOverlayView.centerYAnchor),

            videoPlaybackButton.widthAnchor.constraint(equalToConstant: 18),
            videoPlaybackButton.heightAnchor.constraint(equalToConstant: 18)
        ])

        mediaWidthConstraint = mediaContainerView.widthAnchor.constraint(equalToConstant: Layout.fallbackDisplaySize.width)
        mediaHeightConstraint = mediaContainerView.heightAnchor.constraint(equalToConstant: Layout.fallbackDisplaySize.height)
        mediaWidthConstraint?.isActive = true
        mediaHeightConstraint?.isActive = true
    }

    @objc private func videoPlaybackButtonTapped() {
        playVideoIfAvailable()
    }

    @objc private func mediaContainerTapped() {
        playVideoIfAvailable()
    }

    override func accessibilityActivate() -> Bool {
        guard isVideoMessage else { return false }
        playVideoIfAvailable()
        return true
    }

    private func playVideoIfAvailable() {
        guard isVideoMessage, let row else { return }
        actions.onPlayVideo(row)
    }

    private func updateMediaSize(for imageSize: CGSize?) {
        let displaySize = Self.displaySize(for: imageSize)
        mediaWidthConstraint?.constant = displaySize.width
        mediaHeightConstraint?.constant = displaySize.height
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private static func displaySize(for imageSize: CGSize?) -> CGSize {
        guard
            let imageSize,
            imageSize.width > 0,
            imageSize.height > 0
        else {
            return Layout.fallbackDisplaySize
        }

        let aspectRatio = imageSize.width / imageSize.height
        let maxSize = Layout.maxDisplaySize
        if aspectRatio >= 1 {
            return CGSize(width: maxSize.width, height: maxSize.width / aspectRatio)
        }

        let height = min(maxSize.height, maxSize.width / aspectRatio)
        return CGSize(width: height * aspectRatio, height: height)
    }

    private static func durationText(milliseconds: Int) -> String {
        let seconds = max(1, Int((Double(milliseconds) / 1_000.0).rounded()))
        return "\(seconds)s"
    }
}
