//
//  ConversationListViewController.swift
//  AppleIM
//
//  Created by Sondra on 2026/4/28.
//

import Combine
import UIKit

/// 主会话列表 section 标识
private let conversationListSection = "main"
/// 搜索联系人 section 标识
private let searchContactsSection = "search_contacts"
/// 搜索会话 section 标识
private let searchConversationsSection = "search_conversations"
/// 搜索消息 section 标识
private let searchMessagesSection = "search_messages"
/// 会话列表导航标题
private let conversationListNavigationTitle = "Messages"

/// 会话列表账号操作
nonisolated enum ConversationListAccountAction: Sendable {
    /// 切换当前账号
    case switchAccount
    /// 退出当前账号
    case logOut
    /// 删除当前账号本地数据
    case deleteLocalData
}

/// 会话列表页面控制器
@MainActor
final class ConversationListViewController: UIViewController {
    /// 会话列表 ViewModel
    private let viewModel: ConversationListViewModel
    /// 搜索 ViewModel
    private let searchViewModel: SearchViewModel
    /// 选择会话回调
    private let onSelectConversation: (ConversationListRowState) -> Void
    /// 首次加载结束回调
    private let onInitialLoadFinished: () -> Void
    /// 账号操作回调
    private let onAccountAction: (ConversationListAccountAction) -> Void
    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()
    /// 列表 diffable 数据源
    private var dataSource: UICollectionViewDiffableDataSource<String, String>?
    /// 当前会话行缓存
    private var rowsByID: [String: ConversationListRowState] = [:]
    /// 当前搜索行缓存
    private var searchRowsByID: [String: SearchResultRowState] = [:]
    /// 已渲染的会话 ID 顺序
    private var renderedConversationIDs: [String] = []
    /// 最近一次会话状态
    private var lastConversationState = ConversationListViewState()
    /// 最近一次搜索状态
    private var lastSearchState = SearchViewState()
    /// 是否已上报首次加载结束
    private var didReportInitialLoadFinished = false
    /// 页面离开后再次出现时刷新列表，避免已读、同步等后台变化滞后
    private var shouldRefreshOnNextAppear = false
    /// 页面当前是否处于可见生命周期内
    private var isVisible = false

