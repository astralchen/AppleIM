//
//  DatabaseActor.swift
//  AppleIM
//

import Foundation

nonisolated struct MigrationMetadata: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let lastMigrationID: String
    let lastVacuumAt: Int?
    let lastIntegrityCheckAt: Int?
    let ftsRebuildVersion: Int
    let appliedScriptIDs: [String]
}

nonisolated struct DatabaseBootstrapResult: Equatable, Sendable {
    let paths: AccountStoragePaths
    let metadata: MigrationMetadata
}

actor DatabaseActor {
    func bootstrap(paths: AccountStoragePaths) async throws -> DatabaseBootstrapResult {
        let metadata = MigrationMetadata(
            schemaVersion: DatabaseSchema.currentVersion,
            lastMigrationID: DatabaseSchema.initialScripts.last?.id ?? "",
            lastVacuumAt: nil,
            lastIntegrityCheckAt: nil,
            ftsRebuildVersion: 0,
            appliedScriptIDs: DatabaseSchema.initialScripts.map(\.id)
        )

        try persist(metadata: metadata, in: paths)

        return DatabaseBootstrapResult(paths: paths, metadata: metadata)
    }

    func loadMigrationMetadata(paths: AccountStoragePaths) async throws -> MigrationMetadata {
        let data = try Data(contentsOf: metadataURL(in: paths))
        return try JSONDecoder().decode(MigrationMetadata.self, from: data)
    }

    private func persist(metadata: MigrationMetadata, in paths: AccountStoragePaths) throws {
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: metadataURL(in: paths), options: [.atomic])
    }

    private func metadataURL(in paths: AccountStoragePaths) -> URL {
        paths.cacheDirectory.appendingPathComponent("migration_meta.json")
    }
}
