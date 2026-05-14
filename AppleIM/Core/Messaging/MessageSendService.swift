//
//  MessageSendService.swift
//  AppleIM
//
//  消息发送领域接口
//  定义消息发送结果、重试策略和发送服务协议

import Foundation

/// 消息发送确认
///
/// 服务端返回的消息发送成功确认信息
nonisolated struct MessageSendAck: Equatable, Sendable {
    /// 服务端消息 ID
    let serverMessageID: String
    /// 服务端序号
    let sequence: Int64
    /// 服务端时间戳
    let serverTime: Int64
}

/// 消息发送失败原因
nonisolated enum MessageSendFailureReason: String, Codable, Equatable, Sendable {
    /// 未知错误
    case unknown
    /// 超时
    case timeout
    /// 离线
    case offline
    /// 缺少确认
    case ackMissing
}

/// 消息发送结果
nonisolated enum MessageSendResult: Equatable, Sendable {
    /// 发送成功
    case success(MessageSendAck)
    /// 发送失败
    case failure(MessageSendFailureReason = .unknown)
}

/// 消息重试策略
///
/// 使用指数退避算法计算重试延迟
nonisolated struct MessageRetryPolicy: Equatable, Sendable {
    /// 初始延迟秒数
    let initialDelaySeconds: Int64
    /// 最大延迟秒数
    let maxDelaySeconds: Int64
    /// 最大重试次数
    let maxRetryCount: Int

    init(
        initialDelaySeconds: Int64 = 2,
        maxDelaySeconds: Int64 = 60,
        maxRetryCount: Int = 5
    ) {
        self.initialDelaySeconds = max(1, initialDelaySeconds)
        self.maxDelaySeconds = max(self.initialDelaySeconds, maxDelaySeconds)
        self.maxRetryCount = max(1, maxRetryCount)
    }

    /// 计算重试延迟秒数
    ///
    /// 使用指数退避算法：delay = initialDelay * 2^retryCount
    ///
    /// - Parameter retryCount: 重试次数
    /// - Returns: 延迟秒数
    func delaySeconds(after retryCount: Int) -> Int64 {
        let boundedRetryCount = max(0, retryCount)
        let multiplier = Int64(1) << min(boundedRetryCount, 30)
        return min(maxDelaySeconds, initialDelaySeconds * multiplier)
    }

    /// 计算下次重试时间
    ///
    /// - Parameters:
    ///   - now: 当前时间戳
    ///   - retryCount: 重试次数
    /// - Returns: 下次重试时间戳
    func nextRetryAt(now: Int64, retryCount: Int) -> Int64 {
        now + delaySeconds(after: retryCount)
    }
}

/// 消息发送服务协议
protocol MessageSendService: Sendable {
    /// 发送文本消息
    ///
    /// - Parameter message: 存储的消息
    /// - Returns: 发送结果
    func sendText(message: StoredMessage) async -> MessageSendResult
    /// 发送图片消息
    ///
    /// - Parameters:
    ///   - message: 存储的图片消息
    ///   - upload: 图片上传确认信息
    /// - Returns: 发送结果
    func sendImage(message: StoredMessage, upload: MediaUploadAck) async -> MessageSendResult
    /// 发送语音消息
    ///
    /// - Parameters:
    ///   - message: 存储的语音消息
    ///   - upload: 语音上传确认信息
    /// - Returns: 发送结果
    func sendVoice(message: StoredMessage, upload: MediaUploadAck) async -> MessageSendResult
    /// 发送视频消息
    ///
    /// - Parameters:
    ///   - message: 存储的视频消息
    ///   - upload: 视频上传确认信息
    /// - Returns: 发送结果
    func sendVideo(message: StoredMessage, upload: MediaUploadAck) async -> MessageSendResult
    /// 发送文件消息
    ///
    /// - Parameters:
    ///   - message: 存储的文件消息
    ///   - upload: 文件上传确认信息
    /// - Returns: 发送结果
    func sendFile(message: StoredMessage, upload: MediaUploadAck) async -> MessageSendResult
    /// 发送表情消息。
    func sendEmoji(message: StoredMessage) async -> MessageSendResult
}

/// 模拟消息发送服务
///
/// 用于测试和演示，模拟网络延迟和发送结果
nonisolated struct MockMessageSendService: MessageSendService {
    /// 模拟的发送结果
    private let result: MessageSendResult
    /// 模拟的延迟（纳秒）
    private let delayNanoseconds: UInt64

    /// 初始化
    ///
    /// - Parameters:
    ///   - result: 模拟的发送结果，默认为成功
    ///   - delayNanoseconds: 模拟的延迟（纳秒），默认 300ms
    init(
        result: MessageSendResult = .success(MessageSendAck(serverMessageID: "", sequence: 0, serverTime: 0)),
        delayNanoseconds: UInt64 = 300_000_000
    ) {
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    /// 发送文本消息
    ///
    /// 模拟延迟后返回配置的结果
    ///
    /// - Parameter message: 存储的消息
    /// - Returns: 发送结果
    func sendText(message: StoredMessage) async -> MessageSendResult {
        do {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        } catch {
            return .failure()
        }

        switch result {
        case .success:
            return .success(
                MessageSendAck(
                    serverMessageID: "server_\(message.id.rawValue)",
                    sequence: message.timeline.sortSequence,
                    serverTime: Int64(Date().timeIntervalSince1970)
                )
            )
        case let .failure(reason):
            return .failure(reason)
        }
    }

    /// 发送图片消息
    ///
    /// - Parameters:
    ///   - message: 存储的图片消息
    ///   - upload: 图片上传确认信息
    /// - Returns: 发送结果
    func sendImage(message: StoredMessage, upload: MediaUploadAck) async -> MessageSendResult {
        await sendMedia(message: message)
    }

    /// 发送语音消息
    ///
    /// - Parameters:
    ///   - message: 存储的语音消息
    ///   - upload: 语音上传确认信息
    /// - Returns: 发送结果
    func sendVoice(message: StoredMessage, upload: MediaUploadAck) async -> MessageSendResult {
        await sendMedia(message: message)
    }

    /// 发送视频消息
    ///
    /// - Parameters:
    ///   - message: 存储的视频消息
    ///   - upload: 视频上传确认信息
    /// - Returns: 发送结果
    func sendVideo(message: StoredMessage, upload: MediaUploadAck) async -> MessageSendResult {
        await sendMedia(message: message)
    }

    /// 发送文件消息
    ///
    /// - Parameters:
    ///   - message: 存储的文件消息
    ///   - upload: 文件上传确认信息
    /// - Returns: 发送结果
    func sendFile(message: StoredMessage, upload: MediaUploadAck) async -> MessageSendResult {
        await sendMedia(message: message)
    }

    func sendEmoji(message: StoredMessage) async -> MessageSendResult {
        await sendMedia(message: message)
    }

    /// 发送媒体消息（内部实现）
    ///
    /// 模拟延迟后返回配置的结果
    ///
    /// - Parameter message: 存储的消息
    /// - Returns: 发送结果
    private func sendMedia(message: StoredMessage) async -> MessageSendResult {
        do {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        } catch {
            return .failure()
        }

        switch result {
        case .success:
            return .success(
                MessageSendAck(
                    serverMessageID: "server_\(message.id.rawValue)",
                    sequence: message.timeline.sortSequence,
                    serverTime: Int64(Date().timeIntervalSince1970)
                )
            )
        case let .failure(reason):
            return .failure(reason)
        }
    }
}
