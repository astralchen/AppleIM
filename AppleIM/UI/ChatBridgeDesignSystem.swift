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

        /// Apple Messages 风格的发出消息蓝色气泡
        static let appleMessageOutgoing = UIColor { traits in
            UIColor.systemBlue.resolvedColor(with: traits)
        }

        /// Apple Messages 风格的收到消息灰色气泡
        static let appleMessageIncoming = UIColor { traits in
            UIColor.systemGray6.resolvedColor(with: traits)
        }

        /// Apple Messages 风格的附件卡片背景
        static let appleMessageAttachment = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.secondarySystemGroupedBackground
                : UIColor.systemBackground
        }

        /// Apple ID 风格登录表单背景
        static let appleLoginFieldBackground = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.secondarySystemGroupedBackground
                : UIColor.secondarySystemBackground
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
        /// 会话列表同款低饱和默认头像
        static var neutralAvatar: [UIColor] {
            let color = UIColor.tertiarySystemFill
            return [color, color]
        }
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
        /// Apple Messages 风格消息气泡圆角
        static let appleMessageBubble: CGFloat = 18
        /// Apple Messages 风格媒体预览圆角
        static let appleMessageMedia: CGFloat = 20
        /// Apple Messages 风格 composer 附件圆角
        static let appleComposerAttachment: CGFloat = 16
        /// Apple ID 风格登录输入区圆角
        static let appleLoginField: CGFloat = 14
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
        /// Apple ID 风格登录按钮最小高度
        static let appleLoginButtonHeight: CGFloat = 50
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
        /// 发出消息
        case outgoing
        /// 收到消息
        case incoming
        /// 图片或视频媒体消息
        case media
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
    /// 气泡外形遮罩
    private let shapeMaskLayer = CAShapeLayer()

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
            let color = ChatBridgeDesignSystem.ColorToken.appleMessageOutgoing
            gradientLayer.colors = [color.cgColor, color.cgColor]
        case .incoming:
            let color = ChatBridgeDesignSystem.ColorToken.appleMessageIncoming
            gradientLayer.colors = [color.cgColor, color.cgColor]
        case .media:
            let color = UIColor.clear
            gradientLayer.colors = [color.cgColor, color.cgColor]
        case .revoked:
            let color = UIColor.tertiarySystemFill
            gradientLayer.colors = [color.cgColor, color.cgColor]
        }
        setNeedsLayout()
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

    /// 布局变化时刷新气泡尾角遮罩
    override func layoutSubviews() {
        super.layoutSubviews()
        shapeMaskLayer.frame = bounds
        shapeMaskLayer.path = makeMaskPath().cgPath
    }

    /// 配置默认圆角、渐变方向和样式
    private func configure() {
        layer.cornerRadius = 0
        layer.masksToBounds = false
        layer.mask = shapeMaskLayer
        gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.15)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        apply(style: Style.incoming)
    }

    /// 生成类似 Apple Messages 的圆角气泡和尾角外形。
    static func maskPath(in bounds: CGRect, style: Style) -> UIBezierPath {
        let radius = ChatBridgeDesignSystem.RadiusToken.appleMessageBubble
        let tailWidth: CGFloat = 7

        switch style {
        case .outgoing:
            let rect = bounds.inset(by: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: tailWidth))
            return outgoingMaskPath(in: bounds, bodyRect: rect, radius: radius)
        case .incoming:
            let rect = bounds.inset(by: UIEdgeInsets(top: 0, left: tailWidth, bottom: 0, right: 0))
            return incomingMaskPath(in: bounds, bodyRect: rect, radius: radius)
        case .media, .revoked:
            return UIBezierPath(roundedRect: bounds, cornerRadius: radius)
        }
    }

    private static func outgoingMaskPath(in bounds: CGRect, bodyRect rect: CGRect, radius: CGFloat) -> UIBezierPath {
        let cornerRadius = min(radius, rect.width / 2, rect.height / 2)
        let maxY = rect.maxY
        let tailTopY = maxY - min(18, rect.height * 0.40)
        let tailTipY = maxY - min(10, rect.height * 0.28)
        let tailBottomY = maxY - min(4, rect.height * 0.10)
        let tailRootX = rect.maxX - cornerRadius * 0.38

        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius),
            controlPoint: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: tailTopY))
        path.addCurve(
            to: CGPoint(x: bounds.maxX, y: tailTipY),
            controlPoint1: CGPoint(x: rect.maxX + 3, y: tailTopY + 2),
            controlPoint2: CGPoint(x: bounds.maxX - 1, y: tailTipY - 3)
        )
        path.addCurve(
            to: CGPoint(x: tailRootX, y: tailBottomY),
            controlPoint1: CGPoint(x: bounds.maxX - 1, y: tailTipY + 3),
            controlPoint2: CGPoint(x: rect.maxX - 3, y: tailBottomY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
            controlPoint: CGPoint(x: rect.maxX - cornerRadius * 0.45, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius),
            controlPoint: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY),
            controlPoint: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.close()

        return path
    }

    private static func incomingMaskPath(in bounds: CGRect, bodyRect rect: CGRect, radius: CGFloat) -> UIBezierPath {
        let cornerRadius = min(radius, rect.width / 2, rect.height / 2)
        let maxY = rect.maxY
        let tailTopY = maxY - min(18, rect.height * 0.40)
        let tailTipY = maxY - min(10, rect.height * 0.28)
        let tailBottomY = maxY - min(4, rect.height * 0.10)
        let tailRootX = rect.minX + cornerRadius * 0.38

        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius),
            controlPoint: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: tailTopY))
        path.addCurve(
            to: CGPoint(x: bounds.minX, y: tailTipY),
            controlPoint1: CGPoint(x: rect.minX - 3, y: tailTopY + 2),
            controlPoint2: CGPoint(x: bounds.minX + 1, y: tailTipY - 3)
        )
        path.addCurve(
            to: CGPoint(x: tailRootX, y: tailBottomY),
            controlPoint1: CGPoint(x: bounds.minX + 1, y: tailTipY + 3),
            controlPoint2: CGPoint(x: rect.minX + 3, y: tailBottomY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY),
            controlPoint: CGPoint(x: rect.minX + cornerRadius * 0.45, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius),
            controlPoint: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY),
            controlPoint: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.close()

        return path
    }

    private func makeMaskPath() -> UIBezierPath {
        Self.maskPath(in: bounds, style: style)
    }
}

