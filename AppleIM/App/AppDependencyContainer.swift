//
//  AppDependencyContainer.swift
//  AppleIM
//
//  应用依赖容器
//  管理全局依赖的创建和注入

import UIKit

/// 应用依赖容器
///
/// 负责创建和管理应用级别的依赖对象
/// 提供工厂方法创建各个页面的 ViewController
@MainActor
final class AppDependencyContainer {
    /// 聊天存储提供者
    private let storeProvider: ChatStoreProvider
    /// 统一模拟后台推送服务
    private let simulatedIncomingPushService: SimulatedIncomingPushService
    /// 消息发送服务
    private let messageSendService: any MessageSendService
    /// 媒体文件存储
    private let mediaFileStore: any MediaFileStoring
    /// 媒体上传服务
    private let mediaUploadService: any MediaUploadService
    /// 本地通知管理器
    private let localNotificationManager: any LocalNotificationManaging
    /// App 角标管理器
    private let applicationBadgeManager: any ApplicationBadgeManaging
    /// 当前登录用户 ID
    let accountID: UserID
    /// 当前登录用户头像 URL
    private let accountAvatarURL: String?
    /// 账号存储服务
    private let storageService: any AccountStorageService
    /// 网络恢复协调器
    private let networkRecoveryCoordinator: NetworkRecoveryCoordinator
    /// UI 自动化测试模式
    let isUITesting: Bool
    /// 最近一次后台数据修复报告
    private(set) var lastDataRepairReport: DataRepairReport?
    /// 网络恢复协调器启动幂等标记，避免重复订阅网络状态。
    private var didStartNetworkRecovery = false

    init(
        accountID: UserID,
        accountAvatarURL: String? = nil,
        storageService: (any AccountStorageService)? = nil,
        database: DatabaseActor = DatabaseActor(),
        databaseKeyStore: any AccountDatabaseKeyStore = KeychainAccountDatabaseKeyStore(),
        messageSendService: any MessageSendService = MockMessageSendService(),
        serverMessageSendConfiguration: ServerMessageSendService.Configuration? = nil,
        mediaUploadService: any MediaUploadService = MockMediaUploadService(),
        localNotificationManager: any LocalNotificationManaging = UserNotificationCenterNotificationManager(),
        applicationBadgeManager: any ApplicationBadgeManaging = UIKitApplicationBadgeManager()
    ) throws {
        let uiTestConfiguration = AppUITestConfiguration.current
        let storageService = try storageService
            ?? uiTestConfiguration.map(AppUITestConfiguration.makeStorageService)
            ?? AccountStorageFactory.makeDefaultService()
        let resolvedDatabaseKeyStore: any AccountDatabaseKeyStore = uiTestConfiguration == nil
            ? databaseKeyStore
            : InMemoryAccountDatabaseKeyStore()
        let resolvedMessageSendService: any MessageSendService
        if let uiTestConfiguration {
            resolvedMessageSendService = AppUITestConfiguration.makeMessageSendService(for: uiTestConfiguration)
        } else if let serverMessageSendConfiguration {
            resolvedMessageSendService = ServerMessageSendService(configuration: serverMessageSendConfiguration)
        } else {
            resolvedMessageSendService = messageSendService
        }

        self.isUITesting = uiTestConfiguration != nil
        self.accountID = accountID
        self.accountAvatarURL = accountAvatarURL
        self.storageService = storageService
        self.messageSendService = resolvedMessageSendService
        self.mediaUploadService = mediaUploadService
        self.localNotificationManager = localNotificationManager
        self.applicationBadgeManager = applicationBadgeManager
        self.mediaFileStore = AccountMediaFileStore(accountID: accountID, storageService: storageService)
        self.storeProvider = ChatStoreProvider(
            accountID: accountID,
            storageService: storageService,
            database: database,
            databaseKeyStore: resolvedDatabaseKeyStore,
            localNotificationManager: localNotificationManager,
            applicationBadgeManager: applicationBadgeManager
        )
        self.simulatedIncomingPushService = SimulatedIncomingPushService(
            userID: accountID,
            storeProvider: storeProvider
        )
        self.networkRecoveryCoordinator = NetworkRecoveryCoordinator(
            userID: accountID,
            storeProvider: storeProvider,
            sendService: resolvedMessageSendService,
            mediaUploadService: mediaUploadService
        )
    }

