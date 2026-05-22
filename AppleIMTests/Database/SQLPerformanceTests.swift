import Testing
import Foundation
import GRDB

@testable import AppleIM

extension AppleIMTests {
    @Test func sqlHotPathIndexesAreAvailableAfterBootstrap() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (_, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "sql_index_user")
        let indexNames = try await databaseContext.databaseActor.read(paths: databaseContext.paths) { db in
            let rows = try Row.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index' ORDER BY name;")
            return Set(rows.compactMap { $0["name"] as String? })
        }

        #expect(indexNames.contains("idx_pending_job_user_recoverable"))
        #expect(indexNames.contains("idx_media_resource_user_updated"))
        #expect(indexNames.contains("idx_media_resource_owner_message"))
        #expect(indexNames.contains("idx_message_conversation_seq"))
        #expect(indexNames.contains("idx_message_conversation_read_state"))
        #expect(indexNames.contains("idx_message_conversation_send_recovery"))
    }

    @Test func sqlHotPathQueriesUseDedicatedIndexes() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (_, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "sql_plan_user")
        try await seedSQLPerformanceDataset(databaseContext: databaseContext, userID: "sql_plan_user")

        let pendingJobPlan = try await queryPlan(
            """
            EXPLAIN QUERY PLAN
            SELECT job_id, user_id, job_type, biz_key, payload_json, status, retry_count, max_retry_count, next_retry_at, updated_at, created_at
            FROM pending_job
            WHERE user_id = ?
            AND status IN (?, ?)
            AND retry_count < max_retry_count
            AND (next_retry_at IS NULL OR next_retry_at <= ?)
            ORDER BY COALESCE(next_retry_at, created_at), created_at;
            """,
            arguments: [
                "sql_plan_user",
                PendingJobStatus.pending.rawValue,
                PendingJobStatus.running.rawValue,
                500
            ],
            databaseContext: databaseContext
        )
        expectPlan(pendingJobPlan, contains: "idx_pending_job_user_recoverable")

        let missingMediaPlan = try await queryPlan(
            """
            EXPLAIN QUERY PLAN
            SELECT media_id, user_id, owner_message_id, local_path, remote_url
            FROM media_resource
            WHERE user_id = ?
            AND local_path IS NOT NULL
            AND TRIM(local_path) <> ''
            AND remote_url IS NOT NULL
            AND TRIM(remote_url) <> ''
            ORDER BY updated_at DESC, created_at DESC;
            """,
            arguments: ["sql_plan_user"],
            databaseContext: databaseContext
        )
        expectPlan(missingMediaPlan, contains: "idx_media_resource_user_updated")

        let ownerMessagePlan = try await queryPlan(
            """
            EXPLAIN QUERY PLAN
            UPDATE media_resource
            SET upload_status = ?, updated_at = ?
            WHERE owner_message_id = ?;
            """,
            arguments: [
                MediaUploadStatus.success.rawValue,
                500,
                "sql_plan_message_10"
            ],
            databaseContext: databaseContext
        )
        expectPlan(ownerMessagePlan, contains: "idx_media_resource_owner_message")

        let duplicatePlan = try await queryPlan(
            """
            EXPLAIN QUERY PLAN
            SELECT message_id
            FROM message
            WHERE
                (? IS NOT NULL AND client_msg_id = ?)
                OR (? IS NOT NULL AND server_msg_id = ?)
                OR (conversation_id = ? AND seq = ?)
            LIMIT 1;
            """,
            arguments: [
                nil,
                nil,
                nil,
                nil,
                "sql_plan_conversation",
                10
            ],
            databaseContext: databaseContext
        )
        expectPlan(duplicatePlan, contains: "idx_message_conversation_seq")

        let markReadPlan = try await queryPlan(
            """
            EXPLAIN QUERY PLAN
            UPDATE message
            SET read_status = ?
            WHERE conversation_id = ?
            AND direction = ?
            AND read_status = ?
            AND is_deleted = 0;
            """,
            arguments: [
                MessageReadStatus.read.rawValue,
                "sql_plan_conversation",
                MessageDirection.incoming.rawValue,
                MessageReadStatus.unread.rawValue
            ],
            databaseContext: databaseContext
        )
        expectPlan(markReadPlan, contains: "idx_message_conversation_read_state")

        let recoveryPlan = try await queryPlan(
            """
            EXPLAIN QUERY PLAN
            SELECT message.message_id, message.conversation_id, message.client_msg_id, message.msg_type
            FROM message
            INNER JOIN conversation ON conversation.conversation_id = message.conversation_id
            WHERE conversation.user_id = ?
            AND message.direction = ?
            AND message.send_status = ?
            AND message.is_deleted = 0
            ORDER BY message.local_time ASC, message.sort_seq ASC;
            """,
            arguments: [
                "sql_plan_user",
                MessageDirection.outgoing.rawValue,
                MessageSendStatus.sending.rawValue
            ],
            databaseContext: databaseContext
        )
        expectPlan(recoveryPlan, contains: "idx_message_conversation_send_recovery")
    }

    @Test func conversationListLoadsExtraJSONWithBatchQueryBehaviorUnchanged() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "sql_extra_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "sql_extra_with_mention", userID: "sql_extra_user", title: "Mention", sortTimestamp: 20)
        )
        try await repository.upsertConversation(
            makeConversationRecord(id: "sql_extra_without_mention", userID: "sql_extra_user", title: "Normal", sortTimestamp: 10)
        )
        _ = try await databaseContext.databaseActor.write(paths: databaseContext.paths) { db in
            try db.execute(
                sql: """
                UPDATE conversation
                SET extra_json = ?
                WHERE conversation_id = ?;
                """,
                arguments: [#"{"has_unread_mention":true}"#, "sql_extra_with_mention"]
            )
        }

        let conversations = try await repository.listConversations(for: "sql_extra_user", limit: 20, after: nil)

        #expect(conversations.first { $0.id == "sql_extra_with_mention" }?.hasUnreadMention == true)
        #expect(conversations.first { $0.id == "sql_extra_without_mention" }?.hasUnreadMention == false)
    }
}

