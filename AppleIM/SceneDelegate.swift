//
//  SceneDelegate.swift
//  AppleIM
//
//  场景委托
//  管理 UI 场景的生命周期和依赖注入

import UIKit

/// 场景委托
///
/// 负责创建和管理应用的 UI 窗口和依赖容器
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    /// 主窗口
    var window: UIWindow?
    /// 依赖容器
    private var dependencies: AppDependencyContainer?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)

        do {
            let dependencies = try AppDependencyContainer()
            self.dependencies = dependencies
            dependencies.startNetworkRecovery()
            window.rootViewController = UINavigationController(
                rootViewController: dependencies.makeConversationListViewController()
            )
        } catch {
            window.rootViewController = makeStartupErrorViewController()
        }

        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
    }

    /// 场景变为活跃状态
    ///
    /// 触发待处理任务的重试
    func sceneDidBecomeActive(_ scene: UIScene) {
        dependencies?.runDueJobsWhenNetworkIsReachable()
    }

    func sceneWillResignActive(_ scene: UIScene) {
    }

    /// 场景即将进入前台
    ///
    /// 触发待处理任务的重试
    func sceneWillEnterForeground(_ scene: UIScene) {
        dependencies?.runDueJobsWhenNetworkIsReachable()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
    }
}

/// 创建启动错误页面
private func makeStartupErrorViewController() -> UIViewController {
    let viewController = UIViewController()
    viewController.view.backgroundColor = .systemBackground

    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.text = "Unable to start ChatBridge"
    label.textColor = .secondaryLabel
    label.font = .preferredFont(forTextStyle: .body)

    viewController.view.addSubview(label)

    NSLayoutConstraint.activate([
        label.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
        label.centerYAnchor.constraint(equalTo: viewController.view.centerYAnchor)
    ])

    return viewController
}
