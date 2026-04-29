//
//  SyncEngineActor.swift
//  AppleIM
//
//  同步引擎 Actor
//  负责管理增量同步流程，防止并发拉取造成乱序写入
//  使用 actor 隔离确保同步操作串行化执行

import Foundation

/// 同步增量数据服务协议
///
/// 由网络层实现，负责从服务端拉取增量数据
protocol SyncDeltaService: Sendable {
    /// 拉取增量数据
    ///
    /// - Parameter checkpoint: 上次同步的检查点，nil 表示首次同步
    /// - Returns: 同步批次数据
    /// - Throws: 网络请求失败时抛出错误
    func fetchDelta(after checkpoint: SyncCheckpoint?) async throws -> SyncBatch
}

/// 同步引擎 Actor
///
/// ## 核心职责
///
/// 1. 管理同步检查点（cursor、seq）
/// 2. 串行化同步操作，防止并发拉取
/// 3. 处理增量数据批次
/// 4. 支持单次同步和持续同步直到追上
///
/// ## 重要说明
///
/// - 使用 actor 隔离，所有同步操作串行执行
/// - 支持消息去重（基于 client_msg_id、server_msg_id、seq）
/// - 支持断点续传（基于 checkpoint）
/// - 支持多页同步（syncUntilCaughtUp）
///
/// ## 使用场景
///
/// - App 启动时同步离线消息
/// - 网络恢复后补拉消息
/// - 定时增量同步
actor SyncEngineActor {
    /// 消息同步业务 key
    static let messageBizKey = "message"

    /// 当前用户 ID
    private let userID: UserID
    /// 业务 key（用于区分不同类型的同步）
    private let bizKey: String
    /// 同步存储（负责读写检查点和应用数据）
    private let store: any SyncStore
    /// 增量数据服务（负责从服务端拉取数据）
    private let deltaService: any SyncDeltaService

    /// 初始化同步引擎
    ///
    /// - Parameters:
    ///   - userID: 当前用户 ID
    ///   - bizKey: 业务 key，默认为消息同步
    ///   - store: 同步存储
    ///   - deltaService: 增量数据服务
    init(
        userID: UserID,
        bizKey: String = SyncEngineActor.messageBizKey,
        store: any SyncStore,
        deltaService: any SyncDeltaService
    ) {
        self.userID = userID
        self.bizKey = bizKey
        self.store = store
        self.deltaService = deltaService
    }

    /// 同步一次
    ///
    /// 拉取一个批次的增量数据并应用到本地
    ///
    /// - Returns: 同步结果
    /// - Throws: 同步失败时抛出错误
    func syncOnce() async throws -> SyncResult {
        let (result, _) = try await syncNextBatch()
        return result
    }

    /// 持续同步直到追上服务端
    ///
    /// 循环拉取增量数据，直到服务端返回 `hasMore = false`
    /// 用于处理大量离线消息的场景
    ///
    /// ## 防护机制
    ///
    /// - 限制最大批次数，防止无限循环
    /// - 每批次独立处理，失败时可以从上次检查点恢复
    ///
    /// - Parameter maxBatches: 最大批次数，默认 20
    /// - Returns: 同步运行结果（包含总批次数、总消息数等）
    /// - Throws: 同步失败或超过最大批次数时抛出错误
    func syncUntilCaughtUp(maxBatches: Int = 20) async throws -> SyncRunResult {
        guard maxBatches > 0 else {
            throw SyncEngineError.invalidMaxBatches
        }

        var batchCount = 0
        var fetchedCount = 0
        var insertedCount = 0
        var skippedDuplicateCount = 0
        var initialCheckpoint: SyncCheckpoint?
        var finalCheckpoint: SyncCheckpoint?

        while true {
            let (result, batch) = try await syncNextBatch()

            if batchCount == 0 {
                initialCheckpoint = result.previousCheckpoint
            }

            batchCount += 1
            fetchedCount += result.fetchedCount
            insertedCount += result.insertedCount
            skippedDuplicateCount += result.skippedDuplicateCount
            finalCheckpoint = result.checkpoint

            guard batch.hasMore else {
                guard let finalCheckpoint else {
                    throw SyncEngineError.invalidMaxBatches
                }

                return SyncRunResult(
                    batchCount: batchCount,
                    fetchedCount: fetchedCount,
                    insertedCount: insertedCount,
                    skippedDuplicateCount: skippedDuplicateCount,
                    initialCheckpoint: initialCheckpoint,
                    finalCheckpoint: finalCheckpoint
                )
            }

            guard batchCount < maxBatches else {
                throw SyncEngineError.exceededMaxBatches(maxBatches)
            }
        }
    }

    /// 同步下一个批次
    ///
    /// 内部方法，执行单次同步流程：
    /// 1. 读取上次检查点
    /// 2. 拉取增量数据
    /// 3. 应用到本地（去重、入库、更新检查点）
    ///
    /// - Returns: 元组（同步结果，批次数据）
    /// - Throws: 同步失败时抛出错误
    private func syncNextBatch() async throws -> (SyncResult, SyncBatch) {
        let checkpoint = try await store.syncCheckpoint(for: bizKey)
        let batch = try await deltaService.fetchDelta(after: checkpoint)
        let applyResult = try await store.applyIncomingSyncBatch(batch, userID: userID)

        return (
            SyncResult(
                previousCheckpoint: checkpoint,
                fetchedCount: applyResult.fetchedCount,
                insertedCount: applyResult.insertedCount,
                skippedDuplicateCount: applyResult.skippedDuplicateCount,
                checkpoint: applyResult.checkpoint
            ),
            batch
        )
    }
}

/// 静态同步增量数据服务
///
/// 用于测试，返回固定的批次数据
nonisolated struct StaticSyncDeltaService: SyncDeltaService {
    /// 固定的批次数据
    let batch: SyncBatch

    func fetchDelta(after checkpoint: SyncCheckpoint?) async throws -> SyncBatch {
        batch
    }
}
