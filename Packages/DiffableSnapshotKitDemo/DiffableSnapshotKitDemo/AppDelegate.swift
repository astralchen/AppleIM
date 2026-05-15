import UIKit

/// UIKit Demo 的应用入口。
///
/// 这个工程是标准 UIKit iOS App，不再使用 Swift Playgrounds 的
/// `AppleProductTypes`。窗口创建交给 `SceneDelegate`，这里保留最小生命周期实现。
@main
@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
    /// Demo 主窗口。
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let navigationController = UINavigationController(rootViewController: DemoHomeViewController())
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
