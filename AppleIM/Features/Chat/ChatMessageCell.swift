//
//  ChatMessageCell.swift
//  AppleIM
//

import UIKit

/// 聊天消息单元格动作集合
@MainActor
struct ChatMessageCellActions {
    let onRetry: (MessageID) -> Void
    let onDelete: (MessageID) -> Void
    let onRevoke: (MessageID) -> Void
    let onPlayVoice: (ChatMessageRowState) -> Void
    let onPlayVideo: (ChatMessageRowState) -> Void

    static let empty = ChatMessageCellActions(
        onRetry: { _ in },
        onDelete: { _ in },
        onRevoke: { _ in },
        onPlayVoice: { _ in },
        onPlayVideo: { _ in }
    )
}

/// 聊天消息内容类型
nonisolated enum ChatMessageContentKind: Equatable {
    case text
    case image
    case voice
    case video
    case file
    case emoji
    case revoked

    init(row: ChatMessageRowState) {
        switch row.content.kind {
        case .revoked:
            self = .revoked
        case .voice:
            self = .voice
        case .video:
            self = .video
        case .image:
            self = .image
        case .file:
            self = .file
        case .emoji:
            self = .emoji
        case .text:
            self = .text
        }
    }
}

/// 消息内容展示样式
struct ChatMessageContentStyle {
    let textColor: UIColor
    let secondaryTextColor: UIColor
    let tintColor: UIColor
}

/// 可插拔消息内容视图
@MainActor
protocol ChatMessageContentView: AnyObject {
    func configure(
        row: ChatMessageRowState,
        style: ChatMessageContentStyle,
        actions: ChatMessageCellActions
    )
}

/// 消息内容视图工厂
@MainActor
final class ChatMessageContentViewFactory {
    func view(
        for kind: ChatMessageContentKind,
        reusing existingView: (UIView & ChatMessageContentView)?
    ) -> UIView & ChatMessageContentView {
        switch kind {
        case .text, .revoked:
            if let textView = existingView as? TextMessageContentView {
                return textView
            }
            return TextMessageContentView()
        case .file:
            if let fileView = existingView as? FileMessageContentView {
                return fileView
            }
            return FileMessageContentView()
        case .image, .video:
            if let mediaView = existingView as? MediaMessageContentView {
                return mediaView
            }
            return MediaMessageContentView()
        case .voice:
            if let voiceView = existingView as? VoiceMessageContentView {
                return voiceView
            }
            return VoiceMessageContentView()
        case .emoji:
            if let emojiView = existingView as? EmojiMessageContentView {
                return emojiView
            }
            return EmojiMessageContentView()
        }
    }
}

/// 文本和撤回消息内容视图
@MainActor
final class TextMessageContentView: UIView, ChatMessageContentView {
    private let messageLabel = UILabel()

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
        messageLabel.text = Self.text(for: row.content)
        messageLabel.textColor = style.textColor
    }

    private static func text(for content: ChatMessageRowContent) -> String {
        switch content {
        case let .text(text), let .revoked(text):
            return text
        case .image:
            return "Image"
        case let .voice(voice):
            return "Voice \(ChatMessageRowContent.durationText(milliseconds: voice.durationMilliseconds))"
        case let .video(video):
            return "Video \(ChatMessageRowContent.durationText(milliseconds: video.durationMilliseconds))"
        case let .file(file):
            return file.fileName
        case let .emoji(emoji):
            return emoji.name ?? "Emoji"
        }
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0

        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: topAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

/// 表情消息内容视图
@MainActor
final class EmojiMessageContentView: UIView, ChatMessageContentView {
    private let imageView = UIImageView()
    private let fallbackLabel = UILabel()

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
        guard case let .emoji(emoji) = row.content else { return }

        let localImagePath = emoji.thumbPath ?? emoji.localPath
        let image = localImagePath.flatMap(UIImage.init(contentsOfFile:))
        imageView.image = image
        imageView.isHidden = image == nil
        fallbackLabel.isHidden = image != nil
        fallbackLabel.text = emoji.name ?? "Emoji"
        fallbackLabel.textColor = style.textColor
        fallbackLabel.backgroundColor = style.tintColor.withAlphaComponent(row.isOutgoing ? 0.18 : 0.10)
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8

        fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
        fallbackLabel.font = .preferredFont(forTextStyle: .subheadline)
        fallbackLabel.adjustsFontForContentSizeCategory = true
        fallbackLabel.textAlignment = .center
        fallbackLabel.numberOfLines = 2
        fallbackLabel.layer.cornerRadius = 8
        fallbackLabel.layer.masksToBounds = true

        addSubview(imageView)
        addSubview(fallbackLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 96),
            imageView.heightAnchor.constraint(equalToConstant: 96),

            fallbackLabel.topAnchor.constraint(equalTo: topAnchor),
            fallbackLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            fallbackLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            fallbackLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            fallbackLabel.widthAnchor.constraint(equalToConstant: 96),
            fallbackLabel.heightAnchor.constraint(equalToConstant: 96)
        ])
    }
}

