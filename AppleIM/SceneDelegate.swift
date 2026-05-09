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

    /// 场景连接到会话
    ///
    /// 流程：
    /// 1. 创建主窗口
    /// 2. 检查是否需要重置会话（UI 测试）
    /// 3. 加载已保存的会话，显示主界面或登录界面
    /// 4. 显示窗口
    ///
    /// - Parameters:
    ///   - scene: UI 场景
    ///   - session: 场景会话
    ///   - connectionOptions: 连接选项
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

    /// 场景断开连接
    ///
    /// 场景被系统释放时调用
    ///
    /// - Parameter scene: UI 场景
    func sceneDidDisconnect(_ scene: UIScene) {
    }

    /// 场景变为活跃状态
    ///
    /// 触发待处理任务的重试
    ///
    /// - Parameter scene: UI 场景
    func sceneDidBecomeActive(_ scene: UIScene) {
        guard dependencies?.isUITesting != true else {
            return
        }

        dependencies?.runDueJobsWhenNetworkIsReachable()
        dependencies?.refreshApplicationBadge()
    }

    /// 场景即将变为非活跃状态
    ///
    /// 场景失去焦点时调用
    ///
    /// - Parameter scene: UI 场景
    func sceneWillResignActive(_ scene: UIScene) {
    }

    /// 场景即将进入前台
    ///
    /// 触发待处理任务的重试
    ///
    /// - Parameter scene: UI 场景
    func sceneWillEnterForeground(_ scene: UIScene) {
        guard dependencies?.isUITesting != true else {
            return
        }

        dependencies?.runDueJobsWhenNetworkIsReachable()
        dependencies?.refreshApplicationBadge()
    }

    /// 场景进入后台
    ///
    /// 场景进入后台时调用
    ///
    /// - Parameter scene: UI 场景
    func sceneDidEnterBackground(_ scene: UIScene) {
    }

    /// 显示登录界面
    ///
    /// 清空依赖容器，显示登录页面
    ///
    /// - Parameter window: 主窗口
    private func showLoginInterface(in window: UIWindow) {
        dependencies = nil
        window.rootViewController = makeLoginViewController()
    }

    /// 结束当前会话
    ///
    /// 清空会话缓存，返回登录界面
    private func endCurrentSession() {
        sessionStore.clearSession()
        guard let window else {
            dependencies = nil
            return
        }

        showLoginInterface(in: window)
    }

    /// 删除当前账号本地数据后结束会话。
    private func deleteCurrentAccountLocalData() {
        guard let dependencies else {
            endCurrentSession()
            return
        }

        Task { @MainActor [weak self] in
            do {
                try await dependencies.deleteCurrentAccountStorage()
                self?.endCurrentSession()
            } catch {
                self?.showLocalDataDeletionError()
            }
        }
    }

    /// 显示当前账号本地数据删除失败提示。
    private func showLocalDataDeletionError() {
        let alertController = UIAlertController(
            title: "Unable to Delete Local Data",
            message: "Please try again.",
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "OK", style: .default))

        window?.rootViewController?.topVisibleViewController.present(alertController, animated: true)
    }

    /// 创建登录视图控制器
    ///
    /// 创建登录页面，登录成功后显示主界面
    ///
    /// - Returns: 登录视图控制器
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

    /// 显示主界面
    ///
    /// 流程：
    /// 1. 创建依赖容器
    /// 2. 请求通知授权（非 UI 测试）
    /// 3. 启动网络恢复（非 UI 测试）
    /// 4. 刷新应用角标
    /// 5. 运行启动数据修复
    /// 6. 创建会话列表导航控制器
    ///
    /// - Parameters:
    ///   - session: 账号会话
    ///   - window: 主窗口
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
                rootViewController: dependencies.makeConversationListViewController { [weak self] action in
                    switch action {
                    case .switchAccount, .logOut:
                        self?.endCurrentSession()
                    case .deleteLocalData:
                        self?.deleteCurrentAccountLocalData()
                    }
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
