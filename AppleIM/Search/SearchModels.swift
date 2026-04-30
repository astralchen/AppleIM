//
//  SearchModels.swift
//  AppleIM
//
//  Search module models.

import Foundation

nonisolated enum SearchResultKind: String, Codable, Sendable {
    case contact
    case conversation
    case message
}

nonisolated struct SearchResultRecord: Equatable, Sendable {
    let kind: SearchResultKind
    let id: String
    let title: String
    let subtitle: String
    let conversationID: ConversationID?
    let messageID: MessageID?
}

nonisolated struct SearchResults: Equatable, Sendable {
    var contacts: [SearchResultRecord] = []
    var conversations: [SearchResultRecord] = []
    var messages: [SearchResultRecord] = []

    var isEmpty: Bool {
        contacts.isEmpty && conversations.isEmpty && messages.isEmpty
    }
}

nonisolated struct SearchResultRowState: Identifiable, Hashable, Sendable {
    let id: String
    let kind: SearchResultKind
    let title: String
    let subtitle: String
    let conversationID: ConversationID?
    let messageID: MessageID?

    init(record: SearchResultRecord) {
        self.id = "\(record.kind.rawValue)_\(record.id)"
        self.kind = record.kind
        self.title = record.title
        self.subtitle = record.subtitle
        self.conversationID = record.conversationID
        self.messageID = record.messageID
    }
}

nonisolated struct SearchViewState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var query = ""
    var phase: Phase = .idle
    var contacts: [SearchResultRowState] = []
    var conversations: [SearchResultRowState] = []
    var messages: [SearchResultRowState] = []

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isEmpty: Bool {
        contacts.isEmpty && conversations.isEmpty && messages.isEmpty
    }
}
