//
//  ChatBridgeDesignSystem.swift
//  AppleIM
//
//  Shared UIKit styling for the ChatBridge visual refresh.
//

import UIKit

enum ChatBridgeDesignSystem {
    enum ColorToken {
        static let mint = UIColor.chatBridgeHex(0x27D9A5)
        static let sky = UIColor.chatBridgeHex(0x4DA3FF)
        static let coral = UIColor.chatBridgeHex(0xFF5A7A)
        static let ink = UIColor { traits in
            traits.userInterfaceStyle == .dark ? .white : UIColor.chatBridgeHex(0x111827)
        }
        static let backgroundStart = UIColor.chatBridgeHex(0xEAFBFF)
        static let backgroundMiddle = UIColor.chatBridgeHex(0xF7F1FF)
        static let backgroundEnd = UIColor.chatBridgeHex(0xFFF7EA)

        static var incomingCard: UIColor {
            UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.86)
                    : UIColor.white.withAlphaComponent(0.88)
            }
        }

        static var elevatedCard: UIColor {
            UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor.tertiarySystemGroupedBackground.withAlphaComponent(0.82)
                    : UIColor.white.withAlphaComponent(0.76)
            }
        }

        static var pinnedCard: UIColor {
            UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? mint.withAlphaComponent(0.18)
                    : mint.withAlphaComponent(0.14)
            }
        }
    }

    enum GradientToken {
        static let appBackground = [ColorToken.backgroundStart, ColorToken.backgroundMiddle, ColorToken.backgroundEnd]
        static let outgoingBubble = [ColorToken.mint, UIColor.chatBridgeHex(0x3B82F6)]
        static let brandButton = [ColorToken.mint, ColorToken.sky]
        static let playfulAvatar = [ColorToken.coral, ColorToken.sky]
    }

    enum RadiusToken {
        static let pageCard: CGFloat = 22
        static let inputBar: CGFloat = 24
        static let messageBubble: CGFloat = 18
        static let media: CGFloat = 14
        static let badge: CGFloat = 11
        static let field: CGFloat = 17
    }

    enum SpacingToken {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum ShadowToken {
        static func applyCardShadow(to layer: CALayer) {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.10
            layer.shadowRadius = 18
            layer.shadowOffset = CGSize(width: 0, height: 10)
        }

        static func applyBubbleShadow(to layer: CALayer) {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.08
            layer.shadowRadius = 10
            layer.shadowOffset = CGSize(width: 0, height: 5)
        }
    }

    enum ButtonRole {
        case primary
        case secondary
        case circularTool
        case destructive
    }

    static func makeGlassButtonConfiguration(role: ButtonRole) -> UIButton.Configuration {
        if #available(iOS 26.0, *) {
            switch role {
            case .primary:
                return UIButton.Configuration.prominentGlass()
            case .secondary, .circularTool:
                return UIButton.Configuration.glass()
            case .destructive:
                return UIButton.Configuration.prominentClearGlass()
            }
        }

        return makeFallbackButtonConfiguration(role: role)
    }

    static func makeFallbackButtonConfiguration(role: ButtonRole) -> UIButton.Configuration {
        var configuration: UIButton.Configuration

        switch role {
        case .primary:
            configuration = .filled()
            configuration.baseBackgroundColor = ColorToken.mint
            configuration.baseForegroundColor = .white
        case .secondary:
            configuration = .tinted()
            configuration.baseBackgroundColor = ColorToken.sky.withAlphaComponent(0.18)
            configuration.baseForegroundColor = ColorToken.sky
        case .circularTool:
            configuration = .tinted()
            configuration.baseBackgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.88)
            configuration.baseForegroundColor = ColorToken.sky
        case .destructive:
            configuration = .tinted()
            configuration.baseBackgroundColor = ColorToken.coral.withAlphaComponent(0.14)
            configuration.baseForegroundColor = ColorToken.coral
        }

        configuration.cornerStyle = .capsule
        return configuration
    }
}

