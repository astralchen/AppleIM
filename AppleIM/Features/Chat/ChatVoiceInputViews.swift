//
//  ChatVoiceInputViews.swift
//  AppleIM
//

import UIKit

/// 输入栏通用视觉参数。
@MainActor
enum ChatInputBarStyling {
    /// 默认文本输入背景色。
    static var defaultTextInputTintColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.54)
                : UIColor.white.withAlphaComponent(0.58)
        }
    }
}

/// 输入栏内圆形图标按钮的统一样式。
@MainActor
enum ChatInputBarControlStyling {
    /// 配置圆形图标按钮。
    static func configureCircleButton(
        _ button: UIButton,
        imageName: String,
        foregroundColor: UIColor,
        backgroundColor: UIColor,
        accessibilityLabel: String,
        accessibilityIdentifier: String?
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: imageName)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        configuration.baseForegroundColor = foregroundColor
        configuration.baseBackgroundColor = backgroundColor
        button.configuration = configuration
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityIdentifier = accessibilityIdentifier
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
}

/// 输入栏语音时长文案格式化。
enum ChatInputBarVoiceFormatting {
    /// 格式化录音时长文本。
    static func recordingDurationText(milliseconds: Int) -> String {
        let seconds = max(0, milliseconds / 1_000)
        return "0:\(String(format: "%02d", seconds))"
    }

    /// 格式化语音播放时长文本。
    static func playbackDurationText(
        elapsedMilliseconds: Int,
        durationMilliseconds: Int,
        isPlaying: Bool
    ) -> String {
        let totalText = ChatMessageRowContent.voiceDurationDisplayText(milliseconds: durationMilliseconds)
        guard isPlaying else {
            return "+ \(totalText)"
        }

        let elapsedText = ChatMessageRowContent.voiceElapsedDisplayText(milliseconds: elapsedMilliseconds)
        return "+ \(elapsedText)/\(totalText)"
    }
}

/// 录音中的输入胶囊内容。
@MainActor
final class ChatRecordingCapsuleView: UIView {
    /// 停止录音回调。
    var onStopTapped: (() -> Void)?

    /// 录音状态内容栈。
    private let stackView = UIStackView()
    /// 录音音量电平视图。
    private let levelMeterView = VoiceLevelMeterView()
    /// 录音时长标签。
    private let durationLabel = UILabel()
    /// 录音提示标签。
    private let hintLabel = UILabel()
    /// 录音停止按钮。
    private let stopButton = UIButton(type: .system)

    /// 初始化录音胶囊。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    /// 从 storyboard/xib 初始化录音胶囊。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    /// 渲染录音状态。
    func render(_ state: VoiceRecordingState) {
        guard state.isRecording else {
            levelMeterView.powerLevel = 0
            hintLabel.isHidden = true
            return
        }

        let accentColor: UIColor = .systemRed
        durationLabel.text = ChatInputBarVoiceFormatting.recordingDurationText(milliseconds: state.elapsedMilliseconds)
        durationLabel.textColor = accentColor
        levelMeterView.tintColor = accentColor
        levelMeterView.appendPowerLevel(state.averagePowerLevel)
        hintLabel.text = state.isCanceling ? state.hintText : nil
        hintLabel.textColor = state.isCanceling ? .systemRed : .secondaryLabel
        hintLabel.isHidden = !state.isCanceling
    }

