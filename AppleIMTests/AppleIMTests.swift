//
//  AppleIMTests.swift
//  AppleIMTests
//
//  Created by Sondra on 2026/4/28.
//

import Testing
import Foundation
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

    @Test func accountStoragePreparesIsolatedDirectories() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let service = await FileAccountStorageService(rootDirectory: rootDirectory)
        let paths = try await service.prepareStorage(for: "test/account")

        #expect(paths.rootDirectory.lastPathComponent == "account_test_account")
        #expect(FileManager.default.fileExists(atPath: paths.mainDatabase.path))
        #expect(FileManager.default.fileExists(atPath: paths.searchDatabase.path))
        #expect(FileManager.default.fileExists(atPath: paths.fileIndexDatabase.path))
        #expect(FileManager.default.fileExists(atPath: paths.mediaDirectory.path))
        #expect(FileManager.default.fileExists(atPath: paths.cacheDirectory.path))
    }

    @Test func databaseBootstrapPersistsMigrationMetadata() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let paths = try await storageService.prepareStorage(for: "metadata_user")
        let databaseActor = await DatabaseActor()

        let result = try await databaseActor.bootstrap(paths: paths)
        let loadedMetadata = try await databaseActor.loadMigrationMetadata(paths: paths)

        #expect(result.metadata.schemaVersion == DatabaseSchema.currentVersion)
        #expect(loadedMetadata == result.metadata)
        #expect(loadedMetadata.appliedScriptIDs.contains("001_main_core_tables"))
        #expect(loadedMetadata.appliedScriptIDs.contains("001_search_tables"))
        #expect(loadedMetadata.appliedScriptIDs.contains("001_file_index_tables"))
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

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("AppleIMTests-\(UUID().uuidString)", isDirectory: true)
}
