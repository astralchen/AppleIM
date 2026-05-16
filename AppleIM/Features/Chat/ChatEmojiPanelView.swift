//
//  ChatEmojiPanelView.swift
//  AppleIM
//

import UIKit

/// 表情面板对外发布的用户动作。
@MainActor
enum ChatEmojiPanelAction: Equatable {
    /// 选择表情。
    case selected(EmojiAssetRecord)
    /// 切换收藏状态。
    case favoriteToggled(EmojiAssetRecord, Bool)

    /// 动作类型，便于测试和调用方做轻量判断。
    enum Kind: Equatable {
        case selected
        case favoriteToggled
    }

    /// 动作关联的表情 ID。
    var emojiID: String {
        switch self {
        case let .selected(emoji), let .favoriteToggled(emoji, _):
            return emoji.emojiID
        }
    }

    /// 动作类型。
    var kind: Kind {
        switch self {
        case .selected:
            return .selected
        case .favoriteToggled:
            return .favoriteToggled
        }
    }
}

/// 聊天表情输入面板。
@MainActor
final class ChatEmojiPanelView: UIControl {
    static let panelHeight: CGFloat = 335

    /// 最近一次发布的用户动作。
    private(set) var lastAction: ChatEmojiPanelAction?

    private let sectionButtonStackView = UIStackView()
    private let collectionView: UICollectionView
    private let emptyLabel = UILabel()

