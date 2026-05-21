//
//  AccountViewController.swift
//  AppleIM
//
//  Apple 风格账号管理页
//

import UIKit

/// 账号管理页
@MainActor
final class AccountViewController: UIViewController {
    /// 列表分区
    nonisolated private enum Section: Int, CaseIterable, Hashable, Sendable {
        case profile
        case actions
    }

    /// 列表条目
    nonisolated private enum Item: Hashable, Sendable {
        case profile
        case action(ActionRow)
    }

    /// 操作行
    nonisolated private enum ActionRow: Int, CaseIterable, Hashable, Sendable {
        case language
        case switchAccount
        case logOut
        case deleteLocalData

        var titleKey: String {
            switch self {
            case .language:
                return "account.action.language"
            case .switchAccount:
                return "account.action.switchAccount"
            case .logOut:
                return "account.action.logOut"
            case .deleteLocalData:
                return "account.action.deleteLocalData"
            }
        }

        var imageName: String {
            switch self {
            case .language:
                return "globe"
            case .switchAccount:
                return "person.2"
            case .logOut:
                return "rectangle.portrait.and.arrow.right"
            case .deleteLocalData:
                return "trash"
            }
        }

        var accessibilityIdentifier: String {
            switch self {
            case .language:
                return "account.action.language"
            case .switchAccount:
                return "account.action.switchAccount"
            case .logOut:
                return "account.action.logOut"
            case .deleteLocalData:
                return "account.action.deleteLocalData"
            }
        }

        var isDestructive: Bool {
            switch self {
            case .language, .switchAccount:
                return false
            case .logOut, .deleteLocalData:
                return true
            }
        }
    }

    /// 账号页状态
    private let state: AccountViewState
    /// 账号操作回调
    private let onAction: (AccountAction) -> Void
    /// 账号列表
    private var collectionView: UICollectionView!
    /// 列表数据源
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>?

    /// 初始化账号页
    init(state: AccountViewState, onAction: @escaping (AccountAction) -> Void) {
        self.state = state
        self.onAction = onAction
        super.init(nibName: nil, bundle: nil)
        title = L10n.shared.tr("account.title")
        tabBarItem = UITabBarItem(
            title: L10n.shared.tr("account.title"),
            image: UIImage(systemName: "person.crop.circle"),
            selectedImage: UIImage(systemName: "person.crop.circle.fill")
        )
        tabBarItem.accessibilityIdentifier = "mainTab.account"
    }

    /// 禁用 storyboard 初始化
    required init?(coder: NSCoder) {
        fatalError("Storyboard initialization is not supported.")
    }

