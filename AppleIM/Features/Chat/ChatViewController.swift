//
//  ChatViewController.swift
//  AppleIM
//

import Combine
import UIKit

private let chatSection = "messages"

@MainActor
final class ChatViewController: UIViewController {
    private let viewModel: ChatViewModel
    private var cancellables = Set<AnyCancellable>()
    private var dataSource: UICollectionViewDiffableDataSource<String, String>?
    private var rowsByID: [String: ChatMessageRowState] = [:]

    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: makeLayout()
    )
    private let emptyLabel = UILabel()
    private let inputContainerView = UIView()
    private let inputStackView = UIStackView()
    private let textField = UITextField()
    private let sendButton = UIButton(type: .system)

    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
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
        viewModel.load()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.cancel()
        viewModel.flushDraft(textField.text ?? "")
    }

    private func configureView() {
        view.backgroundColor = .systemGroupedBackground

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.delegate = self

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "No messages yet"
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true

        inputContainerView.translatesAutoresizingMaskIntoConstraints = false
        inputContainerView.backgroundColor = .secondarySystemGroupedBackground
        inputContainerView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 10,
            leading: 16,
            bottom: 10,
            trailing: 16
        )

        inputStackView.translatesAutoresizingMaskIntoConstraints = false
        inputStackView.axis = .horizontal
        inputStackView.alignment = .center
        inputStackView.spacing = 12
        inputStackView.distribution = .fill

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.borderStyle = .roundedRect
        textField.placeholder = "Message"
        textField.returnKeyType = .send
        textField.delegate = self
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.addTarget(self, action: #selector(textFieldEditingChanged), for: .editingChanged)

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        var sendButtonConfiguration = UIButton.Configuration.plain()
        sendButtonConfiguration.title = "Send"
        sendButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(
            top: 8,
            leading: 10,
            bottom: 8,
            trailing: 10
        )
        sendButtonConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .preferredFont(forTextStyle: .headline)
            return attributes
        }
        sendButton.configuration = sendButtonConfiguration
        sendButton.setContentHuggingPriority(.required, for: .horizontal)
        sendButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        sendButton.addTarget(self, action: #selector(sendButtonTapped), for: .touchUpInside)

        view.addSubview(collectionView)
        view.addSubview(emptyLabel)
        view.addSubview(inputContainerView)
        inputContainerView.addSubview(inputStackView)
        inputStackView.addArrangedSubview(textField)
        inputStackView.addArrangedSubview(sendButton)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: inputContainerView.topAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),

            inputContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputContainerView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            inputStackView.leadingAnchor.constraint(equalTo: inputContainerView.layoutMarginsGuide.leadingAnchor),
            inputStackView.trailingAnchor.constraint(equalTo: inputContainerView.layoutMarginsGuide.trailingAnchor),
            inputStackView.topAnchor.constraint(equalTo: inputContainerView.layoutMarginsGuide.topAnchor),
            inputStackView.bottomAnchor.constraint(equalTo: inputContainerView.layoutMarginsGuide.bottomAnchor),

            textField.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            sendButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            sendButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 64)
        ])
    }

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<ChatMessageCell, String> { [weak self] cell, _, rowID in
            guard let row = self?.rowsByID[rowID] else { return }
            cell.configure(row: row) { [weak self] messageID in
                self?.viewModel.resend(messageID: messageID)
            }
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

        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        snapshot.appendSections([chatSection])
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    private func bindViewModel() {
        viewModel.statePublisher
            .sink { [weak self] state in
                self?.render(state)
            }
            .store(in: &cancellables)
    }

    private func render(_ state: ChatViewState) {
        title = state.title
        emptyLabel.text = state.emptyMessage
        emptyLabel.isHidden = !state.isEmpty || state.phase == .loading
        rowsByID = Dictionary(uniqueKeysWithValues: state.rows.map { ($0.diffIdentifier, $0) })

        if !textField.isFirstResponder, textField.text != state.draftText {
            textField.text = state.draftText
        }

        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        snapshot.appendSections([chatSection])
        snapshot.appendItems(state.rows.map(\.diffIdentifier), toSection: chatSection)
        dataSource?.apply(snapshot, animatingDifferences: true)

        guard !state.rows.isEmpty else { return }
        let lastIndexPath = IndexPath(item: state.rows.count - 1, section: 0)
        collectionView.scrollToItem(at: lastIndexPath, at: .bottom, animated: true)
    }

    private func makeLayout() -> UICollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(72)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)

        return UICollectionViewCompositionalLayout(section: section)
    }

    @objc private func sendButtonTapped() {
        sendCurrentText()
    }

    @objc private func textFieldEditingChanged() {
        viewModel.saveDraft(textField.text ?? "")
    }

    private func sendCurrentText() {
        let text = textField.text ?? ""
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        textField.text = nil
        viewModel.saveDraft("")
        viewModel.sendText(trimmedText)
    }
}

