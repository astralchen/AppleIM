import Testing
import Foundation

@testable import AppleIM

extension AppleIMTests {
    @Test func sqlHotPathIndexesAreAvailableAfterBootstrap() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (_, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "sql_index_user")
        let rows = try await databaseContext.databaseActor.query(
            "SELECT name FROM sqlite_master WHERE type = 'index' ORDER BY name;",
            paths: databaseContext.paths
        )
        let indexNames = Set(rows.compactMap { $0.string("name") })

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
            parameters: [
                .text("sql_plan_user"),
                .integer(Int64(PendingJobStatus.pending.rawValue)),
                .integer(Int64(PendingJobStatus.running.rawValue)),
                .integer(500)
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
            parameters: [.text("sql_plan_user")],
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
            parameters: [
                .integer(Int64(MediaUploadStatus.success.rawValue)),
                .integer(500),
                .text("sql_plan_message_10")
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
            parameters: [
                .optionalText(nil),
                .optionalText(nil),
                .optionalText(nil),
                .optionalText(nil),
                .text("sql_plan_conversation"),
                .integer(10)
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
            parameters: [
                .integer(Int64(MessageReadStatus.read.rawValue)),
                .text("sql_plan_conversation"),
                .integer(Int64(MessageDirection.incoming.rawValue)),
                .integer(Int64(MessageReadStatus.unread.rawValue))
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
            parameters: [
                .text("sql_plan_user"),
                .integer(Int64(MessageDirection.outgoing.rawValue)),
                .integer(Int64(MessageSendStatus.sending.rawValue))
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
        try await databaseContext.databaseActor.execute(
            """
            UPDATE conversation
            SET extra_json = ?
            WHERE conversation_id = ?;
            """,
            parameters: [
                .text(#"{"has_unread_mention":true}"#),
                .text("sql_extra_with_mention")
            ],
            paths: databaseContext.paths
        )

        let conversations = try await repository.listConversations(for: "sql_extra_user", limit: 20, after: nil)

        #expect(conversations.first { $0.id == "sql_extra_with_mention" }?.hasUnreadMention == true)
        #expect(conversations.first { $0.id == "sql_extra_without_mention" }?.hasUnreadMention == false)
    }
}

private func queryPlan(
    _ statement: String,
    parameters: [SQLiteValue],
    databaseContext: DatabaseTestContext
) async throws -> String {
    let rows = try await databaseContext.databaseActor.query(
        statement,
        parameters: parameters,
        paths: databaseContext.paths
    )
    return rows.compactMap { $0.string("detail") }.joined(separator: "\n")
}

private func expectPlan(_ plan: String, contains indexName: String) {
    #expect(plan.contains(indexName), "查询计划未命中 \(indexName)：\n\(plan)")
}

private func seedSQLPerformanceDataset(
    databaseContext: DatabaseTestContext,
    userID: UserID
) async throws {
    try await databaseContext.databaseActor.execute(
        """
        INSERT INTO conversation (
            conversation_id, user_id, biz_type, target_id, title, last_message_digest,
            unread_count, is_pinned, is_muted, is_hidden, sort_ts, updated_at, created_at
        ) VALUES (?, ?, ?, ?, ?, '', 0, 0, 0, 0, 1000, 1000, 1000);
        """,
        parameters: [
            .text("sql_plan_conversation"),
            .text(userID.rawValue),
            .integer(Int64(ConversationType.single.rawValue)),
            .text("sql_plan_target"),
            .text("SQL Plan")
        ],
        paths: databaseContext.paths
    )
    try await seedPerformanceMessages(
        databaseContext: databaseContext,
        conversationID: "sql_plan_conversation",
        userID: userID,
        count: 250
    )
    try await databaseContext.databaseActor.execute(
        """
        UPDATE message
        SET direction = ?, send_status = ?, read_status = ?, seq = sort_seq, server_msg_id = 'server_' || sort_seq
        WHERE conversation_id = ?;
        """,
        parameters: [
            .integer(Int64(MessageDirection.incoming.rawValue)),
            .integer(Int64(MessageSendStatus.sending.rawValue)),
            .integer(Int64(MessageReadStatus.unread.rawValue)),
            .text("sql_plan_conversation")
        ],
        paths: databaseContext.paths
    )
    try await seedSQLPerformancePendingJobs(databaseContext: databaseContext, userID: userID)
    try await seedSQLPerformanceMediaResources(databaseContext: databaseContext, userID: userID)
}

private func seedSQLPerformancePendingJobs(
    databaseContext: DatabaseTestContext,
    userID: UserID
) async throws {
    let statements = (1...40).map { index in
        let status: PendingJobStatus = index.isMultiple(of: 2) ? .pending : .running
        return SQLiteStatement(
            """
            INSERT INTO pending_job (
                job_id, user_id, job_type, biz_key, payload_json, status,
                retry_count, max_retry_count, next_retry_at, updated_at, created_at
            ) VALUES (?, ?, ?, ?, '{}', ?, 0, 3, ?, ?, ?);
            """,
            parameters: [
                .text("sql_plan_job_\(index)"),
                .text(userID.rawValue),
                .integer(Int64(PendingJobType.messageResend.rawValue)),
                .text("sql_plan_job_\(index)"),
                .integer(Int64(status.rawValue)),
                .integer(Int64(index * 10)),
                .integer(Int64(index * 10)),
                .integer(Int64(index * 10))
            ]
        )
    }
    try await databaseContext.databaseActor.performTransaction(statements, paths: databaseContext.paths)
}

private func seedSQLPerformanceMediaResources(
    databaseContext: DatabaseTestContext,
    userID: UserID
) async throws {
    let statements = (1...40).map { index in
        SQLiteStatement(
            """
            INSERT INTO media_resource (
                media_id, user_id, owner_message_id, local_path, remote_url, thumb_path,
                size_bytes, md5, upload_status, download_status, updated_at, created_at
            ) VALUES (?, ?, ?, ?, ?, NULL, 128, NULL, 0, 0, ?, ?);
            """,
            parameters: [
                .text("sql_plan_media_\(index)"),
                .text(userID.rawValue),
                .text("sql_plan_message_\(index)"),
                .text("/tmp/sql_plan_media_\(index).dat"),
                .text("https://example.com/sql_plan_media_\(index).dat"),
                .integer(Int64(index * 10)),
                .integer(Int64(index * 10))
            ]
        )
    }
    try await databaseContext.databaseActor.performTransaction(statements, paths: databaseContext.paths)
}
