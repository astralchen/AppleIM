//
//  FileAccountStorageService.swift
//  AppleIM
//

import Foundation

protocol AccountStorageService: Sendable {
    func prepareStorage(for accountID: UserID) async throws -> AccountStoragePaths
    func deleteStorage(for accountID: UserID) async throws
}

actor FileAccountStorageService: AccountStorageService {
    private let rootDirectory: URL

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

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

        return paths
    }

    func deleteStorage(for accountID: UserID) async throws {
        let paths = try makePaths(for: accountID)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: paths.rootDirectory.path) {
            try fileManager.removeItem(at: paths.rootDirectory)
        }
    }

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

    private func createFileIfNeeded(at url: URL) throws {
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: url.path) {
            _ = fileManager.createFile(atPath: url.path, contents: Data())
        }
    }

    nonisolated private static func sanitizedDirectoryComponent(_ rawValue: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return rawValue.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "_" }
            .reduce(into: "") { result, character in
                result.append(character)
            }
    }
}
