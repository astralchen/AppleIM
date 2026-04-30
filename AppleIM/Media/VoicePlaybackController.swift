//
//  VoicePlaybackController.swift
//  AppleIM
//

import AVFoundation
import Foundation

/// AVFoundation 语音播放控制器
@MainActor
final class VoicePlaybackController: NSObject {
    var onStarted: ((MessageID) -> Void)?
    var onStopped: ((MessageID) -> Void)?
    var onFailed: ((MessageID) -> Void)?

    private var player: AVAudioPlayer?
    private var playingMessageID: MessageID?

    func isPlaying(messageID: MessageID) -> Bool {
        playingMessageID == messageID && player?.isPlaying == true
    }

    @discardableResult
    func play(messageID: MessageID, fileURL: URL) -> Bool {
        if isPlaying(messageID: messageID) {
            stop()
            return true
        }

        stop()

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            onFailed?(messageID)
            return false
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.delegate = self
            player.prepareToPlay()

            guard player.play() else {
                onFailed?(messageID)
                return false
            }

            self.player = player
            playingMessageID = messageID
            onStarted?(messageID)
            return true
        } catch {
            player = nil
            playingMessageID = nil
            onFailed?(messageID)
            return false
        }
    }

    func stop() {
        guard let messageID = playingMessageID else {
            return
        }

        player?.stop()
        player = nil
        playingMessageID = nil
        deactivateSession()
        onStopped?(messageID)
    }

    private func finishPlayback(successfully: Bool) {
        guard let messageID = playingMessageID else {
            return
        }

        player = nil
        playingMessageID = nil
        deactivateSession()

        if successfully {
            onStopped?(messageID)
        } else {
            onFailed?(messageID)
        }
    }

    private func deactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Playback session teardown failure is non-fatal for chat UI state.
        }
    }
}

extension VoicePlaybackController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.finishPlayback(successfully: flag)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.finishPlayback(successfully: false)
        }
    }
}