/// 会话列表单元格内容行
@MainActor
enum ConversationListCellContentRow: Equatable {
    /// 普通会话行
    case conversation(ConversationListRowState)
    /// 搜索结果行
    case search(SearchResultRowState)

    /// 主标题
    var title: String {
        switch self {
        case .conversation(let row):
            return row.title
        case .search(let row):
            return row.title
        }
    }

    /// 副标题
    var subtitle: String {
        switch self {
        case .conversation(let row):
            return row.subtitle
        case .search(let row):
            return row.subtitle
        }
    }

    /// 右侧时间或类型文案
    var trailingText: String {
        switch self {
        case .conversation(let row):
            return row.timeText
        case .search(let row):
            return row.kind.displayText
        }
    }

    /// 头像 URL
    var avatarURL: String? {
        switch self {
        case .conversation(let row):
            return row.avatarURL
        case .search:
            return nil
        }
    }

    /// 未读文案
    var unreadText: String? {
        switch self {
        case .conversation(let row):
            return row.unreadText
        case .search:
            return nil
        }
    }

    /// 是否置顶
    var isPinned: Bool {
        switch self {
        case .conversation(let row):
            return row.isPinned
        case .search:
            return true
        }
    }

    /// 是否免打扰
    var isMuted: Bool {
        switch self {
        case .conversation(let row):
            return row.isMuted
        case .search:
            return false
        }
    }
}