    /// 会话列表 collection view
    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: makeLayout()
    )
    /// 系统搜索控制器
    private let searchController = UISearchController(searchResultsController: nil)

    /// 空状态标签
    private let emptyLabel = UILabel()
    /// 加载指示器
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    /// 初始化会话列表页面
    init(
        viewModel: ConversationListViewModel,
        searchViewModel: SearchViewModel,
        onSelectConversation: @escaping (ConversationListRowState) -> Void,
        onInitialLoadFinished: @escaping () -> Void = {},
        onAccountAction: @escaping (ConversationListAccountAction) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.searchViewModel = searchViewModel
        self.onSelectConversation = onSelectConversation
        self.onInitialLoadFinished = onInitialLoadFinished
        self.onAccountAction = onAccountAction
        super.init(nibName: nil, bundle: nil)
    }

    /// 禁用 storyboard 初始化
    required init?(coder: NSCoder) {
        fatalError("Storyboard initialization is not supported.")
    }

    /// 配置视图、数据源和状态绑定
    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        configureDataSource()
        bindViewModel()
        bindConversationStoreNotifications()
    }

    /// 页面出现时触发会话加载
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isVisible = true
        navigationController?.navigationBar.prefersLargeTitles = true
        if shouldRefreshOnNextAppear {
            shouldRefreshOnNextAppear = false
            viewModel.refresh()
        } else {
            viewModel.loadIfNeeded()
        }
    }

    /// 页面消失时取消会话和搜索任务
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isVisible = false
        shouldRefreshOnNextAppear = true
        viewModel.cancel()
        searchViewModel.cancel()
    }

    /// 创建会话列表视图层级和约束
    private func configureView() {
        title = conversationListNavigationTitle
        navigationItem.largeTitleDisplayMode = .always
        view.backgroundColor = .systemBackground

        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search"
        searchController.searchBar.accessibilityIdentifier = "conversationList.searchBar"
        searchController.searchBar.searchTextField.accessibilityIdentifier = "conversationList.searchField"
        searchController.searchBar.searchTextField.backgroundColor = .secondarySystemBackground
        definesPresentationContext = true

        let accountButton = UIButton(type: .system)
        var accountConfiguration = UIButton.Configuration.plain()
        accountConfiguration.image = UIImage(systemName: "person.crop.circle")
        accountConfiguration.baseForegroundColor = .systemBlue
        accountConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6)
        accountButton.configuration = accountConfiguration
        accountButton.accessibilityIdentifier = "conversationList.accountButton"
        accountButton.accessibilityLabel = "Account"
        accountButton.addTarget(self, action: #selector(accountButtonTapped), for: .touchUpInside)
        accountButton.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: accountButton)

        let simulateIncomingButton = UIButton(type: .system)
        var simulateIncomingConfiguration = UIButton.Configuration.plain()
        simulateIncomingConfiguration.image = UIImage(systemName: "text.bubble")
        simulateIncomingConfiguration.baseForegroundColor = .systemBlue
        simulateIncomingConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6)
        simulateIncomingButton.configuration = simulateIncomingConfiguration
        simulateIncomingButton.accessibilityIdentifier = "conversationList.simulateIncomingButton"
        simulateIncomingButton.accessibilityLabel = "模拟接收消息"
        simulateIncomingButton.addTarget(self, action: #selector(simulateIncomingButtonTapped), for: .touchUpInside)
        simulateIncomingButton.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: simulateIncomingButton)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.accessibilityIdentifier = "conversationList.collection"

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true

        view.addSubview(collectionView)
        view.addSubview(emptyLabel)
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    /// 配置 diffable data source 与 section header
    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<ConversationListCell, String> { [weak self] cell, _, rowID in
            guard let self else { return }

            if let row = rowsByID[rowID] {
                cell.configure(row: row)
                cell.isAccessibilityElement = true
                cell.accessibilityIdentifier = "conversationList.cell.\(row.id.rawValue)"
                cell.accessibilityLabel = self.accessibilityLabel(for: row)
            } else if let row = searchRowsByID[rowID] {
                cell.configure(searchRow: row)
                cell.isAccessibilityElement = true
                cell.accessibilityIdentifier = "conversationList.searchCell.\(rowID)"
                cell.accessibilityLabel = [row.title, row.subtitle].compactMap { $0 }.joined(separator: ", ")
            }
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<ConversationListHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] supplementaryView, _, indexPath in
            guard
                let self,
                let sectionID = self.dataSource?.snapshot().sectionIdentifiers[safe: indexPath.section]
            else {
                supplementaryView.configure(title: "")
                return
            }

            supplementaryView.configure(title: self.title(for: sectionID))
        }

        dataSource = UICollectionViewDiffableDataSource<String, String>(
            collectionView: collectionView
        ) { (collectionView: UICollectionView, indexPath: IndexPath, rowID: String) in
            collectionView.dequeueConfiguredReusableCell(
                using: cellRegistration,
                for: indexPath,
                item: rowID
            )
        }

        dataSource?.supplementaryViewProvider = { (collectionView: UICollectionView, _: String, indexPath: IndexPath) -> UICollectionReusableView? in
            collectionView.dequeueConfiguredReusableSupplementary(
                using: headerRegistration,
                for: indexPath
            )
        }

        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        snapshot.appendSections([conversationListSection])
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    /// 绑定会话列表和搜索状态
    private func bindViewModel() {
        viewModel.statePublisher
            .sink { [weak self] state in
                self?.lastConversationState = state
                guard self?.lastSearchState.isSearching != true else { return }
                self?.renderConversations(state)
                self?.reportInitialLoadFinishedIfNeeded(for: state)
            }
            .store(in: &cancellables)

        searchViewModel.statePublisher
            .sink { [weak self] state in
                self?.lastSearchState = state
                if state.isSearching {
                    self?.renderSearch(state)
                } else {
                    self?.renderConversations(self?.lastConversationState ?? ConversationListViewState())
                }
            }
            .store(in: &cancellables)
    }

    /// 监听仓储层会话变更，保持列表停留时的未读数与摘要同步。
    private func bindConversationStoreNotifications() {
        NotificationCenter.default.publisher(for: .chatStoreConversationsDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, isVisible else { return }
                viewModel.refresh()
            }
            .store(in: &cancellables)
    }

    /// 渲染普通会话列表状态
    private func renderConversations(_ state: ConversationListViewState) {
        title = conversationListNavigationTitle
        emptyLabel.text = state.emptyMessage
        emptyLabel.isHidden = !state.isEmpty || state.phase == .loading

        if state.phase == .loading {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }

        let previousRowsByID = rowsByID
        rowsByID = Dictionary(uniqueKeysWithValues: state.rows.map { ($0.id.rawValue, $0) })
        searchRowsByID = [:]
        let rowIDs = state.rows.map { $0.id.rawValue }
        let changedRowIDs = rowIDs.filter { previousRowsByID[$0] != rowsByID[$0] }

        if shouldRebuildConversationSnapshot(with: rowIDs, phase: state.phase) {
            var snapshot = NSDiffableDataSourceSnapshot<String, String>()
            snapshot.appendSections([conversationListSection])
            snapshot.appendItems(rowIDs, toSection: conversationListSection)
            dataSource?.apply(snapshot, animatingDifferences: state.phase != .loading && !renderedConversationIDs.isEmpty)
        } else if rowIDs.count > renderedConversationIDs.count {
            var snapshot = dataSource?.snapshot() ?? NSDiffableDataSourceSnapshot<String, String>()

            if !snapshot.sectionIdentifiers.contains(conversationListSection) {
                snapshot.appendSections([conversationListSection])
            }

            let newRowIDs = Array(rowIDs.dropFirst(renderedConversationIDs.count))
            snapshot.appendItems(newRowIDs, toSection: conversationListSection)
            snapshot.reconfigureItems(changedRowIDs.filter { !newRowIDs.contains($0) })
            dataSource?.apply(snapshot, animatingDifferences: false)
        } else if !changedRowIDs.isEmpty {
            var snapshot = dataSource?.snapshot() ?? NSDiffableDataSourceSnapshot<String, String>()
            snapshot.reconfigureItems(changedRowIDs)
            dataSource?.apply(snapshot, animatingDifferences: false)
        }

        renderedConversationIDs = rowIDs
    }

    /// 在首次加载进入终态时回调上层
    private func reportInitialLoadFinishedIfNeeded(for state: ConversationListViewState) {
        guard !didReportInitialLoadFinished else { return }

        switch state.phase {
        case .loaded, .failed:
            didReportInitialLoadFinished = true
            onInitialLoadFinished()
        case .idle, .loading:
            break
        }
    }

    /// 渲染搜索结果状态
    private func renderSearch(_ state: SearchViewState) {
        title = conversationListNavigationTitle

        if state.phase == .loading {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }

        switch state.phase {
        case .failed(let message):
            emptyLabel.text = message
        default:
            emptyLabel.text = "No results"
        }

        emptyLabel.isHidden = state.phase == .loading || !state.isEmpty
        rowsByID = [:]
        renderedConversationIDs = []

        let allRows = state.contacts + state.conversations + state.messages
        searchRowsByID = Dictionary(uniqueKeysWithValues: allRows.map { ($0.id, $0) })

        var snapshot = NSDiffableDataSourceSnapshot<String, String>()

        if !state.contacts.isEmpty {
            snapshot.appendSections([searchContactsSection])
            snapshot.appendItems(state.contacts.map(\.id), toSection: searchContactsSection)
        }

        if !state.conversations.isEmpty {
            snapshot.appendSections([searchConversationsSection])
            snapshot.appendItems(state.conversations.map(\.id), toSection: searchConversationsSection)
        }

        if !state.messages.isEmpty {
            snapshot.appendSections([searchMessagesSection])
            snapshot.appendItems(state.messages.map(\.id), toSection: searchMessagesSection)
        }

        dataSource?.apply(snapshot, animatingDifferences: true)
    }

    /// 判断是否需要完整重建会话列表快照
    private func shouldRebuildConversationSnapshot(with rowIDs: [String], phase: ConversationListViewState.LoadingPhase) -> Bool {
        guard !renderedConversationIDs.isEmpty else {
            return true
        }

        guard rowIDs.count >= renderedConversationIDs.count else {
            return true
        }

        return !rowIDs.starts(with: renderedConversationIDs) || phase == .loading
    }

    /// 创建列表布局
    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, layoutEnvironment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            let sectionID = self?.dataSource?.snapshot().sectionIdentifiers[safe: sectionIndex]
            if let sectionID = sectionID, sectionID != conversationListSection {
                configuration.headerMode = .supplementary
            } else {
                configuration.headerMode = .none
            }
            configuration.showsSeparators = false
            configuration.backgroundColor = .clear
            configuration.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
                self?.swipeActionsConfiguration(at: indexPath)
            }

            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
        }
    }

    /// 为会话行创建右滑操作
    private func swipeActionsConfiguration(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard
            let rowID = dataSource?.itemIdentifier(for: indexPath),
            let row = rowsByID[rowID]
        else {
            return nil
        }

        let muteTitle = row.isMuted ? "Unmute" : "Mute"
        let muteAction = UIContextualAction(style: .normal, title: muteTitle) { [weak self] _, _, completion in
            self?.viewModel.setMuted(conversationID: row.id, isMuted: !row.isMuted)
            completion(true)
        }
        muteAction.backgroundColor = .systemOrange
        muteAction.image = UIImage(systemName: row.isMuted ? "bell" : "bell.slash")

        let pinTitle = row.isPinned ? "Unpin" : "Pin"
        let pinAction = UIContextualAction(style: .normal, title: pinTitle) { [weak self] _, _, completion in
            self?.viewModel.setPinned(conversationID: row.id, isPinned: !row.isPinned)
            completion(true)
        }
        pinAction.backgroundColor = .systemBlue
        pinAction.image = UIImage(systemName: row.isPinned ? "pin.slash" : "pin")

        let configuration = UISwipeActionsConfiguration(actions: [muteAction, pinAction])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    /// 创建会话行尾部附件
    private func accessories(for row: ConversationListRowState) -> [UICellAccessory] {
        var accessories: [UICellAccessory] = [
            .customView(configuration: .init(customView: TrailingConversationStatusView(row: row), placement: .trailing()))
        ]

        if row.isMuted {
            accessories.append(.outlineDisclosure(options: .init(style: .cell)))
        }

        return accessories
    }

    /// 生成会话行无障碍描述
    private func accessibilityLabel(for row: ConversationListRowState) -> String {
        var parts = [row.title, row.subtitle]

        if let unreadText = row.unreadText {
            parts.append(unreadText)
        }

        if row.isPinned {
            parts.append("Pinned")
        }

        if row.isMuted {
            parts.append("Muted")
        }

        return parts.joined(separator: ", ")
    }

    /// 根据 section 标识返回展示标题
    private func title(for sectionID: String) -> String {
        switch sectionID {
        case conversationListSection:
            return ""
        case searchContactsSection:
            return "Contacts"
        case searchConversationsSection:
            return "Conversations"
        case searchMessagesSection:
            return "Messages"
        default:
            return ""
        }
    }

    /// 将搜索行转换为可打开的会话行
    private func conversationRow(for searchRow: SearchResultRowState) -> ConversationListRowState? {
        guard let conversationID = searchRow.conversationID else {
            return nil
        }

        if let existingRow = lastConversationState.rows.first(where: { $0.id == conversationID }) {
            return existingRow
        }

        return ConversationListRowState(
            id: conversationID,
            title: searchRow.kind == .message ? "Search Result" : searchRow.title,
            avatarURL: nil,
            subtitle: searchRow.kind == .message ? searchRow.title : searchRow.subtitle,
            timeText: "",
            unreadText: nil,
            isPinned: false,
            isMuted: false
        )
    }

    /// 打开账号操作菜单
    @objc private func accountButtonTapped() {
        let alertController = UIAlertController(
            title: "Account",
            message: "Manage your local session",
            preferredStyle: .actionSheet
        )

        let switchAction = UIAlertAction(title: "Switch Account", style: .default) { [weak self] _ in
            self?.onAccountAction(.switchAccount)
        }
        switchAction.setValue("accountAction.switchAccount", forKey: "accessibilityIdentifier")

        let logOutAction = UIAlertAction(title: "Log Out", style: .destructive) { [weak self] _ in
            self?.onAccountAction(.logOut)
        }
        logOutAction.setValue("accountAction.logOut", forKey: "accessibilityIdentifier")

        let deleteLocalDataAction = UIAlertAction(title: "Delete Local Data", style: .destructive) { [weak self] _ in
            self?.presentDeleteLocalDataConfirmation()
        }
        deleteLocalDataAction.setValue("accountAction.deleteLocalData", forKey: "accessibilityIdentifier")

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)

        alertController.addAction(switchAction)
        alertController.addAction(logOutAction)
        alertController.addAction(deleteLocalDataAction)
        alertController.addAction(cancelAction)

        if let popover = alertController.popoverPresentationController {
            popover.barButtonItem = navigationItem.leftBarButtonItem
        }

        present(alertController, animated: true)
    }

    /// 触发会话列表模拟收消息。
    @objc private func simulateIncomingButtonTapped() {
        viewModel.simulateIncomingMessages()
    }

    /// 二次确认当前账号本地数据删除。
    private func presentDeleteLocalDataConfirmation() {
        let presentConfirmation = { [weak self] in
            guard let self else { return }
            self.present(self.makeDeleteLocalDataConfirmationController(), animated: true)
        }

        if presentedViewController != nil {
            dismiss(animated: true) {
                presentConfirmation()
            }
        } else {
            presentConfirmation()
        }
    }

    /// 构造当前账号本地数据删除确认弹窗。
    func makeDeleteLocalDataConfirmationController() -> UIAlertController {
        let alertController = UIAlertController(
            title: "Delete Local Data?",
            message: "This deletes the current account's local database, search index, media files, cache, and database key from this device. Other accounts and mock account records are not affected.",
            preferredStyle: .alert
        )

        let confirmAction = UIAlertAction(title: "Delete Local Data", style: .destructive) { [weak self] _ in
            self?.onAccountAction(.deleteLocalData)
        }
        confirmAction.setValue("accountAction.confirmDeleteLocalData", forKey: "accessibilityIdentifier")

        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alertController.addAction(confirmAction)
        return alertController
    }
}

