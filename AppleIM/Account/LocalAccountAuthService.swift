//
//  LocalAccountAuthService.swift
//  AppleIM
//
//  基于本地账号文件的模拟登录服务
//

import Foundation

/// 账号认证服务协议
///
/// 定义用户登录的业务接口
protocol AccountAuthService: Sendable {
    /// 登录
    ///
    /// - Parameters:
    ///   - identifier: 账号标识（用户名或手机号）
    ///   - password: 密码
    /// - Returns: 账号会话
    /// - Throws: 认证错误
    nonisolated func login(identifier: String, password: String) async throws -> AccountSession
}

/// 账号认证错误
nonisolated enum AccountAuthError: Error, Equatable, Sendable {
    /// 账号标识为空
    case emptyIdentifier
    /// 密码为空
    case emptyPassword
    /// 账号不存在
    case accountNotFound
    /// 密码错误
    case invalidPassword
}

nonisolated extension AccountAuthError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyIdentifier:
            "Enter an account or phone number."
        case .emptyPassword:
            "Enter a password."
        case .accountNotFound:
            "Account not found."
        case .invalidPassword:
            "Incorrect password."
        }
    }
}

/// 本地账号认证服务实现
///
/// 基于本地 JSON 文件的模拟登录服务，用于开发和测试
nonisolated struct LocalAccountAuthService: AccountAuthService {
    /// 账号目录
    private let catalog: any AccountCatalog

    /// 初始化
    ///
    /// - Parameter catalog: 账号目录，默认为 BundleAccountCatalog
    init(catalog: any AccountCatalog = BundleAccountCatalog()) {
        self.catalog = catalog
    }

    /// 登录
    ///
    /// 流程：
    /// 1. 验证账号标识和密码非空
    /// 2. 从账号目录加载账号列表
    /// 3. 查找匹配的账号（支持用户名或手机号）
    /// 4. 验证密码
    /// 5. 生成会话令牌
    ///
    /// - Parameters:
    ///   - identifier: 账号标识（用户名或手机号，不区分大小写）
    ///   - password: 密码
    /// - Returns: 账号会话（包含用户 ID、显示名、令牌、登录时间）
    /// - Throws: 空标识、空密码、账号不存在或密码错误
    nonisolated func login(identifier: String, password: String) async throws -> AccountSession {
        let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty else {
            throw AccountAuthError.emptyIdentifier
        }

        guard !password.isEmpty else {
            throw AccountAuthError.emptyPassword
        }

        let accounts = try await catalog.accounts()
        guard let account = accounts.first(where: { account in
            account.loginName.caseInsensitiveCompare(normalizedIdentifier) == .orderedSame
                || account.mobile == normalizedIdentifier
        }) else {
            throw AccountAuthError.accountNotFound
        }

        guard account.password == password else {
            throw AccountAuthError.invalidPassword
        }

        return AccountSession(
            userID: account.userID,
            displayName: account.displayName,
            avatarURL: account.avatarURL,
            token: "mock_token_\(account.userID.rawValue)_\(UUID().uuidString)",
            loggedInAt: Int64(Date().timeIntervalSince1970)
        )
    }
}
