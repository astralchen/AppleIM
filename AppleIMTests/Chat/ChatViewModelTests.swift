import Testing
import Foundation
import UIKit

@testable import AppleIM

extension AppleIMTests {
    @MainActor
    @Test func chatViewModelLoadsMessagesAfterConversationListSimulatedPush() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "push_enter_view_model_user",
            storageService: storageService,
            database: DatabaseActor(),
            shouldSeedDemoData: false
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "push_enter_view_model_conversation",
                userID: "push_enter_view_model_user",
                title: "Push Enter View Model",
                sortTimestamp: 100
            )
        )
        let pushService = SimulatedIncomingPushService(userID: "push_enter_view_model_user", storeProvider: storeProvider)
        let pushResult = try #require(try await pushService.simulateIncomingPush(
            SimulatedIncomingPushRequest(target: .conversation("push_enter_view_model_conversation"), messageCount: 2)
        ))
        let useCase = StoreBackedChatUseCase(
            userID: "push_enter_view_model_user",
            conversationID: pushResult.conversationID,
            storeProvider: storeProvider,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: AccountMediaFileStore(accountID: "push_enter_view_model_user", storageService: storageService)
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Push Enter View Model")

        viewModel.load()

        try await waitForCondition {
            viewModel.currentState.rows.map(\.id) == pushResult.messages.map(\.messageID)
        }
        #expect(viewModel.currentState.phase == .loaded)
    }

    @MainActor
    @Test func chatViewModelCancelStopsPendingLoadUpdate() async throws {
        let viewModel = ChatViewModel(useCase: SlowChatUseCase(), title: "Cancel")

        viewModel.load()
        viewModel.cancel()
        try await Task.sleep(nanoseconds: 30_000_000)

        #expect(viewModel.currentState.phase == .loading)
        #expect(viewModel.currentState.rows.isEmpty)
    }

    @MainActor
    @Test func chatViewModelAppendsSimulatedIncomingMessagesWithoutClearingDraft() async throws {
        let useCase = SimulatedIncomingStubChatUseCase()
        let viewModel = ChatViewModel(useCase: useCase, title: "Simulated")

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.phase == .loaded
            }
        }
        viewModel.composerTextChanged("draft text")
        viewModel.simulateIncomingMessage()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 2
            }
        }

        #expect(viewModel.currentState.draftText == "draft text")
        #expect(viewModel.currentState.rows.count == 2)
        #expect(viewModel.currentState.rows.allSatisfy { $0.isOutgoing == false })
        #expect(viewModel.currentState.rows.map(rowText) == ["模拟收到第 1 条后台推送", "模拟收到第 2 条后台推送"])
        #expect(useCase.simulateIncomingCallCount == 1)
    }

    @MainActor
    @Test func chatViewModelLeavesRowsUnchangedWhenSimulatedPushMissesCurrentConversation() async throws {
        let useCase = MissedSimulatedIncomingStubChatUseCase()
        let viewModel = ChatViewModel(useCase: useCase, title: "Missed Simulated")

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.phase == .loaded
            }
        }

        viewModel.simulateIncomingMessage()
        try await waitForCondition {
            useCase.simulateIncomingCallCount == 1
        }

        #expect(viewModel.currentState.rows.isEmpty)
    }

    @MainActor
    @Test func chatViewModelQueuesRapidSimulatedIncomingTaps() async throws {
        let useCase = DelayedSimulatedIncomingStubChatUseCase()
        let viewModel = ChatViewModel(useCase: useCase, title: "Rapid Simulated")

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.phase == .loaded
            }
        }

        viewModel.simulateIncomingMessage()
        viewModel.simulateIncomingMessage()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 2
            }
        }

        #expect(viewModel.currentState.rows.map(rowText) == ["模拟收到第 1 条消息", "模拟收到第 2 条消息"])
        #expect(useCase.simulateIncomingCallCount == 2)
    }

    @MainActor
    @Test func chatViewModelRefreshesVisibleMessagesForCurrentConversationStoreChange() async throws {
        let useCase = StoreRefreshingChatUseCase()
        let viewModel = ChatViewModel(useCase: useCase, title: "Store Refresh")

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.phase == .loaded
            }
        }
        #expect(viewModel.currentState.rows.isEmpty)

        useCase.replaceRows([
            makeChatRow(id: "store_refresh_message", text: "Store refreshed message", sortSequence: 10)
        ])
        viewModel.refreshAfterStoreChange(
            userID: "store_refresh_user",
            conversationIDs: ["store_refresh_conversation"]
        )
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.map(\.id) == ["store_refresh_message"]
            }
        }

        #expect(useCase.loadInitialMessagesCallCount == 2)
        #expect(viewModel.currentState.rows.map(rowText) == ["Store refreshed message"])
    }

    @MainActor
    @Test func chatViewModelIgnoresOtherConversationStoreChange() async throws {
        let useCase = StoreRefreshingChatUseCase()
        let viewModel = ChatViewModel(useCase: useCase, title: "Store Refresh")

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.phase == .loaded
            }
        }
        useCase.replaceRows([
            makeChatRow(id: "ignored_store_refresh_message", text: "Ignored store refresh", sortSequence: 10)
        ])

        viewModel.refreshAfterStoreChange(
            userID: "store_refresh_user",
            conversationIDs: ["other_conversation"]
        )
        try await Task.sleep(nanoseconds: 40_000_000)

        #expect(useCase.loadInitialMessagesCallCount == 1)
        #expect(viewModel.currentState.rows.isEmpty)
    }

    @MainActor
    @Test func chatViewModelKeepsConcurrentTextSendsAlive() async throws {
        let useCase = DelayedTextSendingStubChatUseCase()
        let viewModel = ChatViewModel(useCase: useCase, title: "Concurrent Sends")

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.phase == .loaded
            }
        }

        viewModel.sendText("First")
        viewModel.sendText("Second")
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 2
            }
        }

        #expect(viewModel.currentState.rows.map(rowText) == ["First", "Second"])
        #expect(useCase.sentTexts == ["First", "Second"])
    }

    @MainActor
    @Test func chatViewModelPrependsOlderMessagesWithoutDuplicates() async throws {
        let useCase = PagingStubChatUseCase(
            initialPage: ChatMessagePage(
                rows: [
                    makeChatRow(id: "message_51", text: "51", sortSequence: 51),
                    makeChatRow(id: "message_52", text: "52", sortSequence: 52)
                ],
                hasMore: true,
                nextBeforeSortSequence: 51
            ),
            olderPage: ChatMessagePage(
                rows: [
                    makeChatRow(id: "message_49", text: "49", sortSequence: 49),
                    makeChatRow(id: "message_50", text: "50", sortSequence: 50),
                    makeChatRow(id: "message_51", text: "51", sortSequence: 51)
                ],
                hasMore: false,
                nextBeforeSortSequence: 49
            )
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Paging")

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 2
            }
        }
        viewModel.loadOlderMessagesIfNeeded()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 4
            }
        }

        #expect(viewModel.currentState.rows.map(\.id.rawValue) == ["message_49", "message_50", "message_51", "message_52"])
        #expect(viewModel.currentState.hasMoreOlderMessages == false)
        #expect(viewModel.currentState.isLoadingOlderMessages == false)
        #expect(useCase.loadOlderCallCount == 1)
    }

    @MainActor
    @Test func chatViewModelAppliesWeChatStyleTimeSeparatorsOnInitialLoad() async throws {
        let useCase = PagingStubChatUseCase(
            initialPage: ChatMessagePage(
                rows: [
                    makeChatRow(id: "time_first", text: "First", sortSequence: 1, sentAt: 100),
                    makeChatRow(id: "time_close", text: "Close", sortSequence: 2, sentAt: 220),
                    makeChatRow(id: "time_gap", text: "Gap", sortSequence: 3, sentAt: 520)
                ],
                hasMore: false,
                nextBeforeSortSequence: 1
            ),
            olderPage: ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Times")

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 3
            }
        }

        #expect(viewModel.currentState.rows.map(\.showsTimeSeparator) == [true, false, true])
    }

    @Test func chatBridgeTimeFormatterUsesWeChatStyleMessageText() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        calendar.firstWeekday = 2
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 15, minute: 30)))
        let todayMorning = try timestamp(year: 2026, month: 5, day: 13, hour: 9, minute: 5, calendar: calendar)
        let yesterdayNight = try timestamp(year: 2026, month: 5, day: 12, hour: 23, minute: 10, calendar: calendar)
        let mondayMorning = try timestamp(year: 2026, month: 5, day: 11, hour: 8, minute: 0, calendar: calendar)
        let currentYearEarlier = try timestamp(year: 2026, month: 5, day: 1, hour: 21, minute: 2, calendar: calendar)
        let previousYear = try timestamp(year: 2025, month: 12, day: 31, hour: 23, minute: 59, calendar: calendar)

        #expect(
            ChatBridgeTimeFormatter.messageTimeText(
                from: todayMorning,
                now: now,
                calendar: calendar
            ) == "09:05"
        )
        #expect(
            ChatBridgeTimeFormatter.messageTimeText(
                from: yesterdayNight,
                now: now,
                calendar: calendar
            ) == "昨天 23:10"
        )
        #expect(
            ChatBridgeTimeFormatter.messageTimeText(
                from: mondayMorning,
                now: now,
                calendar: calendar
            ) == "星期一 08:00"
        )
        #expect(
            ChatBridgeTimeFormatter.messageTimeText(
                from: currentYearEarlier,
                now: now,
                calendar: calendar
            ) == "5月1日 21:02"
        )
        #expect(
            ChatBridgeTimeFormatter.messageTimeText(
                from: previousYear,
                now: now,
                calendar: calendar
            ) == "2025年12月31日 23:59"
        )
        #expect(ChatBridgeTimeFormatter.messageTimeText(from: 0, now: now, calendar: calendar) == "")
    }

    @MainActor
    @Test func chatViewModelShowsTimeSeparatorWhenMessagesCrossCalendarDay() async throws {
        let calendar = Calendar.current
        let beforeMidnight = try #require(
            calendar.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 23, minute: 59))
        )
        let afterMidnight = try #require(
            calendar.date(from: DateComponents(year: 2024, month: 1, day: 2, hour: 0, minute: 1))
        )
        let useCase = PagingStubChatUseCase(
            initialPage: ChatMessagePage(
                rows: [
                    makeChatRow(
                        id: "day_first",
                        text: "Before midnight",
                        sortSequence: 1,
                        sentAt: Int64(beforeMidnight.timeIntervalSince1970)
                    ),
                    makeChatRow(
                        id: "day_next",
                        text: "After midnight",
                        sortSequence: 2,
                        sentAt: Int64(afterMidnight.timeIntervalSince1970)
                    )
                ],
                hasMore: false,
                nextBeforeSortSequence: 1
            ),
            olderPage: ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Days")

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 2
            }
        }

        #expect(viewModel.currentState.rows.map(\.showsTimeSeparator) == [true, true])
    }

    @MainActor
    @Test func chatViewModelRecalculatesTimeSeparatorsAfterPrependingOlderMessages() async throws {
        let useCase = PagingStubChatUseCase(
            initialPage: ChatMessagePage(
                rows: [
                    makeChatRow(id: "current_message", text: "Current", sortSequence: 3, sentAt: 1_000)
                ],
                hasMore: true,
                nextBeforeSortSequence: 3
            ),
            olderPage: ChatMessagePage(
                rows: [
                    makeChatRow(id: "older_first", text: "Older first", sortSequence: 1, sentAt: 600),
                    makeChatRow(id: "older_close", text: "Older close", sortSequence: 2, sentAt: 760)
                ],
                hasMore: false,
                nextBeforeSortSequence: 1
            )
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Paging Times")

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.map(\.id.rawValue) == ["current_message"]
            }
        }
        viewModel.loadOlderMessagesIfNeeded()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 3
            }
        }

        #expect(viewModel.currentState.rows.map(\.id.rawValue) == ["older_first", "older_close", "current_message"])
        #expect(viewModel.currentState.rows.map(\.showsTimeSeparator) == [true, false, false])
    }

    @MainActor
    @Test func chatViewModelDoesNotRequestOlderMessagesWhenPageIsExhausted() async throws {
        let useCase = PagingStubChatUseCase(
            initialPage: ChatMessagePage(
                rows: [makeChatRow(id: "only_message", text: "Only", sortSequence: 1)],
                hasMore: false,
                nextBeforeSortSequence: 1
            ),
            olderPage: ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "No More")

        viewModel.load()
        try await Task.sleep(nanoseconds: 10_000_000)
        viewModel.loadOlderMessagesIfNeeded()
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(viewModel.currentState.rows.map(\.id.rawValue) == ["only_message"])
        #expect(useCase.loadOlderCallCount == 0)
    }

    @MainActor
    @Test func chatViewModelLoadsGroupAnnouncementAndMentionOptions() async throws {
        let useCase = GroupContextStubChatUseCase(
            context: GroupChatContext(
                members: [
                    GroupMember(conversationID: "group_vm", memberID: "current_user", displayName: "Me", role: .admin, joinTime: 1),
                    GroupMember(conversationID: "group_vm", memberID: "sondra", displayName: "Sondra", role: .member, joinTime: 2)
                ],
                currentUserRole: .admin,
                announcement: GroupAnnouncement(
                    conversationID: "group_vm",
                    text: "今天完成群聊 P1",
                    updatedBy: "current_user",
                    updatedAt: 10
                )
            )
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Group")

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.phase == .loaded
            }
        }
        viewModel.composerTextChanged("@")

        #expect(viewModel.currentState.groupAnnouncement?.text == "今天完成群聊 P1")
        #expect(viewModel.currentState.groupAnnouncement?.canEdit == true)
        #expect(viewModel.currentState.mentionPicker?.options.map(\.displayName) == ["所有人", "Sondra"])
    }

    @MainActor
    @Test func chatViewModelSendsSelectedMentionMetadata() async throws {
        let useCase = GroupContextStubChatUseCase(
            context: GroupChatContext(
                members: [
                    GroupMember(conversationID: "group_vm", memberID: "current_user", displayName: "Me", role: .admin, joinTime: 1),
                    GroupMember(conversationID: "group_vm", memberID: "sondra", displayName: "Sondra", role: .member, joinTime: 2)
                ],
                currentUserRole: .admin,
                announcement: nil
            )
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Group")

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.phase == .loaded
            }
        }
        viewModel.composerTextChanged("@")
        viewModel.selectMention(userID: "sondra")
        viewModel.sendText("@Sondra 请看这里")
        try await waitForCondition {
            useCase.sentMentionedUserIDs == ["sondra"]
        }

        #expect(useCase.sentText == "@Sondra 请看这里")
        #expect(useCase.sentMentionsAll == false)
    }

    @MainActor
    @Test func chatViewModelRecalculatesTimeSeparatorsWhenAppendingSentMessage() async throws {
        let useCase = TextSendingTimeStubChatUseCase(
            initialRows: [
                makeChatRow(id: "existing_message", text: "Existing", sortSequence: 1, sentAt: 1_000)
            ],
            sentRows: [
                makeChatRow(id: "sent_close", text: "Close", sortSequence: 2, sentAt: 1_120),
                makeChatRow(id: "sent_gap", text: "Gap", sortSequence: 3, sentAt: 1_420)
            ]
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Append Times")

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 1
            }
        }
        viewModel.sendText("Close")
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 2
            }
        }
        viewModel.sendText("Gap")
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 3
            }
        }

        #expect(viewModel.currentState.rows.map(\.showsTimeSeparator) == [true, false, true])
    }

    @MainActor
    @Test func chatViewModelPaginationFailureKeepsCurrentRows() async throws {
        let useCase = PagingStubChatUseCase(
            initialPage: ChatMessagePage(
                rows: [makeChatRow(id: "current_message", text: "Current", sortSequence: 10)],
                hasMore: true,
                nextBeforeSortSequence: 10
            ),
            olderPage: ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil),
            olderError: TestChatError.paginationFailed
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Failure")

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.map(\.id.rawValue) == ["current_message"]
            }
        }
        viewModel.loadOlderMessagesIfNeeded()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.paginationErrorMessage == "Unable to load older messages"
            }
        }

        #expect(viewModel.currentState.rows.map(\.id.rawValue) == ["current_message"])
        #expect(viewModel.currentState.phase == .loaded)
        #expect(viewModel.currentState.isLoadingOlderMessages == false)
        #expect(viewModel.currentState.paginationErrorMessage == "Unable to load older messages")
    }

    @MainActor
    @Test func chatViewModelCanLoadOlderMessagesAfterPaginationFailure() async throws {
        let useCase = RecoveringPagingStubChatUseCase(
            initialPage: ChatMessagePage(
                rows: [makeChatRow(id: "current_message", text: "Current", sortSequence: 10)],
                hasMore: true,
                nextBeforeSortSequence: 10
            ),
            recoveredPage: ChatMessagePage(
                rows: [makeChatRow(id: "older_message", text: "Older", sortSequence: 9)],
                hasMore: false,
                nextBeforeSortSequence: 9
            )
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Recover")

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.map(\.id.rawValue) == ["current_message"]
            }
        }
        viewModel.loadOlderMessagesIfNeeded()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.paginationErrorMessage == "Unable to load older messages"
            }
        }
        viewModel.loadOlderMessagesIfNeeded()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.map(\.id.rawValue) == ["older_message", "current_message"]
            }
        }

        #expect(viewModel.currentState.paginationErrorMessage == nil)
        #expect(viewModel.currentState.hasMoreOlderMessages == false)
        #expect(useCase.loadOlderCallCount == 2)
    }

    @MainActor
    @Test func chatViewModelDeleteRemovesMessageRow() async throws {
        let useCase = MessageActionStubChatUseCase(
            initialRows: [
                makeChatRow(id: "delete_keep", text: "Keep", sortSequence: 1),
                makeChatRow(id: "delete_remove", text: "Remove", sortSequence: 2)
            ]
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Delete")

        viewModel.load()
        try await waitForCondition(timeoutNanoseconds: 15_000_000_000) {
            await MainActor.run {
                viewModel.currentState.rows.count == 2
            }
        }
        viewModel.delete(messageID: "delete_remove")
        try await waitForCondition(timeoutNanoseconds: 15_000_000_000) {
            await MainActor.run {
                viewModel.currentState.rows.map(\.id.rawValue) == ["delete_keep"]
            }
        }

        #expect(useCase.deletedMessageIDs == ["delete_remove"])
        #expect(viewModel.currentState.phase == .loaded)
    }

    @MainActor
    @Test func chatViewModelRecalculatesFirstTimeSeparatorAfterDeletingMessage() async throws {
        let useCase = MessageActionStubChatUseCase(
            initialRows: [
                makeChatRow(id: "delete_time_first", text: "First", sortSequence: 1, sentAt: 100),
                makeChatRow(id: "delete_time_second", text: "Second", sortSequence: 2, sentAt: 160)
            ]
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Delete Times")

        viewModel.load()
        try await waitForCondition(timeoutNanoseconds: 15_000_000_000) {
            await MainActor.run {
                viewModel.currentState.rows.map(\.showsTimeSeparator) == [true, false]
            }
        }
        viewModel.delete(messageID: "delete_time_first")
        try await waitForCondition(timeoutNanoseconds: 15_000_000_000) {
            await MainActor.run {
                viewModel.currentState.rows.map(\.id.rawValue) == ["delete_time_second"]
            }
        }

        #expect(viewModel.currentState.rows.map(\.showsTimeSeparator) == [true])
    }

    @MainActor
    @Test func chatViewModelRevokeReloadsRevokedMessageRow() async throws {
        let useCase = MessageActionStubChatUseCase(
            initialRows: [
                makeChatRow(id: "revoke_message", text: "Secret", sortSequence: 1)
            ],
            revokedRows: [
                makeRevokedChatRow(id: "revoke_message", text: "你撤回了一条消息", sortSequence: 1)
            ]
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Revoke")

        viewModel.load()
        try await waitForCondition(timeoutNanoseconds: 15_000_000_000) {
            await MainActor.run {
                viewModel.currentState.rows.first?.content == .text("Secret")
            }
        }
        viewModel.revoke(messageID: "revoke_message")
        try await waitForCondition(timeoutNanoseconds: 15_000_000_000) {
            await MainActor.run {
                viewModel.currentState.rows.first?.content == .revoked("你撤回了一条消息")
            }
        }

        #expect(useCase.revokedMessageIDs == ["revoke_message"])
        #expect(viewModel.currentState.phase == .loaded)
    }

    @MainActor
    @Test func chatViewModelDeleteFailureKeepsRowsAndReportsFailure() async throws {
        let useCase = MessageActionStubChatUseCase(
            initialRows: [
                makeChatRow(id: "delete_failure_message", text: "Still here", sortSequence: 1)
            ],
            deleteError: TestChatError.messageActionFailed
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Delete Failure")

        viewModel.load()
        try await waitForCondition(timeoutNanoseconds: 15_000_000_000) {
            await MainActor.run {
                viewModel.currentState.rows.map(\.id.rawValue) == ["delete_failure_message"]
            }
        }
        viewModel.delete(messageID: "delete_failure_message")
        try await waitForCondition(timeoutNanoseconds: 15_000_000_000) {
            await MainActor.run {
                viewModel.currentState.phase == .failed("Unable to delete message")
            }
        }

        #expect(viewModel.currentState.rows.map(\.id.rawValue) == ["delete_failure_message"])
    }

    @MainActor
    @Test func chatViewModelRevokeFailureKeepsRowsAndReportsFailure() async throws {
        let useCase = MessageActionStubChatUseCase(
            initialRows: [
                makeChatRow(id: "revoke_failure_message", text: "Still secret", sortSequence: 1)
            ],
            revokeError: TestChatError.messageActionFailed
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Revoke Failure")

        viewModel.load()
        try await waitForCondition(timeoutNanoseconds: 15_000_000_000) {
            await MainActor.run {
                viewModel.currentState.rows.first?.content == .text("Still secret")
            }
        }
        viewModel.revoke(messageID: "revoke_failure_message")
        try await waitForCondition(timeoutNanoseconds: 15_000_000_000) {
            await MainActor.run {
                viewModel.currentState.phase == .failed("Unable to revoke message")
            }
        }

        #expect(viewModel.currentState.rows.first?.content == .text("Still secret"))
    }

    @MainActor
    @Test func chatViewModelAppendsImageRowAfterSendingImage() async throws {
        let useCase = ImageSendingStubChatUseCase()
        let viewModel = ChatViewModel(useCase: useCase, title: "Images")

        viewModel.sendImage(data: samplePNGData(), preferredFileExtension: "png")
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 1
            }
        }

        #expect(viewModel.currentState.rows.count == 1)
        #expect(viewModel.currentState.rows.first.flatMap(imageThumbnailPath) == "/tmp/chat-thumb.jpg")
        #expect(viewModel.currentState.rows.first.map(isImageContent) == true)
        #expect(useCase.sentImageCount == 1)
    }

    @MainActor
    @Test func chatViewModelSendsComposerImageThenText() async throws {
        let useCase = ComposerSendingStubChatUseCase()
        let viewModel = ChatViewModel(useCase: useCase, title: "Composer")

        viewModel.sendComposer(
            media: .image(data: samplePNGData(), preferredFileExtension: "png"),
            text: "Hello after image"
        )
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 2
            }
        }

        #expect(useCase.events == ["image:png", "text:Hello after image"])
        #expect(viewModel.currentState.rows.map(\.id.rawValue) == ["composer_image", "composer_text"])
    }

    @MainActor
    @Test func chatViewModelSendsComposerVideoOnly() async throws {
        let useCase = ComposerSendingStubChatUseCase()
        let viewModel = ChatViewModel(useCase: useCase, title: "Composer")
        let videoURL = temporaryDirectory().appendingPathComponent("composer.mov")

        viewModel.sendComposer(media: .video(fileURL: videoURL, preferredFileExtension: "mov"), text: "   ")
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 1
            }
        }

        #expect(useCase.events == ["video:mov"])
        #expect(viewModel.currentState.rows.first.map(isVideoContent) == true)
    }

    @MainActor
    @Test func chatViewModelSendsComposerMediaInSelectionOrderThenText() async throws {
        let useCase = ComposerSendingStubChatUseCase()
        let viewModel = ChatViewModel(useCase: useCase, title: "Composer")
        let videoURL = temporaryDirectory().appendingPathComponent("composer.mov")

        viewModel.sendComposer(
            media: [
                .image(data: samplePNGData(), preferredFileExtension: "png"),
                .video(fileURL: videoURL, preferredFileExtension: "mov"),
                .image(data: samplePNGData(), preferredFileExtension: "heic")
            ],
            text: "Media batch"
        )

        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            useCase.events == ["image:png", "video:mov", "image:heic", "text:Media batch"]
        }
    }

    @MainActor
    @Test func chatViewModelTracksOnlyActiveVoicePlaybackRow() async throws {
        let voiceA = makeVoiceRow(id: "voice_a", sortSequence: 1, isUnplayed: true)
        let voiceB = makeVoiceRow(id: "voice_b", sortSequence: 2, isUnplayed: true)
        let useCase = VoicePlaybackStubChatUseCase(rows: [voiceA, voiceB])
        let viewModel = ChatViewModel(useCase: useCase, title: "Voice")

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 2
            }
        }
        viewModel.voicePlaybackStarted(messageID: "voice_a")
        try await waitForCondition {
            await MainActor.run {
                useCase.markedMessageIDs == ["voice_a"]
                    && viewModel.currentState.rows.first { $0.id == "voice_a" }.map(isPlayingVoiceContent) == true
            }
        }

        let rowsAfterStart = viewModel.currentState.rows
        #expect(rowsAfterStart.first { $0.id == "voice_a" }.map(isPlayingVoiceContent) == true)
        #expect(rowsAfterStart.first { $0.id == "voice_a" }.map(isUnplayedVoiceContent) == false)
        #expect(rowsAfterStart.first { $0.id == "voice_b" }.map(isPlayingVoiceContent) == false)
        #expect(rowsAfterStart.first { $0.id == "voice_b" }.map(isUnplayedVoiceContent) == true)
        #expect(useCase.markedMessageIDs == ["voice_a"])

        viewModel.voicePlaybackStopped(messageID: "voice_a")
        #expect(viewModel.currentState.rows.first { $0.id == "voice_a" }.map(isPlayingVoiceContent) == false)
    }

    @MainActor
    @Test func chatViewModelUpdatesOnlyActiveVoicePlaybackProgress() async throws {
        let voiceA = makeVoiceRow(id: "voice_a", sortSequence: 1, isUnplayed: true)
        let voiceB = makeVoiceRow(id: "voice_b", sortSequence: 2, isUnplayed: true)
        let useCase = VoicePlaybackStubChatUseCase(rows: [voiceA, voiceB])
        let viewModel = ChatViewModel(useCase: useCase, title: "Voice")

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 2
            }
        }
        viewModel.voicePlaybackStarted(messageID: "voice_a")
        viewModel.voicePlaybackProgress(
            messageID: "voice_a",
            progress: VoicePlaybackProgress(
                elapsedMilliseconds: 1_000,
                durationMilliseconds: 2_000,
                fraction: 0.5
            )
        )

        let rowsAfterProgress = viewModel.currentState.rows
        let playingVoice = try #require(rowsAfterProgress.first { $0.id == "voice_a" }?.voiceContent)
        let idleVoice = try #require(rowsAfterProgress.first { $0.id == "voice_b" }?.voiceContent)
        #expect(playingVoice.isPlaying)
        #expect(playingVoice.playbackElapsedMilliseconds == 1_000)
        #expect(playingVoice.playbackProgress == 0.5)
        #expect(idleVoice.isPlaying == false)
        #expect(idleVoice.playbackElapsedMilliseconds == 0)
        #expect(idleVoice.playbackProgress == 0)

        viewModel.voicePlaybackStopped(messageID: "voice_a")

        let stoppedVoice = try #require(viewModel.currentState.rows.first { $0.id == "voice_a" }?.voiceContent)
        #expect(stoppedVoice.isPlaying == false)
        #expect(stoppedVoice.playbackElapsedMilliseconds == 0)
        #expect(stoppedVoice.playbackProgress == 0)
    }

    @MainActor
    @Test func chatViewModelPreservesActiveVoicePlaybackAcrossStoreRefresh() async throws {
        let voice = makeVoiceRow(id: "voice_refresh", sortSequence: 1, isUnplayed: true)
        let useCase = StoreRefreshingChatUseCase()
        useCase.replaceRows([voice])
        let viewModel = ChatViewModel(useCase: useCase, title: "Voice Refresh")

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 1
            }
        }

        viewModel.voicePlaybackStarted(messageID: "voice_refresh")
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.first?.voiceContent?.isPlaying == true
            }
        }

        useCase.replaceRows([voice.withVoicePlayback(isPlaying: false, isUnplayed: false)])
        viewModel.refreshAfterStoreChange(
            userID: "store_refresh_user",
            conversationIDs: ["store_refresh_conversation"]
        )
        try await waitForCondition {
            useCase.loadInitialMessagesCallCount == 2
        }

        let refreshedVoice = try #require(viewModel.currentState.rows.first?.voiceContent)
        #expect(refreshedVoice.isPlaying)
        #expect(refreshedVoice.isUnplayed == false)
    }

    @MainActor
    @Test func chatViewModelThrottlesVoicePlaybackProgressUpdates() async throws {
        var currentUptime: TimeInterval = 0
        let voice = makeVoiceRow(id: "voice_throttle", sortSequence: 1, isUnplayed: true)
        let useCase = VoicePlaybackStubChatUseCase(rows: [voice])
        let viewModel = ChatViewModel(
            useCase: useCase,
            title: "Voice Throttle",
            currentUptime: { currentUptime }
        )

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 1
            }
        }
        viewModel.voicePlaybackStarted(messageID: "voice_throttle")

        viewModel.voicePlaybackProgress(
            messageID: "voice_throttle",
            progress: VoicePlaybackProgress(elapsedMilliseconds: 100, durationMilliseconds: 1_000, fraction: 0.1)
        )
        var playingVoice = try #require(viewModel.currentState.rows.first?.voiceContent)
        #expect(playingVoice.playbackElapsedMilliseconds == 100)
        #expect(playingVoice.playbackProgress == 0.1)

        currentUptime = 0.10
        viewModel.voicePlaybackProgress(
            messageID: "voice_throttle",
            progress: VoicePlaybackProgress(elapsedMilliseconds: 200, durationMilliseconds: 1_000, fraction: 0.2)
        )
        playingVoice = try #require(viewModel.currentState.rows.first?.voiceContent)
        #expect(playingVoice.playbackElapsedMilliseconds == 100)
        #expect(playingVoice.playbackProgress == 0.1)

        currentUptime = 0.26
        viewModel.voicePlaybackProgress(
            messageID: "voice_throttle",
            progress: VoicePlaybackProgress(elapsedMilliseconds: 300, durationMilliseconds: 1_000, fraction: 0.3)
        )
        playingVoice = try #require(viewModel.currentState.rows.first?.voiceContent)
        #expect(playingVoice.playbackElapsedMilliseconds == 300)
        #expect(playingVoice.playbackProgress == 0.3)
    }

    @MainActor
    @Test func chatViewModelIgnoresVoiceProgressAfterPlaybackStops() async throws {
        let voice = makeVoiceRow(id: "voice_stop", sortSequence: 1, isUnplayed: true)
        let useCase = VoicePlaybackStubChatUseCase(rows: [voice])
        let viewModel = ChatViewModel(useCase: useCase, title: "Voice Stop")

        viewModel.load()
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 1
            }
        }
        viewModel.voicePlaybackStarted(messageID: "voice_stop")
        viewModel.voicePlaybackStopped(messageID: "voice_stop")
        viewModel.voicePlaybackProgress(
            messageID: "voice_stop",
            progress: VoicePlaybackProgress(elapsedMilliseconds: 500, durationMilliseconds: 1_000, fraction: 0.5)
        )

        let stoppedVoice = try #require(viewModel.currentState.rows.first?.voiceContent)
        #expect(stoppedVoice.isPlaying == false)
        #expect(stoppedVoice.playbackElapsedMilliseconds == 0)
        #expect(stoppedVoice.playbackProgress == 0)
    }

    @MainActor
    @Test func chatViewControllerDisablesSnapshotAnimationForOnlyVoicePlaybackChanges() {
        let idleVoice = makeVoiceRow(id: "voice_animation", sortSequence: 1, isUnplayed: true)
        let playingVoice = idleVoice.withVoicePlaybackProgress(
            VoicePlaybackProgress(elapsedMilliseconds: 250, durationMilliseconds: 1_000, fraction: 0.25)
        )

        #expect(ChatViewController.containsOnlyVoicePlaybackChanges(previousRows: [idleVoice], newRows: [playingVoice]))
        #expect(ChatViewController.containsOnlyVoicePlaybackChanges(previousRows: [idleVoice], newRows: [
            playingVoice.copy(statusText: "Delivered")
        ]) == false)
    }

    @MainActor
    @Test func chatViewModelShowsOutgoingVoiceRowImmediatelyWhenSendStarts() async throws {
        let row = ChatMessageRowState(
            id: "sent_voice",
            content: .voice(
                ChatMessageRowContent.VoiceContent(
                    localPath: "/tmp/sent_voice.m4a",
                    durationMilliseconds: 4_200,
                    isUnplayed: false,
                    isPlaying: false
                )
            ),
            sortSequence: 1,
            timeText: "Now",
            statusText: "Sending",
            uploadProgress: nil,
            isOutgoing: true,
            canRetry: false,
            canDelete: true,
            canRevoke: false
        )
        let useCase = ImmediateVoiceSendStubChatUseCase(row: row)
        let viewModel = ChatViewModel(useCase: useCase, title: "Voice")
        let recording = VoiceRecordingFile(fileURL: URL(fileURLWithPath: "/tmp/sent_voice_recording.m4a"), durationMilliseconds: 4_200)

        viewModel.sendVoice(recording: recording)

        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.contains { $0.id == "sent_voice" }
            }
        }
        let insertedRow = try #require(viewModel.currentState.rows.first { $0.id == "sent_voice" })
        #expect(insertedRow.isOutgoing)
        #expect(insertedRow.statusText == "Sending")
        #expect(insertedRow.voiceContent?.durationMilliseconds == 4_200)
    }
}
