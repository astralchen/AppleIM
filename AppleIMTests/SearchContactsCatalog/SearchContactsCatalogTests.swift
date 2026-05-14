import Testing
import Foundation
import UIKit

@testable import AppleIM

extension AppleIMTests {
    @Test func emojiRepositoryListsPackagesFavoritesAndRecentPerAccount() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "emoji_user")
        let package = EmojiPackageRecord(
            packageID: "pkg_wave",
            userID: "emoji_user",
            title: "Wave Pack",
            author: "ChatBridge",
            coverURL: nil,
            localCoverPath: nil,
            version: 1,
            status: .downloaded,
            sortOrder: 1,
            createdAt: 10,
            updatedAt: 10
        )
        let wave = EmojiAssetRecord(
            emojiID: "wave",
            userID: "emoji_user",
            packageID: "pkg_wave",
            emojiType: .package,
            name: "Wave",
            md5: "wave_md5",
            localPath: "/tmp/wave.png",
            thumbPath: "/tmp/wave-thumb.png",
            cdnURL: nil,
            width: 128,
            height: 128,
            sizeBytes: 2048,
            useCount: 0,
            lastUsedAt: nil,
            isFavorite: false,
            isDeleted: false,
            extraJSON: nil,
            createdAt: 10,
            updatedAt: 10
        )
        let otherAccountEmoji = EmojiAssetRecord(
            emojiID: "other_wave",
            userID: "other_user",
            packageID: "pkg_wave",
            emojiType: .package,
            name: "Other",
            md5: nil,
            localPath: nil,
            thumbPath: nil,
            cdnURL: nil,
            width: nil,
            height: nil,
            sizeBytes: nil,
            useCount: 0,
            lastUsedAt: nil,
            isFavorite: false,
            isDeleted: false,
            extraJSON: nil,
            createdAt: 10,
            updatedAt: 10
        )

        try await repository.upsertEmojiPackage(package)
        try await repository.upsertEmojiAsset(wave)
        try await repository.upsertEmojiAsset(otherAccountEmoji)
        try await repository.setEmojiFavorite(emojiID: "wave", userID: "emoji_user", isFavorite: true, updatedAt: 20)
        try await repository.recordEmojiUsed(emojiID: "wave", userID: "emoji_user", usedAt: 30)

        let packages = try await repository.listEmojiPackages(for: "emoji_user")
        let favorites = try await repository.listFavoriteEmojis(for: "emoji_user")
        let recent = try await repository.listRecentEmojis(for: "emoji_user", limit: 10)
        let otherRecent = try await repository.listRecentEmojis(for: "other_user", limit: 10)

        #expect(packages.map(\.packageID) == ["pkg_wave"])
        #expect(favorites.map(\.emojiID) == ["wave"])
        #expect(recent.map(\.emojiID) == ["wave"])
        #expect(recent.first?.useCount == 1)
        #expect(otherRecent.isEmpty)
    }

    @Test func insertingOutgoingEmojiMessagePersistsContentAndConversationDigest() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "emoji_message_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "emoji_conversation", userID: "emoji_message_user", title: "Emoji", sortTimestamp: 1)
        )

        let message = try await repository.insertOutgoingEmojiMessage(
            OutgoingEmojiMessageInput(
                userID: "emoji_message_user",
                conversationID: "emoji_conversation",
                senderID: "emoji_message_user",
                emoji: StoredEmojiContent(
                    emojiID: "smile",
                    packageID: "pkg_smile",
                    emojiType: .package,
                    name: "Smile",
                    localPath: "/tmp/smile.png",
                    thumbPath: "/tmp/smile-thumb.png",
                    cdnURL: nil,
                    width: 128,
                    height: 128,
                    sizeBytes: 1024
                ),
                localTime: 100,
                messageID: "emoji_message",
                clientMessageID: "emoji_client",
                sortSequence: 100
            )
        )
        let loaded = try await repository.message(messageID: "emoji_message")
        let conversations = try await repository.listConversations(for: "emoji_message_user")

        #expect(message.type == .emoji)
        let loadedEmoji = try requireEmojiContent(loaded)
        #expect(loadedEmoji.emojiID == "smile")
        #expect(loadedEmoji.thumbPath == "/tmp/smile-thumb.png")
        #expect(conversations.first { $0.id == "emoji_conversation" }?.lastMessageDigest == "[表情]")
    }

    @MainActor
    @Test func chatViewModelLoadsFavoritesAndSendsEmoji() async throws {
        let useCase = EmojiPanelStubChatUseCase()
        let viewModel = ChatViewModel(useCase: useCase, title: "Emoji Chat")

        viewModel.loadEmojiPanel()
        try await waitForCondition {
            viewModel.currentState.emojiPanel.packages.map(\.packageID) == ["pkg_stub"]
        }

        #expect(viewModel.currentState.emojiPanel.favoriteEmojis.map(\.emojiID) == ["favorite_stub"])
        viewModel.toggleEmojiFavorite(emojiID: "package_stub", isFavorite: true)
        try await waitForCondition {
            useCase.favoriteUpdates == ["package_stub:true"]
        }

        viewModel.sendEmoji(useCase.packageEmoji)
        try await waitForCondition {
            viewModel.currentState.rows.contains { $0.id == "sent_emoji" }
        }

        #expect(useCase.sentEmojiIDs == ["package_stub"])
        #expect(viewModel.currentState.rows.first?.content == .emoji(
            ChatMessageRowContent.EmojiContent(
                emojiID: "package_stub",
                name: "Package Stub",
                localPath: "/tmp/package.png",
                thumbPath: "/tmp/package-thumb.png",
                cdnURL: nil
            )
        ))
    }

    @Test func searchIndexRebuildIndexesContactsConversationsAndMessages() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "search_user")
        try await databaseContext.databaseActor.execute(
            """
            INSERT INTO contact (
                contact_id,
                user_id,
                wxid,
                nickname,
                remark,
                type,
                is_deleted
            ) VALUES (?, ?, ?, ?, ?, 0, 0);
            """,
            parameters: [
                .text("contact_sondra"),
                .text("search_user"),
                .text("wx_sondra"),
                .text("Sondra Search"),
                .text("Index Friend")
            ],
            paths: databaseContext.paths
        )
        try await repository.upsertConversation(
            makeConversationRecord(id: "search_conversation", userID: "search_user", title: "Bridge Search", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "search_user",
                conversationID: "search_conversation",
                senderID: "search_user",
                text: "Hello full text search",
                localTime: 100,
                messageID: "search_message",
                clientMessageID: "search_client",
                sortSequence: 100
            )
        )

        let searchIndex = SearchIndexActor(database: databaseContext.databaseActor, paths: databaseContext.paths)
        try await searchIndex.rebuildAll(userID: "search_user")

        let contactResults = try await searchIndex.search(query: "Sondra", limit: 10)
        let conversationResults = try await searchIndex.search(query: "Bridge", limit: 10)
        let messageResults = try await searchIndex.search(query: "Hello", limit: 10)

        #expect(contactResults.contains { $0.kind == .contact && $0.id == "contact_sondra" })
        #expect(conversationResults.contains { $0.kind == .conversation && $0.conversationID == "search_conversation" })
        #expect(messageResults.contains { $0.kind == .message && $0.messageID == "search_message" })
    }

    @Test func searchIndexRebuildExcludesDeletedAndRevokedMessages() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "search_filter_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "search_filter_conversation", userID: "search_filter_user", title: "Filter", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "search_filter_user",
                conversationID: "search_filter_conversation",
                senderID: "search_filter_user",
                text: "DeleteOnlyTerm",
                localTime: 100,
                messageID: "deleted_search_message",
                clientMessageID: "deleted_search_client",
                sortSequence: 100
            )
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "search_filter_user",
                conversationID: "search_filter_conversation",
                senderID: "search_filter_user",
                text: "RevokeOnlyTerm",
                localTime: 101,
                messageID: "revoked_search_message",
                clientMessageID: "revoked_search_client",
                sortSequence: 101
            )
        )
        try await repository.markMessageDeleted(messageID: "deleted_search_message", userID: "search_filter_user")
        _ = try await repository.revokeMessage(
            messageID: "revoked_search_message",
            userID: "search_filter_user",
            replacementText: "你撤回了一条消息"
        )

        let searchIndex = SearchIndexActor(database: databaseContext.databaseActor, paths: databaseContext.paths)
        try await searchIndex.rebuildAll(userID: "search_filter_user")

        let deletedResults = try await searchIndex.search(query: "DeleteOnlyTerm", limit: 10)
        let revokedResults = try await searchIndex.search(query: "RevokeOnlyTerm", limit: 10)

        #expect(deletedResults.isEmpty)
        #expect(revokedResults.isEmpty)
    }

    @Test func localSearchUseCaseReturnsGroupedResults() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let databaseActor = DatabaseActor()
        let storeProvider = ChatStoreProvider(accountID: "search_usecase_user", storageService: storageService, database: databaseActor)
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(id: "usecase_search_conversation", userID: "search_usecase_user", title: "UseCase Bridge", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "search_usecase_user",
                conversationID: "usecase_search_conversation",
                senderID: "search_usecase_user",
                text: "UseCase message body",
                localTime: 200,
                messageID: "usecase_search_message",
                clientMessageID: "usecase_search_client",
                sortSequence: 200
            )
        )

        let useCase = LocalSearchUseCase(userID: "search_usecase_user", storeProvider: storeProvider)
        try await useCase.rebuildIndex()

        let bridgeResults = try await useCase.search(query: "UseCase")
        let messageResults = try await useCase.search(query: "body")

        #expect(bridgeResults.conversations.contains { $0.conversationID == "usecase_search_conversation" })
        #expect(messageResults.messages.contains { $0.messageID == "usecase_search_message" })
    }

    @Test func bundleContactCatalogReadsContactsForAccount() async throws {
        let catalog = BundleContactCatalog(resourceURL: try makeMockContactsFile())

        let contacts = try await catalog.contacts(for: "mock_user")

        #expect(contacts.map(\.contactID.rawValue) == ["contact_sondra", "group_core_contact"])
        #expect(contacts.first?.displayName == "Sondra")
        #expect(contacts.first?.type == .friend)
        #expect(contacts.last?.type == .group)
    }

    @Test func bundleDemoDataCatalogReadsAccountDataFromJSON() async throws {
        let catalog = BundleDemoDataCatalog(resourceURL: try makeMockDemoDataFile(messageCount: 3))

        let data = try await catalog.demoData(for: "mock_user", now: 10_000)

        #expect(data.conversations.map(\.id.rawValue) == ["single_sondra", "group_core", "system_release"])
        #expect(data.messages.map(\.messageID.rawValue) == [
            "seed_single_sondra_1",
            "seed_single_sondra_2",
            "seed_single_sondra_3"
        ])
        #expect(data.messages.first?.localTime == 9_998)
        #expect(data.messages.last?.sortSequence == 10_000)
        #expect(data.messages.last?.direction == .incoming)
        #expect(data.groupMembers.map(\.memberID.rawValue).contains("sondra"))
        #expect(data.groupAnnouncements.first?.conversationID == "group_core")
    }

    @Test func bundleDemoDataCatalogReturnsEmptyDataForUnknownAccount() async throws {
        let catalog = BundleDemoDataCatalog(resourceURL: try makeMockDemoDataFile(messageCount: 3))

        let data = try await catalog.demoData(for: "missing_user", now: 10_000)

        #expect(data.conversations.isEmpty)
        #expect(data.messages.isEmpty)
        #expect(data.groupMembers.isEmpty)
        #expect(data.groupAnnouncements.isEmpty)
    }

    @Test func bundleDemoDataCatalogRejectsInvalidMessageDirection() async throws {
        let catalog = BundleDemoDataCatalog(resourceURL: try makeMockDemoDataFile(
            messageCount: 1,
            firstMessageDirection: "sideways"
        ))

        await #expect(throws: DemoDataCatalogError.invalidMessageDirection("sideways")) {
            _ = try await catalog.demoData(for: "mock_user", now: 10_000)
        }
    }

    @Test func demoDataSeederSeedsContactsIdempotentlyWithoutOverwritingExistingRows() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "mock_user")
        try await repository.upsertContact(
            ContactRecord(
                contactID: "contact_sondra",
                userID: "mock_user",
                wxid: "sondra",
                nickname: "Existing Sondra",
                remark: "Do Not Replace",
                avatarURL: nil,
                type: .friend,
                isStarred: false,
                isBlocked: false,
                isDeleted: false,
                source: nil,
                extraJSON: nil,
                updatedAt: 1,
                createdAt: 1
            )
        )

        try await DemoDataSeeder.seedContactsIfNeeded(
            repository: repository,
            userID: "mock_user",
            catalog: BundleContactCatalog(resourceURL: try makeMockContactsFile())
        )
        try await DemoDataSeeder.seedContactsIfNeeded(
            repository: repository,
            userID: "mock_user",
            catalog: BundleContactCatalog(resourceURL: try makeMockContactsFile())
        )

        let contacts = try await repository.listContacts(for: "mock_user")
        let existing = try #require(contacts.first { $0.contactID == "contact_sondra" })

        #expect(contacts.count == 1)
        #expect(existing.displayName == "Do Not Replace")
        #expect(existing.isStarred == false)
    }

    @Test func demoDataSeederSeedsContactsFromJSONWhenAccountHasNoContacts() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "mock_user")

        try await DemoDataSeeder.seedContactsIfNeeded(
            repository: repository,
            userID: "mock_user",
            catalog: BundleContactCatalog(resourceURL: try makeMockContactsFile())
        )

        let contacts = try await repository.listContacts(for: "mock_user")

        #expect(contacts.map(\.contactID.rawValue) == ["contact_sondra", "group_core_contact"])
        #expect(contacts.first?.displayName == "Sondra")
        #expect(contacts.last?.type == .group)
    }

    @Test func demoDataSeederSeedsConversationsAndMessagesFromJSON() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "mock_user")

        try await DemoDataSeeder.seedIfNeeded(
            repository: repository,
            userID: "mock_user",
            catalog: BundleDemoDataCatalog(resourceURL: try makeMockDemoDataFile(messageCount: 120)),
            contactCatalog: BundleContactCatalog(resourceURL: try makeMockContactsFile())
        )
        try await DemoDataSeeder.seedIfNeeded(
            repository: repository,
            userID: "mock_user",
            catalog: BundleDemoDataCatalog(resourceURL: try makeMockDemoDataFile(messageCount: 120)),
            contactCatalog: BundleContactCatalog(resourceURL: try makeMockContactsFile())
        )

        let conversations = try await repository.listConversations(for: "mock_user")
        let storedMessages = try await repository.listMessages(
            conversationID: "single_sondra",
            limit: 200,
            beforeSortSeq: nil
        )
        let groupMembers = try await repository.groupMembers(conversationID: "group_core")

        #expect(conversations.map(\.id.rawValue).contains("single_sondra"))
        #expect(conversations.first { $0.id == "single_sondra" }?.lastMessageDigest == "Sondra JSON message 120")
        #expect(storedMessages.count == 120)
        #expect(try requireTextContent(storedMessages.first) == "Sondra JSON message 120")
        #expect(try requireTextContent(storedMessages.last) == "Sondra JSON message 1")
        #expect(groupMembers.map(\.memberID.rawValue).contains("sondra"))
    }

    @Test func demoDataSeederSeedsUITestAccountAndConversationPageLoads() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "ui_test_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let useCase = LocalConversationListUseCase(userID: "ui_test_user", storeProvider: storeProvider)

        let page = try await useCase.loadConversationPage(limit: 50, after: nil)

        #expect(page.rows.map(\.id.rawValue).contains("single_sondra"))
        #expect(page.rows.map(\.title).contains("Sondra"))
    }

    @Test func localContactListUseCaseGroupsAndFiltersContacts() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "contacts_group_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertContact(makeContactRecord(contactID: "friend_normal", userID: "contacts_group_user", wxid: "normal", nickname: "Normal Friend"))
        try await repository.upsertContact(makeContactRecord(contactID: "friend_starred", userID: "contacts_group_user", wxid: "star", nickname: "Star Friend", isStarred: true))
        try await repository.upsertContact(makeContactRecord(contactID: "group_ios", userID: "contacts_group_user", wxid: "ios_group", nickname: "iOS Group", type: .group))
        try await repository.upsertContact(makeContactRecord(contactID: "deleted_friend", userID: "contacts_group_user", wxid: "deleted", nickname: "Deleted", isDeleted: true))

        let useCase = LocalContactListUseCase(userID: "contacts_group_user", storeProvider: storeProvider)
        let state = try await useCase.loadContacts(query: "")
        let filtered = try await useCase.loadContacts(query: "star")

        #expect(state.groupRows.map(\.title) == ["iOS Group"])
        #expect(state.starredRows.map(\.title) == ["Star Friend"])
        #expect(state.contactRows.map(\.title) == ["Normal Friend"])
        #expect(filtered.starredRows.map(\.title) == ["Star Friend"])
        #expect(filtered.contactRows.isEmpty)
        #expect(filtered.groupRows.isEmpty)
    }

    @MainActor
    @Test func contactListViewModelLoadsFiltersAndOpensContactConversation() async throws {
        let useCase = StubContactListUseCase()
        let viewModel = ContactListViewModel(useCase: useCase)

        viewModel.load()
        try await waitForCondition {
            viewModel.currentState.phase == .loaded
        }

        #expect(viewModel.currentState.contactRows.map(\.title) == ["Sondra"])

        viewModel.updateSearchQuery("son")
        try await waitForCondition {
            let queries = await useCase.queries
            return viewModel.currentState.query == "son" && queries.contains("son")
        }

        var openedConversation: ConversationListRowState?
        viewModel.open(row: ContactListRowState(contact: makeContactRecord(contactID: "contact_sondra", userID: "contact_vm_user", wxid: "sondra", nickname: "Sondra"))) {
            openedConversation = $0
        }
        try await waitForCondition {
            openedConversation?.id == "single_sondra"
        }
    }

    @Test func localContactListUseCaseCreatesSingleConversationForFriendAndReusesExistingConversation() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "contacts_open_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let repository = try await storeProvider.repository()
        let contact = makeContactRecord(contactID: "contact_new", userID: "contacts_open_user", wxid: "new_friend", nickname: "New Friend")
        try await repository.upsertContact(contact)

        let useCase = LocalContactListUseCase(userID: "contacts_open_user", storeProvider: storeProvider)
        let created = try await useCase.openConversation(for: contact.contactID)
        let reused = try await useCase.openConversation(for: contact.contactID)
        let conversations = try await repository.listConversations(for: "contacts_open_user")

        #expect(created.id == "single_new_friend")
        #expect(created.title == "New Friend")
        #expect(reused.id == created.id)
        #expect(conversations.filter { $0.id == "single_new_friend" }.count == 1)
    }

    @MainActor
    @Test func searchViewModelDebouncesAndIgnoresStaleResults() async throws {
        let useCase = StaleSearchUseCase()
        let viewModel = SearchViewModel(useCase: useCase, debounceMilliseconds: 5)

        viewModel.setQuery("old")
        try await Task.sleep(nanoseconds: 20_000_000)
        viewModel.setQuery("new")
        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(viewModel.currentState.phase == .loaded)
        #expect(viewModel.currentState.messages.map(\.title) == ["New Result"])
    }

    @Test func searchIndexFailureCreatesRepairPendingJob() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "search_failure_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "search_failure_conversation", userID: "search_failure_user", title: "Failure", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "search_failure_user",
                conversationID: "search_failure_conversation",
                senderID: "search_failure_user",
                text: "Repair me",
                localTime: 100,
                messageID: "search_failure_message",
                clientMessageID: "search_failure_client",
                sortSequence: 100
            )
        )
        try await waitForCondition {
            let rows = try await databaseContext.databaseActor.query(
                "SELECT COUNT(*) AS index_count FROM message_search WHERE message_id = ?;",
                parameters: [.text("search_failure_message")],
                in: .search,
                paths: databaseContext.paths
            )

            return rows.first?.int("index_count") == 1
        }
        try await waitForCondition {
            let rows = try await databaseContext.databaseActor.query(
                "SELECT COUNT(*) AS index_count FROM conversation_search WHERE conversation_id = ?;",
                parameters: [.text("search_failure_conversation")],
                in: .search,
                paths: databaseContext.paths
            )

            return rows.first?.int("index_count") == 1
        }
        try FileManager.default.removeItem(at: databaseContext.paths.searchDatabase)
        try FileManager.default.createDirectory(at: databaseContext.paths.searchDatabase, withIntermediateDirectories: false)

        let searchIndex = SearchIndexActor(database: databaseContext.databaseActor, paths: databaseContext.paths)
        await searchIndex.indexMessageBestEffort(messageID: "search_failure_message", userID: "search_failure_user")

        let repairJobs = try await repository.recoverablePendingJobs(userID: "search_failure_user", now: Int64.max)
            .filter { $0.type == .searchIndexRepair }

        #expect(repairJobs.count == 1)
        #expect(repairJobs.first?.bizKey == "message:search_failure_message")
    }
}