    private var panelState = ChatEmojiPanelState.empty
    private var visibleSections: [Section] = []
    private var selectedSectionID: Section.ID?
    private var renderedSectionIDs: [Section.ID] = []
    private var sectionButtonsByID: [Section.ID: UIButton] = [:]
    private var renderedGridSignature: GridSignature?
    private var dataSource: UICollectionViewDiffableDataSource<Int, EmojiAssetRecord>?

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 10
        layout.minimumInteritemSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 12, left: 12, bottom: 20, right: 12)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 10
        layout.minimumInteritemSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 12, left: 12, bottom: 20, right: 12)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(coder: coder)
        configureView()
    }

    func render(_ state: ChatEmojiPanelState) {
        self.panelState = state
        rebuildSections()
        reconcileSelectedSection()
        rebuildSectionButtons()
        rebuildGrid()
        setNeedsLayout()
        layoutIfNeeded()
    }

    private func configureView() {
        clipsToBounds = false
        backgroundColor = .clear
        accessibilityIdentifier = "chat.emojiInputPanel"

        sectionButtonStackView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        sectionButtonStackView.axis = .horizontal
        sectionButtonStackView.alignment = .fill
        sectionButtonStackView.distribution = .fillEqually
        sectionButtonStackView.spacing = 8

        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .none
        collectionView.delegate = self
        collectionView.accessibilityIdentifier = "chat.emojiGrid"
        configureDataSource()

        emptyLabel.font = .preferredFont(forTextStyle: .subheadline)
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.text = "No emoji"

        addSubview(sectionButtonStackView)
        addSubview(collectionView)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            sectionButtonStackView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            sectionButtonStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            sectionButtonStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            sectionButtonStackView.heightAnchor.constraint(equalToConstant: 32),

            collectionView.topAnchor.constraint(equalTo: sectionButtonStackView.bottomAnchor, constant: 8),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
        ])
    }

    /// 配置表情网格数据源。
    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<ChatEmojiItemCell, EmojiAssetRecord> { [weak self] cell, _, emoji in
            cell.configure(emoji: emoji)
            cell.onSelect = { [weak self] emoji in
                self?.emit(.selected(emoji))
            }
            cell.onFavoriteToggle = { [weak self] emoji, isFavorite in
                self?.emit(.favoriteToggled(emoji, isFavorite))
            }
        }

        dataSource = UICollectionViewDiffableDataSource<Int, EmojiAssetRecord>(
            collectionView: collectionView
        ) { collectionView, indexPath, emoji in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: emoji)
        }
    }

    private func rebuildSections() {
        visibleSections = [
            Section(id: .recent, title: "最近", emojis: panelState.recentEmojis),
            Section(id: .favorites, title: "收藏", emojis: panelState.favoriteEmojis)
        ] + panelState.packages.map { package in
            Section(
                id: .package(package.packageID),
                title: package.title,
                emojis: panelState.packageEmojisByPackageID[package.packageID] ?? []
            )
        }
    }

    private func reconcileSelectedSection() {
        let firstNonEmptySectionID = visibleSections.first { !$0.emojis.isEmpty }?.id
        if let selectedSectionID,
           let selectedSection = visibleSections.first(where: { $0.id == selectedSectionID }),
           !selectedSection.emojis.isEmpty || firstNonEmptySectionID == nil {
            return
        }

        selectedSectionID = firstNonEmptySectionID
            ?? visibleSections.first?.id
    }

    private func rebuildSectionButtons() {
        sectionButtonStackView.isHidden = visibleSections.isEmpty
        let sectionIDs = visibleSections.map(\.id)

        if sectionIDs != renderedSectionIDs {
            sectionButtonStackView.arrangedSubviews.forEach { view in
                sectionButtonStackView.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            sectionButtonsByID.removeAll()
            renderedSectionIDs = sectionIDs

            for section in visibleSections {
                let button = makeSectionButton(for: section)
                sectionButtonsByID[section.id] = button
                sectionButtonStackView.addArrangedSubview(button)
            }
        }

        for section in visibleSections {
            if let button = sectionButtonsByID[section.id] {
                updateSectionButton(button, for: section)
            }
        }
    }

    private func makeSectionButton(for section: Section) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = section.title
        button.accessibilityIdentifier = "chat.emojiSection.\(section.id.accessibilitySuffix)"
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        updateSectionButton(button, for: section)
        button.addAction(UIAction { [weak self] _ in
            self?.selectedSectionID = section.id
            self?.updateSectionButtonStyles()
            self?.rebuildGrid(force: true)
        }, for: .touchUpInside)
        return button
    }

    private func updateSectionButton(_ button: UIButton, for section: Section) {
        button.accessibilityLabel = section.title
        button.accessibilityIdentifier = "chat.emojiSection.\(section.id.accessibilitySuffix)"
        var configuration = UIButton.Configuration.filled()
        configuration.title = section.title
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        configuration.baseForegroundColor = section.id == selectedSectionID ? .white : .label
        configuration.baseBackgroundColor = section.id == selectedSectionID
            ? .systemBlue
            : UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.75)
        button.configuration = configuration
        button.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.lineBreakMode = .byTruncatingTail
    }

    private func updateSectionButtonStyles() {
        for section in visibleSections {
            if let button = sectionButtonsByID[section.id] {
                updateSectionButton(button, for: section)
            }
        }
    }

    private func rebuildGrid(force: Bool = false) {
        let emojis = selectedSection?.emojis ?? []
        let gridSignature = GridSignature(
            sectionID: selectedSection?.id,
            emojiIDs: emojis.map(\.emojiID),
            names: emojis.map(\.name),
            localPaths: emojis.map(\.localPath),
            thumbPaths: emojis.map(\.thumbPath),
            favoriteStates: emojis.map(\.isFavorite)
        )
        emptyLabel.isHidden = !emojis.isEmpty
        emptyLabel.text = panelState.isLoading ? "Loading emoji..." : (panelState.errorMessage ?? "No emoji")
        guard force || gridSignature != renderedGridSignature else { return }
        renderedGridSignature = gridSignature

        var snapshot = NSDiffableDataSourceSnapshot<Int, EmojiAssetRecord>()
        snapshot.appendSections([0])
        snapshot.appendItems(emojis, toSection: 0)
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    private var selectedSection: Section? {
        if let selectedSectionID,
           let selectedSection = visibleSections.first(where: { $0.id == selectedSectionID }) {
            return selectedSection
        }
        return visibleSections.first
    }

    private struct Section {
        let id: ID
        let title: String
        let emojis: [EmojiAssetRecord]

        enum ID: Hashable {
            case recent
            case favorites
            case package(String)

            var accessibilitySuffix: String {
                switch self {
                case .recent:
                    return "recent"
                case .favorites:
                    return "favorites"
                case let .package(packageID):
                    return "package.\(packageID)"
                }
            }
        }
    }

    private struct GridSignature: Equatable {
        let sectionID: Section.ID?
        let emojiIDs: [String]
        let names: [String?]
        let localPaths: [String?]
        let thumbPaths: [String?]
        let favoriteStates: [Bool]
    }

    /// 发布表情面板用户动作。
    private func emit(_ action: ChatEmojiPanelAction) {
        lastAction = action
        sendActions(for: .primaryActionTriggered)
    }
}