/// 会话列表交互回调
extension ConversationListViewController: UICollectionViewDelegate {
    /// 选择会话或搜索结果后进入聊天页
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        guard
            let rowID = dataSource?.itemIdentifier(for: indexPath),
            let row = rowsByID[rowID]
        else {
            if
                let rowID = dataSource?.itemIdentifier(for: indexPath),
                let searchRow = searchRowsByID[rowID],
                let conversation = conversationRow(for: searchRow)
            {
                viewModel.markConversationReadLocally(conversationID: conversation.id)
                onSelectConversation(conversation)
            }
            return
        }

        viewModel.markConversationReadLocally(conversationID: row.id)
        onSelectConversation(row)
    }

    /// 滚动时按当前可见位置触发分页加载
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard lastSearchState.isSearching == false else {
            return
        }

        let visibleRowID = collectionView.indexPathsForVisibleItems
            .max { lhs, rhs in
                if lhs.section == rhs.section {
                    return lhs.item < rhs.item
                }

                return lhs.section < rhs.section
            }
            .flatMap { dataSource?.itemIdentifier(for: $0) }
            .map(ConversationID.init(rawValue:))

        viewModel.loadNextPageIfNeeded(visibleRowID: visibleRowID)
    }
}

/// 搜索框输入更新
extension ConversationListViewController: UISearchResultsUpdating {
    /// 将搜索框文本同步给搜索 ViewModel
    func updateSearchResults(for searchController: UISearchController) {
        searchViewModel.setQuery(searchController.searchBar.text ?? "")
    }
}

