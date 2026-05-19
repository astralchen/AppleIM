//
//  KeyboardNotificationPayload.swift
//  AppleIM
//
//  类型化键盘通知载荷，隔离 UIKit userInfo 字典解析。
//

import UIKit

/// UIKit 键盘通知类型。
enum KeyboardNotificationKind: CaseIterable, Equatable, Sendable {
    case willShow
    case didShow
    case willHide
    case didHide
    case willChangeFrame
    case didChangeFrame

    /// 对应的 UIKit 通知名称。
    var notificationName: Notification.Name {
        switch self {
        case .willShow:
            UIResponder.keyboardWillShowNotification
        case .didShow:
            UIResponder.keyboardDidShowNotification
        case .willHide:
            UIResponder.keyboardWillHideNotification
        case .didHide:
            UIResponder.keyboardDidHideNotification
        case .willChangeFrame:
            UIResponder.keyboardWillChangeFrameNotification
        case .didChangeFrame:
            UIResponder.keyboardDidChangeFrameNotification
        }
    }

    /// 从 UIKit 通知名称恢复键盘通知类型。
    init?(name: Notification.Name) {
        guard let kind = Self.allCases.first(where: { $0.notificationName == name }) else {
            return nil
        }
        self = kind
    }
}

/// 键盘通知的类型化载荷。
@MainActor
struct KeyboardNotificationPayload: Equatable {
    /// 键盘通知类型。
    let kind: KeyboardNotificationKind
    /// UIKit 提供的键盘变化起始 frame。
    let beginFrame: CGRect?
    /// UIKit 提供的键盘变化结束 frame。
    let endFrame: CGRect?
    /// UIKit 键盘动画时长。
    let animationDuration: TimeInterval
    /// UIKit 键盘动画曲线原始值。
    let animationCurveRawValue: UInt
    /// 通知是否来自当前 App 的本地键盘。
    let isLocal: Bool?

    /// 可直接传给 UIView 动画的键盘动画选项。
    var animationOptions: UIView.AnimationOptions {
        UIView.AnimationOptions(rawValue: animationCurveRawValue << 16)
    }

    /// 从 UIKit Notification 解析类型化键盘载荷。
    init?(_ notification: Notification) {
        guard let kind = KeyboardNotificationKind(name: notification.name) else {
            return nil
        }

        self.kind = kind
        beginFrame = Self.readRect(notification.userInfo?[UIResponder.keyboardFrameBeginUserInfoKey])
        endFrame = Self.readRect(notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey])
        animationDuration = Self.readTimeInterval(notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey]) ?? 0.25
        animationCurveRawValue = Self.readUInt(notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey])
            ?? UIView.AnimationOptions.curveEaseInOut.rawValue
        isLocal = Self.readBool(notification.userInfo?[UIResponder.keyboardIsLocalUserInfoKey])
    }

    /// 测试或兼容旧通知发布时使用的显式初始化入口。
    init(
        kind: KeyboardNotificationKind,
        beginFrame: CGRect? = nil,
        endFrame: CGRect? = nil,
        animationDuration: TimeInterval = 0.25,
        animationCurveRawValue: UInt = UIView.AnimationOptions.curveEaseInOut.rawValue,
        isLocal: Bool? = nil
    ) {
        self.kind = kind
        self.beginFrame = beginFrame
        self.endFrame = endFrame
        self.animationDuration = animationDuration
        self.animationCurveRawValue = animationCurveRawValue
        self.isLocal = isLocal
    }

    /// 生成兼容 UIKit NotificationCenter 的 userInfo。
    var userInfo: [AnyHashable: Any] {
        var info: [AnyHashable: Any] = [
            UIResponder.keyboardAnimationDurationUserInfoKey: animationDuration,
            UIResponder.keyboardAnimationCurveUserInfoKey: animationCurveRawValue
        ]
        if let beginFrame {
            info[UIResponder.keyboardFrameBeginUserInfoKey] = beginFrame
        }
        if let endFrame {
            info[UIResponder.keyboardFrameEndUserInfoKey] = endFrame
        }
        if let isLocal {
            info[UIResponder.keyboardIsLocalUserInfoKey] = isLocal
        }
        return info
    }

    /// 起始 frame 转换到目标 view 坐标系。
    func beginFrame(in view: UIView) -> CGRect? {
        guard let beginFrame else { return nil }
        return view.convert(beginFrame, from: nil)
    }

    /// 结束 frame 转换到目标 view 坐标系。
    func endFrame(in view: UIView) -> CGRect? {
        guard let endFrame else { return nil }
        return view.convert(endFrame, from: nil)
    }

    /// 根据结束 frame 判断键盘在目标 view 内是否可见；缺少 frame 时返回 nil。
    func isVisible(in view: UIView, tolerance: CGFloat = 0.5) -> Bool? {
        guard let frame = endFrame(in: view) else { return nil }
        return frame.minY < view.bounds.maxY - tolerance && frame.height > 0
    }

    private static func readRect(_ value: Any?) -> CGRect? {
        if let rect = value as? CGRect {
            return rect
        }
        if let value = value as? NSValue {
            return value.cgRectValue
        }
        return nil
    }

    private static func readTimeInterval(_ value: Any?) -> TimeInterval? {
        if let value = value as? TimeInterval {
            return value
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        return nil
    }

    private static func readUInt(_ value: Any?) -> UInt? {
        if let value = value as? UInt {
            return value
        }
        if let value = value as? Int {
            return UInt(value)
        }
        if let value = value as? NSNumber {
            return value.uintValue
        }
        return nil
    }

    private static func readBool(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        return nil
    }
}

extension NotificationCenter {
    /// 订阅全部 UIKit 键盘通知，并统一转换成类型化载荷。
    func keyboardNotifications() -> AsyncStream<KeyboardNotificationPayload> {
        AsyncStream { continuation in
            let tasks = KeyboardNotificationKind.allCases.map { kind in
                Task { @MainActor in
                    for await notification in notifications(named: kind.notificationName) {
                        guard !Task.isCancelled else { return }
                        guard let payload = KeyboardNotificationPayload(notification) else {
                            continue
                        }
                        continuation.yield(payload)
                    }
                }
            }

            continuation.onTermination = { _ in
                tasks.forEach { $0.cancel() }
            }
        }
    }
}
