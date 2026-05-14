//
//  ChatEmojiPanelView.swift
//  AppleIM
//

import UIKit

/// 聊天表情输入面板。
@MainActor
final class ChatEmojiPanelView: UIView {
    static let panelHeight: CGFloat = 280

    var onEmojiSelected: ((EmojiAssetRecord) -> Void)?
    var onFavoriteToggled: ((EmojiAssetRecord, Bool) -> Void)?

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let sectionButtonStackView = UIStackView()
    private let scrollView = UIScrollView()
    private let contentStackView = UIStackView()
    private let emptyLabel = UILabel()

    private var state = ChatEmojiPanelState.empty
    private var visibleSections: [Section] = []
    private var selectedSectionID: Section.ID?
    private var renderedSectionIDs: [Section.ID] = []
    private var sectionButtonsByID: [Section.ID: UIButton] = [:]
    private var renderedGridSignature: GridSignature?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    func render(_ state: ChatEmojiPanelState) {
        self.state = state
        rebuildSections()
        reconcileSelectedSection()
        rebuildSectionButtons()
        rebuildGrid()
        setNeedsLayout()
        layoutIfNeeded()
    }

    private func configureView() {
        clipsToBounds = true
        accessibilityIdentifier = "chat.emojiInputPanel"

        blurView.translatesAutoresizingMaskIntoConstraints = false
        sectionButtonStackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        sectionButtonStackView.axis = .horizontal
        sectionButtonStackView.alignment = .fill
        sectionButtonStackView.distribution = .fillEqually
        sectionButtonStackView.spacing = 8

        contentStackView.axis = .vertical
        contentStackView.spacing = 10
        contentStackView.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 20, right: 12)
        contentStackView.isLayoutMarginsRelativeArrangement = true

        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .none

        emptyLabel.font = .preferredFont(forTextStyle: .subheadline)
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.text = "No emoji"

        addSubview(blurView)
        addSubview(sectionButtonStackView)
        addSubview(scrollView)
        scrollView.addSubview(contentStackView)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            sectionButtonStackView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            sectionButtonStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            sectionButtonStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            sectionButtonStackView.heightAnchor.constraint(equalToConstant: 32),

            scrollView.topAnchor.constraint(equalTo: sectionButtonStackView.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
        ])
    }

    private func rebuildSections() {
        visibleSections = [
            Section(id: .recent, title: "最近", emojis: state.recentEmojis),
            Section(id: .favorites, title: "收藏", emojis: state.favoriteEmojis)
        ] + state.packages.map { package in
            Section(
                id: .package(package.packageID),
                title: package.title,
                emojis: state.packageEmojisByPackageID[package.packageID] ?? []
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
        emptyLabel.text = state.isLoading ? "Loading emoji..." : (state.errorMessage ?? "No emoji")
        guard force || gridSignature != renderedGridSignature else { return }
        renderedGridSignature = gridSignature

        contentStackView.arrangedSubviews.forEach { view in
            contentStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard !emojis.isEmpty else { return }

        let columns = 4
        var rowStack: UIStackView?
        for (index, emoji) in emojis.enumerated() {
            if index % columns == 0 {
                let stack = UIStackView()
                stack.axis = .horizontal
                stack.alignment = .fill
                stack.distribution = .fillEqually
                stack.spacing = 8
                contentStackView.addArrangedSubview(stack)
                rowStack = stack
            }

            rowStack?.addArrangedSubview(makeEmojiItemView(emoji))
        }

        if let rowStack {
            let remainder = emojis.count % columns
            if remainder > 0 {
                for _ in remainder..<columns {
                    rowStack.addArrangedSubview(UIView())
                }
            }
        }
    }

    private func makeEmojiItemView(_ emoji: EmojiAssetRecord) -> UIView {
        let container = UIView()
        let button = UIButton(type: .system)
        let favoriteButton = UIButton(type: .system)

        container.translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false
        favoriteButton.translatesAutoresizingMaskIntoConstraints = false

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
        button.addAction(UIAction { [weak self] _ in
            self?.onEmojiSelected?(emoji)
        }, for: .touchUpInside)

        var favoriteConfiguration = UIButton.Configuration.plain()
        favoriteConfiguration.image = UIImage(systemName: emoji.isFavorite ? "star.fill" : "star")
        favoriteConfiguration.baseForegroundColor = emoji.isFavorite ? .systemYellow : .tertiaryLabel
        favoriteConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        favoriteButton.configuration = favoriteConfiguration
        favoriteButton.accessibilityIdentifier = "chat.emojiFavorite.\(emoji.emojiID)"
        favoriteButton.addAction(UIAction { [weak self] _ in
            self?.onFavoriteToggled?(emoji, !emoji.isFavorite)
        }, for: .touchUpInside)

        container.addSubview(button)
        container.addSubview(favoriteButton)

        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            button.heightAnchor.constraint(equalToConstant: 74),

            favoriteButton.topAnchor.constraint(equalTo: container.topAnchor),
            favoriteButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            favoriteButton.widthAnchor.constraint(equalToConstant: 28),
            favoriteButton.heightAnchor.constraint(equalToConstant: 28)
        ])

        return container
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
}
