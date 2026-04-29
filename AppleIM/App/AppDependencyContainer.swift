//
//  AppDependencyContainer.swift
//  AppleIM
//

import UIKit

@MainActor
final class AppDependencyContainer {
    private let storeProvider: ChatStoreProvider
    private let messageSendService: any MessageSendService
    private let demoUserID: UserID
    private let networkRecoveryCoordinator: NetworkRecoveryCoordinator

    init(
        demoUserID: UserID = "demo_user",
        storageService: (any AccountStorageService)? = nil,
        database: DatabaseActor = DatabaseActor(),
        messageSendService: any MessageSendService = MockMessageSendService()
    ) throws {
        let storageService = try storageService ?? AccountStorageFactory.makeDefaultService()
        self.demoUserID = demoUserID
        self.messageSendService = messageSendService
        self.storeProvider = ChatStoreProvider(
            accountID: demoUserID,
            storageService: storageService,
            database: database
        )
        self.networkRecoveryCoordinator = NetworkRecoveryCoordinator(
            userID: demoUserID,
            storeProvider: storeProvider,
            sendService: messageSendService
        )
    }

    func startNetworkRecovery() {
        networkRecoveryCoordinator.start()
    }

    func runDueJobsWhenNetworkIsReachable() {
        networkRecoveryCoordinator.runDueJobsWhenReachable()
    }

    func makeConversationListViewController() -> ConversationListViewController {
        let useCase = LocalConversationListUseCase(
            userID: demoUserID,
            storeProvider: storeProvider
        )
        let viewModel = ConversationListViewModel(useCase: useCase)
        return ConversationListViewController(viewModel: viewModel) { conversation in
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
            sendService: messageSendService
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