    /// 配置视图
    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
    }

    /// 配置基础视图属性
    private func configureView() {
        navigationItem.largeTitleDisplayMode = .always
        view.backgroundColor = .systemGroupedBackground
        configureCollectionView()
        configureDataSource()
        applyLocalizedText()
        updateSnapshot()
    }

    /// 配置账号列表
    private func configureCollectionView() {
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.backgroundColor = .clear
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.accessibilityIdentifier = "account.collectionView"
        view.addSubview(collectionView)
        self.collectionView = collectionView

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// 配置 diffable data source
    private func configureDataSource() {
        let profileRegistration = UICollectionView.CellRegistration<AccountProfileCell, Item> { [weak self] cell, indexPath, item in
            self?.profileCellRegistrationHandler(cell: cell, indexPath: indexPath, item: item)
        }
        let actionRegistration = UICollectionView.CellRegistration<AccountActionCell, Item> { [weak self] cell, indexPath, item in
            self?.actionCellRegistrationHandler(cell: cell, indexPath: indexPath, item: item)
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .profile:
                collectionView.dequeueConfiguredReusableCell(using: profileRegistration, for: indexPath, item: item)
            case .action:
                collectionView.dequeueConfiguredReusableCell(using: actionRegistration, for: indexPath, item: item)
            }
        }
    }

    /// 配置账号资料 cell。
    private func profileCellRegistrationHandler(cell: AccountProfileCell, indexPath: IndexPath, item: Item) {
        guard case .profile = item else { return }
        cell.configure(
            state: state,
            layoutDirection: AppLanguageManager.shared.currentContext.semanticContentAttribute
        )
    }

    /// 配置账号操作 cell。
    private func actionCellRegistrationHandler(cell: AccountActionCell, indexPath: IndexPath, item: Item) {
        guard case .action(let row) = item else { return }
        cell.configure(
            title: L10n.shared.tr(row.titleKey),
            subtitle: row == .language ? languageSubtitle() : nil,
            imageName: row.imageName,
            isDestructive: row.isDestructive,
            layoutDirection: AppLanguageManager.shared.currentContext.semanticContentAttribute
        )
        cell.accessibilityIdentifier = row.accessibilityIdentifier
    }

    /// 更新列表快照
    private func updateSnapshot(forceReconfigure: Bool = false) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections(Section.allCases)
        snapshot.appendItems([Item.profile], toSection: Section.profile)
        snapshot.appendItems(ActionRow.allCases.map(Item.action), toSection: Section.actions)
        if forceReconfigure {
            snapshot.reconfigureItems(snapshot.itemIdentifiers)
        }
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    /// 构造当前账号本地数据删除确认弹窗。
    func makeDeleteLocalDataConfirmationController() -> UIAlertController {
        let alertController = UIAlertController(
            title: L10n.shared.tr("account.delete.confirm.title"),
            message: L10n.shared.tr("account.delete.confirm.message"),
            preferredStyle: .alert
        )

        let confirmAction = UIAlertAction(title: L10n.shared.tr("account.action.deleteLocalData"), style: .destructive) { [weak self] _ in
            self?.onAction(.deleteLocalData)
        }
        confirmAction.setValue("accountAction.confirmDeleteLocalData", forKey: "accessibilityIdentifier")

        alertController.addAction(UIAlertAction(title: L10n.shared.tr("common.cancel"), style: .cancel))
        alertController.addAction(confirmAction)
        return alertController
    }

    /// 根据当前语言偏好生成语言行副标题。
    private func languageSubtitle() -> String {
        let context = AppLanguageManager.shared.currentContext
        let resolvedName = L10n.shared.tr(context.resolvedLanguage.displayNameKey)
        switch context.preference {
        case .system:
            return L10n.shared.tr("account.language.currentSystemFormat", resolvedName)
        case .language:
            return resolvedName
        }
    }

    /// 刷新账号页文案。
    private func applyLocalizedText() {
        title = L10n.shared.tr("account.title")
        navigationItem.title = L10n.shared.tr("account.title")
        tabBarItem.title = L10n.shared.tr("account.title")
    }
}

extension AccountViewController: UICollectionViewDelegate {
    /// 只允许选择账号操作行
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard case .action = dataSource?.itemIdentifier(for: indexPath) else {
            return false
        }
        return true
    }

    /// 处理账号操作选择
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        guard case .action(let row) = dataSource?.itemIdentifier(for: indexPath) else {
            return
        }

        switch row {
        case .language:
            let viewController = LanguageSettingsViewController()
            let navigationController = UINavigationController(rootViewController: viewController)
            navigationController.modalPresentationStyle = .pageSheet
            if let sheetPresentationController = navigationController.sheetPresentationController {
                sheetPresentationController.detents = [.large()]
                sheetPresentationController.prefersGrabberVisible = false
                sheetPresentationController.preferredCornerRadius = 32
            }
            present(navigationController, animated: true)
        case .deleteLocalData:
            present(makeDeleteLocalDataConfirmationController(), animated: true)
        case .switchAccount:
            onAction(.switchAccount)
        case .logOut:
            onAction(.logOut)
        }
    }
}

extension AccountViewController: AppLanguageUpdatable {
    /// 语言变化时保留页面状态，只刷新标题、方向和可见行。
    func applyLanguageChange(_ context: AppLanguageContext) {
        view.applyLanguageSemanticContentAttribute(context.semanticContentAttribute)
        applyLocalizedText()
        collectionView.semanticContentAttribute = context.semanticContentAttribute
        collectionView.collectionViewLayout.invalidateLayout()
        updateSnapshot(forceReconfigure: true)
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
    }
}

/// 账号资料列表单元
@MainActor
private final class AccountProfileCell: UICollectionViewListCell {
    private let profileView = AccountProfileHeaderView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHierarchy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 配置资料内容
    func configure(state: AccountViewState, layoutDirection: UISemanticContentAttribute) {
        semanticContentAttribute = layoutDirection
        contentView.semanticContentAttribute = layoutDirection
        profileView.semanticContentAttribute = layoutDirection
        profileView.configure(state: state)
        accessibilityIdentifier = "account.profileHeader"
        isAccessibilityElement = false
    }

