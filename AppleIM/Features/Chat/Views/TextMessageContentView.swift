//
//  TextMessageContentView.swift
//  AppleIM
//

import UIKit

/// 文本和撤回消息内容视图
@MainActor
final class TextMessageContentView: UIView, ChatMessageContentView {
    private let messageLabel = UILabel()

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
        messageLabel.textColor = style.textColor
        messageLabel.attributedText = ChatMentionTextStyling.attributedText(
            for: Self.text(for: row.content),
            baseColor: style.textColor,
            mentionColor: .systemBlue,
            font: messageLabel.font
        )
    }

    private static func text(for content: ChatMessageRowContent) -> String {
        switch content {
        case let .text(text):
            return text
        case let .revoked(content):
            return content.noticeText
        case .image:
            return "Image"
        case let .voice(voice):
            return "Voice \(ChatMessageRowContent.durationText(milliseconds: voice.durationMilliseconds))"
        case let .video(video):
            return "Video \(ChatMessageRowContent.durationText(milliseconds: video.durationMilliseconds))"
        case let .file(file):
            return file.fileName
        case let .emoji(emoji):
            return emoji.name ?? "Emoji"
        }
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0

        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: topAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