/// 安全下标访问
private extension Array {
    /// 越界时返回 nil
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// 会话列表 section 头部视图
private final class ConversationListHeaderView: UICollectionReusableView {
    /// 标题标签
    private let titleLabel = UILabel()

    /// 初始化头部视图
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    /// 从 storyboard/xib 初始化头部视图
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    /// 设置头部标题
    func configure(title: String) {
        titleLabel.text = title
    }

    /// 配置标题样式和约束
    private func configureView() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label

        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }
}

/// 会话列表尾部状态视图
private final class TrailingConversationStatusView: UIView {
    /// 竖向状态栈
    private let stackView = UIStackView()
    /// 时间标签
    private let timeLabel = UILabel()

    /// 根据会话行初始化状态视图
    init(row: ConversationListRowState) {
        super.init(frame: .zero)
        configureView()
        configure(row: row)
    }

    /// 从 storyboard/xib 初始化状态视图
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    /// 配置状态视图层级和约束
    private func configureView() {
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .trailing
        stackView.spacing = 4

        timeLabel.font = .preferredFont(forTextStyle: .caption2)
        timeLabel.textColor = .secondaryLabel

        addSubview(stackView)
        stackView.addArrangedSubview(timeLabel)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// 根据会话行展示时间、未读或免打扰状态
    private func configure(row: ConversationListRowState) {
        timeLabel.text = row.timeText

        if let unreadText = row.unreadText {
            let unreadLabel = UnreadBadgeLabel()
            unreadLabel.text = unreadText
            stackView.addArrangedSubview(unreadLabel)
        } else if row.isMuted {
            let mutedLabel = UILabel()
            mutedLabel.font = .preferredFont(forTextStyle: .caption2)
            mutedLabel.textColor = .tertiaryLabel
            mutedLabel.text = "Muted"
            stackView.addArrangedSubview(mutedLabel)
        }
    }
}

/// 会话列表本地未读徽标
private final class UnreadBadgeLabel: UILabel {
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

    /// 保证徽标拥有最小可读尺寸
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: max(size.width + 12, 22), height: 22)
    }

    /// 配置徽标样式
    private func configure() {
        textAlignment = .center
        textColor = .white
        backgroundColor = .systemRed
        font = .preferredFont(forTextStyle: .caption2)
        layer.cornerRadius = 11
        layer.masksToBounds = true
    }
}