    /// 配置视图层级。
    private func configure() {
        backgroundColor = .clear
        accessibilityIdentifier = "chat.recordingCapsule"
        isOpaque = false
        isUserInteractionEnabled = true

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 14

        levelMeterView.translatesAutoresizingMaskIntoConstraints = false
        levelMeterView.tintColor = .systemRed
        levelMeterView.accessibilityIdentifier = "chat.recordingWaveform"
        levelMeterView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        levelMeterView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        durationLabel.adjustsFontForContentSizeCategory = true
        durationLabel.textColor = .systemRed
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = .preferredFont(forTextStyle: .subheadline)
        hintLabel.adjustsFontForContentSizeCategory = true
        hintLabel.textColor = .secondaryLabel
        hintLabel.numberOfLines = 1
        hintLabel.isHidden = true
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        ChatInputBarControlStyling.configureCircleButton(
            stopButton,
            imageName: "stop.fill",
            foregroundColor: .systemRed,
            backgroundColor: UIColor.systemRed.withAlphaComponent(0.16),
            accessibilityLabel: "Stop Voice Recording",
            accessibilityIdentifier: "chat.voiceStopButton"
        )
        var stopConfiguration = stopButton.configuration
        stopConfiguration?.image = UIImage(
            systemName: "stop.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        )
        stopConfiguration?.contentInsets = .zero
        stopButton.configuration = stopConfiguration
        stopButton.addTarget(self, action: #selector(stopButtonTapped), for: .touchUpInside)

        addSubview(stackView)
        stackView.addArrangedSubview(levelMeterView)
        stackView.addArrangedSubview(durationLabel)
        stackView.addArrangedSubview(hintLabel)
        stackView.addArrangedSubview(stopButton)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            levelMeterView.heightAnchor.constraint(equalToConstant: 24),
            stopButton.widthAnchor.constraint(equalToConstant: 52),
            stopButton.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    /// 点击停止录音。
    @objc private func stopButtonTapped() {
        onStopTapped?()
    }
}

/// 待发送语音预览的输入胶囊内容。
@MainActor
final class ChatVoicePreviewCapsuleView: UIView {
    /// 播放或暂停预览回调。
    var onPlayTapped: (() -> Void)?
    /// 发送预览回调。
    var onSendTapped: (() -> Void)?

    /// 待发送语音预览内容栈。
    private let stackView = UIStackView()
    /// 待发送语音播放按钮。
    private let playButton = UIButton(type: .system)
    /// 待发送语音波形。
    private let waveformView = VoiceLevelMeterView()
    /// 待发送语音时长标签。
    private let durationLabel = UILabel()
    /// 待发送语音发送按钮。
    private let sendButton = UIButton(type: .system)

    /// 初始化语音预览胶囊。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    /// 从 storyboard/xib 初始化语音预览胶囊。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    /// 渲染待发送语音预览。
    func render(
        durationMilliseconds: Int,
        isPlaying: Bool,
        playbackProgress: Double,
        elapsedMilliseconds: Int
    ) {
        durationLabel.text = ChatInputBarVoiceFormatting.playbackDurationText(
            elapsedMilliseconds: elapsedMilliseconds,
            durationMilliseconds: durationMilliseconds,
            isPlaying: isPlaying
        )
        waveformView.playbackProgress = playbackProgress
        ChatInputBarControlStyling.configureCircleButton(
            playButton,
            imageName: isPlaying ? "pause.fill" : "play.fill",
            foregroundColor: .label,
            backgroundColor: UIColor.systemGray5,
            accessibilityLabel: isPlaying ? "Pause Voice Preview" : "Play Voice Preview",
            accessibilityIdentifier: isHidden ? nil : "chat.voicePreviewPlayButton"
        )
    }

    /// 隐藏或恢复内容层辅助标识。
    func setContentHidden(_ isHidden: Bool) {
        accessibilityElementsHidden = isHidden
        isUserInteractionEnabled = !isHidden
        playButton.accessibilityIdentifier = isHidden ? nil : "chat.voicePreviewPlayButton"
        waveformView.accessibilityIdentifier = isHidden ? nil : "chat.voicePreviewWaveform"
        sendButton.accessibilityIdentifier = isHidden ? nil : "chat.voicePreviewSendButton"
    }

    /// 配置视图层级。
    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8

        ChatInputBarControlStyling.configureCircleButton(
            playButton,
            imageName: "play.fill",
            foregroundColor: .label,
            backgroundColor: UIColor.systemGray5,
            accessibilityLabel: "Play Voice Preview",
            accessibilityIdentifier: "chat.voicePreviewPlayButton"
        )
        playButton.addTarget(self, action: #selector(playButtonTapped), for: .touchUpInside)

        waveformView.translatesAutoresizingMaskIntoConstraints = false
        waveformView.accessibilityIdentifier = "chat.voicePreviewWaveform"
        waveformView.tintColor = .systemGray
        waveformView.seedPreviewSamples()
        waveformView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        durationLabel.adjustsFontForContentSizeCategory = true
        durationLabel.textColor = .label
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)

        ChatInputBarControlStyling.configureCircleButton(
            sendButton,
            imageName: "arrow.up",
            foregroundColor: .white,
            backgroundColor: .systemGreen,
            accessibilityLabel: "Send Voice Preview",
            accessibilityIdentifier: "chat.voicePreviewSendButton"
        )
        sendButton.addTarget(self, action: #selector(sendButtonTapped), for: .touchUpInside)

        addSubview(stackView)
        stackView.addArrangedSubview(playButton)
        stackView.addArrangedSubview(waveformView)
        stackView.addArrangedSubview(durationLabel)
        stackView.addArrangedSubview(sendButton)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 34),
            playButton.heightAnchor.constraint(equalToConstant: 34),
            waveformView.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            waveformView.heightAnchor.constraint(equalToConstant: 20),
            sendButton.widthAnchor.constraint(equalToConstant: 42),
            sendButton.heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    /// 点击播放或暂停预览。
    @objc private func playButtonTapped() {
        onPlayTapped?()
    }

    /// 点击发送预览。
    @objc private func sendButtonTapped() {
        onSendTapped?()
    }
}

/// 语音录制音量电平视图
@MainActor
final class VoiceLevelMeterView: UIView {
    /// 最多保留的波形样本数量
    private static let maximumSampleCount = 42
    /// 实时录音音量采样间隔，和 `VoiceRecordingController` 的 meter timer 保持一致。
    private static let recordingSampleInterval: CFTimeInterval = 0.1
    /// 波形高度样本，数组尾部是最新样本
    private var samples: [Double] = []
    /// 已裁剪的播放进度。
    private var playbackProgressValue: Double?
    /// 录音态滚动动画。
    private var recordingDisplayLink: CADisplayLink?
    /// 录音态柱形左移相位，范围 0...1。
    private var recordingScrollPhase: CGFloat = 0
    /// 上一帧动画时间戳。
    private var lastDisplayLinkTimestamp: CFTimeInterval = 0
    /// 播放进度。录音电平视图为 nil，预览播放视图为 0...1。
    var playbackProgress: Double? {
        get {
            playbackProgressValue
        }
        set {
            playbackProgressValue = newValue.map { min(1, max(0, $0)) }
            if playbackProgressValue != nil {
                stopRecordingAnimation()
            }
            setNeedsDisplay()
        }
    }

    /// 归一化音量值，范围 0...1
    var powerLevel: Double = 0 {
        didSet {
            powerLevel = max(0, min(1, powerLevel))
            samples = [powerLevel]
            playbackProgress = nil
            stopRecordingAnimation()
            setNeedsDisplay()
        }
    }

    /// 初始化音量电平视图
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    /// 从 storyboard/xib 初始化音量电平视图
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }

    /// 视图离开窗口时停止动画，避免隐藏状态空跑。
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            stopRecordingAnimation()
            return
        }

        if playbackProgress == nil, samples.count > 1 {
            startRecordingAnimationIfNeeded()
        }
    }

