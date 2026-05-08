//
//  VoicePlaybackController.swift
//  AppleIM
//

import AVFoundation
import Foundation

/// AVFoundation 语音播放控制器
///
/// ## 职责
///
/// 1. 管理语音消息的播放
/// 2. 配置音频会话（播放模式）
/// 3. 处理播放状态回调
/// 4. 确保同一时间只播放一条语音
///
/// ## 并发安全
///
/// - 标记为 `@MainActor`，所有方法和属性访问都在主线程
///
/// ## 回调事件
///
/// - `onStarted`: 播放开始
/// - `onStopped`: 播放停止（正常结束或手动停止）
/// - `onFailed`: 播放失败
@MainActor
final class VoicePlaybackController: NSObject {
    var onStarted: ((MessageID) -> Void)?
    var onStopped: ((MessageID) -> Void)?
    var onFailed: ((MessageID) -> Void)?

    private var player: AVAudioPlayer?
    private var playingMessageID: MessageID?

    /// 检查指定消息是否正在播放
    ///
    /// - Parameter messageID: 消息 ID
    /// - Returns: 是否正在播放
    func isPlaying(messageID: MessageID) -> Bool {
        playingMessageID == messageID && player?.isPlaying == true
    }

    /// 播放语音消息
    ///
    /// 流程：
    /// 1. 如果正在播放同一条消息，则停止播放
    /// 2. 停止当前播放的其他消息
    /// 3. 检查文件是否存在
    /// 4. 配置音频会话（播放模式）
    /// 5. 创建 AVAudioPlayer 并开始播放
    ///
    /// - Parameters:
    ///   - messageID: 消息 ID
    ///   - fileURL: 语音文件 URL
    /// - Returns: 是否成功开始播放
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

    /// 停止当前播放
    ///
    /// 停止播放器，释放音频会话，并触发 `onStopped` 回调
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