/// 文件消息内容视图
@MainActor
final class FileMessageContentView: UIView, ChatMessageContentView {
    private let containerView = UIView()
    private let iconContainerView = UIView()
    private let iconView = UIImageView(image: UIImage(systemName: "doc.fill"))
    private let textStackView = UIStackView()
    private let fileNameLabel = UILabel()
    private let fileSizeLabel = UILabel()

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
        guard case let .file(file) = row.content else { return }

        fileNameLabel.text = file.fileName
        fileNameLabel.textColor = style.textColor
        fileSizeLabel.text = Self.fileSizeText(bytes: file.sizeBytes)
        fileSizeLabel.textColor = style.secondaryTextColor
        iconView.tintColor = style.tintColor
        iconContainerView.backgroundColor = style.tintColor.withAlphaComponent(row.isOutgoing ? 0.22 : 0.14)
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .clear

        iconContainerView.translatesAutoresizingMaskIntoConstraints = false
        iconContainerView.layer.cornerRadius = 10
        iconContainerView.layer.masksToBounds = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        textStackView.translatesAutoresizingMaskIntoConstraints = false
        textStackView.axis = .vertical
        textStackView.spacing = 2

        fileNameLabel.font = .preferredFont(forTextStyle: .subheadline)
        fileNameLabel.adjustsFontForContentSizeCategory = true
        fileNameLabel.numberOfLines = 2

        fileSizeLabel.font = .preferredFont(forTextStyle: .caption1)
        fileSizeLabel.adjustsFontForContentSizeCategory = true
        fileSizeLabel.numberOfLines = 1

        addSubview(containerView)
        containerView.addSubview(iconContainerView)
        iconContainerView.addSubview(iconView)
        containerView.addSubview(textStackView)
        textStackView.addArrangedSubview(fileNameLabel)
        textStackView.addArrangedSubview(fileSizeLabel)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconContainerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            iconContainerView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconContainerView.widthAnchor.constraint(equalToConstant: 38),
            iconContainerView.heightAnchor.constraint(equalToConstant: 38),

