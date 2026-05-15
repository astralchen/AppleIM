import Testing
import Combine
import Foundation
import UIKit

@testable import AppleIM

extension AppleIMTests {
    @MainActor
    @Test func conversationListViewModelLoadsRows() async throws {
        let viewModel = ConversationListViewModel(useCase: StubConversationListUseCase())

        viewModel.load()
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(viewModel.currentState.phase == .loaded)
        #expect(viewModel.currentState.rows.count == 1)
        #expect(viewModel.currentState.rows.first?.title == "Test Conversation")
    }

    @MainActor
    @Test func conversationListViewModelLoadsNextPageNearBottom() async throws {
        let viewModel = ConversationListViewModel(useCase: PagedConversationListUseCase(), pageSize: 2)

        viewModel.load()
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(viewModel.currentState.rows.map(\.id.rawValue) == ["paged_0", "paged_1"])
        #expect(viewModel.currentState.hasMoreRows)

        viewModel.loadNextPageIfNeeded(visibleRowID: "paged_1")
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(viewModel.currentState.rows.map(\.id.rawValue) == ["paged_0", "paged_1", "paged_2"])
        #expect(viewModel.currentState.hasMoreRows == false)
    }

    @MainActor
    @Test func conversationListViewModelContinuesAfterCursorWhenNewConversationMovesAhead() async throws {
        let viewModel = ConversationListViewModel(useCase: CursorShiftConversationListUseCase(), pageSize: 2)

        viewModel.load()
        try await waitForCondition {
            viewModel.currentState.rows.map(\.id.rawValue) == ["shift_3", "shift_2"]
        }

        viewModel.loadNextPageIfNeeded(visibleRowID: "shift_2")
        try await waitForCondition {
            viewModel.currentState.rows.count == 3
        }

        #expect(viewModel.currentState.rows.map(\.id.rawValue) == ["shift_3", "shift_2", "shift_1"])
        #expect(viewModel.currentState.hasMoreRows == false)
    }

    @MainActor
    @Test func conversationListViewModelRefreshesAfterPinAndMuteChanges() async throws {
        let useCase = MutableConversationListUseCase()
        let viewModel = ConversationListViewModel(useCase: useCase)

        viewModel.load()
        try await waitForCondition {
            viewModel.currentState.phase == .loaded
        }

        viewModel.setPinned(conversationID: "mutable_conversation", isPinned: true)
        try await waitForCondition {
            viewModel.currentState.rows.first?.isPinned == true
        }

        viewModel.setMuted(conversationID: "mutable_conversation", isMuted: true)
        try await waitForCondition {
            viewModel.currentState.rows.first?.isMuted == true
        }
    }

    @MainActor
    @Test func conversationListViewModelClearsUnreadStateForOpenedConversation() {
        let row = ConversationListRowState(
            id: "opened_conversation",
            title: "Opened",
            subtitle: "Unread message",
            timeText: "Now",
            unreadText: "2",
            isPinned: false,
            isMuted: false
        )
        let viewModel = ConversationListViewModel(
            useCase: EmptySimulationConversationListUseCase(),
            initialState: ConversationListViewState(phase: .loaded, rows: [row])
        )

        viewModel.markConversationReadLocally(conversationID: "opened_conversation")

        #expect(viewModel.currentState.rows.first?.unreadText == nil)
        #expect(viewModel.currentState.rows.first?.title == "Opened")
    }

    @MainActor
    @Test func conversationListViewControllerDoesNotReloadLoadedRowsOnRepeatedAppear() async throws {
        let useCase = CountingConversationListUseCase()
        let viewModel = ConversationListViewModel(useCase: useCase)
        let searchViewModel = SearchViewModel(useCase: EmptySearchUseCase())
        let viewController = ConversationListViewController(
            viewModel: viewModel,
            searchViewModel: searchViewModel,
            onSelectConversation: { _ in }
        )

        viewController.loadViewIfNeeded()
        viewController.viewWillAppear(false)
        try await waitForCondition {
            viewModel.currentState.phase == .loaded
        }
        viewController.viewWillAppear(false)
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(await useCase.loadPageCallCount == 1)
    }