    /// 追加新的实时音量样本，视觉上从右侧进入、旧样本向左移动。
    func appendPowerLevel(_ level: Double) {
        playbackProgressValue = nil
        let clampedLevel = max(0, min(1, level))
        samples.append(clampedLevel)
        if samples.count > Self.maximumSampleCount {
            samples.removeFirst(samples.count - Self.maximumSampleCount)
        }
        recordingScrollPhase = 0
        lastDisplayLinkTimestamp = 0
        startRecordingAnimationIfNeeded()
        setNeedsDisplay()
    }

    /// 为待发送预览生成稳定波形。
    func seedPreviewSamples() {
        stopRecordingAnimation()
        samples = (0..<Self.maximumSampleCount).map { index in
            let phase = Double(index) / Double(max(Self.maximumSampleCount - 1, 1))
            return 0.18 + 0.66 * abs(sin(phase * .pi * 2.4))
        }
        playbackProgress = 0
        setNeedsDisplay()
    }

    /// 绘制音量柱形图
    override func draw(_ rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }

        let visibleSamples = visibleSamplesForDrawing()
        let barCount = visibleSamples.count
        let spacing: CGFloat = 3
        let layoutBarCount = playbackProgress == nil ? max(barCount - 1, 1) : barCount
        let barWidth = max(2, min(4, (rect.width - CGFloat(layoutBarCount - 1) * spacing) / CGFloat(layoutBarCount)))
        let barPitch = barWidth + spacing
        let contentWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        let startX = playbackProgress == nil
            ? -recordingScrollPhase * barPitch
            : max(0, rect.width - contentWidth)

