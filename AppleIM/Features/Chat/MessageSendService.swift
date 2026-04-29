//
//  MessageSendService.swift
//  AppleIM
//

import Foundation

nonisolated struct MessageSendAck: Equatable, Sendable {
    let serverMessageID: String
    let sequence: Int64
    let serverTime: Int64
}

nonisolated enum MessageSendFailureReason: String, Codable, Equatable, Sendable {
    case unknown
    case timeout
    case offline
    case ackMissing
}

nonisolated enum MessageSendResult: Equatable, Sendable {
    case success(MessageSendAck)
    case failure(MessageSendFailureReason = .unknown)
}

nonisolated struct MessageRetryPolicy: Equatable, Sendable {
    let initialDelaySeconds: Int64
    let maxDelaySeconds: Int64
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

    func delaySeconds(after retryCount: Int) -> Int64 {
        let boundedRetryCount = max(0, retryCount)
        let multiplier = Int64(1) << min(boundedRetryCount, 30)
        return min(maxDelaySeconds, initialDelaySeconds * multiplier)
    }

    func nextRetryAt(now: Int64, retryCount: Int) -> Int64 {
        now + delaySeconds(after: retryCount)
    }
}

protocol MessageSendService: Sendable {
    func sendText(message: StoredMessage) async -> MessageSendResult
}

nonisolated struct MockMessageSendService: MessageSendService {
    private let result: MessageSendResult
    private let delayNanoseconds: UInt64

    init(
        result: MessageSendResult = .success(MessageSendAck(serverMessageID: "", sequence: 0, serverTime: 0)),
        delayNanoseconds: UInt64 = 300_000_000
    ) {
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

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
                    sequence: message.sortSequence,
                    serverTime: Int64(Date().timeIntervalSince1970)
                )
            )
        case let .failure(reason):
            return .failure(reason)
        }
    }
}
