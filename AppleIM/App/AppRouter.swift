//
//  AppRouter.swift
//  AppleIM
//
//  App 级页面路由
//  将页面跳转从依赖构造层移到专门的路由对象

import UIKit

/// App 主流程路由接口。
@MainActor
protocol AppRouting: AnyObject {
    /// 打开聊天页。
    func showChat(conversation: ConversationListRowState)
}

/// 基于导航控制器的主流程路由。
@MainActor
final class MainAppRouter: AppRouting {
    private weak var navigationController: UINavigationController?
    private weak var dependencies: AppDependencyContainer?

    init(
        navigationController: UINavigationController,
        dependencies: AppDependencyContainer
    ) {
        self.navigationController = navigationController
        self.dependencies = dependencies
    }

    func showChat(conversation: ConversationListRowState) {
        guard let chatViewController = dependencies?.makeChatViewController(conversation: conversation) else {
            return
        }

        navigationController?.pushViewController(chatViewController, animated: true)
    }
}