            iconView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            textStackView.topAnchor.constraint(equalTo: containerView.topAnchor),
            textStackView.leadingAnchor.constraint(equalTo: iconContainerView.trailingAnchor, constant: 10),
            textStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            textStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }

    private static func fileSizeText(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

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
        fallbackLabel.text = isVideo ? "Video unavailable" : "Image unavailable"
        fallbackLabel.textColor = style.textColor
        fallbackLabel.isHidden = thumbnailImageView.image != nil

        videoOverlayView.isHidden = !isVideo || thumbnailImageView.image == nil
        videoStackView.isHidden = !isVideo || thumbnailImageView.image == nil
        videoPlaybackButton.tintColor = .white
        videoPlaybackButton.accessibilityLabel = "Play Video"
        videoDurationLabel.text = Self.durationText(milliseconds: videoDurationMilliseconds ?? 0)
        videoDurationLabel.textColor = .white
        accessibilityLabel = isVideo ? "Play Video" : "Image"
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

/// 语音消息内容视图
@MainActor
final class VoiceMessageContentView: UIView, ChatMessageContentView {
    private let stackView = UIStackView()
    private let voicePlaybackButton = UIButton(type: .system)
    private let waveformView = MessageVoiceWaveformView()
    private let voiceDurationLabel = UILabel()
    private let voiceUnreadDotView = UIView()
    private var row: ChatMessageRowState?
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

        let voice: ChatMessageRowContent.VoiceContent?
        if case let .voice(content) = row.content {
            voice = content
        } else {
            voice = nil
        }

        let isPlaying = voice?.isPlaying == true
        voicePlaybackButton.setImage(UIImage(systemName: isPlaying ? "pause.fill" : "play.fill"), for: .normal)
        voicePlaybackButton.tintColor = style.tintColor
        voicePlaybackButton.accessibilityLabel = isPlaying ? "Stop Voice" : "Play Voice"
        waveformView.tintColor = style.tintColor
        waveformView.isPlaying = isPlaying
        waveformView.playbackProgress = voice?.playbackProgress ?? 0
        voiceDurationLabel.text = Self.durationText(for: voice)
        voiceDurationLabel.textColor = style.textColor
        voiceUnreadDotView.isHidden = !(voice?.isUnplayed == true)
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 9

        voicePlaybackButton.translatesAutoresizingMaskIntoConstraints = false
        voicePlaybackButton.addTarget(self, action: #selector(voicePlaybackButtonTapped), for: .touchUpInside)

        waveformView.translatesAutoresizingMaskIntoConstraints = false

        voiceDurationLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        voiceDurationLabel.adjustsFontForContentSizeCategory = true
        voiceDurationLabel.adjustsFontSizeToFitWidth = true
        voiceDurationLabel.minimumScaleFactor = 0.78

        voiceUnreadDotView.translatesAutoresizingMaskIntoConstraints = false
        voiceUnreadDotView.backgroundColor = ChatBridgeDesignSystem.ColorToken.coral
        voiceUnreadDotView.layer.cornerRadius = 3.5
        voiceUnreadDotView.isHidden = true

        stackView.addArrangedSubview(voicePlaybackButton)
        stackView.addArrangedSubview(waveformView)
        stackView.addArrangedSubview(voiceDurationLabel)
        stackView.addArrangedSubview(voiceUnreadDotView)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            voicePlaybackButton.widthAnchor.constraint(equalToConstant: 28),
            voicePlaybackButton.heightAnchor.constraint(equalToConstant: 28),
            waveformView.widthAnchor.constraint(equalToConstant: 70),
            waveformView.heightAnchor.constraint(equalToConstant: 22),
            voiceUnreadDotView.widthAnchor.constraint(equalToConstant: 7),
            voiceUnreadDotView.heightAnchor.constraint(equalToConstant: 7)
        ])
    }

    @objc private func voicePlaybackButtonTapped() {
        guard let row else { return }
        actions.onPlayVoice(row)
    }

    private static func durationText(for voice: ChatMessageRowContent.VoiceContent?) -> String {
        guard let voice else {
            return ChatMessageRowContent.voiceDurationDisplayText(milliseconds: 0)
        }

        let totalText = ChatMessageRowContent.voiceDurationDisplayText(milliseconds: voice.durationMilliseconds)
        guard voice.isPlaying else {
            return totalText
        }

        let elapsedText = ChatMessageRowContent.voiceElapsedDisplayText(
            milliseconds: voice.playbackElapsedMilliseconds
        )
        return "\(elapsedText)/\(totalText)"
    }
}

