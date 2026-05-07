//
//  LocalAccountAuthService.swift
//  AppleIM
//
//  基于本地账号文件的模拟登录服务
//

import Foundation

protocol AccountAuthService: Sendable {
    nonisolated func login(identifier: String, password: String) async throws -> AccountSession
}

nonisolated enum AccountAuthError: Error, Equatable, Sendable {
    case emptyIdentifier
    case emptyPassword
    case accountNotFound
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

nonisolated struct LocalAccountAuthService: AccountAuthService {
    private let catalog: any AccountCatalog

    init(catalog: any AccountCatalog = BundleAccountCatalog()) {
        self.catalog = catalog
    }

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