    @MainActor
    @Test func conversationListViewControllerRefreshesLoadedRowsAfterReturningFromChat() async throws {
        let useCase = ReadClearingConversationListUseCase()
        let viewModel = ConversationListViewModel(useCase: useCase)
        let searchViewModel = SearchViewModel(useCase: EmptySearchUseCase())
        let viewController = ConversationListViewController(
            viewModel: viewModel,
            searchViewModel: searchViewModel,
            onSelectConversation: { _ in }
        )

        viewController.loadViewIfNeeded()
        viewController.viewWillAppear(false)
        try await waitForCondition {
            viewModel.currentState.rows.first?.unreadText == "2"
        }
        #expect(viewModel.currentState.rows.first?.unreadText == "2")

        viewController.viewDidDisappear(false)
        viewController.viewWillAppear(false)
        try await waitForCondition {
            viewModel.currentState.rows.first?.unreadText == nil
        }

        #expect(await useCase.loadPageCallCount == 2)
    }

    @MainActor
    @Test func conversationListViewControllerClearsUnreadStateWhenSelectingConversation() async throws {
        let useCase = ReadClearingConversationListUseCase()
        let viewModel = ConversationListViewModel(useCase: useCase)
        let searchViewModel = SearchViewModel(useCase: EmptySearchUseCase())
        var selectedConversationID: ConversationID?
        let viewController = ConversationListViewController(
            viewModel: viewModel,
            searchViewModel: searchViewModel,
            onSelectConversation: { row in
                selectedConversationID = row.id
            }
        )

        viewController.loadViewIfNeeded()
        viewController.viewWillAppear(false)
        try await waitForCondition {
            viewModel.currentState.rows.first?.unreadText == "2"
        }
        #expect(viewModel.currentState.rows.first?.unreadText == "2")

        let collectionView = try #require(findView(in: viewController.view, identifier: "conversationList.collection") as? UICollectionView)
        viewController.collectionView(collectionView, didSelectItemAt: IndexPath(item: 0, section: 0))

        #expect(selectedConversationID == "read_clearing_conversation")
        #expect(viewModel.currentState.rows.first?.unreadText == nil)
    }

    @MainActor
    @Test func conversationListViewControllerReportsInitialLoadFinishedOnce() async throws {
        let useCase = CountingConversationListUseCase()
        let viewModel = ConversationListViewModel(useCase: useCase)
        let searchViewModel = SearchViewModel(useCase: EmptySearchUseCase())
        var finishedCount = 0
        let viewController = ConversationListViewController(
            viewModel: viewModel,
            searchViewModel: searchViewModel,
            onSelectConversation: { _ in },
            onInitialLoadFinished: {
                finishedCount += 1
            }
        )

        viewController.loadViewIfNeeded()
        viewController.viewWillAppear(false)
        try await waitForCondition {
            finishedCount == 1
        }
        viewController.viewWillAppear(false)
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(finishedCount == 1)
    }

    @MainActor
    @Test func conversationListLoadIfNeededEmitsDiagnostics() async throws {
        let diagnostics = ConversationListLoadingDiagnosticsSpy()
        let viewModel = ConversationListViewModel(
            useCase: StubConversationListUseCase(),
            diagnostics: diagnostics
        )

        viewModel.loadIfNeeded()
        try await waitForCondition {
            viewModel.currentState.phase == .loaded
        }

        let messages = diagnostics.messages
        #expect(messages.contains { $0.contains("loadIfNeeded called") })
        #expect(messages.contains { $0.contains("initial load started") })
        #expect(messages.contains { $0.contains("loading state published") })
        #expect(messages.contains { $0.contains("loaded state published") })
        #expect(messages.contains { $0.contains("initial load completed") })
    }

    @MainActor
    @Test func conversationListViewModelSimulatesIncomingMessagesAndReloadsRows() async throws {
        let useCase = SimulatingConversationListUseCase()
        let viewModel = ConversationListViewModel(useCase: useCase)

        viewModel.load()
        try await waitForCondition {
            viewModel.currentState.phase == .loaded
        }

        viewModel.simulateIncomingMessages()
        try await waitForCondition {
            viewModel.currentState.rows.first?.unreadText == "3"
        }

        #expect(await useCase.simulateIncomingCallCount == 1)
        #expect(await useCase.loadPageCallCount >= 2)
    }

