//
//  ChatBridgeDesignSystem.swift
//  AppleIM
//
//  Shared UIKit styling for the ChatBridge visual refresh.
//

import UIKit

/// ChatBridge 共享 UIKit 设计系统
enum ChatBridgeDesignSystem {
    /// 颜色令牌
    enum ColorToken {
        /// 品牌薄荷绿
        static let mint = UIColor.chatBridgeHex(0x27D9A5)
        /// 品牌天空蓝
        static let sky = UIColor.chatBridgeHex(0x4DA3FF)
        /// 强调珊瑚红
        static let coral = UIColor.chatBridgeHex(0xFF5A7A)
        /// 主要文字颜色
        static let ink = UIColor { traits in
            traits.userInterfaceStyle == .dark ? .white : UIColor.chatBridgeHex(0x111827)
        }
        /// 页面背景渐变起始色
        static let backgroundStart = UIColor.chatBridgeHex(0xEAFBFF)
        /// 页面背景渐变中间色
        static let backgroundMiddle = UIColor.chatBridgeHex(0xF7F1FF)
        /// 页面背景渐变结束色
        static let backgroundEnd = UIColor.chatBridgeHex(0xFFF7EA)

        /// 收到消息和列表卡片背景
        static var incomingCard: UIColor {
            UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.86)
                    : UIColor.white.withAlphaComponent(0.88)
            }
        }

        /// 抬升容器背景
        static var elevatedCard: UIColor {
            UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor.tertiarySystemGroupedBackground.withAlphaComponent(0.82)
                    : UIColor.white.withAlphaComponent(0.76)
            }
        }

        /// 置顶会话卡片背景
        static var pinnedCard: UIColor {
            UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? mint.withAlphaComponent(0.18)
                    : mint.withAlphaComponent(0.14)
            }
        }
    }

    /// 渐变令牌
    enum GradientToken {
        /// 应用页面背景渐变
        static let appBackground = [ColorToken.backgroundStart, ColorToken.backgroundMiddle, ColorToken.backgroundEnd]
        /// 发出消息气泡渐变
        static let outgoingBubble = [ColorToken.mint, UIColor.chatBridgeHex(0x3B82F6)]
        /// 品牌主按钮渐变
        static let brandButton = [ColorToken.mint, ColorToken.sky]
        /// 默认头像渐变
        static let playfulAvatar = [ColorToken.coral, ColorToken.sky]
    }

    /// 圆角令牌
    enum RadiusToken {
        /// 页面卡片圆角
        static let pageCard: CGFloat = 22
        /// 输入栏圆角
        static let inputBar: CGFloat = 24
        /// 消息气泡圆角
        static let messageBubble: CGFloat = 18
        /// 媒体缩略图圆角
        static let media: CGFloat = 14
        /// 徽标圆角
        static let badge: CGFloat = 11
        /// 输入框圆角
        static let field: CGFloat = 17
    }

    /// 间距令牌
    enum SpacingToken {
        /// 极小间距
        static let xs: CGFloat = 4
        /// 小间距
        static let sm: CGFloat = 8
        /// 中间距
        static let md: CGFloat = 12
        /// 大间距
        static let lg: CGFloat = 16
        /// 超大间距
        static let xl: CGFloat = 24
        /// 最大间距
        static let xxl: CGFloat = 32
    }

    /// 阴影令牌
    enum ShadowToken {
        /// 为卡片层应用统一阴影
        static func applyCardShadow(to layer: CALayer) {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.10
            layer.shadowRadius = 18
            layer.shadowOffset = CGSize(width: 0, height: 10)
        }

        /// 为消息气泡层应用轻量阴影
        static func applyBubbleShadow(to layer: CALayer) {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.08
            layer.shadowRadius = 10
            layer.shadowOffset = CGSize(width: 0, height: 5)
        }
    }

    /// 按钮视觉角色
    enum ButtonRole {
        /// 主要动作按钮
        case primary
        /// 次要动作按钮
        case secondary
        /// 圆形工具按钮
        case circularTool
        /// 破坏性动作按钮
        case destructive
    }

    /// 创建支持系统玻璃效果的按钮配置
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

    /// 创建旧系统上的按钮降级配置
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

/// 渐变背景视图
final class GradientBackgroundView: UIView {
    /// 使用渐变图层作为根图层
    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    /// 强类型渐变图层访问器
    private var gradientLayer: CAGradientLayer {
        layer as! CAGradientLayer
    }

    /// 初始化渐变背景
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    /// 从 storyboard/xib 初始化渐变背景
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    /// 更新渐变颜色
    func setColors(_ colors: [UIColor]) {
        gradientLayer.colors = colors.map(\.cgColor)
    }

    /// 配置默认渐变方向和颜色
    private func configure() {
        isUserInteractionEnabled = false
        gradientLayer.startPoint = CGPoint(x: 0.05, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        setColors(ChatBridgeDesignSystem.GradientToken.appBackground)
    }
}

/// 玻璃质感容器视图
final class GlassContainerView: UIView {
    /// 系统模糊层
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    /// 额外着色层
    private let tintView = UIView()

    /// 外部内容承载视图
    var contentView: UIView {
        blurView.contentView
    }

    /// 初始化玻璃容器
    init(cornerRadius: CGFloat = ChatBridgeDesignSystem.RadiusToken.pageCard) {
        super.init(frame: .zero)
        configure(cornerRadius: cornerRadius)
    }

