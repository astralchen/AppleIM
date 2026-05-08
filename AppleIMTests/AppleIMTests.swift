//
//  AppleIMTests.swift
//  AppleIMTests
//
//  Created by Sondra on 2026/4/28.
//

import Testing
import AVFoundation
import Combine
import Foundation
import CoreGraphics
import ImageIO
import UIKit
import UniformTypeIdentifiers
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

    @MainActor
    @Test func conversationListViewModelLoadsNextPageNearBottom() async throws {
        let viewModel = ConversationListViewModel(useCase: PagedConversationListUseCase(), pageSize: 2)

        viewModel.load()
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(viewModel.currentState.rows.map(\.id.rawValue) == ["paged_0", "paged_1"])
        #expect(viewModel.currentState.hasMoreRows)

        viewModel.loadNextPageIfNeeded(visibleRowID: "paged_1")
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(viewModel.currentState.rows.map(\.id.rawValue) == ["paged_0", "paged_1", "paged_2"])
        #expect(viewModel.currentState.hasMoreRows == false)
    }

    @MainActor
    @Test func conversationListViewModelRefreshesAfterPinAndMuteChanges() async throws {
        let useCase = MutableConversationListUseCase()
        let viewModel = ConversationListViewModel(useCase: useCase)

        viewModel.load()
        try await waitForCondition {
            viewModel.currentState.phase == .loaded
        }

        viewModel.setPinned(conversationID: "mutable_conversation", isPinned: true)
        try await waitForCondition {
            viewModel.currentState.rows.first?.isPinned == true
        }

        viewModel.setMuted(conversationID: "mutable_conversation", isMuted: true)
        try await waitForCondition {
            viewModel.currentState.rows.first?.isMuted == true
        }
    }

    @MainActor
    @Test func conversationListViewControllerDoesNotReloadLoadedRowsOnRepeatedAppear() async throws {
        let useCase = CountingConversationListUseCase()
        let viewModel = ConversationListViewModel(useCase: useCase)
        let searchViewModel = SearchViewModel(useCase: EmptySearchUseCase())
        let viewController = ConversationListViewController(
            viewModel: viewModel,
            searchViewModel: searchViewModel,
            onSelectConversation: { _ in }
        )

        viewController.loadViewIfNeeded()
        viewController.viewWillAppear(false)
        try await waitForCondition {
            viewModel.currentState.phase == .loaded
        }
        viewController.viewWillAppear(false)
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(await useCase.loadPageCallCount == 1)
    }

    @MainActor
    @Test func conversationListViewControllerReportsInitialLoadFinishedOnce() async throws {
        let useCase = CountingConversationListUseCase()
        let viewModel = ConversationListViewModel(useCase: useCase)
        let searchViewModel = SearchViewModel(useCase: EmptySearchUseCase())
        var finishedCount = 0
        let viewController = ConversationListViewController(
            viewModel: viewModel,
            searchViewModel: searchViewModel,
            onSelectConversation: { _ in },
            onInitialLoadFinished: {
                finishedCount += 1
            }
        )

        viewController.loadViewIfNeeded()
        viewController.viewWillAppear(false)
        try await waitForCondition {
            finishedCount == 1
        }
        viewController.viewWillAppear(false)
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(finishedCount == 1)
    }

    @MainActor
    @Test func conversationListLoadIfNeededEmitsDiagnostics() async throws {
        let diagnostics = ConversationListLoadingDiagnosticsSpy()
        let viewModel = ConversationListViewModel(
            useCase: StubConversationListUseCase(),
            diagnostics: diagnostics
        )

        viewModel.loadIfNeeded()
        try await waitForCondition {
            viewModel.currentState.phase == .loaded
        }

        let messages = diagnostics.messages
        #expect(messages.contains { $0.contains("loadIfNeeded called") })
        #expect(messages.contains { $0.contains("initial load started") })
        #expect(messages.contains { $0.contains("initial load completed") })
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

    @Test func accountStorageAppliesFileProtectionToSensitivePaths() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let service = await FileAccountStorageService(rootDirectory: rootDirectory)
        let paths = try await service.prepareStorage(for: "protected_user")

        #if os(iOS)
        let protectedURLs = [
            paths.rootDirectory,
            paths.mainDatabase,
            paths.searchDatabase,
            paths.fileIndexDatabase,
            paths.mediaDirectory
        ]

        for url in protectedURLs {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let protection = attributes[.protectionKey] as? FileProtectionType
            #if targetEnvironment(simulator)
            if let protection {
                #expect(protection == .completeUntilFirstUserAuthentication)
            }
            #else
            #expect(protection == .completeUntilFirstUserAuthentication)
            #endif
        }

        let cacheAttributes = try FileManager.default.attributesOfItem(atPath: paths.cacheDirectory.path)
        let cacheProtection = cacheAttributes[.protectionKey] as? FileProtectionType
        #if targetEnvironment(simulator)
        if let cacheProtection {
            #expect(cacheProtection == FileProtectionType.none)
        }
        #else
        #expect(cacheProtection == FileProtectionType.none)
        #endif
        #endif
    }

    @Test func bundleAccountCatalogReadsMockAccounts() async throws {
        let bundle = Bundle.main.url(forResource: "mock_accounts", withExtension: "json") != nil
            ? Bundle.main
            : Bundle(identifier: "com.sondra.AppleIM") ?? Bundle.main
        let catalog = BundleAccountCatalog(bundle: bundle)

        let accounts = try await catalog.accounts()

        #expect(accounts.contains { $0.userID == "demo_user" })
        #expect(accounts.contains { $0.userID == "ui_test_user" })
    }

    @Test func localAccountAuthServiceLogsInWithAccountPassword() async throws {
        let catalog = BundleAccountCatalog(resourceURL: try makeMockAccountsFile())
        let authService = LocalAccountAuthService(catalog: catalog)

        let session = try await authService.login(identifier: "mock_user", password: "password123")

        #expect(session.userID == "mock_user")
        #expect(session.displayName == "Mock User")
        #expect(session.avatarURL == "https://example.com/mock-avatar.png")
        #expect(session.token.contains("mock_token_mock_user"))
    }

    @Test func accountSessionDecodesLegacyPayloadWithoutAvatarURL() throws {
        let json = """
        {
          "userID": "legacy_user",
          "displayName": "Legacy User",
          "token": "legacy_token",
          "loggedInAt": 1777777777
        }
        """

        let session = try JSONDecoder().decode(AccountSession.self, from: Data(json.utf8))

        #expect(session.userID == "legacy_user")
        #expect(session.displayName == "Legacy User")
        #expect(session.avatarURL == nil)
        #expect(session.token == "legacy_token")
    }

    @Test func localAccountAuthServiceRejectsInvalidLoginInputs() async throws {
        let catalog = BundleAccountCatalog(resourceURL: try makeMockAccountsFile())
        let authService = LocalAccountAuthService(catalog: catalog)

        await #expect(throws: AccountAuthError.emptyIdentifier) {
            _ = try await authService.login(identifier: "  ", password: "password123")
        }
        await #expect(throws: AccountAuthError.emptyPassword) {
            _ = try await authService.login(identifier: "mock_user", password: "")
        }
        await #expect(throws: AccountAuthError.accountNotFound) {
            _ = try await authService.login(identifier: "missing_user", password: "password123")
        }
        await #expect(throws: AccountAuthError.invalidPassword) {
            _ = try await authService.login(identifier: "mock_user", password: "wrong")
        }
    }

    @Test func accountSessionStoreSavesLoadsAndClearsSession() throws {
        let suiteName = "AppleIMTests.AccountSession.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let store = UserDefaultsAccountSessionStore(userDefaults: userDefaults)
        let session = AccountSession(
            userID: "session_user",
            displayName: "Session User",
            token: "mock_token",
            loggedInAt: 1_777_777_777
        )

        try store.saveSession(session)
        #expect(store.loadSession() == session)

        store.clearSession()
        #expect(store.loadSession() == nil)
    }

    @Test func clearingSessionDoesNotDeleteIsolatedAccountDirectories() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        let suiteName = "AppleIMTests.AccountSwitch.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let store = UserDefaultsAccountSessionStore(userDefaults: userDefaults)
        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)

        let firstPaths = try await storageService.prepareStorage(for: "first_account")
        let secondPaths = try await storageService.prepareStorage(for: "second_account")
        try store.saveSession(
            AccountSession(
                userID: "first_account",
                displayName: "First Account",
                token: "mock_token",
                loggedInAt: 1
            )
        )

        store.clearSession()

        #expect(store.loadSession() == nil)
        #expect(firstPaths.rootDirectory != secondPaths.rootDirectory)
        #expect(FileManager.default.fileExists(atPath: firstPaths.rootDirectory.path))
        #expect(FileManager.default.fileExists(atPath: secondPaths.rootDirectory.path))
    }

    @MainActor
    @Test func appDependencyContainerUsesLoginAccountStorage() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let container = try AppDependencyContainer(
            accountID: "login_container_user",
            storageService: storageService,
            database: DatabaseActor(),
            databaseKeyStore: InMemoryAccountDatabaseKeyStore(),
            applicationBadgeManager: CapturingApplicationBadgeManager()
        )

        let paths = try await container.prepareCurrentAccountStorage()

        #expect(container.accountID == "login_container_user")
        #expect(paths.rootDirectory.lastPathComponent == "account_login_container_user")
        #expect(FileManager.default.fileExists(atPath: paths.mainDatabase.path))
    }

    @MainActor
    @Test func appDependencyContainerDefersStartupStorageWorkUntilConversationListLoads() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = TrackingAccountStorageService(rootDirectory: rootDirectory)
        let container = try AppDependencyContainer(
            accountID: "deferred_startup_user",
            storageService: storageService,
            database: DatabaseActor(),
            databaseKeyStore: InMemoryAccountDatabaseKeyStore(),
            applicationBadgeManager: CapturingApplicationBadgeManager()
        )

        container.startNetworkRecovery()
        container.runDueJobsWhenNetworkIsReachable()
        container.refreshApplicationBadge()
        container.runStartupDataRepair()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        #expect(await storageService.prepareCallCount == 0)

        let viewController = container.makeConversationListViewController()
        viewController.loadViewIfNeeded()
        viewController.viewWillAppear(false)
        try await waitForCondition {
            await storageService.prepareCallCount == 1
        }
    }

    @MainActor
    @Test func accountDatabaseKeyStoreGeneratesStableIsolatedKeys() async throws {
        let keyStore = InMemoryAccountDatabaseKeyStore()

        let firstKey = try await keyStore.databaseKey(for: "secure_user")
        let repeatedKey = try await keyStore.databaseKey(for: "secure_user")
        let otherAccountKey = try await keyStore.databaseKey(for: "other_secure_user")
        try await keyStore.deleteDatabaseKey(for: "secure_user")
        let regeneratedKey = try await keyStore.databaseKey(for: "secure_user")

        #expect(firstKey.count == 32)
        #expect(firstKey == repeatedKey)
        #expect(firstKey != otherAccountKey)
        #expect(regeneratedKey.count == 32)
        #expect(regeneratedKey != firstKey)
    }

    @MainActor
    @Test func chatStoreProviderDeletesAccountStorageAndDatabaseKey() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let keyStore = InMemoryAccountDatabaseKeyStore()
        let storeProvider = ChatStoreProvider(
            accountID: "delete_secure_user",
            storageService: storageService,
            database: DatabaseActor(),
            databaseKeyStore: keyStore
        )

        _ = try await storeProvider.repository()
        let originalKey = try await keyStore.databaseKey(for: "delete_secure_user")
        let paths = try await storageService.prepareStorage(for: "delete_secure_user")

        try await storeProvider.deleteAccountStorage()
        let regeneratedKey = try await keyStore.databaseKey(for: "delete_secure_user")

        #expect(FileManager.default.fileExists(atPath: paths.rootDirectory.path) == false)
        #expect(regeneratedKey.count == 32)
        #expect(regeneratedKey != originalKey)
    }

    @MainActor
    @Test func chatStoreProviderInitializesEncryptedDatabasesWithSQLCipher() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let keyStore = InMemoryAccountDatabaseKeyStore()
        let databaseActor = DatabaseActor()
        let storeProvider = ChatStoreProvider(
            accountID: "cipher_user",
            storageService: storageService,
            database: databaseActor,
            databaseKeyStore: keyStore
        )

        _ = try await storeProvider.repository()
        let paths = try await storageService.prepareStorage(for: "cipher_user")

        for databaseKind in DatabaseFileKind.allCases {
            let cipherVersion = try await databaseActor.cipherVersion(in: databaseKind, paths: paths)
            #expect(cipherVersion.isEmpty == false)
        }
    }

    @MainActor
    @Test func chatStoreProviderReusesPreparedStorageAcrossRepositorySearchAndRepair() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = TrackingAccountStorageService(rootDirectory: rootDirectory)
        let keyStore = TrackingAccountDatabaseKeyStore()
        let storeProvider = ChatStoreProvider(
            accountID: "cached_bootstrap_user",
            storageService: storageService,
            database: DatabaseActor(),
            databaseKeyStore: keyStore
        )

        _ = try await storeProvider.repository()
        _ = try await storeProvider.searchIndex()
        _ = try await storeProvider.dataRepairService()

        #expect(await storageService.prepareCallCount == 1)
        #expect(await keyStore.databaseKeyCallCount == 1)
    }

    @MainActor
    @Test func chatStoreProviderSeedsDemoDataWithoutBadgeSideEffects() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let badgeManager = CapturingApplicationBadgeManager()
        let storeProvider = ChatStoreProvider(
            accountID: "seed_side_effect_user",
            storageService: storageService,
            database: DatabaseActor(),
            databaseKeyStore: InMemoryAccountDatabaseKeyStore(),
            applicationBadgeManager: badgeManager
        )

        _ = try await storeProvider.repository()

        #expect(await badgeManager.values().isEmpty)
    }

    @MainActor
    @Test func encryptedDatabaseCannotBeReadWithoutConfiguredKeyOrWithWrongKey() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let keyStore = InMemoryAccountDatabaseKeyStore()
        let encryptedDatabaseActor = DatabaseActor()
        let storeProvider = ChatStoreProvider(
            accountID: "wrong_key_user",
            storageService: storageService,
            database: encryptedDatabaseActor,
            databaseKeyStore: keyStore
        )

        _ = try await storeProvider.repository()
        let paths = try await storageService.prepareStorage(for: "wrong_key_user")

        let unconfiguredActor = DatabaseActor()
        let unconfiguredReadFailed = await databaseReadFails(using: unconfiguredActor, paths: paths)

        let wrongKeyActor = DatabaseActor()
        await wrongKeyActor.configureEncryptionKey(Data(repeating: 0x7F, count: 32), for: paths)
        let wrongKeyReadFailed = await databaseReadFails(using: wrongKeyActor, paths: paths)

        #expect(unconfiguredReadFailed)
        #expect(wrongKeyReadFailed)
    }

    @MainActor
    @Test func plaintextDatabaseMigratesToEncryptedDatabaseWithoutLosingData() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let accountID: UserID = "plaintext_migration_user"
        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let paths = try await storageService.prepareStorage(for: accountID)
        let plaintextActor = DatabaseActor()
        _ = try await plaintextActor.bootstrap(paths: paths)
        let plaintextRepository = LocalChatRepository(database: plaintextActor, paths: paths)
        try await plaintextRepository.upsertConversation(
            makeConversationRecord(
                id: "plaintext_migration_conversation",
                userID: accountID,
                title: "Migrated Conversation",
                sortTimestamp: 10
            )
        )

        let encryptedActor = DatabaseActor()
        let storeProvider = ChatStoreProvider(
            accountID: accountID,
            storageService: storageService,
            database: encryptedActor,
            databaseKeyStore: InMemoryAccountDatabaseKeyStore()
        )

        let encryptedRepository = try await storeProvider.repository()
        let conversations = try await encryptedRepository.listConversations(for: accountID)
        let cipherVersion = try await encryptedActor.cipherVersion(in: .main, paths: paths)
        let unconfiguredReadFailed = await databaseReadFails(using: DatabaseActor(), paths: paths)

        #expect(conversations.contains { $0.title == "Migrated Conversation" })
        #expect(cipherVersion.isEmpty == false)
        #expect(unconfiguredReadFailed)
    }

    @Test func databaseActorErrorDescriptionRedactsSensitiveDetails() {
        let error = DatabaseActorError.executeFailed(
            path: "/private/account_sensitive_user/main.db",
            statement: "INSERT INTO message_text (text) VALUES ('secret token message');",
            message: "failed near secret token message"
        )
        let description = String(describing: error)

        #expect(description == error.safeDescription)
        #expect(description.contains("account_sensitive_user") == false)
        #expect(description.contains("secret token message") == false)
        #expect(description.contains("INSERT INTO") == false)
        #expect(description.contains("/private/") == false)
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
        #expect(loadedMetadata.appliedScriptIDs.contains("002_notification_badge_settings"))
        #expect(mainTables.contains("migration_meta"))
        #expect(mainTables.contains("conversation"))
        #expect(mainTables.contains("message"))
        #expect(searchTables.contains("message_search"))
        #expect(searchTables.contains("contact_search"))
        #expect(searchTables.contains("conversation_search"))
        #expect(fileIndexTables.contains("file_index"))
    }

    @Test func databaseBootstrapCreatesNotificationBadgeSettingColumns() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "fresh_badge_schema_user")
        let rows = try await databaseActor.query("PRAGMA table_info(notification_setting);", paths: paths)
        let columns = Set(rows.compactMap { $0.string("name") })
        let repository = LocalChatRepository(database: databaseActor, paths: paths)
        let setting = try await repository.notificationSetting(for: "fresh_badge_schema_user")

        #expect(columns.contains("badge_enabled"))
        #expect(columns.contains("badge_include_muted"))
        #expect(setting.badgeEnabled == true)
        #expect(setting.badgeIncludeMuted == true)
    }

    @Test func databaseBootstrapMigratesLegacyNotificationBadgeSettingColumns() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let paths = try await storageService.prepareStorage(for: "legacy_badge_schema_user")
        let databaseActor = DatabaseActor()
        try await databaseActor.execute(
            """
            CREATE TABLE notification_setting (
                user_id TEXT PRIMARY KEY,
                is_enabled INTEGER DEFAULT 1,
                show_preview INTEGER DEFAULT 1,
                updated_at INTEGER
            );
            """,
            paths: paths
        )
        try await databaseActor.execute(
            """
            INSERT INTO notification_setting (user_id, is_enabled, show_preview, updated_at)
            VALUES (?, 1, 0, 10);
            """,
            parameters: [.text("legacy_badge_schema_user")],
            paths: paths
        )

        _ = try await databaseActor.bootstrap(paths: paths)
        let rows = try await databaseActor.query("PRAGMA table_info(notification_setting);", paths: paths)
        let columns = Set(rows.compactMap { $0.string("name") })
        let repository = LocalChatRepository(database: databaseActor, paths: paths)
        let setting = try await repository.notificationSetting(for: "legacy_badge_schema_user")

        #expect(columns.contains("badge_enabled"))
        #expect(columns.contains("badge_include_muted"))
        #expect(setting.showPreview == false)
        #expect(setting.badgeEnabled == true)
        #expect(setting.badgeIncludeMuted == true)
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

    @Test func conversationDAOPagesVisibleConversationsInSortOrder() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "paged_user")
        let dao = ConversationDAO(database: databaseActor, paths: paths)

        try await dao.upsert(makeConversationRecord(id: "normal_old", userID: "paged_user", title: "Old", sortTimestamp: 10))
        try await dao.upsert(makeConversationRecord(id: "normal_new", userID: "paged_user", title: "New", sortTimestamp: 30))
        try await dao.upsert(makeConversationRecord(id: "pinned_old", userID: "paged_user", title: "Pinned", isPinned: true, sortTimestamp: 20))

        let firstPage = try await dao.listConversations(for: "paged_user", limit: 2, offset: 0)
        let secondPage = try await dao.listConversations(for: "paged_user", limit: 2, offset: 2)

        #expect(firstPage.map(\.id.rawValue) == ["pinned_old", "normal_new"])
        #expect(secondPage.map(\.id.rawValue) == ["normal_old"])
    }

    @Test func conversationDAOFirstPageLoadsOneThousandConversationsUnderBudget() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "scale_user")
        let dao = ConversationDAO(database: databaseActor, paths: paths)

        for index in 0..<1_000 {
            let id = ConversationID(rawValue: String(format: "scale_%04d", index))
            try await dao.upsert(
                makeConversationRecord(
                    id: id,
                    userID: "scale_user",
                    title: "Scale \(index)",
                    isPinned: index == 0,
                    sortTimestamp: Int64(index)
                )
            )
        }

        let startedAt = Date()
        let firstPage = try await dao.listConversations(for: "scale_user", limit: 50, offset: 0)
        let elapsed = Date().timeIntervalSince(startedAt)

        #expect(firstPage.count == 50)
        #expect(firstPage.first?.id == "scale_0000")
        #expect(firstPage.dropFirst().first?.id == "scale_0999")
        #expect(elapsed < 0.5)
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

    @Test func mediaFileActorStoresOriginalAndThumbnailInsideAccountDirectory() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (_, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "media_user")
        let mediaFileActor = await MediaFileActor(paths: paths)
        let storedFile = try await mediaFileActor.saveImage(data: samplePNGData(), preferredFileExtension: "png")

        #expect(storedFile.content.localPath.hasPrefix(paths.mediaDirectory.path))
        #expect(storedFile.content.thumbnailPath.hasPrefix(paths.mediaDirectory.path))
        #expect(FileManager.default.fileExists(atPath: storedFile.content.localPath))
        #expect(FileManager.default.fileExists(atPath: storedFile.content.thumbnailPath))
        #expect(storedFile.content.width == 1)
        #expect(storedFile.content.height == 1)
        #expect(storedFile.content.format == "png")
    }

    @Test func mediaFileActorDownsamplesOriginalAndThumbnailForLargeImages() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (_, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "large_media_user")
        let processingOptions = MediaImageProcessingOptions(
            originalMaxPixelSize: 256,
            originalCompressionQuality: 0.68,
            thumbnailMaxPixelSize: 64,
            thumbnailCompressionQuality: 0.62
        )
        let mediaFileActor = await MediaFileActor(paths: paths, processingOptions: processingOptions)
        let sourceData = makeJPEGData(width: 1_024, height: 768, quality: 0.98)
        let storedFile = try await mediaFileActor.saveImage(data: sourceData, preferredFileExtension: "jpg")

        let originalDimensions = imageDimensions(atPath: storedFile.content.localPath)
        let thumbnailDimensions = imageDimensions(atPath: storedFile.content.thumbnailPath)

        #expect(max(storedFile.content.width, storedFile.content.height) <= 256)
        #expect(max(originalDimensions.width, originalDimensions.height) <= 256)
        #expect(max(thumbnailDimensions.width, thumbnailDimensions.height) <= 64)
        #expect(storedFile.content.sizeBytes < Int64(sourceData.count))
        #expect(storedFile.content.format == "jpg")
    }

    @Test func mediaFileActorStoresVoiceInsideAccountDirectory() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (_, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "voice_media_user")
        let recordingURL = try makeVoiceRecordingFile(in: rootDirectory)
        let mediaFileActor = await MediaFileActor(paths: paths)
        let storedFile = try await mediaFileActor.saveVoice(
            recordingURL: recordingURL,
            durationMilliseconds: 1_500,
            preferredFileExtension: "m4a"
        )

        #expect(storedFile.content.localPath.hasPrefix(paths.mediaDirectory.appendingPathComponent("voice").path))
        #expect(FileManager.default.fileExists(atPath: storedFile.content.localPath))
        #expect(storedFile.content.durationMilliseconds == 1_500)
        #expect(storedFile.content.sizeBytes > 0)
        #expect(storedFile.content.format == "m4a")
    }

    @Test func mediaFileActorStoresVideoAndThumbnailInsideAccountDirectory() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (_, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "video_media_user")
        let sourceVideoURL = try await makeSampleVideoFile(in: rootDirectory)
        let mediaFileActor = await MediaFileActor(paths: paths)
        let storedFile = try await mediaFileActor.saveVideo(fileURL: sourceVideoURL, preferredFileExtension: "mov")

        #expect(storedFile.content.localPath.hasPrefix(paths.mediaDirectory.appendingPathComponent("video").path))
        #expect(storedFile.content.thumbnailPath.hasPrefix(paths.mediaDirectory.appendingPathComponent("video/thumb").path))
        #expect(FileManager.default.fileExists(atPath: storedFile.content.localPath))
        #expect(FileManager.default.fileExists(atPath: storedFile.content.thumbnailPath))
        #expect(storedFile.content.durationMilliseconds >= 0)
        #expect(storedFile.content.width == 64)
        #expect(storedFile.content.height == 64)
        #expect(storedFile.content.sizeBytes > 0)
    }

    @Test func localChatRepositoryInsertsOutgoingImageMessageInTransaction() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "image_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "image_conversation", userID: "image_user", title: "Image Target", sortTimestamp: 1)
        )

        let image = StoredImageContent(
            mediaID: "media_image_1",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image/original/media_image_1.png").path,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image/thumb/media_image_1.jpg").path,
            width: 120,
            height: 80,
            sizeBytes: 512,
            format: "png"
        )
        let message = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "image_user",
                conversationID: "image_conversation",
                senderID: "image_user",
                image: image,
                localTime: 500,
                messageID: "image_message_1",
                clientMessageID: "image_client_1",
                sortSequence: 500
            )
        )
        let messages = try await repository.listMessages(conversationID: "image_conversation", limit: 20, beforeSortSeq: nil)
        let contentRows = try await databaseContext.databaseActor.query(
            "SELECT COUNT(*) AS content_count FROM message_image WHERE content_id = ?;",
            parameters: [.text("image_image_message_1")],
            paths: databaseContext.paths
        )
        let conversations = try await repository.listConversations(for: "image_user")

        #expect(message.type == .image)
        #expect(message.sendStatus == .sending)
        #expect(message.image == image)
        #expect(messages.first?.image == image)
        #expect(contentRows.first?.int("content_count") == 1)
        #expect(conversations.first?.lastMessageDigest == "[图片]")
    }

    @Test func localChatRepositoryInsertsOutgoingVoiceMessageInTransaction() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "voice_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "voice_conversation", userID: "voice_user", title: "Voice Target", sortTimestamp: 1)
        )

        let voice = StoredVoiceContent(
            mediaID: "media_voice_1",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("voice/media_voice_1.m4a").path,
            durationMilliseconds: 2_400,
            sizeBytes: 1_024,
            format: "m4a"
        )
        let message = try await repository.insertOutgoingVoiceMessage(
            OutgoingVoiceMessageInput(
                userID: "voice_user",
                conversationID: "voice_conversation",
                senderID: "voice_user",
                voice: voice,
                localTime: 510,
                messageID: "voice_message_1",
                clientMessageID: "voice_client_1",
                sortSequence: 510
            )
        )
        let messages = try await repository.listMessages(conversationID: "voice_conversation", limit: 20, beforeSortSeq: nil)
        let contentRows = try await databaseContext.databaseActor.query(
            "SELECT COUNT(*) AS content_count FROM message_voice WHERE content_id = ?;",
            parameters: [.text("voice_voice_message_1")],
            paths: databaseContext.paths
        )
        let resourceRows = try await databaseContext.databaseActor.query(
            "SELECT COUNT(*) AS resource_count FROM media_resource WHERE owner_message_id = ?;",
            parameters: [.text(message.id.rawValue)],
            paths: databaseContext.paths
        )
        let conversations = try await repository.listConversations(for: "voice_user")

        #expect(message.type == .voice)
        #expect(message.sendStatus == .sending)
        #expect(message.voice == voice)
        #expect(messages.first?.voice == voice)
        #expect(contentRows.first?.int("content_count") == 1)
        #expect(resourceRows.first?.int("resource_count") == 1)
        #expect(conversations.first?.lastMessageDigest == "[语音]")
    }

    @Test func localChatRepositoryInsertsOutgoingVideoMessageInTransaction() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "video_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "video_conversation", userID: "video_user", title: "Video Target", sortTimestamp: 1)
        )

        let video = StoredVideoContent(
            mediaID: "media_video_1",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("video/media_video_1.mov").path,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("video/thumb/media_video_1.jpg").path,
            durationMilliseconds: 1_000,
            width: 64,
            height: 64,
            sizeBytes: 2_048
        )
        let message = try await repository.insertOutgoingVideoMessage(
            OutgoingVideoMessageInput(
                userID: "video_user",
                conversationID: "video_conversation",
                senderID: "video_user",
                video: video,
                localTime: 520,
                messageID: "video_message_1",
                clientMessageID: "video_client_1",
                sortSequence: 520
            )
        )
        let messages = try await repository.listMessages(conversationID: "video_conversation", limit: 20, beforeSortSeq: nil)
        let contentRows = try await databaseContext.databaseActor.query(
            "SELECT COUNT(*) AS content_count FROM message_video WHERE content_id = ?;",
            parameters: [.text("video_video_message_1")],
            paths: databaseContext.paths
        )
        let resourceRows = try await databaseContext.databaseActor.query(
            "SELECT COUNT(*) AS resource_count FROM media_resource WHERE owner_message_id = ?;",
            parameters: [.text(message.id.rawValue)],
            paths: databaseContext.paths
        )
        let conversations = try await repository.listConversations(for: "video_user")

        #expect(message.type == .video)
        #expect(message.sendStatus == .sending)
        #expect(message.video == video)
        #expect(messages.first?.video == video)
        #expect(contentRows.first?.int("content_count") == 1)
        #expect(resourceRows.first?.int("resource_count") == 1)
        #expect(conversations.first?.lastMessageDigest == "[视频]")
    }

    @Test func localChatRepositoryIndexesOutgoingImageMediaFiles() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "image_index_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "image_index_conversation", userID: "image_index_user", title: "Image Index", sortTimestamp: 1)
        )

        let image = StoredImageContent(
            mediaID: "media_image_index",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image/original/media_image_index.png").path,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image/thumb/media_image_index.jpg").path,
            width: 120,
            height: 80,
            sizeBytes: 512,
            md5: "image-index-md5",
            format: "png"
        )
        _ = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "image_index_user",
                conversationID: "image_index_conversation",
                senderID: "image_index_user",
                image: image,
                localTime: 530,
                messageID: "image_index_message",
                clientMessageID: "image_index_client",
                sortSequence: 530
            )
        )

        let originalIndex = try await repository.mediaIndexRecord(mediaID: "media_image_index", userID: "image_index_user")
        let thumbnailIndex = try await repository.mediaIndexRecord(mediaID: "media_image_index_thumb", userID: "image_index_user")

        #expect(originalIndex?.localPath == image.localPath)
        #expect(originalIndex?.fileName == "media_image_index.png")
        #expect(originalIndex?.fileExtension == "png")
        #expect(originalIndex?.sizeBytes == 512)
        #expect(originalIndex?.md5 == "image-index-md5")
        #expect(thumbnailIndex?.localPath == image.thumbnailPath)
        #expect(thumbnailIndex?.fileName == "media_image_index.jpg")
        #expect(thumbnailIndex?.fileExtension == "jpg")
    }

    @Test func localChatRepositoryIndexesOutgoingVoiceMediaFile() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "voice_index_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "voice_index_conversation", userID: "voice_index_user", title: "Voice Index", sortTimestamp: 1)
        )

        let voice = StoredVoiceContent(
            mediaID: "media_voice_index",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("voice/media_voice_index.m4a").path,
            durationMilliseconds: 2_400,
            sizeBytes: 1_024,
            format: "m4a"
        )
        _ = try await repository.insertOutgoingVoiceMessage(
            OutgoingVoiceMessageInput(
                userID: "voice_index_user",
                conversationID: "voice_index_conversation",
                senderID: "voice_index_user",
                voice: voice,
                localTime: 540,
                messageID: "voice_index_message",
                clientMessageID: "voice_index_client",
                sortSequence: 540
            )
        )

        let voiceIndex = try await repository.mediaIndexRecord(mediaID: "media_voice_index", userID: "voice_index_user")

        #expect(voiceIndex?.localPath == voice.localPath)
        #expect(voiceIndex?.fileName == "media_voice_index.m4a")
        #expect(voiceIndex?.fileExtension == "m4a")
        #expect(voiceIndex?.sizeBytes == 1_024)
    }

    @Test func localChatRepositoryEnqueuesDownloadJobForMissingMediaWithoutDuplication() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "missing_media_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "missing_media_conversation", userID: "missing_media_user", title: "Missing Media", sortTimestamp: 1)
        )

        let missingLocalPath = databaseContext.paths.mediaDirectory.appendingPathComponent("image/original/missing_media.png").path
        let image = StoredImageContent(
            mediaID: "missing_media",
            localPath: missingLocalPath,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image/thumb/missing_media.jpg").path,
            width: 120,
            height: 80,
            sizeBytes: 512,
            format: "png"
        )
        _ = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "missing_media_user",
                conversationID: "missing_media_conversation",
                senderID: "missing_media_user",
                image: image,
                localTime: 550,
                messageID: "missing_media_message",
                clientMessageID: "missing_media_client",
                sortSequence: 550
            )
        )
        try await databaseContext.databaseActor.execute(
            """
            UPDATE media_resource
            SET remote_url = ?, download_status = ?
            WHERE media_id = ?;
            """,
            parameters: [
                .text("https://mock-cdn.chatbridge.local/image/missing_media"),
                .integer(Int64(MediaUploadStatus.success.rawValue)),
                .text("missing_media")
            ],
            paths: databaseContext.paths
        )

        let missingResources = try await repository.scanMissingMediaResources(userID: "missing_media_user")
        let firstJobs = try await repository.enqueueMediaDownloadJobsForMissingResources(userID: "missing_media_user")
        let secondJobs = try await repository.enqueueMediaDownloadJobsForMissingResources(userID: "missing_media_user")
        let pendingJobRows = try await databaseContext.databaseActor.query(
            "SELECT COUNT(*) AS job_count FROM pending_job WHERE job_type = ?;",
            parameters: [.integer(Int64(PendingJobType.mediaDownload.rawValue))],
            paths: databaseContext.paths
        )
        let resourceRows = try await databaseContext.databaseActor.query(
            "SELECT download_status FROM media_resource WHERE media_id = ?;",
            parameters: [.text("missing_media")],
            paths: databaseContext.paths
        )

        #expect(missingResources.map(\.mediaID) == ["missing_media"])
        #expect(firstJobs.count == 1)
        #expect(firstJobs.first?.id == "media_download_missing_media")
        #expect(firstJobs.first?.type == .mediaDownload)
        #expect(firstJobs.first?.payloadJSON.contains(#""localPath":"\#(missingLocalPath)""#) == true)
        #expect(secondJobs.count == 1)
        #expect(pendingJobRows.first?.int("job_count") == 1)
        #expect(resourceRows.first?.int("download_status") == MediaUploadStatus.pending.rawValue)
    }

    @Test func databaseIntegrityCheckReturnsOKForAllDatabases() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "integrity_user")

        let results = try await databaseActor.integrityCheck(paths: paths)

        #expect(results.map(\.database) == DatabaseFileKind.allCases)
        #expect(results.allSatisfy { $0.isOK })
    }

    @Test func dataRepairRebuildsClearedFTSIndex() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "repair_search_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "repair_search_conversation", userID: "repair_search_user", title: "Repair Search", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "repair_search_user",
                conversationID: "repair_search_conversation",
                senderID: "repair_search_user",
                text: "Repairable FTS body",
                localTime: 560,
                messageID: "repair_search_message",
                clientMessageID: "repair_search_client",
                sortSequence: 560
            )
        )
        try await waitForCondition {
            let rows = try await databaseContext.databaseActor.query(
                "SELECT COUNT(*) AS index_count FROM message_search WHERE message_id = ?;",
                parameters: [.text("repair_search_message")],
                in: .search,
                paths: databaseContext.paths
            )

            return rows.first?.int("index_count") == 1
        }
        try await databaseContext.databaseActor.performTransaction(
            [
                SQLiteStatement("DELETE FROM contact_search;"),
                SQLiteStatement("DELETE FROM conversation_search;"),
                SQLiteStatement("DELETE FROM message_search;")
            ],
            in: .search,
            paths: databaseContext.paths
        )

        let searchIndex = SearchIndexActor(database: databaseContext.databaseActor, paths: databaseContext.paths)
        let emptyResults = try await searchIndex.search(query: "Repairable", limit: 10)
        let repairService = DataRepairService(
            userID: "repair_search_user",
            database: databaseContext.databaseActor,
            paths: databaseContext.paths,
            repository: repository,
            searchIndex: searchIndex
        )

        let report = await repairService.run()
        let repairedResults = try await searchIndex.search(query: "Repairable", limit: 10)
        let metadata = try await databaseContext.databaseActor.loadMigrationMetadata(paths: databaseContext.paths)

        #expect(emptyResults.isEmpty)
        #expect(report.steps.first { $0.step == .ftsRebuild }?.isSuccessful == true)
        #expect(report.isSuccessful)
        #expect(repairedResults.contains { $0.kind == .message && $0.messageID == "repair_search_message" })
        #expect(metadata.ftsRebuildVersion == 1)
        #expect(metadata.lastIntegrityCheckAt != nil)
    }

    @Test func startupDataRepairSkipsWhenMaintenanceMetadataExists() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "repair_skip_user")
        let searchIndex = SearchIndexActor(database: databaseContext.databaseActor, paths: databaseContext.paths)
        let repairService = DataRepairService(
            userID: "repair_skip_user",
            database: databaseContext.databaseActor,
            paths: databaseContext.paths,
            repository: repository,
            searchIndex: searchIndex
        )

        _ = await repairService.run()
        let skippedReport = await repairService.runStartupIfNeeded()

        #expect(skippedReport == nil)
    }

    @Test func mediaIndexRebuildRestoresExistingImageAndVoiceFiles() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "repair_media_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "repair_media_conversation", userID: "repair_media_user", title: "Repair Media", sortTimestamp: 1)
        )
        let imageDirectory = databaseContext.paths.mediaDirectory.appendingPathComponent("image/original", isDirectory: true)
        let thumbnailDirectory = databaseContext.paths.mediaDirectory.appendingPathComponent("image/thumb", isDirectory: true)
        let voiceDirectory = databaseContext.paths.mediaDirectory.appendingPathComponent("voice", isDirectory: true)
        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: voiceDirectory, withIntermediateDirectories: true)
        let imageURL = imageDirectory.appendingPathComponent("repair_image.png")
        let thumbnailURL = thumbnailDirectory.appendingPathComponent("repair_image.jpg")
        let voiceURL = voiceDirectory.appendingPathComponent("repair_voice.m4a")
        try Data("image".utf8).write(to: imageURL, options: [.atomic])
        try Data("thumb".utf8).write(to: thumbnailURL, options: [.atomic])
        try Data("voice".utf8).write(to: voiceURL, options: [.atomic])

        _ = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "repair_media_user",
                conversationID: "repair_media_conversation",
                senderID: "repair_media_user",
                image: StoredImageContent(
                    mediaID: "repair_image",
                    localPath: imageURL.path,
                    thumbnailPath: thumbnailURL.path,
                    width: 120,
                    height: 80,
                    sizeBytes: 5,
                    md5: "repair-md5",
                    format: "png"
                ),
                localTime: 570,
                messageID: "repair_image_message",
                clientMessageID: "repair_image_client",
                sortSequence: 570
            )
        )
        _ = try await repository.insertOutgoingVoiceMessage(
            OutgoingVoiceMessageInput(
                userID: "repair_media_user",
                conversationID: "repair_media_conversation",
                senderID: "repair_media_user",
                voice: StoredVoiceContent(
                    mediaID: "repair_voice",
                    localPath: voiceURL.path,
                    durationMilliseconds: 2_000,
                    sizeBytes: 5,
                    format: "m4a"
                ),
                localTime: 571,
                messageID: "repair_voice_message",
                clientMessageID: "repair_voice_client",
                sortSequence: 571
            )
        )
        try await databaseContext.databaseActor.execute(
            "DELETE FROM file_index WHERE user_id = ?;",
            parameters: [.text("repair_media_user")],
            in: .fileIndex,
            paths: databaseContext.paths
        )

        let result = try await repository.rebuildMediaIndex(userID: "repair_media_user")
        let imageIndex = try await repository.mediaIndexRecord(mediaID: "repair_image", userID: "repair_media_user")
        let thumbnailIndex = try await repository.mediaIndexRecord(mediaID: "repair_image_thumb", userID: "repair_media_user")
        let voiceIndex = try await repository.mediaIndexRecord(mediaID: "repair_voice", userID: "repair_media_user")

        #expect(result == MediaIndexRebuildResult(scannedResourceCount: 2, rebuiltIndexCount: 3, missingResourceCount: 0, createdDownloadJobCount: 0))
        #expect(imageIndex?.localPath == imageURL.path)
        #expect(imageIndex?.md5 == "repair-md5")
        #expect(thumbnailIndex?.localPath == thumbnailURL.path)
        #expect(voiceIndex?.localPath == voiceURL.path)
    }

    @Test func dataRepairCreatesDownloadJobForMissingMedia() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "repair_missing_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "repair_missing_conversation", userID: "repair_missing_user", title: "Repair Missing", sortTimestamp: 1)
        )
        let missingLocalPath = databaseContext.paths.mediaDirectory.appendingPathComponent("image/original/repair_missing.png").path
        _ = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "repair_missing_user",
                conversationID: "repair_missing_conversation",
                senderID: "repair_missing_user",
                image: StoredImageContent(
                    mediaID: "repair_missing",
                    localPath: missingLocalPath,
                    thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image/thumb/repair_missing.jpg").path,
                    width: 64,
                    height: 64,
                    sizeBytes: 128,
                    format: "png"
                ),
                localTime: 580,
                messageID: "repair_missing_message",
                clientMessageID: "repair_missing_client",
                sortSequence: 580
            )
        )
        try await databaseContext.databaseActor.execute(
            """
            UPDATE media_resource
            SET remote_url = ?
            WHERE media_id = ?;
            """,
            parameters: [
                .text("https://mock-cdn.chatbridge.local/image/repair_missing"),
                .text("repair_missing")
            ],
            paths: databaseContext.paths
        )

        let repairService = DataRepairService(
            userID: "repair_missing_user",
            database: databaseContext.databaseActor,
            paths: databaseContext.paths,
            repository: repository,
            searchIndex: SearchIndexActor(database: databaseContext.databaseActor, paths: databaseContext.paths)
        )

        let report = await repairService.run()
        let job = try await repository.pendingJob(id: "media_download_repair_missing")

        #expect(report.mediaIndexRebuildResult?.missingResourceCount == 1)
        #expect(report.mediaIndexRebuildResult?.createdDownloadJobCount == 1)
        #expect(job?.type == .mediaDownload)
        #expect(job?.payloadJSON.contains(#""remoteURL":"https://mock-cdn.chatbridge.local/image/repair_missing""#) == true)
    }

    @Test func dataRepairReportsFailureWithoutThrowing() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "repair_failure_user")
        try FileManager.default.removeItem(at: databaseContext.paths.searchDatabase)
        try FileManager.default.createDirectory(at: databaseContext.paths.searchDatabase, withIntermediateDirectories: false)
        let repairService = DataRepairService(
            userID: "repair_failure_user",
            database: databaseContext.databaseActor,
            paths: databaseContext.paths,
            repository: repository,
            searchIndex: SearchIndexActor(database: databaseContext.databaseActor, paths: databaseContext.paths)
        )

        let report = await repairService.run()

        #expect(report.isSuccessful == false)
        #expect(report.steps.contains { $0.step == .integrityCheck && !$0.isSuccessful })
        #expect(report.steps.contains { $0.step == .ftsRebuild && !$0.isSuccessful })
        #expect(report.steps.contains { $0.step == .mediaIndexRebuild && $0.isSuccessful })
    }

    @Test func localChatRepositoryMarksVoiceMessagePlayed() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "voice_play_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "voice_play_conversation", userID: "voice_play_user", title: "Voice Play", sortTimestamp: 1)
        )

        let voice = StoredVoiceContent(
            mediaID: "media_voice_play",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("voice/media_voice_play.m4a").path,
            durationMilliseconds: 2_000,
            sizeBytes: 512,
            format: "m4a"
        )
        let message = try await repository.insertOutgoingVoiceMessage(
            OutgoingVoiceMessageInput(
                userID: "voice_play_user",
                conversationID: "voice_play_conversation",
                senderID: "friend_user",
                voice: voice,
                localTime: 520,
                messageID: "voice_play_message",
                clientMessageID: "voice_play_client",
                sortSequence: 520
            )
        )
        try await databaseContext.databaseActor.execute(
            "UPDATE message SET read_status = ? WHERE message_id = ?;",
            parameters: [
                .integer(Int64(MessageReadStatus.unread.rawValue)),
                .text(message.id.rawValue)
            ],
            paths: databaseContext.paths
        )

        let unreadMessage = try await repository.message(messageID: message.id)
        try await repository.markVoicePlayed(messageID: message.id)
        let playedMessage = try await repository.message(messageID: message.id)

        #expect(unreadMessage?.readStatus == .unread)
        #expect(playedMessage?.readStatus == .read)
    }

    @Test func chatUseCaseSendImageYieldsProgressThenSuccess() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "image_send_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "image_send_conversation", userID: "image_send_user", title: "Image Send", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let useCase = LocalChatUseCase(
            userID: "image_send_user",
            conversationID: "image_send_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [0.25, 0.75, 1.0], delayNanoseconds: 0)
        )

        let rows = try await collectRows(from: useCase.sendImage(data: samplePNGData(), preferredFileExtension: "png"))
        let messageID = try #require(rows.first?.id)
        let storedMessage = try await repository.message(messageID: messageID)
        let imageRows = try await databaseContext.databaseActor.query(
            "SELECT cdn_url, upload_status FROM message_image WHERE content_id = ?;",
            parameters: [.text("image_\(messageID.rawValue)")],
            paths: databaseContext.paths
        )
        let resourceRows = try await databaseContext.databaseActor.query(
            "SELECT remote_url, upload_status FROM media_resource WHERE owner_message_id = ?;",
            parameters: [.text(messageID.rawValue)],
            paths: databaseContext.paths
        )

        #expect(rows.first?.statusText == "Sending")
        #expect(rows.compactMap(\.uploadProgress) == [0.25, 0.75, 1.0])
        #expect(rows.last?.statusText == nil)
        #expect(storedMessage?.sendStatus == .success)
        #expect(storedMessage?.image?.remoteURL?.contains("mock-cdn.chatbridge.local") == true)
        #expect(imageRows.first?.int("upload_status") == MediaUploadStatus.success.rawValue)
        #expect(imageRows.first?.string("cdn_url") == storedMessage?.image?.remoteURL)
        #expect(resourceRows.first?.int("upload_status") == MediaUploadStatus.success.rawValue)
        #expect(resourceRows.first?.string("remote_url") == storedMessage?.image?.remoteURL)
    }

    @Test func chatUseCaseSendVoiceYieldsProgressThenSuccess() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "voice_send_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "voice_send_conversation", userID: "voice_send_user", title: "Voice Send", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let useCase = LocalChatUseCase(
            userID: "voice_send_user",
            conversationID: "voice_send_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [0.3, 0.6, 1.0], delayNanoseconds: 0)
        )

        let rows = try await collectRows(
            from: useCase.sendVoice(
                recording: VoiceRecordingFile(
                    fileURL: try makeVoiceRecordingFile(in: rootDirectory),
                    durationMilliseconds: 1_800,
                    fileExtension: "m4a"
                )
            )
        )
        let messageID = try #require(rows.first?.id)
        let storedMessage = try await repository.message(messageID: messageID)
        let voiceRows = try await databaseContext.databaseActor.query(
            "SELECT cdn_url, upload_status FROM message_voice WHERE content_id = ?;",
            parameters: [.text("voice_\(messageID.rawValue)")],
            paths: databaseContext.paths
        )

        #expect(rows.first?.statusText == "Sending")
        #expect(rows.first?.isVoice == true)
        #expect(rows.compactMap(\.uploadProgress) == [0.3, 0.6, 1.0])
        #expect(rows.last?.statusText == nil)
        #expect(storedMessage?.sendStatus == .success)
        #expect(storedMessage?.voice?.remoteURL?.contains("mock-cdn.chatbridge.local/voice") == true)
        #expect(voiceRows.first?.int("upload_status") == MediaUploadStatus.success.rawValue)
        #expect(voiceRows.first?.string("cdn_url") == storedMessage?.voice?.remoteURL)
    }

    @Test func chatUseCaseSendVideoYieldsProgressThenSuccess() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "video_send_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "video_send_conversation", userID: "video_send_user", title: "Video Send", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let useCase = LocalChatUseCase(
            userID: "video_send_user",
            conversationID: "video_send_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [0.2, 0.8, 1.0], delayNanoseconds: 0)
        )

        let rows = try await collectRows(
            from: useCase.sendVideo(
                fileURL: try await makeSampleVideoFile(in: rootDirectory),
                preferredFileExtension: "mov"
            )
        )
        let messageID = try #require(rows.first?.id)
        let storedMessage = try await repository.message(messageID: messageID)
        let videoRows = try await databaseContext.databaseActor.query(
            "SELECT cdn_url, upload_status FROM message_video WHERE content_id = ?;",
            parameters: [.text("video_\(messageID.rawValue)")],
            paths: databaseContext.paths
        )

        #expect(rows.first?.statusText == "Sending")
        #expect(rows.first?.isVideo == true)
        #expect(rows.first?.videoThumbnailPath != nil)
        #expect(rows.compactMap(\.uploadProgress) == [0.2, 0.8, 1.0])
        #expect(rows.last?.statusText == nil)
        #expect(storedMessage?.sendStatus == .success)
        #expect(storedMessage?.video?.remoteURL?.contains("mock-cdn.chatbridge.local/video") == true)
        #expect(videoRows.first?.int("upload_status") == MediaUploadStatus.success.rawValue)
        #expect(videoRows.first?.string("cdn_url") == storedMessage?.video?.remoteURL)
    }

    @Test func chatUseCaseDoesNotSendTooShortVoice() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "short_voice_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "short_voice_conversation", userID: "short_voice_user", title: "Short Voice", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let useCase = LocalChatUseCase(
            userID: "short_voice_user",
            conversationID: "short_voice_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [1.0], delayNanoseconds: 0)
        )

        let rows = try await collectRows(
            from: useCase.sendVoice(
                recording: VoiceRecordingFile(
                    fileURL: try makeVoiceRecordingFile(in: rootDirectory),
                    durationMilliseconds: 600,
                    fileExtension: "m4a"
                )
            )
        )
        let messages = try await repository.listMessages(conversationID: "short_voice_conversation", limit: 20, beforeSortSeq: nil)

        #expect(rows.isEmpty)
        #expect(messages.isEmpty)
    }

    @Test func chatUseCaseQueuesImageUploadJobWhenUploadFailsAndResendsWithoutDuplication() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "image_retry_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "image_retry_conversation", userID: "image_retry_user", title: "Image Retry", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let failingUseCase = LocalChatUseCase(
            userID: "image_retry_user",
            conversationID: "image_retry_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(result: .failed(.timeout), progressSteps: [0.4], delayNanoseconds: 0)
        )

        let failedRows = try await collectRows(from: failingUseCase.sendImage(data: samplePNGData(), preferredFileExtension: "png"))
        let failedMessageID = try #require(failedRows.first?.id)
        let failedMessage = try await repository.message(messageID: failedMessageID)
        let recoverableJobs = try await repository.recoverablePendingJobs(userID: "image_retry_user", now: Int64.max)

        let retryingUseCase = LocalChatUseCase(
            userID: "image_retry_user",
            conversationID: "image_retry_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [1.0], delayNanoseconds: 0)
        )
        let retryRows = try await collectRows(from: retryingUseCase.resend(messageID: failedMessageID))
        let storedMessages = try await repository.listMessages(conversationID: "image_retry_conversation", limit: 20, beforeSortSeq: nil)
        let resentMessage = try await repository.message(messageID: failedMessageID)
        let retryJob = try await repository.pendingJob(id: "image_upload_\(failedMessage?.clientMessageID ?? "")")

        #expect(failedRows.last?.statusText == "Failed")
        #expect(failedRows.last?.canRetry == true)
        #expect(failedMessage?.sendStatus == .failed)
        #expect(failedMessage?.image?.uploadStatus == .failed)
        #expect(recoverableJobs.count == 1)
        #expect(recoverableJobs.first?.type == .imageUpload)
        #expect(recoverableJobs.first?.payloadJSON.contains("timeout") == true)
        #expect(retryRows.last?.statusText == nil)
        #expect(storedMessages.count == 1)
        #expect(resentMessage?.sendStatus == .success)
        #expect(retryJob?.status == .success)
    }

    @Test func chatUseCaseQueuesVideoUploadJobWhenUploadFailsAndResendsWithoutDuplication() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "video_retry_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "video_retry_conversation", userID: "video_retry_user", title: "Video Retry", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let failingUseCase = LocalChatUseCase(
            userID: "video_retry_user",
            conversationID: "video_retry_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(result: .failed(.timeout), progressSteps: [0.4], delayNanoseconds: 0)
        )

        let failedRows = try await collectRows(
            from: failingUseCase.sendVideo(
                fileURL: try await makeSampleVideoFile(in: rootDirectory),
                preferredFileExtension: "mov"
            )
        )
        let failedMessageID = try #require(failedRows.first?.id)
        let failedMessage = try await repository.message(messageID: failedMessageID)
        let recoverableJobs = try await repository.recoverablePendingJobs(userID: "video_retry_user", now: Int64.max)

        let retryingUseCase = LocalChatUseCase(
            userID: "video_retry_user",
            conversationID: "video_retry_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [1.0], delayNanoseconds: 0)
        )
        let retryRows = try await collectRows(from: retryingUseCase.resend(messageID: failedMessageID))
        let storedMessages = try await repository.listMessages(conversationID: "video_retry_conversation", limit: 20, beforeSortSeq: nil)
        let resentMessage = try await repository.message(messageID: failedMessageID)
        let retryJob = try await repository.pendingJob(id: "video_upload_\(failedMessage?.clientMessageID ?? "")")

        #expect(failedRows.last?.statusText == "Failed")
        #expect(failedRows.last?.canRetry == true)
        #expect(failedMessage?.sendStatus == .failed)
        #expect(failedMessage?.video?.uploadStatus == .failed)
        #expect(recoverableJobs.count == 1)
        #expect(recoverableJobs.first?.type == .videoUpload)
        #expect(recoverableJobs.first?.payloadJSON.contains("timeout") == true)
        #expect(retryRows.last?.statusText == nil)
        #expect(storedMessages.count == 1)
        #expect(resentMessage?.sendStatus == .success)
        #expect(retryJob?.status == .success)
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

    @Test func localConversationListUseCaseMapsConversationAvatarURL() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "avatar_list_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "avatar_conversation",
                userID: "avatar_list_user",
                title: "Avatar Target",
                avatarURL: "https://example.com/conversation-avatar.png",
                sortTimestamp: 9_999
            )
        )
        let useCase = LocalConversationListUseCase(userID: "avatar_list_user", storeProvider: storeProvider)

        let rows = try await useCase.loadConversations()
        let avatarRow = rows.first { $0.id == "avatar_conversation" }

        #expect(avatarRow?.avatarURL == "https://example.com/conversation-avatar.png")
    }

    @Test func localConversationListUseCaseLoadsPagedRows() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "paged_usecase_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let useCase = LocalConversationListUseCase(userID: "paged_usecase_user", storeProvider: storeProvider)

        let firstPage = try await useCase.loadConversationPage(limit: 2, offset: 0)
        let secondPage = try await useCase.loadConversationPage(limit: 2, offset: 2)

        #expect(firstPage.rows.count == 2)
        #expect(firstPage.hasMore)
        #expect(secondPage.rows.count == 1)
        #expect(secondPage.hasMore == false)
    }

    @Test func localConversationListUseCaseUpdatesPinAndMuteState() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "conversation_setting_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let useCase = LocalConversationListUseCase(userID: "conversation_setting_user", storeProvider: storeProvider)

        try await useCase.setPinned(conversationID: "group_core", isPinned: true)
        try await useCase.setMuted(conversationID: "single_sondra", isMuted: true)

        let rows = try await useCase.loadConversations()
        #expect(rows.first?.id == "single_sondra")
        #expect(rows.first(where: { $0.id == "group_core" })?.isPinned == true)
        #expect(rows.first(where: { $0.id == "single_sondra" })?.isMuted == true)
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

    @Test func chatUseCaseMapsSenderAvatarURLsByMessageDirection() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "avatar_chat_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "avatar_chat_conversation", userID: "avatar_chat_user", title: "Avatar Chat", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "avatar_chat_user",
                conversationID: "avatar_chat_conversation",
                senderID: "avatar_chat_user",
                text: "From me",
                localTime: 100,
                messageID: "avatar_outgoing",
                clientMessageID: "avatar_outgoing_client",
                sortSequence: 100
            )
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "avatar_chat_user",
                conversationID: "avatar_chat_conversation",
                senderID: "friend_user",
                text: "From friend",
                localTime: 200,
                messageID: "avatar_incoming",
                clientMessageID: "avatar_incoming_client",
                sortSequence: 200
            )
        )

        let useCase = LocalChatUseCase(
            userID: "avatar_chat_user",
            conversationID: "avatar_chat_conversation",
            currentUserAvatarURL: "file:///tmp/current-avatar.png",
            conversationAvatarURL: "https://example.com/friend-avatar.png",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let page = try await useCase.loadInitialMessages()

        #expect(page.rows.first?.senderAvatarURL == "file:///tmp/current-avatar.png")
        #expect(page.rows.last?.senderAvatarURL == "https://example.com/friend-avatar.png")
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

    @Test func chatUseCasePagesThroughOneHundredThousandMessagesWithCursor() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "chat_perf_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "chat_perf_conversation", userID: "chat_perf_user", title: "Performance", sortTimestamp: 100_000)
        )
        try await seedPerformanceMessages(
            databaseContext: databaseContext,
            conversationID: "chat_perf_conversation",
            userID: "chat_perf_user",
            count: 100_000
        )

        let useCase = LocalChatUseCase(
            userID: "chat_perf_user",
            conversationID: "chat_perf_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let initialPage = try await useCase.loadInitialMessages()
        let olderPage = try await useCase.loadOlderMessages(beforeSortSequence: 99_951, limit: 50)

        #expect(initialPage.rows.count == 50)
        #expect(initialPage.rows.first?.text == "Perf Message 99951")
        #expect(initialPage.rows.last?.text == "Perf Message 100000")
        #expect(initialPage.hasMore == true)
        #expect(initialPage.nextBeforeSortSequence == 99_951)
        #expect(olderPage.rows.count == 50)
        #expect(olderPage.rows.first?.text == "Perf Message 99901")
        #expect(olderPage.rows.last?.text == "Perf Message 99950")
        #expect(olderPage.hasMore == true)
        #expect(olderPage.nextBeforeSortSequence == 99_901)
    }

    @Test func messagePaginationQueriesUseVisibleSortIndex() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "chat_plan_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "chat_plan_conversation", userID: "chat_plan_user", title: "Query Plan", sortTimestamp: 100)
        )
        try await seedPerformanceMessages(
            databaseContext: databaseContext,
            conversationID: "chat_plan_conversation",
            userID: "chat_plan_user",
            count: 100
        )

        let initialPlanRows = try await databaseContext.databaseActor.query(
            "EXPLAIN QUERY PLAN \(MessageDAO.listMessagesQuery(beforeSortSeq: nil))",
            parameters: [
                .text("chat_plan_conversation"),
                .integer(51)
            ],
            paths: databaseContext.paths
        )
        let olderPlanRows = try await databaseContext.databaseActor.query(
            "EXPLAIN QUERY PLAN \(MessageDAO.listMessagesQuery(beforeSortSeq: 51))",
            parameters: [
                .text("chat_plan_conversation"),
                .integer(51),
                .integer(51)
            ],
            paths: databaseContext.paths
        )

        let initialPlan = initialPlanRows.compactMap { $0.string("detail") }.joined(separator: "\n")
        let olderPlan = olderPlanRows.compactMap { $0.string("detail") }.joined(separator: "\n")

        #expect(initialPlan.contains("idx_message_conversation_visible_sort"))
        #expect(olderPlan.contains("idx_message_conversation_visible_sort"))
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
            pendingJobRepository: repository,
            sendService: MockMessageSendService(result: .failure(), delayNanoseconds: 0)
        )
        let failedRows = try await collectRows(from: failingUseCase.sendText("Retry me"))
        let failedMessageID = failedRows[0].id
        let failedMessage = try await repository.message(messageID: failedMessageID)!

        let retryingUseCase = LocalChatUseCase(
            userID: "resend_user",
            conversationID: "resend_conversation",
            repository: repository,
            pendingJobRepository: repository,
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

    @Test func pendingJobRepositoryUpsertsAndRestoresUnfinishedJobs() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "pending_user")
        let input = PendingJobInput(
            id: "message_resend_pending_client",
            userID: "pending_user",
            type: .messageResend,
            bizKey: "pending_client",
            payloadJSON: #"{"message_id":"pending_message","client_msg_id":"pending_client"}"#,
            maxRetryCount: 3,
            nextRetryAt: 100
        )

        let insertedJob = try await repository.upsertPendingJob(input)
        let duplicateJob = try await repository.upsertPendingJob(input)
        try await repository.updatePendingJobStatus(jobID: input.id, status: .running, nextRetryAt: 100)

        let storedJob = try await repository.pendingJob(id: input.id)
        let recoverableJobs = try await repository.recoverablePendingJobs(userID: "pending_user", now: 100)

        #expect(insertedJob.status == .pending)
        #expect(duplicateJob.id == insertedJob.id)
        #expect(storedJob?.status == .running)
        #expect(recoverableJobs.map(\.id) == [input.id])
    }

    @Test func pendingJobRepositoryTracksFailedSuccessAndCancelledStates() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "pending_state_user")
        let retryInput = PendingJobInput(
            id: "retry_state_job",
            userID: "pending_state_user",
            type: .messageResend,
            bizKey: "retry_state_client",
            payloadJSON: #"{"message_id":"retry_state_message"}"#,
            maxRetryCount: 2
        )
        let successInput = PendingJobInput(
            id: "success_state_job",
            userID: "pending_state_user",
            type: .messageResend,
            bizKey: "success_state_client",
            payloadJSON: #"{"message_id":"success_state_message"}"#
        )
        let cancelledInput = PendingJobInput(
            id: "cancelled_state_job",
            userID: "pending_state_user",
            type: .messageResend,
            bizKey: "cancelled_state_client",
            payloadJSON: #"{"message_id":"cancelled_state_message"}"#
        )

        _ = try await repository.upsertPendingJob(retryInput)
        _ = try await repository.upsertPendingJob(successInput)
        _ = try await repository.upsertPendingJob(cancelledInput)
        try await repository.updatePendingJobStatus(jobID: retryInput.id, status: .failed, nextRetryAt: 200)
        try await repository.updatePendingJobStatus(jobID: successInput.id, status: .success, nextRetryAt: nil)
        try await repository.updatePendingJobStatus(jobID: cancelledInput.id, status: .cancelled, nextRetryAt: nil)

        let retryJob = try await repository.pendingJob(id: retryInput.id)
        let successJob = try await repository.pendingJob(id: successInput.id)
        let cancelledJob = try await repository.pendingJob(id: cancelledInput.id)
        let recoverableJobs = try await repository.recoverablePendingJobs(userID: "pending_state_user", now: 200)

        #expect(retryJob?.status == .failed)
        #expect(retryJob?.retryCount == 1)
        #expect(successJob?.status == .success)
        #expect(cancelledJob?.status == .cancelled)
        #expect(recoverableJobs.isEmpty)
    }

    @Test func chatUseCaseCreatesPendingJobWhenSendFails() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "send_pending_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "send_pending_conversation", userID: "send_pending_user", title: "Pending", sortTimestamp: 1)
        )

        let useCase = LocalChatUseCase(
            userID: "send_pending_user",
            conversationID: "send_pending_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(result: .failure(.timeout), delayNanoseconds: 0),
            retryPolicy: MessageRetryPolicy(initialDelaySeconds: 3, maxDelaySeconds: 30, maxRetryCount: 4)
        )

        let startedAt = Int64(Date().timeIntervalSince1970)
        let rows = try await collectRows(from: useCase.sendText("Queue me"))
        let failedMessage = try await repository.message(messageID: rows[0].id)!
        let recoverableJobs = try await repository.recoverablePendingJobs(userID: "send_pending_user", now: Int64.max)
        let job = recoverableJobs.first

        #expect(rows.map(\.statusText) == ["Sending", "Failed"])
        #expect(failedMessage.sendStatus == .failed)
        #expect(recoverableJobs.count == 1)
        #expect(job?.type == .messageResend)
        #expect(job?.bizKey == failedMessage.clientMessageID)
        #expect(job?.maxRetryCount == 4)
        #expect((job?.nextRetryAt ?? 0) >= startedAt + 3)
        #expect(job?.payloadJSON.contains(failedMessage.id.rawValue) == true)
        #expect(job?.payloadJSON.contains("send_pending_conversation") == true)
        #expect(job?.payloadJSON.contains("timeout") == true)
    }

    @Test func pendingMessageRetryRunnerReschedulesWeakNetworkFailuresWithBackoff() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "retry_runner_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "retry_runner_conversation", userID: "retry_runner_user", title: "Retry Runner", sortTimestamp: 1)
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "retry_runner_user",
                conversationID: "retry_runner_conversation",
                senderID: "retry_runner_user",
                text: "Retry after weak network",
                localTime: 100,
                messageID: "retry_runner_message",
                clientMessageID: "retry_runner_client",
                sortSequence: 100
            )
        )
        try await repository.updateMessageSendStatus(messageID: message.id, status: .failed, ack: nil)
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "message_resend_retry_runner_client",
                userID: "retry_runner_user",
                type: .messageResend,
                bizKey: "retry_runner_client",
                payloadJSON: #"{"messageID":"retry_runner_message","conversationID":"retry_runner_conversation","clientMessageID":"retry_runner_client","lastFailureReason":"offline"}"#,
                maxRetryCount: 3,
                nextRetryAt: 100
            )
        )
        let runner = PendingMessageRetryRunner(
            userID: "retry_runner_user",
            messageRepository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(result: .failure(.ackMissing), delayNanoseconds: 0),
            retryPolicy: MessageRetryPolicy(initialDelaySeconds: 10, maxDelaySeconds: 60, maxRetryCount: 3)
        )

        let result = try await runner.runDueJobs(now: 1_000)
        let job = try await repository.pendingJob(id: "message_resend_retry_runner_client")
        let storedMessage = try await repository.message(messageID: message.id)

        #expect(result == PendingMessageRetryRunResult(scannedJobCount: 1, attemptedCount: 1, successCount: 0, rescheduledCount: 1, exhaustedCount: 0))
        #expect(job?.status == .pending)
        #expect(job?.retryCount == 1)
        #expect(job?.nextRetryAt == 1_020)
        #expect(storedMessage?.sendStatus == .failed)
    }

    @Test func pendingMessageRetryRunnerMarksJobSuccessAfterRecoveredAck() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "retry_success_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "retry_success_conversation", userID: "retry_success_user", title: "Retry Success", sortTimestamp: 1)
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "retry_success_user",
                conversationID: "retry_success_conversation",
                senderID: "retry_success_user",
                text: "Recover ack",
                localTime: 200,
                messageID: "retry_success_message",
                clientMessageID: "retry_success_client",
                sortSequence: 200
            )
        )
        try await repository.updateMessageSendStatus(messageID: message.id, status: .failed, ack: nil)
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "message_resend_retry_success_client",
                userID: "retry_success_user",
                type: .messageResend,
                bizKey: "retry_success_client",
                payloadJSON: #"{"messageID":"retry_success_message","conversationID":"retry_success_conversation","clientMessageID":"retry_success_client","lastFailureReason":"ackMissing"}"#,
                maxRetryCount: 3,
                nextRetryAt: 100
            )
        )
        let runner = PendingMessageRetryRunner(
            userID: "retry_success_user",
            messageRepository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )

        let result = try await runner.runDueJobs(now: 100)
        let job = try await repository.pendingJob(id: "message_resend_retry_success_client")
        let storedMessage = try await repository.message(messageID: message.id)

        #expect(result.successCount == 1)
        #expect(job?.status == .success)
        #expect(storedMessage?.sendStatus == .success)
        #expect(storedMessage?.serverMessageID == "server_retry_success_message")
    }

    @Test func pendingMessageRetryRunnerStopsAtRetryLimit() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "retry_limit_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "retry_limit_conversation", userID: "retry_limit_user", title: "Retry Limit", sortTimestamp: 1)
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "retry_limit_user",
                conversationID: "retry_limit_conversation",
                senderID: "retry_limit_user",
                text: "Give up after limit",
                localTime: 300,
                messageID: "retry_limit_message",
                clientMessageID: "retry_limit_client",
                sortSequence: 300
            )
        )
        try await repository.updateMessageSendStatus(messageID: message.id, status: .failed, ack: nil)
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "message_resend_retry_limit_client",
                userID: "retry_limit_user",
                type: .messageResend,
                bizKey: "retry_limit_client",
                payloadJSON: #"{"messageID":"retry_limit_message","conversationID":"retry_limit_conversation","clientMessageID":"retry_limit_client","lastFailureReason":"timeout"}"#,
                maxRetryCount: 1,
                nextRetryAt: 100
            )
        )
        let runner = PendingMessageRetryRunner(
            userID: "retry_limit_user",
            messageRepository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(result: .failure(.timeout), delayNanoseconds: 0)
        )

        let result = try await runner.runDueJobs(now: 100)
        let job = try await repository.pendingJob(id: "message_resend_retry_limit_client")

        #expect(result.exhaustedCount == 1)
        #expect(job?.status == .failed)
        #expect(job?.retryCount == 1)
    }

    @Test func pendingMessageRetryRunnerRecoversImageUploadJob() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "image_runner_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "image_runner_conversation", userID: "image_runner_user", title: "Image Runner", sortTimestamp: 1)
        )
        let image = StoredImageContent(
            mediaID: "image_runner_media",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image_runner.png").path,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image_runner_thumb.jpg").path,
            width: 64,
            height: 64,
            sizeBytes: 256,
            format: "png"
        )
        let message = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "image_runner_user",
                conversationID: "image_runner_conversation",
                senderID: "image_runner_user",
                image: image,
                localTime: 500,
                messageID: "image_runner_message",
                clientMessageID: "image_runner_client",
                sortSequence: 500
            )
        )
        try await repository.updateImageUploadStatus(
            messageID: message.id,
            uploadStatus: .failed,
            uploadAck: nil,
            sendStatus: .failed,
            sendAck: nil,
            pendingJob: nil
        )
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "image_upload_image_runner_client",
                userID: "image_runner_user",
                type: .imageUpload,
                bizKey: "image_runner_client",
                payloadJSON: #"{"messageID":"image_runner_message","conversationID":"image_runner_conversation","clientMessageID":"image_runner_client","mediaID":"image_runner_media","lastFailureReason":"offline"}"#,
                maxRetryCount: 3,
                nextRetryAt: 100
            )
        )
        let runner = PendingMessageRetryRunner(
            userID: "image_runner_user",
            messageRepository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaUploadService: MockMediaUploadService(progressSteps: [1.0], delayNanoseconds: 0)
        )

        let result = try await runner.runDueJobs(now: 100)
        let job = try await repository.pendingJob(id: "image_upload_image_runner_client")
        let storedMessage = try await repository.message(messageID: message.id)

        #expect(result.successCount == 1)
        #expect(job?.status == .success)
        #expect(storedMessage?.sendStatus == .success)
        #expect(storedMessage?.image?.uploadStatus == .success)
        #expect(storedMessage?.image?.remoteURL?.contains("mock-cdn.chatbridge.local") == true)
    }

    @Test func pendingMessageRetryRunnerRecoversVideoUploadJob() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "video_runner_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "video_runner_conversation", userID: "video_runner_user", title: "Video Runner", sortTimestamp: 1)
        )
        let video = StoredVideoContent(
            mediaID: "video_runner_media",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("video_runner.mov").path,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("video_runner_thumb.jpg").path,
            durationMilliseconds: 1_000,
            width: 64,
            height: 64,
            sizeBytes: 512
        )
        let message = try await repository.insertOutgoingVideoMessage(
            OutgoingVideoMessageInput(
                userID: "video_runner_user",
                conversationID: "video_runner_conversation",
                senderID: "video_runner_user",
                video: video,
                localTime: 520,
                messageID: "video_runner_message",
                clientMessageID: "video_runner_client",
                sortSequence: 520
            )
        )
        try await repository.updateVideoUploadStatus(
            messageID: message.id,
            uploadStatus: .failed,
            uploadAck: nil,
            sendStatus: .failed,
            sendAck: nil,
            pendingJob: nil
        )
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "video_upload_video_runner_client",
                userID: "video_runner_user",
                type: .videoUpload,
                bizKey: "video_runner_client",
                payloadJSON: #"{"messageID":"video_runner_message","conversationID":"video_runner_conversation","clientMessageID":"video_runner_client","mediaID":"video_runner_media","lastFailureReason":"offline"}"#,
                maxRetryCount: 3,
                nextRetryAt: 100
            )
        )
        let runner = PendingMessageRetryRunner(
            userID: "video_runner_user",
            messageRepository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaUploadService: MockMediaUploadService(progressSteps: [1.0], delayNanoseconds: 0)
        )

        let result = try await runner.runDueJobs(now: 100)
        let job = try await repository.pendingJob(id: "video_upload_video_runner_client")
        let storedMessage = try await repository.message(messageID: message.id)

        #expect(result.successCount == 1)
        #expect(job?.status == .success)
        #expect(storedMessage?.sendStatus == .success)
        #expect(storedMessage?.video?.uploadStatus == .success)
        #expect(storedMessage?.video?.remoteURL?.contains("mock-cdn.chatbridge.local/video") == true)
    }

    @Test func pendingMessageRetryRunnerStopsImageUploadAtRetryLimit() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "image_limit_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "image_limit_conversation", userID: "image_limit_user", title: "Image Limit", sortTimestamp: 1)
        )
        let image = StoredImageContent(
            mediaID: "image_limit_media",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image_limit.png").path,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image_limit_thumb.jpg").path,
            width: 64,
            height: 64,
            sizeBytes: 256,
            format: "png"
        )
        let message = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "image_limit_user",
                conversationID: "image_limit_conversation",
                senderID: "image_limit_user",
                image: image,
                localTime: 600,
                messageID: "image_limit_message",
                clientMessageID: "image_limit_client",
                sortSequence: 600
            )
        )
        try await repository.updateImageUploadStatus(
            messageID: message.id,
            uploadStatus: .failed,
            uploadAck: nil,
            sendStatus: .failed,
            sendAck: nil,
            pendingJob: nil
        )
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "image_upload_image_limit_client",
                userID: "image_limit_user",
                type: .imageUpload,
                bizKey: "image_limit_client",
                payloadJSON: #"{"messageID":"image_limit_message","conversationID":"image_limit_conversation","clientMessageID":"image_limit_client","mediaID":"image_limit_media","lastFailureReason":"timeout"}"#,
                maxRetryCount: 1,
                nextRetryAt: 100
            )
        )
        let runner = PendingMessageRetryRunner(
            userID: "image_limit_user",
            messageRepository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaUploadService: MockMediaUploadService(result: .failed(.timeout), progressSteps: [0.5], delayNanoseconds: 0)
        )

        let result = try await runner.runDueJobs(now: 100)
        let job = try await repository.pendingJob(id: "image_upload_image_limit_client")
        let storedMessage = try await repository.message(messageID: message.id)

        #expect(result.exhaustedCount == 1)
        #expect(job?.status == .failed)
        #expect(job?.retryCount == 1)
        #expect(storedMessage?.sendStatus == .failed)
        #expect(storedMessage?.image?.uploadStatus == .failed)
    }

    @Test func crashRecoveryRestoresSendingTextMessageAsPendingJob() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "crash_text_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "crash_text_conversation", userID: "crash_text_user", title: "Crash Text", sortTimestamp: 1)
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "crash_text_user",
                conversationID: "crash_text_conversation",
                senderID: "crash_text_user",
                text: "Recover me after restart",
                localTime: 700,
                messageID: "crash_text_message",
                clientMessageID: "crash_text_client",
                sortSequence: 700
            )
        )

        let result = try await repository.recoverInterruptedOutgoingMessages(
            userID: "crash_text_user",
            retryPolicy: MessageRetryPolicy(initialDelaySeconds: 10, maxDelaySeconds: 60, maxRetryCount: 4),
            now: 1_000
        )
        let storedMessage = try await repository.message(messageID: message.id)
        let job = try await repository.pendingJob(id: "message_resend_crash_text_client")

        #expect(result == MessageCrashRecoveryResult(scannedMessageCount: 1, recoveredMessageCount: 1, pendingJobCount: 1, failedMessageCount: 0))
        #expect(storedMessage?.sendStatus == .pending)
        #expect(job?.status == .pending)
        #expect(job?.type == .messageResend)
        #expect(job?.bizKey == "crash_text_client")
        #expect(job?.maxRetryCount == 4)
        #expect(job?.nextRetryAt == 1_000)
        #expect(job?.payloadJSON.contains("ackMissing") == true)
    }

    @Test func crashRecoveryRestoresSendingImageMessageAsUploadJob() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "crash_image_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "crash_image_conversation", userID: "crash_image_user", title: "Crash Image", sortTimestamp: 1)
        )
        let image = StoredImageContent(
            mediaID: "crash_image_media",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("crash_image.png").path,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("crash_image_thumb.jpg").path,
            width: 64,
            height: 64,
            sizeBytes: 256,
            format: "png"
        )
        let message = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "crash_image_user",
                conversationID: "crash_image_conversation",
                senderID: "crash_image_user",
                image: image,
                localTime: 800,
                messageID: "crash_image_message",
                clientMessageID: "crash_image_client",
                sortSequence: 800
            )
        )
        try await repository.updateImageUploadStatus(
            messageID: message.id,
            uploadStatus: .uploading,
            uploadAck: nil,
            sendStatus: .sending,
            sendAck: nil,
            pendingJob: nil
        )

        let result = try await repository.recoverInterruptedOutgoingMessages(
            userID: "crash_image_user",
            retryPolicy: MessageRetryPolicy(maxRetryCount: 5),
            now: 1_100
        )
        let storedMessage = try await repository.message(messageID: message.id)
        let job = try await repository.pendingJob(id: "image_upload_crash_image_client")
        let mediaRows = try await databaseContext.databaseActor.query(
            "SELECT upload_status FROM media_resource WHERE media_id = ? LIMIT 1;",
            parameters: [.text("crash_image_media")],
            paths: databaseContext.paths
        )

        #expect(result == MessageCrashRecoveryResult(scannedMessageCount: 1, recoveredMessageCount: 1, pendingJobCount: 1, failedMessageCount: 0))
        #expect(storedMessage?.sendStatus == .pending)
        #expect(storedMessage?.image?.uploadStatus == .pending)
        #expect(mediaRows.first?.int("upload_status") == MediaUploadStatus.pending.rawValue)
        #expect(job?.status == .pending)
        #expect(job?.type == .imageUpload)
        #expect(job?.bizKey == "crash_image_client")
        #expect(job?.nextRetryAt == 1_100)
        #expect(job?.payloadJSON.contains("interrupted") == true)
    }

    @Test func crashRecoveryIsIdempotentAndPreservesTerminalJobs() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "crash_idempotent_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "crash_idempotent_conversation", userID: "crash_idempotent_user", title: "Crash Idempotent", sortTimestamp: 1)
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "crash_idempotent_user",
                conversationID: "crash_idempotent_conversation",
                senderID: "crash_idempotent_user",
                text: "Do not duplicate",
                localTime: 900,
                messageID: "crash_idempotent_message",
                clientMessageID: "crash_idempotent_client",
                sortSequence: 900
            )
        )
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "message_resend_crash_idempotent_client",
                userID: "crash_idempotent_user",
                type: .messageResend,
                bizKey: "crash_idempotent_client",
                payloadJSON: #"{"terminal":true}"#,
                maxRetryCount: 1,
                nextRetryAt: 123
            )
        )
        try await repository.updatePendingJobStatus(
            jobID: "message_resend_crash_idempotent_client",
            status: .success,
            nextRetryAt: nil
        )

        let firstResult = try await repository.recoverInterruptedOutgoingMessages(
            userID: "crash_idempotent_user",
            retryPolicy: MessageRetryPolicy(maxRetryCount: 5),
            now: 1_200
        )
        let secondResult = try await repository.recoverInterruptedOutgoingMessages(
            userID: "crash_idempotent_user",
            retryPolicy: MessageRetryPolicy(maxRetryCount: 5),
            now: 1_300
        )
        let storedMessage = try await repository.message(messageID: message.id)
        let job = try await repository.pendingJob(id: "message_resend_crash_idempotent_client")
        let countRows = try await databaseContext.databaseActor.query(
            "SELECT COUNT(*) AS job_count FROM pending_job WHERE job_id = ?;",
            parameters: [.text("message_resend_crash_idempotent_client")],
            paths: databaseContext.paths
        )

        #expect(firstResult == MessageCrashRecoveryResult(scannedMessageCount: 1, recoveredMessageCount: 1, pendingJobCount: 1, failedMessageCount: 0))
        #expect(secondResult == MessageCrashRecoveryResult(scannedMessageCount: 0, recoveredMessageCount: 0, pendingJobCount: 0, failedMessageCount: 0))
        #expect(storedMessage?.sendStatus == .pending)
        #expect(job?.status == .success)
        #expect(job?.payloadJSON == #"{"terminal":true}"#)
        #expect(job?.maxRetryCount == 1)
        #expect(countRows.first?.int("job_count") == 1)
    }

    @MainActor
    @Test func networkRecoveryCoordinatorRecoversInterruptedMessagesBeforeRetrying() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "network_crash_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(id: "network_crash_conversation", userID: "network_crash_user", title: "Network Crash", sortTimestamp: 1)
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "network_crash_user",
                conversationID: "network_crash_conversation",
                senderID: "network_crash_user",
                text: "Recover then retry",
                localTime: 950,
                messageID: "network_crash_message",
                clientMessageID: "network_crash_client",
                sortSequence: 950
            )
        )
        let monitor = TestNetworkConnectivityMonitor(isReachable: false)
        let coordinator = NetworkRecoveryCoordinator(
            userID: "network_crash_user",
            storeProvider: storeProvider,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            monitor: monitor
        )

        coordinator.start()
        monitor.setReachable(true)
        try await waitForCondition {
            let job = try await repository.pendingJob(id: "message_resend_network_crash_client")
            return job?.status == .success
        }
        coordinator.stop()

        let storedMessage = try await repository.message(messageID: message.id)

        #expect(storedMessage?.sendStatus == .success)
        #expect(storedMessage?.serverMessageID == "server_network_crash_message")
        #expect(coordinator.lastCrashRecoveryResult?.recoveredMessageCount == 1)
        #expect(coordinator.lastRunResult?.successCount == 1)
    }

    @MainActor
    @Test func networkRecoveryCoordinatorRunsPendingJobsWhenNetworkRecovers() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "network_recovery_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(id: "network_recovery_conversation", userID: "network_recovery_user", title: "Network", sortTimestamp: 1)
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "network_recovery_user",
                conversationID: "network_recovery_conversation",
                senderID: "network_recovery_user",
                text: "Recover when online",
                localTime: 400,
                messageID: "network_recovery_message",
                clientMessageID: "network_recovery_client",
                sortSequence: 400
            )
        )
        try await repository.updateMessageSendStatus(messageID: message.id, status: .failed, ack: nil)
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "message_resend_network_recovery_client",
                userID: "network_recovery_user",
                type: .messageResend,
                bizKey: "network_recovery_client",
                payloadJSON: #"{"messageID":"network_recovery_message","conversationID":"network_recovery_conversation","clientMessageID":"network_recovery_client","lastFailureReason":"offline"}"#,
                nextRetryAt: 1
            )
        )
        let monitor = TestNetworkConnectivityMonitor(isReachable: false)
        let coordinator = NetworkRecoveryCoordinator(
            userID: "network_recovery_user",
            storeProvider: storeProvider,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            monitor: monitor
        )

        coordinator.start()
        monitor.setReachable(true)
        try await waitForCondition {
            let job = try await repository.pendingJob(id: "message_resend_network_recovery_client")
            return job?.status == .success
        }
        coordinator.stop()

        let storedMessage = try await repository.message(messageID: message.id)

        #expect(storedMessage?.sendStatus == .success)
        #expect(storedMessage?.serverMessageID == "server_network_recovery_message")
        #expect(coordinator.lastRunResult?.successCount == 1)
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

    @Test func chatUseCaseMarksIncomingVoicePlayedAndClearsUnreadDot() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "voice_dot_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "voice_dot_conversation", userID: "voice_dot_user", title: "Voice Dot", sortTimestamp: 1)
        )
        let voice = StoredVoiceContent(
            mediaID: "media_voice_dot",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("voice/media_voice_dot.m4a").path,
            durationMilliseconds: 2_100,
            sizeBytes: 512,
            format: "m4a"
        )
        let insertedMessage = try await repository.insertOutgoingVoiceMessage(
            OutgoingVoiceMessageInput(
                userID: "voice_dot_user",
                conversationID: "voice_dot_conversation",
                senderID: "friend_user",
                voice: voice,
                localTime: 530,
                messageID: "voice_dot_message",
                clientMessageID: "voice_dot_client",
                sortSequence: 530
            )
        )
        try await databaseContext.databaseActor.execute(
            "UPDATE message SET read_status = ? WHERE message_id = ?;",
            parameters: [
                .integer(Int64(MessageReadStatus.unread.rawValue)),
                .text(insertedMessage.id.rawValue)
            ],
            paths: databaseContext.paths
        )

        let useCase = LocalChatUseCase(
            userID: "voice_dot_user",
            conversationID: "voice_dot_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let initialPage = try await useCase.loadInitialMessages()
        let playedRow = try await useCase.markVoicePlayed(messageID: insertedMessage.id)
        let storedMessage = try await repository.message(messageID: insertedMessage.id)

        #expect(initialPage.rows.first?.isVoiceUnplayed == true)
        #expect(initialPage.rows.first?.voiceLocalPath == voice.localPath)
        #expect(playedRow?.isVoiceUnplayed == false)
        #expect(storedMessage?.readStatus == .read)
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
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 2
            }
        }
        viewModel.loadOlderMessagesIfNeeded()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 4
            }
        }

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
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.map(\.id.rawValue) == ["current_message"]
            }
        }
        viewModel.loadOlderMessagesIfNeeded()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.paginationErrorMessage == "Unable to load older messages"
            }
        }

        #expect(viewModel.currentState.rows.map(\.id.rawValue) == ["current_message"])
        #expect(viewModel.currentState.phase == .loaded)
        #expect(viewModel.currentState.isLoadingOlderMessages == false)
        #expect(viewModel.currentState.paginationErrorMessage == "Unable to load older messages")
    }

    @MainActor
    @Test func chatViewModelCanLoadOlderMessagesAfterPaginationFailure() async throws {
        let useCase = RecoveringPagingStubChatUseCase(
            initialPage: ChatMessagePage(
                rows: [makeChatRow(id: "current_message", text: "Current", sortSequence: 10)],
                hasMore: true,
                nextBeforeSortSequence: 10
            ),
            recoveredPage: ChatMessagePage(
                rows: [makeChatRow(id: "older_message", text: "Older", sortSequence: 9)],
                hasMore: false,
                nextBeforeSortSequence: 9
            )
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Recover")

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.map(\.id.rawValue) == ["current_message"]
            }
        }
        viewModel.loadOlderMessagesIfNeeded()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.paginationErrorMessage == "Unable to load older messages"
            }
        }
        viewModel.loadOlderMessagesIfNeeded()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.map(\.id.rawValue) == ["older_message", "current_message"]
            }
        }

        #expect(viewModel.currentState.paginationErrorMessage == nil)
        #expect(viewModel.currentState.hasMoreOlderMessages == false)
        #expect(useCase.loadOlderCallCount == 2)
    }

    @MainActor
    @Test func chatViewModelAppendsImageRowAfterSendingImage() async throws {
        let useCase = ImageSendingStubChatUseCase()
        let viewModel = ChatViewModel(useCase: useCase, title: "Images")

        viewModel.sendImage(data: samplePNGData(), preferredFileExtension: "png")
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(viewModel.currentState.rows.count == 1)
        #expect(viewModel.currentState.rows.first?.imageThumbnailPath == "/tmp/chat-thumb.jpg")
        #expect(viewModel.currentState.rows.first?.isImage == true)
        #expect(useCase.sentImageCount == 1)
    }

    @MainActor
    @Test func chatViewModelSendsComposerImageThenText() async throws {
        let useCase = ComposerSendingStubChatUseCase()
        let viewModel = ChatViewModel(useCase: useCase, title: "Composer")

        viewModel.sendComposer(
            media: .image(data: samplePNGData(), preferredFileExtension: "png"),
            text: "Hello after image"
        )
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 2
            }
        }

        #expect(useCase.events == ["image:png", "text:Hello after image"])
        #expect(viewModel.currentState.rows.map(\.id.rawValue) == ["composer_image", "composer_text"])
    }

    @MainActor
    @Test func chatViewModelSendsComposerVideoOnly() async throws {
        let useCase = ComposerSendingStubChatUseCase()
        let viewModel = ChatViewModel(useCase: useCase, title: "Composer")
        let videoURL = temporaryDirectory().appendingPathComponent("composer.mov")

        viewModel.sendComposer(media: .video(fileURL: videoURL, preferredFileExtension: "mov"), text: "   ")
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 1
            }
        }

        #expect(useCase.events == ["video:mov"])
        #expect(viewModel.currentState.rows.first?.isVideo == true)
    }

    @MainActor
    @Test func chatViewModelSendsComposerMediaInSelectionOrderThenText() async throws {
        let useCase = ComposerSendingStubChatUseCase()
        let viewModel = ChatViewModel(useCase: useCase, title: "Composer")
        let videoURL = temporaryDirectory().appendingPathComponent("composer.mov")

        viewModel.sendComposer(
            media: [
                .image(data: samplePNGData(), preferredFileExtension: "png"),
                .video(fileURL: videoURL, preferredFileExtension: "mov"),
                .image(data: samplePNGData(), preferredFileExtension: "heic")
            ],
            text: "Media batch"
        )

        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            useCase.events == ["image:png", "video:mov", "image:heic", "text:Media batch"]
        }
    }

    @MainActor
    @Test func chatInputBarAttachmentPreviewControlsSendState() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))
        inputBar.layoutIfNeeded()

        #expect(button(in: inputBar, identifier: "chat.voiceButton")?.isEnabled == true)
        #expect(button(in: inputBar, identifier: "chat.sendButton") == nil)

        inputBar.setPendingAttachmentPreviews([
            ChatPendingAttachmentPreviewItem(
                id: "photo-1",
                image: nil,
                title: "Image ready",
                durationText: nil,
                isVideo: false,
                isLoading: false
            ),
            ChatPendingAttachmentPreviewItem(
                id: "video-1",
                image: nil,
                title: "Preparing video...",
                durationText: "0:03",
                isVideo: true,
                isLoading: true
            )
        ], animated: false)
        #expect(button(in: inputBar, identifier: "chat.voiceButton")?.isEnabled == false)

        inputBar.setPendingAttachmentPreviews([
            ChatPendingAttachmentPreviewItem(
                id: "photo-1",
                image: nil,
                title: "Image ready",
                durationText: nil,
                isVideo: false,
                isLoading: false
            ),
            ChatPendingAttachmentPreviewItem(
                id: "video-1",
                image: nil,
                title: "Video ready",
                durationText: "0:03",
                isVideo: true,
                isLoading: false
            )
        ], animated: false)
        #expect(button(in: inputBar, identifier: "chat.sendButton")?.isEnabled == true)

        inputBar.clearPendingAttachmentPreviews(animated: false)
        #expect(button(in: inputBar, identifier: "chat.sendButton") == nil)
        #expect(button(in: inputBar, identifier: "chat.voiceButton")?.isEnabled == true)
    }

    @MainActor
    @Test func chatInputBarRemovesSelectedAttachmentPreviewItem() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        var removedIDs: [String] = []
        inputBar.onAttachmentRemoved = { id in
            removedIDs.append(id)
        }

        inputBar.setPendingAttachmentPreviews([
            ChatPendingAttachmentPreviewItem(
                id: "photo-1",
                image: nil,
                title: "Image ready",
                durationText: nil,
                isVideo: false,
                isLoading: false
            ),
            ChatPendingAttachmentPreviewItem(
                id: "photo-2",
                image: nil,
                title: "Image ready",
                durationText: nil,
                isVideo: false,
                isLoading: false
            )
        ], animated: false)
        inputBar.layoutIfNeeded()

        button(in: inputBar, identifier: "chat.removeAttachmentButton.photo-1")?.sendActions(for: .touchUpInside)

        #expect(removedIDs == ["photo-1"])
        #expect(findView(in: inputBar, identifier: "chat.pendingAttachmentPreviewItem.photo-1") == nil)
        #expect(findView(in: inputBar, identifier: "chat.pendingAttachmentPreviewItem.photo-2") != nil)
        #expect(button(in: inputBar, identifier: "chat.sendButton")?.isEnabled == true)

        button(in: inputBar, identifier: "chat.removeAttachmentButton.photo-2")?.sendActions(for: .touchUpInside)

        #expect(removedIDs == ["photo-1", "photo-2"])
        #expect(findView(in: inputBar, identifier: "chat.pendingAttachmentPreview")?.isHidden == true)
        #expect(button(in: inputBar, identifier: "chat.voiceButton")?.isEnabled == true)
    }

    @MainActor
    @Test func chatInputBarKeepsAttachmentRemoveButtonInsidePreviewItemBounds() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 120))

        inputBar.setPendingAttachmentPreviews([
            ChatPendingAttachmentPreviewItem(
                id: "photo-1",
                image: nil,
                title: "Image ready",
                durationText: nil,
                isVideo: false,
                isLoading: false
            )
        ], animated: false)
        inputBar.layoutIfNeeded()

        let itemView = try #require(findView(in: inputBar, identifier: "chat.pendingAttachmentPreviewItem.photo-1"))
        let removeButton = try #require(button(in: inputBar, identifier: "chat.removeAttachmentButton.photo-1"))
        let scrollView = try #require(itemView.superview?.superview as? UIScrollView)
        itemView.layoutIfNeeded()
        removeButton.layoutIfNeeded()
        let buttonFrameInItem = removeButton.convert(removeButton.bounds, to: itemView)
        let buttonFrameInScrollView = removeButton.convert(removeButton.bounds, to: scrollView)

        #expect(buttonFrameInItem.width == 30)
        #expect(buttonFrameInItem.height == 30)
        #expect(buttonFrameInScrollView.minX >= 0)
        #expect(buttonFrameInScrollView.minY >= 0)
        #expect(buttonFrameInScrollView.maxX <= scrollView.bounds.maxX)
        #expect(buttonFrameInScrollView.maxY <= scrollView.bounds.maxY)
        #expect(removeButton.clipsToBounds == true)
        #expect(removeButton.layer.cornerRadius == 15)
    }

    @MainActor
    @Test func roundedConversationCellShowsFallbackAvatarWhenURLIsMissing() throws {
        let cell = RoundedConversationCell(frame: CGRect(x: 0, y: 0, width: 390, height: 82))

        cell.configure(
            row: ConversationListRowState(
                id: "fallback_avatar",
                title: "Sondra",
                avatarURL: nil,
                subtitle: "No image yet",
                timeText: "Now",
                unreadText: nil,
                isPinned: false,
                isMuted: false
            )
        )

        let avatarImageView = try #require(findView(in: cell, identifier: "conversation.avatarImageView") as? UIImageView)

        #expect(avatarImageView.image == nil)
        #expect(avatarImageView.isHidden)
        #expect(findLabel(withText: "S", in: cell) != nil)
    }

    @MainActor
    @Test func roundedConversationCellLoadsLocalAvatarImage() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let imageURL = directory.appendingPathComponent("conversation-avatar.jpg")
        try makeJPEGData(width: 4, height: 4, quality: 0.8).write(to: imageURL, options: [.atomic])
        let cell = RoundedConversationCell(frame: CGRect(x: 0, y: 0, width: 390, height: 82))

        cell.configure(
            row: ConversationListRowState(
                id: "local_avatar",
                title: "Local Avatar",
                avatarURL: imageURL.path,
                subtitle: "Image from disk",
                timeText: "Now",
                unreadText: nil,
                isPinned: false,
                isMuted: false
            )
        )

        let avatarImageView = try #require(findView(in: cell, identifier: "conversation.avatarImageView") as? UIImageView)

        #expect(avatarImageView.image != nil)
        #expect(avatarImageView.isHidden == false)
        #expect(findLabel(withText: "L", in: cell) != nil)
    }

    @MainActor
    @Test func roundedConversationCellPrepareForReuseClearsAvatarImage() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let imageURL = directory.appendingPathComponent("reuse-avatar.jpg")
        try makeJPEGData(width: 4, height: 4, quality: 0.8).write(to: imageURL, options: [.atomic])
        let cell = RoundedConversationCell(frame: CGRect(x: 0, y: 0, width: 390, height: 82))
        cell.configure(
            row: ConversationListRowState(
                id: "reuse_avatar",
                title: "Reuse Avatar",
                avatarURL: imageURL.absoluteString,
                subtitle: "Image from file URL",
                timeText: "Now",
                unreadText: nil,
                isPinned: false,
                isMuted: false
            )
        )
        let avatarImageView = try #require(findView(in: cell, identifier: "conversation.avatarImageView") as? UIImageView)
        #expect(avatarImageView.image != nil)

        cell.prepareForReuse()

        #expect(avatarImageView.image == nil)
        #expect(avatarImageView.isHidden)
    }

    @Test func photoLibrarySelectionStateKeepsSelectionOrderAndCapsAtNine() {
        var state = ChatPhotoLibrarySelectionState()
        let ids = (1...10).map { "asset-\($0)" }

        let firstNineResults = ids.prefix(9).map { state.toggle(assetID: $0) }
        let tenthResult = state.toggle(assetID: ids[9])

        #expect(firstNineResults.allSatisfy { $0 == .selected })
        #expect(tenthResult == .limitReached)
        #expect(state.selectedAssetIDs == Array(ids.prefix(9)))

        let cancelResult = state.toggle(assetID: "asset-3")

        #expect(cancelResult == .deselected)
        #expect(state.selectedAssetIDs == ["asset-1", "asset-2", "asset-4", "asset-5", "asset-6", "asset-7", "asset-8", "asset-9"])
    }

    @MainActor
    @Test func chatInputBarKeepsReturnSendsMenuAction() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))
        inputBar.layoutIfNeeded()

        let menuChildren = button(in: inputBar, identifier: "chat.moreButton")?.menu?.children ?? []

        #expect(menuChildren.contains { $0.title == "Choose Photo or Video" })
        #expect(menuChildren.contains { $0.title == "Return Sends" })
    }

    @MainActor
    @Test func chatInputBarDoesNotInstallPhotoLibraryAsTextInputView() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))
        let textView = try #require(findView(ofType: UITextView.self, in: inputBar))

        inputBar.showPhotoLibraryInput()

        #expect(textView.inputView == nil)

        inputBar.showKeyboardInput()

        #expect(textView.inputView == nil)
    }

    @MainActor
    @Test func chatPhotoLibraryInputDismissesAfterDownwardPanThreshold() throws {
        #expect(ChatPhotoLibraryInputView.shouldDismissForPan(translationY: 93, velocityY: 0))
        #expect(ChatPhotoLibraryInputView.shouldDismissForPan(translationY: 12, velocityY: 781))
        #expect(ChatPhotoLibraryInputView.shouldDismissForPan(translationY: 40, velocityY: 320) == false)
    }

    @MainActor
    @Test func chatInputBarKeepsMoreButtonOutsideInputCapsule() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))
        inputBar.layoutIfNeeded()

        let moreButton = try #require(button(in: inputBar, identifier: "chat.moreButton"))
        let inputCapsule = try #require(findView(ofType: GlassContainerView.self, in: inputBar))

        let moreFrame = moreButton.convert(moreButton.bounds, to: inputBar)
        let capsuleFrame = inputCapsule.convert(inputCapsule.bounds, to: inputBar)

        #expect(moreButton.isDescendant(of: inputCapsule) == false)
        #expect(moreFrame.maxX <= capsuleFrame.minX)
    }

    @MainActor
    @Test func chatViewModelTracksOnlyActiveVoicePlaybackRow() async throws {
        let voiceA = makeVoiceRow(id: "voice_a", sortSequence: 1, isUnplayed: true)
        let voiceB = makeVoiceRow(id: "voice_b", sortSequence: 2, isUnplayed: true)
        let useCase = VoicePlaybackStubChatUseCase(rows: [voiceA, voiceB])
        let viewModel = ChatViewModel(useCase: useCase, title: "Voice")

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 2
            }
        }
        viewModel.voicePlaybackStarted(messageID: "voice_a")
        try await waitForCondition {
            await MainActor.run {
                useCase.markedMessageIDs == ["voice_a"]
                    && viewModel.currentState.rows.first { $0.id == "voice_a" }?.isVoicePlaying == true
            }
        }

        let rowsAfterStart = viewModel.currentState.rows
        #expect(rowsAfterStart.first { $0.id == "voice_a" }?.isVoicePlaying == true)
        #expect(rowsAfterStart.first { $0.id == "voice_a" }?.isVoiceUnplayed == false)
        #expect(rowsAfterStart.first { $0.id == "voice_b" }?.isVoicePlaying == false)
        #expect(rowsAfterStart.first { $0.id == "voice_b" }?.isVoiceUnplayed == true)
        #expect(useCase.markedMessageIDs == ["voice_a"])

        viewModel.voicePlaybackStopped(messageID: "voice_a")
        #expect(viewModel.currentState.rows.first { $0.id == "voice_a" }?.isVoicePlaying == false)
    }

    @Test func syncEngineAppliesFirstMessageBatchAndStoresCheckpoint() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "sync_first_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "sync_first_conversation", userID: "sync_first_user", title: "Sync", sortTimestamp: 1)
        )

        let batch = SyncBatch(
            messages: [
                IncomingSyncMessage(
                    messageID: "sync_first_message",
                    conversationID: "sync_first_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "sync_first_client",
                    serverMessageID: "sync_first_server",
                    sequence: 10,
                    text: "First sync message",
                    serverTime: 10
                )
            ],
            nextCursor: "cursor_10",
            nextSequence: 10
        )
        let engine = SyncEngineActor(
            userID: "sync_first_user",
            store: repository,
            deltaService: StaticSyncDeltaService(batch: batch)
        )

        let result = try await engine.syncOnce()
        let messages = try await repository.listMessages(conversationID: "sync_first_conversation", limit: 20, beforeSortSeq: nil)
        let checkpoint = try await repository.syncCheckpoint(for: SyncEngineActor.messageBizKey)

        #expect(result.previousCheckpoint == nil)
        #expect(result.fetchedCount == 1)
        #expect(result.insertedCount == 1)
        #expect(result.skippedDuplicateCount == 0)
        #expect(messages.map(\.text) == ["First sync message"])
        #expect(messages.first?.sendStatus == .success)
        #expect(checkpoint?.cursor == "cursor_10")
        #expect(checkpoint?.sequence == 10)
    }

    @Test func syncEngineSkipsDuplicateClientServerAndSequenceMessages() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "sync_duplicate_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "sync_duplicate_conversation", userID: "sync_duplicate_user", title: "Duplicates", sortTimestamp: 1)
        )

        let batch = SyncBatch(
            messages: [
                IncomingSyncMessage(
                    messageID: "sync_unique_1",
                    conversationID: "sync_duplicate_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "dup_client_1",
                    serverMessageID: "dup_server_1",
                    sequence: 1,
                    text: "Unique 1",
                    serverTime: 1
                ),
                IncomingSyncMessage(
                    messageID: "sync_duplicate_client",
                    conversationID: "sync_duplicate_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "dup_client_1",
                    serverMessageID: "dup_server_2",
                    sequence: 2,
                    text: "Duplicate client",
                    serverTime: 2
                ),
                IncomingSyncMessage(
                    messageID: "sync_duplicate_server",
                    conversationID: "sync_duplicate_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "dup_client_3",
                    serverMessageID: "dup_server_1",
                    sequence: 3,
                    text: "Duplicate server",
                    serverTime: 3
                ),
                IncomingSyncMessage(
                    messageID: "sync_duplicate_sequence",
                    conversationID: "sync_duplicate_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "dup_client_4",
                    serverMessageID: "dup_server_4",
                    sequence: 1,
                    text: "Duplicate sequence",
                    serverTime: 4
                ),
                IncomingSyncMessage(
                    messageID: "sync_unique_2",
                    conversationID: "sync_duplicate_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "dup_client_5",
                    serverMessageID: "dup_server_5",
                    sequence: 5,
                    text: "Unique 2",
                    serverTime: 5
                )
            ],
            nextCursor: "cursor_5",
            nextSequence: 5
        )
        let engine = SyncEngineActor(
            userID: "sync_duplicate_user",
            store: repository,
            deltaService: StaticSyncDeltaService(batch: batch)
        )

        let result = try await engine.syncOnce()
        let messages = try await repository.listMessages(conversationID: "sync_duplicate_conversation", limit: 20, beforeSortSeq: nil)

        #expect(result.fetchedCount == 5)
        #expect(result.insertedCount == 2)
        #expect(result.skippedDuplicateCount == 3)
        #expect(messages.map(\.text) == ["Unique 2", "Unique 1"])
    }

    @Test func incomingSyncMessageSchedulesLocalNotification() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "notify_user")
        let notificationManager = CapturingLocalNotificationManager()
        let repository = LocalChatRepository(
            database: databaseActor,
            paths: paths,
            localNotificationManager: notificationManager
        )
        try await repository.upsertConversation(
            makeConversationRecord(id: "notify_conversation", userID: "notify_user", title: "Notify", sortTimestamp: 1)
        )

        _ = try await repository.applyIncomingSyncBatch(
            SyncBatch(
                messages: [
                    IncomingSyncMessage(
                        messageID: "notify_message",
                        conversationID: "notify_conversation",
                        senderID: "notify_sender",
                        serverMessageID: "notify_server",
                        sequence: 1,
                        text: "Preview body",
                        serverTime: 1
                    )
                ],
                nextCursor: "cursor_1",
                nextSequence: 1
            ),
            userID: "notify_user"
        )

        let payloads = await notificationManager.payloads()
        #expect(payloads.count == 1)
        #expect(payloads.first?.conversationID == "notify_conversation")
        #expect(payloads.first?.messageID == "notify_message")
        #expect(payloads.first?.title == "Notify")
        #expect(payloads.first?.notificationBody == "Preview body")
    }

    @Test func applicationBadgeRefreshesFromTotalUnreadIncludingMutedByDefault() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "badge_total_user")
        let badgeManager = CapturingApplicationBadgeManager()
        let repository = LocalChatRepository(
            database: databaseActor,
            paths: paths,
            applicationBadgeManager: badgeManager
        )
        try await repository.upsertConversation(
            makeConversationRecord(id: "badge_normal", userID: "badge_total_user", title: "Normal", unreadCount: 2, sortTimestamp: 1)
        )
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "badge_muted",
                userID: "badge_total_user",
                title: "Muted",
                isMuted: true,
                unreadCount: 3,
                sortTimestamp: 2
            )
        )

        let count = try await repository.refreshApplicationBadge(userID: "badge_total_user")
        let badgeValues = await badgeManager.values()

        #expect(count == 5)
        #expect(badgeValues.last == 5)
    }

    @Test func applicationBadgeCanExcludeMutedConversationUnread() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "badge_muted_policy_user")
        let badgeManager = CapturingApplicationBadgeManager()
        let repository = LocalChatRepository(
            database: databaseActor,
            paths: paths,
            applicationBadgeManager: badgeManager
        )
        try await repository.upsertConversation(
            makeConversationRecord(id: "badge_policy_normal", userID: "badge_muted_policy_user", title: "Normal", unreadCount: 2, sortTimestamp: 1)
        )
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "badge_policy_muted",
                userID: "badge_muted_policy_user",
                title: "Muted",
                isMuted: true,
                unreadCount: 3,
                sortTimestamp: 2
            )
        )

        try await repository.updateBadgeIncludeMuted(userID: "badge_muted_policy_user", includeMuted: false)
        let setting = try await repository.notificationSetting(for: "badge_muted_policy_user")
        let conversations = try await repository.listConversations(for: "badge_muted_policy_user")
        let badgeValues = await badgeManager.values()

        #expect(setting.badgeIncludeMuted == false)
        #expect(conversations.first { $0.id == "badge_policy_muted" }?.unreadCount == 3)
        #expect(badgeValues.last == 2)
    }

    @Test func markingConversationReadRefreshesApplicationBadgeToZero() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "badge_read_user")
        let badgeManager = CapturingApplicationBadgeManager()
        let repository = LocalChatRepository(
            database: databaseActor,
            paths: paths,
            applicationBadgeManager: badgeManager
        )
        try await repository.upsertConversation(
            makeConversationRecord(id: "badge_read_conversation", userID: "badge_read_user", title: "Read", unreadCount: 4, sortTimestamp: 1)
        )

        try await repository.markConversationRead(conversationID: "badge_read_conversation", userID: "badge_read_user")
        let badgeValues = await badgeManager.values()

        #expect(badgeValues.contains(4))
        #expect(badgeValues.last == 0)
    }

    @Test func disabledApplicationBadgeRefreshesToZeroWithoutClearingConversationUnread() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "badge_disabled_user")
        let badgeManager = CapturingApplicationBadgeManager()
        let repository = LocalChatRepository(
            database: databaseActor,
            paths: paths,
            applicationBadgeManager: badgeManager
        )
        try await repository.upsertConversation(
            makeConversationRecord(id: "badge_disabled_conversation", userID: "badge_disabled_user", title: "Disabled", unreadCount: 6, sortTimestamp: 1)
        )

        try await repository.updateBadgeEnabled(userID: "badge_disabled_user", isEnabled: false)
        let conversations = try await repository.listConversations(for: "badge_disabled_user")
        let badgeValues = await badgeManager.values()

        #expect(conversations.first?.unreadCount == 6)
        #expect(badgeValues.last == 0)
    }

    @Test func incomingSyncMessageCarriesLatestBadgeCountInNotificationPayload() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "notify_badge_user")
        let notificationManager = CapturingLocalNotificationManager()
        let badgeManager = CapturingApplicationBadgeManager()
        let repository = LocalChatRepository(
            database: databaseActor,
            paths: paths,
            localNotificationManager: notificationManager,
            applicationBadgeManager: badgeManager
        )
        try await repository.upsertConversation(
            makeConversationRecord(id: "notify_badge_conversation", userID: "notify_badge_user", title: "Badge", unreadCount: 1, sortTimestamp: 1)
        )

        _ = try await repository.applyIncomingSyncBatch(
            SyncBatch(
                messages: [
                    IncomingSyncMessage(
                        messageID: "notify_badge_message",
                        conversationID: "notify_badge_conversation",
                        senderID: "notify_badge_sender",
                        serverMessageID: "notify_badge_server",
                        sequence: 2,
                        text: "Badge body",
                        serverTime: 2
                    )
                ],
                nextCursor: "cursor_2",
                nextSequence: 2
            ),
            userID: "notify_badge_user"
        )

        let payloads = await notificationManager.payloads()
        let badgeValues = await badgeManager.values()

        #expect(payloads.count == 1)
        #expect(payloads.first?.badgeCount == 2)
        #expect(badgeValues.last == 2)
    }

    @Test func mutedConversationDoesNotScheduleLocalNotification() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "muted_notify_user")
        let notificationManager = CapturingLocalNotificationManager()
        let repository = LocalChatRepository(
            database: databaseActor,
            paths: paths,
            localNotificationManager: notificationManager
        )
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "muted_notify_conversation",
                userID: "muted_notify_user",
                title: "Muted",
                isMuted: true,
                sortTimestamp: 1
            )
        )

        _ = try await repository.applyIncomingSyncBatch(
            SyncBatch(
                messages: [
                    IncomingSyncMessage(
                        messageID: "muted_notify_message",
                        conversationID: "muted_notify_conversation",
                        senderID: "notify_sender",
                        serverMessageID: "muted_notify_server",
                        sequence: 1,
                        text: "Muted body",
                        serverTime: 1
                    )
                ],
                nextCursor: "cursor_1",
                nextSequence: 1
            ),
            userID: "muted_notify_user"
        )

        let payloads = await notificationManager.payloads()
        #expect(payloads.isEmpty)
    }

    @Test func hiddenPreviewNotificationUsesGenericBody() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "hidden_preview_user")
        let notificationManager = CapturingLocalNotificationManager()
        let repository = LocalChatRepository(
            database: databaseActor,
            paths: paths,
            localNotificationManager: notificationManager
        )
        try await databaseActor.execute(
            """
            INSERT INTO notification_setting (user_id, is_enabled, show_preview, updated_at)
            VALUES (?, 1, 0, 1);
            """,
            parameters: [.text("hidden_preview_user")],
            paths: paths
        )
        try await repository.upsertConversation(
            makeConversationRecord(id: "hidden_preview_conversation", userID: "hidden_preview_user", title: "Hidden", sortTimestamp: 1)
        )

        _ = try await repository.applyIncomingSyncBatch(
            SyncBatch(
                messages: [
                    IncomingSyncMessage(
                        messageID: "hidden_preview_message",
                        conversationID: "hidden_preview_conversation",
                        senderID: "notify_sender",
                        serverMessageID: "hidden_preview_server",
                        sequence: 1,
                        text: "Sensitive raw message",
                        serverTime: 1
                    )
                ],
                nextCursor: "cursor_1",
                nextSequence: 1
            ),
            userID: "hidden_preview_user"
        )

        let payloads = await notificationManager.payloads()
        #expect(payloads.count == 1)
        #expect(payloads.first?.showPreview == false)
        #expect(payloads.first?.notificationBody == "收到一条新消息")
        #expect(payloads.first?.notificationBody != "Sensitive raw message")
    }

    @Test func outgoingDuplicateAndEmptySyncBatchesDoNotScheduleLocalNotifications() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "quiet_notify_user")
        let initialRepository = LocalChatRepository(database: databaseActor, paths: paths)
        try await initialRepository.upsertConversation(
            makeConversationRecord(id: "quiet_notify_conversation", userID: "quiet_notify_user", title: "Quiet", sortTimestamp: 1)
        )

        let duplicateBatch = SyncBatch(
            messages: [
                IncomingSyncMessage(
                    messageID: "quiet_duplicate_message",
                    conversationID: "quiet_notify_conversation",
                    senderID: "notify_sender",
                    serverMessageID: "quiet_duplicate_server",
                    sequence: 1,
                    text: "Already inserted",
                    serverTime: 1
                )
            ],
            nextCursor: "cursor_1",
            nextSequence: 1
        )
        _ = try await initialRepository.applyIncomingSyncBatch(duplicateBatch, userID: "quiet_notify_user")

        let notificationManager = CapturingLocalNotificationManager()
        let repository = LocalChatRepository(
            database: databaseActor,
            paths: paths,
            localNotificationManager: notificationManager
        )
        _ = try await repository.applyIncomingSyncBatch(
            SyncBatch(messages: [], nextCursor: "cursor_empty", nextSequence: 1),
            userID: "quiet_notify_user"
        )
        _ = try await repository.applyIncomingSyncBatch(
            SyncBatch(
                messages: [
                    IncomingSyncMessage(
                        messageID: "quiet_outgoing_message",
                        conversationID: "quiet_notify_conversation",
                        senderID: "quiet_notify_user",
                        serverMessageID: "quiet_outgoing_server",
                        sequence: 2,
                        text: "Outgoing",
                        serverTime: 2,
                        direction: .outgoing
                    )
                ],
                nextCursor: "cursor_2",
                nextSequence: 2
            ),
            userID: "quiet_notify_user"
        )
        let duplicateResult = try await repository.applyIncomingSyncBatch(duplicateBatch, userID: "quiet_notify_user")

        let payloads = await notificationManager.payloads()
        #expect(duplicateResult.insertedCount == 0)
        #expect(duplicateResult.skippedDuplicateCount == 1)
        #expect(payloads.isEmpty)
    }

    @Test func syncEngineRefreshesConversationSummaryFromLatestSequence() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "sync_summary_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "sync_summary_conversation", userID: "sync_summary_user", title: "Summary", sortTimestamp: 1)
        )

        let batch = SyncBatch(
            messages: [
                IncomingSyncMessage(
                    messageID: "sync_summary_latest",
                    conversationID: "sync_summary_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "summary_client_30",
                    serverMessageID: "summary_server_30",
                    sequence: 30,
                    text: "Latest by seq",
                    serverTime: 30
                ),
                IncomingSyncMessage(
                    messageID: "sync_summary_older",
                    conversationID: "sync_summary_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "summary_client_20",
                    serverMessageID: "summary_server_20",
                    sequence: 20,
                    text: "Older by seq",
                    serverTime: 20
                )
            ],
            nextCursor: "cursor_30",
            nextSequence: 30
        )
        let engine = SyncEngineActor(
            userID: "sync_summary_user",
            store: repository,
            deltaService: StaticSyncDeltaService(batch: batch)
        )

        _ = try await engine.syncOnce()
        let messages = try await repository.listMessages(conversationID: "sync_summary_conversation", limit: 20, beforeSortSeq: nil)
        let conversations = try await repository.listConversations(for: "sync_summary_user")

        #expect(messages.map(\.text) == ["Latest by seq", "Older by seq"])
        #expect(conversations.first?.lastMessageDigest == "Latest by seq")
        #expect(conversations.first?.unreadCount == 2)
    }

    @Test func syncEngineRollsBackMessagesAndCheckpointWhenBatchInsertFails() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "sync_rollback_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "sync_rollback_conversation", userID: "sync_rollback_user", title: "Rollback", sortTimestamp: 1)
        )

        let batch = SyncBatch(
            messages: [
                IncomingSyncMessage(
                    messageID: "sync_rollback_same_id",
                    conversationID: "sync_rollback_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "rollback_client_1",
                    serverMessageID: "rollback_server_1",
                    sequence: 100,
                    text: "Should roll back",
                    serverTime: 100
                ),
                IncomingSyncMessage(
                    messageID: "sync_rollback_same_id",
                    conversationID: "sync_rollback_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "rollback_client_2",
                    serverMessageID: "rollback_server_2",
                    sequence: 101,
                    text: "Duplicate primary key",
                    serverTime: 101
                )
            ],
            nextCursor: "cursor_rollback",
            nextSequence: 101
        )
        let engine = SyncEngineActor(
            userID: "sync_rollback_user",
            store: repository,
            deltaService: StaticSyncDeltaService(batch: batch)
        )

        var didThrow = false
        do {
            _ = try await engine.syncOnce()
        } catch {
            didThrow = true
        }

        let messages = try await repository.listMessages(conversationID: "sync_rollback_conversation", limit: 20, beforeSortSeq: nil)
        let checkpoint = try await repository.syncCheckpoint(for: SyncEngineActor.messageBizKey)

        #expect(didThrow)
        #expect(messages.isEmpty)
        #expect(checkpoint == nil)
    }

    @Test func syncEngineRunsMultipleBatchesUntilCaughtUp() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "sync_multi_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "sync_multi_conversation", userID: "sync_multi_user", title: "Multi", sortTimestamp: 1)
        )

        let deltaService = ScriptedSyncDeltaService(
            batches: [
                SyncBatch(
                    messages: [
                        IncomingSyncMessage(
                            messageID: "sync_multi_1",
                            conversationID: "sync_multi_conversation",
                            senderID: "sync_sender",
                            clientMessageID: "sync_multi_client_1",
                            serverMessageID: "sync_multi_server_1",
                            sequence: 1,
                            text: "First page",
                            serverTime: 1
                        )
                    ],
                    nextCursor: "cursor_1",
                    nextSequence: 1,
                    hasMore: true
                ),
                SyncBatch(
                    messages: [
                        IncomingSyncMessage(
                            messageID: "sync_multi_2",
                            conversationID: "sync_multi_conversation",
                            senderID: "sync_sender",
                            clientMessageID: "sync_multi_client_2",
                            serverMessageID: "sync_multi_server_2",
                            sequence: 2,
                            text: "Second page",
                            serverTime: 2
                        )
                    ],
                    nextCursor: "cursor_2",
                    nextSequence: 2
                )
            ]
        )
        let engine = SyncEngineActor(
            userID: "sync_multi_user",
            store: repository,
            deltaService: deltaService
        )

        let result = try await engine.syncUntilCaughtUp(maxBatches: 4)
        let messages = try await repository.listMessages(conversationID: "sync_multi_conversation", limit: 20, beforeSortSeq: nil)
        let checkpoint = try await repository.syncCheckpoint(for: SyncEngineActor.messageBizKey)
        let requestedCheckpoints = await deltaService.requestedCheckpoints()

        #expect(result.batchCount == 2)
        #expect(result.fetchedCount == 2)
        #expect(result.insertedCount == 2)
        #expect(result.skippedDuplicateCount == 0)
        #expect(result.initialCheckpoint == nil)
        #expect(result.finalCheckpoint.cursor == "cursor_2")
        #expect(messages.map(\.text) == ["Second page", "First page"])
        #expect(checkpoint?.cursor == "cursor_2")
        #expect(checkpoint?.sequence == 2)
        #expect(requestedCheckpoints.map(\.?.cursor) == [nil, "cursor_1"])
    }

    @Test func syncEngineCatchesUpFromExistingCheckpointAndRefreshesLatestSummary() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "sync_catchup_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "sync_catchup_conversation", userID: "sync_catchup_user", title: "Catch Up", sortTimestamp: 1)
        )

        let firstEngine = SyncEngineActor(
            userID: "sync_catchup_user",
            store: repository,
            deltaService: StaticSyncDeltaService(
                batch: SyncBatch(
                    messages: [
                        IncomingSyncMessage(
                            messageID: "sync_catchup_old",
                            conversationID: "sync_catchup_conversation",
                            senderID: "sync_sender",
                            clientMessageID: "sync_catchup_client_1",
                            serverMessageID: "sync_catchup_server_1",
                            sequence: 10,
                            text: "Already synced",
                            serverTime: 10
                        )
                    ],
                    nextCursor: "cursor_10",
                    nextSequence: 10
                )
            )
        )
        _ = try await firstEngine.syncOnce()

        let deltaService = ScriptedSyncDeltaService(
            batches: [
                SyncBatch(
                    messages: [
                        IncomingSyncMessage(
                            messageID: "sync_catchup_newer",
                            conversationID: "sync_catchup_conversation",
                            senderID: "sync_sender",
                            clientMessageID: "sync_catchup_client_20",
                            serverMessageID: "sync_catchup_server_20",
                            sequence: 20,
                            text: "Caught up newer",
                            serverTime: 20
                        ),
                        IncomingSyncMessage(
                            messageID: "sync_catchup_latest",
                            conversationID: "sync_catchup_conversation",
                            senderID: "sync_sender",
                            clientMessageID: "sync_catchup_client_30",
                            serverMessageID: "sync_catchup_server_30",
                            sequence: 30,
                            text: "Caught up latest",
                            serverTime: 30
                        )
                    ],
                    nextCursor: "cursor_30",
                    nextSequence: 30
                )
            ]
        )
        let catchUpEngine = SyncEngineActor(
            userID: "sync_catchup_user",
            store: repository,
            deltaService: deltaService
        )

        let result = try await catchUpEngine.syncUntilCaughtUp()
        let messages = try await repository.listMessages(conversationID: "sync_catchup_conversation", limit: 20, beforeSortSeq: nil)
        let conversations = try await repository.listConversations(for: "sync_catchup_user")
        let requestedCheckpoints = await deltaService.requestedCheckpoints()

        #expect(result.initialCheckpoint?.cursor == "cursor_10")
        #expect(result.finalCheckpoint.cursor == "cursor_30")
        #expect(messages.map(\.text) == ["Caught up latest", "Caught up newer", "Already synced"])
        #expect(conversations.first?.lastMessageDigest == "Caught up latest")
        #expect(requestedCheckpoints.first??.cursor == "cursor_10")
    }

    @Test func syncEngineSkipsDuplicatesAcrossBatches() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "sync_cross_duplicate_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "sync_cross_duplicate_conversation", userID: "sync_cross_duplicate_user", title: "Cross Duplicates", sortTimestamp: 1)
        )

        let deltaService = ScriptedSyncDeltaService(
            batches: [
                SyncBatch(
                    messages: [
                        IncomingSyncMessage(
                            messageID: "sync_cross_unique_1",
                            conversationID: "sync_cross_duplicate_conversation",
                            senderID: "sync_sender",
                            clientMessageID: "sync_cross_client_1",
                            serverMessageID: "sync_cross_server_1",
                            sequence: 1,
                            text: "Unique first batch",
                            serverTime: 1
                        )
                    ],
                    nextCursor: "cursor_1",
                    nextSequence: 1,
                    hasMore: true
                ),
                SyncBatch(
                    messages: [
                        IncomingSyncMessage(
                            messageID: "sync_cross_duplicate_client",
                            conversationID: "sync_cross_duplicate_conversation",
                            senderID: "sync_sender",
                            clientMessageID: "sync_cross_client_1",
                            serverMessageID: "sync_cross_server_2",
                            sequence: 2,
                            text: "Duplicate client across batch",
                            serverTime: 2
                        ),
                        IncomingSyncMessage(
                            messageID: "sync_cross_duplicate_server",
                            conversationID: "sync_cross_duplicate_conversation",
                            senderID: "sync_sender",
                            clientMessageID: "sync_cross_client_3",
                            serverMessageID: "sync_cross_server_1",
                            sequence: 3,
                            text: "Duplicate server across batch",
                            serverTime: 3
                        ),
                        IncomingSyncMessage(
                            messageID: "sync_cross_duplicate_sequence",
                            conversationID: "sync_cross_duplicate_conversation",
                            senderID: "sync_sender",
                            clientMessageID: "sync_cross_client_4",
                            serverMessageID: "sync_cross_server_4",
                            sequence: 1,
                            text: "Duplicate sequence across batch",
                            serverTime: 4
                        ),
                        IncomingSyncMessage(
                            messageID: "sync_cross_unique_5",
                            conversationID: "sync_cross_duplicate_conversation",
                            senderID: "sync_sender",
                            clientMessageID: "sync_cross_client_5",
                            serverMessageID: "sync_cross_server_5",
                            sequence: 5,
                            text: "Unique second batch",
                            serverTime: 5
                        )
                    ],
                    nextCursor: "cursor_5",
                    nextSequence: 5
                )
            ]
        )
        let engine = SyncEngineActor(
            userID: "sync_cross_duplicate_user",
            store: repository,
            deltaService: deltaService
        )

        let result = try await engine.syncUntilCaughtUp(maxBatches: 3)
        let messages = try await repository.listMessages(conversationID: "sync_cross_duplicate_conversation", limit: 20, beforeSortSeq: nil)

        #expect(result.batchCount == 2)
        #expect(result.fetchedCount == 5)
        #expect(result.insertedCount == 2)
        #expect(result.skippedDuplicateCount == 3)
        #expect(messages.map(\.text) == ["Unique second batch", "Unique first batch"])
    }

    @Test func syncEngineStopsWhenHasMoreExceedsMaxBatches() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "sync_limit_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "sync_limit_conversation", userID: "sync_limit_user", title: "Limit", sortTimestamp: 1)
        )

        let batch = SyncBatch(
            messages: [
                IncomingSyncMessage(
                    messageID: "sync_limit_message",
                    conversationID: "sync_limit_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "sync_limit_client",
                    serverMessageID: "sync_limit_server",
                    sequence: 1,
                    text: "Still has more",
                    serverTime: 1
                )
            ],
            nextCursor: "cursor_limit",
            nextSequence: 1,
            hasMore: true
        )
        let engine = SyncEngineActor(
            userID: "sync_limit_user",
            store: repository,
            deltaService: StaticSyncDeltaService(batch: batch)
        )

        var caughtError: SyncEngineError?
        do {
            _ = try await engine.syncUntilCaughtUp(maxBatches: 2)
        } catch let error as SyncEngineError {
            caughtError = error
        }

        let messages = try await repository.listMessages(conversationID: "sync_limit_conversation", limit: 20, beforeSortSeq: nil)
        let checkpoint = try await repository.syncCheckpoint(for: SyncEngineActor.messageBizKey)

        #expect(caughtError == .exceededMaxBatches(2))
        #expect(messages.map(\.text) == ["Still has more"])
        #expect(checkpoint?.cursor == "cursor_limit")
    }

    @Test func photoLibraryVideoDataHandlerWritesChunksFromDetachedExecutor() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("picked-video.mov")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let task = Task.detached {
            let fileHandle = try FileHandle(forWritingTo: url)
            let dataHandler = ChatPhotoLibraryVideoFileIO.makeDataReceivedHandler(fileHandle: fileHandle)

            dataHandler(Data([0x01, 0x02]))
            dataHandler(Data([0x03]))
            try fileHandle.close()
        }
        try await task.value

        let data = try Data(contentsOf: url)
        #expect(data == Data([0x01, 0x02, 0x03]))
    }
}

