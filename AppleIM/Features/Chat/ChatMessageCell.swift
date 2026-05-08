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
        case .text, .file, .revoked:
            if let textView = existingView as? TextMessageContentView {
                return textView
            }
            return TextMessageContentView()
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

/// 图片和视频消息内容视图
@MainActor
final class MediaMessageContentView: UIView, ChatMessageContentView {
    private let stackView = UIStackView()
    private let thumbnailImageView = UIImageView()
    private let videoStackView = UIStackView()
    private let videoPlaybackButton = UIButton(type: .system)
    private let videoDurationLabel = UILabel()
    private let fallbackLabel = UILabel()
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

        if let thumbnailPath {
            thumbnailImageView.image = UIImage(contentsOfFile: thumbnailPath)
        } else {
            thumbnailImageView.image = nil
        }

        thumbnailImageView.isHidden = false
        fallbackLabel.text = isVideo ? "Video unavailable" : "Image unavailable"
        fallbackLabel.textColor = style.textColor
        fallbackLabel.isHidden = thumbnailImageView.image != nil

        videoStackView.isHidden = !isVideo
        videoPlaybackButton.tintColor = style.tintColor
        videoPlaybackButton.accessibilityLabel = "Play Video"
        videoDurationLabel.text = Self.durationText(milliseconds: videoDurationMilliseconds ?? 0)
        videoDurationLabel.textColor = style.textColor
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 4

        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailImageView.contentMode = .scaleAspectFill
        thumbnailImageView.clipsToBounds = true
        thumbnailImageView.layer.cornerRadius = ChatBridgeDesignSystem.RadiusToken.media

        videoStackView.translatesAutoresizingMaskIntoConstraints = false
        videoStackView.axis = .horizontal
        videoStackView.alignment = .center
        videoStackView.spacing = 8

        videoPlaybackButton.translatesAutoresizingMaskIntoConstraints = false
        videoPlaybackButton.setImage(UIImage(systemName: "play.circle.fill"), for: .normal)
        videoPlaybackButton.addTarget(self, action: #selector(videoPlaybackButtonTapped), for: .touchUpInside)

        videoDurationLabel.font = .preferredFont(forTextStyle: .body)
        videoDurationLabel.adjustsFontForContentSizeCategory = true

        fallbackLabel.font = .preferredFont(forTextStyle: .body)
        fallbackLabel.adjustsFontForContentSizeCategory = true
        fallbackLabel.numberOfLines = 0

        videoStackView.addArrangedSubview(videoPlaybackButton)
        videoStackView.addArrangedSubview(videoDurationLabel)
        stackView.addArrangedSubview(thumbnailImageView)
        stackView.addArrangedSubview(videoStackView)
        stackView.addArrangedSubview(fallbackLabel)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            thumbnailImageView.widthAnchor.constraint(equalToConstant: 180),
            thumbnailImageView.heightAnchor.constraint(equalToConstant: 180),
            videoPlaybackButton.widthAnchor.constraint(equalToConstant: 28),
            videoPlaybackButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    @objc private func videoPlaybackButtonTapped() {
        guard let row else { return }
        actions.onPlayVideo(row)
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
        voiceDurationLabel.text = Self.durationText(milliseconds: voice?.durationMilliseconds ?? 0)
        voiceDurationLabel.textColor = style.textColor
        voiceUnreadDotView.isHidden = !(voice?.isUnplayed == true)
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8

        voicePlaybackButton.translatesAutoresizingMaskIntoConstraints = false
        voicePlaybackButton.addTarget(self, action: #selector(voicePlaybackButtonTapped), for: .touchUpInside)

        voiceDurationLabel.font = .preferredFont(forTextStyle: .body)
        voiceDurationLabel.adjustsFontForContentSizeCategory = true

        voiceUnreadDotView.translatesAutoresizingMaskIntoConstraints = false
        voiceUnreadDotView.backgroundColor = .systemRed
        voiceUnreadDotView.layer.cornerRadius = 4
        voiceUnreadDotView.isHidden = true

        stackView.addArrangedSubview(voicePlaybackButton)
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
            voiceUnreadDotView.widthAnchor.constraint(equalToConstant: 8),
            voiceUnreadDotView.heightAnchor.constraint(equalToConstant: 8)
        ])
    }

    @objc private func voicePlaybackButtonTapped() {
        guard let row else { return }
        actions.onPlayVoice(row)
    }

    private static func durationText(milliseconds: Int) -> String {
        let seconds = max(1, Int((Double(milliseconds) / 1_000.0).rounded()))
        return "\(seconds)s"
    }
}