/// Apple Messages 风格的简易语音波形
@MainActor
private final class MessageVoiceWaveformView: UIView {
    private var playbackProgressValue: Double = 0

    var isPlaying = false {
        didSet {
            setNeedsDisplay()
        }
    }

    var playbackProgress: Double {
        get {
            playbackProgressValue
        }
        set {
            playbackProgressValue = min(1, max(0, newValue))
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

        let bars = 13
        let spacing: CGFloat = 3
        let barWidth = max(2, (rect.width - CGFloat(bars - 1) * spacing) / CGFloat(bars))
        let drawBars: (CGFloat) -> Void = { alpha in
            for index in 0..<bars {
                let progress = CGFloat(index) / CGFloat(max(bars - 1, 1))
                let wave = 0.28 + 0.72 * abs(sin(progress * .pi * 1.35))
                let barHeight = max(5, rect.height * wave)
                let x = CGFloat(index) * (barWidth + spacing)
                let y = (rect.height - barHeight) / 2
                let path = UIBezierPath(
                    roundedRect: CGRect(x: x, y: y, width: barWidth, height: barHeight),
                    cornerRadius: barWidth / 2
                )
                self.tintColor.withAlphaComponent(alpha).setFill()
                path.fill()
            }
        }

        drawBars(0.34)

        guard isPlaying, playbackProgressValue > 0, let context = UIGraphicsGetCurrentContext() else {
            return
        }

        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 0, width: rect.width * CGFloat(playbackProgressValue), height: rect.height))
        drawBars(0.95)
        context.restoreGState()
    }
}

/// 聊天消息单元格内容配置
@MainActor
struct ChatMessageCellContentConfiguration: UIContentConfiguration {
    let row: ChatMessageRowState
    let actions: ChatMessageCellActions
    var isHighlighted = false
    var isSelected = false
    fileprivate var updatesOnlyCellState = false

    init(
        row: ChatMessageRowState,
        actions: ChatMessageCellActions,
        isHighlighted: Bool = false,
        isSelected: Bool = false
    ) {
        self.row = row
        self.actions = actions
        self.isHighlighted = isHighlighted
        self.isSelected = isSelected
    }

    func makeContentView() -> UIView & UIContentView {
        ChatMessageCellContentView(configuration: self)
    }

    func updated(for state: UIConfigurationState) -> ChatMessageCellContentConfiguration {
        var updatedConfiguration = self
        if let cellState = state as? UICellConfigurationState {
            updatedConfiguration.isHighlighted = cellState.isHighlighted
            updatedConfiguration.isSelected = cellState.isSelected
            updatedConfiguration.updatesOnlyCellState = true
        }
        return updatedConfiguration
    }

    static func accessibilityLabel(for row: ChatMessageRowState) -> String {
        var parts = [row.content.accessibilityText]

        if let statusText = row.statusText {
            parts.append(statusText)
        }

        if let uploadProgress = row.uploadProgress {
            parts.append("Uploading \(Int(uploadProgress * 100))%")
        }

        return parts.joined(separator: ", ")
    }
}

/// 聊天消息单元格内容视图
@MainActor
final class ChatMessageCellContentView: UIView, UIContentView, UIContextMenuInteractionDelegate {
    /// 头像加载服务，可在测试中替换。
    static var avatarImageLoader: any AvatarImageLoading = DefaultAvatarImageLoader.shared

    private let avatarView = GradientBackgroundView()
    private let avatarImageView = UIImageView()
    private let avatarInitialLabel = UILabel()
    private let bubbleView = ChatBubbleBackgroundView()
    private let stackView = UIStackView()
    private let metadataStackView = UIStackView()
    private let metadataLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let contentFactory = ChatMessageContentViewFactory()