private actor ScriptedSyncDeltaService: SyncDeltaService {
    private let batches: [SyncBatch]
    private var nextBatchIndex = 0
    private var checkpoints: [SyncCheckpoint?] = []

    init(batches: [SyncBatch]) {
        self.batches = batches
    }

    func fetchDelta(after checkpoint: SyncCheckpoint?) async throws -> SyncBatch {
        checkpoints.append(checkpoint)

        guard !batches.isEmpty else {
            return SyncBatch(messages: [], nextCursor: checkpoint?.cursor, nextSequence: checkpoint?.sequence)
        }

        let batchIndex = min(nextBatchIndex, batches.count - 1)
        nextBatchIndex += 1
        return batches[batchIndex]
    }

    func requestedCheckpoints() -> [SyncCheckpoint?] {
        checkpoints
    }
}

@MainActor
private final class TestNetworkConnectivityMonitor: NetworkConnectivityMonitoring {
    private let subject: CurrentValueSubject<Bool, Never>
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    init(isReachable: Bool) {
        self.subject = CurrentValueSubject(isReachable)
    }

    var isReachablePublisher: AnyPublisher<Bool, Never> {
        subject.eraseToAnyPublisher()
    }

    var currentIsReachable: Bool {
        subject.value
    }

    func start() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func setReachable(_ isReachable: Bool) {
        subject.send(isReachable)
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

    func loadConversationPage(limit: Int, offset: Int) async throws -> ConversationListPage {
        let rows = try await loadConversations()
        let requestedLimit = max(limit, 0)
        let pageRows = Array(rows.dropFirst(offset).prefix(requestedLimit))

        return ConversationListPage(
            rows: pageRows,
            hasMore: offset + pageRows.count < rows.count
        )
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}
}

private struct PagedConversationListUseCase: ConversationListUseCase {
    private let rows: [ConversationListRowState] = (0..<3).map { index in
        ConversationListRowState(
            id: ConversationID(rawValue: "paged_\(index)"),
            title: "Paged \(index)",
            subtitle: "Page row \(index)",
            timeText: "Now",
            unreadText: nil,
            isPinned: false,
            isMuted: false
        )
    }

