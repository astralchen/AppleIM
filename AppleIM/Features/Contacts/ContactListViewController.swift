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
        var title: String {
            switch self {
            case .groups:
                return "群聊"
            case .starred:
                return "星标联系人"
            case .friends:
                return "联系人"
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
        title = "通讯录"
        view.backgroundColor = .systemGroupedBackground
        configureCollectionView()
        configureSearch()
        configureEmptyLabel()
        configureDataSource()
        bindViewModel()
        viewModel.load()
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
        searchController.searchBar.placeholder = "搜索联系人"
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
            guard let row = self?.rowsByID[rowID] else { return }
            var content = UIListContentConfiguration.subtitleCell()
            content.text = row.title
            content.secondaryText = row.subtitle
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.secondaryTextProperties.color = .secondaryLabel
            content.image = UIImage(systemName: row.type == .group ? "person.2.fill" : "person.crop.circle.fill")
            content.imageProperties.tintColor = row.type == .group ? ChatBridgeDesignSystem.ColorToken.sky : ChatBridgeDesignSystem.ColorToken.mint
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]
            cell.accessibilityIdentifier = "contacts.cell.\(row.id.rawValue)"
            cell.accessibilityLabel = [row.title, row.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            guard
                let sectionID = self?.dataSource?.snapshot().sectionIdentifiers[safe: indexPath.section]
            else {
                return
            }

            var content = UIListContentConfiguration.groupedHeader()
            content.text = sectionID.title
            header.contentConfiguration = content
        }

        dataSource = UICollectionViewDiffableDataSource<Section, ContactID>(collectionView: collectionView) { collectionView, indexPath, rowID in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: rowID)
        }
        dataSource?.supplementaryViewProvider = { collectionView, kind, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    private func bindViewModel() {
        viewModel.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.render(state)
            }
            .store(in: &cancellables)
    }

    private func render(_ state: ContactListViewState) {
        rowsByID = Dictionary(
            uniqueKeysWithValues: (state.groupRows + state.starredRows + state.contactRows).map { ($0.id, $0) }
        )

        var snapshot = NSDiffableDataSourceSnapshot<Section, ContactID>()
        append(state.groupRows, to: .groups, in: &snapshot)
        append(state.starredRows, to: .starred, in: &snapshot)
        append(state.contactRows, to: .friends, in: &snapshot)
        dataSource?.apply(snapshot, animatingDifferences: state.phase == .loaded)

        emptyLabel.text = state.emptyMessage
        emptyLabel.isHidden = state.phase != .loaded || !state.isEmpty
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

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
