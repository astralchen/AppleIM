//
//  AccountSessionStore.swift
//  AppleIM
//
//  登录态缓存
//

import Foundation

protocol AccountSessionStore: Sendable {
    nonisolated func loadSession() -> AccountSession?
    nonisolated func saveSession(_ session: AccountSession) throws
    nonisolated func clearSession()
}

nonisolated enum AccountSessionStoreError: Error, Equatable, Sendable {
    case encodeFailed
}

/// UserDefaults is documented as thread-safe for simple value access.
nonisolated struct UserDefaultsAccountSessionStore: AccountSessionStore, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "chatbridge.account.session"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    nonisolated func loadSession() -> AccountSession? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(AccountSession.self, from: data)
    }

    nonisolated func saveSession(_ session: AccountSession) throws {
        do {
            let data = try JSONEncoder().encode(session)
            userDefaults.set(data, forKey: key)
        } catch {
            throw AccountSessionStoreError.encodeFailed
        }
    }

    nonisolated func clearSession() {
        userDefaults.removeObject(forKey: key)
    }
}