    func loadConversations() async throws -> [ConversationListRowState] {
        rows
    }

    func loadConversationPage(limit: Int, offset: Int) async throws -> ConversationListPage {
        let requestedLimit = max(limit, 0)
        let pageRows = Array(rows.dropFirst(offset).prefix(requestedLimit))

        return ConversationListPage(
            rows: pageRows,
            hasMore: offset + pageRows.count < rows.count
        )
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}
}

private actor MutableConversationListUseCase: ConversationListUseCase {
    private var row = ConversationListRowState(
        id: "mutable_conversation",
        title: "Mutable Conversation",
        subtitle: "Settings can change",
        timeText: "Now",
        unreadText: nil,
        isPinned: false,
        isMuted: false
    )

    func loadConversations() async throws -> [ConversationListRowState] {
        [row]
    }

    func loadConversationPage(limit: Int, offset: Int) async throws -> ConversationListPage {
        let allRows = try await loadConversations()
        let rows = Array(allRows.dropFirst(offset).prefix(max(limit, 0)))
        return ConversationListPage(rows: rows, hasMore: false)
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {
        guard conversationID == row.id else { return }
        row = ConversationListRowState(
            id: row.id,
            title: row.title,
            subtitle: row.subtitle,
            timeText: row.timeText,
            unreadText: row.unreadText,
            isPinned: isPinned,
            isMuted: row.isMuted
        )
    }

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {
        guard conversationID == row.id else { return }
        row = ConversationListRowState(
            id: row.id,
            title: row.title,
            subtitle: row.subtitle,
            timeText: row.timeText,
            unreadText: row.unreadText,
            isPinned: row.isPinned,
            isMuted: isMuted
        )
    }
}

private actor CountingConversationListUseCase: ConversationListUseCase {
    private(set) var loadPageCallCount = 0

    func loadConversations() async throws -> [ConversationListRowState] {
        try await loadConversationPage(limit: 50, offset: 0).rows
    }

    func loadConversationPage(limit: Int, offset: Int) async throws -> ConversationListPage {
        loadPageCallCount += 1
        return ConversationListPage(
            rows: [
                ConversationListRowState(
                    id: "counting_conversation",
                    title: "Counting Conversation",
                    subtitle: "Loaded once",
                    timeText: "Now",
                    unreadText: nil,
                    isPinned: false,
                    isMuted: false
                )
            ],
            hasMore: false
        )
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}
}

private final class ConversationListLoadingDiagnosticsSpy: ConversationListLoadingDiagnostics, @unchecked Sendable {
    private let lock = NSLock()
    private var storedMessages: [String] = []

    var messages: [String] {
        lock.withLock {
            storedMessages
        }
    }

    func log(_ message: String) {
        lock.withLock {
            storedMessages.append(message)
        }
    }
}

private struct EmptySearchUseCase: SearchUseCase {
    func search(query: String) async throws -> SearchResults {
        SearchResults()
    }

    func rebuildIndex() async throws {}
}

private actor TrackingAccountStorageService: AccountStorageService {
    private let rootDirectory: URL
    private(set) var prepareCallCount = 0

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    func prepareStorage(for accountID: UserID) async throws -> AccountStoragePaths {
        prepareCallCount += 1
        let paths = try makePaths(for: accountID)
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: paths.rootDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.mediaDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.cacheDirectory, withIntermediateDirectories: true)
        createFileIfNeeded(at: paths.mainDatabase)
        createFileIfNeeded(at: paths.searchDatabase)
        createFileIfNeeded(at: paths.fileIndexDatabase)

        return paths
    }

    func deleteStorage(for accountID: UserID) async throws {
        let paths = try makePaths(for: accountID)
        if FileManager.default.fileExists(atPath: paths.rootDirectory.path) {
            try FileManager.default.removeItem(at: paths.rootDirectory)
        }
    }

    private func makePaths(for accountID: UserID) throws -> AccountStoragePaths {
        let rawID = accountID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawID.isEmpty else {
            throw AccountStorageError.emptyAccountID
        }

        let accountRoot = rootDirectory.appendingPathComponent("account_\(rawID)", isDirectory: true)
        return AccountStoragePaths(
            accountID: accountID,
            rootDirectory: accountRoot,
            mainDatabase: accountRoot.appendingPathComponent("main.db"),
            searchDatabase: accountRoot.appendingPathComponent("search.db"),
            fileIndexDatabase: accountRoot.appendingPathComponent("file_index.db"),
            mediaDirectory: accountRoot.appendingPathComponent("media", isDirectory: true),
            cacheDirectory: accountRoot.appendingPathComponent("cache", isDirectory: true)
        )
    }

    private func createFileIfNeeded(at url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: Data())
        }
    }
}

