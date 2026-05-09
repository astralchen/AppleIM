//
//  VoiceRecordingController.swift
//  AppleIM
//

import AVFoundation
import Foundation

/// 语音录制状态
///
/// 用于实时反馈录制进度和音量
nonisolated struct VoiceRecordingState: Equatable, Sendable {
    /// 是否正在录制
    let isRecording: Bool
    /// 是否正在取消（上滑取消状态）
    let isCanceling: Bool
    /// 已录制时长（毫秒）
    let elapsedMilliseconds: Int
    /// 平均音量电平（0.0 - 1.0）
    let averagePowerLevel: Double
    /// 提示文本
    let hintText: String
}

/// 语音录制完成结果
nonisolated enum VoiceRecordingCompletion: Equatable, Sendable {
    /// 录音文件已完成，等待用户预览确认
    case completed(VoiceRecordingFile)
    /// 用户取消
    case cancelled
    /// 录制时长太短
    case tooShort
    /// 麦克风权限被拒绝
    case permissionDenied
    /// 录制失败
    case failed
}

/// AVFoundation 语音录制控制器
///
/// ## 职责
///
/// 1. 管理语音录制的完整生命周期
/// 2. 处理麦克风权限请求
/// 3. 配置音频会话
/// 4. 实时发布录制状态和音量电平
/// 5. 处理录制完成和取消逻辑
///
/// ## 并发安全
///
/// - 标记为 `@MainActor`，所有方法和属性访问都在主线程
///
/// ## 使用流程
///
/// 1. 调用 `beginRecording()` 开始录制
/// 2. 通过 `onStateChange` 接收实时状态更新
/// 3. 调用 `updateCanceling(_:)` 更新取消状态
/// 4. 调用 `finishRecording(cancelled:)` 结束录制
/// 5. 通过 `onCompletion` 接收完成结果，成功录音进入待发送预览
@MainActor
final class VoiceRecordingController: NSObject {
    private static let minimumDurationMilliseconds = 1_000
    private static let maximumDurationMilliseconds = 60_000

    var onStateChange: ((VoiceRecordingState) -> Void)?
    var onCompletion: ((VoiceRecordingCompletion) -> Void)?

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var recordingURL: URL?
    private var startedAt: Date?
    private var isCanceling = false

    var isRecording: Bool {
        recorder?.isRecording == true
    }

    /// 开始录制语音
    ///
    /// 流程：
    /// 1. 检查麦克风权限
    /// 2. 配置音频会话（录制模式）
    /// 3. 创建临时录音文件
    /// 4. 启动 AVAudioRecorder
    /// 5. 启动定时器更新状态
    /// 6. 检查最大时长限制
    ///
    /// - Note: 如果权限被拒绝，会通过 `onCompletion` 回调 `.permissionDenied`
    func beginRecording() async {
        guard !isRecording else { return }

        let hasPermission = await Self.requestMicrophonePermission()
        guard hasPermission else {
            onCompletion?(.permissionDenied)
            publishIdleState(hintText: "Microphone access denied")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let url = Self.makeTemporaryRecordingURL()
            let recorder = try AVAudioRecorder(url: url, settings: Self.recordingSettings)
            recorder.isMeteringEnabled = true
            recorder.delegate = self

            guard recorder.record(forDuration: TimeInterval(Self.maximumDurationMilliseconds) / 1_000.0) else {
                onCompletion?(.failed)
                return
            }

            self.recorder = recorder
            recordingURL = url
            startedAt = Date()
            isCanceling = false
            startMeterTimer()
            publishRecordingState()
        } catch {
            cleanupRecordingFile()
            onCompletion?(.failed)
            publishIdleState(hintText: "Unable to record")
        }
    }

    /// 更新取消状态
    ///
    /// 用于实现"上滑取消"交互，更新 UI 提示
    ///
    /// - Parameter isCanceling: 是否处于取消状态
    func updateCanceling(_ isCanceling: Bool) {
        guard isRecording else { return }
        self.isCanceling = isCanceling
        publishRecordingState()
    }

    /// 结束录制
    ///
    /// 停止录音器，并根据取消状态和时长判断完成结果
    ///
    /// - Parameter cancelled: 是否取消发送
    func finishRecording(cancelled: Bool) {
        guard let recorder else { return }
        isCanceling = cancelled || isCanceling
        recorder.stop()
        finishStoppedRecording()
    }