    @MainActor
    @Test func conversationListViewModelKeepsLoadedStateWhileRefreshingAfterSimulation() async throws {
        let useCase = SimulatingConversationListUseCase()
        let diagnostics = ConversationListLoadingDiagnosticsSpy()
        let viewModel = ConversationListViewModel(useCase: useCase, diagnostics: diagnostics)

        viewModel.load()
        try await waitForCondition {
            viewModel.currentState.phase == .loaded
        }

        let loadingLogCountBeforeSimulation = diagnostics.messages.filter {
            $0.contains("initial load started") && $0.contains("showLoading=true")
        }.count

        viewModel.simulateIncomingMessages()
        try await waitForCondition {
            viewModel.currentState.rows.first?.unreadText == "3"
        }

        let loadingLogCountAfterSimulation = diagnostics.messages.filter {
            $0.contains("initial load started") && $0.contains("showLoading=true")
        }.count
        #expect(loadingLogCountAfterSimulation == loadingLogCountBeforeSimulation)
        #expect(viewModel.currentState.phase == .loaded)
    }

    @MainActor
    @Test func conversationListViewModelPublishesSimulationResultBeforeSlowRefreshCompletes() async throws {
        let useCase = ImmediateResultSlowRefreshConversationListUseCase()
        let viewModel = ConversationListViewModel(useCase: useCase)

        viewModel.load()
        try await waitForCondition {
            viewModel.currentState.phase == .loaded
        }

        viewModel.simulateIncomingMessages()
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(viewModel.currentState.rows.first?.subtitle == "Immediate simulation result")
        #expect(viewModel.currentState.rows.first?.unreadText == "4")
    }

    @MainActor
    @Test func conversationListViewModelMarksSimulationAndBackgroundRefreshRenderIntents() async throws {
        let useCase = ImmediateResultSlowRefreshConversationListUseCase()
        let viewModel = ConversationListViewModel(useCase: useCase)
        var capturedStates: [ConversationListViewState] = []
        let cancellable = viewModel.statePublisher.sink { state in
            capturedStates.append(state)
        }
        defer {
            cancellable.cancel()
        }

        viewModel.load()
        try await waitForCondition {
            viewModel.currentState.phase == .loaded
        }

        viewModel.simulateIncomingMessages()
        try await waitForCondition {
            capturedStates.contains(where: { $0.renderIntent == .simulatedIncoming })
        }

        let simulatedStateCandidate = capturedStates.last(where: { state in
            state.renderIntent == ConversationListViewState.RenderIntent.simulatedIncoming
        })
        let simulatedState = try #require(simulatedStateCandidate)
        #expect(simulatedState.rows.first?.subtitle == "Immediate simulation result")
        #expect(simulatedState.rows.isEmpty == false)

        try await waitForCondition(timeoutNanoseconds: 2_000_000_000) {
            capturedStates.contains(where: { $0.renderIntent == .backgroundRefresh && $0.phase == .loaded })
        }

        let refreshStateCandidate = capturedStates.last(where: { state in
            let isBackgroundRefresh = state.renderIntent == ConversationListViewState.RenderIntent.backgroundRefresh
            let isLoaded = state.phase == ConversationListViewState.LoadingPhase.loaded
            return isBackgroundRefresh && isLoaded
        })
        let refreshState = try #require(refreshStateCandidate)
        #expect(refreshState.rows.isEmpty == false)
    }

    @MainActor
    @Test func conversationListSnapshotPlannerAnimatesOnlySimulatedIncomingMove() {
        let previousIDs: [ConversationID] = ["conversation_a", "conversation_b", "conversation_c"]
        let newIDs: [ConversationID] = ["conversation_c", "conversation_a", "conversation_b"]

        let plan = ConversationListSnapshotPlanner.plan(
            previousRowIDs: previousIDs,
            rowIDs: newIDs,
            changedRowIDs: ["conversation_c"],
            phase: .loaded,
            renderIntent: .simulatedIncoming
        )

        #expect(plan.operation == .rebuild(animatingDifferences: true))
        #expect(plan.reconfiguredRowIDs == ["conversation_c"])
    }

