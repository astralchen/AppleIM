import Testing
import Foundation
import GRDB

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

    @Test func databaseSchemaUsesGRDBBuilderForOrdinaryTablesAndIndexes() throws {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        let testFileURL = URL(fileURLWithPath: #filePath)
        var candidateRoots = [URL]()

        for key in ["SRCROOT", "PROJECT_DIR"] {
            if let path = environment[key], path.isEmpty == false {
                candidateRoots.append(URL(fileURLWithPath: path))
            }
        }
        if #filePath.hasPrefix("/") {
            candidateRoots.append(
                testFileURL
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
            )
        }
        candidateRoots.append(URL(fileURLWithPath: fileManager.currentDirectoryPath))

        let schemaURL = try #require(
            candidateRoots
                .map { $0.appendingPathComponent("AppleIM/Database/DatabaseSchema.swift") }
                .first { fileManager.fileExists(atPath: $0.path) }
        )
        let source = try String(contentsOf: schemaURL, encoding: .utf8)

        #expect(source.contains("MigrationScript") == false)
        #expect(source.contains("baselineScripts") == false)
        #expect(source.contains("baselineExtensionScripts") == false)
        #expect(source.contains("initialScripts") == false)
        #expect(source.contains("CREATE TABLE IF NOT EXISTS") == false)
        #expect(source.contains("CREATE INDEX IF NOT EXISTS") == false)
        #expect(source.contains("CREATE VIRTUAL TABLE IF NOT EXISTS") == true)
        #expect(source.contains("USING fts5") == true)
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
            accountID: "ui_test_user",
            storageService: storageService,
            database: DatabaseActor(),
            databaseKeyStore: InMemoryAccountDatabaseKeyStore()
        )

        let repository = try await storeProvider.repository()
        let conversations = try await repository.listConversations(for: "ui_test_user")
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
    @Test func plaintextDatabaseIsRecreatedAsEncryptedDatabaseWithoutDataMigration() async throws {
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

        #expect(conversations.contains { $0.title == "Migrated Conversation" } == false)
        #expect(cipherVersion.isEmpty == false)
        #expect(unconfiguredReadFailed)
    }

    @Test func databaseActorErrorDescriptionRedactsSensitiveDetails() {
        let error = DatabaseActorError.writeFailed(
            path: "/private/account_sensitive_user/main.db",
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
        let openCountBeforeClose = await databaseActor.openCount(for: .main, paths: paths)
        try await databaseActor.closeConnections(for: paths)
        #expect(await databaseActor.cachedConnectionCount(for: paths) == 0)

        _ = try await databaseActor.tableNames(in: .main, paths: paths)
        let openCountAfterFirstQuery = await databaseActor.openCount(for: .main, paths: paths)
        _ = try await databaseActor.tableNames(in: .main, paths: paths)
        let openCountAfterSecondQuery = await databaseActor.openCount(for: .main, paths: paths)

        #expect(openCountAfterFirstQuery == openCountBeforeClose + 1)
        #expect(openCountAfterSecondQuery == openCountAfterFirstQuery)
        #expect(await databaseActor.cachedConnectionCount(for: paths) == 1)
    }

    @Test func databaseActorReopensConnectionAfterClosingAccountPaths() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "reopen_connection_user")
        let openCountBeforeClose = await databaseActor.openCount(for: .main, paths: paths)
        try await databaseActor.closeConnections(for: paths)

        _ = try await databaseActor.tableNames(in: .main, paths: paths)
        #expect(await databaseActor.openCount(for: .main, paths: paths) == openCountBeforeClose + 1)

        try await databaseActor.closeConnections(for: paths)
        #expect(await databaseActor.cachedConnectionCount(for: paths) == 0)

        _ = try await databaseActor.tableNames(in: .main, paths: paths)
        #expect(await databaseActor.openCount(for: .main, paths: paths) == openCountBeforeClose + 2)
        #expect(await databaseActor.cachedConnectionCount(for: paths) == 1)
    }

    @Test func databaseBootstrapCreatesCurrentDevelopmentBaselineWithoutMigrationState() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let paths = try await storageService.prepareStorage(for: "metadata_user")
        let databaseActor = DatabaseActor()

        let result = try await databaseActor.bootstrap(paths: paths)
        let mainTables = try await databaseActor.tableNames(in: .main, paths: paths)
        let searchTables = try await databaseActor.tableNames(in: .search, paths: paths)
        let fileIndexTables = try await databaseActor.tableNames(in: .fileIndex, paths: paths)
        let metadataURL = paths.cacheDirectory.appendingPathComponent("migration_meta.json")

        #expect(result.paths == paths)
        #expect(FileManager.default.fileExists(atPath: metadataURL.path) == false)
        #expect(mainTables.contains("migration_meta") == false)
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
        let columns = try await databaseActor.read(paths: paths) { db in
            let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(notification_setting);")
            return Set(rows.compactMap { $0["name"] as String? })
        }
        let repository = LocalChatRepository(database: databaseActor, paths: paths)
        let setting = try await repository.notificationSetting(for: "fresh_badge_schema_user")

        #expect(columns.contains("badge_enabled"))
        #expect(columns.contains("badge_include_muted"))
        #expect(setting.badgeEnabled == true)
        #expect(setting.badgeIncludeMuted == true)
    }

    @Test func databaseBootstrapRecreatesLegacyNotificationBadgeSettingSchemaDuringUnreleasedDevelopment() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let paths = try await storageService.prepareStorage(for: "legacy_badge_schema_user")
        let databaseActor = DatabaseActor()
        _ = try await databaseActor.write(paths: paths) { db in
            try db.execute(
                sql: """
                CREATE TABLE notification_setting (
                    user_id TEXT PRIMARY KEY,
                    is_enabled INTEGER DEFAULT 1,
                    show_preview INTEGER DEFAULT 1,
                    updated_at INTEGER
                );
                """
            )
            try db.execute(
                sql: """
                INSERT INTO notification_setting (user_id, is_enabled, show_preview, updated_at)
                VALUES (?, 1, 0, 10);
                """,
                arguments: ["legacy_badge_schema_user"]
            )
        }

        _ = try await databaseActor.bootstrap(paths: paths)
        let columns = try await databaseActor.read(paths: paths) { db in
            let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(notification_setting);")
            return Set(rows.compactMap { $0["name"] as String? })
        }
        let repository = LocalChatRepository(database: databaseActor, paths: paths)
        let setting = try await repository.notificationSetting(for: "legacy_badge_schema_user")

        #expect(columns.contains("badge_enabled"))
        #expect(columns.contains("badge_include_muted"))
        #expect(setting.showPreview == true)
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
        let indexNames = try await databaseActor.read(paths: paths) { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_emoji_%' ORDER BY name;"
            )
            return rows.compactMap { $0["name"] as String? }
        }

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

        let title = try await databaseActor.write(paths: paths) { db in
            try db.execute(
                sql: """
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
                arguments: [
                    "prepared_conversation",
                    "prepared_user",
                    ConversationType.single.rawValue,
                    "target",
                    "Sondra's GRDB",
                    "Prepared statement works",
                    100
                ]
            )
            return try String.fetchOne(
                db,
                sql: "SELECT title FROM conversation WHERE conversation_id = ?;",
                arguments: ["prepared_conversation"]
            )
        }

        #expect(title == "Sondra's GRDB")
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
            let count = try await databaseContext.databaseActor.read(in: .search, paths: databaseContext.paths) { db in
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM message_search WHERE message_id = ?;",
                    arguments: ["repair_search_message"]
                ) ?? 0
            }
            return count == 1
        }
        _ = try await databaseContext.databaseActor.write(in: .search, paths: databaseContext.paths) { db in
            try db.execute(sql: "DELETE FROM contact_search;")
            try db.execute(sql: "DELETE FROM conversation_search;")
            try db.execute(sql: "DELETE FROM message_search;")
        }

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

        #expect(emptyResults.isEmpty)
        #expect(report.steps.first { $0.step == .ftsRebuild }?.isSuccessful == true)
        #expect(report.isSuccessful)
        #expect(repairedResults.contains { $0.kind == .message && $0.messageID == "repair_search_message" })
    }

    @Test func startupDataRepairRunsWithoutMigrationStateGate() async throws {
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

        let firstReport = await repairService.runStartupIfNeeded()
        let secondReport = await repairService.runStartupIfNeeded()

        #expect(firstReport?.isSuccessful == true)
        #expect(secondReport?.isSuccessful == true)
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
        _ = try await databaseContext.databaseActor.write(paths: databaseContext.paths) { db in
            try db.execute(
                sql: """
                UPDATE media_resource
                SET remote_url = ?
                WHERE media_id = ?;
                """,
                arguments: ["https://mock-cdn.chatbridge.local/image/repair_missing", "repair_missing"]
            )
        }

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
        try await databaseContext.databaseActor.closeConnections(for: databaseContext.paths)
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