private actor TrackingAccountDatabaseKeyStore: AccountDatabaseKeyStore {
    private var keys: [UserID: Data] = [:]
    private(set) var databaseKeyCallCount = 0

    func databaseKey(for accountID: UserID) async throws -> Data {
        databaseKeyCallCount += 1
        if let key = keys[accountID] {
            return key
        }

        let key = Data(repeating: UInt8(databaseKeyCallCount), count: 32)
        keys[accountID] = key
        return key
    }

    func deleteDatabaseKey(for accountID: UserID) async throws {
        keys[accountID] = nil
    }
}

private struct StaleSearchUseCase: SearchUseCase {
    func search(query: String) async throws -> SearchResults {
        if query == "old" {
            try await Task.sleep(nanoseconds: 80_000_000)
            return SearchResults(
                messages: [
                    SearchResultRecord(
                        kind: .message,
                        id: "old_result",
                        title: "Old Result",
                        subtitle: "Old",
                        conversationID: "old_conversation",
                        messageID: "old_message"
                    )
                ]
            )
        }

        return SearchResults(
            messages: [
                SearchResultRecord(
                    kind: .message,
                    id: "new_result",
                    title: "New Result",
                    subtitle: "New",
                    conversationID: "new_conversation",
                    messageID: "new_message"
                )
            ]
        )
    }