    func startNetworkRecovery() {
        startNetworkRecoveryNow()
    }

    private func startNetworkRecoveryNow() {
        guard !didStartNetworkRecovery else { return }

        didStartNetworkRecovery = true
        networkRecoveryCoordinator.start()
    }

    func requestLocalNotificationAuthorization() {
        let localNotificationManager = localNotificationManager
        Task {
            _ = try? await localNotificationManager.requestAuthorization()
        }
    }

    func runDueJobsWhenNetworkIsReachable() {
        networkRecoveryCoordinator.runDueJobsWhenReachable()
    }

    func refreshApplicationBadge() {
        refreshApplicationBadgeNow()
    }

    private func refreshApplicationBadgeNow() {
        let storeProvider = storeProvider
        let userID = accountID
        Task {
            guard let repository = try? await storeProvider.repository() else {
                return
            }

            _ = try? await repository.refreshApplicationBadge(userID: userID)
        }
    }

    func runStartupDataRepair() {
        runStartupDataRepairNow()
    }

    private func runStartupDataRepairNow() {
        let storeProvider = storeProvider
        Task { [weak self] in
            guard let repairService = try? await storeProvider.dataRepairService() else {
                return
            }

            guard let report = await repairService.runStartupIfNeeded() else {
                return
            }

            await MainActor.run {
                self?.lastDataRepairReport = report
            }
        }
    }

    func makeConversationListViewController(
        onSelectConversation: @escaping (ConversationListRowState) -> Void
    ) -> ConversationListViewController {
        let useCase = LocalConversationListUseCase(
            userID: accountID,
            storeProvider: storeProvider,
            simulatedIncomingPushService: simulatedIncomingPushService
        )
        let searchUseCase = LocalSearchUseCase(
            userID: accountID,
            storeProvider: storeProvider
        )
        let viewModel = ConversationListViewModel(useCase: useCase)
        let searchViewModel = SearchViewModel(useCase: searchUseCase)
        return ConversationListViewController(
            viewModel: viewModel,
            searchViewModel: searchViewModel,
            onSelectConversation: onSelectConversation
        )
    }

    func makeAccountViewController(
        session: AccountSession,
        onAction: @escaping (AccountAction) -> Void
    ) -> AccountViewController {
        AccountViewController(
            state: AccountViewState(session: session),
            onAction: onAction
        )
    }

    func makeContactListViewController(router: any AppRouting) -> ContactListViewController {
        let useCase = LocalContactListUseCase(
            userID: accountID,
            storeProvider: storeProvider
        )
        let viewModel = ContactListViewModel(useCase: useCase)
        return ContactListViewController(
            viewModel: viewModel,
            onSelectConversation: { [router] conversation in
                router.showChat(conversation: conversation)
            }
        )
    }

    func makeChatViewController(conversation: ConversationListRowState) -> ChatViewController {
        let useCase = StoreBackedChatUseCase(
            userID: accountID,
            conversationID: conversation.id,
            currentUserAvatarURL: accountAvatarURL,
            conversationAvatarURL: conversation.avatarURL,
            storeProvider: storeProvider,
            sendService: messageSendService,
            mediaFileStore: mediaFileStore,
            mediaUploadService: mediaUploadService,
            simulatedIncomingPushService: simulatedIncomingPushService
        )
        let viewModel = ChatViewModel(useCase: useCase, title: conversation.title)
        let viewController = ChatViewController(viewModel: viewModel)
        viewController.hidesBottomBarWhenPushed = true
        return viewController
    }

    func prepareCurrentAccountStorage() async throws -> AccountStoragePaths {
        _ = try await storeProvider.repository()
        return try await storageService.prepareStorage(for: accountID)
    }

    func deleteCurrentAccountStorage() async throws {
        try await storeProvider.deleteAccountStorage()
    }

    func closeCurrentAccountConnections() async throws {
        try await storeProvider.closeAccountConnections()
    }
}

private extension UIViewController {
    var topVisibleViewController: UIViewController {
        if let tabBarController = self as? UITabBarController {
            return tabBarController.selectedViewController?.topVisibleViewController ?? tabBarController
        }

        if let navigationController = self as? UINavigationController {
            return navigationController.visibleViewController?.topVisibleViewController ?? navigationController
        }

        if let presentedViewController {
            return presentedViewController.topVisibleViewController
        }

        return self
    }
}
