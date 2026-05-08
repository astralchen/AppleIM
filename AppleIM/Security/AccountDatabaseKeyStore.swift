//
//  AccountDatabaseKeyStore.swift
//  AppleIM
//
//  账号数据库密钥存取
//

import Foundation
import Security

/// 账号数据库密钥存储协议
///
/// 密钥与账号绑定，调用方只负责获取密钥能力，不直接关心 Keychain 细节。
protocol AccountDatabaseKeyStore: Sendable {
    /// 获取或创建指定账号的数据库加密密钥
    func databaseKey(for accountID: UserID) async throws -> Data
    /// 删除指定账号的数据库加密密钥
    func deleteDatabaseKey(for accountID: UserID) async throws
}

/// 账号数据库密钥错误
nonisolated enum AccountDatabaseKeyStoreError: Error, Equatable, Sendable {
    /// 随机密钥生成失败
    case generationFailed
    /// Keychain 读取失败
    case keychainReadFailed(status: OSStatus)
    /// Keychain 写入失败
    case keychainWriteFailed(status: OSStatus)
    /// Keychain 删除失败
    case keychainDeleteFailed(status: OSStatus)
}

/// Keychain 账号数据库密钥存储
nonisolated struct KeychainAccountDatabaseKeyStore: AccountDatabaseKeyStore {
    /// Keychain service 名称
    private let service: String

    /// 初始化 Keychain 密钥存储
    init(service: String = "com.sondra.AppleIM.database-key") {
        self.service = service
    }

    /// 获取账号数据库密钥，不存在时生成并保存
    func databaseKey(for accountID: UserID) async throws -> Data {
        if let storedKey = try readKey(for: accountID) {
            return storedKey
        }

        let key = try Self.generateKey()
        do {
            try saveKey(key, for: accountID)
        } catch AccountDatabaseKeyStoreError.keychainWriteFailed(let status) where status == errSecDuplicateItem {
            if let storedKey = try readKey(for: accountID) {
                return storedKey
            }

            throw AccountDatabaseKeyStoreError.keychainWriteFailed(status: errSecDuplicateItem)
        }
        return key
    }

    /// 从 Keychain 删除账号数据库密钥
    func deleteDatabaseKey(for accountID: UserID) async throws {
        let status = SecItemDelete(baseQuery(for: accountID) as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AccountDatabaseKeyStoreError.keychainDeleteFailed(status: status)
        }
    }

    /// 从 Keychain 读取账号数据库密钥
    private func readKey(for accountID: UserID) throws -> Data? {
        var query = baseQuery(for: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw AccountDatabaseKeyStoreError.keychainReadFailed(status: status)
        }
    }

    /// 将账号数据库密钥保存到 Keychain
    private func saveKey(_ key: Data, for accountID: UserID) throws {
        var query = baseQuery(for: accountID)
        query[kSecValueData as String] = key
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw AccountDatabaseKeyStoreError.keychainWriteFailed(status: status)
        }
    }

    /// 构造 Keychain 基础查询
    private func baseQuery(for accountID: UserID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.rawValue
        ]
    }

    /// 生成 256-bit 随机数据库密钥
    nonisolated static func generateKey() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let byteCount = bytes.count
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, byteCount, buffer.baseAddress!)
        }

        guard status == errSecSuccess else {
            throw AccountDatabaseKeyStoreError.generationFailed
        }

        return Data(bytes)
    }
}

/// 测试用内存密钥存储
actor InMemoryAccountDatabaseKeyStore: AccountDatabaseKeyStore {
    /// 内存中的账号密钥表
    private var keys: [UserID: Data] = [:]

    /// 获取或创建内存中的账号数据库密钥
    func databaseKey(for accountID: UserID) async throws -> Data {
        if let key = keys[accountID] {
            return key
        }

        let key = try KeychainAccountDatabaseKeyStore.generateKey()
        keys[accountID] = key
        return key
    }

    /// 删除内存中的账号数据库密钥
    func deleteDatabaseKey(for accountID: UserID) async throws {
        keys[accountID] = nil
    }
}
