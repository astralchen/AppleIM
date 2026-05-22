//
//  ChatAttachmentPreviewRailView.swift
//  AppleIM
//

import UIKit

/// 待发送附件预览横向轨道。
@MainActor
final class ChatAttachmentPreviewRailView: UIView {
    /// 移除附件回调。
    var onRemoveItem: ((String) -> Void)?

    /// 横向滚动视图。
    private let scrollView = UIScrollView()
    /// 附件预览内容栈。
    private let stackView = UIStackView()
    /// 输入栏内容左右边距，用于让 rail 视觉上铺满整条输入区。
    private let horizontalOverflow: CGFloat = 12

    /// 初始化附件预览轨道。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    /// 从 storyboard/xib 初始化附件预览轨道。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    /// 渲染待发送附件预览。
    func render(_ items: [ChatPendingAttachmentPreviewItem]) {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for item in items {
            let itemView = PendingAttachmentPreviewItemView(item: item)
            itemView.addTarget(self, action: #selector(attachmentPreviewRemoveTriggered(_:)), for: .primaryActionTriggered)
            stackView.addArrangedSubview(itemView)
        }
    }

    /// 修正横向滚动视图的垂直偏移。
    func normalizeVerticalContentOffset() {
        let offset = scrollView.contentOffset
        guard abs(offset.y) > 0.5 else { return }
        scrollView.contentOffset = CGPoint(x: offset.x, y: 0)
    }

    /// 语言切换时刷新当前可见附件项的辅助文案。
    func applyLocalizedText() {
        for itemView in stackView.arrangedSubviews.compactMap({ $0 as? PendingAttachmentPreviewItemView }) {
            itemView.applyLocalizedText()
        }
    }

    /// 配置视图层级。
    private func configure() {
        backgroundColor = .clear
        accessibilityIdentifier = "chat.pendingAttachmentPreview"

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false
        scrollView.contentInsetAdjustmentBehavior = .never

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .top
        stackView.spacing = 8

        addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -horizontalOverflow),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: horizontalOverflow),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            scrollView.heightAnchor.constraint(equalToConstant: 74),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
    }

    /// 处理附件预览项移除动作。
    @objc private func attachmentPreviewRemoveTriggered(_ sender: UIControl) {
        guard let itemView = sender as? PendingAttachmentPreviewItemView else { return }
        onRemoveItem?(itemView.itemID)
    }
}


/// 待发送附件预览项视图
@MainActor
final class PendingAttachmentPreviewItemView: UIControl {
    /// 附件 ID
    fileprivate let itemID: String
    /// 附件缩略图
    private let imageView = UIImageView()
    /// 底部遮罩
    private let overlayView = UIView()
    /// 媒体类型图标
    private let iconView = UIImageView()
    /// 视频时长标签
    private let durationLabel = UILabel()
    /// 加载指示器
    private let spinner = UIActivityIndicatorView(style: .medium)
    /// 移除按钮
    private let removeButton = UIButton(type: .system)

    /// 根据附件预览项初始化视图
    init(item: ChatPendingAttachmentPreviewItem) {
        itemID = item.id
        super.init(frame: .zero)
        configureView()
        configure(item: item)
    }

    /// 从 storyboard/xib 初始化附件预览视图
    required init?(coder: NSCoder) {
        itemID = ""
        super.init(coder: coder)
        configureView()
    }

    /// 应用附件预览内容
    private func configure(item: ChatPendingAttachmentPreviewItem) {
        accessibilityIdentifier = "chat.pendingAttachmentPreviewItem.\(item.id)"
        accessibilityLabel = item.title
        imageView.image = item.image
        iconView.image = UIImage(systemName: item.isVideo ? "play.fill" : "photo.fill")
        durationLabel.text = item.durationText
        durationLabel.isHidden = item.durationText == nil
        removeButton.isEnabled = !item.isLoading
        removeButton.alpha = item.isLoading ? 0.45 : 1

        if item.isLoading {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
    }

    /// 配置预览视图层级、样式和约束
    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.36)
                : UIColor.systemFill.withAlphaComponent(0.14)
        }
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = ChatBridgeDesignSystem.RadiusToken.appleComposerAttachment

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        overlayView.isUserInteractionEnabled = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        durationLabel.textColor = .white
        durationLabel.adjustsFontSizeToFitWidth = true
        durationLabel.minimumScaleFactor = 0.76
        durationLabel.textAlignment = .right

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        spinner.color = .white

        removeButton.translatesAutoresizingMaskIntoConstraints = false
        applyLocalizedText()
        removeButton.accessibilityIdentifier = "chat.removeAttachmentButton.\(itemID)"
        removeButton.configuration = nil
        removeButton.backgroundColor = UIColor.systemGray.withAlphaComponent(0.62)
        removeButton.tintColor = .white
        removeButton.clipsToBounds = true
        removeButton.layer.cornerRadius = 12
        removeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        removeButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 12, weight: .bold),
            forImageIn: .normal
        )
        removeButton.addTarget(self, action: #selector(removeButtonTapped), for: .touchUpInside)

        addSubview(imageView)
        imageView.addSubview(overlayView)
        overlayView.addSubview(iconView)
        overlayView.addSubview(durationLabel)
        imageView.addSubview(spinner)
        addSubview(removeButton)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 74),
            heightAnchor.constraint(equalToConstant: 74),

            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 66),
            imageView.heightAnchor.constraint(equalToConstant: 66),

            overlayView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            overlayView.heightAnchor.constraint(equalToConstant: 22),

            iconView.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 12),
            iconView.heightAnchor.constraint(equalToConstant: 12),

            durationLabel.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -5),
            durationLabel.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor),
            durationLabel.leadingAnchor.constraint(greaterThanOrEqualTo: iconView.trailingAnchor, constant: 4),

            spinner.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),

            removeButton.topAnchor.constraint(equalTo: topAnchor),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 24),
            removeButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    /// 点击移除附件按钮
    @objc private func removeButtonTapped() {
        guard removeButton.isEnabled else { return }
        sendActions(for: .primaryActionTriggered)
    }

    /// 刷新移除按钮本地化辅助文案。
    func applyLocalizedText() {
        removeButton.accessibilityLabel = L10n.shared.tr("chat.attachment.remove.accessibility")
    }
}