    @MainActor
    @Test func conversationListSnapshotPlannerDoesNotAnimateBackgroundRefreshMove() {
        let previousIDs: [ConversationID] = ["conversation_a", "conversation_b", "conversation_c"]
        let newIDs: [ConversationID] = ["conversation_c", "conversation_a", "conversation_b"]

        let plan = ConversationListSnapshotPlanner.plan(
            previousRowIDs: previousIDs,
            rowIDs: newIDs,
            changedRowIDs: ["conversation_c"],
            phase: .loaded,
            renderIntent: .backgroundRefresh
        )

        #expect(plan.operation == .rebuild(animatingDifferences: false))
        #expect(plan.reconfiguredRowIDs == ["conversation_c"])
    }

    @MainActor
    @Test func conversationListSnapshotPlannerReconfiguresUnmovedContentChange() {
        let rowIDs: [ConversationID] = ["conversation_a", "conversation_b"]

        let plan = ConversationListSnapshotPlanner.plan(
            previousRowIDs: rowIDs,
            rowIDs: rowIDs,
            changedRowIDs: ["conversation_b"],
            phase: .loaded,
            renderIntent: .backgroundRefresh
        )

        #expect(plan.operation == .reconfigure)
        #expect(plan.reconfiguredRowIDs == ["conversation_b"])
    }

    @MainActor
    @Test func conversationListSnapshotPlannerAppendsPaginationWithoutAnimation() {
        let plan = ConversationListSnapshotPlanner.plan(
            previousRowIDs: ["conversation_a", "conversation_b"],
            rowIDs: ["conversation_a", "conversation_b", "conversation_c"],
            changedRowIDs: ["conversation_a"],
            phase: .loaded,
            renderIntent: .pagination
        )

        #expect(plan.operation == .append(newRowIDs: ["conversation_c"]))
        #expect(plan.reconfiguredRowIDs == ["conversation_a"])
    }

    @MainActor
    @Test func conversationListViewModelHandlesRapidSimulatedIncomingTaps() async throws {
        let useCase = DelayedSimulatingConversationListUseCase()
        let viewModel = ConversationListViewModel(useCase: useCase)

        viewModel.load()
        try await waitForCondition {
            viewModel.currentState.phase == .loaded
        }

        viewModel.simulateIncomingMessages()
        viewModel.simulateIncomingMessages()
        try await waitForCondition {
            viewModel.currentState.rows.first?.unreadText != nil
        }

        #expect(await useCase.simulateIncomingCallCount >= 1)
    }

    @MainActor
    @Test func conversationListViewModelPublishesFriendlyFailureWhenSimulationFails() async throws {
        let viewModel = ConversationListViewModel(useCase: FailingSimulationConversationListUseCase())

        viewModel.load()
        try await waitForCondition {
            viewModel.currentState.phase == .loaded
        }

        viewModel.simulateIncomingMessages()
        try await waitForCondition {
            viewModel.currentState.phase == .failed("Unable to simulate incoming messages")
        }
    }

    @MainActor
    @Test func conversationListViewControllerSimulateIncomingButtonTriggersViewModel() async throws {
        let useCase = SimulatingConversationListUseCase()
        let viewModel = ConversationListViewModel(useCase: useCase)
        let searchViewModel = SearchViewModel(useCase: EmptySearchUseCase())
        let viewController = ConversationListViewController(
            viewModel: viewModel,
            searchViewModel: searchViewModel,
            onSelectConversation: { _ in }
        )

        viewController.loadViewIfNeeded()
        let button = try #require(
            viewController.navigationItem.rightBarButtonItems?
                .compactMap { $0.customView as? UIButton }
                .first { $0.accessibilityIdentifier == "conversationList.simulateIncomingButton" }
        )
        #expect(button.accessibilityIdentifier == "conversationList.simulateIncomingButton")
        #expect(button.accessibilityLabel == "模拟接收消息")

        viewModel.load()
        try await waitForCondition {
            viewModel.currentState.phase == .loaded
        }

