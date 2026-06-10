//
//  AppDependencyContainer.swift
//  AppleIM
//
//  应用依赖容器
//  管理全局依赖的创建和注入

import Combine
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
    /// 运行时配置
    private let runtimeConfiguration: AppRuntimeConfiguration
    /// App 级生命周期副作用服务
    private let lifecycleService: AppLifecycleService
    /// UI 自动化测试模式
    var isUITesting: Bool {
        runtimeConfiguration.isUITesting
    }
    /// 最近一次后台数据修复报告
    var lastDataRepairReport: DataRepairReport? {
        lifecycleService.lastDataRepairReport
    }

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
        applicationBadgeManager: any ApplicationBadgeManaging = UIKitApplicationBadgeManager(),
        runtimeConfiguration: AppRuntimeConfiguration? = nil
    ) throws {
        let uiTestConfiguration = AppUITestConfiguration.current
        let runtimeConfiguration = runtimeConfiguration
            ?? AppRuntimeConfiguration.current(serverMessageSendConfiguration: serverMessageSendConfiguration)
        let storageService = try storageService
            ?? uiTestConfiguration.map(AppUITestConfiguration.makeStorageService)
            ?? AccountStorageFactory.makeDefaultService()
        let resolvedDatabaseKeyStore: any AccountDatabaseKeyStore = uiTestConfiguration == nil
            ? databaseKeyStore
            : InMemoryAccountDatabaseKeyStore()
        let resolvedMessageSendService: any MessageSendService
        if let uiTestConfiguration {
            resolvedMessageSendService = AppUITestConfiguration.makeMessageSendService(for: uiTestConfiguration)
        } else if let serverMessageSendConfiguration = runtimeConfiguration.serverMessageSendConfiguration {
            resolvedMessageSendService = ServerMessageSendService(configuration: serverMessageSendConfiguration)
        } else {
            resolvedMessageSendService = messageSendService
        }

        self.runtimeConfiguration = runtimeConfiguration
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
        let networkRecoveryCoordinator = NetworkRecoveryCoordinator(
            userID: accountID,
            storeProvider: storeProvider,
            sendService: resolvedMessageSendService,
            mediaUploadService: mediaUploadService
        )
        self.networkRecoveryCoordinator = networkRecoveryCoordinator
        self.lifecycleService = AppLifecycleService(
            userID: accountID,
            storeProvider: storeProvider,
            localNotificationManager: localNotificationManager,
            networkRecoveryCoordinator: networkRecoveryCoordinator
        )
    }

    func startNetworkRecovery() {
        lifecycleService.startNetworkRecovery()
    }

    func requestLocalNotificationAuthorization() {
        lifecycleService.requestLocalNotificationAuthorization()
    }

    func runDueJobsWhenNetworkIsReachable() {
        lifecycleService.runDueJobsWhenNetworkIsReachable()
    }

    func refreshApplicationBadge() {
        lifecycleService.refreshApplicationBadge()
    }

    func runStartupDataRepair() {
        lifecycleService.runStartupDataRepair()
    }

    func makeConversationListViewController(
        onSelectConversation: @escaping (ConversationListRowState) -> Void
    ) -> ConversationListViewController {
        let conversationService = LocalConversationListService(
            userID: accountID,
            storeProvider: storeProvider,
            simulatedIncomingPushService: simulatedIncomingPushService
        )
        let searchService = LocalSearchService(
            userID: accountID,
            storeProvider: storeProvider
        )
        let viewModel = ConversationListViewModel(useCase: conversationService)
        let searchViewModel = SearchViewModel(useCase: searchService)
        return ConversationListViewController(
            viewModel: viewModel,
            searchViewModel: searchViewModel,
            onSelectConversation: onSelectConversation
        )
    }

    func makeConversationUnreadBadgeController() -> ConversationUnreadBadgeController {
        ConversationUnreadBadgeController(
            userID: accountID,
            storeProvider: storeProvider
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
        let contactService = LocalContactListService(
            userID: accountID,
            storeProvider: storeProvider
        )
        let viewModel = ContactListViewModel(useCase: contactService)
        return ContactListViewController(
            viewModel: viewModel,
            onSelectConversation: { [router] conversation in
                router.showChat(conversation: conversation)
            }
        )
    }

    func makeChatViewController(
        conversation: ConversationListRowState,
        unreadBadgePublisher: AnyPublisher<String?, Never> = Just<String?>(nil).eraseToAnyPublisher()
    ) -> ChatViewController {
        let chatServicesFactory = StoreBackedChatServicesFactory(
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
        let viewModel = ChatViewModel(
            dependencies: chatServicesFactory.makeViewModelDependencies(),
            title: conversation.title
        )
        let viewController = ChatViewController(
            viewModel: viewModel,
            unreadBadgePublisher: unreadBadgePublisher
        )
        viewController.hidesBottomBarWhenPushed = true
        return viewController
    }

    func prepareCurrentAccountStorage() async throws -> AccountStoragePaths {
        _ = try await storeProvider.accountStore()
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
