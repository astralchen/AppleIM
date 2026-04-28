//
//  AppleIMTests.swift
//  AppleIMTests
//
//  Created by Sondra on 2026/4/28.
//

import Testing
@testable import AppleIM

struct AppleIMTests {

    @MainActor
    @Test func conversationListViewModelLoadsRows() async throws {
        let viewModel = ConversationListViewModel(useCase: StubConversationListUseCase())

        viewModel.load()
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(viewModel.currentState.phase == .loaded)
        #expect(viewModel.currentState.rows.count == 1)
        #expect(viewModel.currentState.rows.first?.title == "Test Conversation")
    }
}

private struct StubConversationListUseCase: ConversationListUseCase {
    func loadConversations() async throws -> [ConversationListRowState] {
        [
            ConversationListRowState(
                id: "test_conversation",
                title: "Test Conversation",
                subtitle: "Loaded by ViewModel",
                timeText: "Now",
                unreadText: nil,
                isPinned: false,
                isMuted: false
            )
        ]
    }
}
