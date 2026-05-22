//
//  SendableSafetyNotes.swift
//  AppleIM
//
//  并发安全审计说明
//

import Foundation

/// 记录 Foundation、UIKit 或 Objective-C 回调 token 未标注 Sendable 时的本地约束。
///
/// 新增 `@unchecked Sendable` 前必须满足：
/// 1. 类型不暴露可变业务状态，或可变状态由 actor / lock / 系统线程安全对象保护。
/// 2. 跨并发边界只执行取消、读取不可变配置或系统线程安全 API。
/// 3. 代码附近写明具体依据，不能只写“为了通过 Swift 6”。
///
/// 当前生产允许列表：
/// - `UserDefaultsAccountSessionStore`：系统 `UserDefaults` 桥接。
/// - `URLSessionHTTPClient`：系统 `URLSession` 桥接。
/// - `UserNotificationCenterNotificationManager`：系统通知中心和 Objective-C delegate。
/// - `DatabaseObservationCancellableBox`：Combine `AnyCancellable` 取消 token。
/// - `NotificationObservationToken`：`NotificationCenter` Objective-C 观察 token。
nonisolated enum SendableSafetyNotes {
    static let requiresLocalJustification = true
}
