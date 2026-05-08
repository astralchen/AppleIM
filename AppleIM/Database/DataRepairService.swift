//
//  DataRepairService.swift
//  AppleIM
//
//  后台数据修复协调器。

import Foundation

/// 串联数据库完整性检查、FTS 重建和媒体索引重建。
nonisolated struct DataRepairService: Sendable {
    /// 当前用户 ID
    private let userID: UserID
    /// 数据库操作 Actor
    private let database: DatabaseActor
    /// 当前账号存储路径
    private let paths: AccountStoragePaths
    /// 本地聊天仓储
    private let repository: LocalChatRepository
    /// 搜索索引 Actor
    private let searchIndex: SearchIndexActor

    /// 初始化数据修复服务
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

    /// 运行完整的数据修复流程
    ///
    /// 顺序执行数据库完整性检查、FTS 全量重建和媒体索引重建，并聚合每一步的结果。
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

    /// 启动时按维护元数据判断是否需要运行修复
    func runStartupIfNeeded() async -> DataRepairReport? {
        if let metadata = try? await database.loadMigrationMetadata(paths: paths),
           metadata.lastIntegrityCheckAt != nil,
           metadata.ftsRebuildVersion > 0 {
            return nil
        }

        return await run()
    }

    /// 创建成功步骤报告
    private static func success(_ step: DataRepairStep) -> DataRepairStepReport {
        DataRepairStepReport(step: step, isSuccessful: true, errorDescription: nil)
    }

    /// 根据错误创建失败步骤报告
    private static func failure(_ step: DataRepairStep, error: Error) -> DataRepairStepReport {
        failure(step, description: safeErrorDescription(error))
    }

    /// 根据安全错误描述创建失败步骤报告
    private static func failure(_ step: DataRepairStep, description: String) -> DataRepairStepReport {
        DataRepairStepReport(step: step, isSuccessful: false, errorDescription: description)
    }

    /// 生成不泄露路径、SQL 或参数的错误描述
    private static func safeErrorDescription(_ error: Error) -> String {
        if let databaseError = error as? DatabaseActorError {
            return databaseError.safeDescription
        }

        return String(describing: type(of: error))
    }

    /// 当前秒级时间戳
    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }
}
