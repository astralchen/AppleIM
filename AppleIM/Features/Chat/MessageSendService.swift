//
//  MessageSendService.swift
//  AppleIM
//

import Foundation

nonisolated enum MessageSendResult: Equatable, Sendable {
    case success
    case failure
}

protocol MessageSendService: Sendable {
    func sendText(message: StoredMessage) async -> MessageSendResult
}

nonisolated struct MockMessageSendService: MessageSendService {
    private let result: MessageSendResult
    private let delayNanoseconds: UInt64

    init(result: MessageSendResult = .success, delayNanoseconds: UInt64 = 300_000_000) {
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    func sendText(message: StoredMessage) async -> MessageSendResult {
        do {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        } catch {
            return .failure
        }

        return result
    }
}
