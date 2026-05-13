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
        case switchAccount
        case logOut
        case deleteLocalData

        var title: String {
            switch self {
            case .switchAccount:
                return "Switch Account"
            case .logOut:
                return "Log Out"
            case .deleteLocalData:
                return "Delete Local Data"
            }
        }

        var imageName: String {
            switch self {
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
            case .switchAccount:
                return "account.action.switchAccount"
            case .logOut:
                return "account.action.logOut"
            case .deleteLocalData:
                return "account.action.deleteLocalData"
            }
        }

        var action: AccountAction {
            switch self {
            case .switchAccount:
                return .switchAccount
            case .logOut:
                return .logOut
            case .deleteLocalData:
                return .deleteLocalData
            }
        }

        var isDestructive: Bool {
            switch self {
            case .switchAccount:
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
        title = "Account"
        tabBarItem = UITabBarItem(
            title: "Account",
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
        let profileRegistration = UICollectionView.CellRegistration<AccountProfileCell, Item> { [state] cell, _, _ in
            cell.configure(state: state)
        }
        let actionRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, item in
            guard case .action(let row) = item else { return }
            var content = cell.defaultContentConfiguration()
            content.text = row.title
            content.image = UIImage(systemName: row.imageName)
            content.imageProperties.tintColor = row.isDestructive ? .systemRed : .systemBlue
            content.textProperties.color = row.isDestructive ? .systemRed : .label
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]
            cell.accessibilityIdentifier = row.accessibilityIdentifier
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

    /// 更新列表快照
    private func updateSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections(Section.allCases)
        snapshot.appendItems([Item.profile], toSection: Section.profile)
        snapshot.appendItems(ActionRow.allCases.map(Item.action), toSection: Section.actions)
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    /// 构造当前账号本地数据删除确认弹窗。
    func makeDeleteLocalDataConfirmationController() -> UIAlertController {
        let alertController = UIAlertController(
            title: "Delete Local Data?",
            message: "This deletes the current account's local database, search index, media files, cache, and database key from this device. Other accounts and mock account records are not affected.",
            preferredStyle: .alert
        )

        let confirmAction = UIAlertAction(title: "Delete Local Data", style: .destructive) { [weak self] _ in
            self?.onAction(.deleteLocalData)
        }
        confirmAction.setValue("accountAction.confirmDeleteLocalData", forKey: "accessibilityIdentifier")

        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alertController.addAction(confirmAction)
        return alertController
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
        case .deleteLocalData:
            present(makeDeleteLocalDataConfirmationController(), animated: true)
        case .switchAccount, .logOut:
            onAction(row.action)
        }
    }
}

/// 账号资料列表单元
@MainActor
private final class AccountProfileCell: UICollectionViewListCell {
    /// 当前挂载的资料视图
    private var profileView: AccountProfileHeaderView?

    /// 配置资料内容
    func configure(state: AccountViewState) {
        contentConfiguration = nil
        profileView?.removeFromSuperview()

        let profileView = AccountProfileHeaderView(state: state)
        profileView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(profileView)
        self.profileView = profileView
        accessibilityIdentifier = "account.profileHeader"
        isAccessibilityElement = false

        NSLayoutConstraint.activate([
            profileView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            profileView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            profileView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            profileView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
    }

    /// 清理复用状态
    override func prepareForReuse() {
        super.prepareForReuse()
        profileView?.removeFromSuperview()
        profileView = nil
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
    init(state: AccountViewState) {
        super.init(frame: .zero)
        configure(state: state)
    }

    /// 禁用 storyboard 初始化
    required init?(coder: NSCoder) {
        fatalError("Storyboard initialization is not supported.")
    }

    /// 配置视图层级
    private func configure(state: AccountViewState) {
        accessibilityIdentifier = "account.profileHeader"

        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.image = UIImage(systemName: "person.crop.circle.fill")
        avatarImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 56, weight: .regular)
        avatarImageView.tintColor = .systemBlue
        avatarImageView.contentMode = .scaleAspectFit
        avatarImageView.accessibilityIdentifier = "account.avatarImageView"

        displayNameLabel.translatesAutoresizingMaskIntoConstraints = false
        displayNameLabel.text = state.displayName
        displayNameLabel.textColor = .label
        displayNameLabel.font = .preferredFont(forTextStyle: .title3)
        displayNameLabel.adjustsFontForContentSizeCategory = true
        displayNameLabel.numberOfLines = 0

        userIDLabel.translatesAutoresizingMaskIntoConstraints = false
        userIDLabel.text = state.userID.rawValue
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
}
