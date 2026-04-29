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
        let checkpoint = try await store.syncCheckpoint(for: bizKey)
        let batch = try await deltaService.fetchDelta(after: checkpoint)
        let applyResult = try await store.applyIncomingSyncBatch(batch, userID: userID)

        return SyncResult(
            previousCheckpoint: checkpoint,
            fetchedCount: applyResult.fetchedCount,
            insertedCount: applyResult.insertedCount,
            skippedDuplicateCount: applyResult.skippedDuplicateCount,
            checkpoint: applyResult.checkpoint
        )
    }
}

nonisolated struct StaticSyncDeltaService: SyncDeltaService {
    let batch: SyncBatch

    func fetchDelta(after checkpoint: SyncCheckpoint?) async throws -> SyncBatch {
        batch
    }
}

