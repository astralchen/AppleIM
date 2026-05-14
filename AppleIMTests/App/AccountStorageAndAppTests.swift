import Testing
import Foundation
import UIKit

@testable import AppleIM

extension AppleIMTests {
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
    @Test func appDependencyContainerDeletesCurrentAccountStorage() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let keyStore = InMemoryAccountDatabaseKeyStore()
        let container = try AppDependencyContainer(
            accountID: "delete_container_user",
            storageService: storageService,
            database: DatabaseActor(),
            databaseKeyStore: keyStore,
            applicationBadgeManager: CapturingApplicationBadgeManager()
        )

        let paths = try await container.prepareCurrentAccountStorage()
        let originalKey = try await keyStore.databaseKey(for: "delete_container_user")

        try await container.deleteCurrentAccountStorage()
        let regeneratedKey = try await keyStore.databaseKey(for: "delete_container_user")

        #expect(FileManager.default.fileExists(atPath: paths.rootDirectory.path) == false)
        #expect(regeneratedKey.count == 32)
        #expect(regeneratedKey != originalKey)
    }

    @MainActor
    @Test func appDependencyContainerRefreshesBadgeWithoutConversationListGate() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = TrackingAccountStorageService(rootDirectory: rootDirectory)
        let badgeManager = CapturingApplicationBadgeManager()
        let container = try AppDependencyContainer(
            accountID: "direct_startup_user",
            storageService: storageService,
            database: DatabaseActor(),
            databaseKeyStore: InMemoryAccountDatabaseKeyStore(),
            applicationBadgeManager: badgeManager
        )

        container.refreshApplicationBadge()

        var didCaptureBadgeRefresh = false
        let startedAt = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - startedAt < 5_000_000_000 {
            if await badgeManager.values().isEmpty == false {
                didCaptureBadgeRefresh = true
                break
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(didCaptureBadgeRefresh)
        #expect(await storageService.prepareCallCount == 1)
    }

    @MainActor
    @Test func appDependencyContainerHidesTabBarWhenPushingChat() throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let container = try AppDependencyContainer(
            accountID: "hide_tab_bar_user",
            storageService: TrackingAccountStorageService(rootDirectory: rootDirectory),
            database: DatabaseActor(),
            databaseKeyStore: InMemoryAccountDatabaseKeyStore(),
            applicationBadgeManager: CapturingApplicationBadgeManager()
        )
        let chatViewController = container.makeChatViewController(
            conversation: ConversationListRowState(
                id: "hide_tab_bar_conversation",
                title: "Hide Tab",
                avatarURL: nil,
                subtitle: "Open chat",
                timeText: "Now",
                unreadText: nil,
                isPinned: false,
                isMuted: false
            )
        )

        #expect(chatViewController.hidesBottomBarWhenPushed)
    }

    @MainActor
    @Test func uiTestMessageSendConfigurationKeepsUsingMockService() async throws {
        let service = AppUITestConfiguration.makeMessageSendService(
            for: AppUITestConfiguration.Configuration(
                runID: "ui_send_config",
                sendMode: .success,
                resetSession: true
            )
        )
        let result = await service.sendText(message: makeStoredTextMessage(messageID: "ui_config_message"))

        guard case let .success(ack) = result else {
            Issue.record("Expected UI test send service to use mock success")
            return
        }

        #expect(ack.serverMessageID == "server_ui_config_message")
        #expect(ack.sequence == 100)
    }
}
