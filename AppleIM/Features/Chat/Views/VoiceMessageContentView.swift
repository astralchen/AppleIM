//
//  VoiceMessageContentView.swift
//  AppleIM
//

import UIKit

/// 语音消息内容视图
@MainActor
final class VoiceMessageContentView: UIView, ChatMessageContentView, UIGestureRecognizerDelegate {
    private let stackView = UIStackView()
    private let voicePlaybackButton = UIButton(type: .system)
    private let waveformView = MessageVoiceWaveformView()
    private let voiceDurationLabel = UILabel()
    private let voiceUnreadDotView = UIView()
    private var row: ChatMessageRowState?
    private var actions = ChatMessageCellActions.empty

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
        self.row = row
        self.actions = actions

        let voice: ChatMessageRowContent.VoiceContent?
        if case let .voice(content) = row.content {
            voice = content
        } else {
            voice = nil
        }

        let isPlaying = voice?.isPlaying == true
        voicePlaybackButton.setImage(UIImage(systemName: isPlaying ? "pause.fill" : "play.fill"), for: .normal)
        voicePlaybackButton.tintColor = style.tintColor
        let accessibilityText = L10n.shared.tr(
            isPlaying ? "chat.voice.stop.accessibility" : "chat.voice.play.accessibility"
        )
        voicePlaybackButton.accessibilityLabel = accessibilityText
        accessibilityLabel = accessibilityText
        waveformView.tintColor = style.tintColor
        waveformView.isPlaying = isPlaying
        waveformView.playbackProgress = voice?.playbackProgress ?? 0
        voiceDurationLabel.text = Self.durationText(for: voice)
        voiceDurationLabel.textColor = style.textColor
        voiceUnreadDotView.isHidden = !(voice?.isUnplayed == true)
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = [.button]
        isUserInteractionEnabled = true

        let bubbleTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(voiceBubbleTapped))
        bubbleTapGestureRecognizer.cancelsTouchesInView = false
        bubbleTapGestureRecognizer.delegate = self
        addGestureRecognizer(bubbleTapGestureRecognizer)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 9

        voicePlaybackButton.translatesAutoresizingMaskIntoConstraints = false
        voicePlaybackButton.addTarget(self, action: #selector(voicePlaybackButtonTapped), for: .touchUpInside)

        waveformView.translatesAutoresizingMaskIntoConstraints = false

        voiceDurationLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        voiceDurationLabel.adjustsFontForContentSizeCategory = true
        voiceDurationLabel.adjustsFontSizeToFitWidth = true
        voiceDurationLabel.minimumScaleFactor = 0.78

        voiceUnreadDotView.translatesAutoresizingMaskIntoConstraints = false
        voiceUnreadDotView.backgroundColor = ChatBridgeDesignSystem.ColorToken.coral
        voiceUnreadDotView.layer.cornerRadius = 3.5
        voiceUnreadDotView.isHidden = true

        stackView.addArrangedSubview(voicePlaybackButton)
        stackView.addArrangedSubview(waveformView)
        stackView.addArrangedSubview(voiceDurationLabel)
        stackView.addArrangedSubview(voiceUnreadDotView)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            voicePlaybackButton.widthAnchor.constraint(equalToConstant: 28),
            voicePlaybackButton.heightAnchor.constraint(equalToConstant: 28),
            waveformView.widthAnchor.constraint(equalToConstant: 70),
            waveformView.heightAnchor.constraint(equalToConstant: 22),
            voiceUnreadDotView.widthAnchor.constraint(equalToConstant: 7),
            voiceUnreadDotView.heightAnchor.constraint(equalToConstant: 7)
        ])
    }

    @objc private func voicePlaybackButtonTapped() {
        playVoiceIfAvailable()
    }

    @objc private func voiceBubbleTapped() {
        playVoiceIfAvailable()
    }

    override func accessibilityActivate() -> Bool {
        guard row != nil else { return false }
        playVoiceIfAvailable()
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view?.isDescendant(of: voicePlaybackButton) != true
    }

    private func playVoiceIfAvailable() {
        guard let row else { return }
        actions.onPlayVoice(row)
    }

    private static func durationText(for voice: ChatMessageRowContent.VoiceContent?) -> String {
        guard let voice else {
            return ChatMessageRowContent.voiceDurationDisplayText(milliseconds: 0)
        }

        let totalText = ChatMessageRowContent.voiceDurationDisplayText(milliseconds: voice.durationMilliseconds)
        guard voice.isPlaying else {
            return totalText
        }

        let elapsedText = ChatMessageRowContent.voiceElapsedDisplayText(
            milliseconds: voice.playbackElapsedMilliseconds
        )
        return "\(elapsedText)/\(totalText)"
    }
}

/// Apple Messages 风格的简易语音波形
@MainActor
private final class MessageVoiceWaveformView: UIView {
    private var playbackProgressValue: Double = 0

    var isPlaying = false {
        didSet {
            setNeedsDisplay()
        }
    }

    var playbackProgress: Double {
        get {
            playbackProgressValue
        }
        set {
            playbackProgressValue = min(1, max(0, newValue))
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }

    override func draw(_ rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }

        let bars = 13
        let spacing: CGFloat = 3
        let barWidth = max(2, (rect.width - CGFloat(bars - 1) * spacing) / CGFloat(bars))
        let drawBars: (CGFloat) -> Void = { alpha in
            for index in 0..<bars {
                let progress = CGFloat(index) / CGFloat(max(bars - 1, 1))
                let wave = 0.28 + 0.72 * abs(sin(progress * .pi * 1.35))
                let barHeight = max(5, rect.height * wave)
                let x = CGFloat(index) * (barWidth + spacing)
                let y = (rect.height - barHeight) / 2
                let path = UIBezierPath(
                    roundedRect: CGRect(x: x, y: y, width: barWidth, height: barHeight),
                    cornerRadius: barWidth / 2
                )
                self.tintColor.withAlphaComponent(alpha).setFill()
                path.fill()
            }
        }

        drawBars(0.34)

        guard isPlaying, playbackProgressValue > 0, let context = UIGraphicsGetCurrentContext() else {
            return
        }

        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 0, width: rect.width * CGFloat(playbackProgressValue), height: rect.height))
        drawBars(0.95)
        context.restoreGState()
    }
}
