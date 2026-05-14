import Testing
import Foundation

@testable import AppleIM

extension AppleIMTests {
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
    @Test func chatStoreProviderClosesDatabaseConnectionsBeforeDeletingAccountStorage() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let databaseActor = DatabaseActor()
        let storeProvider = ChatStoreProvider(
            accountID: "delete_cached_connection_user",
            storageService: storageService,
            database: databaseActor,
            databaseKeyStore: InMemoryAccountDatabaseKeyStore()
        )

        _ = try await storeProvider.repository()
        let paths = try await storageService.prepareStorage(for: "delete_cached_connection_user")
        _ = try await databaseActor.tableNames(in: .main, paths: paths)

        #expect(await databaseActor.cachedConnectionCount(for: paths) > 0)

        try await storeProvider.deleteAccountStorage()

        #expect(await databaseActor.cachedConnectionCount(for: paths) == 0)
        #expect(FileManager.default.fileExists(atPath: paths.rootDirectory.path) == false)
    }

    @MainActor
    @Test func chatStoreProviderClosesCurrentAccountConnectionsWithoutDeletingStorage() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let databaseActor = DatabaseActor()
        let storeProvider = ChatStoreProvider(
            accountID: "logout_cached_connection_user",
            storageService: storageService,
            database: databaseActor,
            databaseKeyStore: InMemoryAccountDatabaseKeyStore()
        )

        _ = try await storeProvider.repository()
        let paths = try await storageService.prepareStorage(for: "logout_cached_connection_user")
        _ = try await databaseActor.tableNames(in: .main, paths: paths)
        #expect(await databaseActor.cachedConnectionCount(for: paths) > 0)

        try await storeProvider.closeAccountConnections()

        #expect(await databaseActor.cachedConnectionCount(for: paths) == 0)
        #expect(FileManager.default.fileExists(atPath: paths.rootDirectory.path))
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
    @Test func chatStoreProviderSeedsDemoMessagesForInitialConversations() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "seed_message_user",
            storageService: storageService,
            database: DatabaseActor(),
            databaseKeyStore: InMemoryAccountDatabaseKeyStore()
        )

        let repository = try await storeProvider.repository()
        let conversations = try await repository.listConversations(for: "seed_message_user")
        let conversationsByID = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })

        for conversationID in [ConversationID("single_sondra"), ConversationID("group_core"), ConversationID("system_release")] {
            let conversation = try #require(conversationsByID[conversationID])
            let messages = try await repository.listMessages(
                conversationID: conversationID,
                limit: 20,
                beforeSortSeq: nil
            )
            let latestMessage = try #require(messages.first)

            #expect(try requireTextualContent(latestMessage) == conversation.lastMessageDigest)
        }
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

    @Test func databaseActorReusesCachedConnectionForRepeatedQueries() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "cached_connection_user")
        try await databaseActor.closeConnections(for: paths)
        #expect(await databaseActor.cachedConnectionCount(for: paths) == 0)

        _ = try await databaseActor.tableNames(in: .main, paths: paths)
        let openCountAfterFirstQuery = await databaseActor.openCount(for: .main, paths: paths)
        _ = try await databaseActor.tableNames(in: .main, paths: paths)
        let openCountAfterSecondQuery = await databaseActor.openCount(for: .main, paths: paths)

        #expect(openCountAfterFirstQuery == 1)
        #expect(openCountAfterSecondQuery == openCountAfterFirstQuery)
        #expect(await databaseActor.cachedConnectionCount(for: paths) == 1)
    }

    @Test func databaseActorReopensConnectionAfterClosingAccountPaths() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "reopen_connection_user")
        try await databaseActor.closeConnections(for: paths)

        _ = try await databaseActor.tableNames(in: .main, paths: paths)
        #expect(await databaseActor.openCount(for: .main, paths: paths) == 1)

        try await databaseActor.closeConnections(for: paths)
        #expect(await databaseActor.cachedConnectionCount(for: paths) == 0)

        _ = try await databaseActor.tableNames(in: .main, paths: paths)
        #expect(await databaseActor.openCount(for: .main, paths: paths) == 2)
        #expect(await databaseActor.cachedConnectionCount(for: paths) == 1)
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

    @Test func databaseBootstrapCreatesEmojiTablesAndIndexes() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "emoji_schema_user")
        let tableNames = try await databaseActor.tableNames(in: .main, paths: paths)
        let indexes = try await databaseActor.query(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_emoji_%' ORDER BY name;",
            paths: paths
        )
        let indexNames = indexes.compactMap { $0.string("name") }

        #expect(tableNames.contains("emoji_store"))
        #expect(tableNames.contains("emoji_package"))
        #expect(tableNames.contains("message_emoji"))
        #expect(indexNames.contains("idx_emoji_user_recent"))
        #expect(indexNames.contains("idx_emoji_user_favorite"))
        #expect(indexNames.contains("idx_emoji_package_user_sort"))
    }

    @Test func chatStoreProviderSkipsDemoSeedWhenDisabled() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "mock_user",
            storageService: storageService,
            database: DatabaseActor(),
            demoDataCatalog: BundleDemoDataCatalog(resourceURL: try makeMockDemoDataFile(messageCount: 120)),
            shouldSeedDemoData: false
        )

        let repository = try await storeProvider.repository()
        let conversations = try await repository.listConversations(for: "mock_user")
        let contacts = try await repository.listContacts(for: "mock_user")

        #expect(conversations.isEmpty)
        #expect(contacts.isEmpty)
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
}
