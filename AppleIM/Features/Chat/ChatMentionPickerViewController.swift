//
//  ChatMentionPickerViewController.swift
//  AppleIM
//
//  群聊 @ 提醒成员选择器。

import UIKit
import CoreFoundation

/// @ 提醒选择器事件回调。
@MainActor
protocol ChatMentionPickerViewControllerDelegate: AnyObject {
    /// 单选一个成员或 @ 所有人。
    func mentionPicker(_ picker: ChatMentionPickerViewController, didSelect option: ChatMentionOptionState)
    /// 多选完成，按用户选择顺序返回成员。
    func mentionPicker(_ picker: ChatMentionPickerViewController, didFinishSelecting options: [ChatMentionOptionState])
    /// 用户主动关闭选择器。
    func mentionPickerDidCancel(_ picker: ChatMentionPickerViewController)
}

/// Apple 风格半屏 @ 提醒成员选择器。
@MainActor
final class ChatMentionPickerViewController: UIViewController {
    /// 列表分组。
    private nonisolated enum Section: Hashable, Sendable {
        case frequent
        case alphabet(String)

        var title: String {
            switch self {
            case .frequent:
                "最常提醒"
            case .alphabet(let title):
                title
            }
        }

        var indexTitle: String? {
            switch self {
            case .frequent:
                nil
            case .alphabet(let title):
                title
            }
        }
    }

    private enum SelectionMode {
        case single
        case multiple
    }

    private var allOptions: [ChatMentionOptionState]
    private var filteredOptions: [ChatMentionOptionState]
    private var orderedSections: [Section] = []
    private var itemIDsBySection: [Section: [ContactID]] = [:]
    private var optionByItemID: [ContactID: ChatMentionOptionState] = [:]
    private var optionByContactID: [ContactID: ChatMentionOptionState] = [:]
    private var selectionMode: SelectionMode = .single
    private var selectedContactIDs: [ContactID] = []

    weak var delegate: ChatMentionPickerViewControllerDelegate?

