//
//  AccountSessionStore.swift
//  AppleIM
//
//  登录态缓存
//

import Foundation

/// 账号会话存储协议
///
/// 定义登录态的持久化接口
protocol AccountSessionStore: Sendable {
    /// 加载会话
    ///
    /// - Returns: 账号会话，如果不存在返回 nil
    nonisolated func loadSession() -> AccountSession?

    /// 保存会话
    ///
    /// - Parameter session: 要保存的账号会话
    /// - Throws: 编码失败错误
    nonisolated func saveSession(_ session: AccountSession) throws

    /// 清除会话
    ///
    /// 删除已保存的登录态
    nonisolated func clearSession()
}

/// 账号会话存储错误
nonisolated enum AccountSessionStoreError: Error, Equatable, Sendable {
    /// 编码失败
    case encodeFailed
}

/// UserDefaults 账号会话存储实现
///
/// 使用 UserDefaults 持久化登录态
///
/// ## Sendable 审计
///
/// 保留 `@unchecked Sendable` 的原因：
/// - `UserDefaults` 未声明 Sendable。
/// - 本类型只保存不可变 `UserDefaults` 引用和不可变 key，不保存可变业务状态。
/// - 暴露方法只通过单个 key 读写 `Data` 值，编码器/解码器在方法内部创建。
/// - 登录态对象以值类型 `AccountSession` 跨边界传递，不共享可变引用。
nonisolated struct UserDefaultsAccountSessionStore: AccountSessionStore, @unchecked Sendable {
    /// UserDefaults 实例
    private let userDefaults: UserDefaults
    /// 存储键
    private let key: String

    /// 初始化
    ///
    /// - Parameters:
    ///   - userDefaults: UserDefaults 实例，默认为 standard
    ///   - key: 存储键，默认为 "chatbridge.account.session"
    init(
        userDefaults: UserDefaults = .standard,
        key: String = "chatbridge.account.session"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    /// 加载会话
    ///
    /// 从 UserDefaults 读取并解码会话数据
    ///
    /// - Returns: 账号会话，如果不存在或解码失败返回 nil
    nonisolated func loadSession() -> AccountSession? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(AccountSession.self, from: data)
    }

    /// 保存会话
    ///
    /// 编码会话数据并写入 UserDefaults
    ///
    /// - Parameter session: 要保存的账号会话
    /// - Throws: 编码失败错误
    nonisolated func saveSession(_ session: AccountSession) throws {
        do {
            let data = try JSONEncoder().encode(session)
            userDefaults.set(data, forKey: key)
        } catch {
            throw AccountSessionStoreError.encodeFailed
        }
    }

    /// 清除会话
    ///
    /// 从 UserDefaults 删除会话数据
    nonisolated func clearSession() {
        userDefaults.removeObject(forKey: key)
    }
}
