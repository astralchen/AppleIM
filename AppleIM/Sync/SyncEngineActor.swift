//
//  SyncEngineActor.swift
//  AppleIM
//

import Foundation

protocol SyncDeltaService: Sendable {
    func fetchDelta(after checkpoint: SyncCheckpoint?) async throws -> SyncBatch
}

actor SyncEngineActor {
    static let messageBizKey = "message"

    private let userID: UserID
    private let bizKey: String
    private let store: any SyncStore
    private let deltaService: any SyncDeltaService

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

    func syncOnce() async throws -> SyncResult {
        let (result, _) = try await syncNextBatch()
        return result
    }

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

nonisolated struct StaticSyncDeltaService: SyncDeltaService {
    let batch: SyncBatch

    func fetchDelta(after checkpoint: SyncCheckpoint?) async throws -> SyncBatch {
        batch
    }
}