    private let grabberView = UIView()
    private let titleLabel = UILabel()
    private let leadingButton = UIButton(type: .system)
    private let trailingButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)
    private let searchField = UISearchTextField()
    private let indexStackView = UIStackView()
    private let collectionView: UICollectionView
    private var dataSource: UICollectionViewDiffableDataSource<Section, ContactID>?

    init(options: [ChatMentionOptionState]) {
        self.allOptions = options
        self.filteredOptions = options
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: Self.makeLayout())
        super.init(nibName: nil, bundle: nil)
        rebuildSnapshotState()
    }

    required init?(coder: NSCoder) {
        fatalError("Storyboard initialization is not supported.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        configureDataSource()
        renderChrome()
        applySnapshot(animatingDifferences: false)
    }

    /// 外部状态刷新时同步候选项。
    func update(options: [ChatMentionOptionState]) {
        allOptions = options
        filteredOptions = filter(options: options, query: searchField.text ?? "")
        rebuildSnapshotState()
        applySnapshot(animatingDifferences: true)
    }

    private func configureView() {
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "chat.mentionPicker.sheet"
        if #available(iOS 15.0, *) {
            view.layer.cornerCurve = .continuous
        }

        grabberView.translatesAutoresizingMaskIntoConstraints = false
        grabberView.backgroundColor = .systemGray3
        grabberView.layer.cornerRadius = 2.5
        grabberView.isAccessibilityElement = true
        grabberView.accessibilityIdentifier = "chat.mentionPicker.grabber"
        grabberView.accessibilityLabel = "下滑关闭"

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "选择提醒的人"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true

        leadingButton.translatesAutoresizingMaskIntoConstraints = false
        leadingButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        leadingButton.isAccessibilityElement = true
        leadingButton.accessibilityIdentifier = "chat.mentionPicker.cancelButton"
        leadingButton.addTarget(self, action: #selector(leadingButtonTapped), for: .touchUpInside)

        trailingButton.translatesAutoresizingMaskIntoConstraints = false
        trailingButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        trailingButton.isAccessibilityElement = true
        trailingButton.accessibilityIdentifier = "chat.mentionPicker.multiButton"
        trailingButton.addAction(UIAction { [weak self] _ in
            self?.enterMultipleSelectionMode()
        }, for: .touchUpInside)
        let trailingTapGesture = UITapGestureRecognizer(target: self, action: #selector(trailingButtonTapped))
        trailingTapGesture.cancelsTouchesInView = false
        trailingButton.addGestureRecognizer(trailingTapGesture)

        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        doneButton.isAccessibilityElement = true
        doneButton.accessibilityIdentifier = "chat.mentionPicker.doneButton"
        doneButton.addTarget(self, action: #selector(doneButtonTapped), for: .touchUpInside)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = "搜索"
        searchField.clearButtonMode = .whileEditing
        searchField.backgroundColor = .secondarySystemBackground
        searchField.accessibilityIdentifier = "chat.mentionPicker.searchField"
        searchField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .onDrag
        collectionView.delegate = self

        indexStackView.translatesAutoresizingMaskIntoConstraints = false
        indexStackView.axis = .vertical
        indexStackView.alignment = .center
        indexStackView.distribution = .equalSpacing
        indexStackView.spacing = 2
        indexStackView.accessibilityIdentifier = "chat.mentionPicker.sectionIndex"

        [grabberView, leadingButton, titleLabel, trailingButton, doneButton, searchField, collectionView, indexStackView].forEach(view.addSubview)

        NSLayoutConstraint.activate([
            grabberView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            grabberView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grabberView.widthAnchor.constraint(equalToConstant: 40),
            grabberView.heightAnchor.constraint(equalToConstant: 5),

            leadingButton.topAnchor.constraint(equalTo: grabberView.bottomAnchor, constant: 10),
            leadingButton.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            leadingButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),
            leadingButton.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.centerYAnchor.constraint(equalTo: leadingButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingButton.trailingAnchor, constant: 8),

            trailingButton.centerYAnchor.constraint(equalTo: leadingButton.centerYAnchor),
            trailingButton.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            trailingButton.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            trailingButton.heightAnchor.constraint(equalToConstant: 36),

            doneButton.centerYAnchor.constraint(equalTo: leadingButton.centerYAnchor),
            doneButton.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            doneButton.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            doneButton.heightAnchor.constraint(equalToConstant: 36),

            searchField.topAnchor.constraint(equalTo: leadingButton.bottomAnchor, constant: 18),
            searchField.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 44),

            collectionView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 14),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            indexStackView.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
            indexStackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            indexStackView.widthAnchor.constraint(equalToConstant: 18)
        ])
        renderSectionIndex()
    }

    private static func makeLayout() -> UICollectionViewLayout {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.headerMode = .supplementary
        configuration.showsSeparators = true
        configuration.backgroundColor = .systemBackground
        return UICollectionViewCompositionalLayout.list(using: configuration)
    }

    private func configureDataSource() {
        let memberRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, ContactID> { [weak self] cell, indexPath, itemID in
            self?.memberCellRegistrationHandler(cell: cell, indexPath: indexPath, itemID: itemID)
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<MentionSectionHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            guard let section = self?.orderedSections[safe: indexPath.section] else { return }
            header.configure(title: section.title)
        }

        let dataSource = UICollectionViewDiffableDataSource<Section, ContactID>(
            collectionView: collectionView
        ) { collectionView, indexPath, itemID in
            collectionView.dequeueConfiguredReusableCell(
                using: memberRegistration,
                for: indexPath,
                item: itemID
            )
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(
                using: headerRegistration,
                for: indexPath
            )
        }
        self.dataSource = dataSource
    }

    /// 配置成员 cell。
    private func memberCellRegistrationHandler(cell: UICollectionViewListCell, indexPath: IndexPath, itemID: ContactID) {
        guard let option = optionByItemID[itemID] else { return }
        let contactID = Self.contactID(for: option)
        let showsSelectionControl = selectionMode == .multiple && !option.mentionsAll
        let isSelected = selectedContactIDs.contains(contactID)
        cell.contentConfiguration = memberConfiguration(for: cell, option: option)
        cell.accessories = showsSelectionControl
            ? [.customView(configuration: Self.selectionAccessoryConfiguration(isSelected: isSelected))]
            : []
        cell.backgroundConfiguration = .listPlainCell()
        cell.accessibilityIdentifier = accessibilityIdentifier(for: option, showsSelectionControl: showsSelectionControl)
        cell.isAccessibilityElement = true
        cell.accessibilityLabel = option.mentionsAll ? "@所有人" : option.displayName
        cell.accessibilityValue = showsSelectionControl ? (isSelected ? "已选择" : "未选择") : nil
    }

    /// 构造成员行内容配置。
    private func memberConfiguration(
        for cell: UICollectionViewListCell,
        option: ChatMentionOptionState
    ) -> UIListContentConfiguration {
        var configuration = cell.defaultContentConfiguration()
        configuration.text = option.mentionsAll ? "@所有人" : option.displayName
        configuration.secondaryText = option.mentionsAll ? "提醒全部群成员" : "昵称：\(option.displayName)"
        configuration.image = Self.avatarImage(for: option)
        configuration.imageProperties.maximumSize = CGSize(width: 44, height: 44)
        configuration.imageProperties.cornerRadius = 10
        configuration.textProperties.font = .preferredFont(forTextStyle: .headline)
        configuration.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
        configuration.secondaryTextProperties.color = .secondaryLabel
        configuration.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 16)
        return configuration
    }

    /// 构造多选圆形控件 accessory。
    private static func selectionAccessoryConfiguration(isSelected: Bool) -> UICellAccessory.CustomViewConfiguration {
        let button = UIButton(type: .system)
        button.frame = CGRect(origin: .zero, size: CGSize(width: 28, height: 28))
        button.configuration = selectionButtonConfiguration(isSelected: isSelected)
        button.isAccessibilityElement = false
        button.isUserInteractionEnabled = false
        return UICellAccessory.CustomViewConfiguration(
            customView: button,
            placement: .leading(displayed: .always)
        )
    }

    private func renderChrome() {
        switch selectionMode {
        case .single:
            grabberView.isHidden = false
            leadingButton.isHidden = true
            leadingButton.configuration = nil
            doneButton.isHidden = true
            doneButton.isUserInteractionEnabled = false
            trailingButton.configuration = Self.navigationButtonConfiguration(title: "多选", color: .label)
            trailingButton.accessibilityLabel = "多选"
            trailingButton.isHidden = false
            trailingButton.isEnabled = true
            trailingButton.isUserInteractionEnabled = true
            trailingButton.accessibilityTraits = [.button]
            trailingButton.accessibilityIdentifier = "chat.mentionPicker.multiButton"
        case .multiple:
            grabberView.isHidden = false
            leadingButton.isHidden = false
            leadingButton.configuration = Self.navigationButtonConfiguration(title: "取消", color: .label)
            leadingButton.accessibilityLabel = "取消"
            leadingButton.accessibilityIdentifier = "chat.mentionPicker.cancelButton"
            trailingButton.isHidden = true
            trailingButton.isUserInteractionEnabled = false
            doneButton.isHidden = false
            doneButton.configuration = Self.navigationButtonConfiguration(
                title: "完成",
                color: selectedContactIDs.isEmpty ? .tertiaryLabel : .systemBlue
            )
            doneButton.accessibilityLabel = "完成"
            doneButton.isEnabled = !selectedContactIDs.isEmpty
            doneButton.isUserInteractionEnabled = true
            doneButton.accessibilityTraits = selectedContactIDs.isEmpty ? [.button, .notEnabled] : [.button]
            doneButton.accessibilityIdentifier = "chat.mentionPicker.doneButton"
        }
    }

    private static func navigationButtonConfiguration(title: String, color: UIColor) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseForegroundColor = color
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        return configuration
    }

    @objc private func leadingButtonTapped() {
        switch selectionMode {
        case .single:
            delegate?.mentionPickerDidCancel(self)
            dismiss(animated: true)
        case .multiple:
            selectionMode = .single
            selectedContactIDs = []
            rebuildSnapshotState()
            renderChrome()
            applySnapshot(animatingDifferences: false)
        }
    }

    @objc private func trailingButtonTapped() {
        enterMultipleSelectionMode()
    }

    private func enterMultipleSelectionMode() {
        guard selectionMode == .single else { return }
        selectionMode = .multiple
        selectedContactIDs = []
        rebuildSnapshotState()
        renderChrome()
        applySnapshot(animatingDifferences: false)
    }

    @objc private func doneButtonTapped() {
        let selectedOptions = selectedContactIDs.compactMap { optionByContactID[$0] }
        guard !selectedOptions.isEmpty else { return }
        delegate?.mentionPicker(self, didFinishSelecting: selectedOptions)
        dismiss(animated: true)
    }

    @objc private func searchTextChanged() {
        filteredOptions = filter(options: allOptions, query: searchField.text ?? "")
        selectedContactIDs = selectedContactIDs.filter { selectedID in
            filteredOptions.contains { Self.contactID(for: $0) == selectedID }
        }
        rebuildSnapshotState()
        renderChrome()
        applySnapshot(animatingDifferences: true)
    }

    private func filter(options: [ChatMentionOptionState], query: String) -> [ChatMentionOptionState] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return options }
        return options.filter { option in
            option.displayName.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    private func rebuildSnapshotState() {
        let visibleOptions = selectionMode == .multiple
            ? filteredOptions.filter { !$0.mentionsAll }
            : filteredOptions
        let frequentOptions = Array(visibleOptions.filter { !$0.mentionsAll }.prefix(2))

        var rebuiltSections: [Section] = []
        var rebuiltItemIDsBySection: [Section: [ContactID]] = [:]
        var rebuiltOptionByItemID: [ContactID: ChatMentionOptionState] = [:]
        var rebuiltOptionByContactID: [ContactID: ChatMentionOptionState] = [:]

        func append(section: Section, options: [ChatMentionOptionState]) {
            guard !options.isEmpty else { return }
            rebuiltSections.append(section)
            let itemIDs = options.enumerated().map { index, option in
                let itemID = Self.itemID(for: option, in: section, index: index)
                rebuiltOptionByItemID[itemID] = option
                rebuiltOptionByContactID[Self.contactID(for: option)] = option
                return itemID
            }
            rebuiltItemIDsBySection[section] = itemIDs
        }

        append(section: .frequent, options: frequentOptions)

        let groupedOptions = Dictionary(grouping: visibleOptions) { option in
            option.mentionsAll ? "#" : Self.sectionTitle(for: option.displayName)
        }
        for key in groupedOptions.keys.sorted() {
            guard let options = groupedOptions[key] else { continue }
            append(section: .alphabet(key), options: options)
        }

        orderedSections = rebuiltSections
        itemIDsBySection = rebuiltItemIDsBySection
        optionByItemID = rebuiltOptionByItemID
        optionByContactID = rebuiltOptionByContactID
        renderSectionIndex()
    }

    private func applySnapshot(animatingDifferences: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, ContactID>()
        snapshot.appendSections(orderedSections)
        for section in orderedSections {
            snapshot.appendItems(itemIDsBySection[section, default: []], toSection: section)
        }
        if animatingDifferences {
            dataSource?.apply(snapshot, animatingDifferences: true)
        } else {
            dataSource?.applySnapshotUsingReloadData(snapshot)
        }
    }

    private func renderSectionIndex() {
        indexStackView.arrangedSubviews.forEach { view in
            indexStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let indexedSections = orderedSections.enumerated().compactMap { index, section -> (Int, String)? in
            guard let title = section.indexTitle else { return nil }
            return (index, title)
        }
        indexStackView.isHidden = indexedSections.count <= 1
        for (sectionIndex, title) in indexedSections {
            let button = UIButton(type: .system)
            button.tag = sectionIndex
            button.configuration = Self.sectionIndexButtonConfiguration(title: title)
            button.accessibilityIdentifier = "chat.mentionPicker.sectionIndex.\(title)"
            button.accessibilityLabel = "跳转到\(title)分组"
            button.addTarget(self, action: #selector(sectionIndexTapped(_:)), for: .touchUpInside)
            indexStackView.addArrangedSubview(button)
        }
    }

    private static func sectionIndexButtonConfiguration(title: String) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseForegroundColor = .secondaryLabel
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2)
        return configuration
    }

    @objc private func sectionIndexTapped(_ sender: UIButton) {
        let section = sender.tag
        guard section >= 0,
              section < orderedSections.count,
              let itemID = itemIDsBySection[orderedSections[section]]?.first,
              let itemIndex = dataSource?.indexPath(for: itemID) else {
            return
        }
        collectionView.scrollToItem(at: itemIndex, at: .top, animated: true)
    }

    private static func sectionTitle(for displayName: String) -> String {
        let normalizedName = pinyinText(for: displayName)
        let firstScalar = normalizedName.unicodeScalars.first
        guard let scalar = firstScalar, CharacterSet.alphanumerics.contains(scalar) else {
            return "#"
        }
        return String(Character(scalar)).uppercased()
    }

    /// 中文昵称按拼音首字母分组；英文昵称保持原始首字母。
    private static func pinyinText(for text: String) -> String {
        let mutableText = NSMutableString(string: text)
        CFStringTransform(mutableText, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableText, nil, kCFStringTransformStripCombiningMarks, false)
        return mutableText as String
    }

    private static func contactID(for option: ChatMentionOptionState) -> ContactID {
        ContactID(rawValue: option.id)
    }

    private static func itemID(for option: ChatMentionOptionState, in section: Section, index: Int) -> ContactID {
        ContactID(rawValue: "\(section.title).\(index).\(option.id)")
    }

    private func accessibilityIdentifier(for option: ChatMentionOptionState, showsSelectionControl: Bool) -> String {
        if showsSelectionControl {
            return "chat.mentionSelection.\(option.id)"
        }
        return option.mentionsAll ? "chat.mentionOption.__all__" : "chat.mentionOption.\(option.id)"
    }

    private static func selectionButtonConfiguration(isSelected: Bool) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.image = isSelected ? UIImage(systemName: "checkmark") : nil
        configuration.baseForegroundColor = .white
        configuration.background.backgroundColor = isSelected ? .systemBlue : .clear
        configuration.background.strokeColor = isSelected ? .systemBlue : .systemGray3
        configuration.background.strokeWidth = 1.5
        configuration.background.cornerRadius = 14
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        return configuration
    }

    private static func avatarImage(for option: ChatMentionOptionState) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 44, height: 44))
        return renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 44, height: 44)
            UIColor.secondarySystemGroupedBackground.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 10).fill()

            let text = option.mentionsAll ? "全" : String(option.displayName.prefix(1))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.preferredFont(forTextStyle: .headline),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let size = text.size(withAttributes: attributes)
            let origin = CGPoint(x: (44 - size.width) / 2, y: (44 - size.height) / 2)
            text.draw(at: origin, withAttributes: attributes)
            context.cgContext.setStrokeColor(UIColor.separator.withAlphaComponent(0.35).cgColor)
            context.cgContext.addPath(UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 10).cgPath)
            context.cgContext.strokePath()
        }
    }
}

extension ChatMentionPickerViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let itemID = dataSource?.itemIdentifier(for: indexPath),
              let option = optionByItemID[itemID] else {
            return
        }
        select(option)
    }

    private func select(_ option: ChatMentionOptionState) {
        switch selectionMode {
        case .single:
            delegate?.mentionPicker(self, didSelect: option)
            dismiss(animated: true)
        case .multiple:
            guard !option.mentionsAll else { return }
            let contactID = Self.contactID(for: option)
            if let existingIndex = selectedContactIDs.firstIndex(of: contactID) {
                selectedContactIDs.remove(at: existingIndex)
            } else {
                selectedContactIDs.append(contactID)
            }
            renderChrome()
            applySnapshot(animatingDifferences: false)
        }
    }
}

/// 分组标题。
private final class MentionSectionHeaderView: UICollectionReusableView {
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
        backgroundColor = .systemBackground
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.textColor = .secondaryLabel
        titleLabel.adjustsFontForContentSizeCategory = true
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
