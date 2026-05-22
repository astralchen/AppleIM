//
//  EmojiMessageContentView.swift
//  AppleIM
//

import UIKit

/// 表情消息内容视图
@MainActor
final class EmojiMessageContentView: UIView, ChatMessageContentView {
    private let imageView = UIImageView()
    private let fallbackLabel = UILabel()

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
        guard case let .emoji(emoji) = row.content else { return }

        let localImagePath = emoji.thumbPath ?? emoji.localPath
        let image = localImagePath.flatMap(UIImage.init(contentsOfFile:))
        imageView.image = image
        imageView.isHidden = image == nil
        fallbackLabel.isHidden = image != nil
        fallbackLabel.text = emoji.name ?? "Emoji"
        fallbackLabel.textColor = style.textColor
        fallbackLabel.backgroundColor = style.tintColor.withAlphaComponent(row.isOutgoing ? 0.18 : 0.10)
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8

        fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
        fallbackLabel.font = .preferredFont(forTextStyle: .subheadline)
        fallbackLabel.adjustsFontForContentSizeCategory = true
        fallbackLabel.textAlignment = .center
        fallbackLabel.numberOfLines = 2
        fallbackLabel.layer.cornerRadius = 8
        fallbackLabel.layer.masksToBounds = true

        addSubview(imageView)
        addSubview(fallbackLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 96),
            imageView.heightAnchor.constraint(equalToConstant: 96),

            fallbackLabel.topAnchor.constraint(equalTo: topAnchor),
            fallbackLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            fallbackLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            fallbackLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            fallbackLabel.widthAnchor.constraint(equalToConstant: 96),
            fallbackLabel.heightAnchor.constraint(equalToConstant: 96)
        ])
    }
}
