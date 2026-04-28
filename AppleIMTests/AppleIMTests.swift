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
        let databaseActor = DatabaseActor()

        let result = try await databaseActor.bootstrap(paths: paths)
        let loadedMetadata = try await databaseActor.loadMigrationMetadata(paths: paths)
        let mainTables = try await databaseActor.tableNames(in: .main, paths: paths)
        let searchTables = try await databaseActor.tableNames(in: .search, paths: paths)
        let fileIndexTables = try await databaseActor.tableNames(in: .fileIndex, paths: paths)

        #expect(result.metadata.schemaVersion == DatabaseSchema.currentVersion)
        #expect(loadedMetadata == result.metadata)
        #expect(loadedMetadata.appliedScriptIDs.contains("001_main_core_tables"))
        #expect(loadedMetadata.appliedScriptIDs.contains("001_search_tables"))
        #expect(loadedMetadata.appliedScriptIDs.contains("001_file_index_tables"))
        #expect(mainTables.contains("migration_meta"))
        #expect(mainTables.contains("conversation"))
        #expect(mainTables.contains("message"))
        #expect(searchTables.contains("message_search"))
        #expect(fileIndexTables.contains("file_index"))
    }

    @Test func databaseActorExecutesPreparedInsertAndQuery() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "prepared_user")

        try await databaseActor.execute(
            """
            INSERT INTO conversation (
                conversation_id,
                user_id,
                biz_type,
                target_id,
                title,
                last_message_digest,
                unread_count,
                is_pinned,
                is_muted,
                is_hidden,
                sort_ts
            ) VALUES (?, ?, ?, ?, ?, ?, 0, 0, 0, 0, ?);
            """,
            parameters: [
                .text("prepared_conversation"),
                .text("prepared_user"),
                .integer(Int64(ConversationType.single.rawValue)),
                .text("target"),
                .text("Sondra's SQLite"),
                .text("Prepared statement works"),
                .integer(100)
            ],
            paths: paths
        )

        let rows = try await databaseActor.query(
            "SELECT title FROM conversation WHERE conversation_id = ?;",
            parameters: [.text("prepared_conversation")],
            paths: paths
        )

        #expect(rows.first?.string("title") == "Sondra's SQLite")
    }

    @Test func conversationDAOListsPinnedThenNewestConversations() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "ordered_user")
        let dao = ConversationDAO(database: databaseActor, paths: paths)

        try await dao.upsert(makeConversationRecord(id: "normal_old", userID: "ordered_user", title: "Old", sortTimestamp: 10))
        try await dao.upsert(makeConversationRecord(id: "normal_new", userID: "ordered_user", title: "New", sortTimestamp: 30))
        try await dao.upsert(makeConversationRecord(id: "pinned_old", userID: "ordered_user", title: "Pinned", isPinned: true, sortTimestamp: 20))

        let records = try await dao.listConversations(for: "ordered_user")

        #expect(records.map(\.id.rawValue) == ["pinned_old", "normal_new", "normal_old"])
    }

    @Test func localChatRepositoryInsertsOutgoingTextMessageInTransaction() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "message_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "message_conversation", userID: "message_user", title: "Message Target", sortTimestamp: 1)
        )

        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "message_user",
                conversationID: "message_conversation",
                senderID: "message_user",
                text: "Hello from the repository",
                localTime: 200,
                messageID: "message_1",
                clientMessageID: "client_1",
                sortSequence: 200
            )
        )
        let messages = try await repository.listMessages(conversationID: "message_conversation", limit: 20, beforeSortSeq: nil)
        let conversations = try await repository.listConversations(for: "message_user")

        #expect(message.sendStatus == .sending)
        #expect(messages.count == 1)
        #expect(messages.first?.text == "Hello from the repository")
        #expect(conversations.first?.lastMessageDigest == "Hello from the repository")
    }

    @Test func localChatRepositoryRollsBackWhenMessageInsertFails() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "rollback_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "rollback_conversation", userID: "rollback_user", title: "Rollback", sortTimestamp: 1)
        )

        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "rollback_user",
                conversationID: "rollback_conversation",
                senderID: "rollback_user",
                text: "Original",
                localTime: 300,
                messageID: "rollback_original",
                clientMessageID: "same_client",
                sortSequence: 300
            )
        )

        var didThrow = false

        do {
            _ = try await repository.insertOutgoingTextMessage(
                OutgoingTextMessageInput(
                    userID: "rollback_user",
                    conversationID: "rollback_conversation",
                    senderID: "rollback_user",
                    text: "Duplicate",
                    localTime: 301,
                    messageID: "rollback_duplicate",
                    clientMessageID: "same_client",
                    sortSequence: 301
                )
            )
        } catch {
            didThrow = true
        }

        let leakedContentRows = try await databaseContext.databaseActor.query(
            "SELECT COUNT(*) AS content_count FROM message_text WHERE content_id = ?;",
            parameters: [.text("text_rollback_duplicate")],
            paths: databaseContext.paths
        )
        let conversations = try await repository.listConversations(for: "rollback_user")

        #expect(didThrow)
        #expect(leakedContentRows.first?.int("content_count") == 0)
        #expect(conversations.first?.lastMessageDigest == "Original")
    }

    @Test func localConversationListUseCaseMapsRepositoryRows() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "usecase_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let useCase = LocalConversationListUseCase(userID: "usecase_user", storeProvider: storeProvider)

        let rows = try await useCase.loadConversations()

        #expect(rows.count == 3)
        #expect(rows.first?.id == "single_sondra")
        #expect(rows.first?.unreadText == "2")
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

private nonisolated struct DatabaseTestContext: Sendable {
    let databaseActor: DatabaseActor
    let paths: AccountStoragePaths
}

private func makeBootstrappedDatabase(rootDirectory: URL, accountID: UserID) async throws -> (DatabaseActor, AccountStoragePaths) {
    let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
    let paths = try await storageService.prepareStorage(for: accountID)
    let databaseActor = DatabaseActor()
    _ = try await databaseActor.bootstrap(paths: paths)
    return (databaseActor, paths)
}

private func makeRepository(rootDirectory: URL, accountID: UserID) async throws -> (LocalChatRepository, DatabaseTestContext) {
    let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: accountID)
    let repository = LocalChatRepository(database: databaseActor, paths: paths)
    return (repository, DatabaseTestContext(databaseActor: databaseActor, paths: paths))
}

private func makeConversationRecord(
    id: ConversationID,
    userID: UserID,
    title: String,
    isPinned: Bool = false,
    sortTimestamp: Int64
) -> ConversationRecord {
    ConversationRecord(
        id: id,
        userID: userID,
        type: .single,
        targetID: "\(id.rawValue)_target",
        title: title,
        avatarURL: nil,
        lastMessageID: nil,
        lastMessageTime: sortTimestamp,
        lastMessageDigest: "Digest \(title)",
        unreadCount: 0,
        isPinned: isPinned,
        isMuted: false,
        isHidden: false,
        sortTimestamp: sortTimestamp,
        updatedAt: sortTimestamp,
        createdAt: sortTimestamp
    )
}
