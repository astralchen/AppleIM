//
//  AppLanguageUIKitSupport.swift
//  AppleIM
//
//  UIKit 语言切换辅助
//

import UIKit

@MainActor
extension UIView {
    /// 递归应用当前语言的布局方向，并标记约束和布局需要刷新。
    func applyLanguageSemanticContentAttribute(_ attribute: UISemanticContentAttribute) {
        semanticContentAttribute = attribute
        subviews.forEach { $0.applyLanguageSemanticContentAttribute(attribute) }
        setNeedsUpdateConstraints()
        setNeedsLayout()
    }
}

@MainActor
extension UIWindow {
    /// 从窗口层统一刷新方向，覆盖 sheet / presentation container 等不属于业务控制器 view 树的 UIKit 容器。
    func applyAppLanguageContext(_ context: AppLanguageContext) {
        applyLanguageSemanticContentAttribute(context.semanticContentAttribute)
        rootViewController?.notifyLanguageChangeRecursively(context)
        setNeedsUpdateConstraints()
        setNeedsLayout()
        layoutIfNeeded()
    }
}

@MainActor
extension UIViewController {
    /// 递归通知当前控制器树刷新语言，保留现有页面栈和业务状态。
    func notifyLanguageChangeRecursively(_ context: AppLanguageContext) {
        view.applyLanguageSemanticContentAttribute(context.semanticContentAttribute)
        applyLanguageSemanticContentAttributeToControllerChrome(context.semanticContentAttribute)

        if let updatable = self as? AppLanguageUpdatable {
            updatable.applyLanguageChange(context)
        }

        if let tabBarController = self as? UITabBarController {
            tabBarController.viewControllers?.forEach { $0.notifyLanguageChangeRecursively(context) }
        } else if let navigationController = self as? UINavigationController {
            navigationController.viewControllers.forEach { $0.notifyLanguageChangeRecursively(context) }
        } else {
            children.forEach { $0.notifyLanguageChangeRecursively(context) }
        }

        presentedViewController?.notifyLanguageChangeRecursively(context)
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    /// UIKit 容器的导航栏、Tab 栏和自定义 bar button view 不总在当前页面 view 树内，需要单独刷新方向。
    private func applyLanguageSemanticContentAttributeToControllerChrome(_ attribute: UISemanticContentAttribute) {
        navigationController?.view.applyLanguageSemanticContentAttribute(attribute)
        navigationController?.navigationBar.applyLanguageSemanticContentAttribute(attribute)
        navigationController?.toolbar.applyLanguageSemanticContentAttribute(attribute)
        tabBarController?.view.applyLanguageSemanticContentAttribute(attribute)
        tabBarController?.tabBar.applyLanguageSemanticContentAttribute(attribute)
        navigationItem.titleView?.applyLanguageSemanticContentAttribute(attribute)
        navigationItem.leftBarButtonItems?.forEach { $0.customView?.applyLanguageSemanticContentAttribute(attribute) }
        navigationItem.rightBarButtonItems?.forEach { $0.customView?.applyLanguageSemanticContentAttribute(attribute) }
    }
}
