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

    @Test func messageRepositoryUpdatesSendStatusAndFindsMessageByID() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "status_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "status_conversation", userID: "status_user", title: "Status", sortTimestamp: 1)
        )

        let insertedMessage = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "status_user",
                conversationID: "status_conversation",
                senderID: "status_user",
                text: "Status update",
                localTime: 400,
                messageID: "status_message",
                clientMessageID: "status_client",
                sortSequence: 400
            )
        )

        try await repository.updateMessageSendStatus(
            messageID: insertedMessage.id,
            status: .success,
            ack: MessageSendAck(serverMessageID: "server_status", sequence: 401, serverTime: 401)
        )

        let updatedMessage = try await repository.message(messageID: insertedMessage.id)
        let missingMessage = try await repository.message(messageID: "missing_message")

        #expect(updatedMessage?.sendStatus == .success)
        #expect(missingMessage == nil)
    }

    @Test func chatUseCaseLoadsInitialMessagesInAscendingOrder() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "chat_order_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "chat_order_conversation", userID: "chat_order_user", title: "Chat", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "chat_order_user",
                conversationID: "chat_order_conversation",
                senderID: "chat_order_user",
                text: "First",
                localTime: 100,
                messageID: "chat_first",
                clientMessageID: "chat_first_client",
                sortSequence: 100
            )
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "chat_order_user",
                conversationID: "chat_order_conversation",
                senderID: "chat_order_user",
                text: "Second",
                localTime: 200,
                messageID: "chat_second",
                clientMessageID: "chat_second_client",
                sortSequence: 200
            )
        )

        let useCase = LocalChatUseCase(
            userID: "chat_order_user",
            conversationID: "chat_order_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let page = try await useCase.loadInitialMessages()

        #expect(page.rows.map(\.text) == ["First", "Second"])
        #expect(page.hasMore == false)
        #expect(page.nextBeforeSortSequence == 100)
    }

    @Test func chatUseCaseInitialPageReturnsLatestFiftyMessagesAscending() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "chat_page_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "chat_page_conversation", userID: "chat_page_user", title: "Paged", sortTimestamp: 1)
        )

        for index in 1...60 {
            _ = try await repository.insertOutgoingTextMessage(
                OutgoingTextMessageInput(
                    userID: "chat_page_user",
                    conversationID: "chat_page_conversation",
                    senderID: "chat_page_user",
                    text: "Message \(index)",
                    localTime: Int64(index),
                    messageID: MessageID(rawValue: "chat_page_\(index)"),
                    clientMessageID: "chat_page_client_\(index)",
                    sortSequence: Int64(index)
                )
            )
        }

        let useCase = LocalChatUseCase(
            userID: "chat_page_user",
            conversationID: "chat_page_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let page = try await useCase.loadInitialMessages()

        #expect(page.rows.count == 50)
        #expect(page.rows.first?.text == "Message 11")
        #expect(page.rows.last?.text == "Message 60")
        #expect(page.hasMore == true)
        #expect(page.nextBeforeSortSequence == 11)
    }

    @Test func chatUseCaseOlderPageUsesSortSequenceCursor() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "older_page_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "older_page_conversation", userID: "older_page_user", title: "Older", sortTimestamp: 1)
        )

        for index in 1...60 {
            _ = try await repository.insertOutgoingTextMessage(
                OutgoingTextMessageInput(
                    userID: "older_page_user",
                    conversationID: "older_page_conversation",
                    senderID: "older_page_user",
                    text: "Older \(index)",
                    localTime: Int64(index),
                    messageID: MessageID(rawValue: "older_page_\(index)"),
                    clientMessageID: "older_page_client_\(index)",
                    sortSequence: Int64(index)
                )
            )
        }

        let useCase = LocalChatUseCase(
            userID: "older_page_user",
            conversationID: "older_page_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let olderPage = try await useCase.loadOlderMessages(beforeSortSequence: 11, limit: 50)

        #expect(olderPage.rows.count == 10)
        #expect(olderPage.rows.first?.text == "Older 1")
        #expect(olderPage.rows.last?.text == "Older 10")
        #expect(olderPage.hasMore == false)
        #expect(olderPage.nextBeforeSortSequence == 1)
    }

    @Test func chatUseCaseSendTextYieldsSendingThenSuccess() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "chat_send_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "chat_send_conversation", userID: "chat_send_user", title: "Send", sortTimestamp: 1)
        )

        let useCase = LocalChatUseCase(
            userID: "chat_send_user",
            conversationID: "chat_send_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let rows = try await collectRows(from: useCase.sendText("Hello mock ack"))
        let storedMessage = try await repository.message(messageID: rows[0].id)

        #expect(rows.count == 2)
        #expect(rows[0].statusText == "Sending")
        #expect(rows[1].statusText == nil)
        #expect(storedMessage?.sendStatus == .success)
    }

    @Test func chatUseCaseDoesNotSendBlankText() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "blank_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "blank_conversation", userID: "blank_user", title: "Blank", sortTimestamp: 1)
        )

        let useCase = LocalChatUseCase(
            userID: "blank_user",
            conversationID: "blank_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let rows = try await collectRows(from: useCase.sendText("   \n  "))
        let messages = try await repository.listMessages(conversationID: "blank_conversation", limit: 20, beforeSortSeq: nil)

        #expect(rows.isEmpty)
        #expect(messages.isEmpty)
    }

    @Test func chatUseCaseResendsFailedTextWithoutDuplicatingMessage() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "resend_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "resend_conversation", userID: "resend_user", title: "Resend", sortTimestamp: 1)
        )

        let failingUseCase = LocalChatUseCase(
            userID: "resend_user",
            conversationID: "resend_conversation",
            repository: repository,
            sendService: MockMessageSendService(result: .failure, delayNanoseconds: 0)
        )
        let failedRows = try await collectRows(from: failingUseCase.sendText("Retry me"))
        let failedMessageID = failedRows[0].id
        let failedMessage = try await repository.message(messageID: failedMessageID)!

        let retryingUseCase = LocalChatUseCase(
            userID: "resend_user",
            conversationID: "resend_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let retryRows = try await collectRows(from: retryingUseCase.resend(messageID: failedMessageID))
        let storedMessages = try await repository.listMessages(conversationID: "resend_conversation", limit: 20, beforeSortSeq: nil)
        let resentMessage = try await repository.message(messageID: failedMessageID)!

        #expect(failedRows.map(\.statusText) == ["Sending", "Failed"])
        #expect(failedRows.last?.canRetry == true)
        #expect(retryRows.map(\.statusText) == ["Sending", nil])
        #expect(storedMessages.count == 1)
        #expect(resentMessage.sendStatus == .success)
        #expect(resentMessage.clientMessageID == failedMessage.clientMessageID)
    }

    @Test func repositoryDeletesMessageAndRefreshesConversationSummary() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "delete_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "delete_conversation", userID: "delete_user", title: "Delete", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "delete_user",
                conversationID: "delete_conversation",
                senderID: "delete_user",
                text: "First visible",
                localTime: 100,
                messageID: "delete_first",
                clientMessageID: "delete_first_client",
                sortSequence: 100
            )
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "delete_user",
                conversationID: "delete_conversation",
                senderID: "delete_user",
                text: "Delete me",
                localTime: 200,
                messageID: "delete_second",
                clientMessageID: "delete_second_client",
                sortSequence: 200
            )
        )

        try await repository.markMessageDeleted(messageID: "delete_second", userID: "delete_user")

        let messages = try await repository.listMessages(conversationID: "delete_conversation", limit: 20, beforeSortSeq: nil)
        let conversations = try await repository.listConversations(for: "delete_user")

        #expect(messages.map(\.id.rawValue) == ["delete_first"])
        #expect(conversations.first?.lastMessageDigest == "First visible")
    }

    @Test func repositoryRevokesMessageAndPersistsReplacementText() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "revoke_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "revoke_conversation", userID: "revoke_user", title: "Revoke", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "revoke_user",
                conversationID: "revoke_conversation",
                senderID: "revoke_user",
                text: "Secret",
                localTime: 300,
                messageID: "revoke_message",
                clientMessageID: "revoke_client",
                sortSequence: 300
            )
        )

        let revokedMessage = try await repository.revokeMessage(
            messageID: "revoke_message",
            userID: "revoke_user",
            replacementText: "你撤回了一条消息"
        )
        let reloadedMessage = try await repository.message(messageID: "revoke_message")!
        let conversations = try await repository.listConversations(for: "revoke_user")

        #expect(revokedMessage.isRevoked)
        #expect(reloadedMessage.isRevoked)
        #expect(reloadedMessage.revokeReplacementText == "你撤回了一条消息")
        #expect(conversations.first?.lastMessageDigest == "你撤回了一条消息")
    }

    @Test func draftIsPersistedAndPrioritizedInConversationList() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "draft_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let repository = try await storeProvider.repository()
        try await repository.saveDraft(
            conversationID: "system_release",
            userID: "draft_user",
            text: "Remember this"
        )

        let draftText = try await repository.draft(conversationID: "system_release", userID: "draft_user")
        let rows = try await LocalConversationListUseCase(
            userID: "draft_user",
            storeProvider: storeProvider
        ).loadConversations()
        let draftRowIndex = rows.firstIndex { $0.id == "system_release" }
        let otherUnpinnedRowIndex = rows.firstIndex { $0.id == "group_core" }

        #expect(draftText == "Remember this")
        #expect(draftRowIndex != nil)
        #expect(otherUnpinnedRowIndex != nil)
        #expect((draftRowIndex ?? 0) < (otherUnpinnedRowIndex ?? 0))
        #expect(rows[draftRowIndex ?? 0].subtitle == "Draft: Remember this")

        try await repository.clearDraft(conversationID: "system_release", userID: "draft_user")
        #expect(try await repository.draft(conversationID: "system_release", userID: "draft_user") == nil)
    }

    @Test func chatUseCaseMarksConversationReadWhenLoadingMessages() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "read_user")
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "read_conversation",
                userID: "read_user",
                title: "Read",
                unreadCount: 3,
                sortTimestamp: 1
            )
        )

        let useCase = LocalChatUseCase(
            userID: "read_user",
            conversationID: "read_conversation",
            repository: repository,
            conversationRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        _ = try await useCase.loadInitialMessages()
        let conversations = try await repository.listConversations(for: "read_user")

        #expect(conversations.first?.unreadCount == 0)
    }

    @MainActor
    @Test func chatViewModelCancelStopsPendingLoadUpdate() async throws {
        let viewModel = ChatViewModel(useCase: SlowChatUseCase(), title: "Cancel")

        viewModel.load()
        viewModel.cancel()
        try await Task.sleep(nanoseconds: 30_000_000)

        #expect(viewModel.currentState.phase == .loading)
        #expect(viewModel.currentState.rows.isEmpty)
    }

    @MainActor
    @Test func chatViewModelPrependsOlderMessagesWithoutDuplicates() async throws {
        let useCase = PagingStubChatUseCase(
            initialPage: ChatMessagePage(
                rows: [
                    makeChatRow(id: "message_51", text: "51", sortSequence: 51),
                    makeChatRow(id: "message_52", text: "52", sortSequence: 52)
                ],
                hasMore: true,
                nextBeforeSortSequence: 51
            ),
            olderPage: ChatMessagePage(
                rows: [
                    makeChatRow(id: "message_49", text: "49", sortSequence: 49),
                    makeChatRow(id: "message_50", text: "50", sortSequence: 50),
                    makeChatRow(id: "message_51", text: "51", sortSequence: 51)
                ],
                hasMore: false,
                nextBeforeSortSequence: 49
            )
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Paging")

        viewModel.load()
        try await Task.sleep(nanoseconds: 10_000_000)
        viewModel.loadOlderMessagesIfNeeded()
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(viewModel.currentState.rows.map(\.id.rawValue) == ["message_49", "message_50", "message_51", "message_52"])
        #expect(viewModel.currentState.hasMoreOlderMessages == false)
        #expect(viewModel.currentState.isLoadingOlderMessages == false)
        #expect(useCase.loadOlderCallCount == 1)
    }

    @MainActor
    @Test func chatViewModelDoesNotRequestOlderMessagesWhenPageIsExhausted() async throws {
        let useCase = PagingStubChatUseCase(
            initialPage: ChatMessagePage(
                rows: [makeChatRow(id: "only_message", text: "Only", sortSequence: 1)],
                hasMore: false,
                nextBeforeSortSequence: 1
            ),
            olderPage: ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "No More")

        viewModel.load()
        try await Task.sleep(nanoseconds: 10_000_000)
        viewModel.loadOlderMessagesIfNeeded()
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(viewModel.currentState.rows.map(\.id.rawValue) == ["only_message"])
        #expect(useCase.loadOlderCallCount == 0)
    }

    @MainActor
    @Test func chatViewModelPaginationFailureKeepsCurrentRows() async throws {
        let useCase = PagingStubChatUseCase(
            initialPage: ChatMessagePage(
                rows: [makeChatRow(id: "current_message", text: "Current", sortSequence: 10)],
                hasMore: true,
                nextBeforeSortSequence: 10
            ),
            olderPage: ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil),
            olderError: TestChatError.paginationFailed
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Failure")

        viewModel.load()
        try await Task.sleep(nanoseconds: 10_000_000)
        viewModel.loadOlderMessagesIfNeeded()
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(viewModel.currentState.rows.map(\.id.rawValue) == ["current_message"])
        #expect(viewModel.currentState.phase == .loaded)
        #expect(viewModel.currentState.isLoadingOlderMessages == false)
        #expect(viewModel.currentState.paginationErrorMessage == "Unable to load older messages")
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

private struct SlowChatUseCase: ChatUseCase {
    func loadInitialMessages() async throws -> ChatMessagePage {
        try await Task.sleep(nanoseconds: 200_000_000)
        return ChatMessagePage(
            rows: [
                makeChatRow(id: "slow_message", text: "Too late", sortSequence: 1)
            ],
            hasMore: false,
            nextBeforeSortSequence: 1
        )
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

private final class PagingStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private let initialPage: ChatMessagePage
    private let olderPage: ChatMessagePage
    private let olderError: TestChatError?
    private(set) var loadOlderCallCount = 0

    init(initialPage: ChatMessagePage, olderPage: ChatMessagePage, olderError: TestChatError? = nil) {
        self.initialPage = initialPage
        self.olderPage = olderPage
        self.olderError = olderError
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        initialPage
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        loadOlderCallCount += 1

        if let olderError {
            throw olderError
        }

        return olderPage
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

private enum TestChatError: Error {
    case paginationFailed
}

private func makeChatRow(id: MessageID, text: String, sortSequence: Int64) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        text: text,
        sortSequence: sortSequence,
        timeText: "Now",
        statusText: nil,
        isOutgoing: true,
        canRetry: false,
        canDelete: true,
        canRevoke: false,
        isRevoked: false
    )
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
    unreadCount: Int = 0,
    draftText: String? = nil,
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
        unreadCount: unreadCount,
        draftText: draftText,
        isPinned: isPinned,
        isMuted: false,
        isHidden: false,
        sortTimestamp: sortTimestamp,
        updatedAt: sortTimestamp,
        createdAt: sortTimestamp
    )
}

private func collectRows(from stream: AsyncThrowingStream<ChatMessageRowState, Error>) async throws -> [ChatMessageRowState] {
    var rows: [ChatMessageRowState] = []

    for try await row in stream {
        rows.append(row)
    }

    return rows
}