    /// 完成录制并处理结果
    ///
    /// 流程：
    /// 1. 停止定时器
    /// 2. 释放音频会话
    /// 3. 检查取消状态
    /// 4. 检查最小时长限制
    /// 5. 通过 `onCompletion` 回调结果
    ///
    /// - Note: 如果取消或时长太短，会删除录音文件
    private func finishStoppedRecording() {
        meterTimer?.invalidate()
        meterTimer = nil

        let elapsedMilliseconds = currentElapsedMilliseconds()
        let shouldCancel = isCanceling
        let url = recordingURL

        recorder = nil
        recordingURL = nil
        startedAt = nil
        isCanceling = false

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Session teardown failure should not block sending a valid local recording.
        }

        guard !shouldCancel else {
            removeFileIfNeeded(url)
            onCompletion?(.cancelled)
            publishIdleState(hintText: "Voice cancelled")
            return
        }

        guard elapsedMilliseconds >= Self.minimumDurationMilliseconds, let url else {
            removeFileIfNeeded(url)
            onCompletion?(.tooShort)
            publishIdleState(hintText: "Voice too short")
            return
        }

        onCompletion?(
            .completed(
                VoiceRecordingFile(
                    fileURL: url,
                    durationMilliseconds: elapsedMilliseconds,
                    fileExtension: "m4a"
                )
            )
        )
        publishIdleState(hintText: "Hold to talk")
    }

    /// 启动音量计定时器
    ///
    /// 每 0.1 秒更新一次录制状态和音量电平，并检查最大时长限制
    private func startMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }

                if self.currentElapsedMilliseconds() >= Self.maximumDurationMilliseconds {
                    self.finishRecording(cancelled: false)
                } else {
                    self.publishRecordingState()
                }
            }
        }
    }

    /// 发布录制状态
    ///
    /// 更新音量电平并通过 `onStateChange` 回调状态
    ///
    /// - Note: 音量电平从 -60dB 到 0dB 归一化到 0.0-1.0
    private func publishRecordingState() {
        recorder?.updateMeters()
        let averagePower = recorder?.averagePower(forChannel: 0) ?? -60
        let normalizedPower = max(0.0, min(1.0, (Double(averagePower) + 60.0) / 60.0))
        let elapsedMilliseconds = currentElapsedMilliseconds()

        onStateChange?(
            VoiceRecordingState(
                isRecording: true,
                isCanceling: isCanceling,
                elapsedMilliseconds: elapsedMilliseconds,
                averagePowerLevel: normalizedPower,
                hintText: isCanceling ? "Release to cancel" : "Release to preview"
            )
        )
    }

    /// 发布空闲状态
    ///
    /// 通过 `onStateChange` 回调空闲状态
    ///
    /// - Parameter hintText: 提示文本
    private func publishIdleState(hintText: String) {
        onStateChange?(
            VoiceRecordingState(
                isRecording: false,
                isCanceling: false,
                elapsedMilliseconds: 0,
                averagePowerLevel: 0,
                hintText: hintText
            )
        )
    }

    /// 计算当前已录制时长
    ///
    /// - Returns: 已录制时长（毫秒）
    private func currentElapsedMilliseconds() -> Int {
        guard let startedAt else { return 0 }
        return max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
    }

    /// 请求麦克风权限
    ///
    /// 流程：
    /// 1. 检查当前权限状态
    /// 2. 如果已授权，直接返回 true
    /// 3. 如果已拒绝，返回 false
    /// 4. 如果未确定，弹出系统权限请求
    ///
    /// - Returns: 是否已授权
    private nonisolated static func requestMicrophonePermission() async -> Bool {
        let session = AVAudioSession.sharedInstance()

        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    /// 清理录音文件和状态
    ///
    /// 删除录音文件，释放录音器和定时器
    private func cleanupRecordingFile() {
        removeFileIfNeeded(recordingURL)
        recorder = nil
        recordingURL = nil
        startedAt = nil
        isCanceling = false
        meterTimer?.invalidate()
        meterTimer = nil
    }

    /// 删除录音文件
    ///
    /// - Parameter url: 录音文件 URL
    private func removeFileIfNeeded(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// 录音设置
    ///
    /// - 格式：AAC (MPEG4)
    /// - 采样率：16kHz
    /// - 声道数：单声道
    /// - 音质：中等
    private static var recordingSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
    }

    /// 创建临时录音文件 URL
    ///
    /// 在系统临时目录创建唯一的 .m4a 文件
    ///
    /// - Returns: 临时录音文件 URL
    private static func makeTemporaryRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("chatbridge-voice-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
    }
}

extension VoiceRecordingController: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard self.recorder === recorder else { return }

            if flag {
                self.finishStoppedRecording()
            } else {
                self.cleanupRecordingFile()
                self.onCompletion?(.failed)
                self.publishIdleState(hintText: "Unable to record")
            }
        }
    }
}
