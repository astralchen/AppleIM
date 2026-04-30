//
//  SearchUseCase.swift
//  AppleIM
//
//  Global search use case.

import Foundation

protocol SearchUseCase: Sendable {
    func search(query: String) async throws -> SearchResults
    func rebuildIndex() async throws
}

nonisolated struct LocalSearchUseCase: SearchUseCase {
    private let userID: UserID
    private let storeProvider: ChatStoreProvider
    private let limit: Int

    init(userID: UserID, storeProvider: ChatStoreProvider, limit: Int = 20) {
        self.userID = userID
        self.storeProvider = storeProvider
        self.limit = limit
    }

    func search(query: String) async throws -> SearchResults {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return SearchResults()
        }

        let index = try await storeProvider.searchIndex()
        let records = try await index.search(query: trimmedQuery, limit: limit)

        return SearchResults(
            contacts: records.filter { $0.kind == .contact },
            conversations: records.filter { $0.kind == .conversation },
            messages: records.filter { $0.kind == .message }
        )
    }

    func rebuildIndex() async throws {
        let index = try await storeProvider.searchIndex()
        try await index.rebuildAll(userID: userID)
    }
}
