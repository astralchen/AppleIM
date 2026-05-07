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
    /// 登录态缓存
    private let sessionStore: any AccountSessionStore = UserDefaultsAccountSessionStore()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        self.window = window

        if AppUITestConfiguration.current?.resetSession == true {
            sessionStore.clearSession()
        }

        if let accountSession = sessionStore.loadSession() {
            showMainInterface(for: accountSession, in: window)
        } else {
            showLoginInterface(in: window)
        }

        window.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
    }

    /// 场景变为活跃状态
    ///
    /// 触发待处理任务的重试
    func sceneDidBecomeActive(_ scene: UIScene) {
        guard dependencies?.isUITesting != true else {
            return
        }

        dependencies?.runDueJobsWhenNetworkIsReachable()
        dependencies?.refreshApplicationBadge()
    }

    func sceneWillResignActive(_ scene: UIScene) {
    }

    /// 场景即将进入前台
    ///
    /// 触发待处理任务的重试
    func sceneWillEnterForeground(_ scene: UIScene) {
        guard dependencies?.isUITesting != true else {
            return
        }

        dependencies?.runDueJobsWhenNetworkIsReachable()
        dependencies?.refreshApplicationBadge()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
    }

    private func showLoginInterface(in window: UIWindow) {
        dependencies = nil
        window.rootViewController = makeLoginViewController()
    }

    private func endCurrentSession() {
        sessionStore.clearSession()
        guard let window else {
            dependencies = nil
            return
        }

        showLoginInterface(in: window)
    }

    private func makeLoginViewController() -> UIViewController {
        let viewModel = LoginViewModel(
            authService: LocalAccountAuthService(),
            sessionStore: sessionStore
        )
        return LoginViewController(viewModel: viewModel) { [weak self] session in
            guard let self, let window = self.window else {
                return
            }

            self.showMainInterface(for: session, in: window)
        }
    }

    private func showMainInterface(for session: AccountSession, in window: UIWindow) {
        do {
            let dependencies = try AppDependencyContainer(accountID: session.userID, accountAvatarURL: session.avatarURL)
            self.dependencies = dependencies
            if !dependencies.isUITesting {
                dependencies.requestLocalNotificationAuthorization()
                dependencies.startNetworkRecovery()
            }
            dependencies.refreshApplicationBadge()
            dependencies.runStartupDataRepair()
            let rootViewController = UINavigationController(
                rootViewController: dependencies.makeConversationListViewController { [weak self] _ in
                    self?.endCurrentSession()
                }
            )
            window.rootViewController = rootViewController
        } catch {
            window.rootViewController = makeStartupErrorViewController()
        }
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
