//
//  VoiceRecordingController.swift
//  AppleIM
//

import AVFoundation
import Foundation

/// 语音录制状态
nonisolated struct VoiceRecordingState: Equatable, Sendable {
    let isRecording: Bool
    let isCanceling: Bool
    let elapsedMilliseconds: Int
    let averagePowerLevel: Double
    let hintText: String
}

/// 语音录制完成结果
nonisolated enum VoiceRecordingCompletion: Equatable, Sendable {
    case send(VoiceRecordingFile)
    case cancelled
    case tooShort
    case permissionDenied
    case failed
}

/// AVFoundation 语音录制控制器
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

    func beginRecording() async {
        guard !isRecording else { return }

        let hasPermission = await requestMicrophonePermission()
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

    func updateCanceling(_ isCanceling: Bool) {
        guard isRecording else { return }
        self.isCanceling = isCanceling
        publishRecordingState()
    }

    func finishRecording(cancelled: Bool) {
        guard let recorder else { return }
        isCanceling = cancelled || isCanceling
        recorder.stop()
        finishStoppedRecording()
    }

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
            .send(
                VoiceRecordingFile(
                    fileURL: url,
                    durationMilliseconds: elapsedMilliseconds,
                    fileExtension: "m4a"
                )
            )
        )
        publishIdleState(hintText: "Hold to talk")
    }

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
                hintText: isCanceling ? "Release to cancel" : "Release to send"
            )
        )
    }

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

    private func currentElapsedMilliseconds() -> Int {
        guard let startedAt else { return 0 }
        return max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
    }

    private func requestMicrophonePermission() async -> Bool {
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

    private func cleanupRecordingFile() {
        removeFileIfNeeded(recordingURL)
        recorder = nil
        recordingURL = nil
        startedAt = nil
        isCanceling = false
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func removeFileIfNeeded(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static var recordingSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
    }

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