    /// 清理复用状态
    override func prepareForReuse() {
        super.prepareForReuse()
    }

    private func configureHierarchy() {
        profileView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(profileView)

        NSLayoutConstraint.activate([
            profileView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            profileView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            profileView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            profileView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
    }
}

/// 账号操作列表单元。使用自有内容视图，避免系统 list content 在 RTL/LTR 反复切换后残留镜像状态。
@MainActor
private final class AccountActionCell: UICollectionViewListCell {
    private enum Layout {
        static let horizontalInset: CGFloat = 20
        static let verticalInset: CGFloat = 14
        static let iconSize: CGFloat = 28
        static let iconToTextSpacing: CGFloat = 14
        static let textToChevronSpacing: CGFloat = 12
        static let chevronSize: CGFloat = 16
    }

    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let textStackView = UIStackView()
    private let chevronImageView = UIImageView(image: UIImage(systemName: "chevron.forward"))
    private var iconLeadingConstraint: NSLayoutConstraint?
    private var iconTrailingConstraint: NSLayoutConstraint?
    private var textLeadingToIconConstraint: NSLayoutConstraint?
    private var textTrailingToChevronConstraint: NSLayoutConstraint?
    private var textLeadingToChevronConstraint: NSLayoutConstraint?
    private var textTrailingToIconConstraint: NSLayoutConstraint?
    private var chevronLeadingConstraint: NSLayoutConstraint?
    private var chevronTrailingConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHierarchy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconImageView.image = nil
        titleLabel.attributedText = nil
        subtitleLabel.attributedText = nil
        subtitleLabel.isHidden = true
    }

    func configure(
        title: String,
        subtitle: String?,
        imageName: String,
        isDestructive: Bool,
        layoutDirection: UISemanticContentAttribute
    ) {
        semanticContentAttribute = layoutDirection
        contentView.semanticContentAttribute = layoutDirection
        iconImageView.semanticContentAttribute = layoutDirection
        textStackView.semanticContentAttribute = layoutDirection
        chevronImageView.semanticContentAttribute = layoutDirection

        let tintColor: UIColor = isDestructive ? .systemRed : .systemBlue
        let titleColor: UIColor = isDestructive ? .systemRed : .label
        iconImageView.image = UIImage(systemName: imageName)
        iconImageView.tintColor = tintColor
        titleLabel.attributedText = attributedText(title, color: titleColor, direction: layoutDirection, font: .preferredFont(forTextStyle: .body))
        if let subtitle {
            subtitleLabel.attributedText = attributedText(subtitle, color: .secondaryLabel, direction: layoutDirection, font: .preferredFont(forTextStyle: .subheadline))
            subtitleLabel.isHidden = false
        } else {
            subtitleLabel.attributedText = nil
            subtitleLabel.isHidden = true
        }
        applyLayoutDirection(layoutDirection)
    }

    private func configureHierarchy() {
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFit

        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 1
        subtitleLabel.isHidden = true

        textStackView.translatesAutoresizingMaskIntoConstraints = false
        textStackView.axis = .vertical
        textStackView.spacing = 2
        textStackView.addArrangedSubview(titleLabel)
        textStackView.addArrangedSubview(subtitleLabel)

        chevronImageView.translatesAutoresizingMaskIntoConstraints = false
        chevronImageView.tintColor = .tertiaryLabel
        chevronImageView.contentMode = .scaleAspectFit

        contentView.addSubview(iconImageView)
        contentView.addSubview(textStackView)
        contentView.addSubview(chevronImageView)

        iconLeadingConstraint = iconImageView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor)
        iconTrailingConstraint = iconImageView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor)
        textLeadingToIconConstraint = textStackView.leadingAnchor.constraint(
            equalTo: iconImageView.trailingAnchor,
            constant: Layout.iconToTextSpacing
        )
        textTrailingToChevronConstraint = textStackView.trailingAnchor.constraint(
            equalTo: chevronImageView.leadingAnchor,
            constant: -Layout.textToChevronSpacing
        )
        textLeadingToChevronConstraint = textStackView.leadingAnchor.constraint(
            equalTo: chevronImageView.trailingAnchor,
            constant: Layout.textToChevronSpacing
        )
        textTrailingToIconConstraint = textStackView.trailingAnchor.constraint(
            equalTo: iconImageView.leadingAnchor,
            constant: -Layout.iconToTextSpacing
        )
        chevronLeadingConstraint = chevronImageView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor)
        chevronTrailingConstraint = chevronImageView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor)

        NSLayoutConstraint.activate([
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: Layout.iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: Layout.iconSize),
            textStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Layout.verticalInset),
            textStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Layout.verticalInset),
            chevronImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevronImageView.widthAnchor.constraint(equalToConstant: Layout.chevronSize),
            chevronImageView.heightAnchor.constraint(equalToConstant: Layout.chevronSize)
        ])
        applyLayoutDirection(.forceLeftToRight)
    }

    private func applyLayoutDirection(_ direction: UISemanticContentAttribute) {
        let isRTL = direction == .forceRightToLeft
        let textAlignment: NSTextAlignment = isRTL ? .right : .left
        textStackView.alignment = isRTL ? .trailing : .leading
        titleLabel.textAlignment = textAlignment
        subtitleLabel.textAlignment = textAlignment
        iconLeadingConstraint?.isActive = !isRTL
        textLeadingToIconConstraint?.isActive = !isRTL
        textTrailingToChevronConstraint?.isActive = !isRTL
        chevronTrailingConstraint?.isActive = !isRTL
        iconTrailingConstraint?.isActive = isRTL
        textLeadingToChevronConstraint?.isActive = isRTL
        textTrailingToIconConstraint?.isActive = isRTL
        chevronLeadingConstraint?.isActive = isRTL
        setNeedsLayout()
    }

    private func attributedText(
        _ text: String,
        color: UIColor,
        direction: UISemanticContentAttribute,
        font: UIFont
    ) -> NSAttributedString {
        let isRTL = direction == .forceRightToLeft
        let writingDirection: NSWritingDirection = isRTL ? .rightToLeft : .leftToRight
        let writingDirectionValue = writingDirection.rawValue | NSWritingDirectionFormatType.embedding.rawValue
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.baseWritingDirection = isRTL ? .rightToLeft : .leftToRight
        paragraphStyle.alignment = isRTL ? .right : .left
        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle,
                .writingDirection: [NSNumber(value: writingDirectionValue)]
            ]
        )
    }
}

