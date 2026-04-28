//
//  ChatViewState.swift
//  AppleIM
//

import Foundation

nonisolated struct ChatMessageRowState: Identifiable, Hashable, Sendable {
    let id: MessageID
    let text: String
    let timeText: String
    let statusText: String?
    let isOutgoing: Bool
}

nonisolated struct ChatViewState: Equatable, Sendable {
    enum LoadingPhase: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var title: String
    var phase: LoadingPhase = .idle
    var rows: [ChatMessageRowState] = []
    var emptyMessage = "No messages yet"

    var isEmpty: Bool {
        rows.isEmpty
    }
}
