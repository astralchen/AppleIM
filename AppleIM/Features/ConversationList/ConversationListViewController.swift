//
//  ConversationListViewController.swift
//  AppleIM
//
//  Created by Sondra on 2026/4/28.
//

import Combine
import UIKit

private let conversationListSection = "main"

@MainActor
final class ConversationListViewController: UIViewController {
    private let viewModel = ConversationListViewModel(useCase: PreviewConversationListUseCase())
    private var cancellables = Set<AnyCancellable>()
    private var dataSource: UICollectionViewDiffableDataSource<String, String>?
    private var rowsByID: [String: ConversationListRowState] = [:]

    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: makeLayout()
    )

    private let emptyLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        configureDataSource()
        bindViewModel()
        viewModel.load()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.cancel()
    }

    private func configureView() {
        title = "ChatBridge"
        view.backgroundColor = .systemBackground

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemGroupedBackground

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
            guard let self, let row = rowsByID[rowID] else { return }

            var content = cell.defaultContentConfiguration()
            content.text = row.title
            content.secondaryText = row.subtitle
            content.secondaryTextProperties.color = .secondaryLabel
            cell.contentConfiguration = content
            cell.accessories = self.accessories(for: row)

            var background = UIBackgroundConfiguration.listGroupedCell()
            background.backgroundColor = row.isPinned ? .secondarySystemGroupedBackground : .systemBackground
            cell.backgroundConfiguration = background
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<ConversationListHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { supplementaryView, _, _ in
            supplementaryView.configure(title: "ChatBridge")
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
                self?.render(state)
            }
            .store(in: &cancellables)
    }

    private func render(_ state: ConversationListViewState) {
        title = state.title
        emptyLabel.text = state.emptyMessage
        emptyLabel.isHidden = !state.isEmpty || state.phase == .loading

        if state.phase == .loading {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }

        rowsByID = Dictionary(uniqueKeysWithValues: state.rows.map { ($0.id.rawValue, $0) })

        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        snapshot.appendSections([conversationListSection])
        snapshot.appendItems(state.rows.map { $0.id.rawValue }, toSection: conversationListSection)
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
