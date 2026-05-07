//
//  DataRepairService.swift
//  AppleIM
//
//  后台数据修复协调器。

import Foundation

/// 串联数据库完整性检查、FTS 重建和媒体索引重建。
nonisolated struct DataRepairService: Sendable {
    private let userID: UserID
    private let database: DatabaseActor
    private let paths: AccountStoragePaths
    private let repository: LocalChatRepository
    private let searchIndex: SearchIndexActor

    init(
        userID: UserID,
        database: DatabaseActor,
        paths: AccountStoragePaths,
        repository: LocalChatRepository,
        searchIndex: SearchIndexActor
    ) {
        self.userID = userID
        self.database = database
        self.paths = paths
        self.repository = repository
        self.searchIndex = searchIndex
    }

    func run() async -> DataRepairReport {
        var integrityResults: [DatabaseIntegrityCheckResult] = []
        var mediaIndexRebuildResult: MediaIndexRebuildResult?
        var steps: [DataRepairStepReport] = []

        do {
            let results = try await database.integrityCheck(paths: paths)
            integrityResults = results

            if results.allSatisfy(\.isOK) {
                _ = try await database.recordMaintenanceMetadata(
                    paths: paths,
                    integrityCheckedAt: Self.currentTimestamp(),
                    ftsRebuildVersion: nil
                )
                steps.append(Self.success(.integrityCheck))
            } else {
                steps.append(
                    Self.failure(
                        .integrityCheck,
                        description: "Database integrity check reported a non-ok result."
                    )
                )
            }
        } catch {
            steps.append(Self.failure(.integrityCheck, error: error))
        }

        do {
            try await searchIndex.rebuildAll(userID: userID)
            let previousMetadata = try? await database.loadMigrationMetadata(paths: paths)
            _ = try await database.recordMaintenanceMetadata(
                paths: paths,
                integrityCheckedAt: nil,
                ftsRebuildVersion: (previousMetadata?.ftsRebuildVersion ?? 0) + 1
            )
            steps.append(Self.success(.ftsRebuild))
        } catch {
            steps.append(Self.failure(.ftsRebuild, error: error))
        }

        do {
            let result = try await repository.rebuildMediaIndex(userID: userID)
            mediaIndexRebuildResult = result
            steps.append(Self.success(.mediaIndexRebuild))
        } catch {
            steps.append(Self.failure(.mediaIndexRebuild, error: error))
        }

        return DataRepairReport(
            userID: userID,
            integrityResults: integrityResults,
            mediaIndexRebuildResult: mediaIndexRebuildResult,
            steps: steps
        )
    }

    func runStartupIfNeeded() async -> DataRepairReport? {
        if let metadata = try? await database.loadMigrationMetadata(paths: paths),
           metadata.lastIntegrityCheckAt != nil,
           metadata.ftsRebuildVersion > 0 {
            return nil
        }

        return await run()
    }

    private static func success(_ step: DataRepairStep) -> DataRepairStepReport {
        DataRepairStepReport(step: step, isSuccessful: true, errorDescription: nil)
    }

    private static func failure(_ step: DataRepairStep, error: Error) -> DataRepairStepReport {
        failure(step, description: safeErrorDescription(error))
    }

    private static func failure(_ step: DataRepairStep, description: String) -> DataRepairStepReport {
        DataRepairStepReport(step: step, isSuccessful: false, errorDescription: description)
    }

    private static func safeErrorDescription(_ error: Error) -> String {
        if let databaseError = error as? DatabaseActorError {
            return databaseError.safeDescription
        }

        return String(describing: type(of: error))
    }

    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }
}