/// 会话列表单元格内容配置
@MainActor
struct ConversationListCellContentConfiguration: UIContentConfiguration {
    /// 行内容
    let row: ConversationListCellContentRow
    /// 高亮状态
    var isHighlighted = false
    /// 选中状态
    var isSelected = false
    fileprivate var updatesOnlyCellState = false

    /// 初始化内容配置
    init(
        row: ConversationListCellContentRow,
        isHighlighted: Bool = false,
        isSelected: Bool = false
    ) {
        self.row = row
        self.isHighlighted = isHighlighted
        self.isSelected = isSelected
    }

    /// 创建内容视图
    func makeContentView() -> UIView & UIContentView {
        ConversationListCellContentView(configuration: self)
    }

    /// 根据 cell 状态派生配置
    func updated(for state: UIConfigurationState) -> ConversationListCellContentConfiguration {
        var updatedConfiguration = self
        if let cellState = state as? UICellConfigurationState {
            updatedConfiguration.isHighlighted = cellState.isHighlighted
            updatedConfiguration.isSelected = cellState.isSelected
            updatedConfiguration.updatesOnlyCellState = true
        }
        return updatedConfiguration
    }
}

/// 会话列表单元格内容视图
@MainActor
final class ConversationListCellContentView: UIView, UIContentView {
    /// 头像加载服务，可在测试中替换。
    static var avatarImageLoader: any AvatarImageLoading = DefaultAvatarImageLoader.shared

    /// 行内容容器
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
    /// 置顶和免打扰图标容器
    private let statusIconStackView = UIStackView()
    /// 未读数标签
    private let unreadLabel = ChatBridgeUnreadBadgeLabel()
    /// 置顶状态图标
    private let pinnedImageView = UIImageView(image: UIImage(systemName: "pin.fill"))
    /// 免打扰状态图标
    private let mutedImageView = UIImageView(image: UIImage(systemName: "bell.slash.fill"))
    /// 行底部分割线
    private let separatorView = UIView()
    /// 当前头像加载任务
    private var avatarLoadTask: (any AvatarImageLoadTask)?
    /// 当前期望展示的头像 URL
    private var expectedAvatarURL: String?
    private var currentConfiguration: ConversationListCellContentConfiguration

    /// 初始化会话单元格
    init(configuration: ConversationListCellContentConfiguration) {
        currentConfiguration = configuration
        super.init(frame: .zero)
        configureView()
        apply(configuration)
    }

    /// 从 storyboard/xib 初始化会话单元格
    required init?(coder: NSCoder) {
        currentConfiguration = ConversationListCellContentConfiguration(
            row: .conversation(
                ConversationListRowState(
                    id: "empty",
                    title: "",
                    subtitle: "",
                    timeText: "",
                    unreadText: nil,
                    isPinned: false,
                    isMuted: false
                )
            )
        )
        super.init(coder: coder)
        configureView()
        apply(currentConfiguration)
    }

    deinit {
        avatarLoadTask?.cancel()
    }

    /// 当前内容配置
    var configuration: UIContentConfiguration {
        get { currentConfiguration }
        set {
            guard let newConfiguration = newValue as? ConversationListCellContentConfiguration else {
                return
            }

            let shouldOnlyUpdateCellState = newConfiguration.updatesOnlyCellState
                && currentConfiguration.row == newConfiguration.row
            currentConfiguration = newConfiguration

            if shouldOnlyUpdateCellState {
                applyCellState(newConfiguration)
            } else {
                apply(newConfiguration)
            }
        }
    }

    /// 重用前重置状态和头像加载
    func reset() {
        unreadLabel.isHidden = true
        pinnedImageView.isHidden = true
        mutedImageView.isHidden = true
        cardView.backgroundColor = .systemBackground
        alpha = 1
        applyTextStyle(hasUnread: false)
        resetAvatarImage()
    }