    private var incomingAvatarLeadingConstraint: NSLayoutConstraint?
    private var incomingBubbleLeadingConstraint: NSLayoutConstraint?
    private var outgoingAvatarTrailingConstraint: NSLayoutConstraint?
    private var outgoingBubbleTrailingToAvatarConstraint: NSLayoutConstraint?
    private var outgoingBubbleTrailingConstraint: NSLayoutConstraint?
    private var neutralBubbleCenterXConstraint: NSLayoutConstraint?
    private var metadataTopConstraint: NSLayoutConstraint?
    private var bubbleTopConstraint: NSLayoutConstraint?
    private var bubbleTopWithoutMetadataConstraint: NSLayoutConstraint?
    private var metadataHiddenHeightConstraint: NSLayoutConstraint?
    private var stackTopConstraint: NSLayoutConstraint?
    private var stackLeadingConstraint: NSLayoutConstraint?
    private var stackTrailingConstraint: NSLayoutConstraint?
    private var stackBottomConstraint: NSLayoutConstraint?
    private var avatarLoadTask: (any AvatarImageLoadTask)?
    private var expectedAvatarURL: String?
    private var row: ChatMessageRowState?
    private var retryMessageID: MessageID?
    private var actions = ChatMessageCellActions.empty
    private var contentViewForMessage: (UIView & ChatMessageContentView)?
    private var currentConfiguration: ChatMessageCellContentConfiguration

    var configuration: UIContentConfiguration {
        get { currentConfiguration }
        set {
            guard let newConfiguration = newValue as? ChatMessageCellContentConfiguration else {
                return
            }
            let shouldOnlyUpdateCellState = newConfiguration.updatesOnlyCellState
                && currentConfiguration.row == newConfiguration.row
            currentConfiguration = newConfiguration
            guard !shouldOnlyUpdateCellState else {
                updateCellState(configuration: newConfiguration)
                return
            }
            apply(configuration: newConfiguration)
        }
    }

    init(configuration: ChatMessageCellContentConfiguration) {
        currentConfiguration = configuration
        super.init(frame: .zero)
        configureView()
        apply(configuration: configuration)
    }

    required init?(coder: NSCoder) {
        currentConfiguration = ChatMessageCellContentConfiguration(
            row: ChatMessageRowState(
                id: "",
                content: .text(""),
                sortSequence: 0,
                timeText: "",
                statusText: nil,
                uploadProgress: nil,
                isOutgoing: false,
                canRetry: false,
                canDelete: false,
                canRevoke: false
            ),
            actions: .empty
        )
        super.init(coder: coder)
        configureView()
    }

    deinit {
        avatarLoadTask?.cancel()
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        let hasUnboundedHeight = !targetSize.height.isFinite
            || targetSize.height >= CGFloat.greatestFiniteMagnitude / 2
        let fittingTargetSize = CGSize(
            width: targetSize.width,
            height: hasUnboundedHeight ? UIView.layoutFittingCompressedSize.height : targetSize.height
        )
        let fittingVerticalPriority = hasUnboundedHeight ? UILayoutPriority.fittingSizeLevel : verticalFittingPriority
        let fittingSize = super.systemLayoutSizeFitting(
            fittingTargetSize,
            withHorizontalFittingPriority: horizontalFittingPriority,
            verticalFittingPriority: fittingVerticalPriority
        )
        guard fittingSize.height.isFinite, fittingSize.height < CGFloat.greatestFiniteMagnitude / 2 else {
            return CGSize(width: fittingSize.width, height: UIView.layoutFittingCompressedSize.height)
        }
        return fittingSize
    }

    private func apply(configuration: ChatMessageCellContentConfiguration) {
        configure(row: configuration.row, actions: configuration.actions)
        updateCellState(configuration: configuration)
    }

    private func updateCellState(configuration: ChatMessageCellContentConfiguration) {
        alpha = configuration.isHighlighted || configuration.isSelected ? 0.82 : 1
    }

    func reset() {
        row = nil
        retryMessageID = nil
        actions = .empty
        retryButton.accessibilityIdentifier = nil
        avatarLoadTask?.cancel()
        avatarLoadTask = nil
        expectedAvatarURL = nil
        avatarImageView.image = nil
        avatarImageView.isHidden = true
    }