    func rebuildIndex() async throws {}
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

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
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

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

private final class RecoveringPagingStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private let initialPage: ChatMessagePage
    private let recoveredPage: ChatMessagePage
    private(set) var loadOlderCallCount = 0

    init(initialPage: ChatMessagePage, recoveredPage: ChatMessagePage) {
        self.initialPage = initialPage
        self.recoveredPage = recoveredPage
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        initialPage
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        loadOlderCallCount += 1

        if loadOlderCallCount == 1 {
            throw TestChatError.paginationFailed
        }

        return recoveredPage
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

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

private final class ImageSendingStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private(set) var sentImageCount = 0

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
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

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sentImageCount += 1

        return AsyncThrowingStream { continuation in
            continuation.yield(
                ChatMessageRowState(
                    id: "image_stub_message",
                    text: "",
                    imageThumbnailPath: "/tmp/chat-thumb.jpg",
                    voiceDurationMilliseconds: nil,
                    sortSequence: 1,
                    timeText: "Now",
                    statusText: nil,
                    uploadProgress: nil,
                    isOutgoing: true,
                    canRetry: false,
                    canDelete: true,
                    canRevoke: false,
                    isRevoked: false
                )
            )
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

private final class ComposerSendingStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private(set) var events: [String] = []

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        events.append("text:\(text)")

        return AsyncThrowingStream { continuation in
            continuation.yield(
                makeChatRow(id: "composer_text", text: text, sortSequence: 2)
            )
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        events.append("image:\(preferredFileExtension ?? "")")

        return AsyncThrowingStream { continuation in
            continuation.yield(
                ChatMessageRowState(
                    id: "composer_image",
                    text: "",
                    imageThumbnailPath: "/tmp/composer-image.jpg",
                    voiceDurationMilliseconds: nil,
                    sortSequence: 1,
                    timeText: "Now",
                    statusText: nil,
                    uploadProgress: nil,
                    isOutgoing: true,
                    canRetry: false,
                    canDelete: true,
                    canRevoke: false,
                    isRevoked: false
                )
            )
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVideo(fileURL: URL, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        events.append("video:\(preferredFileExtension ?? "")")

        return AsyncThrowingStream { continuation in
            continuation.yield(
                ChatMessageRowState(
                    id: "composer_video",
                    text: "",
                    imageThumbnailPath: nil,
                    videoThumbnailPath: "/tmp/composer-video.jpg",
                    videoLocalPath: fileURL.path,
                    videoDurationMilliseconds: 1_000,
                    voiceDurationMilliseconds: nil,
                    sortSequence: 1,
                    timeText: "Now",
                    statusText: nil,
                    uploadProgress: nil,
                    isOutgoing: true,
                    canRetry: false,
                    canDelete: true,
                    canRevoke: false,
                    isRevoked: false
                )
            )
            continuation.finish()
        }
    }

    func sendFile(fileURL: URL) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

private final class VoicePlaybackStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private var rows: [ChatMessageRowState]
    private(set) var markedMessageIDs: [MessageID] = []

    init(rows: [ChatMessageRowState]) {
        self.rows = rows
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: rows, hasMore: false, nextBeforeSortSequence: rows.first?.sortSequence)
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

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        markedMessageIDs.append(messageID)

        guard let index = rows.firstIndex(where: { $0.id == messageID }) else {
            return nil
        }

        rows[index] = rows[index].withVoicePlayback(isPlaying: false, isUnplayed: false)
        return rows[index]
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

private extension ChatUseCase {
    func sendVideo(fileURL: URL, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendFile(fileURL: URL) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private func makeChatRow(id: MessageID, text: String, sortSequence: Int64) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        text: text,
        imageThumbnailPath: nil,
        voiceDurationMilliseconds: nil,
        sortSequence: sortSequence,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: true,
        canRetry: false,
        canDelete: true,
        canRevoke: false,
        isRevoked: false
    )
}

private func makeVoiceRow(id: MessageID, sortSequence: Int64, isUnplayed: Bool) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        text: "Voice 2s",
        imageThumbnailPath: nil,
        voiceDurationMilliseconds: 2_000,
        sortSequence: sortSequence,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: false,
        canRetry: false,
        canDelete: true,
        canRevoke: false,
        isRevoked: false,
        voiceLocalPath: "/tmp/\(id.rawValue).m4a",
        isVoiceUnplayed: isUnplayed,
        isVoicePlaying: false
    )
}

@Test func chatMessageRowStateWithVoicePlaybackPreservesSenderAvatarURL() {
    let row = ChatMessageRowState(
        id: "avatar_voice",
        text: "Voice 2s",
        imageThumbnailPath: nil,
        voiceDurationMilliseconds: 2_000,
        sortSequence: 1,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        senderAvatarURL: "https://example.com/voice-avatar.png",
        isOutgoing: false,
        canRetry: false,
        canDelete: true,
        canRevoke: false,
        isRevoked: false,
        voiceLocalPath: "/tmp/avatar_voice.m4a",
        isVoiceUnplayed: true,
        isVoicePlaying: false
    )

    let updatedRow = row.withVoicePlayback(isPlaying: true)

    #expect(updatedRow.senderAvatarURL == "https://example.com/voice-avatar.png")
    #expect(updatedRow.isVoicePlaying)
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("AppleIMTests-\(UUID().uuidString)", isDirectory: true)
}

private func makeMockAccountsFile() throws -> URL {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("mock_accounts.json")
    let json = """
    [
      {
        "userID": "mock_user",
        "loginName": "mock_user",
        "password": "password123",
        "displayName": "Mock User",
        "mobile": "13700000000",
        "avatarURL": "https://example.com/mock-avatar.png"
      }
    ]
    """
    try Data(json.utf8).write(to: url, options: [.atomic])
    return url
}

private func samplePNGData() -> Data {
    Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")!
}

private func makeVoiceRecordingFile(in directory: URL) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("sample-\(UUID().uuidString)").appendingPathExtension("m4a")
    try Data("mock voice recording".utf8).write(to: url, options: [.atomic])
    return url
}

private func makeSampleVideoFile(in directory: URL) async throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("sample-\(UUID().uuidString)").appendingPathExtension("mov")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 64,
        AVVideoHeightKey: 64
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 64
        ]
    )

    guard writer.canAdd(input) else {
        Issue.record("Unable to add video writer input")
        return url
    }

    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    let firstPixelBuffer = try makePixelBuffer(width: 64, height: 64, colorOffset: 0)
    let secondPixelBuffer = try makePixelBuffer(width: 64, height: 64, colorOffset: 48)
    while !input.isReadyForMoreMediaData {
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    guard adaptor.append(firstPixelBuffer, withPresentationTime: .zero) else {
        throw writer.error ?? MediaFileError.invalidVideoFile
    }

    while !input.isReadyForMoreMediaData {
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    guard adaptor.append(secondPixelBuffer, withPresentationTime: CMTime(value: 1, timescale: 1)) else {
        throw writer.error ?? MediaFileError.invalidVideoFile
    }

    input.markAsFinished()
    await writer.finishWriting()

    if writer.status == .failed {
        throw writer.error ?? MediaFileError.invalidVideoFile
    }

    return url
}

private func makePixelBuffer(width: Int, height: Int, colorOffset: UInt8) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32ARGB,
        nil,
        &pixelBuffer
    )

    guard status == kCVReturnSuccess, let pixelBuffer else {
        throw MediaFileError.invalidVideoFile
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    }

    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        throw MediaFileError.invalidVideoFile
    }

    let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * 4
            buffer[offset] = 255
            buffer[offset + 1] = UInt8((x * 4 + Int(colorOffset)) % 256)
            buffer[offset + 2] = UInt8((y * 4 + Int(colorOffset)) % 256)
            buffer[offset + 3] = 180
        }
    }

    return pixelBuffer
}

