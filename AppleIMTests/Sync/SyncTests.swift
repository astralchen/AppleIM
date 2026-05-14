import Testing
import Foundation

@testable import AppleIM

extension AppleIMTests {
    @Test func chatStoreConversationChangeEventParsesNotificationPayload() {
        let notification = Notification(
            name: .chatStoreConversationsDidChange,
            object: nil,
            userInfo: [
                ChatStoreConversationChangeNotification.userIDKey: "typed_event_user",
                ChatStoreConversationChangeNotification.conversationIDsKey: [
                    "typed_event_conversation_a",
                    "typed_event_conversation_b"
                ]
            ]
        )

        let event = ChatStoreConversationChangeEvent(notification: notification)

        #expect(event?.userID == UserID(rawValue: "typed_event_user"))
        #expect(event?.conversationIDs == [
            ConversationID(rawValue: "typed_event_conversation_a"),
            ConversationID(rawValue: "typed_event_conversation_b")
        ])
    }

    @Test func syncEngineAppliesFirstMessageBatchAndStoresCheckpoint() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "sync_first_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "sync_first_conversation", userID: "sync_first_user", title: "Sync", sortTimestamp: 1)
        )

        let batch = SyncBatch(
            messages: [
                IncomingSyncMessage(
                    messageID: "sync_first_message",
                    conversationID: "sync_first_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "sync_first_client",
                    serverMessageID: "sync_first_server",
                    sequence: 10,
                    text: "First sync message",
                    serverTime: 10
                )
            ],
            nextCursor: "cursor_10",
            nextSequence: 10
        )
        let engine = SyncEngineActor(
            userID: "sync_first_user",
            store: repository,
            deltaService: StaticSyncDeltaService(batch: batch)
        )

        let result = try await engine.syncOnce()
        let messages = try await repository.listMessages(conversationID: "sync_first_conversation", limit: 20, beforeSortSeq: nil)
        let checkpoint = try await repository.syncCheckpoint(for: SyncEngineActor.messageBizKey)

        #expect(result.previousCheckpoint == nil)
        #expect(result.fetchedCount == 1)
        #expect(result.insertedCount == 1)
        #expect(result.skippedDuplicateCount == 0)
        #expect(try messages.map { try requireTextContent($0) } == ["First sync message"])
        #expect(messages.first?.state.sendStatus == .success)
        #expect(checkpoint?.cursor == "cursor_10")
        #expect(checkpoint?.sequence == 10)
    }

    @Test func incomingSyncMessagePostsConversationChangeNotification() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "sync_notify_change_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "sync_notify_change_conversation", userID: "sync_notify_change_user", title: "Notify", sortTimestamp: 1)
        )
        let notificationSpy = ConversationChangeNotificationSpy()
        let observer = NotificationCenter.default.addObserver(
            forName: .chatStoreConversationsDidChange,
            object: nil,
            queue: .main
        ) { notification in
            let userID = notification.userInfo?[ChatStoreConversationChangeNotification.userIDKey] as? String
            let conversationIDs = notification.userInfo?[ChatStoreConversationChangeNotification.conversationIDsKey] as? [String] ?? []
            Task {
                await notificationSpy.record(userID: userID, conversationIDs: conversationIDs)
            }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        _ = try await repository.applyIncomingSyncBatch(
            SyncBatch(
                messages: [
                    IncomingSyncMessage(
                        messageID: "sync_notify_change_message",
                        conversationID: "sync_notify_change_conversation",
                        senderID: "sync_sender",
                        serverMessageID: "sync_notify_change_server",
                        sequence: 1,
                        text: "Notify list",
                        serverTime: 1
                    )
                ],
                nextCursor: nil,
                nextSequence: 1
            ),
            userID: "sync_notify_change_user"
        )

        try await waitForCondition {
            await notificationSpy.didRecord(
                userID: "sync_notify_change_user",
                conversationID: "sync_notify_change_conversation"
            )
        }
    }

    @Test func syncEngineSkipsDuplicateClientServerAndSequenceMessages() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "sync_duplicate_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "sync_duplicate_conversation", userID: "sync_duplicate_user", title: "Duplicates", sortTimestamp: 1)
        )

        let batch = SyncBatch(
            messages: [
                IncomingSyncMessage(
                    messageID: "sync_unique_1",
                    conversationID: "sync_duplicate_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "dup_client_1",
                    serverMessageID: "dup_server_1",
                    sequence: 1,
                    text: "Unique 1",
                    serverTime: 1
                ),
                IncomingSyncMessage(
                    messageID: "sync_duplicate_client",
                    conversationID: "sync_duplicate_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "dup_client_1",
                    serverMessageID: "dup_server_2",
                    sequence: 2,
                    text: "Duplicate client",
                    serverTime: 2
                ),
                IncomingSyncMessage(
                    messageID: "sync_duplicate_server",
                    conversationID: "sync_duplicate_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "dup_client_3",
                    serverMessageID: "dup_server_1",
                    sequence: 3,
                    text: "Duplicate server",
                    serverTime: 3
                ),
                IncomingSyncMessage(
                    messageID: "sync_duplicate_sequence",
                    conversationID: "sync_duplicate_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "dup_client_4",
                    serverMessageID: "dup_server_4",
                    sequence: 1,
                    text: "Duplicate sequence",
                    serverTime: 4
                ),
                IncomingSyncMessage(
                    messageID: "sync_unique_2",
                    conversationID: "sync_duplicate_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "dup_client_5",
                    serverMessageID: "dup_server_5",
                    sequence: 5,
                    text: "Unique 2",
                    serverTime: 5
                )
            ],
            nextCursor: "cursor_5",
            nextSequence: 5
        )
        let engine = SyncEngineActor(
            userID: "sync_duplicate_user",
            store: repository,
            deltaService: StaticSyncDeltaService(batch: batch)
        )

        let result = try await engine.syncOnce()
        let messages = try await repository.listMessages(conversationID: "sync_duplicate_conversation", limit: 20, beforeSortSeq: nil)

        #expect(result.fetchedCount == 5)
        #expect(result.insertedCount == 2)
        #expect(result.skippedDuplicateCount == 3)
        #expect(try messages.map { try requireTextContent($0) } == ["Unique 2", "Unique 1"])
    }

    @Test func incomingSyncMessageSchedulesLocalNotification() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "notify_user")
        let notificationManager = CapturingLocalNotificationManager()
        let repository = LocalChatRepository(
            database: databaseActor,
            paths: paths,
            localNotificationManager: notificationManager
        )
        try await repository.upsertConversation(
            makeConversationRecord(id: "notify_conversation", userID: "notify_user", title: "Notify", sortTimestamp: 1)
        )

        _ = try await repository.applyIncomingSyncBatch(
            SyncBatch(
                messages: [
                    IncomingSyncMessage(
                        messageID: "notify_message",
                        conversationID: "notify_conversation",
                        senderID: "notify_sender",
                        serverMessageID: "notify_server",
                        sequence: 1,
                        text: "Preview body",
                        serverTime: 1
                    )
                ],
                nextCursor: "cursor_1",
                nextSequence: 1
            ),
            userID: "notify_user"
        )

        let payloads = await notificationManager.payloads()
        #expect(payloads.count == 1)
        #expect(payloads.first?.conversationID == "notify_conversation")
        #expect(payloads.first?.messageID == "notify_message")
        #expect(payloads.first?.title == "Notify")
        #expect(payloads.first?.notificationBody == "Preview body")
    }

    @Test func applicationBadgeRefreshesFromTotalUnreadIncludingMutedByDefault() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "badge_total_user")
        let badgeManager = CapturingApplicationBadgeManager()
        let repository = LocalChatRepository(
            database: databaseActor,
            paths: paths,
            applicationBadgeManager: badgeManager
        )
        try await repository.upsertConversation(
            makeConversationRecord(id: "badge_normal", userID: "badge_total_user", title: "Normal", unreadCount: 2, sortTimestamp: 1)
        )
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "badge_muted",
                userID: "badge_total_user",
                title: "Muted",
                isMuted: true,
                unreadCount: 3,
                sortTimestamp: 2
            )
        )

        let count = try await repository.refreshApplicationBadge(userID: "badge_total_user")
        let badgeValues = await badgeManager.values()

        #expect(count == 5)
        #expect(badgeValues.last == 5)
    }

    @Test func applicationBadgeCanExcludeMutedConversationUnread() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "badge_muted_policy_user")
        let badgeManager = CapturingApplicationBadgeManager()
        let repository = LocalChatRepository(
            database: databaseActor,
            paths: paths,
            applicationBadgeManager: badgeManager
        )
        try await repository.upsertConversation(
            makeConversationRecord(id: "badge_policy_normal", userID: "badge_muted_policy_user", title: "Normal", unreadCount: 2, sortTimestamp: 1)
        )
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "badge_policy_muted",
                userID: "badge_muted_policy_user",
                title: "Muted",
                isMuted: true,
                unreadCount: 3,
                sortTimestamp: 2
            )
        )

        try await repository.updateBadgeIncludeMuted(userID: "badge_muted_policy_user", includeMuted: false)
        let setting = try await repository.notificationSetting(for: "badge_muted_policy_user")
        let conversations = try await repository.listConversations(for: "badge_muted_policy_user")
        let badgeValues = await badgeManager.values()

        #expect(setting.badgeIncludeMuted == false)
        #expect(conversations.first { $0.id == "badge_policy_muted" }?.unreadCount == 3)
        #expect(badgeValues.last == 2)
    }

    @Test func markingConversationReadRefreshesApplicationBadgeToZero() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "badge_read_user")
        let badgeManager = CapturingApplicationBadgeManager()
        let repository = LocalChatRepository(
            database: databaseActor,
            paths: paths,
            applicationBadgeManager: badgeManager
        )
        try await repository.upsertConversation(
            makeConversationRecord(id: "badge_read_conversation", userID: "badge_read_user", title: "Read", unreadCount: 4, sortTimestamp: 1)
        )

        try await repository.markConversationRead(conversationID: "badge_read_conversation", userID: "badge_read_user")
        let badgeValues = await badgeManager.values()

        #expect(badgeValues.contains(4))
        #expect(badgeValues.last == 0)
    }

    @Test func disabledApplicationBadgeRefreshesToZeroWithoutClearingConversationUnread() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "badge_disabled_user")
        let badgeManager = CapturingApplicationBadgeManager()
        let repository = LocalChatRepository(
            database: databaseActor,
            paths: paths,
            applicationBadgeManager: badgeManager
        )
        try await repository.upsertConversation(
            makeConversationRecord(id: "badge_disabled_conversation", userID: "badge_disabled_user", title: "Disabled", unreadCount: 6, sortTimestamp: 1)
        )

        try await repository.updateBadgeEnabled(userID: "badge_disabled_user", isEnabled: false)
        let conversations = try await repository.listConversations(for: "badge_disabled_user")
        let badgeValues = await badgeManager.values()

        #expect(conversations.first?.unreadCount == 6)
        #expect(badgeValues.last == 0)
    }

    @Test func incomingSyncMessageCarriesLatestBadgeCountInNotificationPayload() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "notify_badge_user")
        let notificationManager = CapturingLocalNotificationManager()
        let badgeManager = CapturingApplicationBadgeManager()
        let repository = LocalChatRepository(
            database: databaseActor,
            paths: paths,
            localNotificationManager: notificationManager,
            applicationBadgeManager: badgeManager
        )
        try await repository.upsertConversation(
            makeConversationRecord(id: "notify_badge_conversation", userID: "notify_badge_user", title: "Badge", unreadCount: 1, sortTimestamp: 1)
        )

        _ = try await repository.applyIncomingSyncBatch(
            SyncBatch(
                messages: [
                    IncomingSyncMessage(
                        messageID: "notify_badge_message",
                        conversationID: "notify_badge_conversation",
                        senderID: "notify_badge_sender",
                        serverMessageID: "notify_badge_server",
                        sequence: 2,
                        text: "Badge body",
                        serverTime: 2
                    )
                ],
                nextCursor: "cursor_2",
                nextSequence: 2
            ),
            userID: "notify_badge_user"
        )

        let payloads = await notificationManager.payloads()
        let badgeValues = await badgeManager.values()

        #expect(payloads.count == 1)
        #expect(payloads.first?.badgeCount == 2)
        #expect(badgeValues.last == 2)
    }

    @Test func mutedConversationDoesNotScheduleLocalNotification() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "muted_notify_user")
        let notificationManager = CapturingLocalNotificationManager()
        let repository = LocalChatRepository(
            database: databaseActor,
            paths: paths,
            localNotificationManager: notificationManager
        )
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "muted_notify_conversation",
                userID: "muted_notify_user",
                title: "Muted",
                isMuted: true,
                sortTimestamp: 1
            )
        )

        _ = try await repository.applyIncomingSyncBatch(
            SyncBatch(
                messages: [
                    IncomingSyncMessage(
                        messageID: "muted_notify_message",
                        conversationID: "muted_notify_conversation",
                        senderID: "notify_sender",
                        serverMessageID: "muted_notify_server",
                        sequence: 1,
                        text: "Muted body",
                        serverTime: 1
                    )
                ],
                nextCursor: "cursor_1",
                nextSequence: 1
            ),
            userID: "muted_notify_user"
        )

        let payloads = await notificationManager.payloads()
        #expect(payloads.isEmpty)
    }

    @Test func hiddenPreviewNotificationUsesGenericBody() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "hidden_preview_user")
        let notificationManager = CapturingLocalNotificationManager()
        let repository = LocalChatRepository(
            database: databaseActor,
            paths: paths,
            localNotificationManager: notificationManager
        )
        try await databaseActor.execute(
            """
            INSERT INTO notification_setting (user_id, is_enabled, show_preview, updated_at)
            VALUES (?, 1, 0, 1);
            """,
            parameters: [.text("hidden_preview_user")],
            paths: paths
        )
        try await repository.upsertConversation(
            makeConversationRecord(id: "hidden_preview_conversation", userID: "hidden_preview_user", title: "Hidden", sortTimestamp: 1)
        )

        _ = try await repository.applyIncomingSyncBatch(
            SyncBatch(
                messages: [
                    IncomingSyncMessage(
                        messageID: "hidden_preview_message",
                        conversationID: "hidden_preview_conversation",
                        senderID: "notify_sender",
                        serverMessageID: "hidden_preview_server",
                        sequence: 1,
                        text: "Sensitive raw message",
                        serverTime: 1
                    )
                ],
                nextCursor: "cursor_1",
                nextSequence: 1
            ),
            userID: "hidden_preview_user"
        )

        let payloads = await notificationManager.payloads()
        #expect(payloads.count == 1)
        #expect(payloads.first?.showPreview == false)
        #expect(payloads.first?.notificationBody == "收到一条新消息")
        #expect(payloads.first?.notificationBody != "Sensitive raw message")
    }

    @Test func outgoingDuplicateAndEmptySyncBatchesDoNotScheduleLocalNotifications() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "quiet_notify_user")
        let initialRepository = LocalChatRepository(database: databaseActor, paths: paths)
        try await initialRepository.upsertConversation(
            makeConversationRecord(id: "quiet_notify_conversation", userID: "quiet_notify_user", title: "Quiet", sortTimestamp: 1)
        )

        let duplicateBatch = SyncBatch(
            messages: [
                IncomingSyncMessage(
                    messageID: "quiet_duplicate_message",
                    conversationID: "quiet_notify_conversation",
                    senderID: "notify_sender",
                    serverMessageID: "quiet_duplicate_server",
                    sequence: 1,
                    text: "Already inserted",
                    serverTime: 1
                )
            ],
            nextCursor: "cursor_1",
            nextSequence: 1
        )
        _ = try await initialRepository.applyIncomingSyncBatch(duplicateBatch, userID: "quiet_notify_user")

        let notificationManager = CapturingLocalNotificationManager()
        let repository = LocalChatRepository(
            database: databaseActor,
            paths: paths,
            localNotificationManager: notificationManager
        )
        _ = try await repository.applyIncomingSyncBatch(
            SyncBatch(messages: [], nextCursor: "cursor_empty", nextSequence: 1),
            userID: "quiet_notify_user"
        )
        _ = try await repository.applyIncomingSyncBatch(
            SyncBatch(
                messages: [
                    IncomingSyncMessage(
                        messageID: "quiet_outgoing_message",
                        conversationID: "quiet_notify_conversation",
                        senderID: "quiet_notify_user",
                        serverMessageID: "quiet_outgoing_server",
                        sequence: 2,
                        text: "Outgoing",
                        serverTime: 2,
                        direction: .outgoing
                    )
                ],
                nextCursor: "cursor_2",
                nextSequence: 2
            ),
            userID: "quiet_notify_user"
        )
        let duplicateResult = try await repository.applyIncomingSyncBatch(duplicateBatch, userID: "quiet_notify_user")

        let payloads = await notificationManager.payloads()
        #expect(duplicateResult.insertedCount == 0)
        #expect(duplicateResult.skippedDuplicateCount == 1)
        #expect(payloads.isEmpty)
    }

    @Test func syncEngineRefreshesConversationSummaryFromLatestSequence() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "sync_summary_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "sync_summary_conversation", userID: "sync_summary_user", title: "Summary", sortTimestamp: 1)
        )

        let batch = SyncBatch(
            messages: [
                IncomingSyncMessage(
                    messageID: "sync_summary_latest",
                    conversationID: "sync_summary_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "summary_client_30",
                    serverMessageID: "summary_server_30",
                    sequence: 30,
                    text: "Latest by seq",
                    serverTime: 30
                ),
                IncomingSyncMessage(
                    messageID: "sync_summary_older",
                    conversationID: "sync_summary_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "summary_client_20",
                    serverMessageID: "summary_server_20",
                    sequence: 20,
                    text: "Older by seq",
                    serverTime: 20
                )
            ],
            nextCursor: "cursor_30",
            nextSequence: 30
        )
        let engine = SyncEngineActor(
            userID: "sync_summary_user",
            store: repository,
            deltaService: StaticSyncDeltaService(batch: batch)
        )

        _ = try await engine.syncOnce()
        let messages = try await repository.listMessages(conversationID: "sync_summary_conversation", limit: 20, beforeSortSeq: nil)
        let conversations = try await repository.listConversations(for: "sync_summary_user")

        #expect(try messages.map { try requireTextContent($0) } == ["Latest by seq", "Older by seq"])
        #expect(conversations.first?.lastMessageDigest == "Latest by seq")
        #expect(conversations.first?.unreadCount == 2)
    }

    @Test func syncEngineRollsBackMessagesAndCheckpointWhenBatchInsertFails() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "sync_rollback_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "sync_rollback_conversation", userID: "sync_rollback_user", title: "Rollback", sortTimestamp: 1)
        )

        let batch = SyncBatch(
            messages: [
                IncomingSyncMessage(
                    messageID: "sync_rollback_same_id",
                    conversationID: "sync_rollback_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "rollback_client_1",
                    serverMessageID: "rollback_server_1",
                    sequence: 100,
                    text: "Should roll back",
                    serverTime: 100
                ),
                IncomingSyncMessage(
                    messageID: "sync_rollback_same_id",
                    conversationID: "sync_rollback_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "rollback_client_2",
                    serverMessageID: "rollback_server_2",
                    sequence: 101,
                    text: "Duplicate primary key",
                    serverTime: 101
                )
            ],
            nextCursor: "cursor_rollback",
            nextSequence: 101
        )
        let engine = SyncEngineActor(
            userID: "sync_rollback_user",
            store: repository,
            deltaService: StaticSyncDeltaService(batch: batch)
        )

        var didThrow = false
        do {
            _ = try await engine.syncOnce()
        } catch {
            didThrow = true
        }

        let messages = try await repository.listMessages(conversationID: "sync_rollback_conversation", limit: 20, beforeSortSeq: nil)
        let checkpoint = try await repository.syncCheckpoint(for: SyncEngineActor.messageBizKey)

        #expect(didThrow)
        #expect(messages.isEmpty)
        #expect(checkpoint == nil)
    }

    @Test func syncEngineRunsMultipleBatchesUntilCaughtUp() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "sync_multi_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "sync_multi_conversation", userID: "sync_multi_user", title: "Multi", sortTimestamp: 1)
        )

        let deltaService = ScriptedSyncDeltaService(
            batches: [
                SyncBatch(
                    messages: [
                        IncomingSyncMessage(
                            messageID: "sync_multi_1",
                            conversationID: "sync_multi_conversation",
                            senderID: "sync_sender",
                            clientMessageID: "sync_multi_client_1",
                            serverMessageID: "sync_multi_server_1",
                            sequence: 1,
                            text: "First page",
                            serverTime: 1
                        )
                    ],
                    nextCursor: "cursor_1",
                    nextSequence: 1,
                    hasMore: true
                ),
                SyncBatch(
                    messages: [
                        IncomingSyncMessage(
                            messageID: "sync_multi_2",
                            conversationID: "sync_multi_conversation",
                            senderID: "sync_sender",
                            clientMessageID: "sync_multi_client_2",
                            serverMessageID: "sync_multi_server_2",
                            sequence: 2,
                            text: "Second page",
                            serverTime: 2
                        )
                    ],
                    nextCursor: "cursor_2",
                    nextSequence: 2
                )
            ]
        )
        let engine = SyncEngineActor(
            userID: "sync_multi_user",
            store: repository,
            deltaService: deltaService
        )

        let result = try await engine.syncUntilCaughtUp(maxBatches: 4)
        let messages = try await repository.listMessages(conversationID: "sync_multi_conversation", limit: 20, beforeSortSeq: nil)
        let checkpoint = try await repository.syncCheckpoint(for: SyncEngineActor.messageBizKey)
        let requestedCheckpoints = await deltaService.requestedCheckpoints()

        #expect(result.batchCount == 2)
        #expect(result.fetchedCount == 2)
        #expect(result.insertedCount == 2)
        #expect(result.skippedDuplicateCount == 0)
        #expect(result.initialCheckpoint == nil)
        #expect(result.finalCheckpoint.cursor == "cursor_2")
        #expect(try messages.map { try requireTextContent($0) } == ["Second page", "First page"])
        #expect(checkpoint?.cursor == "cursor_2")
        #expect(checkpoint?.sequence == 2)
        #expect(requestedCheckpoints.map(\.?.cursor) == [nil, "cursor_1"])
    }

    @Test func syncEngineCatchesUpFromExistingCheckpointAndRefreshesLatestSummary() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "sync_catchup_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "sync_catchup_conversation", userID: "sync_catchup_user", title: "Catch Up", sortTimestamp: 1)
        )

        let firstEngine = SyncEngineActor(
            userID: "sync_catchup_user",
            store: repository,
            deltaService: StaticSyncDeltaService(
                batch: SyncBatch(
                    messages: [
                        IncomingSyncMessage(
                            messageID: "sync_catchup_old",
                            conversationID: "sync_catchup_conversation",
                            senderID: "sync_sender",
                            clientMessageID: "sync_catchup_client_1",
                            serverMessageID: "sync_catchup_server_1",
                            sequence: 10,
                            text: "Already synced",
                            serverTime: 10
                        )
                    ],
                    nextCursor: "cursor_10",
                    nextSequence: 10
                )
            )
        )
        _ = try await firstEngine.syncOnce()

        let deltaService = ScriptedSyncDeltaService(
            batches: [
                SyncBatch(
                    messages: [
                        IncomingSyncMessage(
                            messageID: "sync_catchup_newer",
                            conversationID: "sync_catchup_conversation",
                            senderID: "sync_sender",
                            clientMessageID: "sync_catchup_client_20",
                            serverMessageID: "sync_catchup_server_20",
                            sequence: 20,
                            text: "Caught up newer",
                            serverTime: 20
                        ),
                        IncomingSyncMessage(
                            messageID: "sync_catchup_latest",
                            conversationID: "sync_catchup_conversation",
                            senderID: "sync_sender",
                            clientMessageID: "sync_catchup_client_30",
                            serverMessageID: "sync_catchup_server_30",
                            sequence: 30,
                            text: "Caught up latest",
                            serverTime: 30
                        )
                    ],
                    nextCursor: "cursor_30",
                    nextSequence: 30
                )
            ]
        )
        let catchUpEngine = SyncEngineActor(
            userID: "sync_catchup_user",
            store: repository,
            deltaService: deltaService
        )

        let result = try await catchUpEngine.syncUntilCaughtUp()
        let messages = try await repository.listMessages(conversationID: "sync_catchup_conversation", limit: 20, beforeSortSeq: nil)
        let conversations = try await repository.listConversations(for: "sync_catchup_user")
        let requestedCheckpoints = await deltaService.requestedCheckpoints()

        #expect(result.initialCheckpoint?.cursor == "cursor_10")
        #expect(result.finalCheckpoint.cursor == "cursor_30")
        #expect(try messages.map { try requireTextContent($0) } == ["Caught up latest", "Caught up newer", "Already synced"])
        #expect(conversations.first?.lastMessageDigest == "Caught up latest")
        #expect(requestedCheckpoints.first??.cursor == "cursor_10")
    }

    @Test func syncEngineSkipsDuplicatesAcrossBatches() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "sync_cross_duplicate_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "sync_cross_duplicate_conversation", userID: "sync_cross_duplicate_user", title: "Cross Duplicates", sortTimestamp: 1)
        )

        let deltaService = ScriptedSyncDeltaService(
            batches: [
                SyncBatch(
                    messages: [
                        IncomingSyncMessage(
                            messageID: "sync_cross_unique_1",
                            conversationID: "sync_cross_duplicate_conversation",
                            senderID: "sync_sender",
                            clientMessageID: "sync_cross_client_1",
                            serverMessageID: "sync_cross_server_1",
                            sequence: 1,
                            text: "Unique first batch",
                            serverTime: 1
                        )
                    ],
                    nextCursor: "cursor_1",
                    nextSequence: 1,
                    hasMore: true
                ),
                SyncBatch(
                    messages: [
                        IncomingSyncMessage(
                            messageID: "sync_cross_duplicate_client",
                            conversationID: "sync_cross_duplicate_conversation",
                            senderID: "sync_sender",
                            clientMessageID: "sync_cross_client_1",
                            serverMessageID: "sync_cross_server_2",
                            sequence: 2,
                            text: "Duplicate client across batch",
                            serverTime: 2
                        ),
                        IncomingSyncMessage(
                            messageID: "sync_cross_duplicate_server",
                            conversationID: "sync_cross_duplicate_conversation",
                            senderID: "sync_sender",
                            clientMessageID: "sync_cross_client_3",
                            serverMessageID: "sync_cross_server_1",
                            sequence: 3,
                            text: "Duplicate server across batch",
                            serverTime: 3
                        ),
                        IncomingSyncMessage(
                            messageID: "sync_cross_duplicate_sequence",
                            conversationID: "sync_cross_duplicate_conversation",
                            senderID: "sync_sender",
                            clientMessageID: "sync_cross_client_4",
                            serverMessageID: "sync_cross_server_4",
                            sequence: 1,
                            text: "Duplicate sequence across batch",
                            serverTime: 4
                        ),
                        IncomingSyncMessage(
                            messageID: "sync_cross_unique_5",
                            conversationID: "sync_cross_duplicate_conversation",
                            senderID: "sync_sender",
                            clientMessageID: "sync_cross_client_5",
                            serverMessageID: "sync_cross_server_5",
                            sequence: 5,
                            text: "Unique second batch",
                            serverTime: 5
                        )
                    ],
                    nextCursor: "cursor_5",
                    nextSequence: 5
                )
            ]
        )
        let engine = SyncEngineActor(
            userID: "sync_cross_duplicate_user",
            store: repository,
            deltaService: deltaService
        )

        let result = try await engine.syncUntilCaughtUp(maxBatches: 3)
        let messages = try await repository.listMessages(conversationID: "sync_cross_duplicate_conversation", limit: 20, beforeSortSeq: nil)

        #expect(result.batchCount == 2)
        #expect(result.fetchedCount == 5)
        #expect(result.insertedCount == 2)
        #expect(result.skippedDuplicateCount == 3)
        #expect(try messages.map { try requireTextContent($0) } == ["Unique second batch", "Unique first batch"])
    }

    @Test func syncEngineStopsWhenHasMoreExceedsMaxBatches() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "sync_limit_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "sync_limit_conversation", userID: "sync_limit_user", title: "Limit", sortTimestamp: 1)
        )

        let batch = SyncBatch(
            messages: [
                IncomingSyncMessage(
                    messageID: "sync_limit_message",
                    conversationID: "sync_limit_conversation",
                    senderID: "sync_sender",
                    clientMessageID: "sync_limit_client",
                    serverMessageID: "sync_limit_server",
                    sequence: 1,
                    text: "Still has more",
                    serverTime: 1
                )
            ],
            nextCursor: "cursor_limit",
            nextSequence: 1,
            hasMore: true
        )
        let engine = SyncEngineActor(
            userID: "sync_limit_user",
            store: repository,
            deltaService: StaticSyncDeltaService(batch: batch)
        )

        var caughtError: SyncEngineError?
        do {
            _ = try await engine.syncUntilCaughtUp(maxBatches: 2)
        } catch let error as SyncEngineError {
            caughtError = error
        }

        let messages = try await repository.listMessages(conversationID: "sync_limit_conversation", limit: 20, beforeSortSeq: nil)
        let checkpoint = try await repository.syncCheckpoint(for: SyncEngineActor.messageBizKey)

        #expect(caughtError == .exceededMaxBatches(2))
        #expect(try messages.map { try requireTextContent($0) } == ["Still has more"])
        #expect(checkpoint?.cursor == "cursor_limit")
    }
}