    private func configure(row: ChatMessageRowState, actions: ChatMessageCellActions) {
        self.row = row
        retryMessageID = row.id
        self.actions = actions
        configureAvatar(for: row)

        let isRevoked = row.content.kind == .revoked
        let isMedia = row.content.kind == .image || row.content.kind == .video
        let bubbleStyle: ChatBubbleBackgroundView.Style = isRevoked
            ? .revoked
            : (isMedia ? .media : (row.isOutgoing ? .outgoing : .incoming))
        bubbleView.apply(style: bubbleStyle)

        let contentStyle = contentStyle(for: bubbleStyle)
        configureContent(row: row, style: contentStyle, actions: actions)
        configureBubblePadding(style: bubbleStyle)

        let progressText = row.uploadProgress.map { "Uploading \(Int($0 * 100))%" }
        let metadataText = [
            row.showsTimeSeparator ? row.timeText : nil,
            progressText ?? row.statusText
        ].compactMap { $0 }.joined(separator: " · ")
        let showsMetadataText = !metadataText.isEmpty
        let showsMetadata = showsMetadataText || row.canRetry
        metadataLabel.text = metadataText
        metadataLabel.isHidden = !showsMetadataText
        metadataLabel.textColor = .secondaryLabel
        retryButton.isHidden = !row.canRetry
        retryButton.tintColor = .systemBlue
        retryButton.accessibilityIdentifier = "chat.retryButton.\(row.id.rawValue)"
        metadataStackView.isHidden = !showsMetadata
        metadataHiddenHeightConstraint?.isActive = !showsMetadata
        metadataTopConstraint?.constant = showsMetadata ? 4 : 0
        bubbleTopConstraint?.isActive = showsMetadata
        bubbleTopWithoutMetadataConstraint?.isActive = !showsMetadata

        let showsAvatar = !isRevoked
        incomingAvatarLeadingConstraint?.isActive = showsAvatar && !row.isOutgoing
        incomingBubbleLeadingConstraint?.isActive = showsAvatar && !row.isOutgoing
        outgoingAvatarTrailingConstraint?.isActive = showsAvatar && row.isOutgoing
        outgoingBubbleTrailingToAvatarConstraint?.isActive = showsAvatar && row.isOutgoing
        outgoingBubbleTrailingConstraint?.isActive = !showsAvatar && row.isOutgoing
        neutralBubbleCenterXConstraint?.isActive = !showsAvatar && !row.isOutgoing
    }

    private func contentStyle(for bubbleStyle: ChatBubbleBackgroundView.Style) -> ChatMessageContentStyle {
        switch bubbleStyle {
        case .outgoing:
            return ChatMessageContentStyle(
                textColor: .white,
                secondaryTextColor: UIColor.white.withAlphaComponent(0.72),
                tintColor: .white
            )
        case .revoked:
            return ChatMessageContentStyle(
                textColor: .secondaryLabel,
                secondaryTextColor: .secondaryLabel,
                tintColor: .systemBlue
            )
        case .incoming, .media:
            return ChatMessageContentStyle(
                textColor: .label,
                secondaryTextColor: .secondaryLabel,
                tintColor: .systemBlue
            )
        }
    }

    private func configureContent(
        row: ChatMessageRowState,
        style: ChatMessageContentStyle,
        actions: ChatMessageCellActions
    ) {
        let kind = ChatMessageContentKind(row: row)
        let contentView = contentFactory.view(for: kind, reusing: contentViewForMessage)

        if contentView !== contentViewForMessage {
            if let contentViewForMessage {
                stackView.removeArrangedSubview(contentViewForMessage)
                contentViewForMessage.removeFromSuperview()
            }

            stackView.insertArrangedSubview(contentView, at: 0)
            contentViewForMessage = contentView
        }

        contentView.configure(row: row, style: style, actions: actions)
    }

