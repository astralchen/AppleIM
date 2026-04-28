//
//  ConversationListViewState.swift
//  AppleIM
//

import Foundation

struct ConversationListRowState: Identifiable, Equatable, Sendable {
    let id: ConversationID
    let title: String
    let subtitle: String
    let timeText: String
    let unreadText: String?
    let isPinned: Bool
    let isMuted: Bool
}

struct ConversationListViewState: Equatable, Sendable {
    enum LoadingPhase: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var title = "ChatBridge"
    var phase: LoadingPhase = .idle
    var rows: [ConversationListRowState] = []
    var emptyMessage = "No conversations yet"

    var isEmpty: Bool {
        rows.isEmpty
    }
}
