//
//  LanguageSettingsViewController.swift
//  AppleIM
//
//  应用内语言设置页
//

import UIKit

/// iOS 设置风格的应用内语言选择页。
@MainActor
final class LanguageSettingsViewController: UIViewController {
    /// 附件为 @3x 参考图，以下尺寸均按 point 口径维护。
    nonisolated private enum Layout {
        static let closeButtonSize: CGFloat = 44
        static let closeButtonTopSpacing: CGFloat = 18
        static let headerToSectionSpacing: CGFloat = 66
        static let horizontalInset: CGFloat = 16
        static let contentHorizontalInset: CGFloat = 32
        static let listCornerRadius: CGFloat = 22
        static let searchHeight: CGFloat = 52
        static let searchCornerRadius: CGFloat = 26
        static let searchBottomSpacing: CGFloat = 16
        static let searchHorizontalInset: CGFloat = 28
        static let searchIconSize: CGFloat = 24
        static let microphoneIconSize: CGFloat = 22
        static let searchIconInset: CGFloat = 22
        static let rowVerticalInset: CGFloat = 8
        static let rowHorizontalInset: CGFloat = 22
        static let titleFontSize: CGFloat = 22
        static let sectionTitleFontSize: CGFloat = 22
        static let languageTitleFontSize: CGFloat = 22
        static let languageSubtitleFontSize: CGFloat = 19
    }

    /// 列表分区。
    nonisolated private enum Section: Hashable, Sendable {
        case main
    }

    /// 语言选项。
    nonisolated private enum Item: Hashable, Sendable {
        case system
        case language(AppLanguage)

        var preference: AppLanguagePreference {
            switch self {
            case .system:
                return .system
            case .language(let language):
                return .language(language)
            }
        }

        var titleKey: String {
            switch self {
            case .system:
                return "language.option.system"
            case .language(let language):
                return language.displayNameKey
            }
        }

        var nativeTitle: String? {
            switch self {
            case .system:
                return nil
            case .language(.simplifiedChinese):
                return "简体中文"
            case .language(.traditionalChinese):
                return "繁體中文"
            case .language(.english):
                return "English"
            case .language(.arabic):
                return "العربية"
            }
        }

        var subtitleKey: String {
            switch self {
            case .system:
                return "account.language.currentSystemFormat"
            case .language(.simplifiedChinese):
                return "language.subtitle.simplifiedChinese"
            case .language(.traditionalChinese):
                return "language.subtitle.traditionalChinese"
            case .language(.english):
                return "language.subtitle.english"
            case .language(.arabic):
                return "language.subtitle.arabic"
            }
        }

        var accessibilityIdentifier: String {
            switch self {
            case .system:
                return "account.language.system"
            case .language(let language):
                return "account.language.\(language.identifier)"
            }
        }
    }

    /// 关闭按钮。
    private let closeButton = UIButton(type: .system)
    /// 页面标题。
    private let titleLabel = UILabel()
    /// 分组标题。
    private let sectionTitleLabel = UILabel()
    /// 列表圆角容器。
    private let listContainerView = UIView()
    /// 底部搜索容器。
    private let searchContainerView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    /// 搜索图标。
    private let searchIconView = UIImageView(image: UIImage(systemName: "magnifyingglass"))
    /// 搜索输入框。
    private let searchTextField = UITextField()
    /// 语音图标。
    private let microphoneIconView = UIImageView(image: UIImage(systemName: "mic.fill"))
    /// 语言选项列表。
    private var collectionView: UICollectionView!
    /// 列表数据源。
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>?
    /// 当前导航栏显示状态，用于离开页面时恢复。
    private var previousNavigationBarHidden = false
    /// 当前搜索关键字。
    private var searchQuery = ""

    private var allItems: [Item] {
        [.system] + [.english, .simplifiedChinese, .traditionalChinese, .arabic].map(Item.language)
    }