extension ChatViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendCurrentText()
        return false
    }
}

extension ChatViewController: UICollectionViewDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard
            let rowID = dataSource?.itemIdentifier(for: indexPath),
            let row = rowsByID[rowID],
            row.canDelete || row.canRevoke
        else {
            return nil
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            var actions: [UIAction] = []

            if row.canRevoke {
                actions.append(
                    UIAction(title: "Revoke", image: UIImage(systemName: "arrow.uturn.backward")) { _ in
                        self?.viewModel.revoke(messageID: row.id)
                    }
                )
            }

            if row.canDelete {
                actions.append(
                    UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                        self?.viewModel.delete(messageID: row.id)
                    }
                )
            }

            return UIMenu(children: actions)
        }
    }
}

private extension ChatMessageRowState {
    var diffIdentifier: String {
        [
            id.rawValue,
            text,
            statusText ?? "",
            canRetry ? "retry" : "no-retry",
            canRevoke ? "revoke" : "no-revoke",
            isRevoked ? "revoked" : "normal"
        ].joined(separator: "|")
    }
}

private final class ChatMessageCell: UICollectionViewCell {
    private let bubbleView = UIView()
    private let stackView = UIStackView()
    private let messageLabel = UILabel()
    private let metadataLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    private var retryMessageID: MessageID?
    private var onRetry: ((MessageID) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    func configure(row: ChatMessageRowState, onRetry: @escaping (MessageID) -> Void) {
        retryMessageID = row.id
        self.onRetry = onRetry
        messageLabel.text = row.text
        metadataLabel.text = [row.timeText, row.statusText].compactMap { $0 }.joined(separator: " · ")
        bubbleView.backgroundColor = row.isRevoked ? .tertiarySystemGroupedBackground : (row.isOutgoing ? .systemBlue : .secondarySystemGroupedBackground)
        messageLabel.textColor = row.isOutgoing && !row.isRevoked ? .white : .label
        metadataLabel.textColor = row.isOutgoing && !row.isRevoked ? .white.withAlphaComponent(0.75) : .secondaryLabel
        retryButton.isHidden = !row.canRetry
        retryButton.tintColor = row.isOutgoing ? .white : .systemBlue

        leadingConstraint?.isActive = !row.isOutgoing
        trailingConstraint?.isActive = row.isOutgoing
    }

    private func configureView() {
        contentView.backgroundColor = .systemGroupedBackground

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.layer.cornerRadius = 16
        bubbleView.layer.masksToBounds = true

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 4

        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0

        metadataLabel.font = .preferredFont(forTextStyle: .caption2)
        metadataLabel.adjustsFontForContentSizeCategory = true
        metadataLabel.numberOfLines = 1

        retryButton.setTitle("Retry", for: .normal)
        retryButton.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        retryButton.contentHorizontalAlignment = .leading
        retryButton.addTarget(self, action: #selector(retryButtonTapped), for: .touchUpInside)

        contentView.addSubview(bubbleView)
        bubbleView.addSubview(stackView)
        stackView.addArrangedSubview(messageLabel)
        stackView.addArrangedSubview(metadataLabel)
        stackView.addArrangedSubview(retryButton)

        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.72),

            stackView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            stackView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            stackView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8)
        ])
    }

    @objc private func retryButtonTapped() {
        guard let retryMessageID else { return }
        onRetry?(retryMessageID)
    }
}