    private func configureBubblePadding(style: ChatBubbleBackgroundView.Style) {
        guard style != .media else {
            stackTopConstraint?.constant = 0
            stackLeadingConstraint?.constant = 0
            stackTrailingConstraint?.constant = 0
            stackBottomConstraint?.constant = 0
            return
        }

        let tailWidth: CGFloat = 7
        let vertical: CGFloat = 10
        let horizontal: CGFloat = 13
        let leading = horizontal + (style == .incoming ? tailWidth : 0)
        let trailing = horizontal + (style == .outgoing ? tailWidth : 0)
        stackTopConstraint?.constant = vertical
        stackLeadingConstraint?.constant = leading
        stackTrailingConstraint?.constant = -trailing
        stackBottomConstraint?.constant = -vertical
    }

    private func configureView() {
        backgroundColor = .clear

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.setColors(ChatBridgeDesignSystem.GradientToken.neutralAvatar)
        avatarView.layer.cornerRadius = 15
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
        avatarInitialLabel.textColor = .secondaryLabel
        avatarInitialLabel.textAlignment = .center
        avatarInitialLabel.isAccessibilityElement = false

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.isUserInteractionEnabled = true
        bubbleView.addInteraction(UIContextMenuInteraction(delegate: self))

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 4

        metadataStackView.translatesAutoresizingMaskIntoConstraints = false
        metadataStackView.axis = .horizontal
        metadataStackView.alignment = .center
        metadataStackView.spacing = 5

        metadataLabel.font = .preferredFont(forTextStyle: .caption2)
        metadataLabel.adjustsFontForContentSizeCategory = true
        metadataLabel.numberOfLines = 1
        metadataLabel.textAlignment = .center

        retryButton.setTitle(nil, for: .normal)
        retryButton.setImage(UIImage(systemName: "exclamationmark.circle.fill"), for: .normal)
        retryButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold),
            forImageIn: .normal
        )
        retryButton.addTarget(self, action: #selector(retryButtonTapped), for: .touchUpInside)

        addSubview(avatarView)
        avatarView.addSubview(avatarInitialLabel)
        avatarView.addSubview(avatarImageView)
        addSubview(bubbleView)
        addSubview(metadataStackView)
        bubbleView.addSubview(stackView)
        metadataStackView.addArrangedSubview(metadataLabel)
        metadataStackView.addArrangedSubview(retryButton)

        incomingAvatarLeadingConstraint = avatarView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor)
        incomingBubbleLeadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 8)
        outgoingAvatarTrailingConstraint = avatarView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor)
        outgoingBubbleTrailingToAvatarConstraint = bubbleView.trailingAnchor.constraint(equalTo: avatarView.leadingAnchor, constant: -8)
        outgoingBubbleTrailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor)
        neutralBubbleCenterXConstraint = bubbleView.centerXAnchor.constraint(equalTo: centerXAnchor)

        let metadataTopConstraint = metadataStackView.topAnchor.constraint(equalTo: topAnchor, constant: 4)
        let bubbleTopConstraint = bubbleView.topAnchor.constraint(equalTo: metadataStackView.bottomAnchor, constant: 4)
        let bubbleTopWithoutMetadataConstraint = bubbleView.topAnchor.constraint(equalTo: topAnchor)
        let metadataHiddenHeightConstraint = metadataStackView.heightAnchor.constraint(equalToConstant: 0)
        let stackTopConstraint = stackView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10)
        let stackLeadingConstraint = stackView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 13)
        let stackTrailingConstraint = stackView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -13)
        let stackBottomConstraint = stackView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10)
        self.metadataTopConstraint = metadataTopConstraint
        self.bubbleTopConstraint = bubbleTopConstraint
        self.bubbleTopWithoutMetadataConstraint = bubbleTopWithoutMetadataConstraint
        self.metadataHiddenHeightConstraint = metadataHiddenHeightConstraint
        self.stackTopConstraint = stackTopConstraint
        self.stackLeadingConstraint = stackLeadingConstraint
        self.stackTrailingConstraint = stackTrailingConstraint
        self.stackBottomConstraint = stackBottomConstraint

        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: bubbleView.topAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 30),
            avatarView.heightAnchor.constraint(equalToConstant: 30),

            avatarInitialLabel.topAnchor.constraint(equalTo: avatarView.topAnchor),
            avatarInitialLabel.leadingAnchor.constraint(equalTo: avatarView.leadingAnchor),
            avatarInitialLabel.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor),
            avatarInitialLabel.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor),

            avatarImageView.topAnchor.constraint(equalTo: avatarView.topAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: avatarView.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor),

            metadataTopConstraint,
            metadataStackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            metadataStackView.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
            metadataStackView.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),

            bubbleTopConstraint,
            bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.72),

            retryButton.widthAnchor.constraint(equalToConstant: 22),
            retryButton.heightAnchor.constraint(equalToConstant: 22),

            stackTopConstraint,
            stackLeadingConstraint,
            stackTrailingConstraint,
            stackBottomConstraint
        ])
    }

    private func configureAvatar(for row: ChatMessageRowState) {
        avatarLoadTask?.cancel()
        avatarLoadTask = nil
        expectedAvatarURL = row.senderAvatarURL
        avatarView.isHidden = row.content.kind == .revoked
        avatarInitialLabel.text = row.isOutgoing ? "Me" : "C"
        avatarImageView.image = nil
        avatarImageView.isHidden = true

        guard let avatarURL = row.senderAvatarURL?.trimmingCharacters(in: .whitespacesAndNewlines), !avatarURL.isEmpty else {
            return
        }

        avatarLoadTask = Self.avatarImageLoader.loadImage(from: avatarURL) { [weak self] image in
            guard let self, self.expectedAvatarURL == avatarURL, let image else {
                return
            }

            self.avatarImageView.image = image
            self.avatarImageView.isHidden = false
        }
    }

    @objc private func retryButtonTapped() {
        guard let retryMessageID else { return }
        actions.onRetry(retryMessageID)
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let row, row.canDelete || row.canRevoke else {
            return nil
        }

        return UIContextMenuConfiguration(identifier: row.diffIdentifier as NSString, previewProvider: nil) { [weak self] _ in
            var menuActions: [UIAction] = []

            if row.canRevoke {
                menuActions.append(
                    UIAction(title: "Revoke", image: UIImage(systemName: "arrow.uturn.backward")) { _ in
                        self?.actions.onRevoke(row.id)
                    }
                )
            }

            if row.canDelete {
                menuActions.append(
                    UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                        self?.actions.onDelete(row.id)
                    }
                )
            }

            return UIMenu(children: menuActions)
        }
    }
}

/// 聊天消息单元格
@MainActor
final class ChatMessageCell: UICollectionViewCell {
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
        accessibilityIdentifier = nil
        accessibilityLabel = nil
        (contentView.subviews.first as? ChatMessageCellContentView)?.reset()
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        guard let configuration = contentConfiguration as? ChatMessageCellContentConfiguration else {
            return
        }
        contentConfiguration = configuration.updated(for: state)
    }

    func configure(row: ChatMessageRowState, actions: ChatMessageCellActions) {
        let configuration = ChatMessageCellContentConfiguration(row: row, actions: actions)
        contentConfiguration = configuration
        applyAccessibility(from: configuration)
    }

    private func configureView() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
    }

    private func applyAccessibility(from configuration: UIContentConfiguration?) {
        guard let configuration = configuration as? ChatMessageCellContentConfiguration else {
            accessibilityIdentifier = nil
            accessibilityLabel = nil
            return
        }

        accessibilityIdentifier = "chat.messageCell.\(configuration.row.id.rawValue)"
        accessibilityLabel = ChatMessageCellContentConfiguration.accessibilityLabel(for: configuration.row)
    }
}
