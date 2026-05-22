//
//  GRDBJobAndSyncRecords.swift
//  AppleIM
//
//  GRDB 内部表映射。
//

import Foundation
import GRDB

/// pending_job 表的 GRDB 读取模型。
nonisolated struct PendingJobDatabaseRecord: FetchableRecord, TableRecord, Sendable {
    static let databaseTableName = "pending_job"

    enum Columns {
        static let jobID = Column("job_id")
        static let userID = Column("user_id")
        static let jobType = Column("job_type")
        static let bizKey = Column("biz_key")
        static let payloadJSON = Column("payload_json")
        static let status = Column("status")
        static let retryCount = Column("retry_count")
        static let maxRetryCount = Column("max_retry_count")
        static let nextRetryAt = Column("next_retry_at")
        static let updatedAt = Column("updated_at")
        static let createdAt = Column("created_at")
    }

    let job: PendingJob

    init(row: Row) throws {
        let typeRawValue: Int = row[Columns.jobType]
        let statusRawValue: Int = row[Columns.status]

        guard let type = PendingJobType(rawValue: typeRawValue) else {
            throw ChatStoreError.invalidPendingJobType(typeRawValue)
        }

        guard let status = PendingJobStatus(rawValue: statusRawValue) else {
            throw ChatStoreError.invalidPendingJobStatus(statusRawValue)
        }

        job = PendingJob(
            id: row[Columns.jobID],
            userID: UserID(rawValue: row[Columns.userID]),
            type: type,
            bizKey: row[Columns.bizKey],
            payloadJSON: row[Columns.payloadJSON],
            status: status,
            retryCount: row[Columns.retryCount],
            maxRetryCount: row[Columns.maxRetryCount],
            nextRetryAt: row[Columns.nextRetryAt],
            updatedAt: row[Columns.updatedAt],
            createdAt: row[Columns.createdAt]
        )
    }
}


/// sync_checkpoint 表的 GRDB 读取模型。
nonisolated struct SyncCheckpointDatabaseRecord: FetchableRecord, TableRecord, Sendable {
    static let databaseTableName = "sync_checkpoint"

    enum Columns {
        static let bizKey = Column("biz_key")
        static let cursor = Column("cursor")
        static let sequence = Column("seq")
        static let updatedAt = Column("updated_at")
    }

    let checkpoint: SyncCheckpoint

    init(row: Row) throws {
        checkpoint = SyncCheckpoint(
            bizKey: row[Columns.bizKey],
            cursor: row[Columns.cursor],
            sequence: row[Columns.sequence],
            updatedAt: row[Columns.updatedAt] ?? 0
        )
    }
}


extension PendingJobDatabaseRecord: PersistableRecord {
    init(job: PendingJob) {
        self.job = job
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.jobID] = job.id
        container[Columns.userID] = job.userID.rawValue
        container[Columns.jobType] = job.type.rawValue
        container[Columns.bizKey] = job.bizKey
        container[Columns.payloadJSON] = job.payloadJSON
        container[Columns.status] = job.status.rawValue
        container[Columns.retryCount] = job.retryCount
        container[Columns.maxRetryCount] = job.maxRetryCount
        container[Columns.nextRetryAt] = job.nextRetryAt
        container[Columns.updatedAt] = job.updatedAt
        container[Columns.createdAt] = job.createdAt
    }

    @discardableResult
    static func upsertRepairJob(_ job: PendingJob, in db: Database) throws -> PendingJob {
        let databaseRecord = try PendingJobDatabaseRecord(job: job)
            .upsertAndFetch(db, updating: .noColumnUnlessSpecified) { excluded in
                [
                    Columns.payloadJSON.set(to: excluded[Columns.payloadJSON]),
                    Columns.status.set(to: excluded[Columns.status]),
                    Columns.updatedAt.set(to: excluded[Columns.updatedAt])
                ]
            }
        return databaseRecord.job
    }

    @discardableResult
    static func upsertNonTerminalJob(_ job: PendingJob, in db: Database) throws -> PendingJob {
        if let existing = try PendingJobDatabaseRecord
            .filter(PendingJobDatabaseRecord.Columns.jobID == job.id)
            .fetchOne(db)?
            .job,
           existing.status == .success || existing.status == .cancelled {
            return existing
        }

        let databaseRecord = try PendingJobDatabaseRecord(job: job)
            .upsertAndFetch(db, updating: .noColumnUnlessSpecified) { excluded in
                [
                    Columns.userID.set(to: excluded[Columns.userID]),
                    Columns.jobType.set(to: excluded[Columns.jobType]),
                    Columns.bizKey.set(to: excluded[Columns.bizKey]),
                    Columns.payloadJSON.set(to: excluded[Columns.payloadJSON]),
                    Columns.status.set(to: excluded[Columns.status]),
                    Columns.retryCount.set(to: excluded[Columns.retryCount]),
                    Columns.maxRetryCount.set(to: excluded[Columns.maxRetryCount]),
                    Columns.nextRetryAt.set(to: excluded[Columns.nextRetryAt]),
                    Columns.updatedAt.set(to: excluded[Columns.updatedAt])
                ]
            }
        return databaseRecord.job
    }
}


extension SyncCheckpointDatabaseRecord: PersistableRecord {
    init(checkpoint: SyncCheckpoint) {
        self.checkpoint = checkpoint
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.bizKey] = checkpoint.bizKey
        container[Columns.cursor] = checkpoint.cursor
        container[Columns.sequence] = checkpoint.sequence
        container[Columns.updatedAt] = checkpoint.updatedAt
    }

    static func upsertRecord(_ checkpoint: SyncCheckpoint, in db: Database) throws {
        try SyncCheckpointDatabaseRecord(checkpoint: checkpoint).upsert(db)
    }
}

// MARK: - 复杂查询行模型

