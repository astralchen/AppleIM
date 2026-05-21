//
//  ContactListViewController.swift
//  AppleIM
//
//  通讯录页面
//

import Combine
import UIKit

/// 通讯录页面
final class ContactListViewController: UIViewController {
    /// 通讯录分区标识。
    nonisolated private enum Section: Hashable, Sendable {
        /// 群聊分区。
        case groups
        /// 星标联系人分区。
        case starred
        /// 普通联系人分区。
        case friends

        /// 分区展示标题。
        var titleKey: String {
            switch self {
            case .groups:
                return "contacts.section.groups"
            case .starred:
                return "contacts.section.starred"
            case .friends:
                return "contacts.section.friends"
            }
        }
    }

    private let viewModel: ContactListViewModel
    private let onSelectConversation: (ConversationListRowState) -> Void
    private var cancellables: Set<AnyCancellable> = []
    private var dataSource: UICollectionViewDiffableDataSource<Section, ContactID>?
    private var rowsByID: [ContactID: ContactListRowState] = [:]
    private var collectionView: UICollectionView!
    private let searchController = UISearchController(searchResultsController: nil)
    private let emptyLabel = UILabel()

    init(
        viewModel: ContactListViewModel,
        onSelectConversation: @escaping (ConversationListRowState) -> Void
    ) {
        self.viewModel = viewModel
        self.onSelectConversation = onSelectConversation
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        applyLocalizedText()
        configureNavigationItems()
        configureCollectionView()
        configureSearch()
        configureEmptyLabel()
        configureDataSource()
        bindViewModel()
        viewModel.load()
    }

