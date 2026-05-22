//
//  MainInterfaceBuilder.swift
//  AppleIM
//
//  登录后主界面构建
//

import Combine
import UIKit

/// 主界面构建结果。
@MainActor
struct MainInterfaceBuildResult {
    /// 根 Tab 控制器。
    let tabBarController: UITabBarController
    /// 未读徽标订阅。
    let unreadBadgeCancellable: AnyCancellable
}

/// 登录后主界面构建器。
@MainActor
final class MainInterfaceBuilder {
    func makeMainTabController(
        session: AccountSession,
        dependencies: AppDependencyContainer,
        unreadBadgeController: ConversationUnreadBadgeController,
        onAccountAction: @escaping (AccountAction) -> Void
    ) -> MainInterfaceBuildResult {
        let messagesNavigationController = UINavigationController()
        let unreadBadgePublisher = unreadBadgeController.badgePublisher
        let conversationListViewController = dependencies.makeConversationListViewController { [weak messagesNavigationController, weak dependencies] conversation in
            guard let chatViewController = dependencies?.makeChatViewController(
                conversation: conversation,
                unreadBadgePublisher: unreadBadgePublisher
            ) else {
                return
            }

            messagesNavigationController?.pushViewController(chatViewController, animated: true)
        }
        let messagesTabBarItem = UITabBarItem(
            title: L10n.shared.tr("conversation.title"),
            image: UIImage(systemName: "message"),
            selectedImage: UIImage(systemName: "message.fill")
        )
        messagesTabBarItem.accessibilityIdentifier = "mainTab.messages"
        let unreadBadgeCancellable = unreadBadgePublisher
            .sink { badgeText in
                messagesTabBarItem.badgeValue = badgeText
            }
        conversationListViewController.tabBarItem = messagesTabBarItem
        messagesNavigationController.tabBarItem = messagesTabBarItem
        messagesNavigationController.viewControllers = [conversationListViewController]

        let contactNavigationController = UINavigationController()
        let contactRouter = MainAppRouter(
            navigationController: contactNavigationController,
            dependencies: dependencies
        )
        let contactListViewController = dependencies.makeContactListViewController(router: contactRouter)
        contactNavigationController.viewControllers = [contactListViewController]
        contactNavigationController.tabBarItem = UITabBarItem(
            title: L10n.shared.tr("contacts.title"),
            image: UIImage(systemName: "person.2"),
            selectedImage: UIImage(systemName: "person.2.fill")
        )
        contactNavigationController.tabBarItem.accessibilityIdentifier = "mainTab.contacts"

        let accountViewController = dependencies.makeAccountViewController(
            session: session,
            onAction: onAccountAction
        )
        let accountNavigationController = UINavigationController(rootViewController: accountViewController)
        accountNavigationController.tabBarItem = accountViewController.tabBarItem

        let tabBarController = UITabBarController()
        tabBarController.viewControllers = [
            messagesNavigationController,
            contactNavigationController,
            accountNavigationController
        ]
        tabBarController.selectedIndex = 0

        return MainInterfaceBuildResult(
            tabBarController: tabBarController,
            unreadBadgeCancellable: unreadBadgeCancellable
        )
    }
}