final class GradientBackgroundView: UIView {
    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    private var gradientLayer: CAGradientLayer {
        layer as! CAGradientLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func setColors(_ colors: [UIColor]) {
        gradientLayer.colors = colors.map(\.cgColor)
    }

    private func configure() {
        isUserInteractionEnabled = false
        gradientLayer.startPoint = CGPoint(x: 0.05, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        setColors(ChatBridgeDesignSystem.GradientToken.appBackground)
    }
}

final class GlassContainerView: UIView {
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let tintView = UIView()

    var contentView: UIView {
        blurView.contentView
    }

    init(cornerRadius: CGFloat = ChatBridgeDesignSystem.RadiusToken.pageCard) {
        super.init(frame: .zero)
        configure(cornerRadius: cornerRadius)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure(cornerRadius: ChatBridgeDesignSystem.RadiusToken.pageCard)
    }

    private func configure(cornerRadius: CGFloat) {
        clipsToBounds = false
        layer.cornerRadius = cornerRadius
        ChatBridgeDesignSystem.ShadowToken.applyCardShadow(to: layer)

        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.clipsToBounds = true
        blurView.layer.cornerRadius = cornerRadius

        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.backgroundColor = ChatBridgeDesignSystem.ColorToken.elevatedCard
        tintView.isUserInteractionEnabled = false

        addSubview(blurView)
        blurView.contentView.addSubview(tintView)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            tintView.topAnchor.constraint(equalTo: blurView.contentView.topAnchor),
            tintView.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor),
            tintView.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor)
        ])
    }
}

enum ChatBubbleStyle {
    case outgoing
    case incoming
    case revoked

    var backgroundStyle: ChatBubbleBackgroundView.Style {
        switch self {
        case .outgoing:
            return .outgoing
        case .incoming:
            return .incoming
        case .revoked:
            return .revoked
        }
    }
}

final class GradientButtonBackgroundView: UIView {
    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    private var gradientLayer: CAGradientLayer {
        layer as! CAGradientLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isUserInteractionEnabled = false
        layer.cornerRadius = ChatBridgeDesignSystem.RadiusToken.inputBar
        layer.masksToBounds = true
        gradientLayer.colors = ChatBridgeDesignSystem.GradientToken.brandButton.map(\.cgColor)
        gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
    }
}

final class ChatBubbleBackgroundView: UIView {
    enum Style {
        case outgoing
        case incoming
        case revoked
    }

    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    private var gradientLayer: CAGradientLayer {
        layer as! CAGradientLayer
    }

    private(set) var style: Style = .incoming

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func apply(style: Style) {
        self.style = style

        switch style {
        case .outgoing:
            gradientLayer.colors = ChatBridgeDesignSystem.GradientToken.outgoingBubble.map(\.cgColor)
        case .incoming:
            let color = ChatBridgeDesignSystem.ColorToken.incomingCard
            gradientLayer.colors = [color.cgColor, color.cgColor]
        case .revoked:
            let color = UIColor.tertiarySystemGroupedBackground
            gradientLayer.colors = [color.cgColor, color.cgColor]
        }
    }

    func apply(style: ChatBubbleStyle) {
        apply(style: style.backgroundStyle)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        apply(style: style)
    }

    private func configure() {
        layer.cornerRadius = ChatBridgeDesignSystem.RadiusToken.messageBubble
        layer.masksToBounds = true
        gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.15)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        apply(style: Style.incoming)
    }
}

final class RoundedConversationCell: UICollectionViewCell {
    private static let avatarImageCache = NSCache<NSString, UIImage>()

