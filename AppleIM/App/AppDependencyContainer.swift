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
    /// 演示用户 ID
    private let demoUserID: UserID
    /// 网络恢复协调器
    private let networkRecoveryCoordinator: NetworkRecoveryCoordinator

    init(
        demoUserID: UserID = "demo_user",
        storageService: (any AccountStorageService)? = nil,
        database: DatabaseActor = DatabaseActor(),
        messageSendService: any MessageSendService = MockMessageSendService(),
        mediaUploadService: any MediaUploadService = MockMediaUploadService(),
        localNotificationManager: any LocalNotificationManaging = UserNotificationCenterNotificationManager(),
        applicationBadgeManager: any ApplicationBadgeManaging = UIKitApplicationBadgeManager()
    ) throws {
        let storageService = try storageService ?? AccountStorageFactory.makeDefaultService()
        self.demoUserID = demoUserID
        self.messageSendService = messageSendService
        self.mediaUploadService = mediaUploadService
        self.localNotificationManager = localNotificationManager
        self.applicationBadgeManager = applicationBadgeManager
        self.mediaFileStore = AccountMediaFileStore(accountID: demoUserID, storageService: storageService)
        self.storeProvider = ChatStoreProvider(
            accountID: demoUserID,
            storageService: storageService,
            database: database,
            localNotificationManager: localNotificationManager,
            applicationBadgeManager: applicationBadgeManager
        )
        self.networkRecoveryCoordinator = NetworkRecoveryCoordinator(
            userID: demoUserID,
            storeProvider: storeProvider,
            sendService: messageSendService,
            mediaUploadService: mediaUploadService
        )
    }

    func startNetworkRecovery() {
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
        let storeProvider = storeProvider
        let userID = demoUserID
        Task {
            guard let repository = try? await storeProvider.repository() else {
                return
            }

            _ = try? await repository.refreshApplicationBadge(userID: userID)
        }
    }

    func makeConversationListViewController() -> ConversationListViewController {
        let useCase = LocalConversationListUseCase(
            userID: demoUserID,
            storeProvider: storeProvider
        )
        let searchUseCase = LocalSearchUseCase(
            userID: demoUserID,
            storeProvider: storeProvider
        )
        let viewModel = ConversationListViewModel(useCase: useCase)
        let searchViewModel = SearchViewModel(useCase: searchUseCase)
        return ConversationListViewController(viewModel: viewModel, searchViewModel: searchViewModel) { conversation in
            let chatViewController = self.makeChatViewController(conversation: conversation)
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first?
                .rootViewController?
                .topVisibleViewController
                .navigationController?
                .pushViewController(chatViewController, animated: true)
        }
    }

    func makeChatViewController(conversation: ConversationListRowState) -> ChatViewController {
        let useCase = StoreBackedChatUseCase(
            userID: demoUserID,
            conversationID: conversation.id,
            storeProvider: storeProvider,
            sendService: messageSendService,
            mediaFileStore: mediaFileStore,
            mediaUploadService: mediaUploadService
        )
        let viewModel = ChatViewModel(useCase: useCase, title: conversation.title)
        return ChatViewController(viewModel: viewModel)
    }
}

private extension UIViewController {
    var topVisibleViewController: UIViewController {
        if let navigationController = self as? UINavigationController {
            return navigationController.visibleViewController?.topVisibleViewController ?? navigationController
        }

        if let presentedViewController {
            return presentedViewController.topVisibleViewController
        }

        return self
    }
}