        for (index, sample) in visibleSamples.enumerated() {
            let progress = CGFloat(index) / CGFloat(max(barCount - 1, 1))
            let centerWeight = 0.38 + 0.62 * sin(progress * .pi)
            let heightScale = 0.22 + 0.78 * CGFloat(sample) * centerWeight
            let barHeight = max(4, rect.height * heightScale)
            let x = startX + CGFloat(index) * (barWidth + spacing)
            let y = (rect.height - barHeight) / 2
            let path = UIBezierPath(
                roundedRect: CGRect(x: x, y: y, width: barWidth, height: barHeight),
                cornerRadius: barWidth / 2
            )
            let ageAlpha: CGFloat
            if let playbackProgress {
                let activeSamples = Int(ceil(CGFloat(barCount) * CGFloat(playbackProgress)))
                ageAlpha = index < activeSamples ? 0.92 : 0.3
            } else {
                ageAlpha = 0.3 + 0.62 * CGFloat(index + 1) / CGFloat(barCount)
            }
            let color = tintColor.withAlphaComponent(ageAlpha)
            color.setFill()
            path.fill()
        }
    }

    /// 当前绘制用样本。录音态需要铺满可用宽度，避免实时样本少时右侧留空。
    private func visibleSamplesForDrawing() -> [Double] {
        if playbackProgress != nil {
            return samples.isEmpty ? Array(repeating: powerLevel, count: 9) : samples
        }

        let currentSamples = samples.isEmpty ? [powerLevel] : samples
        guard currentSamples.count < Self.maximumSampleCount else {
            return currentSamples + [currentSamples.last ?? powerLevel]
        }

        let paddingCount = Self.maximumSampleCount - currentSamples.count
        let seedLevel = max(0.12, min(0.28, currentSamples.first ?? powerLevel))
        let paddingSamples = (0..<paddingCount).map { index in
            let phase = Double(index) / Double(max(paddingCount - 1, 1))
            return seedLevel * (0.72 + 0.28 * abs(sin(phase * .pi * 2)))
        }
        let paddedSamples = paddingSamples + currentSamples
        return paddedSamples + [paddedSamples.last ?? seedLevel]
    }

    /// 启动录音态显示刷新。
    private func startRecordingAnimationIfNeeded() {
        guard window != nil, recordingDisplayLink == nil else { return }
        let displayLink = CADisplayLink(target: self, selector: #selector(recordingAnimationDidTick(_:)))
        displayLink.add(to: .main, forMode: .common)
        recordingDisplayLink = displayLink
    }

    /// 停止录音态显示刷新。
    private func stopRecordingAnimation() {
        recordingDisplayLink?.invalidate()
        recordingDisplayLink = nil
        recordingScrollPhase = 0
        lastDisplayLinkTimestamp = 0
    }

    /// 推进录音态波形滚动相位。
    @objc private func recordingAnimationDidTick(_ displayLink: CADisplayLink) {
        let elapsed: CFTimeInterval
        if lastDisplayLinkTimestamp > 0 {
            elapsed = max(0, displayLink.timestamp - lastDisplayLinkTimestamp)
        } else {
            elapsed = displayLink.duration
        }

        lastDisplayLinkTimestamp = displayLink.timestamp
        let phaseDelta = CGFloat(elapsed / Self.recordingSampleInterval)
        recordingScrollPhase = min(0.98, recordingScrollPhase + phaseDelta)
        setNeedsDisplay()
    }
}