    private let cardView = UIView()
    private let avatarView = GradientBackgroundView()
    private let avatarImageView = UIImageView()
    private let avatarLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let timeLabel = UILabel()
    private let statusStackView = UIStackView()
    private let unreadLabel = ChatBridgeUnreadBadgeLabel()
    private let mutedLabel = UILabel()
    private var avatarDataTask: URLSessionDataTask?
    private var expectedAvatarURL: String?

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
        unreadLabel.isHidden = true
        mutedLabel.isHidden = true
        cardView.backgroundColor = ChatBridgeDesignSystem.ColorToken.incomingCard
        resetAvatarImage()
    }

    func configure(row: ConversationListRowState) {
        titleLabel.text = row.title
        subtitleLabel.text = row.subtitle
        timeLabel.text = row.timeText
        unreadLabel.text = row.unreadText
        unreadLabel.isHidden = row.unreadText == nil
        mutedLabel.isHidden = row.unreadText != nil || !row.isMuted
        avatarLabel.text = Self.initials(from: row.title)
        avatarView.setColors(row.isPinned ? ChatBridgeDesignSystem.GradientToken.brandButton : ChatBridgeDesignSystem.GradientToken.playfulAvatar)
        configureAvatarImage(from: row.avatarURL)
        cardView.backgroundColor = row.isPinned ? ChatBridgeDesignSystem.ColorToken.pinnedCard : ChatBridgeDesignSystem.ColorToken.incomingCard
    }

    func configure(searchRow: SearchResultRowState) {
        titleLabel.text = searchRow.title
        subtitleLabel.text = searchRow.subtitle
        timeLabel.text = searchRow.kind.displayText
        unreadLabel.isHidden = true
        mutedLabel.isHidden = true
        avatarLabel.text = Self.initials(from: searchRow.title)
        avatarView.setColors(ChatBridgeDesignSystem.GradientToken.brandButton)
        resetAvatarImage()
        cardView.backgroundColor = ChatBridgeDesignSystem.ColorToken.incomingCard
    }

    private func configureView() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = ChatBridgeDesignSystem.ColorToken.incomingCard
        cardView.layer.cornerRadius = ChatBridgeDesignSystem.RadiusToken.pageCard
        cardView.layer.masksToBounds = false
        ChatBridgeDesignSystem.ShadowToken.applyCardShadow(to: cardView.layer)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.layer.cornerRadius = 24
        avatarView.layer.masksToBounds = true

        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.isHidden = true
        avatarImageView.isAccessibilityElement = false
        avatarImageView.accessibilityIdentifier = "conversation.avatarImageView"

        avatarLabel.translatesAutoresizingMaskIntoConstraints = false
        avatarLabel.font = .preferredFont(forTextStyle: .headline)
        avatarLabel.textColor = .white
        avatarLabel.textAlignment = .center
        avatarLabel.adjustsFontForContentSizeCategory = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 2

        timeLabel.font = .preferredFont(forTextStyle: .caption2)
        timeLabel.textColor = .secondaryLabel
        timeLabel.adjustsFontForContentSizeCategory = true
        timeLabel.textAlignment = .right

        mutedLabel.font = .preferredFont(forTextStyle: .caption2)
        mutedLabel.textColor = .tertiaryLabel
        mutedLabel.text = "Muted"
        mutedLabel.adjustsFontForContentSizeCategory = true
        mutedLabel.isHidden = true

        statusStackView.translatesAutoresizingMaskIntoConstraints = false
        statusStackView.axis = .vertical
        statusStackView.alignment = .trailing
        statusStackView.spacing = ChatBridgeDesignSystem.SpacingToken.xs
        statusStackView.addArrangedSubview(timeLabel)
        statusStackView.addArrangedSubview(unreadLabel)
        statusStackView.addArrangedSubview(mutedLabel)

        contentView.addSubview(cardView)
        cardView.addSubview(avatarView)
        avatarView.addSubview(avatarLabel)
        avatarView.addSubview(avatarImageView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(subtitleLabel)
        cardView.addSubview(statusStackView)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),

            avatarView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            avatarView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 48),
            avatarView.heightAnchor.constraint(equalToConstant: 48),

            avatarLabel.topAnchor.constraint(equalTo: avatarView.topAnchor),
            avatarLabel.leadingAnchor.constraint(equalTo: avatarView.leadingAnchor),
            avatarLabel.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor),
            avatarLabel.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor),

            avatarImageView.topAnchor.constraint(equalTo: avatarView.topAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: avatarView.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor),

            statusStackView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 14),
            statusStackView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            statusStackView.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 13),
            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusStackView.leadingAnchor, constant: -10),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -12)
        ])
    }

    private func configureAvatarImage(from value: String?) {
        resetAvatarImage()

        guard let avatarURL = value?.trimmingCharacters(in: .whitespacesAndNewlines), !avatarURL.isEmpty else {
            return
        }

        expectedAvatarURL = avatarURL
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
            guard let data else {
                return
            }

            DispatchQueue.main.async {
                guard let self, self.expectedAvatarURL == avatarURL, let image = UIImage(data: data) else {
                    return
                }

                Self.avatarImageCache.setObject(image, forKey: avatarURL as NSString)
                self.avatarImageView.image = image
                self.avatarImageView.isHidden = false
            }
        }
        avatarDataTask?.resume()
    }

    private func resetAvatarImage() {
        avatarDataTask?.cancel()
        avatarDataTask = nil
        expectedAvatarURL = nil
        avatarImageView.image = nil
        avatarImageView.isHidden = true
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

    private static func initials(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first.map { String($0).uppercased() } ?? "C"
    }
}

final class ChatBridgeUnreadBadgeLabel: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: max(size.width + 12, 22), height: 22)
    }

    private func configure() {
        textAlignment = .center
        textColor = .white
        backgroundColor = ChatBridgeDesignSystem.ColorToken.coral
        font = .preferredFont(forTextStyle: .caption2)
        adjustsFontForContentSizeCategory = true
        layer.cornerRadius = ChatBridgeDesignSystem.RadiusToken.badge
        layer.masksToBounds = true
    }
}

extension SearchResultKind {
    var displayText: String {
        switch self {
        case .contact:
            return "Contact"
        case .conversation:
            return "Chat"
        case .message:
            return "Message"
        }
    }
}

extension UIColor {
    static func chatBridgeHex(_ rgb: UInt32, alpha: CGFloat = 1.0) -> UIColor {
        UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}