    private var visibleItems: [Item] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return allItems
        }

        return allItems.filter { item in
            let values = [
                displayTitle(for: item),
                localizedSubtitle(for: item),
                L10n.shared.tr(item.titleKey)
            ]
            return values.contains { $0.lowercased().contains(query) }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        previousNavigationBarHidden = navigationController?.isNavigationBarHidden ?? false
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(previousNavigationBarHidden, animated: animated)
    }

    /// 配置页面基础结构。
    private func configureView() {
        view.backgroundColor = UIColor(red: 0.951, green: 0.953, blue: 0.973, alpha: 1)
        configureHeader()
        configureCollectionView()
        configureSearchBar()
        configureDataSource()
        applyLocalizedText()
        updateSnapshot()
    }

    /// 配置顶部关闭按钮和居中标题。
    private func configureHeader() {
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.backgroundColor = .secondarySystemGroupedBackground
        closeButton.layer.cornerRadius = Layout.closeButtonSize / 2
        closeButton.tintColor = .label
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.accessibilityIdentifier = "language.closeButton"
        closeButton.addTarget(self, action: #selector(closeLanguageSettings), for: .touchUpInside)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .systemFont(ofSize: Layout.titleFontSize, weight: .bold)
        )
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true

        sectionTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        sectionTitleLabel.font = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .systemFont(ofSize: Layout.sectionTitleFontSize, weight: .bold)
        )
        sectionTitleLabel.textColor = .secondaryLabel
        sectionTitleLabel.adjustsFontForContentSizeCategory = true

        view.addSubview(closeButton)
        view.addSubview(titleLabel)
        view.addSubview(sectionTitleLabel)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Layout.closeButtonTopSpacing),
            closeButton.widthAnchor.constraint(equalToConstant: Layout.closeButtonSize),
            closeButton.heightAnchor.constraint(equalToConstant: Layout.closeButtonSize),

            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: closeButton.trailingAnchor, constant: Layout.horizontalInset),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),

            sectionTitleLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: Layout.contentHorizontalInset),
            sectionTitleLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -Layout.contentHorizontalInset),
            sectionTitleLabel.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: Layout.headerToSectionSpacing)
        ])
    }

    /// 配置列表。
    private func configureCollectionView() {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.backgroundColor = .white
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .white
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 84, right: 0)
        collectionView.delegate = self
        collectionView.accessibilityIdentifier = "language.collectionView"
        listContainerView.translatesAutoresizingMaskIntoConstraints = false
        listContainerView.backgroundColor = .white
        listContainerView.layer.cornerRadius = Layout.listCornerRadius
        listContainerView.layer.cornerCurve = .continuous
        listContainerView.clipsToBounds = true
        view.addSubview(listContainerView)
        listContainerView.addSubview(collectionView)
        self.collectionView = collectionView

        NSLayoutConstraint.activate([
            listContainerView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            listContainerView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            listContainerView.topAnchor.constraint(equalTo: sectionTitleLabel.bottomAnchor, constant: 16),
            listContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),

            collectionView.leadingAnchor.constraint(equalTo: listContainerView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: listContainerView.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: listContainerView.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: listContainerView.bottomAnchor)
        ])
    }

    /// 配置底部悬浮搜索条。
    private func configureSearchBar() {
        searchContainerView.translatesAutoresizingMaskIntoConstraints = false
        searchContainerView.layer.cornerRadius = Layout.searchCornerRadius
        searchContainerView.layer.cornerCurve = .continuous
        searchContainerView.clipsToBounds = true
        searchContainerView.accessibilityIdentifier = "language.searchContainer"

        searchIconView.translatesAutoresizingMaskIntoConstraints = false
        searchIconView.tintColor = .label
        searchIconView.contentMode = .scaleAspectFit

        searchTextField.translatesAutoresizingMaskIntoConstraints = false
        searchTextField.borderStyle = .none
        searchTextField.clearButtonMode = .whileEditing
        searchTextField.font = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .systemFont(ofSize: Layout.languageTitleFontSize, weight: .regular)
        )
        searchTextField.textColor = .label
        searchTextField.adjustsFontForContentSizeCategory = true
        searchTextField.accessibilityIdentifier = "language.searchTextField"
        searchTextField.addTarget(self, action: #selector(searchTextDidChange), for: .editingChanged)

        microphoneIconView.translatesAutoresizingMaskIntoConstraints = false
        microphoneIconView.tintColor = .label
        microphoneIconView.contentMode = .scaleAspectFit

        view.addSubview(searchContainerView)
        let contentView = searchContainerView.contentView
        contentView.addSubview(searchIconView)
        contentView.addSubview(searchTextField)
        contentView.addSubview(microphoneIconView)

        NSLayoutConstraint.activate([
            searchContainerView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: Layout.searchHorizontalInset),
            searchContainerView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -Layout.searchHorizontalInset),
            searchContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Layout.searchBottomSpacing),
            searchContainerView.heightAnchor.constraint(equalToConstant: Layout.searchHeight),

            searchIconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Layout.searchIconInset),
            searchIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            searchIconView.widthAnchor.constraint(equalToConstant: Layout.searchIconSize),
            searchIconView.heightAnchor.constraint(equalToConstant: Layout.searchIconSize),

            microphoneIconView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Layout.searchIconInset),
            microphoneIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            microphoneIconView.widthAnchor.constraint(equalToConstant: Layout.microphoneIconSize),
            microphoneIconView.heightAnchor.constraint(equalToConstant: Layout.microphoneIconSize),

            searchTextField.leadingAnchor.constraint(equalTo: searchIconView.trailingAnchor, constant: 16),
            searchTextField.trailingAnchor.constraint(equalTo: microphoneIconView.leadingAnchor, constant: -16),
            searchTextField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            searchTextField.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6)
        ])
    }

    /// 配置 diffable data source。
    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<LanguageOptionCell, Item> { [weak self] cell, _, item in
            self?.configure(cell: cell, item: item)
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }
    }

    /// 配置单个语言选项行。
    private func configure(cell: LanguageOptionCell, item: Item) {
        let context = AppLanguageManager.shared.currentContext
        let titleFont = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .systemFont(ofSize: Layout.languageTitleFontSize, weight: .regular)
        )
        let subtitleFont = UIFontMetrics(forTextStyle: .title3).scaledFont(
            for: .systemFont(ofSize: Layout.languageSubtitleFontSize, weight: .regular)
        )
        cell.configure(
            title: displayTitle(for: item),
            subtitle: localizedSubtitle(for: item),
            titleFont: titleFont,
            subtitleFont: subtitleFont,
            isSelected: item.preference == AppLanguageManager.shared.preference,
            layoutDirection: context.semanticContentAttribute,
            titleDirection: titleSemanticContentAttribute(for: item, context: context),
            subtitleDirection: context.semanticContentAttribute,
            hidesSeparator: item == visibleItems.last
        )
        cell.accessibilityIdentifier = item.accessibilityIdentifier
    }

    /// 语言原生名称按自身语言决定书写方向，“跟随系统”行则跟随当前界面语言。
    private func titleSemanticContentAttribute(
        for item: Item,
        context: AppLanguageContext
    ) -> UISemanticContentAttribute {
        switch item {
        case .system:
            return context.semanticContentAttribute
        case .language(.arabic):
            return .forceRightToLeft
        case .language(.simplifiedChinese), .language(.traditionalChinese), .language(.english):
            return .forceLeftToRight
        }
    }

    /// 主标题遵循附件样式：手动语言展示原生名称，“跟随系统”使用当前界面语言。
    private func displayTitle(for item: Item) -> String {
        item.nativeTitle ?? L10n.shared.tr(item.titleKey)
    }

    /// 当前语言下的副标题，参照系统语言列表展示“本地语言名 + 当前界面语言说明”。
    private func localizedSubtitle(for item: Item) -> String {
        switch item {
        case .system:
            return systemLanguageSubtitle()
        case .language:
            return L10n.shared.tr(item.subtitleKey)
        }
    }

    /// 跟随系统行展示当前解析出的实际语言。
    private func systemLanguageSubtitle() -> String {
        let resolvedName = L10n.shared.tr(AppLanguageManager.shared.currentContext.resolvedLanguage.displayNameKey)
        return L10n.shared.tr("account.language.currentSystemFormat", resolvedName)
    }

    /// 刷新列表快照。
    private func updateSnapshot(forceReconfigure: Bool = false) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(visibleItems, toSection: .main)
        if forceReconfigure {
            snapshot.reconfigureItems(snapshot.itemIdentifiers)
        }
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    /// 刷新导航文案。
    private func applyLocalizedText() {
        let title = L10n.shared.tr("language.title.select")
        self.title = title
        titleLabel.text = title
        sectionTitleLabel.text = L10n.shared.tr("language.section.iphoneLanguages")
        searchTextField.placeholder = L10n.shared.tr("language.search.placeholder")
    }

    @objc private func closeLanguageSettings() {
        if let navigationController, navigationController.presentingViewController != nil {
            navigationController.dismiss(animated: true)
        } else if presentingViewController != nil {
            dismiss(animated: true)
        } else if let navigationController {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    @objc private func searchTextDidChange() {
        searchQuery = searchTextField.text ?? ""
        updateSnapshot()
    }
}

extension LanguageSettingsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource?.itemIdentifier(for: indexPath) else {
            return
        }

        AppLanguageManager.shared.setPreference(item.preference)
        applyLanguageChangeImmediately(AppLanguageManager.shared.currentContext)
    }

    /// 点选语言后先同步刷新当前窗口，避免从 RTL 切回 LTR 时等待 SceneDelegate 异步通知造成短暂方向残留。
    private func applyLanguageChangeImmediately(_ context: AppLanguageContext) {
        if let window = view.window {
            window.applyAppLanguageContext(context)
        } else if let navigationController {
            navigationController.notifyLanguageChangeRecursively(context)
        } else {
            notifyLanguageChangeRecursively(context)
        }
    }
}