    private func configureNavigationItems() {
        let simulateProfileChangeButton = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "person.crop.circle.badge.exclamationmark")
        configuration.baseForegroundColor = .systemBlue
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6)
        simulateProfileChangeButton.configuration = configuration
        simulateProfileChangeButton.accessibilityIdentifier = "contacts.simulateProfileChangeButton"
        simulateProfileChangeButton.accessibilityLabel = "模拟用户信息变更"
        simulateProfileChangeButton.addTarget(self, action: #selector(simulateProfileChangeButtonTapped), for: .touchUpInside)
        simulateProfileChangeButton.frame = CGRect(x: 0, y: 0, width: 44, height: 44)

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(customView: simulateProfileChangeButton)
        ]
    }

    private func configureCollectionView() {
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.headerMode = .supplementary
        configuration.backgroundColor = .clear
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.accessibilityIdentifier = "contacts.collection"
        view.addSubview(collectionView)
        self.collectionView = collectionView

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureSearch() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.accessibilityIdentifier = "contacts.searchField"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func configureEmptyLabel() {
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, ContactID> { [weak self] cell, _, rowID in
            self?.cellRegistrationHandler(cell: cell, rowID: rowID)
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            self?.headerRegistrationHandler(header: header, indexPath: indexPath)
        }

        dataSource = UICollectionViewDiffableDataSource<Section, ContactID>(collectionView: collectionView) { collectionView, indexPath, rowID in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: rowID)
        }
        dataSource?.supplementaryViewProvider = { collectionView, kind, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    /// 配置联系人 cell。
    private func cellRegistrationHandler(cell: UICollectionViewListCell, rowID: ContactID) {
        guard let row = rowsByID[rowID] else { return }
        cell.contentConfiguration = contactConfiguration(for: cell, row: row)
        cell.accessories = [.disclosureIndicator()]
        cell.accessibilityIdentifier = "contacts.cell.\(row.id.rawValue)"
        cell.accessibilityLabel = [row.title, row.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// 构造联系人行内容配置。
    private func contactConfiguration(for cell: UICollectionViewListCell, row: ContactListRowState) -> UIListContentConfiguration {
        var content = cell.defaultContentConfiguration()
        content.text = row.title
        content.secondaryText = row.type == .group ? L10n.shared.tr("contacts.section.groups") : row.subtitle
        content.textProperties.font = .preferredFont(forTextStyle: .headline)
        content.secondaryTextProperties.color = .secondaryLabel
        content.image = UIImage(systemName: row.type == .group ? "person.2.fill" : "person.crop.circle.fill")
        content.imageProperties.tintColor = row.type == .group ? ChatBridgeDesignSystem.ColorToken.sky : ChatBridgeDesignSystem.ColorToken.mint
        return content
    }

    /// 配置联系人分组标题。
    private func headerRegistrationHandler(header: UICollectionViewListCell, indexPath: IndexPath) {
        guard
            let sectionID = dataSource?.snapshot().sectionIdentifiers[safe: indexPath.section]
        else {
            return
        }

        var content = UIListContentConfiguration.groupedHeader()
        content.text = L10n.shared.tr(sectionID.titleKey)
        header.contentConfiguration = content
    }

    private func bindViewModel() {
        viewModel.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.render(state)
            }
            .store(in: &cancellables)
    }

    private func render(_ state: ContactListViewState, forceReconfigure: Bool = false) {
        let previousRowsByID = rowsByID
        let nextRowsByID = Dictionary(
            uniqueKeysWithValues: (state.groupRows + state.starredRows + state.contactRows).map { ($0.id, $0) }
        )
        rowsByID = nextRowsByID

        var snapshot = NSDiffableDataSourceSnapshot<Section, ContactID>()
        append(state.groupRows, to: .groups, in: &snapshot)
        append(state.starredRows, to: .starred, in: &snapshot)
        append(state.contactRows, to: .friends, in: &snapshot)
        let currentSnapshot = dataSource?.snapshot()
        let changedVisibleIDs = nextRowsByID.compactMap { rowID, nextRow -> ContactID? in
            guard
                previousRowsByID[rowID] != nextRow,
                currentSnapshot?.indexOfItem(rowID) != nil,
                snapshot.indexOfItem(rowID) != nil
            else {
                return nil
            }
            return rowID
        }
        if forceReconfigure {
            snapshot.reconfigureItems(snapshot.itemIdentifiers)
        } else if !changedVisibleIDs.isEmpty {
            snapshot.reconfigureItems(changedVisibleIDs)
        }
        dataSource?.apply(snapshot, animatingDifferences: state.phase == .loaded)

        emptyLabel.text = localizedEmptyMessage(state.emptyMessage)
        emptyLabel.isHidden = state.phase != .loaded || !state.isEmpty
    }

    /// 刷新通讯录页面文案。
    private func applyLocalizedText() {
        title = L10n.shared.tr("contacts.title")
        navigationItem.title = L10n.shared.tr("contacts.title")
        tabBarItem.title = L10n.shared.tr("contacts.title")
        searchController.searchBar.placeholder = L10n.shared.tr("contacts.search.placeholder")
    }

    /// ViewState 中的错误保留业务原文，空态随语言刷新。
    private func localizedEmptyMessage(_ message: String) -> String {
        message == "No contacts yet" ? L10n.shared.tr("contacts.empty") : message
    }

    private func append(
        _ rows: [ContactListRowState],
        to section: Section,
        in snapshot: inout NSDiffableDataSourceSnapshot<Section, ContactID>
    ) {
        guard !rows.isEmpty else { return }

        snapshot.appendSections([section])
        snapshot.appendItems(rows.map(\.id), toSection: section)
    }

    @objc private func simulateProfileChangeButtonTapped() {
        viewModel.simulateContactProfileChange()
    }
}

extension ContactListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        guard
            let rowID = dataSource?.itemIdentifier(for: indexPath),
            let row = rowsByID[rowID]
        else {
            return
        }

        viewModel.open(row: row, onOpenConversation: onSelectConversation)
    }
}

extension ContactListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        viewModel.updateSearchQuery(searchController.searchBar.text ?? "")
    }
}

extension ContactListViewController: AppLanguageUpdatable {
    /// 语言变化后刷新导航、搜索框、分组标题和布局方向。
    func applyLanguageChange(_ context: AppLanguageContext) {
        view.applyLanguageSemanticContentAttribute(context.semanticContentAttribute)
        applyLocalizedText()
        collectionView.collectionViewLayout.invalidateLayout()
        render(viewModel.currentState, forceReconfigure: true)
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
