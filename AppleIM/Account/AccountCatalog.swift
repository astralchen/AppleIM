//
//  AccountCatalog.swift
//  AppleIM
//
//  本地模拟账号文件读取
//

import Foundation

/// 账号目录协议
///
/// 定义获取可用账号列表的接口
protocol AccountCatalog: Sendable {
    /// 获取账号列表
    ///
    /// - Returns: 模拟账号列表
    /// - Throws: 账号目录错误
    nonisolated func accounts() async throws -> [MockAccount]
}

/// 账号目录错误
nonisolated enum AccountCatalogError: Error, Equatable, Sendable {
    /// 账号文件缺失
    case resourceMissing
    /// 账号文件为空
    case empty
}

nonisolated extension AccountCatalogError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .resourceMissing:
            "Account file is missing."
        case .empty:
            "Account file has no accounts."
        }
    }
}

/// Bundle 账号目录实现
///
/// 从 App Bundle 中读取 mock_accounts.json 文件
nonisolated struct BundleAccountCatalog: AccountCatalog {
    /// 账号文件 URL
    private let resourceURL: URL?

    /// 初始化
    ///
    /// - Parameters:
    ///   - bundle: Bundle 实例，默认为 main bundle
    ///   - resourceName: 资源文件名，默认为 "mock_accounts"
    init(bundle: Bundle = .main, resourceName: String = "mock_accounts") {
        self.resourceURL = bundle.url(forResource: resourceName, withExtension: "json")
    }

    /// 初始化
    ///
    /// - Parameter resourceURL: 资源文件 URL
    init(resourceURL: URL?) {
        self.resourceURL = resourceURL
    }

    /// 获取账号列表
    ///
    /// 流程：
    /// 1. 检查资源文件是否存在
    /// 2. 读取 JSON 数据
    /// 3. 解码为账号列表
    /// 4. 验证列表非空
    ///
    /// - Returns: 模拟账号列表
    /// - Throws: 文件缺失、解码失败或列表为空错误
    nonisolated func accounts() async throws -> [MockAccount] {
        guard let resourceURL else {
            throw AccountCatalogError.resourceMissing
        }

        let data = try Data(contentsOf: resourceURL)
        let accounts = try JSONDecoder().decode([MockAccount].self, from: data)
        guard !accounts.isEmpty else {
            throw AccountCatalogError.empty
        }

        return accounts
    }
}