    /// 从 storyboard/xib 初始化玻璃容器
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure(cornerRadius: ChatBridgeDesignSystem.RadiusToken.pageCard)
    }

    /// 配置模糊、着色和约束
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

/// 聊天气泡样式
enum ChatBubbleStyle {
    /// 当前用户发出的消息
    case outgoing
    /// 对方发来的消息
    case incoming
    /// 已撤回消息
    case revoked

    /// 对应的气泡背景样式
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

/// 品牌渐变按钮背景视图
final class GradientButtonBackgroundView: UIView {
    /// 使用渐变图层作为根图层
    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    /// 强类型渐变图层访问器
    private var gradientLayer: CAGradientLayer {
        layer as! CAGradientLayer
    }

    /// 初始化按钮背景
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    /// 从 storyboard/xib 初始化按钮背景
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    /// 配置按钮渐变方向和圆角
    private func configure() {
        isUserInteractionEnabled = false
        layer.cornerRadius = ChatBridgeDesignSystem.RadiusToken.inputBar
        layer.masksToBounds = true
        gradientLayer.colors = ChatBridgeDesignSystem.GradientToken.brandButton.map(\.cgColor)
        gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
    }
}

/// 消息气泡背景视图
final class ChatBubbleBackgroundView: UIView {
    /// 气泡背景绘制样式
    enum Style {
        /// 发出消息渐变
        case outgoing
        /// 收到消息纯色卡片
        case incoming
        /// 撤回消息纯色背景
        case revoked
    }

    /// 使用渐变图层作为根图层
    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    /// 强类型渐变图层访问器
    private var gradientLayer: CAGradientLayer {
        layer as! CAGradientLayer
    }

    /// 当前背景样式
    private(set) var style: Style = .incoming

    /// 初始化气泡背景
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    /// 从 storyboard/xib 初始化气泡背景
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    /// 应用指定背景样式
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

    /// 应用聊天气泡样式
    func apply(style: ChatBubbleStyle) {
        apply(style: style.backgroundStyle)
    }

    /// 深浅色模式变化时刷新动态颜色
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        apply(style: style)
    }

    /// 配置默认圆角、渐变方向和样式
    private func configure() {
        layer.cornerRadius = ChatBridgeDesignSystem.RadiusToken.messageBubble
        layer.masksToBounds = true
        gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.15)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        apply(style: Style.incoming)
    }
}

/// 圆角会话列表单元格
final class RoundedConversationCell: UICollectionViewCell {
    /// 头像图片缓存
    private static let avatarImageCache = NSCache<NSString, UIImage>()

    /// 卡片容器
    private let cardView = UIView()
    /// 默认渐变头像背景
    private let avatarView = GradientBackgroundView()
    /// 远程或本地头像图片
    private let avatarImageView = UIImageView()
    /// 无头像时展示的首字母
    private let avatarLabel = UILabel()
    /// 会话标题
    private let titleLabel = UILabel()
    /// 会话摘要
    private let subtitleLabel = UILabel()
    /// 最后一条消息时间
    private let timeLabel = UILabel()
    /// 状态标签容器
    private let statusStackView = UIStackView()
    /// 未读数标签
    private let unreadLabel = ChatBridgeUnreadBadgeLabel()
    /// 免打扰状态标签
    private let mutedLabel = UILabel()
    /// 当前头像加载任务
    private var avatarDataTask: URLSessionDataTask?
    /// 当前期望展示的头像 URL
    private var expectedAvatarURL: String?

    /// 初始化会话单元格
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    /// 从 storyboard/xib 初始化会话单元格
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    /// 重用前重置状态和头像加载
    override func prepareForReuse() {
        super.prepareForReuse()
        unreadLabel.isHidden = true
        mutedLabel.isHidden = true
        cardView.backgroundColor = ChatBridgeDesignSystem.ColorToken.incomingCard
        resetAvatarImage()
    }

    /// 使用会话行状态配置单元格
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

    /// 使用搜索结果行状态配置单元格
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

    /// 配置单元格层级、样式和约束
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

    /// 配置远程或本地头像图片
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

    /// 取消头像请求并恢复默认头像状态
    private func resetAvatarImage() {
        avatarDataTask?.cancel()
        avatarDataTask = nil
        expectedAvatarURL = nil
        avatarImageView.image = nil
        avatarImageView.isHidden = true
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

    /// 根据标题生成头像首字母
    private static func initials(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first.map { String($0).uppercased() } ?? "C"
    }
}

/// ChatBridge 未读数徽标标签
final class ChatBridgeUnreadBadgeLabel: UILabel {
    /// 初始化未读徽标
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    /// 从 storyboard/xib 初始化未读徽标
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    /// 保证徽标有最小宽高
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: max(size.width + 12, 22), height: 22)
    }

    /// 配置徽标颜色、字体和圆角
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

/// 搜索结果类型的展示文案
extension SearchResultKind {
    /// 面向 UI 的类型名称
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

/// ChatBridge 颜色辅助方法
extension UIColor {
    /// 根据 0xRRGGBB 值创建 UIColor
    static func chatBridgeHex(_ rgb: UInt32, alpha: CGFloat = 1.0) -> UIColor {
        UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}
