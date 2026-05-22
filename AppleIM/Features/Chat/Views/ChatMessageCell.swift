//
//  ChatMessageCell.swift
//  AppleIM
//

import UIKit

/// 聊天消息单元格
@MainActor
final class ChatMessageCell: UICollectionViewCell {
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
        accessibilityIdentifier = nil
        accessibilityLabel = nil
        (contentView.subviews.first as? ChatMessageCellContentView)?.reset()
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        guard let configuration = contentConfiguration as? ChatMessageCellContentConfiguration else {
            return
        }
        contentConfiguration = configuration.updated(for: state)
    }

    func configure(row: ChatMessageRowState, actions: ChatMessageCellActions) {
        let configuration = ChatMessageCellContentConfiguration(row: row, actions: actions)
        contentConfiguration = configuration
        applyAccessibility(from: configuration)
    }

    private func configureView() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
    }

    private func applyAccessibility(from configuration: UIContentConfiguration?) {
        guard let configuration = configuration as? ChatMessageCellContentConfiguration else {
            accessibilityIdentifier = nil
            accessibilityLabel = nil
            return
        }

        accessibilityIdentifier = "chat.messageCell.\(configuration.row.id.rawValue)"
        accessibilityLabel = ChatMessageCellContentConfiguration.accessibilityLabel(for: configuration.row)
    }

    /// 语言切换时重新应用当前配置，让消息内容、元数据和辅助文案原地刷新。
    func applyLanguageChange(_ context: AppLanguageContext) {
        applyLanguageSemanticContentAttribute(context.semanticContentAttribute)
        guard let configuration = contentConfiguration as? ChatMessageCellContentConfiguration else {
            return
        }
        contentConfiguration = nil
        contentConfiguration = configuration
        applyAccessibility(from: configuration)
    }
}
