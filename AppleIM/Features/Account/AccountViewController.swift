//
//  AccountViewController.swift
//  AppleIM
//
//  Apple 风格账号管理页
//

import UIKit

/// 账号管理页
@MainActor
final class AccountViewController: UITableViewController {
    /// 列表分区
    private enum Section: Int, CaseIterable {
        case profile
        case actions
    }

    /// 操作行
    private enum ActionRow: Int, CaseIterable {
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

    /// 初始化账号页
    init(state: AccountViewState, onAction: @escaping (AccountAction) -> Void) {
        self.state = state
        self.onAction = onAction
        super.init(style: .insetGrouped)
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

    /// 分区数量
    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    /// 行数量
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else {
            return 0
        }

        switch section {
        case .profile:
            return 1
        case .actions:
            return ActionRow.allCases.count
        }
    }

    /// 配置列表行
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch section {
        case .profile:
            return makeProfileCell()
        case .actions:
            return makeActionCell(at: indexPath)
        }
    }

    /// 处理列表选择
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard
            Section(rawValue: indexPath.section) == .actions,
            let row = ActionRow(rawValue: indexPath.row)
        else {
            return
        }

        switch row {
        case .deleteLocalData:
            present(makeDeleteLocalDataConfirmationController(), animated: true)
        case .switchAccount, .logOut:
            onAction(row.action)
        }
    }

    /// 配置基础视图属性
    private func configureView() {
        navigationItem.largeTitleDisplayMode = .always
        tableView.accessibilityIdentifier = "account.tableView"
        tableView.backgroundColor = .systemGroupedBackground
        tableView.cellLayoutMarginsFollowReadableWidth = true
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "AccountCell")
    }

    /// 构建账号资料行
    private func makeProfileCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.accessibilityIdentifier = "account.profileHeader"

        let profileView = AccountProfileHeaderView(state: state)
        profileView.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(profileView)

        NSLayoutConstraint.activate([
            profileView.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 16),
            profileView.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            profileView.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            profileView.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -16)
        ])

        return cell
    }

    /// 构建账号操作行
    private func makeActionCell(at indexPath: IndexPath) -> UITableViewCell {
        guard let row = ActionRow(rawValue: indexPath.row) else {
            return UITableViewCell()
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "AccountCell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = row.title
        content.image = UIImage(systemName: row.imageName)
        content.imageProperties.tintColor = row.isDestructive ? .systemRed : .systemBlue
        content.textProperties.color = row.isDestructive ? .systemRed : .label
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = row.accessibilityIdentifier
        return cell
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
