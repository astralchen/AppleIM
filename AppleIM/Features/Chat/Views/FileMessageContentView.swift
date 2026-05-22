//
//  FileMessageContentView.swift
//  AppleIM
//

import UIKit

/// 文件消息内容视图
@MainActor
final class FileMessageContentView: UIView, ChatMessageContentView {
    private let containerView = UIView()
    private let iconContainerView = UIView()
    private let iconView = UIImageView(image: UIImage(systemName: "doc.fill"))
    private let textStackView = UIStackView()
    private let fileNameLabel = UILabel()
    private let fileSizeLabel = UILabel()

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
        guard case let .file(file) = row.content else { return }

        fileNameLabel.text = file.fileName
        fileNameLabel.textColor = style.textColor
        fileSizeLabel.text = Self.fileSizeText(bytes: file.sizeBytes)
        fileSizeLabel.textColor = style.secondaryTextColor
        iconView.tintColor = style.tintColor
        iconContainerView.backgroundColor = style.tintColor.withAlphaComponent(row.isOutgoing ? 0.22 : 0.14)
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .clear

        iconContainerView.translatesAutoresizingMaskIntoConstraints = false
        iconContainerView.layer.cornerRadius = 10
        iconContainerView.layer.masksToBounds = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        textStackView.translatesAutoresizingMaskIntoConstraints = false
        textStackView.axis = .vertical
        textStackView.spacing = 2

        fileNameLabel.font = .preferredFont(forTextStyle: .subheadline)
        fileNameLabel.adjustsFontForContentSizeCategory = true
        fileNameLabel.numberOfLines = 2

        fileSizeLabel.font = .preferredFont(forTextStyle: .caption1)
        fileSizeLabel.adjustsFontForContentSizeCategory = true
        fileSizeLabel.numberOfLines = 1

        addSubview(containerView)
        containerView.addSubview(iconContainerView)
        iconContainerView.addSubview(iconView)
        containerView.addSubview(textStackView)
        textStackView.addArrangedSubview(fileNameLabel)
        textStackView.addArrangedSubview(fileSizeLabel)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconContainerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            iconContainerView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconContainerView.widthAnchor.constraint(equalToConstant: 38),
            iconContainerView.heightAnchor.constraint(equalToConstant: 38),

            iconView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            textStackView.topAnchor.constraint(equalTo: containerView.topAnchor),
            textStackView.leadingAnchor.constraint(equalTo: iconContainerView.trailingAnchor, constant: 10),
            textStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            textStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }

    private static func fileSizeText(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
