//
//  ChatMessageCellContentView.swift
//  AppleIM
//

import UIKit

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
            parts.append(Self.uploadProgressText(uploadProgress))
        }

        return parts.joined(separator: ", ")
    }

    static func uploadProgressText(_ progress: Double) -> String {
        L10n.shared.tr("chat.upload.progress.accessibility", Int(progress * 100))
    }
}

/// 聊天消息单元格内容视图
@MainActor
final class ChatMessageCellContentView: UIView, UIContentView, UIContextMenuInteractionDelegate {
    /// 头像加载服务，可在测试中替换。
    static var avatarImageLoader: any AvatarImageLoading = DefaultAvatarImageLoader.shared

    private enum Layout {
        static let singleLineBubbleHeight: CGFloat = 40
        static let avatarDiameter = singleLineBubbleHeight
        static let defaultVerticalPadding: CGFloat = 10
        static let defaultHorizontalPadding: CGFloat = 13
        static let voiceVerticalPadding: CGFloat = 6
        static let revokedVerticalPadding: CGFloat = 6
        static let revokedHorizontalPadding: CGFloat = 10
        static let tailWidth: CGFloat = 7
    }

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

        let kind = ChatMessageContentKind(row: row)
        let isRevoked = kind == .revoked
        let bubbleStyle = Self.bubbleStyle(for: row, kind: kind)
        bubbleView.apply(style: bubbleStyle)

        let contentStyle = contentStyle(for: bubbleStyle)
        configureContent(row: row, style: contentStyle, actions: actions)
        configureBubblePadding(style: bubbleStyle, kind: kind)

        let progressText = row.uploadProgress.map(ChatMessageCellContentConfiguration.uploadProgressText)
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
        outgoingBubbleTrailingConstraint?.isActive = !showsAvatar && row.isOutgoing && !isRevoked
        neutralBubbleCenterXConstraint?.isActive = isRevoked || (!showsAvatar && !row.isOutgoing)
    }

    private static func bubbleStyle(
        for row: ChatMessageRowState,
        kind: ChatMessageContentKind
    ) -> ChatBubbleBackgroundView.Style {
        switch kind {
        case .text, .voice:
            return row.isOutgoing ? .weChatOutgoing : .weChatIncoming
        case .image, .video:
            return .media
        case .revoked:
            return .revoked
        case .file:
            return row.isOutgoing ? .outgoing : .incoming
        case .emoji:
            return .plain
        }
    }

    private func contentStyle(for bubbleStyle: ChatBubbleBackgroundView.Style) -> ChatMessageContentStyle {
        switch bubbleStyle {
        case .outgoing:
            return ChatMessageContentStyle(
                textColor: .white,
                secondaryTextColor: UIColor.white.withAlphaComponent(0.72),
                tintColor: .white
            )
        case .weChatOutgoing, .weChatIncoming:
            return ChatMessageContentStyle(
                textColor: .label,
                secondaryTextColor: .secondaryLabel,
                tintColor: .label
            )
        case .revoked:
            return ChatMessageContentStyle(
                textColor: .secondaryLabel,
                secondaryTextColor: .secondaryLabel,
                tintColor: .systemBlue
            )
        case .incoming, .media, .plain:
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

    private func configureBubblePadding(
        style: ChatBubbleBackgroundView.Style,
        kind: ChatMessageContentKind
    ) {
        guard style != .media && style != .plain else {
            stackTopConstraint?.constant = 0
            stackLeadingConstraint?.constant = 0
            stackTrailingConstraint?.constant = 0
            stackBottomConstraint?.constant = 0
            return
        }

        let hasLeadingTail = style == .incoming || style == .weChatIncoming
        let hasTrailingTail = style == .outgoing || style == .weChatOutgoing
        let vertical: CGFloat
        let horizontal: CGFloat
        if style == .revoked {
            vertical = Layout.revokedVerticalPadding
            horizontal = Layout.revokedHorizontalPadding
        } else if kind == .voice {
            vertical = Layout.voiceVerticalPadding
            horizontal = Layout.defaultHorizontalPadding
        } else {
            vertical = Layout.defaultVerticalPadding
            horizontal = Layout.defaultHorizontalPadding
        }
        let leading = horizontal + (hasLeadingTail ? Layout.tailWidth : 0)
        let trailing = horizontal + (hasTrailingTail ? Layout.tailWidth : 0)
        stackTopConstraint?.constant = vertical
        stackLeadingConstraint?.constant = leading
        stackTrailingConstraint?.constant = -trailing
        stackBottomConstraint?.constant = -vertical
    }

    private func configureView() {
        backgroundColor = .clear

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.setColors(ChatBridgeDesignSystem.GradientToken.neutralAvatar)
        avatarView.layer.cornerRadius = Layout.avatarDiameter / 2
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
        let stackTopConstraint = stackView.topAnchor.constraint(
            equalTo: bubbleView.topAnchor,
            constant: Layout.defaultVerticalPadding
        )
        let stackLeadingConstraint = stackView.leadingAnchor.constraint(
            equalTo: bubbleView.leadingAnchor,
            constant: Layout.defaultHorizontalPadding
        )
        let stackTrailingConstraint = stackView.trailingAnchor.constraint(
            equalTo: bubbleView.trailingAnchor,
            constant: -Layout.defaultHorizontalPadding
        )
        let stackBottomConstraint = stackView.bottomAnchor.constraint(
            equalTo: bubbleView.bottomAnchor,
            constant: -Layout.defaultVerticalPadding
        )
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
            avatarView.widthAnchor.constraint(equalToConstant: Layout.avatarDiameter),
            avatarView.heightAnchor.constraint(equalToConstant: Layout.avatarDiameter),

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
