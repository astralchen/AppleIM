import UIKit

/// UIKit Demo 的 scene 生命周期入口。
///
/// 根控制器是 `UINavigationController`，首页展示用法目录，详情页展示 planner 输出。
@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let navigationController = UINavigationController(rootViewController: DemoHomeViewController())
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        self.window = window
    }
}
