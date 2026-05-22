import Testing
import Foundation
import UIKit

@testable import AppleIM

extension AppleIMTests {
    @MainActor
    @Test func appLifecycleServiceStartsNetworkRecoveryOnlyOnce() throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        let networkRecovery = NetworkRecoveryCoordinatorSpy()
        let service = try makeLifecycleService(
            accountID: "lifecycle_network_user",
            rootDirectory: rootDirectory,
            networkRecoveryCoordinator: networkRecovery
        )

        service.startNetworkRecovery()
        service.startNetworkRecovery()
        service.runDueJobsWhenNetworkIsReachable()

        #expect(networkRecovery.startCallCount == 1)
        #expect(networkRecovery.runDueJobsWhenReachableCallCount == 1)
    }

    @MainActor
    @Test func appLifecycleServiceRequestsNotificationAuthorization() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        let notificationManager = CountingLocalNotificationManager()
        let service = try makeLifecycleService(
            accountID: "lifecycle_notification_user",
            rootDirectory: rootDirectory,
            localNotificationManager: notificationManager
        )

        service.requestLocalNotificationAuthorization()

        try await waitUntil {
            await notificationManager.requestAuthorizationCallCount == 1
        }
    }

    @MainActor
    @Test func appLifecycleServiceRunsStartupDataRepairAndKeepsReport() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        let service = try makeLifecycleService(
            accountID: "lifecycle_repair_user",
            rootDirectory: rootDirectory
        )

        service.runStartupDataRepair()

        try await waitUntil {
            service.lastDataRepairReport != nil
        }
        #expect(service.lastDataRepairReport?.isSuccessful == true)
    }

    @MainActor
    @Test func mainInterfaceBuilderCreatesStableTabsAndRetainsUnreadBadgeSubscription() throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        let container = try AppDependencyContainer(
            accountID: "main_interface_user",
            storageService: FileAccountStorageService(rootDirectory: rootDirectory),
            database: DatabaseActor(),
            databaseKeyStore: InMemoryAccountDatabaseKeyStore(),
            applicationBadgeManager: CapturingApplicationBadgeManager()
        )
        let unreadBadgeController = container.makeConversationUnreadBadgeController()
        let session = AccountSession(
            userID: "main_interface_user",
            displayName: "Main Interface",
            token: "mock_token",
            loggedInAt: 1
        )

        let result = MainInterfaceBuilder().makeMainTabController(
            session: session,
            dependencies: container,
            unreadBadgeController: unreadBadgeController,
            onAccountAction: { _ in }
        )

        #expect(result.tabBarController.selectedIndex == 0)
        #expect(result.tabBarController.viewControllers?.count == 3)
        #expect(result.tabBarController.viewControllers?.first?.tabBarItem.accessibilityIdentifier == "mainTab.messages")
        _ = result.unreadBadgeCancellable
    }

    @Test func defaultMediaFileMetadataProviderReturnsNilForMissingFileSize() {
        let provider = DefaultMediaFileMetadataProvider()

        #expect(provider.fileExists(atPath: "/missing/chatbridge/\(UUID().uuidString)") == false)
        #expect(provider.fileSize(atPath: "/missing/chatbridge/\(UUID().uuidString)") == nil)
    }

    @MainActor
    private func makeLifecycleService(
        accountID: UserID,
        rootDirectory: URL,
        localNotificationManager: any LocalNotificationManaging = CountingLocalNotificationManager(),
        networkRecoveryCoordinator: any NetworkRecoveryCoordinating = NetworkRecoveryCoordinatorSpy()
    ) throws -> AppLifecycleService {
        let storeProvider = ChatStoreProvider(
            accountID: accountID,
            storageService: FileAccountStorageService(rootDirectory: rootDirectory),
            database: DatabaseActor(),
            databaseKeyStore: InMemoryAccountDatabaseKeyStore()
        )
        return AppLifecycleService(
            userID: accountID,
            storeProvider: storeProvider,
            localNotificationManager: localNotificationManager,
            networkRecoveryCoordinator: networkRecoveryCoordinator
        )
    }
}

@MainActor
private final class NetworkRecoveryCoordinatorSpy: NetworkRecoveryCoordinating {
    private(set) var startCallCount = 0
    private(set) var runDueJobsWhenReachableCallCount = 0

    func start() {
        startCallCount += 1
    }

    func runDueJobsWhenReachable() {
        runDueJobsWhenReachableCallCount += 1
    }
}

private actor CountingLocalNotificationManager: LocalNotificationManaging {
    private(set) var requestAuthorizationCallCount = 0

    func requestAuthorization() async throws -> Bool {
        requestAuthorizationCallCount += 1
        return true
    }

    func scheduleIncomingMessageNotification(_ payload: IncomingMessageNotificationPayload) async throws {}
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    pollingIntervalNanoseconds: UInt64 = 10_000_000,
    condition: () async -> Bool
) async throws {
    let start = DispatchTime.now().uptimeNanoseconds
    while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
        if await condition() {
            return
        }

        try await Task.sleep(nanoseconds: pollingIntervalNanoseconds)
    }

    Issue.record("Timed out waiting for asynchronous condition")
}
