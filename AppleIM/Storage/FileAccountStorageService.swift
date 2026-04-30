//
//  FileAccountStorageService.swift
//  AppleIM
//
//  基于文件系统的账号存储服务
//  为每个账号创建独立的目录结构

import Foundation

/// 账号存储服务协议
protocol AccountStorageService: Sendable {
    /// 准备账号存储
    ///
    /// 创建账号目录和数据库文件
    func prepareStorage(for accountID: UserID) async throws -> AccountStoragePaths

    /// 删除账号存储
    func deleteStorage(for accountID: UserID) async throws
}

/// 基于文件系统的账号存储服务
///
/// 使用 actor 隔离确保文件操作的线程安全
/// 每个账号拥有独立的目录：account_<sanitized_id>/
actor FileAccountStorageService: AccountStorageService {
    /// 根目录
    private let rootDirectory: URL

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    /// 准备账号存储
    ///
    /// 创建账号目录结构和数据库文件
    ///
    /// - Parameter accountID: 账号 ID
    /// - Returns: 账号存储路径
    /// - Throws: 目录或文件创建失败时抛出错误
    func prepareStorage(for accountID: UserID) async throws -> AccountStoragePaths {
        let paths = try makePaths(for: accountID)
        let fileManager = FileManager.default

        try fileManager.createDirectory(
            at: paths.rootDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: paths.mediaDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: paths.cacheDirectory,
            withIntermediateDirectories: true
        )

        try createFileIfNeeded(at: paths.mainDatabase)
        try createFileIfNeeded(at: paths.searchDatabase)
        try createFileIfNeeded(at: paths.fileIndexDatabase)
        try applyProtectionAttributes(to: paths)

        return paths
    }

    /// 删除账号存储
    ///
    /// - Parameter accountID: 账号 ID
    /// - Throws: 删除失败时抛出错误
    func deleteStorage(for accountID: UserID) async throws {
        let paths = try makePaths(for: accountID)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: paths.rootDirectory.path) {
            try fileManager.removeItem(at: paths.rootDirectory)
        }
    }

    /// 构建账号存储路径
    ///
    /// - Parameter accountID: 账号 ID
    /// - Returns: 账号存储路径
    /// - Throws: 账号 ID 为空时抛出错误
    private func makePaths(for accountID: UserID) throws -> AccountStoragePaths {
        let rawID = accountID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawID.isEmpty else {
            throw AccountStorageError.emptyAccountID
        }

        let accountRoot = rootDirectory.appendingPathComponent(
            "account_\(Self.sanitizedDirectoryComponent(rawID))",
            isDirectory: true
        )

        return AccountStoragePaths(
            accountID: accountID,
            rootDirectory: accountRoot,
            mainDatabase: accountRoot.appendingPathComponent("main.db"),
            searchDatabase: accountRoot.appendingPathComponent("search.db"),
            fileIndexDatabase: accountRoot.appendingPathComponent("file_index.db"),
            mediaDirectory: accountRoot.appendingPathComponent("media", isDirectory: true),
            cacheDirectory: accountRoot.appendingPathComponent("cache", isDirectory: true)
        )
    }

    /// 如果文件不存在则创建空文件
    ///
    /// - Parameter url: 文件 URL
    /// - Throws: 文件创建失败时抛出错误
    private func createFileIfNeeded(at url: URL) throws {
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: url.path) {
            _ = fileManager.createFile(atPath: url.path, contents: Data())
        }
    }

    /// 为账号目录、数据库和媒体目录应用 iOS 文件保护
    private func applyProtectionAttributes(to paths: AccountStoragePaths) throws {
        #if os(iOS)
        let protectedURLs = [
            paths.rootDirectory,
            paths.mainDatabase,
            paths.searchDatabase,
            paths.fileIndexDatabase,
            paths.mediaDirectory
        ]
        let fileManager = FileManager.default

        for url in protectedURLs {
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        }

        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.none],
            ofItemAtPath: paths.cacheDirectory.path
        )
        #endif
    }

    /// 清理目录名中的非法字符
    ///
    /// 只保留字母、数字、连字符和下划线，其他字符替换为下划线
    ///
    /// - Parameter rawValue: 原始字符串
    /// - Returns: 清理后的字符串
    nonisolated private static func sanitizedDirectoryComponent(_ rawValue: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return rawValue.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "_" }
            .reduce(into: "") { result, character in
                result.append(character)
            }
    }
}