    /// 应用内容配置
    private func apply(_ configuration: ConversationListCellContentConfiguration) {
        reset()
        let row = configuration.row
        titleLabel.text = row.title
        subtitleLabel.text = row.subtitle
        timeLabel.text = row.trailingText
        unreadLabel.text = row.unreadText
        unreadLabel.isHidden = row.unreadText == nil
        pinnedImageView.isHidden = !row.isPinned
        mutedImageView.isHidden = !row.isMuted
        avatarLabel.text = Self.initials(from: row.title)
        avatarView.setColors(Self.avatarColors(isPinned: row.isPinned))
        configureAvatarImage(from: row.avatarURL)
        cardView.backgroundColor = .systemBackground
        applyTextStyle(hasUnread: row.unreadText != nil)
        applyCellState(configuration)
    }

    /// 应用 cell 高亮/选中展示状态
    private func applyCellState(_ configuration: ConversationListCellContentConfiguration) {
        alpha = configuration.isHighlighted || configuration.isSelected ? 0.82 : 1
    }

    /// 配置单元格层级、样式和约束
    private func configureView() {
        backgroundColor = .clear

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = .systemBackground
        cardView.layer.cornerRadius = 0
        cardView.layer.masksToBounds = true

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.layer.cornerRadius = 26
        avatarView.layer.masksToBounds = true
        avatarView.setColors(Self.avatarColors(isPinned: false))

        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.isHidden = true
        avatarImageView.isAccessibilityElement = false
        avatarImageView.accessibilityIdentifier = "conversation.avatarImageView"

        avatarLabel.translatesAutoresizingMaskIntoConstraints = false
        avatarLabel.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: .systemFont(ofSize: 20, weight: .semibold)
        )
        avatarLabel.textColor = .secondaryLabel
        avatarLabel.textAlignment = .center
        avatarLabel.adjustsFontForContentSizeCategory = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 2

        timeLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 13, weight: .regular)
        )
        timeLabel.textColor = .secondaryLabel
        timeLabel.adjustsFontForContentSizeCategory = true
        timeLabel.textAlignment = .right
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        [pinnedImageView, mutedImageView].forEach { imageView in
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.tintColor = .tertiaryLabel
            imageView.contentMode = .scaleAspectFit
            imageView.isHidden = true
        }

        statusIconStackView.translatesAutoresizingMaskIntoConstraints = false
        statusIconStackView.axis = .horizontal
        statusIconStackView.alignment = .center
        statusIconStackView.spacing = ChatBridgeDesignSystem.SpacingToken.xs
        statusIconStackView.addArrangedSubview(pinnedImageView)
        statusIconStackView.addArrangedSubview(mutedImageView)

        statusStackView.translatesAutoresizingMaskIntoConstraints = false
        statusStackView.axis = .vertical
        statusStackView.alignment = .trailing
        statusStackView.spacing = ChatBridgeDesignSystem.SpacingToken.xs
        statusStackView.addArrangedSubview(timeLabel)
        statusStackView.addArrangedSubview(unreadLabel)
        statusStackView.addArrangedSubview(statusIconStackView)

        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = .separator

        addSubview(cardView)
        cardView.addSubview(avatarView)
        avatarView.addSubview(avatarLabel)
        avatarView.addSubview(avatarImageView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(subtitleLabel)
        cardView.addSubview(statusStackView)
        cardView.addSubview(separatorView)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            avatarView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            avatarView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            avatarView.topAnchor.constraint(greaterThanOrEqualTo: cardView.topAnchor, constant: 10),
            avatarView.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -10),
            avatarView.widthAnchor.constraint(equalToConstant: 52),
            avatarView.heightAnchor.constraint(equalToConstant: 52),

            avatarLabel.topAnchor.constraint(equalTo: avatarView.topAnchor),
            avatarLabel.leadingAnchor.constraint(equalTo: avatarView.leadingAnchor),
            avatarLabel.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor),
            avatarLabel.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor),

            avatarImageView.topAnchor.constraint(equalTo: avatarView.topAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: avatarView.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor),

            statusStackView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 11),
            statusStackView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),
            statusStackView.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -10),
            statusStackView.widthAnchor.constraint(greaterThanOrEqualToConstant: 58),

            pinnedImageView.widthAnchor.constraint(equalToConstant: 13),
            pinnedImageView.heightAnchor.constraint(equalToConstant: 13),
            mutedImageView.widthAnchor.constraint(equalToConstant: 13),
            mutedImageView.heightAnchor.constraint(equalToConstant: 13),

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 11),
            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusStackView.leadingAnchor, constant: -8),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusStackView.leadingAnchor, constant: -8),
            subtitleLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -11),

            separatorView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            separatorView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])

        applyTextStyle(hasUnread: false)
    }

    /// 根据未读状态切换 Messages 风格文字层级
    private func applyTextStyle(hasUnread: Bool) {
        titleLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 17, weight: hasUnread ? .semibold : .regular)
        )
        subtitleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 15, weight: hasUnread ? .semibold : .regular)
        )
        subtitleLabel.textColor = hasUnread ? .label : .secondaryLabel
        timeLabel.textColor = hasUnread ? .systemBlue : .secondaryLabel
    }

    /// 配置远程或本地头像图片
    private func configureAvatarImage(from value: String?) {
        resetAvatarImage()

        guard let avatarURL = value?.trimmingCharacters(in: .whitespacesAndNewlines), !avatarURL.isEmpty else {
            return
        }

        expectedAvatarURL = avatarURL
        avatarLoadTask = Self.avatarImageLoader.loadImage(from: avatarURL) { [weak self] image in
            guard let self, self.expectedAvatarURL == avatarURL, let image else {
                return
            }

            self.avatarImageView.image = image
            self.avatarImageView.isHidden = false
        }
    }

    /// 取消头像请求并恢复默认头像状态
    private func resetAvatarImage() {
        avatarLoadTask?.cancel()
        avatarLoadTask = nil
        expectedAvatarURL = nil
        avatarImageView.image = nil
        avatarImageView.isHidden = true
    }

    /// 根据标题生成头像首字母
    private static func initials(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first.map { String($0).uppercased() } ?? "C"
    }

    /// 生成 Messages 风格的低调默认头像色
    private static func avatarColors(isPinned: Bool) -> [UIColor] {
        if isPinned {
            let color = UIColor.systemBlue.withAlphaComponent(0.18)
            return [color, color]
        }

        let color = UIColor.tertiarySystemFill
        return [color, color]
    }
}