private func makeJPEGData(width: Int, height: Int, quality: Double) -> Data {
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * bytesPerPixel
            pixels[offset] = UInt8(x % 256)
            pixels[offset + 1] = UInt8(y % 256)
            pixels[offset + 2] = UInt8((x + y) % 256)
            pixels[offset + 3] = 255
        }
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let image = context.makeImage()
    else {
        Issue.record("Unable to create JPEG test image")
        return Data()
    }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
        Issue.record("Unable to create JPEG destination")
        return Data()
    }

    CGImageDestinationAddImage(destination, image, [
        kCGImageDestinationLossyCompressionQuality: quality
    ] as CFDictionary)

    guard CGImageDestinationFinalize(destination) else {
        Issue.record("Unable to finalize JPEG test image")
        return Data()
    }

    return data as Data
}

private func imageDimensions(atPath path: String) -> (width: Int, height: Int) {
    guard
        let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else {
        Issue.record("Unable to read image dimensions at \(path)")
        return (0, 0)
    }

    return (
        properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
        properties[kCGImagePropertyPixelHeight] as? Int ?? 0
    )
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

private func seedPerformanceMessages(
    databaseContext: DatabaseTestContext,
    conversationID: ConversationID,
    userID: UserID,
    count: Int
) async throws {
    let numbersCTE = """
    WITH
        digits(d) AS (
            VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9)
        ),
        numbers(value) AS (
            SELECT ones.d + tens.d * 10 + hundreds.d * 100 + thousands.d * 1000 + tenThousands.d * 10000 + 1
            FROM digits AS ones
            CROSS JOIN digits AS tens
            CROSS JOIN digits AS hundreds
            CROSS JOIN digits AS thousands
            CROSS JOIN digits AS tenThousands
        )
    """

    try await databaseContext.databaseActor.execute(
        """
        \(numbersCTE)
        INSERT INTO message_text (content_id, text, mentions_json, at_all, rich_text_json)
        SELECT
            'perf_text_' || value,
            'Perf Message ' || value,
            NULL,
            0,
            NULL
        FROM numbers
        WHERE value <= \(count);
        """,
        paths: databaseContext.paths
    )

    try await databaseContext.databaseActor.execute(
        """
        \(numbersCTE)
        INSERT INTO message (
            message_id,
            conversation_id,
            sender_id,
            client_msg_id,
            msg_type,
            direction,
            send_status,
            delivery_status,
            read_status,
            revoke_status,
            is_deleted,
            content_table,
            content_id,
            sort_seq,
            local_time
        )
        SELECT
            'perf_message_' || value,
            ?,
            ?,
            'perf_client_' || value,
            \(MessageType.text.rawValue),
            \(MessageDirection.outgoing.rawValue),
            \(MessageSendStatus.success.rawValue),
            0,
            \(MessageReadStatus.read.rawValue),
            0,
            0,
            'message_text',
            'perf_text_' || value,
            value,
            value
        FROM numbers
        WHERE value <= \(count);
        """,
        parameters: [
            .text(conversationID.rawValue),
            .text(userID.rawValue)
        ],
        paths: databaseContext.paths
    )
}

private func databaseReadFails(using databaseActor: DatabaseActor, paths: AccountStoragePaths) async -> Bool {
    do {
        _ = try await databaseActor.tableNames(in: .main, paths: paths)
        return false
    } catch {
        return true
    }
}

private func waitForCondition(
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    condition: @escaping () async throws -> Bool
) async throws {
    let startedAt = DispatchTime.now().uptimeNanoseconds

    while DispatchTime.now().uptimeNanoseconds - startedAt < timeoutNanoseconds {
        if try await condition() {
            return
        }

        try await Task.sleep(nanoseconds: 10_000_000)
    }

    Issue.record("Timed out waiting for condition")
}

private func makeConversationRecord(
    id: ConversationID,
    userID: UserID,
    title: String,
    isPinned: Bool = false,
    isMuted: Bool = false,
    unreadCount: Int = 0,
    draftText: String? = nil,
    avatarURL: String? = nil,
    sortTimestamp: Int64
) -> ConversationRecord {
    ConversationRecord(
        id: id,
        userID: userID,
        type: .single,
        targetID: "\(id.rawValue)_target",
        title: title,
        avatarURL: avatarURL,
        lastMessageID: nil,
        lastMessageTime: sortTimestamp,
        lastMessageDigest: "Digest \(title)",
        unreadCount: unreadCount,
        draftText: draftText,
        isPinned: isPinned,
        isMuted: isMuted,
        isHidden: false,
        sortTimestamp: sortTimestamp,
        updatedAt: sortTimestamp,
        createdAt: sortTimestamp
    )
}

@MainActor
private func button(in view: UIView, identifier: String) -> UIButton? {
    if let button = view as? UIButton, button.accessibilityIdentifier == identifier {
        return button
    }

    for subview in view.subviews {
        if let button = button(in: subview, identifier: identifier) {
            return button
        }
    }

    return nil
}

@MainActor
private func findView(in view: UIView, identifier: String) -> UIView? {
    if view.accessibilityIdentifier == identifier {
        return view
    }

    for subview in view.subviews {
        if let matchingView = findView(in: subview, identifier: identifier) {
            return matchingView
        }
    }

    return nil
}

@MainActor
private func findView<T: UIView>(ofType type: T.Type, in view: UIView) -> T? {
    if let matchingView = view as? T {
        return matchingView
    }

    for subview in view.subviews {
        if let matchingView = findView(ofType: type, in: subview) {
            return matchingView
        }
    }

    return nil
}

@MainActor
private func findLabel(withText text: String, in view: UIView) -> UILabel? {
    if let label = view as? UILabel, label.text == text {
        return label
    }

    for subview in view.subviews {
        if let matchingLabel = findLabel(withText: text, in: subview) {
            return matchingLabel
        }
    }

    return nil
}

private actor CapturingLocalNotificationManager: LocalNotificationManaging {
    private var capturedPayloads: [IncomingMessageNotificationPayload] = []

    func requestAuthorization() async throws -> Bool {
        true
    }

    func scheduleIncomingMessageNotification(_ payload: IncomingMessageNotificationPayload) async throws {
        capturedPayloads.append(payload)
    }

    func payloads() -> [IncomingMessageNotificationPayload] {
        capturedPayloads
    }
}

private actor CapturingApplicationBadgeManager: ApplicationBadgeManaging {
    private var capturedValues: [Int] = []

    func setApplicationIconBadgeNumber(_ count: Int) async {
        capturedValues.append(count)
    }

    func values() -> [Int] {
        capturedValues
    }
}

private func collectRows(from stream: AsyncThrowingStream<ChatMessageRowState, Error>) async throws -> [ChatMessageRowState] {
    var rows: [ChatMessageRowState] = []

    for try await row in stream {
        rows.append(row)
    }

    return rows
}