extension ChatEmojiPanelView: UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let availableWidth = collectionView.bounds.width - 24 - 8 * 3
        let itemWidth = floor(availableWidth / 4)
        return CGSize(width: itemWidth, height: 74)
    }
}

/// 表情网格单元格。
@MainActor
private final class ChatEmojiItemCell: UICollectionViewCell {
    var onSelect: ((EmojiAssetRecord) -> Void)?
    var onFavoriteToggle: ((EmojiAssetRecord, Bool) -> Void)?

    private let button = UIButton(type: .system)
    private let favoriteButton = UIButton(type: .system)
    private var emoji: EmojiAssetRecord?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        emoji = nil
        onSelect = nil
        onFavoriteToggle = nil
        button.accessibilityIdentifier = nil
        favoriteButton.accessibilityIdentifier = nil
    }

    func configure(emoji: EmojiAssetRecord) {
        self.emoji = emoji

        var buttonConfiguration = UIButton.Configuration.plain()
        buttonConfiguration.imagePlacement = .top
        buttonConfiguration.imagePadding = 4
        buttonConfiguration.title = emoji.name ?? "Emoji"
        buttonConfiguration.image = emoji.thumbPath
            .flatMap(UIImage.init(contentsOfFile:))
            ?? emoji.localPath.flatMap(UIImage.init(contentsOfFile:))
            ?? UIImage(systemName: "face.smiling")
        buttonConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        buttonConfiguration.baseForegroundColor = .label
        button.configuration = buttonConfiguration
        button.accessibilityIdentifier = "chat.emojiItem.\(emoji.emojiID)"

        var favoriteConfiguration = UIButton.Configuration.plain()
        favoriteConfiguration.image = UIImage(systemName: emoji.isFavorite ? "star.fill" : "star")
        favoriteConfiguration.baseForegroundColor = emoji.isFavorite ? .systemYellow : .tertiaryLabel
        favoriteConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        favoriteButton.configuration = favoriteConfiguration
        favoriteButton.accessibilityIdentifier = "chat.emojiFavorite.\(emoji.emojiID)"
    }

    private func configureView() {
        button.translatesAutoresizingMaskIntoConstraints = false
        favoriteButton.translatesAutoresizingMaskIntoConstraints = false

        button.addAction(UIAction { [weak self] _ in
            guard let self, let emoji = self.emoji else { return }
            self.onSelect?(emoji)
        }, for: .touchUpInside)
        favoriteButton.addAction(UIAction { [weak self] _ in
            guard let self, let emoji = self.emoji else { return }
            self.onFavoriteToggle?(emoji, !emoji.isFavorite)
        }, for: .touchUpInside)

        contentView.addSubview(button)
        contentView.addSubview(favoriteButton)

        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: contentView.topAnchor),
            button.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            favoriteButton.topAnchor.constraint(equalTo: contentView.topAnchor),
            favoriteButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            favoriteButton.widthAnchor.constraint(equalToConstant: 28),
            favoriteButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }
}
