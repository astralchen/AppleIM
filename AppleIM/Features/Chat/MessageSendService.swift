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

nonisolated enum MessageSendResult: Equatable, Sendable {
    case success(MessageSendAck)
    case failure
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
            return .failure
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
        case .failure:
            return .failure
        }
    }
}
