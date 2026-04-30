//
//  ConversationListViewController.swift
//  AppleIM
//
//  Created by Sondra on 2026/4/28.
//

import Combine
import UIKit

private let conversationListSection = "main"
private let searchContactsSection = "search_contacts"
private let searchConversationsSection = "search_conversations"
private let searchMessagesSection = "search_messages"

@MainActor
final class ConversationListViewController: UIViewController {
    private let viewModel: ConversationListViewModel
    private let searchViewModel: SearchViewModel
    private let onSelectConversation: (ConversationListRowState) -> Void
    private var cancellables = Set<AnyCancellable>()
    private var dataSource: UICollectionViewDiffableDataSource<String, String>?
    private var rowsByID: [String: ConversationListRowState] = [:]
    private var searchRowsByID: [String: SearchResultRowState] = [:]
    private var lastConversationState = ConversationListViewState()
    private var lastSearchState = SearchViewState()

    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: makeLayout()
    )
    private let searchController = UISearchController(searchResultsController: nil)

    private let emptyLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    init(
        viewModel: ConversationListViewModel,
        searchViewModel: SearchViewModel,
        onSelectConversation: @escaping (ConversationListRowState) -> Void
    ) {
        self.viewModel = viewModel
        self.searchViewModel = searchViewModel
        self.onSelectConversation = onSelectConversation
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Storyboard initialization is not supported.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        configureDataSource()
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.load()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.cancel()
        searchViewModel.cancel()
    }

    private func configureView() {
        title = "ChatBridge"
        view.backgroundColor = .systemBackground
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search"
        definesPresentationContext = true

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.delegate = self

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

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, rowID in
            guard let self else { return }

            var content = cell.defaultContentConfiguration()
            if let row = rowsByID[rowID] {
                content.text = row.title
                content.secondaryText = row.subtitle
                content.secondaryTextProperties.color = .secondaryLabel
                cell.accessories = self.accessories(for: row)

                var background = UIBackgroundConfiguration.listGroupedCell()
                background.backgroundColor = row.isPinned ? .secondarySystemGroupedBackground : .systemBackground
                cell.backgroundConfiguration = background
            } else if let row = searchRowsByID[rowID] {
                content.text = row.title
                content.secondaryText = row.subtitle
                content.secondaryTextProperties.color = .secondaryLabel
                cell.accessories = row.conversationID == nil ? [] : [.disclosureIndicator()]
                cell.backgroundConfiguration = UIBackgroundConfiguration.listGroupedCell()
            }

            cell.contentConfiguration = content
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

    private func bindViewModel() {
        viewModel.statePublisher
            .sink { [weak self] state in
                self?.lastConversationState = state
                guard self?.lastSearchState.isSearching != true else { return }
                self?.renderConversations(state)
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

    private func renderConversations(_ state: ConversationListViewState) {
        title = state.title
        emptyLabel.text = state.emptyMessage
        emptyLabel.isHidden = !state.isEmpty || state.phase == .loading

        if state.phase == .loading {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }

        rowsByID = Dictionary(uniqueKeysWithValues: state.rows.map { ($0.id.rawValue, $0) })
        searchRowsByID = [:]

        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        snapshot.appendSections([conversationListSection])
        snapshot.appendItems(state.rows.map { $0.id.rawValue }, toSection: conversationListSection)
        dataSource?.apply(snapshot, animatingDifferences: true)
    }

    private func renderSearch(_ state: SearchViewState) {
        title = "Search"

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

    private func makeLayout() -> UICollectionViewLayout {
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.headerMode = .supplementary
        configuration.showsSeparators = true

        return UICollectionViewCompositionalLayout.list(using: configuration)
    }

    private func accessories(for row: ConversationListRowState) -> [UICellAccessory] {
        var accessories: [UICellAccessory] = [
            .customView(configuration: .init(customView: TrailingConversationStatusView(row: row), placement: .trailing()))
        ]

        if row.isMuted {
            accessories.append(.outlineDisclosure(options: .init(style: .cell)))
        }

        return accessories
    }

    private func title(for sectionID: String) -> String {
        switch sectionID {
        case conversationListSection:
            return "ChatBridge"
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
            subtitle: searchRow.kind == .message ? searchRow.title : searchRow.subtitle,
            timeText: "",
            unreadText: nil,
            isPinned: false,
            isMuted: false
        )
    }
}

extension ConversationListViewController: UICollectionViewDelegate {
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
                onSelectConversation(conversation)
            }
            return
        }

        onSelectConversation(row)
    }
}

extension ConversationListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchViewModel.setQuery(searchController.searchBar.text ?? "")
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private final class ConversationListHeaderView: UICollectionReusableView {
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    func configure(title: String) {
        titleLabel.text = title
    }

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

private final class TrailingConversationStatusView: UIView {
    private let stackView = UIStackView()
    private let timeLabel = UILabel()

    init(row: ConversationListRowState) {
        super.init(frame: .zero)
        configureView()
        configure(row: row)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

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

private final class UnreadBadgeLabel: UILabel {
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
        backgroundColor = .systemRed
        font = .preferredFont(forTextStyle: .caption2)
        layer.cornerRadius = 11
        layer.masksToBounds = true
    }
}