        button.sendActions(for: .touchUpInside)
        try await waitForCondition {
            await useCase.simulateIncomingCallCount == 1
        }
    }

    @MainActor
    @Test func conversationListViewControllerReloadsVisibleRowWhenUnreadChangesAfterSimulation() async throws {
        let useCase = SimulatingConversationListUseCase()
        let viewModel = ConversationListViewModel(useCase: useCase)
        let searchViewModel = SearchViewModel(useCase: EmptySearchUseCase())
        let viewController = ConversationListViewController(
            viewModel: viewModel,
            searchViewModel: searchViewModel,
            onSelectConversation: { _ in }
        )

        viewController.loadViewIfNeeded()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        viewController.viewWillAppear(false)
        let collectionView = try #require(findView(in: viewController.view, identifier: "conversationList.collection") as? UICollectionView)
        viewController.view.layoutIfNeeded()
        try await waitForCondition {
            viewModel.currentState.phase == .loaded && collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) != nil
        }

        viewModel.simulateIncomingMessages()
        try await waitForCondition {
            viewModel.currentState.rows.first?.unreadText == "3"
        }
        collectionView.layoutIfNeeded()

        let cell = try #require(collectionView.cellForItem(at: IndexPath(item: 0, section: 0)))
        #expect(cell.accessibilityLabel?.contains("3") == true)
    }

    @MainActor
    @Test func conversationListViewControllerRefreshesWhenConversationStoreChangesExternally() async throws {
        let useCase = ExternalConversationChangeUseCase()
        let viewModel = ConversationListViewModel(useCase: useCase)
        let searchViewModel = SearchViewModel(useCase: EmptySearchUseCase())
        let viewController = ConversationListViewController(
            viewModel: viewModel,
            searchViewModel: searchViewModel,
            onSelectConversation: { _ in }
        )

        viewController.loadViewIfNeeded()
        viewController.viewWillAppear(false)
        try await waitForCondition {
            viewModel.currentState.phase == .loaded
        }
        #expect(viewModel.currentState.rows.first?.unreadText == nil)

        await useCase.receiveUnreadMessage()
        NotificationCenter.default.post(name: .chatStoreConversationsDidChange, object: nil)
        try await waitForCondition {
            viewModel.currentState.rows.first?.unreadText == "1"
        }

        #expect(viewModel.currentState.rows.first?.unreadText == "1")
    }

    @Test func localConversationListUseCaseMapsRepositoryRows() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "ui_test_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let useCase = LocalConversationListUseCase(userID: "ui_test_user", storeProvider: storeProvider)

        let rows = try await useCase.loadConversations()

        #expect(rows.count == 3)
        #expect(rows.first?.id == "single_sondra")
        #expect(rows.first?.unreadText == "2")
    }

    @Test func localConversationListUseCaseMapsConversationAvatarURL() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "avatar_list_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "avatar_conversation",
                userID: "avatar_list_user",
                title: "Avatar Target",
                avatarURL: "https://example.com/conversation-avatar.png",
                sortTimestamp: 9_999
            )
        )
        let useCase = LocalConversationListUseCase(userID: "avatar_list_user", storeProvider: storeProvider)

        let rows = try await useCase.loadConversations()
        let avatarRow = rows.first { $0.id == "avatar_conversation" }

        #expect(avatarRow?.avatarURL == "https://example.com/conversation-avatar.png")
    }

    @Test func localConversationListUseCaseLoadsPagedRows() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "ui_test_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let useCase = LocalConversationListUseCase(userID: "ui_test_user", storeProvider: storeProvider)

        let firstPage = try await useCase.loadConversationPage(limit: 2, after: nil)
        let secondPage = try await useCase.loadConversationPage(limit: 2, after: firstPage.nextCursor)

        #expect(firstPage.rows.count == 2)
        #expect(firstPage.hasMore)
        #expect(secondPage.rows.count == 1)
        #expect(secondPage.hasMore == false)
    }

    @Test func localConversationListUseCaseUpdatesPinAndMuteState() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "ui_test_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let useCase = LocalConversationListUseCase(userID: "ui_test_user", storeProvider: storeProvider)

        try await useCase.setPinned(conversationID: "group_core", isPinned: true)
        try await useCase.setMuted(conversationID: "single_sondra", isMuted: true)

        let rows = try await useCase.loadConversations()
        #expect(rows.first?.id == "single_sondra")
        #expect(rows.first(where: { $0.id == "group_core" })?.isPinned == true)
        #expect(rows.first(where: { $0.id == "single_sondra" })?.isMuted == true)
    }

    @Test func localConversationListUseCaseSimulatesIncomingMessagesThroughSyncStore() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "ui_test_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let useCase = LocalConversationListUseCase(userID: "ui_test_user", storeProvider: storeProvider)
        let rowsBefore = try await useCase.loadConversations()

        let result = try #require(try await useCase.simulateIncomingMessages())
        let rowsAfter = try await useCase.loadConversations()
        let rowBefore = try #require(rowsBefore.first { $0.id == result.conversationID })
        let rowAfter = try #require(rowsAfter.first { $0.id == result.conversationID })
        let unreadBefore = Int(rowBefore.unreadText ?? "0") ?? 0
        let unreadAfter = Int(rowAfter.unreadText ?? "0") ?? 0

        #expect((1...5).contains(result.messageCount))
        #expect(unreadAfter == unreadBefore + result.messageCount)
        #expect(rowAfter.subtitle == result.finalRow.subtitle)
        #expect(rowAfter.subtitle.contains("#"))
        #expect(result.finalRow.id == result.conversationID)
    }

    @Test func localConversationListUseCaseReturnsNilWhenNoConversationsExist() async throws {
        let useCase = EmptySimulationConversationListUseCase()

        let result = try await useCase.simulateIncomingMessages()

        #expect(result == nil)
    }

    @Test func simulatedIncomingPushServiceWritesFixedConversationBatchThroughSyncStore() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "push_service_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "push_service_conversation",
                userID: "push_service_user",
                title: "Push Service",
                targetID: "push_service_peer",
                unreadCount: 1,
                sortTimestamp: 100
            )
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "push_service_user",
                conversationID: "push_service_conversation",
                senderID: "push_service_user",
                text: "Before push",
                localTime: 100,
                messageID: "push_service_existing",
                clientMessageID: "push_service_existing_client",
                sortSequence: 100
            )
        )
        let service = SimulatedIncomingPushService(userID: "push_service_user", storeProvider: storeProvider)

        let result = try #require(try await service.simulateIncomingPush(
            SimulatedIncomingPushRequest(target: .conversation("push_service_conversation"), messageCount: 2)
        ))
        let conversations = try await repository.listConversations(for: "push_service_user")
        let storedConversation = try #require(conversations.first { $0.id == "push_service_conversation" })
        let storedMessages = try await repository.listMessages(
            conversationID: "push_service_conversation",
            limit: 3,
            beforeSortSeq: nil
        )

        #expect(result.conversationID == "push_service_conversation")
        #expect(result.insertedCount == 2)
        #expect(result.messages.count == 2)
        #expect(result.messages.allSatisfy { $0.senderID == "push_service_peer" })
        #expect(result.finalConversation.unreadCount == 3)
        #expect(result.finalConversation.lastMessageDigest == result.messages.last?.text)
        #expect(storedConversation.unreadCount == 3)
        #expect(storedConversation.lastMessageDigest == result.messages.last?.text)
        #expect(storedMessages.prefix(2).map(\.id) == result.messages.reversed().map(\.messageID))
        #expect(storedMessages.prefix(2).allSatisfy { $0.senderID == "push_service_peer" })
    }

    @Test func simulatedIncomingPushServiceAssignsDistinctSequencesForConcurrentPushes() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "push_concurrent_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "push_concurrent_conversation",
                userID: "push_concurrent_user",
                title: "Push Concurrent",
                sortTimestamp: 100
            )
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "push_concurrent_user",
                conversationID: "push_concurrent_conversation",
                senderID: "push_concurrent_user",
                text: "Before concurrent push",
                localTime: 100,
                messageID: "push_concurrent_existing",
                clientMessageID: "push_concurrent_existing_client",
                sortSequence: 100
            )
        )
        let service = SimulatedIncomingPushService(userID: "push_concurrent_user", storeProvider: storeProvider)
        let request = SimulatedIncomingPushRequest(target: .conversation("push_concurrent_conversation"), messageCount: 2)

        async let first = service.simulateIncomingPush(request)
        async let second = service.simulateIncomingPush(request)
        let results = try await [first, second].compactMap { $0 }
        let sequences = results.flatMap(\.messages).map(\.sequence).sorted()

        #expect(results.count == 2)
        #expect(sequences.count == 4)
        #expect(Set(sequences).count == 4)
        #expect(sequences == Array(sequences[0]...(sequences[0] + 3)))
    }

    @Test func simulatedIncomingPushServiceReturnsNilWhenNoConversationExists() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "push_empty_user",
            storageService: storageService,
            database: DatabaseActor(),
            shouldSeedDemoData: false
        )
        let service = SimulatedIncomingPushService(userID: "push_empty_user", storeProvider: storeProvider)

        let result = try await service.simulateIncomingPush()

        #expect(result == nil)
    }

    @MainActor
    @Test func conversationListSimulatedPushIsVisibleAfterEnteringChat() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "push_enter_chat_user",
            storageService: storageService,
            database: DatabaseActor(),
            shouldSeedDemoData: false
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "push_enter_chat_conversation",
                userID: "push_enter_chat_user",
                title: "Push Enter Chat",
                sortTimestamp: 100
            )
        )
        let pushService = SimulatedIncomingPushService(userID: "push_enter_chat_user", storeProvider: storeProvider)

        let pushResult = try #require(try await pushService.simulateIncomingPush(
            SimulatedIncomingPushRequest(target: .conversation("push_enter_chat_conversation"), messageCount: 2)
        ))
        let useCase = StoreBackedChatUseCase(
            userID: "push_enter_chat_user",
            conversationID: pushResult.conversationID,
            storeProvider: storeProvider,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: AccountMediaFileStore(accountID: "push_enter_chat_user", storageService: storageService)
        )

        let page = try await useCase.loadInitialMessages()

        #expect(page.rows.map(\.id) == pushResult.messages.map(\.messageID))
        #expect(page.rows.allSatisfy { $0.isOutgoing == false })
    }

    @MainActor
    @Test func conversationListCellShowsFallbackAvatarWhenURLIsMissing() throws {
        let cell = ConversationListCell(frame: CGRect(x: 0, y: 0, width: 390, height: 82))

        cell.configure(
            row: ConversationListRowState(
                id: "fallback_avatar",
                title: "Sondra",
                avatarURL: nil,
                subtitle: "No image yet",
                timeText: "Now",
                unreadText: nil,
                isPinned: false,
                isMuted: false
            )
        )

        #expect(cell.contentConfiguration is ConversationListCellContentConfiguration)
        let avatarImageView = try #require(findView(in: cell, identifier: "conversation.avatarImageView") as? UIImageView)

        #expect(avatarImageView.image == nil)
        #expect(avatarImageView.isHidden)
        #expect(findLabel(withText: "S", in: cell) != nil)
    }

    @MainActor
    @Test func conversationListCellLoadsLocalAvatarImage() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let imageURL = directory.appendingPathComponent("conversation-avatar.jpg")
        try makeJPEGData(width: 4, height: 4, quality: 0.8).write(to: imageURL, options: [.atomic])
        let cell = ConversationListCell(frame: CGRect(x: 0, y: 0, width: 390, height: 82))

        cell.configure(
            row: ConversationListRowState(
                id: "local_avatar",
                title: "Local Avatar",
                avatarURL: imageURL.path,
                subtitle: "Image from disk",
                timeText: "Now",
                unreadText: nil,
                isPinned: false,
                isMuted: false
            )
        )

        #expect(cell.contentConfiguration is ConversationListCellContentConfiguration)
        let avatarImageView = try #require(findView(in: cell, identifier: "conversation.avatarImageView") as? UIImageView)

        #expect(avatarImageView.image != nil)
        #expect(avatarImageView.isHidden == false)
        #expect(findLabel(withText: "L", in: cell) != nil)
    }

    @MainActor
    @Test func conversationListCellPrepareForReuseClearsAvatarImage() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let imageURL = directory.appendingPathComponent("reuse-avatar.jpg")
        try makeJPEGData(width: 4, height: 4, quality: 0.8).write(to: imageURL, options: [.atomic])
        let cell = ConversationListCell(frame: CGRect(x: 0, y: 0, width: 390, height: 82))
        cell.configure(
            row: ConversationListRowState(
                id: "reuse_avatar",
                title: "Reuse Avatar",
                avatarURL: imageURL.absoluteString,
                subtitle: "Image from file URL",
                timeText: "Now",
                unreadText: nil,
                isPinned: false,
                isMuted: false
            )
        )
        let avatarImageView = try #require(findView(in: cell, identifier: "conversation.avatarImageView") as? UIImageView)
        #expect(avatarImageView.image != nil)

        cell.prepareForReuse()

        #expect(avatarImageView.image == nil)
        #expect(avatarImageView.isHidden)
    }
}
