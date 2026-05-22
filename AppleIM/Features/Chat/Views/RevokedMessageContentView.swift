//
//  RevokedMessageContentView.swift
//  AppleIM
//

import UIKit

/// 撤回消息内容视图
@MainActor
final class RevokedMessageContentView: UIView, ChatMessageContentView {
    private let stackView = UIStackView()
    private let noticeLabel = UILabel()
    private let reeditButton = UIButton(type: .system)
    private var rowID: MessageID?
    private var editableText: String?
    private var actions: ChatMessageCellActions = .empty

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    func configure(
        row: ChatMessageRowState,
        style: ChatMessageContentStyle,
        actions: ChatMessageCellActions
    ) {
        guard let revoked = row.content.revokedContent else { return }

        rowID = row.id
        editableText = revoked.editableText
        self.actions = actions
        noticeLabel.text = revoked.noticeText
        noticeLabel.textColor = style.textColor

        let showsReedit = revoked.allowsReedit && revoked.editableText != nil
        reeditButton.isHidden = !showsReedit
        reeditButton.isAccessibilityElement = showsReedit
        reeditButton.accessibilityIdentifier = showsReedit ? "chat.revokedReeditButton.\(row.id.rawValue)" : nil
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .firstBaseline
        stackView.spacing = 6

        noticeLabel.font = .preferredFont(forTextStyle: .footnote)
        noticeLabel.adjustsFontForContentSizeCategory = true
        noticeLabel.numberOfLines = 0
        noticeLabel.textAlignment = .center

        reeditButton.setTitle("重新编辑", for: .normal)
        reeditButton.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        reeditButton.titleLabel?.adjustsFontForContentSizeCategory = true
        reeditButton.setContentHuggingPriority(.required, for: .horizontal)
        reeditButton.addTarget(self, action: #selector(reeditButtonTapped), for: .touchUpInside)

        addSubview(stackView)
        stackView.addArrangedSubview(noticeLabel)
        stackView.addArrangedSubview(reeditButton)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @objc private func reeditButtonTapped() {
        guard let rowID, let editableText else { return }
        actions.onReeditRevokedText(rowID, editableText)
    }
}
