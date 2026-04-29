//
//  MediaUploadService.swift
//  AppleIM
//
//  媒体上传服务
//  定义可替换的媒体上传协议和 Mock 实现

import Foundation

/// 媒体上传确认
nonisolated struct MediaUploadAck: Equatable, Sendable {
    /// 媒体资源 ID
    let mediaID: String
    /// CDN URL
    let cdnURL: String
    /// 文件摘要
    let md5: String?
}

/// 媒体上传失败原因
nonisolated enum MediaUploadFailureReason: String, Codable, Equatable, Sendable {
    /// 未知错误
    case unknown
    /// 超时
    case timeout
    /// 离线
    case offline
}

/// 媒体上传事件
nonisolated enum MediaUploadEvent: Equatable, Sendable {
    /// 上传进度，范围 0.0-1.0
    case progress(Double)
    /// 上传完成
    case completed(MediaUploadAck)
    /// 上传失败
    case failed(MediaUploadFailureReason = .unknown)
}

/// 媒体上传服务协议
protocol MediaUploadService: Sendable {
    /// 上传图片
    ///
    /// - Parameter message: 已落盘并入库的图片消息
    /// - Returns: 上传事件流
    nonisolated func uploadImage(message: StoredMessage) -> AsyncStream<MediaUploadEvent>
    /// 上传语音
    ///
    /// - Parameter message: 已落盘并入库的语音消息
    /// - Returns: 上传事件流
    nonisolated func uploadVoice(message: StoredMessage) -> AsyncStream<MediaUploadEvent>
}

/// Mock 媒体上传服务
///
/// 用于本地开发和测试，分段发布进度并返回稳定的 CDN URL。
nonisolated struct MockMediaUploadService: MediaUploadService {
    private let result: MediaUploadEvent
    private let progressSteps: [Double]
    private let delayNanoseconds: UInt64

    init(
        result: MediaUploadEvent? = nil,
        progressSteps: [Double] = [0.2, 0.5, 0.8, 1.0],
        delayNanoseconds: UInt64 = 120_000_000
    ) {
        self.result = result ?? .completed(
            MediaUploadAck(
                mediaID: "",
                cdnURL: "",
                md5: nil
            )
        )
        self.progressSteps = progressSteps
        self.delayNanoseconds = delayNanoseconds
    }

    nonisolated func uploadImage(message: StoredMessage) -> AsyncStream<MediaUploadEvent> {
        upload(kind: "image", message: message, mediaID: message.image?.mediaID)
    }

    nonisolated func uploadVoice(message: StoredMessage) -> AsyncStream<MediaUploadEvent> {
        upload(kind: "voice", message: message, mediaID: message.voice?.mediaID)
    }

    private nonisolated func upload(kind: String, message: StoredMessage, mediaID: String?) -> AsyncStream<MediaUploadEvent> {
        AsyncStream { continuation in
            let task = Task {
                for step in progressSteps {
                    guard !Task.isCancelled else {
                        continuation.finish()
                        return
                    }

                    continuation.yield(.progress(min(1.0, max(0.0, step))))

                    do {
                        try await Task.sleep(nanoseconds: delayNanoseconds)
                    } catch {
                        continuation.finish()
                        return
                    }
                }

                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }

                switch result {
                case let .completed(ack):
                    continuation.yield(
                        .completed(
                            MediaUploadAck(
                                mediaID: ack.mediaID.isEmpty ? (mediaID ?? message.id.rawValue) : ack.mediaID,
                                cdnURL: ack.cdnURL.isEmpty ? "https://mock-cdn.chatbridge.local/\(kind)/\(message.id.rawValue)" : ack.cdnURL,
                                md5: ack.md5 ?? "mock-md5-\(mediaID ?? message.id.rawValue)"
                            )
                        )
                    )
                case let .failed(reason):
                    continuation.yield(.failed(reason))
                case let .progress(progress):
                    continuation.yield(.progress(progress))
                    continuation.yield(
                        .completed(
                            MediaUploadAck(
                                mediaID: mediaID ?? message.id.rawValue,
                                cdnURL: "https://mock-cdn.chatbridge.local/\(kind)/\(message.id.rawValue)",
                                md5: "mock-md5-\(mediaID ?? message.id.rawValue)"
                            )
                        )
                    )
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