/// 聊天消息单元格
@MainActor
final class ChatMessageCell: UICollectionViewCell, UIContextMenuInteractionDelegate {
    private static let avatarImageCache = NSCache<NSString, UIImage>()

    private let avatarView = GradientBackgroundView()
    private let avatarImageView = UIImageView()
    private let avatarInitialLabel = UILabel()
    private let bubbleView = ChatBubbleBackgroundView()
    private let stackView = UIStackView()
    private let metadataLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let contentFactory = ChatMessageContentViewFactory()

    private var incomingAvatarLeadingConstraint: NSLayoutConstraint?
    private var incomingBubbleLeadingConstraint: NSLayoutConstraint?
    private var outgoingAvatarTrailingConstraint: NSLayoutConstraint?
    private var outgoingBubbleTrailingConstraint: NSLayoutConstraint?
    private var avatarDataTask: URLSessionDataTask?
    private var expectedAvatarURL: String?
    private var row: ChatMessageRowState?
    private var retryMessageID: MessageID?
    private var actions = ChatMessageCellActions.empty
    private var contentViewForMessage: (UIView & ChatMessageContentView)?

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
        actions = .empty
        accessibilityIdentifier = nil
        accessibilityLabel = nil
        retryButton.accessibilityIdentifier = nil
        avatarDataTask?.cancel()
        avatarDataTask = nil
        expectedAvatarURL = nil
        avatarImageView.image = nil
        avatarImageView.isHidden = true
    }

    func configure(row: ChatMessageRowState, actions: ChatMessageCellActions) {
        self.row = row
        retryMessageID = row.id
        self.actions = actions
        accessibilityIdentifier = "chat.messageCell.\(row.id.rawValue)"
        accessibilityLabel = Self.accessibilityLabel(for: row)
        configureAvatar(for: row)

        let isRevoked = row.content.kind == .revoked
        let bubbleStyle: ChatBubbleBackgroundView.Style = isRevoked ? .revoked : (row.isOutgoing ? .outgoing : .incoming)
        bubbleView.apply(style: bubbleStyle)

        let foregroundColor: UIColor = row.isOutgoing && !isRevoked ? .white : .label
        let secondaryColor: UIColor = row.isOutgoing && !isRevoked ? .white.withAlphaComponent(0.75) : .secondaryLabel
        let tintColor: UIColor = row.isOutgoing && !isRevoked ? .white : .systemBlue
        let contentStyle = ChatMessageContentStyle(
            textColor: foregroundColor,
            secondaryTextColor: secondaryColor,
            tintColor: tintColor
        )
        configureContent(row: row, style: contentStyle, actions: actions)

        let progressText = row.uploadProgress.map { "Uploading \(Int($0 * 100))%" }
        metadataLabel.text = [row.timeText, progressText ?? row.statusText].compactMap { $0 }.joined(separator: " · ")
        metadataLabel.textColor = secondaryColor
        retryButton.isHidden = !row.canRetry
        retryButton.tintColor = row.isOutgoing ? .white : .systemBlue
        retryButton.accessibilityIdentifier = "chat.retryButton.\(row.id.rawValue)"

        incomingAvatarLeadingConstraint?.isActive = !row.isOutgoing
        incomingBubbleLeadingConstraint?.isActive = !row.isOutgoing
        outgoingAvatarTrailingConstraint?.isActive = row.isOutgoing
        outgoingBubbleTrailingConstraint?.isActive = row.isOutgoing
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
        bubbleView.addInteraction(UIContextMenuInteraction(delegate: self))

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 4

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
            stackView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8)
        ])
    }

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

        let cacheKey = avatarURL
        if let cachedImage = Self.avatarImageCache.object(forKey: cacheKey as NSString) {
            avatarImageView.image = cachedImage
            avatarImageView.isHidden = false
            return
        }

        if let localImage = Self.localAvatarImage(from: avatarURL) {
            Self.avatarImageCache.setObject(localImage, forKey: cacheKey as NSString)
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

            Task { @MainActor in
                Self.avatarImageCache.setObject(image, forKey: cacheKey as NSString)

                guard let self, self.expectedAvatarURL == avatarURL else {
                    return
                }

                self.avatarImageView.image = image
                self.avatarImageView.isHidden = false
            }
        }
        avatarDataTask?.resume()
    }

    private static func localAvatarImage(from value: String) -> UIImage? {
        if let url = URL(string: value), url.isFileURL {
            return UIImage(contentsOfFile: url.path)
        }

        guard !value.hasPrefix("http://"), !value.hasPrefix("https://") else {
            return nil
        }

        return UIImage(contentsOfFile: value)
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

    private static func accessibilityLabel(for row: ChatMessageRowState) -> String {
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