extension LanguageSettingsViewController: AppLanguageUpdatable {
    /// 语言变化后刷新页面标题、选中状态和 RTL 布局。
    func applyLanguageChange(_ context: AppLanguageContext) {
        view.applyLanguageSemanticContentAttribute(context.semanticContentAttribute)
        applyLocalizedText()
        searchIconView.image = UIImage(systemName: "magnifyingglass")
        microphoneIconView.image = UIImage(systemName: "mic.fill")
        collectionView.semanticContentAttribute = context.semanticContentAttribute
        collectionView.collectionViewLayout.invalidateLayout()
        updateSnapshot(forceReconfigure: true)
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
    }
}

/// 语言设置页专用行。使用自有 cell 避免 `UICollectionViewListCell` 在 RTL / LTR 反复切换后复用内部 content/accessory 状态。
private final class LanguageOptionCell: UICollectionViewCell {
    private enum Layout {
        static let horizontalInset: CGFloat = 22
        static let verticalInset: CGFloat = 8
        static let checkmarkSize: CGFloat = 24
        static let checkmarkSpacing: CGFloat = 14
    }

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let textStackView = UIStackView()
    private let checkmarkImageView = UIImageView(image: UIImage(systemName: "checkmark"))
    private let separatorView = UIView()
    private var textLeadingToContentConstraint: NSLayoutConstraint?
    private var textTrailingToCheckmarkConstraint: NSLayoutConstraint?
    private var textLeadingToCheckmarkConstraint: NSLayoutConstraint?
    private var textTrailingToContentConstraint: NSLayoutConstraint?
    private var checkmarkLeadingConstraint: NSLayoutConstraint?
    private var checkmarkTrailingConstraint: NSLayoutConstraint?

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
        titleLabel.text = nil
        subtitleLabel.text = nil
        checkmarkImageView.isHidden = true
        separatorView.isHidden = false
    }

    /// 按当前页面方向和语言自身书写方向刷新行内容。
    func configure(
        title: String,
        subtitle: String,
        titleFont: UIFont,
        subtitleFont: UIFont,
        isSelected: Bool,
        layoutDirection: UISemanticContentAttribute,
        titleDirection: UISemanticContentAttribute,
        subtitleDirection: UISemanticContentAttribute,
        hidesSeparator: Bool
    ) {
        semanticContentAttribute = layoutDirection
        contentView.semanticContentAttribute = layoutDirection
        titleLabel.semanticContentAttribute = titleDirection
        subtitleLabel.semanticContentAttribute = subtitleDirection
        titleLabel.attributedText = attributedText(title, direction: titleDirection, font: titleFont, color: .label)
        subtitleLabel.attributedText = attributedText(subtitle, direction: subtitleDirection, font: subtitleFont, color: .secondaryLabel)
        checkmarkImageView.isHidden = !isSelected
        separatorView.isHidden = hidesSeparator
        applyLayoutDirection(layoutDirection)
    }

    private func configureHierarchy() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.textAlignment = .natural

        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 1
        subtitleLabel.textAlignment = .natural

        textStackView.translatesAutoresizingMaskIntoConstraints = false
        textStackView.axis = .vertical
        textStackView.alignment = .fill
        textStackView.spacing = 2
        textStackView.addArrangedSubview(titleLabel)
        textStackView.addArrangedSubview(subtitleLabel)

        checkmarkImageView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkImageView.tintColor = .systemBlue
        checkmarkImageView.contentMode = .scaleAspectFit

        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = .separator

        contentView.addSubview(textStackView)
        contentView.addSubview(checkmarkImageView)
        contentView.addSubview(separatorView)

        textLeadingToContentConstraint = textStackView.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor,
            constant: Layout.horizontalInset
        )
        textTrailingToCheckmarkConstraint = textStackView.trailingAnchor.constraint(
            equalTo: checkmarkImageView.leadingAnchor,
            constant: -Layout.checkmarkSpacing
        )
        textLeadingToCheckmarkConstraint = textStackView.leadingAnchor.constraint(
            equalTo: checkmarkImageView.trailingAnchor,
            constant: Layout.checkmarkSpacing
        )
        textTrailingToContentConstraint = textStackView.trailingAnchor.constraint(
            equalTo: contentView.trailingAnchor,
            constant: -Layout.horizontalInset
        )
        checkmarkLeadingConstraint = checkmarkImageView.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor,
            constant: Layout.horizontalInset
        )
        checkmarkTrailingConstraint = checkmarkImageView.trailingAnchor.constraint(
            equalTo: contentView.trailingAnchor,
            constant: -Layout.horizontalInset
        )

        NSLayoutConstraint.activate([
            textStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Layout.verticalInset),
            textStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Layout.verticalInset),
            checkmarkImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: Layout.checkmarkSize),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: Layout.checkmarkSize),
            separatorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Layout.horizontalInset),
            separatorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Layout.horizontalInset),
            separatorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])
        applyLayoutDirection(.forceLeftToRight)
    }

    private func applyLayoutDirection(_ direction: UISemanticContentAttribute) {
        let isRTL = direction == .forceRightToLeft
        let textAlignment: NSTextAlignment = isRTL ? .right : .left
        textStackView.alignment = isRTL ? .trailing : .leading
        titleLabel.textAlignment = textAlignment
        subtitleLabel.textAlignment = textAlignment
        textLeadingToContentConstraint?.isActive = !isRTL
        textTrailingToCheckmarkConstraint?.isActive = !isRTL
        checkmarkTrailingConstraint?.isActive = !isRTL
        textLeadingToCheckmarkConstraint?.isActive = isRTL
        textTrailingToContentConstraint?.isActive = isRTL
        checkmarkLeadingConstraint?.isActive = isRTL
        setNeedsLayout()
    }

    /// 每个语言名称按自身方向写入，避免 LTR/CJK 文本在 RTL 页面状态下被倒序渲染。
    private func attributedText(
        _ text: String,
        direction: UISemanticContentAttribute,
        font: UIFont,
        color: UIColor
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
