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
    private let segmentedControl = UISegmentedControl()
    private let scrollView = UIScrollView()
    private let contentStackView = UIStackView()
    private let emptyLabel = UILabel()

    private var state = ChatEmojiPanelState.empty
    private var visibleSections: [Section] = []

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
        rebuildSegmentedControl()
        rebuildGrid()
    }

    private func configureView() {
        clipsToBounds = true
        accessibilityIdentifier = "chat.emojiInputPanel"

        blurView.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

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

        segmentedControl.addTarget(self, action: #selector(selectedSectionChanged), for: .valueChanged)

        addSubview(blurView)
        addSubview(segmentedControl)
        addSubview(scrollView)
        scrollView.addSubview(contentStackView)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            segmentedControl.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            segmentedControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            segmentedControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
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
            Section(title: "最近", emojis: state.recentEmojis),
            Section(title: "收藏", emojis: state.favoriteEmojis)
        ] + state.packages.map { package in
            Section(
                title: package.title,
                emojis: state.packageEmojisByPackageID[package.packageID] ?? []
            )
        }
    }

    private func rebuildSegmentedControl() {
        let selectedTitle = selectedSection?.title
        segmentedControl.removeAllSegments()
        for (index, section) in visibleSections.enumerated() {
            segmentedControl.insertSegment(withTitle: section.title, at: index, animated: false)
        }
        segmentedControl.isHidden = visibleSections.isEmpty
        segmentedControl.selectedSegmentIndex = max(0, visibleSections.firstIndex { $0.title == selectedTitle } ?? 0)
    }

    private func rebuildGrid() {
        contentStackView.arrangedSubviews.forEach { view in
            contentStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let emojis = selectedSection?.emojis ?? []
        emptyLabel.isHidden = !emojis.isEmpty
        emptyLabel.text = state.isLoading ? "Loading emoji..." : (state.errorMessage ?? "No emoji")
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

    @objc private func selectedSectionChanged() {
        rebuildGrid()
    }

    private var selectedSection: Section? {
        guard visibleSections.indices.contains(segmentedControl.selectedSegmentIndex) else {
            return visibleSections.first
        }
        return visibleSections[segmentedControl.selectedSegmentIndex]
    }

    private struct Section {
        let title: String
        let emojis: [EmojiAssetRecord]
    }
}