/// 账号资料头部视图
@MainActor
private final class AccountProfileHeaderView: UIView {
    /// 头像视图
    private let avatarImageView = UIImageView()
    /// 昵称标签
    private let displayNameLabel = UILabel()
    /// 用户 ID 标签
    private let userIDLabel = UILabel()

    /// 初始化资料头部
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    /// 禁用 storyboard 初始化
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    /// 配置视图层级
    private func configureView() {
        accessibilityIdentifier = "account.profileHeader"

        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.image = UIImage(systemName: "person.crop.circle.fill")
        avatarImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 56, weight: .regular)
        avatarImageView.tintColor = .systemBlue
        avatarImageView.contentMode = .scaleAspectFit
        avatarImageView.accessibilityIdentifier = "account.avatarImageView"

        displayNameLabel.translatesAutoresizingMaskIntoConstraints = false
        displayNameLabel.textColor = .label
        displayNameLabel.font = .preferredFont(forTextStyle: .title3)
        displayNameLabel.adjustsFontForContentSizeCategory = true
        displayNameLabel.numberOfLines = 0

        userIDLabel.translatesAutoresizingMaskIntoConstraints = false
        userIDLabel.textColor = .secondaryLabel
        userIDLabel.font = .preferredFont(forTextStyle: .subheadline)
        userIDLabel.adjustsFontForContentSizeCategory = true
        userIDLabel.numberOfLines = 0

        let labelStackView = UIStackView(arrangedSubviews: [
            displayNameLabel,
            userIDLabel
        ])
        labelStackView.translatesAutoresizingMaskIntoConstraints = false
        labelStackView.axis = .vertical
        labelStackView.spacing = 4
        labelStackView.alignment = .fill

        let stackView = UIStackView(arrangedSubviews: [
            avatarImageView,
            labelStackView
        ])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 16
        stackView.alignment = .center

        addSubview(stackView)

        NSLayoutConstraint.activate([
            avatarImageView.widthAnchor.constraint(equalToConstant: 64),
            avatarImageView.heightAnchor.constraint(equalToConstant: 64),

            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// 应用账号资料状态。
    func configure(state: AccountViewState) {
        displayNameLabel.text = state.displayName
        userIDLabel.text = state.userID.rawValue
    }
}
