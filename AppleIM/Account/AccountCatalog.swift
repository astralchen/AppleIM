//
//  AccountCatalog.swift
//  AppleIM
//
//  本地模拟账号文件读取
//

import Foundation

protocol AccountCatalog: Sendable {
    nonisolated func accounts() async throws -> [MockAccount]
}

nonisolated enum AccountCatalogError: Error, Equatable, Sendable {
    case resourceMissing
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

nonisolated struct BundleAccountCatalog: AccountCatalog {
    private let resourceURL: URL?

    init(bundle: Bundle = .main, resourceName: String = "mock_accounts") {
        self.resourceURL = bundle.url(forResource: resourceName, withExtension: "json")
    }

    init(resourceURL: URL?) {
        self.resourceURL = resourceURL
    }

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