private func queryPlan(
    _ statement: String,
    arguments: StatementArguments,
    databaseContext: DatabaseTestContext
) async throws -> String {
    try await databaseContext.databaseActor.read(paths: databaseContext.paths) { db in
        let rows = try Row.fetchAll(db, sql: statement, arguments: arguments)
        return rows.compactMap { $0["detail"] as String? }.joined(separator: "\n")
    }
}

private func expectPlan(_ plan: String, contains indexName: String) {
    #expect(plan.contains(indexName), "查询计划未命中 \(indexName)：\n\(plan)")
}

private func seedSQLPerformanceDataset(
    databaseContext: DatabaseTestContext,
    userID: UserID
) async throws {
    _ = try await databaseContext.databaseActor.write(paths: databaseContext.paths) { db in
        try db.execute(
            sql: """
            INSERT INTO conversation (
                conversation_id, user_id, biz_type, target_id, title, last_message_digest,
                unread_count, is_pinned, is_muted, is_hidden, sort_ts, updated_at, created_at
            ) VALUES (?, ?, ?, ?, ?, '', 0, 0, 0, 0, 1000, 1000, 1000);
            """,
            arguments: [
                "sql_plan_conversation",
                userID.rawValue,
                ConversationType.single.rawValue,
                "sql_plan_target",
                "SQL Plan"
            ]
        )
    }
    try await seedPerformanceMessages(
        databaseContext: databaseContext,
        conversationID: "sql_plan_conversation",
        userID: userID,
        count: 250
    )
    _ = try await databaseContext.databaseActor.write(paths: databaseContext.paths) { db in
        try db.execute(
            sql: """
            UPDATE message
            SET direction = ?, send_status = ?, read_status = ?, seq = sort_seq, server_msg_id = 'server_' || sort_seq
            WHERE conversation_id = ?;
            """,
            arguments: [
                MessageDirection.incoming.rawValue,
                MessageSendStatus.sending.rawValue,
                MessageReadStatus.unread.rawValue,
                "sql_plan_conversation"
            ]
        )
    }
    try await seedSQLPerformancePendingJobs(databaseContext: databaseContext, userID: userID)
    try await seedSQLPerformanceMediaResources(databaseContext: databaseContext, userID: userID)
}

private func seedSQLPerformancePendingJobs(
    databaseContext: DatabaseTestContext,
    userID: UserID
) async throws {
    _ = try await databaseContext.databaseActor.write(paths: databaseContext.paths) { db in
        for index in 1...40 {
            let status: PendingJobStatus = index.isMultiple(of: 2) ? .pending : .running
            try db.execute(
                sql: """
                INSERT INTO pending_job (
                    job_id, user_id, job_type, biz_key, payload_json, status,
                    retry_count, max_retry_count, next_retry_at, updated_at, created_at
                ) VALUES (?, ?, ?, ?, '{}', ?, 0, 3, ?, ?, ?);
                """,
                arguments: [
                    "sql_plan_job_\(index)",
                    userID.rawValue,
                    PendingJobType.messageResend.rawValue,
                    "sql_plan_job_\(index)",
                    status.rawValue,
                    index * 10,
                    index * 10,
                    index * 10
                ]
            )
        }
    }
}

private func seedSQLPerformanceMediaResources(
    databaseContext: DatabaseTestContext,
    userID: UserID
) async throws {
    _ = try await databaseContext.databaseActor.write(paths: databaseContext.paths) { db in
        for index in 1...40 {
            try db.execute(
                sql: """
                INSERT INTO media_resource (
                    media_id, user_id, owner_message_id, local_path, remote_url, thumb_path,
                    size_bytes, md5, upload_status, download_status, updated_at, created_at
                ) VALUES (?, ?, ?, ?, ?, NULL, 128, NULL, 0, 0, ?, ?);
                """,
                arguments: [
                    "sql_plan_media_\(index)",
                    userID.rawValue,
                    "sql_plan_message_\(index)",
                    "/tmp/sql_plan_media_\(index).dat",
                    "https://example.com/sql_plan_media_\(index).dat",
                    index * 10,
                    index * 10
                ]
            )
        }
    }
}