/// 会话列表单元格
@MainActor
final class ConversationListCell: UICollectionViewCell {
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
        resetConversationContentViews(in: self)
        resetAvatarImageViews(in: self)
        contentConfiguration = nil
        isAccessibilityElement = false
        accessibilityIdentifier = nil
        accessibilityLabel = nil
    }

    private func resetConversationContentViews(in view: UIView) {
        for subview in view.subviews {
            if let conversationContentView = subview as? ConversationListCellContentView {
                conversationContentView.reset()
            }
            resetConversationContentViews(in: subview)
        }
    }

    private func resetAvatarImageViews(in view: UIView) {
        for subview in view.subviews {
            if
                let imageView = subview as? UIImageView,
                imageView.accessibilityIdentifier == "conversation.avatarImageView"
            {
                imageView.image = nil
                imageView.isHidden = true
            }
            resetAvatarImageViews(in: subview)
        }
    }

    /// 使用会话行状态配置单元格
    func configure(row: ConversationListRowState) {
        contentConfiguration = ConversationListCellContentConfiguration(row: .conversation(row))
    }

    /// 使用搜索结果行状态配置单元格
    func configure(searchRow: SearchResultRowState) {
        contentConfiguration = ConversationListCellContentConfiguration(row: .search(searchRow))
    }

    /// 根据 cell 状态更新内容配置
    override func updateConfiguration(using state: UICellConfigurationState) {
        super.updateConfiguration(using: state)
        guard let configuration = contentConfiguration as? ConversationListCellContentConfiguration else {
            return
        }
        contentConfiguration = configuration.updated(for: state)
    }

    /// 配置 cell 外层样式
    private func configureView() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
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
        backgroundColor = .systemBlue
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
