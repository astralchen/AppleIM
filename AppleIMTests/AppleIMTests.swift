//
//  AppleIMTests.swift
//  AppleIMTests
//
//  Created by Sondra on 2026/4/28.
//

import Testing
import AVFoundation
import Combine
import Foundation
import CoreGraphics
import ImageIO
import UIKit
import UniformTypeIdentifiers
@testable import AppleIM

@Suite(.serialized)
struct AppleIMTests {

    @Test func storedMessageContentDerivesMessageType() {
        let image = StoredImageContent(
            mediaID: "content_image",
            localPath: "media/content.png",
            thumbnailPath: "media/content_thumb.jpg",
            width: 320,
            height: 240,
            sizeBytes: 4_096,
            format: "png"
        )
        let emoji = StoredEmojiContent(
            emojiID: "content_emoji",
            packageID: "pkg_content",
            emojiType: .customImage,
            name: "Content Emoji",
            localPath: "emoji/content.png",
            thumbPath: "emoji/content_thumb.png",
            cdnURL: nil,
            width: 128,
            height: 128,
            sizeBytes: 2_048
        )

        #expect(StoredMessageContent.text("Hello").type == .text)
        #expect(StoredMessageContent.image(image).type == .image)
        #expect(StoredMessageContent.emoji(emoji).type == .emoji)
        #expect(StoredMessageContent.revoked("已撤回").type == .revoked)
    }

    @Test func outgoingMessageInputsExposeSharedEnvelope() {
        let envelope = OutgoingMessageEnvelope(
            userID: "envelope_user",
            conversationID: "envelope_conversation",
            senderID: "envelope_sender",
            localTime: 1_234,
            messageID: "envelope_message",
            clientMessageID: "envelope_client",
            sortSequence: 1_235
        )

        let textInput = OutgoingTextMessageInput(envelope: envelope, text: "Hello", mentionedUserIDs: ["mentioned_user"], mentionsAll: false)
        let imageInput = OutgoingImageMessageInput(
            envelope: envelope,
            image: StoredImageContent(
                mediaID: "image_media",
                localPath: "media/image.png",
                thumbnailPath: "media/image_thumb.jpg",
                width: 320,
                height: 240,
                sizeBytes: 4_096,
                format: "png"
            )
        )
        let emojiInput = OutgoingEmojiMessageInput(
            envelope: envelope,
            emoji: StoredEmojiContent(
                emojiID: "emoji_1",
                packageID: nil,
                emojiType: .customImage,
                name: "Hi",
                localPath: "emoji/hi.png",
                thumbPath: nil,
                cdnURL: nil,
                width: 96,
                height: 96,
                sizeBytes: 2_048
            )
        )

        #expect(textInput.envelope == envelope)
        #expect(textInput.userID == envelope.userID)
        #expect(textInput.messageID == envelope.messageID)
        #expect(imageInput.envelope == envelope)
        #expect(imageInput.localTime == envelope.localTime)
        #expect(emojiInput.envelope == envelope)
        #expect(emojiInput.clientMessageID == envelope.clientMessageID)
    }

    @Test func storedMediaContentsExposeSharedResourceSnapshot() {
        let image = StoredImageContent(
            mediaID: "shared_media",
            localPath: "media/shared.png",
            thumbnailPath: "media/shared_thumb.jpg",
            width: 640,
            height: 480,
            sizeBytes: 8_192,
            remoteURL: "https://cdn.example/shared.png",
            md5: "abc123",
            format: "png",
            uploadStatus: .success
        )
        let expectedResource = StoredMediaResourceSnapshot(
            mediaID: "shared_media",
            localPath: "media/shared.png",
            sizeBytes: 8_192,
            remoteURL: "https://cdn.example/shared.png",
            md5: "abc123",
            uploadStatus: .success
        )

        #expect(image.resource == expectedResource)
        #expect(image.mediaID == expectedResource.mediaID)
        #expect(image.localPath == expectedResource.localPath)
        #expect(image.sizeBytes == expectedResource.sizeBytes)
        #expect(image.remoteURL == expectedResource.remoteURL)
        #expect(image.md5 == expectedResource.md5)
        #expect(image.uploadStatus == expectedResource.uploadStatus)
        #expect(StoredMessageContent.image(image).type == .image)
    }

    @Test func pendingJobPayloadEncodesExistingJSONShapes() throws {
        let input = try PendingMessageJobFactory.imageUploadInput(
            messageID: "payload_message",
            conversationID: "payload_conversation",
            clientMessageID: "payload_client",
            mediaID: "payload_media",
            userID: "payload_user",
            failureReason: "offline",
            maxRetryCount: 7,
            nextRetryAt: 99
        )
        let decoded = try input.decodedPayload()

        #expect(input.id == "image_upload_payload_client")
        #expect(input.bizKey == "payload_client")
        #expect(input.maxRetryCount == 7)
        #expect(input.nextRetryAt == 99)
        #expect(decoded == .mediaUpload(MediaUploadPendingJobPayload(
            messageID: "payload_message",
            conversationID: "payload_conversation",
            clientMessageID: "payload_client",
            mediaID: "payload_media",
            lastFailureReason: "offline"
        )))
        #expect(try PendingJobPayload.decode(input.payloadJSON, type: input.type) == decoded)
    }

    @Test func chatMessageRowStateCopyUpdatesOnlyRequestedFields() {
        let row = ChatMessageRowState(
            id: "copy_row",
            content: .text("Hello"),
            sortSequence: 42,
            sentAt: 41,
            timeText: "20:30",
            showsTimeSeparator: true,
            statusText: "发送中",
            uploadProgress: 0.5,
            senderAvatarURL: "https://cdn.example/avatar.png",
            isOutgoing: true,
            canRetry: true,
            canDelete: true,
            canRevoke: false
        )

        let copied = row.copy(
            content: .revoked("已撤回"),
            showsTimeSeparator: false,
            uploadProgress: 1.0
        )

        #expect(copied.id == row.id)
        #expect(copied.content == .revoked("已撤回"))
        #expect(copied.sortSequence == row.sortSequence)
        #expect(copied.sentAt == row.sentAt)
        #expect(copied.timeText == row.timeText)
        #expect(copied.showsTimeSeparator == false)
        #expect(copied.statusText == row.statusText)
        #expect(copied.uploadProgress == 1.0)
        #expect(copied.senderAvatarURL == row.senderAvatarURL)
        #expect(copied.isOutgoing == row.isOutgoing)
        #expect(copied.canRetry == row.canRetry)
        #expect(copied.canDelete == row.canDelete)
        #expect(copied.canRevoke == row.canRevoke)
    }

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

    @Test func accountStoragePreparesIsolatedDirectories() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let service = await FileAccountStorageService(rootDirectory: rootDirectory)
        let paths = try await service.prepareStorage(for: "test/account")

        #expect(paths.rootDirectory.lastPathComponent == "account_test_account")
        #expect(FileManager.default.fileExists(atPath: paths.mainDatabase.path))
        #expect(FileManager.default.fileExists(atPath: paths.searchDatabase.path))
        #expect(FileManager.default.fileExists(atPath: paths.fileIndexDatabase.path))
        #expect(FileManager.default.fileExists(atPath: paths.mediaDirectory.path))
        #expect(FileManager.default.fileExists(atPath: paths.cacheDirectory.path))
    }

    @Test func accountStorageAppliesFileProtectionToSensitivePaths() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let service = await FileAccountStorageService(rootDirectory: rootDirectory)
        let paths = try await service.prepareStorage(for: "protected_user")

        #if os(iOS)
        let protectedURLs = [
            paths.rootDirectory,
            paths.mainDatabase,
            paths.searchDatabase,
            paths.fileIndexDatabase,
            paths.mediaDirectory
        ]

        for url in protectedURLs {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let protection = attributes[.protectionKey] as? FileProtectionType
            #if targetEnvironment(simulator)
            if let protection {
                #expect(protection == .completeUntilFirstUserAuthentication)
            }
            #else
            #expect(protection == .completeUntilFirstUserAuthentication)
            #endif
        }

        let cacheAttributes = try FileManager.default.attributesOfItem(atPath: paths.cacheDirectory.path)
        let cacheProtection = cacheAttributes[.protectionKey] as? FileProtectionType
        #if targetEnvironment(simulator)
        if let cacheProtection {
            #expect(cacheProtection == FileProtectionType.none)
        }
        #else
        #expect(cacheProtection == FileProtectionType.none)
        #endif
        #endif
    }

    @Test func bundleAccountCatalogReadsMockAccounts() async throws {
        let bundle = Bundle.main.url(forResource: "mock_accounts", withExtension: "json") != nil
            ? Bundle.main
            : Bundle(identifier: "com.sondra.AppleIM") ?? Bundle.main
        let catalog = BundleAccountCatalog(bundle: bundle)

        let accounts = try await catalog.accounts()

        #expect(accounts.contains { $0.userID == "demo_user" })
        #expect(accounts.contains { $0.userID == "ui_test_user" })
    }

    @Test func localAccountAuthServiceLogsInWithAccountPassword() async throws {
        let catalog = BundleAccountCatalog(resourceURL: try makeMockAccountsFile())
        let authService = LocalAccountAuthService(catalog: catalog)

        let session = try await authService.login(identifier: "mock_user", password: "password123")

        #expect(session.userID == "mock_user")
        #expect(session.displayName == "Mock User")
        #expect(session.avatarURL == "https://example.com/mock-avatar.png")
        #expect(session.token.contains("mock_token_mock_user"))
    }

    @Test func accountSessionDecodesLegacyPayloadWithoutAvatarURL() throws {
        let json = """
        {
          "userID": "legacy_user",
          "displayName": "Legacy User",
          "token": "legacy_token",
          "loggedInAt": 1777777777
        }
        """

        let session = try JSONDecoder().decode(AccountSession.self, from: Data(json.utf8))

        #expect(session.userID == "legacy_user")
        #expect(session.displayName == "Legacy User")
        #expect(session.avatarURL == nil)
        #expect(session.token == "legacy_token")
    }

    @Test func localAccountAuthServiceRejectsInvalidLoginInputs() async throws {
        let catalog = BundleAccountCatalog(resourceURL: try makeMockAccountsFile())
        let authService = LocalAccountAuthService(catalog: catalog)

        await #expect(throws: AccountAuthError.emptyIdentifier) {
            _ = try await authService.login(identifier: "  ", password: "password123")
        }
        await #expect(throws: AccountAuthError.emptyPassword) {
            _ = try await authService.login(identifier: "mock_user", password: "")
        }
        await #expect(throws: AccountAuthError.accountNotFound) {
            _ = try await authService.login(identifier: "missing_user", password: "password123")
        }
        await #expect(throws: AccountAuthError.invalidPassword) {
            _ = try await authService.login(identifier: "mock_user", password: "wrong")
        }
    }

    @Test func accountSessionStoreSavesLoadsAndClearsSession() throws {
        let suiteName = "AppleIMTests.AccountSession.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let store = UserDefaultsAccountSessionStore(userDefaults: userDefaults)
        let session = AccountSession(
            userID: "session_user",
            displayName: "Session User",
            token: "mock_token",
            loggedInAt: 1_777_777_777
        )

        try store.saveSession(session)
        #expect(store.loadSession() == session)

        store.clearSession()
        #expect(store.loadSession() == nil)
    }

    @Test func clearingSessionDoesNotDeleteIsolatedAccountDirectories() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        let suiteName = "AppleIMTests.AccountSwitch.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let store = UserDefaultsAccountSessionStore(userDefaults: userDefaults)
        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)

        let firstPaths = try await storageService.prepareStorage(for: "first_account")
        let secondPaths = try await storageService.prepareStorage(for: "second_account")
        try store.saveSession(
            AccountSession(
                userID: "first_account",
                displayName: "First Account",
                token: "mock_token",
                loggedInAt: 1
            )
        )

        store.clearSession()

        #expect(store.loadSession() == nil)
        #expect(firstPaths.rootDirectory != secondPaths.rootDirectory)
        #expect(FileManager.default.fileExists(atPath: firstPaths.rootDirectory.path))
        #expect(FileManager.default.fileExists(atPath: secondPaths.rootDirectory.path))
    }

    @MainActor
    @Test func appDependencyContainerUsesLoginAccountStorage() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let container = try AppDependencyContainer(
            accountID: "login_container_user",
            storageService: storageService,
            database: DatabaseActor(),
            databaseKeyStore: InMemoryAccountDatabaseKeyStore(),
            applicationBadgeManager: CapturingApplicationBadgeManager()
        )

        let paths = try await container.prepareCurrentAccountStorage()

        #expect(container.accountID == "login_container_user")
        #expect(paths.rootDirectory.lastPathComponent == "account_login_container_user")
        #expect(FileManager.default.fileExists(atPath: paths.mainDatabase.path))
    }

    @MainActor
    @Test func appDependencyContainerDeletesCurrentAccountStorage() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let keyStore = InMemoryAccountDatabaseKeyStore()
        let container = try AppDependencyContainer(
            accountID: "delete_container_user",
            storageService: storageService,
            database: DatabaseActor(),
            databaseKeyStore: keyStore,
            applicationBadgeManager: CapturingApplicationBadgeManager()
        )

        let paths = try await container.prepareCurrentAccountStorage()
        let originalKey = try await keyStore.databaseKey(for: "delete_container_user")

        try await container.deleteCurrentAccountStorage()
        let regeneratedKey = try await keyStore.databaseKey(for: "delete_container_user")

        #expect(FileManager.default.fileExists(atPath: paths.rootDirectory.path) == false)
        #expect(regeneratedKey.count == 32)
        #expect(regeneratedKey != originalKey)
    }

    @MainActor
    @Test func appDependencyContainerRefreshesBadgeWithoutConversationListGate() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = TrackingAccountStorageService(rootDirectory: rootDirectory)
        let badgeManager = CapturingApplicationBadgeManager()
        let container = try AppDependencyContainer(
            accountID: "direct_startup_user",
            storageService: storageService,
            database: DatabaseActor(),
            databaseKeyStore: InMemoryAccountDatabaseKeyStore(),
            applicationBadgeManager: badgeManager
        )

        container.refreshApplicationBadge()

        var didCaptureBadgeRefresh = false
        let startedAt = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - startedAt < 5_000_000_000 {
            if await badgeManager.values().isEmpty == false {
                didCaptureBadgeRefresh = true
                break
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(didCaptureBadgeRefresh)
        #expect(await storageService.prepareCallCount == 1)
    }

    @MainActor
    @Test func appDependencyContainerHidesTabBarWhenPushingChat() throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let container = try AppDependencyContainer(
            accountID: "hide_tab_bar_user",
            storageService: TrackingAccountStorageService(rootDirectory: rootDirectory),
            database: DatabaseActor(),
            databaseKeyStore: InMemoryAccountDatabaseKeyStore(),
            applicationBadgeManager: CapturingApplicationBadgeManager()
        )
        let chatViewController = container.makeChatViewController(
            conversation: ConversationListRowState(
                id: "hide_tab_bar_conversation",
                title: "Hide Tab",
                avatarURL: nil,
                subtitle: "Open chat",
                timeText: "Now",
                unreadText: nil,
                isPinned: false,
                isMuted: false
            )
        )

        #expect(chatViewController.hidesBottomBarWhenPushed)
    }

    @MainActor
    @Test func chatViewControllerUsesInlineNavigationTitle() throws {
        let viewModel = ChatViewModel(useCase: SimulatedIncomingStubChatUseCase(), title: "Sondra")
        let viewController = ChatViewController(viewModel: viewModel)

        viewController.loadViewIfNeeded()

        #expect(viewController.navigationItem.largeTitleDisplayMode == .never)
    }

    @Test func serverMessageSendConfigurationRequiresExplicitBaseURL() async throws {
        let missingConfiguration = ServerMessageSendService.Configuration.fromEnvironment([:], token: "secret_token")
        let missingTokenConfiguration = ServerMessageSendService.Configuration.fromEnvironment(
            ["CHATBRIDGE_SERVER_BASE_URL": "https://api.example.com"],
            token: nil
        )
        let configuration = try #require(
            ServerMessageSendService.Configuration.fromEnvironment(
                [
                    "CHATBRIDGE_SERVER_BASE_URL": "https://api.example.com",
                    "CHATBRIDGE_SERVER_TIMEOUT_SECONDS": "7"
                ],
                token: "secret_token"
            )
        )

        #expect(missingConfiguration == nil)
        #expect(missingTokenConfiguration == nil)
        #expect(configuration.baseURL.absoluteString == "https://api.example.com")
        #expect(configuration.timeoutSeconds == 7)
        #expect(await configuration.authTokenProvider() == "secret_token")
    }

    @Test func tokenRefreshActorReturnsCachedTokenAndPersistsRefresh() async throws {
        let suiteName = "AppleIMTests.TokenRefresh.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let sessionStore = UserDefaultsAccountSessionStore(userDefaults: userDefaults)
        let session = AccountSession(
            userID: "refresh_user",
            displayName: "Refresh User",
            token: "old_token",
            loggedInAt: 1
        )
        try sessionStore.saveSession(session)
        let httpClient = RecordingHTTPClient(
            tokenRefreshResponse: ServerTokenRefreshResponse(token: "new_token")
        )
        let tokenActor = TokenRefreshActor(
            session: session,
            sessionStore: sessionStore,
            httpClient: httpClient
        )

        let cachedToken = await tokenActor.validToken()
        let refreshedToken = await tokenActor.refreshToken()
        let persistedSession = sessionStore.loadSession()
        let request = await httpClient.lastTokenRefreshRequest

        #expect(cachedToken == "old_token")
        #expect(refreshedToken == "new_token")
        #expect(await tokenActor.validToken() == "new_token")
        #expect(persistedSession?.token == "new_token")
        #expect(request?.token == "old_token")
    }

    @Test func tokenRefreshActorCoalescesConcurrentRefreshes() async throws {
        let sessionStore = InMemoryAccountSessionStore(
            session: AccountSession(
                userID: "coalesce_user",
                displayName: "Coalesce User",
                token: "coalesce_old_token",
                loggedInAt: 1
            )
        )
        let httpClient = RecordingHTTPClient(
            tokenRefreshResponse: ServerTokenRefreshResponse(token: "coalesce_new_token"),
            delayNanoseconds: 100_000_000
        )
        let tokenActor = TokenRefreshActor(
            session: try #require(sessionStore.loadSession()),
            sessionStore: sessionStore,
            httpClient: httpClient
        )

        async let first = tokenActor.refreshToken()
        async let second = tokenActor.refreshToken()
        async let third = tokenActor.refreshToken()
        let tokens = await [first, second, third]

        #expect(tokens == ["coalesce_new_token", "coalesce_new_token", "coalesce_new_token"])
        #expect(await httpClient.tokenRefreshCallCount == 1)
        #expect(sessionStore.loadSession()?.token == "coalesce_new_token")
    }

    @Test func serverMessageSendConfigurationUsesTokenProviderActor() async throws {
        let sessionStore = InMemoryAccountSessionStore(
            session: AccountSession(
                userID: "provider_user",
                displayName: "Provider User",
                token: "provider_old_token",
                loggedInAt: 1
            )
        )
        let tokenActor = TokenRefreshActor(
            session: try #require(sessionStore.loadSession()),
            sessionStore: sessionStore,
            httpClient: RecordingHTTPClient(tokenRefreshResponse: ServerTokenRefreshResponse(token: "provider_new_token"))
        )
        let authTokenProvider: @Sendable () async -> String? = {
            await tokenActor.validToken()
        }
        let optionalConfiguration = ServerMessageSendService.Configuration.fromEnvironment(
            ["CHATBRIDGE_SERVER_BASE_URL": "https://api.example.com"],
            authTokenProvider: authTokenProvider
        )
        let configuration = try #require(optionalConfiguration)

        #expect(await configuration.authTokenProvider() == "provider_old_token")
        _ = await tokenActor.refreshToken()
        #expect(await configuration.authTokenProvider() == "provider_new_token")
    }

    @MainActor
    @Test func uiTestMessageSendConfigurationKeepsUsingMockService() async throws {
        let service = AppUITestConfiguration.makeMessageSendService(
            for: AppUITestConfiguration.Configuration(
                runID: "ui_send_config",
                sendMode: .success,
                resetSession: true
            )
        )
        let result = await service.sendText(message: makeStoredTextMessage(messageID: "ui_config_message"))

        guard case let .success(ack) = result else {
            Issue.record("Expected UI test send service to use mock success")
            return
        }

        #expect(ack.serverMessageID == "server_ui_config_message")
        #expect(ack.sequence == 100)
    }

    @MainActor
    @Test func accountDatabaseKeyStoreGeneratesStableIsolatedKeys() async throws {
        let keyStore = InMemoryAccountDatabaseKeyStore()

        let firstKey = try await keyStore.databaseKey(for: "secure_user")
        let repeatedKey = try await keyStore.databaseKey(for: "secure_user")
        let otherAccountKey = try await keyStore.databaseKey(for: "other_secure_user")
        try await keyStore.deleteDatabaseKey(for: "secure_user")
        let regeneratedKey = try await keyStore.databaseKey(for: "secure_user")

        #expect(firstKey.count == 32)
        #expect(firstKey == repeatedKey)
        #expect(firstKey != otherAccountKey)
        #expect(regeneratedKey.count == 32)
        #expect(regeneratedKey != firstKey)
    }

    @MainActor
    @Test func chatStoreProviderDeletesAccountStorageAndDatabaseKey() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let keyStore = InMemoryAccountDatabaseKeyStore()
        let storeProvider = ChatStoreProvider(
            accountID: "delete_secure_user",
            storageService: storageService,
            database: DatabaseActor(),
            databaseKeyStore: keyStore
        )

        _ = try await storeProvider.repository()
        let originalKey = try await keyStore.databaseKey(for: "delete_secure_user")
        let paths = try await storageService.prepareStorage(for: "delete_secure_user")

        try await storeProvider.deleteAccountStorage()
        let regeneratedKey = try await keyStore.databaseKey(for: "delete_secure_user")

        #expect(FileManager.default.fileExists(atPath: paths.rootDirectory.path) == false)
        #expect(regeneratedKey.count == 32)
        #expect(regeneratedKey != originalKey)
    }

    @MainActor
    @Test func chatStoreProviderClosesDatabaseConnectionsBeforeDeletingAccountStorage() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let databaseActor = DatabaseActor()
        let storeProvider = ChatStoreProvider(
            accountID: "delete_cached_connection_user",
            storageService: storageService,
            database: databaseActor,
            databaseKeyStore: InMemoryAccountDatabaseKeyStore()
        )

        _ = try await storeProvider.repository()
        let paths = try await storageService.prepareStorage(for: "delete_cached_connection_user")
        _ = try await databaseActor.tableNames(in: .main, paths: paths)

        #expect(await databaseActor.cachedConnectionCount(for: paths) > 0)

        try await storeProvider.deleteAccountStorage()

        #expect(await databaseActor.cachedConnectionCount(for: paths) == 0)
        #expect(FileManager.default.fileExists(atPath: paths.rootDirectory.path) == false)
    }

    @MainActor
    @Test func chatStoreProviderClosesCurrentAccountConnectionsWithoutDeletingStorage() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let databaseActor = DatabaseActor()
        let storeProvider = ChatStoreProvider(
            accountID: "logout_cached_connection_user",
            storageService: storageService,
            database: databaseActor,
            databaseKeyStore: InMemoryAccountDatabaseKeyStore()
        )

        _ = try await storeProvider.repository()
        let paths = try await storageService.prepareStorage(for: "logout_cached_connection_user")
        _ = try await databaseActor.tableNames(in: .main, paths: paths)
        #expect(await databaseActor.cachedConnectionCount(for: paths) > 0)

        try await storeProvider.closeAccountConnections()

        #expect(await databaseActor.cachedConnectionCount(for: paths) == 0)
        #expect(FileManager.default.fileExists(atPath: paths.rootDirectory.path))
    }

    @MainActor
    @Test func chatStoreProviderInitializesEncryptedDatabasesWithSQLCipher() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let keyStore = InMemoryAccountDatabaseKeyStore()
        let databaseActor = DatabaseActor()
        let storeProvider = ChatStoreProvider(
            accountID: "cipher_user",
            storageService: storageService,
            database: databaseActor,
            databaseKeyStore: keyStore
        )

        _ = try await storeProvider.repository()
        let paths = try await storageService.prepareStorage(for: "cipher_user")

        for databaseKind in DatabaseFileKind.allCases {
            let cipherVersion = try await databaseActor.cipherVersion(in: databaseKind, paths: paths)
            #expect(cipherVersion.isEmpty == false)
        }
    }

    @MainActor
    @Test func chatStoreProviderReusesPreparedStorageAcrossRepositorySearchAndRepair() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = TrackingAccountStorageService(rootDirectory: rootDirectory)
        let keyStore = TrackingAccountDatabaseKeyStore()
        let storeProvider = ChatStoreProvider(
            accountID: "cached_bootstrap_user",
            storageService: storageService,
            database: DatabaseActor(),
            databaseKeyStore: keyStore
        )

        _ = try await storeProvider.repository()
        _ = try await storeProvider.searchIndex()
        _ = try await storeProvider.dataRepairService()

        #expect(await storageService.prepareCallCount == 1)
        #expect(await keyStore.databaseKeyCallCount == 1)
    }

    @MainActor
    @Test func chatStoreProviderSeedsDemoDataWithoutBadgeSideEffects() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let badgeManager = CapturingApplicationBadgeManager()
        let storeProvider = ChatStoreProvider(
            accountID: "seed_side_effect_user",
            storageService: storageService,
            database: DatabaseActor(),
            databaseKeyStore: InMemoryAccountDatabaseKeyStore(),
            applicationBadgeManager: badgeManager
        )

        _ = try await storeProvider.repository()

        #expect(await badgeManager.values().isEmpty)
    }

    @MainActor
    @Test func chatStoreProviderSeedsDemoMessagesForInitialConversations() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "seed_message_user",
            storageService: storageService,
            database: DatabaseActor(),
            databaseKeyStore: InMemoryAccountDatabaseKeyStore()
        )

        let repository = try await storeProvider.repository()
        let conversations = try await repository.listConversations(for: "seed_message_user")
        let conversationsByID = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })

        for conversationID in [ConversationID("single_sondra"), ConversationID("group_core"), ConversationID("system_release")] {
            let conversation = try #require(conversationsByID[conversationID])
            let messages = try await repository.listMessages(
                conversationID: conversationID,
                limit: 20,
                beforeSortSeq: nil
            )
            let latestMessage = try #require(messages.first)

            #expect(try requireTextualContent(latestMessage) == conversation.lastMessageDigest)
        }
    }

    @MainActor
    @Test func encryptedDatabaseCannotBeReadWithoutConfiguredKeyOrWithWrongKey() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let keyStore = InMemoryAccountDatabaseKeyStore()
        let encryptedDatabaseActor = DatabaseActor()
        let storeProvider = ChatStoreProvider(
            accountID: "wrong_key_user",
            storageService: storageService,
            database: encryptedDatabaseActor,
            databaseKeyStore: keyStore
        )

        _ = try await storeProvider.repository()
        let paths = try await storageService.prepareStorage(for: "wrong_key_user")

        let unconfiguredActor = DatabaseActor()
        let unconfiguredReadFailed = await databaseReadFails(using: unconfiguredActor, paths: paths)

        let wrongKeyActor = DatabaseActor()
        await wrongKeyActor.configureEncryptionKey(Data(repeating: 0x7F, count: 32), for: paths)
        let wrongKeyReadFailed = await databaseReadFails(using: wrongKeyActor, paths: paths)

        #expect(unconfiguredReadFailed)
        #expect(wrongKeyReadFailed)
    }

    @MainActor
    @Test func plaintextDatabaseMigratesToEncryptedDatabaseWithoutLosingData() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let accountID: UserID = "plaintext_migration_user"
        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let paths = try await storageService.prepareStorage(for: accountID)
        let plaintextActor = DatabaseActor()
        _ = try await plaintextActor.bootstrap(paths: paths)
        let plaintextRepository = LocalChatRepository(database: plaintextActor, paths: paths)
        try await plaintextRepository.upsertConversation(
            makeConversationRecord(
                id: "plaintext_migration_conversation",
                userID: accountID,
                title: "Migrated Conversation",
                sortTimestamp: 10
            )
        )

        let encryptedActor = DatabaseActor()
        let storeProvider = ChatStoreProvider(
            accountID: accountID,
            storageService: storageService,
            database: encryptedActor,
            databaseKeyStore: InMemoryAccountDatabaseKeyStore()
        )

        let encryptedRepository = try await storeProvider.repository()
        let conversations = try await encryptedRepository.listConversations(for: accountID)
        let cipherVersion = try await encryptedActor.cipherVersion(in: .main, paths: paths)
        let unconfiguredReadFailed = await databaseReadFails(using: DatabaseActor(), paths: paths)

        #expect(conversations.contains { $0.title == "Migrated Conversation" })
        #expect(cipherVersion.isEmpty == false)
        #expect(unconfiguredReadFailed)
    }

    @Test func databaseActorErrorDescriptionRedactsSensitiveDetails() {
        let error = DatabaseActorError.executeFailed(
            path: "/private/account_sensitive_user/main.db",
            statement: "INSERT INTO message_text (text) VALUES ('secret token message');",
            message: "failed near secret token message"
        )
        let description = String(describing: error)

        #expect(description == error.safeDescription)
        #expect(description.contains("account_sensitive_user") == false)
        #expect(description.contains("secret token message") == false)
        #expect(description.contains("INSERT INTO") == false)
        #expect(description.contains("/private/") == false)
    }

    @Test func databaseActorReusesCachedConnectionForRepeatedQueries() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "cached_connection_user")
        try await databaseActor.closeConnections(for: paths)
        #expect(await databaseActor.cachedConnectionCount(for: paths) == 0)

        _ = try await databaseActor.tableNames(in: .main, paths: paths)
        let openCountAfterFirstQuery = await databaseActor.openCount(for: .main, paths: paths)
        _ = try await databaseActor.tableNames(in: .main, paths: paths)
        let openCountAfterSecondQuery = await databaseActor.openCount(for: .main, paths: paths)

        #expect(openCountAfterFirstQuery == 1)
        #expect(openCountAfterSecondQuery == openCountAfterFirstQuery)
        #expect(await databaseActor.cachedConnectionCount(for: paths) == 1)
    }

    @Test func databaseActorReopensConnectionAfterClosingAccountPaths() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "reopen_connection_user")
        try await databaseActor.closeConnections(for: paths)

        _ = try await databaseActor.tableNames(in: .main, paths: paths)
        #expect(await databaseActor.openCount(for: .main, paths: paths) == 1)

        try await databaseActor.closeConnections(for: paths)
        #expect(await databaseActor.cachedConnectionCount(for: paths) == 0)

        _ = try await databaseActor.tableNames(in: .main, paths: paths)
        #expect(await databaseActor.openCount(for: .main, paths: paths) == 2)
        #expect(await databaseActor.cachedConnectionCount(for: paths) == 1)
    }

    @Test func databaseBootstrapPersistsMigrationMetadata() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let paths = try await storageService.prepareStorage(for: "metadata_user")
        let databaseActor = DatabaseActor()

        let result = try await databaseActor.bootstrap(paths: paths)
        let loadedMetadata = try await databaseActor.loadMigrationMetadata(paths: paths)
        let mainTables = try await databaseActor.tableNames(in: .main, paths: paths)
        let searchTables = try await databaseActor.tableNames(in: .search, paths: paths)
        let fileIndexTables = try await databaseActor.tableNames(in: .fileIndex, paths: paths)

        #expect(result.metadata.schemaVersion == DatabaseSchema.currentVersion)
        #expect(loadedMetadata == result.metadata)
        #expect(loadedMetadata.appliedScriptIDs.contains("001_main_core_tables"))
        #expect(loadedMetadata.appliedScriptIDs.contains("001_search_tables"))
        #expect(loadedMetadata.appliedScriptIDs.contains("001_file_index_tables"))
        #expect(loadedMetadata.appliedScriptIDs.contains("002_notification_badge_settings"))
        #expect(mainTables.contains("migration_meta"))
        #expect(mainTables.contains("conversation"))
        #expect(mainTables.contains("message"))
        #expect(searchTables.contains("message_search"))
        #expect(searchTables.contains("contact_search"))
        #expect(searchTables.contains("conversation_search"))
        #expect(fileIndexTables.contains("file_index"))
    }

    @Test func databaseBootstrapCreatesNotificationBadgeSettingColumns() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "fresh_badge_schema_user")
        let rows = try await databaseActor.query("PRAGMA table_info(notification_setting);", paths: paths)
        let columns = Set(rows.compactMap { $0.string("name") })
        let repository = LocalChatRepository(database: databaseActor, paths: paths)
        let setting = try await repository.notificationSetting(for: "fresh_badge_schema_user")

        #expect(columns.contains("badge_enabled"))
        #expect(columns.contains("badge_include_muted"))
        #expect(setting.badgeEnabled == true)
        #expect(setting.badgeIncludeMuted == true)
    }

    @Test func databaseBootstrapMigratesLegacyNotificationBadgeSettingColumns() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let paths = try await storageService.prepareStorage(for: "legacy_badge_schema_user")
        let databaseActor = DatabaseActor()
        try await databaseActor.execute(
            """
            CREATE TABLE notification_setting (
                user_id TEXT PRIMARY KEY,
                is_enabled INTEGER DEFAULT 1,
                show_preview INTEGER DEFAULT 1,
                updated_at INTEGER
            );
            """,
            paths: paths
        )
        try await databaseActor.execute(
            """
            INSERT INTO notification_setting (user_id, is_enabled, show_preview, updated_at)
            VALUES (?, 1, 0, 10);
            """,
            parameters: [.text("legacy_badge_schema_user")],
            paths: paths
        )

        _ = try await databaseActor.bootstrap(paths: paths)
        let rows = try await databaseActor.query("PRAGMA table_info(notification_setting);", paths: paths)
        let columns = Set(rows.compactMap { $0.string("name") })
        let repository = LocalChatRepository(database: databaseActor, paths: paths)
        let setting = try await repository.notificationSetting(for: "legacy_badge_schema_user")

        #expect(columns.contains("badge_enabled"))
        #expect(columns.contains("badge_include_muted"))
        #expect(setting.showPreview == false)
        #expect(setting.badgeEnabled == true)
        #expect(setting.badgeIncludeMuted == true)
    }

    @Test func databaseBootstrapCreatesEmojiTablesAndIndexes() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "emoji_schema_user")
        let tableNames = try await databaseActor.tableNames(in: .main, paths: paths)
        let indexes = try await databaseActor.query(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_emoji_%' ORDER BY name;",
            paths: paths
        )
        let indexNames = indexes.compactMap { $0.string("name") }

        #expect(tableNames.contains("emoji_store"))
        #expect(tableNames.contains("emoji_package"))
        #expect(tableNames.contains("message_emoji"))
        #expect(indexNames.contains("idx_emoji_user_recent"))
        #expect(indexNames.contains("idx_emoji_user_favorite"))
        #expect(indexNames.contains("idx_emoji_package_user_sort"))
    }

    @Test func emojiRepositoryListsPackagesFavoritesAndRecentPerAccount() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "emoji_user")
        let package = EmojiPackageRecord(
            packageID: "pkg_wave",
            userID: "emoji_user",
            title: "Wave Pack",
            author: "ChatBridge",
            coverURL: nil,
            localCoverPath: nil,
            version: 1,
            status: .downloaded,
            sortOrder: 1,
            createdAt: 10,
            updatedAt: 10
        )
        let wave = EmojiAssetRecord(
            emojiID: "wave",
            userID: "emoji_user",
            packageID: "pkg_wave",
            emojiType: .package,
            name: "Wave",
            md5: "wave_md5",
            localPath: "/tmp/wave.png",
            thumbPath: "/tmp/wave-thumb.png",
            cdnURL: nil,
            width: 128,
            height: 128,
            sizeBytes: 2048,
            useCount: 0,
            lastUsedAt: nil,
            isFavorite: false,
            isDeleted: false,
            extraJSON: nil,
            createdAt: 10,
            updatedAt: 10
        )
        let otherAccountEmoji = EmojiAssetRecord(
            emojiID: "other_wave",
            userID: "other_user",
            packageID: "pkg_wave",
            emojiType: .package,
            name: "Other",
            md5: nil,
            localPath: nil,
            thumbPath: nil,
            cdnURL: nil,
            width: nil,
            height: nil,
            sizeBytes: nil,
            useCount: 0,
            lastUsedAt: nil,
            isFavorite: false,
            isDeleted: false,
            extraJSON: nil,
            createdAt: 10,
            updatedAt: 10
        )

        try await repository.upsertEmojiPackage(package)
        try await repository.upsertEmojiAsset(wave)
        try await repository.upsertEmojiAsset(otherAccountEmoji)
        try await repository.setEmojiFavorite(emojiID: "wave", userID: "emoji_user", isFavorite: true, updatedAt: 20)
        try await repository.recordEmojiUsed(emojiID: "wave", userID: "emoji_user", usedAt: 30)

        let packages = try await repository.listEmojiPackages(for: "emoji_user")
        let favorites = try await repository.listFavoriteEmojis(for: "emoji_user")
        let recent = try await repository.listRecentEmojis(for: "emoji_user", limit: 10)
        let otherRecent = try await repository.listRecentEmojis(for: "other_user", limit: 10)

        #expect(packages.map(\.packageID) == ["pkg_wave"])
        #expect(favorites.map(\.emojiID) == ["wave"])
        #expect(recent.map(\.emojiID) == ["wave"])
        #expect(recent.first?.useCount == 1)
        #expect(otherRecent.isEmpty)
    }

    @Test func insertingOutgoingEmojiMessagePersistsContentAndConversationDigest() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "emoji_message_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "emoji_conversation", userID: "emoji_message_user", title: "Emoji", sortTimestamp: 1)
        )

        let message = try await repository.insertOutgoingEmojiMessage(
            OutgoingEmojiMessageInput(
                userID: "emoji_message_user",
                conversationID: "emoji_conversation",
                senderID: "emoji_message_user",
                emoji: StoredEmojiContent(
                    emojiID: "smile",
                    packageID: "pkg_smile",
                    emojiType: .package,
                    name: "Smile",
                    localPath: "/tmp/smile.png",
                    thumbPath: "/tmp/smile-thumb.png",
                    cdnURL: nil,
                    width: 128,
                    height: 128,
                    sizeBytes: 1024
                ),
                localTime: 100,
                messageID: "emoji_message",
                clientMessageID: "emoji_client",
                sortSequence: 100
            )
        )
        let loaded = try await repository.message(messageID: "emoji_message")
        let conversations = try await repository.listConversations(for: "emoji_message_user")

        #expect(message.type == .emoji)
        let loadedEmoji = try requireEmojiContent(loaded)
        #expect(loadedEmoji.emojiID == "smile")
        #expect(loadedEmoji.thumbPath == "/tmp/smile-thumb.png")
        #expect(conversations.first { $0.id == "emoji_conversation" }?.lastMessageDigest == "[表情]")
    }

    @MainActor
    @Test func chatViewModelLoadsFavoritesAndSendsEmoji() async throws {
        let useCase = EmojiPanelStubChatUseCase()
        let viewModel = ChatViewModel(useCase: useCase, title: "Emoji Chat")

        viewModel.loadEmojiPanel()
        try await waitForCondition {
            viewModel.currentState.emojiPanel.packages.map(\.packageID) == ["pkg_stub"]
        }

        #expect(viewModel.currentState.emojiPanel.favoriteEmojis.map(\.emojiID) == ["favorite_stub"])
        viewModel.toggleEmojiFavorite(emojiID: "package_stub", isFavorite: true)
        try await waitForCondition {
            useCase.favoriteUpdates == ["package_stub:true"]
        }

        viewModel.sendEmoji(useCase.packageEmoji)
        try await waitForCondition {
            viewModel.currentState.rows.contains { $0.id == "sent_emoji" }
        }

        #expect(useCase.sentEmojiIDs == ["package_stub"])
        #expect(viewModel.currentState.rows.first?.content == .emoji(
            ChatMessageRowContent.EmojiContent(
                emojiID: "package_stub",
                name: "Package Stub",
                localPath: "/tmp/package.png",
                thumbPath: "/tmp/package-thumb.png",
                cdnURL: nil
            )
        ))
    }

    @Test func searchIndexRebuildIndexesContactsConversationsAndMessages() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "search_user")
        try await databaseContext.databaseActor.execute(
            """
            INSERT INTO contact (
                contact_id,
                user_id,
                wxid,
                nickname,
                remark,
                type,
                is_deleted
            ) VALUES (?, ?, ?, ?, ?, 0, 0);
            """,
            parameters: [
                .text("contact_sondra"),
                .text("search_user"),
                .text("wx_sondra"),
                .text("Sondra Search"),
                .text("Index Friend")
            ],
            paths: databaseContext.paths
        )
        try await repository.upsertConversation(
            makeConversationRecord(id: "search_conversation", userID: "search_user", title: "Bridge Search", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "search_user",
                conversationID: "search_conversation",
                senderID: "search_user",
                text: "Hello full text search",
                localTime: 100,
                messageID: "search_message",
                clientMessageID: "search_client",
                sortSequence: 100
            )
        )

        let searchIndex = SearchIndexActor(database: databaseContext.databaseActor, paths: databaseContext.paths)
        try await searchIndex.rebuildAll(userID: "search_user")

        let contactResults = try await searchIndex.search(query: "Sondra", limit: 10)
        let conversationResults = try await searchIndex.search(query: "Bridge", limit: 10)
        let messageResults = try await searchIndex.search(query: "Hello", limit: 10)

        #expect(contactResults.contains { $0.kind == .contact && $0.id == "contact_sondra" })
        #expect(conversationResults.contains { $0.kind == .conversation && $0.conversationID == "search_conversation" })
        #expect(messageResults.contains { $0.kind == .message && $0.messageID == "search_message" })
    }

    @Test func searchIndexRebuildExcludesDeletedAndRevokedMessages() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "search_filter_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "search_filter_conversation", userID: "search_filter_user", title: "Filter", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "search_filter_user",
                conversationID: "search_filter_conversation",
                senderID: "search_filter_user",
                text: "DeleteOnlyTerm",
                localTime: 100,
                messageID: "deleted_search_message",
                clientMessageID: "deleted_search_client",
                sortSequence: 100
            )
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "search_filter_user",
                conversationID: "search_filter_conversation",
                senderID: "search_filter_user",
                text: "RevokeOnlyTerm",
                localTime: 101,
                messageID: "revoked_search_message",
                clientMessageID: "revoked_search_client",
                sortSequence: 101
            )
        )
        try await repository.markMessageDeleted(messageID: "deleted_search_message", userID: "search_filter_user")
        _ = try await repository.revokeMessage(
            messageID: "revoked_search_message",
            userID: "search_filter_user",
            replacementText: "你撤回了一条消息"
        )

        let searchIndex = SearchIndexActor(database: databaseContext.databaseActor, paths: databaseContext.paths)
        try await searchIndex.rebuildAll(userID: "search_filter_user")

        let deletedResults = try await searchIndex.search(query: "DeleteOnlyTerm", limit: 10)
        let revokedResults = try await searchIndex.search(query: "RevokeOnlyTerm", limit: 10)

        #expect(deletedResults.isEmpty)
        #expect(revokedResults.isEmpty)
    }

    @Test func localSearchUseCaseReturnsGroupedResults() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let databaseActor = DatabaseActor()
        let storeProvider = ChatStoreProvider(accountID: "search_usecase_user", storageService: storageService, database: databaseActor)
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(id: "usecase_search_conversation", userID: "search_usecase_user", title: "UseCase Bridge", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "search_usecase_user",
                conversationID: "usecase_search_conversation",
                senderID: "search_usecase_user",
                text: "UseCase message body",
                localTime: 200,
                messageID: "usecase_search_message",
                clientMessageID: "usecase_search_client",
                sortSequence: 200
            )
        )

        let useCase = LocalSearchUseCase(userID: "search_usecase_user", storeProvider: storeProvider)
        try await useCase.rebuildIndex()

        let bridgeResults = try await useCase.search(query: "UseCase")
        let messageResults = try await useCase.search(query: "body")

        #expect(bridgeResults.conversations.contains { $0.conversationID == "usecase_search_conversation" })
        #expect(messageResults.messages.contains { $0.messageID == "usecase_search_message" })
    }

    @Test func bundleContactCatalogReadsContactsForAccount() async throws {
        let catalog = BundleContactCatalog(resourceURL: try makeMockContactsFile())

        let contacts = try await catalog.contacts(for: "mock_user")

        #expect(contacts.map(\.contactID.rawValue) == ["contact_sondra", "group_core_contact"])
        #expect(contacts.first?.displayName == "Sondra")
        #expect(contacts.first?.type == .friend)
        #expect(contacts.last?.type == .group)
    }

    @Test func bundleDemoDataCatalogReadsAccountDataFromJSON() async throws {
        let catalog = BundleDemoDataCatalog(resourceURL: try makeMockDemoDataFile(messageCount: 3))

        let data = try await catalog.demoData(for: "mock_user", now: 10_000)

        #expect(data.conversations.map(\.id.rawValue) == ["single_sondra", "group_core", "system_release"])
        #expect(data.messages.map(\.messageID.rawValue) == [
            "seed_single_sondra_1",
            "seed_single_sondra_2",
            "seed_single_sondra_3"
        ])
        #expect(data.messages.first?.localTime == 9_998)
        #expect(data.messages.last?.sortSequence == 10_000)
        #expect(data.messages.last?.direction == .incoming)
        #expect(data.groupMembers.map(\.memberID.rawValue).contains("sondra"))
        #expect(data.groupAnnouncements.first?.conversationID == "group_core")
    }

    @Test func bundleDemoDataCatalogReturnsEmptyDataForUnknownAccount() async throws {
        let catalog = BundleDemoDataCatalog(resourceURL: try makeMockDemoDataFile(messageCount: 3))

        let data = try await catalog.demoData(for: "missing_user", now: 10_000)

        #expect(data.conversations.isEmpty)
        #expect(data.messages.isEmpty)
        #expect(data.groupMembers.isEmpty)
        #expect(data.groupAnnouncements.isEmpty)
    }

    @Test func bundleDemoDataCatalogRejectsInvalidMessageDirection() async throws {
        let catalog = BundleDemoDataCatalog(resourceURL: try makeMockDemoDataFile(
            messageCount: 1,
            firstMessageDirection: "sideways"
        ))

        await #expect(throws: DemoDataCatalogError.invalidMessageDirection("sideways")) {
            _ = try await catalog.demoData(for: "mock_user", now: 10_000)
        }
    }

    @Test func demoDataSeederSeedsContactsIdempotentlyWithoutOverwritingExistingRows() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "mock_user")
        try await repository.upsertContact(
            ContactRecord(
                contactID: "contact_sondra",
                userID: "mock_user",
                wxid: "sondra",
                nickname: "Existing Sondra",
                remark: "Do Not Replace",
                avatarURL: nil,
                type: .friend,
                isStarred: false,
                isBlocked: false,
                isDeleted: false,
                source: nil,
                extraJSON: nil,
                updatedAt: 1,
                createdAt: 1
            )
        )

        try await DemoDataSeeder.seedContactsIfNeeded(
            repository: repository,
            userID: "mock_user",
            catalog: BundleContactCatalog(resourceURL: try makeMockContactsFile())
        )
        try await DemoDataSeeder.seedContactsIfNeeded(
            repository: repository,
            userID: "mock_user",
            catalog: BundleContactCatalog(resourceURL: try makeMockContactsFile())
        )

        let contacts = try await repository.listContacts(for: "mock_user")
        let existing = try #require(contacts.first { $0.contactID == "contact_sondra" })

        #expect(contacts.count == 1)
        #expect(existing.displayName == "Do Not Replace")
        #expect(existing.isStarred == false)
    }

    @Test func demoDataSeederSeedsContactsFromJSONWhenAccountHasNoContacts() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "mock_user")

        try await DemoDataSeeder.seedContactsIfNeeded(
            repository: repository,
            userID: "mock_user",
            catalog: BundleContactCatalog(resourceURL: try makeMockContactsFile())
        )

        let contacts = try await repository.listContacts(for: "mock_user")

        #expect(contacts.map(\.contactID.rawValue) == ["contact_sondra", "group_core_contact"])
        #expect(contacts.first?.displayName == "Sondra")
        #expect(contacts.last?.type == .group)
    }

    @Test func demoDataSeederSeedsConversationsAndMessagesFromJSON() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "mock_user")

        try await DemoDataSeeder.seedIfNeeded(
            repository: repository,
            userID: "mock_user",
            catalog: BundleDemoDataCatalog(resourceURL: try makeMockDemoDataFile(messageCount: 120)),
            contactCatalog: BundleContactCatalog(resourceURL: try makeMockContactsFile())
        )
        try await DemoDataSeeder.seedIfNeeded(
            repository: repository,
            userID: "mock_user",
            catalog: BundleDemoDataCatalog(resourceURL: try makeMockDemoDataFile(messageCount: 120)),
            contactCatalog: BundleContactCatalog(resourceURL: try makeMockContactsFile())
        )

        let conversations = try await repository.listConversations(for: "mock_user")
        let storedMessages = try await repository.listMessages(
            conversationID: "single_sondra",
            limit: 200,
            beforeSortSeq: nil
        )
        let groupMembers = try await repository.groupMembers(conversationID: "group_core")

        #expect(conversations.map(\.id.rawValue).contains("single_sondra"))
        #expect(conversations.first { $0.id == "single_sondra" }?.lastMessageDigest == "Sondra JSON message 120")
        #expect(storedMessages.count == 120)
        #expect(try requireTextContent(storedMessages.first) == "Sondra JSON message 120")
        #expect(try requireTextContent(storedMessages.last) == "Sondra JSON message 1")
        #expect(groupMembers.map(\.memberID.rawValue).contains("sondra"))
    }

    @Test func chatStoreProviderSkipsDemoSeedWhenDisabled() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "mock_user",
            storageService: storageService,
            database: DatabaseActor(),
            demoDataCatalog: BundleDemoDataCatalog(resourceURL: try makeMockDemoDataFile(messageCount: 120)),
            shouldSeedDemoData: false
        )

        let repository = try await storeProvider.repository()
        let conversations = try await repository.listConversations(for: "mock_user")
        let contacts = try await repository.listContacts(for: "mock_user")

        #expect(conversations.isEmpty)
        #expect(contacts.isEmpty)
    }

    @Test func demoDataSeederSeedsUITestAccountAndConversationPageLoads() async throws {
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

        let page = try await useCase.loadConversationPage(limit: 50, after: nil)

        #expect(page.rows.map(\.id.rawValue).contains("single_sondra"))
        #expect(page.rows.map(\.title).contains("Sondra"))
    }

    @Test func localContactListUseCaseGroupsAndFiltersContacts() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "contacts_group_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertContact(makeContactRecord(contactID: "friend_normal", userID: "contacts_group_user", wxid: "normal", nickname: "Normal Friend"))
        try await repository.upsertContact(makeContactRecord(contactID: "friend_starred", userID: "contacts_group_user", wxid: "star", nickname: "Star Friend", isStarred: true))
        try await repository.upsertContact(makeContactRecord(contactID: "group_ios", userID: "contacts_group_user", wxid: "ios_group", nickname: "iOS Group", type: .group))
        try await repository.upsertContact(makeContactRecord(contactID: "deleted_friend", userID: "contacts_group_user", wxid: "deleted", nickname: "Deleted", isDeleted: true))

        let useCase = LocalContactListUseCase(userID: "contacts_group_user", storeProvider: storeProvider)
        let state = try await useCase.loadContacts(query: "")
        let filtered = try await useCase.loadContacts(query: "star")

        #expect(state.groupRows.map(\.title) == ["iOS Group"])
        #expect(state.starredRows.map(\.title) == ["Star Friend"])
        #expect(state.contactRows.map(\.title) == ["Normal Friend"])
        #expect(filtered.starredRows.map(\.title) == ["Star Friend"])
        #expect(filtered.contactRows.isEmpty)
        #expect(filtered.groupRows.isEmpty)
    }

    @MainActor
    @Test func contactListViewModelLoadsFiltersAndOpensContactConversation() async throws {
        let useCase = StubContactListUseCase()
        let viewModel = ContactListViewModel(useCase: useCase)

        viewModel.load()
        try await waitForCondition {
            viewModel.currentState.phase == .loaded
        }

        #expect(viewModel.currentState.contactRows.map(\.title) == ["Sondra"])

        viewModel.updateSearchQuery("son")
        try await waitForCondition {
            let queries = await useCase.queries
            return viewModel.currentState.query == "son" && queries.contains("son")
        }

        var openedConversation: ConversationListRowState?
        viewModel.open(row: ContactListRowState(contact: makeContactRecord(contactID: "contact_sondra", userID: "contact_vm_user", wxid: "sondra", nickname: "Sondra"))) {
            openedConversation = $0
        }
        try await waitForCondition {
            openedConversation?.id == "single_sondra"
        }
    }

    @Test func localContactListUseCaseCreatesSingleConversationForFriendAndReusesExistingConversation() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "contacts_open_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let repository = try await storeProvider.repository()
        let contact = makeContactRecord(contactID: "contact_new", userID: "contacts_open_user", wxid: "new_friend", nickname: "New Friend")
        try await repository.upsertContact(contact)

        let useCase = LocalContactListUseCase(userID: "contacts_open_user", storeProvider: storeProvider)
        let created = try await useCase.openConversation(for: contact.contactID)
        let reused = try await useCase.openConversation(for: contact.contactID)
        let conversations = try await repository.listConversations(for: "contacts_open_user")

        #expect(created.id == "single_new_friend")
        #expect(created.title == "New Friend")
        #expect(reused.id == created.id)
        #expect(conversations.filter { $0.id == "single_new_friend" }.count == 1)
    }

    @MainActor
    @Test func searchViewModelDebouncesAndIgnoresStaleResults() async throws {
        let useCase = StaleSearchUseCase()
        let viewModel = SearchViewModel(useCase: useCase, debounceMilliseconds: 5)

        viewModel.setQuery("old")
        try await Task.sleep(nanoseconds: 20_000_000)
        viewModel.setQuery("new")
        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(viewModel.currentState.phase == .loaded)
        #expect(viewModel.currentState.messages.map(\.title) == ["New Result"])
    }

    @Test func searchIndexFailureCreatesRepairPendingJob() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "search_failure_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "search_failure_conversation", userID: "search_failure_user", title: "Failure", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "search_failure_user",
                conversationID: "search_failure_conversation",
                senderID: "search_failure_user",
                text: "Repair me",
                localTime: 100,
                messageID: "search_failure_message",
                clientMessageID: "search_failure_client",
                sortSequence: 100
            )
        )
        try await waitForCondition {
            let rows = try await databaseContext.databaseActor.query(
                "SELECT COUNT(*) AS index_count FROM message_search WHERE message_id = ?;",
                parameters: [.text("search_failure_message")],
                in: .search,
                paths: databaseContext.paths
            )

            return rows.first?.int("index_count") == 1
        }
        try await waitForCondition {
            let rows = try await databaseContext.databaseActor.query(
                "SELECT COUNT(*) AS index_count FROM conversation_search WHERE conversation_id = ?;",
                parameters: [.text("search_failure_conversation")],
                in: .search,
                paths: databaseContext.paths
            )

            return rows.first?.int("index_count") == 1
        }
        try FileManager.default.removeItem(at: databaseContext.paths.searchDatabase)
        try FileManager.default.createDirectory(at: databaseContext.paths.searchDatabase, withIntermediateDirectories: false)

        let searchIndex = SearchIndexActor(database: databaseContext.databaseActor, paths: databaseContext.paths)
        await searchIndex.indexMessageBestEffort(messageID: "search_failure_message", userID: "search_failure_user")

        let repairJobs = try await repository.recoverablePendingJobs(userID: "search_failure_user", now: Int64.max)
            .filter { $0.type == .searchIndexRepair }

        #expect(repairJobs.count == 1)
        #expect(repairJobs.first?.bizKey == "message:search_failure_message")
    }

    @Test func databaseActorExecutesPreparedInsertAndQuery() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "prepared_user")

        try await databaseActor.execute(
            """
            INSERT INTO conversation (
                conversation_id,
                user_id,
                biz_type,
                target_id,
                title,
                last_message_digest,
                unread_count,
                is_pinned,
                is_muted,
                is_hidden,
                sort_ts
            ) VALUES (?, ?, ?, ?, ?, ?, 0, 0, 0, 0, ?);
            """,
            parameters: [
                .text("prepared_conversation"),
                .text("prepared_user"),
                .integer(Int64(ConversationType.single.rawValue)),
                .text("target"),
                .text("Sondra's SQLite"),
                .text("Prepared statement works"),
                .integer(100)
            ],
            paths: paths
        )

        let rows = try await databaseActor.query(
            "SELECT title FROM conversation WHERE conversation_id = ?;",
            parameters: [.text("prepared_conversation")],
            paths: paths
        )

        #expect(rows.first?.string("title") == "Sondra's SQLite")
    }

    @Test func conversationDAOListsPinnedThenNewestConversations() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "ordered_user")
        let dao = ConversationDAO(database: databaseActor, paths: paths)

        try await dao.upsert(makeConversationRecord(id: "normal_old", userID: "ordered_user", title: "Old", sortTimestamp: 10))
        try await dao.upsert(makeConversationRecord(id: "normal_new", userID: "ordered_user", title: "New", sortTimestamp: 30))
        try await dao.upsert(makeConversationRecord(id: "pinned_old", userID: "ordered_user", title: "Pinned", isPinned: true, sortTimestamp: 20))

        let records = try await dao.listConversations(for: "ordered_user")

        #expect(records.map(\.id.rawValue) == ["pinned_old", "normal_new", "normal_old"])
    }

    @Test func conversationDAOPagesVisibleConversationsAfterCursorWhenNewConversationMovesAhead() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "paged_user")
        let dao = ConversationDAO(database: databaseActor, paths: paths)

        try await dao.upsert(makeConversationRecord(id: "normal_older", userID: "paged_user", title: "Older", sortTimestamp: 10))
        try await dao.upsert(makeConversationRecord(id: "normal_old", userID: "paged_user", title: "Old", sortTimestamp: 10))
        try await dao.upsert(makeConversationRecord(id: "normal_new", userID: "paged_user", title: "New", sortTimestamp: 30))
        try await dao.upsert(makeConversationRecord(id: "pinned_old", userID: "paged_user", title: "Pinned", isPinned: true, sortTimestamp: 20))

        let firstPage = try await dao.listConversations(for: "paged_user", limit: 2, after: nil)
        try await dao.upsert(makeConversationRecord(id: "new_arrival", userID: "paged_user", title: "New Arrival", sortTimestamp: 100))
        let cursor = ConversationPageCursor(record: try #require(firstPage.last))
        let secondPage = try await dao.listConversations(for: "paged_user", limit: 2, after: cursor)

        #expect(firstPage.map(\.id.rawValue) == ["pinned_old", "normal_new"])
        #expect(secondPage.map(\.id.rawValue) == ["normal_older", "normal_old"])
    }

    @Test func conversationDAOPagesEqualSortTimestampByConversationIDDescending() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "tie_user")
        let dao = ConversationDAO(database: databaseActor, paths: paths)

        try await dao.upsert(makeConversationRecord(id: "same_a", userID: "tie_user", title: "A", sortTimestamp: 10))
        try await dao.upsert(makeConversationRecord(id: "same_c", userID: "tie_user", title: "C", sortTimestamp: 10))
        try await dao.upsert(makeConversationRecord(id: "same_b", userID: "tie_user", title: "B", sortTimestamp: 10))

        let firstPage = try await dao.listConversations(for: "tie_user", limit: 2, after: nil)
        let cursor = ConversationPageCursor(record: try #require(firstPage.last))
        let secondPage = try await dao.listConversations(for: "tie_user", limit: 2, after: cursor)

        #expect(firstPage.map(\.id.rawValue) == ["same_c", "same_b"])
        #expect(secondPage.map(\.id.rawValue) == ["same_a"])
    }

    @Test func conversationDAOFirstPageLoadsOneThousandConversationsUnderBudget() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "scale_user")
        let dao = ConversationDAO(database: databaseActor, paths: paths)

        for index in 0..<1_000 {
            let id = ConversationID(rawValue: String(format: "scale_%04d", index))
            try await dao.upsert(
                makeConversationRecord(
                    id: id,
                    userID: "scale_user",
                    title: "Scale \(index)",
                    isPinned: index == 0,
                    sortTimestamp: Int64(index)
                )
            )
        }

        let startedAt = Date()
        let firstPage = try await dao.listConversations(for: "scale_user", limit: 50, after: nil)
        let elapsed = Date().timeIntervalSince(startedAt)

        #expect(firstPage.count == 50)
        #expect(firstPage.first?.id == "scale_0000")
        #expect(firstPage.dropFirst().first?.id == "scale_0999")
        #expect(elapsed < 0.5)
    }

    @Test func localChatRepositoryInsertsOutgoingTextMessageInTransaction() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "message_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "message_conversation", userID: "message_user", title: "Message Target", sortTimestamp: 1)
        )

        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "message_user",
                conversationID: "message_conversation",
                senderID: "message_user",
                text: "Hello from the repository",
                localTime: 200,
                messageID: "message_1",
                clientMessageID: "client_1",
                sortSequence: 200
            )
        )
        let messages = try await repository.listMessages(conversationID: "message_conversation", limit: 20, beforeSortSeq: nil)
        let conversations = try await repository.listConversations(for: "message_user")

        #expect(message.state.sendStatus == .sending)
        #expect(messages.count == 1)
        #expect(try requireTextContent(messages.first) == "Hello from the repository")
        #expect(conversations.first?.lastMessageDigest == "Hello from the repository")
    }

    @Test func mediaFileActorStoresOriginalAndThumbnailInsideAccountDirectory() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (_, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "media_user")
        let mediaFileActor = await MediaFileActor(paths: paths)
        let storedFile = try await mediaFileActor.saveImage(data: samplePNGData(), preferredFileExtension: "png")

        #expect(storedFile.content.localPath.hasPrefix(paths.mediaDirectory.path))
        #expect(storedFile.content.thumbnailPath.hasPrefix(paths.mediaDirectory.path))
        #expect(FileManager.default.fileExists(atPath: storedFile.content.localPath))
        #expect(FileManager.default.fileExists(atPath: storedFile.content.thumbnailPath))
        #expect(storedFile.content.width == 1)
        #expect(storedFile.content.height == 1)
        #expect(storedFile.content.format == "png")
    }

    @Test func mediaFileActorDownsamplesOriginalAndThumbnailForLargeImages() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (_, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "large_media_user")
        let processingOptions = MediaImageProcessingOptions(
            originalMaxPixelSize: 256,
            originalCompressionQuality: 0.68,
            thumbnailMaxPixelSize: 64,
            thumbnailCompressionQuality: 0.62
        )
        let mediaFileActor = await MediaFileActor(paths: paths, processingOptions: processingOptions)
        let sourceData = makeJPEGData(width: 1_024, height: 768, quality: 0.98)
        let storedFile = try await mediaFileActor.saveImage(data: sourceData, preferredFileExtension: "jpg")

        let originalDimensions = imageDimensions(atPath: storedFile.content.localPath)
        let thumbnailDimensions = imageDimensions(atPath: storedFile.content.thumbnailPath)

        #expect(max(storedFile.content.width, storedFile.content.height) <= 256)
        #expect(max(originalDimensions.width, originalDimensions.height) <= 256)
        #expect(max(thumbnailDimensions.width, thumbnailDimensions.height) <= 64)
        #expect(storedFile.content.sizeBytes < Int64(sourceData.count))
        #expect(storedFile.content.format == "jpg")
    }

    @Test func mediaFileActorStoresVoiceInsideAccountDirectory() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (_, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "voice_media_user")
        let recordingURL = try makeVoiceRecordingFile(in: rootDirectory)
        let mediaFileActor = await MediaFileActor(paths: paths)
        let storedFile = try await mediaFileActor.saveVoice(
            recordingURL: recordingURL,
            durationMilliseconds: 1_500,
            preferredFileExtension: "m4a"
        )

        #expect(storedFile.content.localPath.hasPrefix(paths.mediaDirectory.appendingPathComponent("voice").path))
        #expect(FileManager.default.fileExists(atPath: storedFile.content.localPath))
        #expect(storedFile.content.durationMilliseconds == 1_500)
        #expect(storedFile.content.sizeBytes > 0)
        #expect(storedFile.content.format == "m4a")
    }

    @Test func mediaFileActorStoresVideoAndThumbnailInsideAccountDirectory() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (_, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "video_media_user")
        let sourceVideoURL = try await makeSampleVideoFile(in: rootDirectory)
        let mediaFileActor = await MediaFileActor(paths: paths)
        let storedFile = try await mediaFileActor.saveVideo(fileURL: sourceVideoURL, preferredFileExtension: "mov")

        #expect(storedFile.content.localPath.hasPrefix(paths.mediaDirectory.appendingPathComponent("video").path))
        #expect(storedFile.content.thumbnailPath.hasPrefix(paths.mediaDirectory.appendingPathComponent("video/thumb").path))
        #expect(FileManager.default.fileExists(atPath: storedFile.content.localPath))
        #expect(FileManager.default.fileExists(atPath: storedFile.content.thumbnailPath))
        #expect(storedFile.content.durationMilliseconds >= 0)
        #expect(storedFile.content.width == 64)
        #expect(storedFile.content.height == 64)
        #expect(storedFile.content.sizeBytes > 0)
    }

    @Test func localChatRepositoryInsertsOutgoingImageMessageInTransaction() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "image_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "image_conversation", userID: "image_user", title: "Image Target", sortTimestamp: 1)
        )

        let image = StoredImageContent(
            mediaID: "media_image_1",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image/original/media_image_1.png").path,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image/thumb/media_image_1.jpg").path,
            width: 120,
            height: 80,
            sizeBytes: 512,
            format: "png"
        )
        let message = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "image_user",
                conversationID: "image_conversation",
                senderID: "image_user",
                image: image,
                localTime: 500,
                messageID: "image_message_1",
                clientMessageID: "image_client_1",
                sortSequence: 500
            )
        )
        let messages = try await repository.listMessages(conversationID: "image_conversation", limit: 20, beforeSortSeq: nil)
        let contentRows = try await databaseContext.databaseActor.query(
            "SELECT COUNT(*) AS content_count FROM message_image WHERE content_id = ?;",
            parameters: [.text("image_image_message_1")],
            paths: databaseContext.paths
        )
        let conversations = try await repository.listConversations(for: "image_user")

        #expect(message.type == .image)
        #expect(message.state.sendStatus == .sending)
        #expect(try requireImageContent(message) == image)
        #expect(try requireImageContent(messages.first) == image)
        #expect(contentRows.first?.int("content_count") == 1)
        #expect(conversations.first?.lastMessageDigest == "[图片]")
    }

    @Test func localChatRepositoryInsertsOutgoingVoiceMessageInTransaction() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "voice_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "voice_conversation", userID: "voice_user", title: "Voice Target", sortTimestamp: 1)
        )

        let voice = StoredVoiceContent(
            mediaID: "media_voice_1",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("voice/media_voice_1.m4a").path,
            durationMilliseconds: 2_400,
            sizeBytes: 1_024,
            format: "m4a"
        )
        let message = try await repository.insertOutgoingVoiceMessage(
            OutgoingVoiceMessageInput(
                userID: "voice_user",
                conversationID: "voice_conversation",
                senderID: "voice_user",
                voice: voice,
                localTime: 510,
                messageID: "voice_message_1",
                clientMessageID: "voice_client_1",
                sortSequence: 510
            )
        )
        let messages = try await repository.listMessages(conversationID: "voice_conversation", limit: 20, beforeSortSeq: nil)
        let contentRows = try await databaseContext.databaseActor.query(
            "SELECT COUNT(*) AS content_count FROM message_voice WHERE content_id = ?;",
            parameters: [.text("voice_voice_message_1")],
            paths: databaseContext.paths
        )
        let resourceRows = try await databaseContext.databaseActor.query(
            "SELECT COUNT(*) AS resource_count FROM media_resource WHERE owner_message_id = ?;",
            parameters: [.text(message.id.rawValue)],
            paths: databaseContext.paths
        )
        let conversations = try await repository.listConversations(for: "voice_user")

        #expect(message.type == .voice)
        #expect(message.state.sendStatus == .sending)
        #expect(try requireVoiceContent(message) == voice)
        #expect(try requireVoiceContent(messages.first) == voice)
        #expect(contentRows.first?.int("content_count") == 1)
        #expect(resourceRows.first?.int("resource_count") == 1)
        #expect(conversations.first?.lastMessageDigest == "[语音]")
    }

    @Test func localChatRepositoryInsertsOutgoingVideoMessageInTransaction() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "video_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "video_conversation", userID: "video_user", title: "Video Target", sortTimestamp: 1)
        )

        let video = StoredVideoContent(
            mediaID: "media_video_1",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("video/media_video_1.mov").path,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("video/thumb/media_video_1.jpg").path,
            durationMilliseconds: 1_000,
            width: 64,
            height: 64,
            sizeBytes: 2_048
        )
        let message = try await repository.insertOutgoingVideoMessage(
            OutgoingVideoMessageInput(
                userID: "video_user",
                conversationID: "video_conversation",
                senderID: "video_user",
                video: video,
                localTime: 520,
                messageID: "video_message_1",
                clientMessageID: "video_client_1",
                sortSequence: 520
            )
        )
        let messages = try await repository.listMessages(conversationID: "video_conversation", limit: 20, beforeSortSeq: nil)
        let contentRows = try await databaseContext.databaseActor.query(
            "SELECT COUNT(*) AS content_count FROM message_video WHERE content_id = ?;",
            parameters: [.text("video_video_message_1")],
            paths: databaseContext.paths
        )
        let resourceRows = try await databaseContext.databaseActor.query(
            "SELECT COUNT(*) AS resource_count FROM media_resource WHERE owner_message_id = ?;",
            parameters: [.text(message.id.rawValue)],
            paths: databaseContext.paths
        )
        let conversations = try await repository.listConversations(for: "video_user")

        #expect(message.type == .video)
        #expect(message.state.sendStatus == .sending)
        #expect(try requireVideoContent(message) == video)
        #expect(try requireVideoContent(messages.first) == video)
        #expect(contentRows.first?.int("content_count") == 1)
        #expect(resourceRows.first?.int("resource_count") == 1)
        #expect(conversations.first?.lastMessageDigest == "[视频]")
    }

    @Test func localChatRepositoryInsertsOutgoingFileMessageInTransaction() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "file_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "file_conversation", userID: "file_user", title: "File Target", sortTimestamp: 1)
        )

        let file = StoredFileContent(
            mediaID: "media_file_1",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("file/report.pdf").path,
            fileName: "report.pdf",
            fileExtension: "pdf",
            sizeBytes: 4_096
        )
        let message = try await repository.insertOutgoingFileMessage(
            OutgoingFileMessageInput(
                userID: "file_user",
                conversationID: "file_conversation",
                senderID: "file_user",
                file: file,
                localTime: 530,
                messageID: "file_message_1",
                clientMessageID: "file_client_1",
                sortSequence: 530
            )
        )
        let messages = try await repository.listMessages(conversationID: "file_conversation", limit: 20, beforeSortSeq: nil)
        let contentRows = try await databaseContext.databaseActor.query(
            "SELECT COUNT(*) AS content_count FROM message_file WHERE content_id = ?;",
            parameters: [.text("file_file_message_1")],
            paths: databaseContext.paths
        )
        let conversations = try await repository.listConversations(for: "file_user")

        #expect(message.type == .file)
        #expect(message.state.sendStatus == .sending)
        #expect(try requireFileContent(message) == file)
        #expect(try requireFileContent(messages.first) == file)
        #expect(contentRows.first?.int("content_count") == 1)
        #expect(conversations.first?.lastMessageDigest == "[文件] report.pdf")
    }

    @Test func localChatRepositoryResolvesImagePathsAfterStorageRootMoves() async throws {
        let oldRootDirectory = temporaryDirectory()
        let newRootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: oldRootDirectory)
            try? FileManager.default.removeItem(at: newRootDirectory)
        }

        let accountID = UserID(rawValue: "image_move_user")
        let (oldRepository, oldDatabaseContext) = try await makeRepository(
            rootDirectory: oldRootDirectory,
            accountID: accountID
        )
        try await oldRepository.upsertConversation(
            makeConversationRecord(id: "image_move_conversation", userID: accountID, title: "Image Move", sortTimestamp: 1)
        )

        let image = StoredImageContent(
            mediaID: "media_image_move",
            localPath: oldDatabaseContext.paths.mediaDirectory.appendingPathComponent("image/original/media_image_move.png").path,
            thumbnailPath: oldDatabaseContext.paths.mediaDirectory.appendingPathComponent("image/thumb/media_image_move.jpg").path,
            width: 120,
            height: 80,
            sizeBytes: 512,
            format: "png"
        )
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: image.localPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: image.thumbnailPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: URL(fileURLWithPath: image.localPath))
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: URL(fileURLWithPath: image.thumbnailPath))
        _ = try await oldRepository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: accountID,
                conversationID: "image_move_conversation",
                senderID: accountID,
                image: image,
                localTime: 521,
                messageID: "image_move_message",
                clientMessageID: "image_move_client",
                sortSequence: 521
            )
        )

        try FileManager.default.createDirectory(at: newRootDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: oldDatabaseContext.paths.rootDirectory,
            to: newRootDirectory.appendingPathComponent(
                oldDatabaseContext.paths.rootDirectory.lastPathComponent,
                isDirectory: true
            )
        )
        try FileManager.default.removeItem(at: oldRootDirectory)

        let (newRepository, newDatabaseContext) = try await makeRepository(
            rootDirectory: newRootDirectory,
            accountID: accountID
        )
        let messages = try await newRepository.listMessages(
            conversationID: "image_move_conversation",
            limit: 20,
            beforeSortSeq: nil
        )
        let reloadedImage = try requireImageContent(messages.first)

        #expect(reloadedImage.localPath == newDatabaseContext.paths.mediaDirectory.appendingPathComponent("image/original/media_image_move.png").path)
        #expect(reloadedImage.thumbnailPath == newDatabaseContext.paths.mediaDirectory.appendingPathComponent("image/thumb/media_image_move.jpg").path)
    }

    @Test func localChatRepositoryResolvesVideoPathsAfterStorageRootMoves() async throws {
        let oldRootDirectory = temporaryDirectory()
        let newRootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: oldRootDirectory)
            try? FileManager.default.removeItem(at: newRootDirectory)
        }

        let accountID = UserID(rawValue: "video_move_user")
        let (oldRepository, oldDatabaseContext) = try await makeRepository(
            rootDirectory: oldRootDirectory,
            accountID: accountID
        )
        try await oldRepository.upsertConversation(
            makeConversationRecord(id: "video_move_conversation", userID: accountID, title: "Video Move", sortTimestamp: 1)
        )

        let video = StoredVideoContent(
            mediaID: "media_video_move",
            localPath: oldDatabaseContext.paths.mediaDirectory.appendingPathComponent("video/media_video_move.mov").path,
            thumbnailPath: oldDatabaseContext.paths.mediaDirectory.appendingPathComponent("video/thumb/media_video_move.jpg").path,
            durationMilliseconds: 1_000,
            width: 64,
            height: 64,
            sizeBytes: 2_048
        )
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: video.localPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: video.thumbnailPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("mov".utf8).write(to: URL(fileURLWithPath: video.localPath))
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: URL(fileURLWithPath: video.thumbnailPath))
        _ = try await oldRepository.insertOutgoingVideoMessage(
            OutgoingVideoMessageInput(
                userID: accountID,
                conversationID: "video_move_conversation",
                senderID: accountID,
                video: video,
                localTime: 522,
                messageID: "video_move_message",
                clientMessageID: "video_move_client",
                sortSequence: 522
            )
        )

        try FileManager.default.createDirectory(at: newRootDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: oldDatabaseContext.paths.rootDirectory,
            to: newRootDirectory.appendingPathComponent(
                oldDatabaseContext.paths.rootDirectory.lastPathComponent,
                isDirectory: true
            )
        )
        try FileManager.default.removeItem(at: oldRootDirectory)

        let (newRepository, newDatabaseContext) = try await makeRepository(
            rootDirectory: newRootDirectory,
            accountID: accountID
        )
        let messages = try await newRepository.listMessages(
            conversationID: "video_move_conversation",
            limit: 20,
            beforeSortSeq: nil
        )
        let reloadedVideo = try requireVideoContent(messages.first)

        #expect(reloadedVideo.localPath == newDatabaseContext.paths.mediaDirectory.appendingPathComponent("video/media_video_move.mov").path)
        #expect(reloadedVideo.thumbnailPath == newDatabaseContext.paths.mediaDirectory.appendingPathComponent("video/thumb/media_video_move.jpg").path)
    }

    @Test func localChatRepositoryIndexesOutgoingImageMediaFiles() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "image_index_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "image_index_conversation", userID: "image_index_user", title: "Image Index", sortTimestamp: 1)
        )

        let image = StoredImageContent(
            mediaID: "media_image_index",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image/original/media_image_index.png").path,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image/thumb/media_image_index.jpg").path,
            width: 120,
            height: 80,
            sizeBytes: 512,
            md5: "image-index-md5",
            format: "png"
        )
        _ = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "image_index_user",
                conversationID: "image_index_conversation",
                senderID: "image_index_user",
                image: image,
                localTime: 530,
                messageID: "image_index_message",
                clientMessageID: "image_index_client",
                sortSequence: 530
            )
        )

        let originalIndex = try await repository.mediaIndexRecord(mediaID: "media_image_index", userID: "image_index_user")
        let thumbnailIndex = try await repository.mediaIndexRecord(mediaID: "media_image_index_thumb", userID: "image_index_user")

        #expect(originalIndex?.localPath == image.localPath)
        #expect(originalIndex?.fileName == "media_image_index.png")
        #expect(originalIndex?.fileExtension == "png")
        #expect(originalIndex?.sizeBytes == 512)
        #expect(originalIndex?.md5 == "image-index-md5")
        #expect(thumbnailIndex?.localPath == image.thumbnailPath)
        #expect(thumbnailIndex?.fileName == "media_image_index.jpg")
        #expect(thumbnailIndex?.fileExtension == "jpg")
    }

    @Test func localChatRepositoryIndexesOutgoingVoiceMediaFile() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "voice_index_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "voice_index_conversation", userID: "voice_index_user", title: "Voice Index", sortTimestamp: 1)
        )

        let voice = StoredVoiceContent(
            mediaID: "media_voice_index",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("voice/media_voice_index.m4a").path,
            durationMilliseconds: 2_400,
            sizeBytes: 1_024,
            format: "m4a"
        )
        _ = try await repository.insertOutgoingVoiceMessage(
            OutgoingVoiceMessageInput(
                userID: "voice_index_user",
                conversationID: "voice_index_conversation",
                senderID: "voice_index_user",
                voice: voice,
                localTime: 540,
                messageID: "voice_index_message",
                clientMessageID: "voice_index_client",
                sortSequence: 540
            )
        )

        let voiceIndex = try await repository.mediaIndexRecord(mediaID: "media_voice_index", userID: "voice_index_user")

        #expect(voiceIndex?.localPath == voice.localPath)
        #expect(voiceIndex?.fileName == "media_voice_index.m4a")
        #expect(voiceIndex?.fileExtension == "m4a")
        #expect(voiceIndex?.sizeBytes == 1_024)
    }

    @Test func localChatRepositoryEnqueuesDownloadJobForMissingMediaWithoutDuplication() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "missing_media_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "missing_media_conversation", userID: "missing_media_user", title: "Missing Media", sortTimestamp: 1)
        )

        let missingLocalPath = databaseContext.paths.mediaDirectory.appendingPathComponent("image/original/missing_media.png").path
        let image = StoredImageContent(
            mediaID: "missing_media",
            localPath: missingLocalPath,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image/thumb/missing_media.jpg").path,
            width: 120,
            height: 80,
            sizeBytes: 512,
            format: "png"
        )
        _ = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "missing_media_user",
                conversationID: "missing_media_conversation",
                senderID: "missing_media_user",
                image: image,
                localTime: 550,
                messageID: "missing_media_message",
                clientMessageID: "missing_media_client",
                sortSequence: 550
            )
        )
        try await databaseContext.databaseActor.execute(
            """
            UPDATE media_resource
            SET remote_url = ?, download_status = ?
            WHERE media_id = ?;
            """,
            parameters: [
                .text("https://mock-cdn.chatbridge.local/image/missing_media"),
                .integer(Int64(MediaUploadStatus.success.rawValue)),
                .text("missing_media")
            ],
            paths: databaseContext.paths
        )

        let missingResources = try await repository.scanMissingMediaResources(userID: "missing_media_user")
        let firstJobs = try await repository.enqueueMediaDownloadJobsForMissingResources(userID: "missing_media_user")
        let secondJobs = try await repository.enqueueMediaDownloadJobsForMissingResources(userID: "missing_media_user")
        let pendingJobRows = try await databaseContext.databaseActor.query(
            "SELECT COUNT(*) AS job_count FROM pending_job WHERE job_type = ?;",
            parameters: [.integer(Int64(PendingJobType.mediaDownload.rawValue))],
            paths: databaseContext.paths
        )
        let resourceRows = try await databaseContext.databaseActor.query(
            "SELECT download_status FROM media_resource WHERE media_id = ?;",
            parameters: [.text("missing_media")],
            paths: databaseContext.paths
        )

        #expect(missingResources.map(\.mediaID) == ["missing_media"])
        #expect(firstJobs.count == 1)
        #expect(firstJobs.first?.id == "media_download_missing_media")
        #expect(firstJobs.first?.type == .mediaDownload)
        #expect(firstJobs.first?.payloadJSON.contains(#""localPath":"\#(missingLocalPath)""#) == true)
        #expect(secondJobs.count == 1)
        #expect(pendingJobRows.first?.int("job_count") == 1)
        #expect(resourceRows.first?.int("download_status") == MediaUploadStatus.pending.rawValue)
    }

    @Test func databaseIntegrityCheckReturnsOKForAllDatabases() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "integrity_user")

        let results = try await databaseActor.integrityCheck(paths: paths)

        #expect(results.map(\.database) == DatabaseFileKind.allCases)
        #expect(results.allSatisfy { $0.isOK })
    }

    @Test func dataRepairRebuildsClearedFTSIndex() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "repair_search_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "repair_search_conversation", userID: "repair_search_user", title: "Repair Search", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "repair_search_user",
                conversationID: "repair_search_conversation",
                senderID: "repair_search_user",
                text: "Repairable FTS body",
                localTime: 560,
                messageID: "repair_search_message",
                clientMessageID: "repair_search_client",
                sortSequence: 560
            )
        )
        try await waitForCondition {
            let rows = try await databaseContext.databaseActor.query(
                "SELECT COUNT(*) AS index_count FROM message_search WHERE message_id = ?;",
                parameters: [.text("repair_search_message")],
                in: .search,
                paths: databaseContext.paths
            )

            return rows.first?.int("index_count") == 1
        }
        try await databaseContext.databaseActor.performTransaction(
            [
                SQLiteStatement("DELETE FROM contact_search;"),
                SQLiteStatement("DELETE FROM conversation_search;"),
                SQLiteStatement("DELETE FROM message_search;")
            ],
            in: .search,
            paths: databaseContext.paths
        )

        let searchIndex = SearchIndexActor(database: databaseContext.databaseActor, paths: databaseContext.paths)
        let emptyResults = try await searchIndex.search(query: "Repairable", limit: 10)
        let repairService = DataRepairService(
            userID: "repair_search_user",
            database: databaseContext.databaseActor,
            paths: databaseContext.paths,
            repository: repository,
            searchIndex: searchIndex
        )

        let report = await repairService.run()
        let repairedResults = try await searchIndex.search(query: "Repairable", limit: 10)
        let metadata = try await databaseContext.databaseActor.loadMigrationMetadata(paths: databaseContext.paths)

        #expect(emptyResults.isEmpty)
        #expect(report.steps.first { $0.step == .ftsRebuild }?.isSuccessful == true)
        #expect(report.isSuccessful)
        #expect(repairedResults.contains { $0.kind == .message && $0.messageID == "repair_search_message" })
        #expect(metadata.ftsRebuildVersion == 1)
        #expect(metadata.lastIntegrityCheckAt != nil)
    }

    @Test func startupDataRepairSkipsWhenMaintenanceMetadataExists() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "repair_skip_user")
        let searchIndex = SearchIndexActor(database: databaseContext.databaseActor, paths: databaseContext.paths)
        let repairService = DataRepairService(
            userID: "repair_skip_user",
            database: databaseContext.databaseActor,
            paths: databaseContext.paths,
            repository: repository,
            searchIndex: searchIndex
        )

        _ = await repairService.run()
        let skippedReport = await repairService.runStartupIfNeeded()

        #expect(skippedReport == nil)
    }

    @Test func mediaIndexRebuildRestoresExistingImageAndVoiceFiles() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "repair_media_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "repair_media_conversation", userID: "repair_media_user", title: "Repair Media", sortTimestamp: 1)
        )
        let imageDirectory = databaseContext.paths.mediaDirectory.appendingPathComponent("image/original", isDirectory: true)
        let thumbnailDirectory = databaseContext.paths.mediaDirectory.appendingPathComponent("image/thumb", isDirectory: true)
        let voiceDirectory = databaseContext.paths.mediaDirectory.appendingPathComponent("voice", isDirectory: true)
        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: voiceDirectory, withIntermediateDirectories: true)
        let imageURL = imageDirectory.appendingPathComponent("repair_image.png")
        let thumbnailURL = thumbnailDirectory.appendingPathComponent("repair_image.jpg")
        let voiceURL = voiceDirectory.appendingPathComponent("repair_voice.m4a")
        try Data("image".utf8).write(to: imageURL, options: [.atomic])
        try Data("thumb".utf8).write(to: thumbnailURL, options: [.atomic])
        try Data("voice".utf8).write(to: voiceURL, options: [.atomic])

        _ = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "repair_media_user",
                conversationID: "repair_media_conversation",
                senderID: "repair_media_user",
                image: StoredImageContent(
                    mediaID: "repair_image",
                    localPath: imageURL.path,
                    thumbnailPath: thumbnailURL.path,
                    width: 120,
                    height: 80,
                    sizeBytes: 5,
                    md5: "repair-md5",
                    format: "png"
                ),
                localTime: 570,
                messageID: "repair_image_message",
                clientMessageID: "repair_image_client",
                sortSequence: 570
            )
        )
        _ = try await repository.insertOutgoingVoiceMessage(
            OutgoingVoiceMessageInput(
                userID: "repair_media_user",
                conversationID: "repair_media_conversation",
                senderID: "repair_media_user",
                voice: StoredVoiceContent(
                    mediaID: "repair_voice",
                    localPath: voiceURL.path,
                    durationMilliseconds: 2_000,
                    sizeBytes: 5,
                    format: "m4a"
                ),
                localTime: 571,
                messageID: "repair_voice_message",
                clientMessageID: "repair_voice_client",
                sortSequence: 571
            )
        )
        try await databaseContext.databaseActor.execute(
            "DELETE FROM file_index WHERE user_id = ?;",
            parameters: [.text("repair_media_user")],
            in: .fileIndex,
            paths: databaseContext.paths
        )

        let result = try await repository.rebuildMediaIndex(userID: "repair_media_user")
        let imageIndex = try await repository.mediaIndexRecord(mediaID: "repair_image", userID: "repair_media_user")
        let thumbnailIndex = try await repository.mediaIndexRecord(mediaID: "repair_image_thumb", userID: "repair_media_user")
        let voiceIndex = try await repository.mediaIndexRecord(mediaID: "repair_voice", userID: "repair_media_user")

        #expect(result == MediaIndexRebuildResult(scannedResourceCount: 2, rebuiltIndexCount: 3, missingResourceCount: 0, createdDownloadJobCount: 0))
        #expect(imageIndex?.localPath == imageURL.path)
        #expect(imageIndex?.md5 == "repair-md5")
        #expect(thumbnailIndex?.localPath == thumbnailURL.path)
        #expect(voiceIndex?.localPath == voiceURL.path)
    }

    @Test func dataRepairCreatesDownloadJobForMissingMedia() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "repair_missing_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "repair_missing_conversation", userID: "repair_missing_user", title: "Repair Missing", sortTimestamp: 1)
        )
        let missingLocalPath = databaseContext.paths.mediaDirectory.appendingPathComponent("image/original/repair_missing.png").path
        _ = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "repair_missing_user",
                conversationID: "repair_missing_conversation",
                senderID: "repair_missing_user",
                image: StoredImageContent(
                    mediaID: "repair_missing",
                    localPath: missingLocalPath,
                    thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image/thumb/repair_missing.jpg").path,
                    width: 64,
                    height: 64,
                    sizeBytes: 128,
                    format: "png"
                ),
                localTime: 580,
                messageID: "repair_missing_message",
                clientMessageID: "repair_missing_client",
                sortSequence: 580
            )
        )
        try await databaseContext.databaseActor.execute(
            """
            UPDATE media_resource
            SET remote_url = ?
            WHERE media_id = ?;
            """,
            parameters: [
                .text("https://mock-cdn.chatbridge.local/image/repair_missing"),
                .text("repair_missing")
            ],
            paths: databaseContext.paths
        )

        let repairService = DataRepairService(
            userID: "repair_missing_user",
            database: databaseContext.databaseActor,
            paths: databaseContext.paths,
            repository: repository,
            searchIndex: SearchIndexActor(database: databaseContext.databaseActor, paths: databaseContext.paths)
        )

        let report = await repairService.run()
        let job = try await repository.pendingJob(id: "media_download_repair_missing")

        #expect(report.mediaIndexRebuildResult?.missingResourceCount == 1)
        #expect(report.mediaIndexRebuildResult?.createdDownloadJobCount == 1)
        #expect(job?.type == .mediaDownload)
        #expect(job?.payloadJSON.contains(#""remoteURL":"https://mock-cdn.chatbridge.local/image/repair_missing""#) == true)
    }

    @Test func dataRepairReportsFailureWithoutThrowing() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "repair_failure_user")
        try FileManager.default.removeItem(at: databaseContext.paths.searchDatabase)
        try FileManager.default.createDirectory(at: databaseContext.paths.searchDatabase, withIntermediateDirectories: false)
        let repairService = DataRepairService(
            userID: "repair_failure_user",
            database: databaseContext.databaseActor,
            paths: databaseContext.paths,
            repository: repository,
            searchIndex: SearchIndexActor(database: databaseContext.databaseActor, paths: databaseContext.paths)
        )

        let report = await repairService.run()

        #expect(report.isSuccessful == false)
        #expect(report.steps.contains { $0.step == .integrityCheck && !$0.isSuccessful })
        #expect(report.steps.contains { $0.step == .ftsRebuild && !$0.isSuccessful })
        #expect(report.steps.contains { $0.step == .mediaIndexRebuild && $0.isSuccessful })
    }

    @Test func localChatRepositoryMarksVoiceMessagePlayed() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "voice_play_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "voice_play_conversation", userID: "voice_play_user", title: "Voice Play", sortTimestamp: 1)
        )

        let voice = StoredVoiceContent(
            mediaID: "media_voice_play",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("voice/media_voice_play.m4a").path,
            durationMilliseconds: 2_000,
            sizeBytes: 512,
            format: "m4a"
        )
        let message = try await repository.insertOutgoingVoiceMessage(
            OutgoingVoiceMessageInput(
                userID: "voice_play_user",
                conversationID: "voice_play_conversation",
                senderID: "friend_user",
                voice: voice,
                localTime: 520,
                messageID: "voice_play_message",
                clientMessageID: "voice_play_client",
                sortSequence: 520
            )
        )
        try await databaseContext.databaseActor.execute(
            "UPDATE message SET read_status = ? WHERE message_id = ?;",
            parameters: [
                .integer(Int64(MessageReadStatus.unread.rawValue)),
                .text(message.id.rawValue)
            ],
            paths: databaseContext.paths
        )

        let unreadMessage = try await repository.message(messageID: message.id)
        try await repository.markVoicePlayed(messageID: message.id)
        let playedMessage = try await repository.message(messageID: message.id)

        #expect(unreadMessage?.state.readStatus == .unread)
        #expect(playedMessage?.state.readStatus == .read)
    }

    @Test func chatUseCaseSendImageYieldsProgressThenSuccess() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "image_send_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "image_send_conversation", userID: "image_send_user", title: "Image Send", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let useCase = LocalChatUseCase(
            userID: "image_send_user",
            conversationID: "image_send_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [0.25, 0.75, 1.0], delayNanoseconds: 0)
        )

        let rows = try await collectRows(from: useCase.sendImage(data: samplePNGData(), preferredFileExtension: "png"))
        let messageID = try #require(rows.first?.id)
        let storedMessage = try await repository.message(messageID: messageID)
        let imageRows = try await databaseContext.databaseActor.query(
            "SELECT cdn_url, upload_status FROM message_image WHERE content_id = ?;",
            parameters: [.text("image_\(messageID.rawValue)")],
            paths: databaseContext.paths
        )
        let resourceRows = try await databaseContext.databaseActor.query(
            "SELECT remote_url, upload_status FROM media_resource WHERE owner_message_id = ?;",
            parameters: [.text(messageID.rawValue)],
            paths: databaseContext.paths
        )

        #expect(rows.first?.statusText == "Sending")
        #expect(rows.compactMap(\.uploadProgress) == [0.25, 0.75, 1.0])
        #expect(rows.last?.statusText == nil)
        let storedImage = try requireImageContent(storedMessage)
        #expect(storedMessage?.state.sendStatus == .success)
        #expect(storedImage.remoteURL?.contains("mock-cdn.chatbridge.local") == true)
        #expect(imageRows.first?.int("upload_status") == MediaUploadStatus.success.rawValue)
        #expect(imageRows.first?.string("cdn_url") == storedImage.remoteURL)
        #expect(resourceRows.first?.int("upload_status") == MediaUploadStatus.success.rawValue)
        #expect(resourceRows.first?.string("remote_url") == storedImage.remoteURL)
    }

    @Test func chatUseCaseSendVoiceYieldsProgressThenSuccess() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "voice_send_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "voice_send_conversation", userID: "voice_send_user", title: "Voice Send", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let useCase = LocalChatUseCase(
            userID: "voice_send_user",
            conversationID: "voice_send_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [0.3, 0.6, 1.0], delayNanoseconds: 0)
        )

        let rows = try await collectRows(
            from: useCase.sendVoice(
                recording: VoiceRecordingFile(
                    fileURL: try makeVoiceRecordingFile(in: rootDirectory),
                    durationMilliseconds: 1_800,
                    fileExtension: "m4a"
                )
            )
        )
        let messageID = try #require(rows.first?.id)
        let storedMessage = try await repository.message(messageID: messageID)
        let voiceRows = try await databaseContext.databaseActor.query(
            "SELECT cdn_url, upload_status FROM message_voice WHERE content_id = ?;",
            parameters: [.text("voice_\(messageID.rawValue)")],
            paths: databaseContext.paths
        )

        #expect(rows.first?.statusText == "Sending")
        #expect(rows.first.map(isVoiceContent) == true)
        #expect(rows.compactMap(\.uploadProgress) == [0.3, 0.6, 1.0])
        #expect(rows.last?.statusText == nil)
        let storedVoice = try requireVoiceContent(storedMessage)
        #expect(storedMessage?.state.sendStatus == .success)
        #expect(storedVoice.remoteURL?.contains("mock-cdn.chatbridge.local/voice") == true)
        #expect(voiceRows.first?.int("upload_status") == MediaUploadStatus.success.rawValue)
        #expect(voiceRows.first?.string("cdn_url") == storedVoice.remoteURL)
    }

    @Test func chatUseCaseSendVideoYieldsProgressThenSuccess() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "video_send_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "video_send_conversation", userID: "video_send_user", title: "Video Send", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let useCase = LocalChatUseCase(
            userID: "video_send_user",
            conversationID: "video_send_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [0.2, 0.8, 1.0], delayNanoseconds: 0)
        )

        let rows = try await collectRows(
            from: useCase.sendVideo(
                fileURL: try await makeSampleVideoFile(in: rootDirectory),
                preferredFileExtension: "mov"
            )
        )
        let messageID = try #require(rows.first?.id)
        let storedMessage = try await repository.message(messageID: messageID)
        let videoRows = try await databaseContext.databaseActor.query(
            "SELECT cdn_url, upload_status FROM message_video WHERE content_id = ?;",
            parameters: [.text("video_\(messageID.rawValue)")],
            paths: databaseContext.paths
        )

        #expect(rows.first?.statusText == "Sending")
        #expect(rows.first.map(isVideoContent) == true)
        #expect(rows.first.flatMap(videoThumbnailPath) != nil)
        #expect(rows.compactMap(\.uploadProgress) == [0.2, 0.8, 1.0])
        #expect(rows.last?.statusText == nil)
        let storedVideo = try requireVideoContent(storedMessage)
        #expect(storedMessage?.state.sendStatus == .success)
        #expect(storedVideo.remoteURL?.contains("mock-cdn.chatbridge.local/video") == true)
        #expect(videoRows.first?.int("upload_status") == MediaUploadStatus.success.rawValue)
        #expect(videoRows.first?.string("cdn_url") == storedVideo.remoteURL)
    }

    @Test func chatUseCaseDoesNotSendTooShortVoice() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "short_voice_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "short_voice_conversation", userID: "short_voice_user", title: "Short Voice", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let useCase = LocalChatUseCase(
            userID: "short_voice_user",
            conversationID: "short_voice_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [1.0], delayNanoseconds: 0)
        )

        let rows = try await collectRows(
            from: useCase.sendVoice(
                recording: VoiceRecordingFile(
                    fileURL: try makeVoiceRecordingFile(in: rootDirectory),
                    durationMilliseconds: 600,
                    fileExtension: "m4a"
                )
            )
        )
        let messages = try await repository.listMessages(conversationID: "short_voice_conversation", limit: 20, beforeSortSeq: nil)

        #expect(rows.isEmpty)
        #expect(messages.isEmpty)
    }

    @Test func chatUseCaseQueuesImageUploadJobWhenUploadFailsAndResendsWithoutDuplication() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "image_retry_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "image_retry_conversation", userID: "image_retry_user", title: "Image Retry", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let failingUseCase = LocalChatUseCase(
            userID: "image_retry_user",
            conversationID: "image_retry_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(result: .failed(.timeout), progressSteps: [0.4], delayNanoseconds: 0)
        )

        let failedRows = try await collectRows(from: failingUseCase.sendImage(data: samplePNGData(), preferredFileExtension: "png"))
        let failedMessageID = try #require(failedRows.first?.id)
        let failedMessage = try await repository.message(messageID: failedMessageID)
        let recoverableJobs = try await repository.recoverablePendingJobs(userID: "image_retry_user", now: Int64.max)

        let retryingUseCase = LocalChatUseCase(
            userID: "image_retry_user",
            conversationID: "image_retry_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [1.0], delayNanoseconds: 0)
        )
        let retryRows = try await collectRows(from: retryingUseCase.resend(messageID: failedMessageID))
        let storedMessages = try await repository.listMessages(conversationID: "image_retry_conversation", limit: 20, beforeSortSeq: nil)
        let resentMessage = try await repository.message(messageID: failedMessageID)
        let retryJob = try await repository.pendingJob(id: "image_upload_\(failedMessage?.delivery.clientMessageID ?? "")")

        #expect(failedRows.last?.statusText == "Failed")
        #expect(failedRows.last?.canRetry == true)
        #expect(failedMessage?.state.sendStatus == .failed)
        #expect(try requireImageContent(failedMessage).uploadStatus == .failed)
        #expect(recoverableJobs.count == 1)
        #expect(recoverableJobs.first?.type == .imageUpload)
        #expect(recoverableJobs.first?.payloadJSON.contains("timeout") == true)
        #expect(retryRows.last?.statusText == nil)
        #expect(storedMessages.count == 1)
        #expect(resentMessage?.state.sendStatus == .success)
        #expect(retryJob?.status == .success)
    }

    @Test func chatUseCaseQueuesVideoUploadJobWhenUploadFailsAndResendsWithoutDuplication() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "video_retry_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "video_retry_conversation", userID: "video_retry_user", title: "Video Retry", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let failingUseCase = LocalChatUseCase(
            userID: "video_retry_user",
            conversationID: "video_retry_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(result: .failed(.timeout), progressSteps: [0.4], delayNanoseconds: 0)
        )

        let failedRows = try await collectRows(
            from: failingUseCase.sendVideo(
                fileURL: try await makeSampleVideoFile(in: rootDirectory),
                preferredFileExtension: "mov"
            )
        )
        let failedMessageID = try #require(failedRows.first?.id)
        let failedMessage = try await repository.message(messageID: failedMessageID)
        let recoverableJobs = try await repository.recoverablePendingJobs(userID: "video_retry_user", now: Int64.max)

        let retryingUseCase = LocalChatUseCase(
            userID: "video_retry_user",
            conversationID: "video_retry_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [1.0], delayNanoseconds: 0)
        )
        let retryRows = try await collectRows(from: retryingUseCase.resend(messageID: failedMessageID))
        let storedMessages = try await repository.listMessages(conversationID: "video_retry_conversation", limit: 20, beforeSortSeq: nil)
        let resentMessage = try await repository.message(messageID: failedMessageID)
        let retryJob = try await repository.pendingJob(id: "video_upload_\(failedMessage?.delivery.clientMessageID ?? "")")

        #expect(failedRows.last?.statusText == "Failed")
        #expect(failedRows.last?.canRetry == true)
        #expect(failedMessage?.state.sendStatus == .failed)
        #expect(try requireVideoContent(failedMessage).uploadStatus == .failed)
        #expect(recoverableJobs.count == 1)
        #expect(recoverableJobs.first?.type == .videoUpload)
        #expect(recoverableJobs.first?.payloadJSON.contains("timeout") == true)
        #expect(retryRows.last?.statusText == nil)
        #expect(storedMessages.count == 1)
        #expect(resentMessage?.state.sendStatus == .success)
        #expect(retryJob?.status == .success)
    }

    @Test func chatUseCasePersistsServerAckForImageAndVideoSends() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "media_server_ack_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "media_server_ack_conversation", userID: "media_server_ack_user", title: "Media Ack", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let service = ServerMessageSendService(
            httpClient: RecordingHTTPClient(
                response: ServerTextMessageSendResponse(
                    serverMessageID: "server_media_message",
                    sequence: 919,
                    serverTime: 1_777_777_919
                )
            )
        )
        let useCase = LocalChatUseCase(
            userID: "media_server_ack_user",
            conversationID: "media_server_ack_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: service,
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [1.0], delayNanoseconds: 0)
        )

        let imageRows = try await collectRows(from: useCase.sendImage(data: samplePNGData(), preferredFileExtension: "png"))
        let videoRows = try await collectRows(
            from: useCase.sendVideo(
                fileURL: try await makeSampleVideoFile(in: rootDirectory),
                preferredFileExtension: "mov"
            )
        )
        let imageMessage = try await repository.message(messageID: try #require(imageRows.first?.id))
        let videoMessage = try await repository.message(messageID: try #require(videoRows.first?.id))

        #expect(imageRows.last?.statusText == nil)
        #expect(videoRows.last?.statusText == nil)
        #expect(imageMessage?.state.sendStatus == .success)
        #expect(videoMessage?.state.sendStatus == .success)
        #expect(imageMessage?.delivery.serverMessageID == "server_media_message")
        #expect(videoMessage?.delivery.serverMessageID == "server_media_message")
        #expect(imageMessage?.delivery.sequence == 919)
        #expect(videoMessage?.delivery.sequence == 919)
        #expect(try requireImageContent(imageMessage).remoteURL?.contains("mock-cdn.chatbridge.local/image") == true)
        #expect(try requireVideoContent(videoMessage).remoteURL?.contains("mock-cdn.chatbridge.local/video") == true)
    }

    @Test func chatUseCaseQueuesMediaUploadJobWhenServerMediaSendFailsAfterUpload() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "media_server_fail_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "media_server_fail_conversation", userID: "media_server_fail_user", title: "Media Fail", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let useCase = LocalChatUseCase(
            userID: "media_server_fail_user",
            conversationID: "media_server_fail_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: ServerMessageSendService(httpClient: RecordingHTTPClient(error: ChatBridgeHTTPError.timeout)),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [1.0], delayNanoseconds: 0),
            retryPolicy: MessageRetryPolicy(initialDelaySeconds: 2, maxDelaySeconds: 10, maxRetryCount: 3)
        )

        let imageRows = try await collectRows(from: useCase.sendImage(data: samplePNGData(), preferredFileExtension: "png"))
        let videoRows = try await collectRows(
            from: useCase.sendVideo(
                fileURL: try await makeSampleVideoFile(in: rootDirectory),
                preferredFileExtension: "mov"
            )
        )
        let imageMessage = try await repository.message(messageID: try #require(imageRows.first?.id))
        let videoMessage = try await repository.message(messageID: try #require(videoRows.first?.id))
        let imageJob = try await repository.pendingJob(id: "image_upload_\(imageMessage?.delivery.clientMessageID ?? "")")
        let videoJob = try await repository.pendingJob(id: "video_upload_\(videoMessage?.delivery.clientMessageID ?? "")")

        #expect(imageRows.last?.statusText == "Failed")
        #expect(videoRows.last?.statusText == "Failed")
        let uploadedImage = try requireImageContent(imageMessage)
        let uploadedVideo = try requireVideoContent(videoMessage)
        #expect(imageMessage?.state.sendStatus == .failed)
        #expect(videoMessage?.state.sendStatus == .failed)
        #expect(uploadedImage.uploadStatus == .failed)
        #expect(uploadedVideo.uploadStatus == .failed)
        #expect(uploadedImage.remoteURL?.contains("mock-cdn.chatbridge.local/image") == true)
        #expect(uploadedVideo.remoteURL?.contains("mock-cdn.chatbridge.local/video") == true)
        #expect(imageJob?.type == .imageUpload)
        #expect(videoJob?.type == .videoUpload)
        #expect(imageJob?.payloadJSON.contains("timeout") == true)
        #expect(videoJob?.payloadJSON.contains("timeout") == true)
    }

    @Test func localChatRepositoryRollsBackWhenMessageInsertFails() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "rollback_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "rollback_conversation", userID: "rollback_user", title: "Rollback", sortTimestamp: 1)
        )

        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "rollback_user",
                conversationID: "rollback_conversation",
                senderID: "rollback_user",
                text: "Original",
                localTime: 300,
                messageID: "rollback_original",
                clientMessageID: "same_client",
                sortSequence: 300
            )
        )

        var didThrow = false

        do {
            _ = try await repository.insertOutgoingTextMessage(
                OutgoingTextMessageInput(
                    userID: "rollback_user",
                    conversationID: "rollback_conversation",
                    senderID: "rollback_user",
                    text: "Duplicate",
                    localTime: 301,
                    messageID: "rollback_duplicate",
                    clientMessageID: "same_client",
                    sortSequence: 301
                )
            )
        } catch {
            didThrow = true
        }

        let leakedContentRows = try await databaseContext.databaseActor.query(
            "SELECT COUNT(*) AS content_count FROM message_text WHERE content_id = ?;",
            parameters: [.text("text_rollback_duplicate")],
            paths: databaseContext.paths
        )
        let conversations = try await repository.listConversations(for: "rollback_user")

        #expect(didThrow)
        #expect(leakedContentRows.first?.int("content_count") == 0)
        #expect(conversations.first?.lastMessageDigest == "Original")
    }

    @Test func localConversationListUseCaseMapsRepositoryRows() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "usecase_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let useCase = LocalConversationListUseCase(userID: "usecase_user", storeProvider: storeProvider)

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
            accountID: "paged_usecase_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let useCase = LocalConversationListUseCase(userID: "paged_usecase_user", storeProvider: storeProvider)

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
            accountID: "conversation_setting_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let useCase = LocalConversationListUseCase(userID: "conversation_setting_user", storeProvider: storeProvider)

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
            accountID: "conversation_list_sim_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let useCase = LocalConversationListUseCase(userID: "conversation_list_sim_user", storeProvider: storeProvider)
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

    @Test func localChatRepositoryStoresGroupMembersAndAnnouncementPermissions() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "group_repo_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "group_repo_conversation", userID: "group_repo_user", type: .group, targetID: "group_repo")
        )
        try await repository.upsertGroupMembers(
            [
                GroupMember(conversationID: "group_repo_conversation", memberID: "group_repo_user", displayName: "Me", role: .owner, joinTime: 100),
                GroupMember(conversationID: "group_repo_conversation", memberID: "admin_user", displayName: "Admin", role: .admin, joinTime: 101),
                GroupMember(conversationID: "group_repo_conversation", memberID: "member_user", displayName: "Member", role: .member, joinTime: 102)
            ]
        )

        let members = try await repository.groupMembers(conversationID: "group_repo_conversation")
        try await repository.updateGroupAnnouncement(
            conversationID: "group_repo_conversation",
            userID: "admin_user",
            text: "本周联调重点：群聊 P1。"
        )
        let announcement = try await repository.groupAnnouncement(conversationID: "group_repo_conversation")

        #expect(members.map(\.memberID) == ["group_repo_user", "admin_user", "member_user"])
        #expect(try await repository.currentMemberRole(conversationID: "group_repo_conversation", userID: "admin_user") == .admin)
        #expect(announcement?.text == "本周联调重点：群聊 P1。")
        await #expect(throws: GroupChatError.permissionDenied) {
            try await repository.updateGroupAnnouncement(
                conversationID: "group_repo_conversation",
                userID: "member_user",
                text: "普通成员不能改公告"
            )
        }
    }

    @Test func outgoingTextMessagePersistsMentionMetadata() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "mention_send_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "mention_send_conversation", userID: "mention_send_user", type: .group, targetID: "mention_group")
        )

        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "mention_send_user",
                conversationID: "mention_send_conversation",
                senderID: "mention_send_user",
                text: "@Sondra 请看这里",
                localTime: 200,
                messageID: "mention_send_message",
                mentionedUserIDs: ["sondra"],
                mentionsAll: false,
                sortSequence: 200
            )
        )

        let rows = try await databaseContext.databaseActor.query(
            "SELECT mentions_json, at_all FROM message_text WHERE content_id = ?;",
            parameters: [.text("text_\(message.id.rawValue)")],
            paths: databaseContext.paths
        )

        #expect(rows.first?.string("mentions_json") == "[\"sondra\"]")
        #expect(rows.first?.int("at_all") == 0)
    }

    @Test func incomingMentionMarksConversationUntilRead() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "mention_incoming_user")
        let batch = SyncBatch(
            messages: [
                IncomingSyncMessage(
                    messageID: "incoming_mention_message",
                    conversationID: "incoming_mention_conversation",
                    senderID: "teammate",
                    serverMessageID: "server_incoming_mention",
                    sequence: 10,
                    text: "@我 看下公告",
                    serverTime: 10,
                    conversationTitle: "Mention Group",
                    conversationType: .group,
                    mentionedUserIDs: ["mention_incoming_user"]
                )
            ],
            nextCursor: "cursor",
            nextSequence: 10
        )

        _ = try await repository.applyIncomingSyncBatch(batch, userID: "mention_incoming_user")
        let rowsBeforeRead = LocalConversationListUseCase.rowStates(
            from: try await repository.listConversations(for: "mention_incoming_user")
        )
        try await repository.markConversationRead(conversationID: "incoming_mention_conversation", userID: "mention_incoming_user")
        let rowsAfterRead = LocalConversationListUseCase.rowStates(
            from: try await repository.listConversations(for: "mention_incoming_user")
        )

        #expect(rowsBeforeRead.first?.mentionIndicatorText == "[有人@我]")
        #expect(rowsBeforeRead.first?.subtitle.hasPrefix("[有人@我] ") == true)
        #expect(rowsAfterRead.first?.mentionIndicatorText == nil)
    }

    @Test func messageRepositoryUpdatesSendStatusAndFindsMessageByID() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "status_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "status_conversation", userID: "status_user", title: "Status", sortTimestamp: 1)
        )

        let insertedMessage = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "status_user",
                conversationID: "status_conversation",
                senderID: "status_user",
                text: "Status update",
                localTime: 400,
                messageID: "status_message",
                clientMessageID: "status_client",
                sortSequence: 400
            )
        )

        try await repository.updateMessageSendStatus(
            messageID: insertedMessage.id,
            status: .success,
            ack: MessageSendAck(serverMessageID: "server_status", sequence: 401, serverTime: 401)
        )

        let updatedMessage = try await repository.message(messageID: insertedMessage.id)
        let missingMessage = try await repository.message(messageID: "missing_message")

        #expect(updatedMessage?.state.sendStatus == .success)
        #expect(missingMessage == nil)
    }

    @Test func chatUseCaseLoadsInitialMessagesInAscendingOrder() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "chat_order_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "chat_order_conversation", userID: "chat_order_user", title: "Chat", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "chat_order_user",
                conversationID: "chat_order_conversation",
                senderID: "chat_order_user",
                text: "First",
                localTime: 100,
                messageID: "chat_first",
                clientMessageID: "chat_first_client",
                sortSequence: 100
            )
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "chat_order_user",
                conversationID: "chat_order_conversation",
                senderID: "chat_order_user",
                text: "Second",
                localTime: 200,
                messageID: "chat_second",
                clientMessageID: "chat_second_client",
                sortSequence: 200
            )
        )

        let useCase = LocalChatUseCase(
            userID: "chat_order_user",
            conversationID: "chat_order_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let page = try await useCase.loadInitialMessages()

        #expect(page.rows.map(rowText) == ["First", "Second"])
        #expect(page.hasMore == false)
        #expect(page.nextBeforeSortSequence == 100)
    }

    @MainActor
    @Test func storeBackedChatUseCaseSimulatesIncomingTextMessageThroughSyncStore() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "simulated_store_user",
            storageService: storageService,
            database: DatabaseActor(),
            shouldSeedDemoData: false
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "simulated_store_conversation",
                userID: "simulated_store_user",
                title: "Simulated Store",
                sortTimestamp: 100
            )
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "simulated_store_user",
                conversationID: "simulated_store_conversation",
                senderID: "simulated_store_user",
                text: "Before simulated incoming",
                localTime: 100,
                messageID: "simulated_store_existing",
                clientMessageID: "simulated_store_existing_client",
                sortSequence: 100
            )
        )
        let useCase = StoreBackedChatUseCase(
            userID: "simulated_store_user",
            conversationID: "simulated_store_conversation",
            storeProvider: storeProvider,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: AccountMediaFileStore(accountID: "simulated_store_user", storageService: storageService)
        )

        let row = try #require(try await useCase.simulateIncomingMessages().first)
        let secondRow = try #require(try await useCase.simulateIncomingMessages().first)
        let storedMessage = try #require(try await repository.message(messageID: row.id))
        let secondStoredMessage = try #require(try await repository.message(messageID: secondRow.id))
        let page = try await useCase.loadInitialMessages()

        #expect(row.id.rawValue.hasPrefix("simulated_push_incoming_"))
        #expect(row.isOutgoing == false)
        let storedText = try requireTextContent(storedMessage)
        let secondStoredText = try requireTextContent(secondStoredMessage)
        #expect(storedMessage.state.direction == .incoming)
        #expect(secondStoredMessage.state.direction == .incoming)
        #expect(storedText.isEmpty == false)
        #expect(secondStoredText.isEmpty == false)
        #expect(storedText != secondStoredText)
        #expect(storedMessage.timeline.sortSequence >= 101)
        #expect(secondStoredMessage.timeline.sortSequence > storedMessage.timeline.sortSequence)
        #expect(page.rows.contains { $0.id == row.id })
        #expect(page.rows.contains { $0.id == secondRow.id })
    }

    @MainActor
    @Test func storeBackedChatUseCaseAssignsDistinctSequencesForConcurrentSimulatedIncomingMessages() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "simulated_concurrent_user",
            storageService: storageService,
            database: DatabaseActor(),
            shouldSeedDemoData: false
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "simulated_concurrent_conversation",
                userID: "simulated_concurrent_user",
                title: "Simulated Concurrent",
                sortTimestamp: 100
            )
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "simulated_concurrent_user",
                conversationID: "simulated_concurrent_conversation",
                senderID: "simulated_concurrent_user",
                text: "Before concurrent simulated incoming",
                localTime: 100,
                messageID: "simulated_concurrent_existing",
                clientMessageID: "simulated_concurrent_existing_client",
                sortSequence: 100
            )
        )
        let useCase = StoreBackedChatUseCase(
            userID: "simulated_concurrent_user",
            conversationID: "simulated_concurrent_conversation",
            storeProvider: storeProvider,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: AccountMediaFileStore(accountID: "simulated_concurrent_user", storageService: storageService)
        )

        async let first = useCase.simulateIncomingMessages()
        async let second = useCase.simulateIncomingMessages()
        let rows = try await [first, second].flatMap { $0 }
        var storedMessages: [StoredMessage] = []
        for row in rows {
            storedMessages.append(try #require(try await repository.message(messageID: row.id)))
        }
        let sortedSequences = storedMessages.map(\.timeline.sortSequence).sorted()

        #expect(rows.count >= 2)
        #expect(Set(rows.map(\.id)).count == rows.count)
        #expect(Set(storedMessages.map(\.timeline.sortSequence)).count == storedMessages.count)
        #expect(sortedSequences[1] > sortedSequences[0])
    }

    @MainActor
    @Test func storeBackedChatUseCaseKeepsSimulatedIncomingMessageReadWhenChatIsOpen() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "simulated_read_user",
            storageService: storageService,
            database: DatabaseActor(),
            shouldSeedDemoData: false
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "simulated_read_conversation",
                userID: "simulated_read_user",
                title: "Simulated Read",
                unreadCount: 0,
                sortTimestamp: 100
            )
        )
        let useCase = StoreBackedChatUseCase(
            userID: "simulated_read_user",
            conversationID: "simulated_read_conversation",
            storeProvider: storeProvider,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: AccountMediaFileStore(accountID: "simulated_read_user", storageService: storageService)
        )

        _ = try await useCase.loadInitialMessages()
        let row = try #require(try await useCase.simulateIncomingMessages().first)

        try await waitForCondition {
            let conversations = try await repository.listConversations(for: "simulated_read_user")
            let storedMessage = try await repository.message(messageID: row.id)
            let conversation = conversations.first { $0.id == "simulated_read_conversation" }
            return conversation?.unreadCount == 0 && storedMessage?.state.readStatus == .read
        }
        let conversations = try await repository.listConversations(for: "simulated_read_user")
        let storedMessage = try #require(try await repository.message(messageID: row.id))
        let conversation = try #require(conversations.first { $0.id == "simulated_read_conversation" })
        #expect(conversation.unreadCount == 0)
        #expect(storedMessage.state.readStatus == .read)
    }

    @Test func localChatUseCaseRequestsCurrentConversationWhenTriggeringChatPush() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "chat_push_request_user")
        let conversationID = ConversationID(rawValue: "chat_push_request_conversation")
        let message = IncomingSyncMessage(
            messageID: "chat_push_request_message",
            conversationID: conversationID,
            senderID: "chat_push_request_peer",
            serverMessageID: "server_chat_push_request_message",
            sequence: 101,
            text: "后台推送对方消息",
            serverTime: 101,
            direction: .incoming,
            conversationTitle: "Chat Push Request",
            conversationType: .single
        )
        let pusher = CapturingSimulatedIncomingPusher(
            result: SimulatedIncomingPushResult(
                conversationID: conversationID,
                messages: [message],
                insertedCount: 1,
                finalConversation: Conversation(
                    id: conversationID,
                    type: .single,
                    title: "Chat Push Request",
                    avatarURL: nil,
                    lastMessageDigest: message.text,
                    lastMessageTimeText: "Now",
                    unreadCount: 1,
                    isPinned: false,
                    isMuted: false,
                    draftText: nil,
                    sortTimestamp: message.sequence
                )
            )
        )
        let useCase = LocalChatUseCase(
            userID: "chat_push_request_user",
            conversationID: conversationID,
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            simulatedIncomingPushService: pusher
        )

        let rows = try await useCase.simulateIncomingMessages()
        let requests = await pusher.requests

        #expect(requests == [SimulatedIncomingPushRequest(target: .conversation(conversationID))])
        #expect(rows.map(\.id) == [message.messageID])
        #expect(rows.allSatisfy { $0.isOutgoing == false })
    }

    @MainActor
    @Test func storeBackedChatUseCasePushesOnlyIntoCurrentConversation() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "chat_current_push_user",
            storageService: storageService,
            database: DatabaseActor(),
            shouldSeedDemoData: false
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "chat_current_push_conversation",
                userID: "chat_current_push_user",
                title: "Current Push",
                targetID: "chat_current_push_peer",
                sortTimestamp: 100
            )
        )
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "chat_other_push_conversation",
                userID: "chat_current_push_user",
                title: "Other Push",
                targetID: "chat_other_push_peer",
                sortTimestamp: 200
            )
        )
        let useCase = StoreBackedChatUseCase(
            userID: "chat_current_push_user",
            conversationID: "chat_current_push_conversation",
            storeProvider: storeProvider,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: AccountMediaFileStore(accountID: "chat_current_push_user", storageService: storageService)
        )

        let rows = try await useCase.simulateIncomingMessages()
        let currentMessages = try await repository.listMessages(
            conversationID: "chat_current_push_conversation",
            limit: 10,
            beforeSortSeq: nil
        )
        let otherMessages = try await repository.listMessages(
            conversationID: "chat_other_push_conversation",
            limit: 10,
            beforeSortSeq: nil
        )

        #expect(rows.isEmpty == false)
        #expect(currentMessages.count == rows.count)
        #expect(Set(currentMessages.map(\.id)) == Set(rows.map(\.id)))
        #expect(otherMessages.isEmpty)
        #expect(currentMessages.allSatisfy { $0.state.direction == .incoming })
        #expect(currentMessages.allSatisfy { $0.senderID == "chat_current_push_peer" })
        #expect(rows.allSatisfy { $0.isOutgoing == false })
    }

    @Test func chatUseCaseMapsSenderAvatarURLsByMessageDirection() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "avatar_chat_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "avatar_chat_conversation", userID: "avatar_chat_user", title: "Avatar Chat", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "avatar_chat_user",
                conversationID: "avatar_chat_conversation",
                senderID: "avatar_chat_user",
                text: "From me",
                localTime: 100,
                messageID: "avatar_outgoing",
                clientMessageID: "avatar_outgoing_client",
                sortSequence: 100
            )
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "avatar_chat_user",
                conversationID: "avatar_chat_conversation",
                senderID: "friend_user",
                text: "From friend",
                localTime: 200,
                messageID: "avatar_incoming",
                clientMessageID: "avatar_incoming_client",
                sortSequence: 200
            )
        )

        let useCase = LocalChatUseCase(
            userID: "avatar_chat_user",
            conversationID: "avatar_chat_conversation",
            currentUserAvatarURL: "file:///tmp/current-avatar.png",
            conversationAvatarURL: "https://example.com/friend-avatar.png",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let page = try await useCase.loadInitialMessages()

        #expect(page.rows.first?.senderAvatarURL == "file:///tmp/current-avatar.png")
        #expect(page.rows.last?.senderAvatarURL == "https://example.com/friend-avatar.png")
    }

    @Test func chatUseCaseInitialPageReturnsLatestFiftyMessagesAscending() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "chat_page_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "chat_page_conversation", userID: "chat_page_user", title: "Paged", sortTimestamp: 1)
        )

        for index in 1...60 {
            _ = try await repository.insertOutgoingTextMessage(
                OutgoingTextMessageInput(
                    userID: "chat_page_user",
                    conversationID: "chat_page_conversation",
                    senderID: "chat_page_user",
                    text: "Message \(index)",
                    localTime: Int64(index),
                    messageID: MessageID(rawValue: "chat_page_\(index)"),
                    clientMessageID: "chat_page_client_\(index)",
                    sortSequence: Int64(index)
                )
            )
        }

        let useCase = LocalChatUseCase(
            userID: "chat_page_user",
            conversationID: "chat_page_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let page = try await useCase.loadInitialMessages()

        #expect(page.rows.count == 50)
        #expect(page.rows.first.map(rowText) == "Message 11")
        #expect(page.rows.last.map(rowText) == "Message 60")
        #expect(page.hasMore == true)
        #expect(page.nextBeforeSortSequence == 11)
    }

    @Test func seededSondraConversationInitialPageLoadsNewestFiftyMessages() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "mock_user")
        try await DemoDataSeeder.seedIfNeeded(
            repository: repository,
            userID: "mock_user",
            catalog: BundleDemoDataCatalog(resourceURL: try makeMockDemoDataFile(messageCount: 120)),
            contactCatalog: BundleContactCatalog(resourceURL: try makeMockContactsFile())
        )
        let useCase = LocalChatUseCase(
            userID: "mock_user",
            conversationID: "single_sondra",
            repository: repository,
            conversationRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )

        let page = try await useCase.loadInitialMessages()

        #expect(page.rows.count == 50)
        #expect(page.rows.first.map(rowText) == "Sondra JSON message 71")
        #expect(page.rows.last.map(rowText) == "Sondra JSON message 120")
        #expect(page.hasMore == true)
        #expect(page.nextBeforeSortSequence == 9_951)
    }

    @Test func chatUseCaseOlderPageUsesSortSequenceCursor() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "older_page_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "older_page_conversation", userID: "older_page_user", title: "Older", sortTimestamp: 1)
        )

        for index in 1...60 {
            _ = try await repository.insertOutgoingTextMessage(
                OutgoingTextMessageInput(
                    userID: "older_page_user",
                    conversationID: "older_page_conversation",
                    senderID: "older_page_user",
                    text: "Older \(index)",
                    localTime: Int64(index),
                    messageID: MessageID(rawValue: "older_page_\(index)"),
                    clientMessageID: "older_page_client_\(index)",
                    sortSequence: Int64(index)
                )
            )
        }

        let useCase = LocalChatUseCase(
            userID: "older_page_user",
            conversationID: "older_page_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let olderPage = try await useCase.loadOlderMessages(beforeSortSequence: 11, limit: 50)

        #expect(olderPage.rows.count == 10)
        #expect(olderPage.rows.first.map(rowText) == "Older 1")
        #expect(olderPage.rows.last.map(rowText) == "Older 10")
        #expect(olderPage.hasMore == false)
        #expect(olderPage.nextBeforeSortSequence == 1)
    }

    @Test func chatUseCasePagesThroughOneHundredThousandMessagesWithCursor() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "chat_perf_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "chat_perf_conversation", userID: "chat_perf_user", title: "Performance", sortTimestamp: 100_000)
        )
        try await seedPerformanceMessages(
            databaseContext: databaseContext,
            conversationID: "chat_perf_conversation",
            userID: "chat_perf_user",
            count: 100_000
        )

        let useCase = LocalChatUseCase(
            userID: "chat_perf_user",
            conversationID: "chat_perf_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let initialPage = try await useCase.loadInitialMessages()
        let olderPage = try await useCase.loadOlderMessages(beforeSortSequence: 99_951, limit: 50)

        #expect(initialPage.rows.count == 50)
        #expect(initialPage.rows.first.map(rowText) == "Perf Message 99951")
        #expect(initialPage.rows.last.map(rowText) == "Perf Message 100000")
        #expect(initialPage.hasMore == true)
        #expect(initialPage.nextBeforeSortSequence == 99_951)
        #expect(olderPage.rows.count == 50)
        #expect(olderPage.rows.first.map(rowText) == "Perf Message 99901")
        #expect(olderPage.rows.last.map(rowText) == "Perf Message 99950")
        #expect(olderPage.hasMore == true)
        #expect(olderPage.nextBeforeSortSequence == 99_901)
    }

    @Test func messagePaginationQueriesUseVisibleSortIndex() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "chat_plan_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "chat_plan_conversation", userID: "chat_plan_user", title: "Query Plan", sortTimestamp: 100)
        )
        try await seedPerformanceMessages(
            databaseContext: databaseContext,
            conversationID: "chat_plan_conversation",
            userID: "chat_plan_user",
            count: 100
        )

        let initialPlanRows = try await databaseContext.databaseActor.query(
            "EXPLAIN QUERY PLAN \(MessageDAO.listMessagesQuery(beforeSortSeq: nil))",
            parameters: [
                .text("chat_plan_conversation"),
                .integer(51)
            ],
            paths: databaseContext.paths
        )
        let olderPlanRows = try await databaseContext.databaseActor.query(
            "EXPLAIN QUERY PLAN \(MessageDAO.listMessagesQuery(beforeSortSeq: 51))",
            parameters: [
                .text("chat_plan_conversation"),
                .integer(51),
                .integer(51)
            ],
            paths: databaseContext.paths
        )

        let initialPlan = initialPlanRows.compactMap { $0.string("detail") }.joined(separator: "\n")
        let olderPlan = olderPlanRows.compactMap { $0.string("detail") }.joined(separator: "\n")

        #expect(initialPlan.contains("idx_message_conversation_visible_sort"))
        #expect(olderPlan.contains("idx_message_conversation_visible_sort"))
    }

    @MainActor
    @Test func chatUseCaseSendTextYieldsSendingThenSuccess() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "chat_send_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "chat_send_conversation", userID: "chat_send_user", title: "Send", sortTimestamp: 1)
        )
        try await repository.saveDraft(conversationID: "chat_send_conversation", userID: "chat_send_user", text: "draft before send")

        let useCase = LocalChatUseCase(
            userID: "chat_send_user",
            conversationID: "chat_send_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        var iterator = useCase.sendText("Hello mock ack").makeAsyncIterator()
        let sendingRow = try #require(try await iterator.next())
        let draftAfterFirstRow = try await repository.draft(conversationID: "chat_send_conversation", userID: "chat_send_user")
        let successRow = try #require(try await iterator.next())
        let storedMessage = try await repository.message(messageID: sendingRow.id)

        #expect(sendingRow.statusText == "Sending")
        #expect(successRow.statusText == nil)
        #expect(draftAfterFirstRow == "draft before send")
        #expect(try await iterator.next() == nil)
        #expect(try await repository.draft(conversationID: "chat_send_conversation", userID: "chat_send_user") == nil)
        #expect(storedMessage?.state.sendStatus == .success)
    }

    @Test func serverMessageSendServiceMapsTextAckToSendResult() async throws {
        let httpClient = RecordingHTTPClient(
            response: ServerTextMessageSendResponse(
                serverMessageID: "server_contract_ack",
                sequence: 42,
                serverTime: 1_777_777_777
            )
        )
        let service = ServerMessageSendService(httpClient: httpClient)
        let message = makeStoredTextMessage(
            messageID: "local_contract_message",
            conversationID: "contract_conversation",
            senderID: "contract_user",
            clientMessageID: "client_contract_message",
            text: "Hello server"
        )

        let result = await service.sendText(message: message)
        let request = await httpClient.lastTextRequest

        #expect(result == .success(MessageSendAck(serverMessageID: "server_contract_ack", sequence: 42, serverTime: 1_777_777_777)))
        #expect(request?.conversationID == "contract_conversation")
        #expect(request?.clientMessageID == "client_contract_message")
        #expect(request?.senderID == "contract_user")
        #expect(request?.text == "Hello server")
        #expect(request?.localTime == 100)
    }

    @Test func serverMessageSendServiceMapsTransportFailuresToSendFailures() async throws {
        let offlineService = ServerMessageSendService(
            httpClient: RecordingHTTPClient(error: ChatBridgeHTTPError.offline)
        )
        let timeoutService = ServerMessageSendService(
            httpClient: RecordingHTTPClient(error: ChatBridgeHTTPError.timeout)
        )
        let ackMissingService = ServerMessageSendService(
            httpClient: RecordingHTTPClient(error: ChatBridgeHTTPError.ackMissing)
        )
        let message = makeStoredTextMessage()

        let offlineResult = await offlineService.sendText(message: message)
        let timeoutResult = await timeoutService.sendText(message: message)
        let ackMissingResult = await ackMissingService.sendText(message: message)

        #expect(offlineResult == .failure(.offline))
        #expect(timeoutResult == .failure(.timeout))
        #expect(ackMissingResult == .failure(.ackMissing))
    }

    @Test func serverMessageSendServiceMapsImageAckToSendResult() async throws {
        let httpClient = RecordingHTTPClient(
            response: ServerTextMessageSendResponse(
                serverMessageID: "server_image_ack",
                sequence: 43,
                serverTime: 1_777_777_743
            )
        )
        let service = ServerMessageSendService(httpClient: httpClient)
        let message = makeStoredImageMessage(
            messageID: "local_image_message",
            conversationID: "image_conversation",
            senderID: "image_user",
            clientMessageID: "client_image_message"
        )
        let upload = MediaUploadAck(mediaID: "image_media_uploaded", cdnURL: "https://cdn.example/image.png", md5: "image-md5")

        let result = await service.sendImage(message: message, upload: upload)
        let request = await httpClient.lastImageRequest

        #expect(result == .success(MessageSendAck(serverMessageID: "server_image_ack", sequence: 43, serverTime: 1_777_777_743)))
        #expect(request?.conversationID == "image_conversation")
        #expect(request?.clientMessageID == "client_image_message")
        #expect(request?.senderID == "image_user")
        #expect(request?.mediaID == "image_media_uploaded")
        #expect(request?.cdnURL == "https://cdn.example/image.png")
        #expect(request?.md5 == "image-md5")
        #expect(request?.width == 320)
        #expect(request?.height == 240)
        #expect(request?.sizeBytes == 4_096)
        #expect(request?.format == "png")
        #expect(request?.localTime == 100)
    }

    @Test func serverMessageSendServiceMapsVoiceVideoAndFileRequests() async throws {
        let httpClient = RecordingHTTPClient(
            response: ServerTextMessageSendResponse(
                serverMessageID: "server_media_ack",
                sequence: 44,
                serverTime: 1_777_777_744
            )
        )
        let service = ServerMessageSendService(httpClient: httpClient)
        let upload = MediaUploadAck(mediaID: "uploaded_media", cdnURL: "https://cdn.example/media", md5: "media-md5")

        let voiceResult = await service.sendVoice(message: makeStoredVoiceMessage(), upload: upload)
        let videoResult = await service.sendVideo(message: makeStoredVideoMessage(), upload: upload)
        let fileResult = await service.sendFile(message: makeStoredFileMessage(), upload: upload)
        let voiceRequest = await httpClient.lastVoiceRequest
        let videoRequest = await httpClient.lastVideoRequest
        let fileRequest = await httpClient.lastFileRequest

        #expect(voiceResult == .success(MessageSendAck(serverMessageID: "server_media_ack", sequence: 44, serverTime: 1_777_777_744)))
        #expect(videoResult == .success(MessageSendAck(serverMessageID: "server_media_ack", sequence: 44, serverTime: 1_777_777_744)))
        #expect(fileResult == .success(MessageSendAck(serverMessageID: "server_media_ack", sequence: 44, serverTime: 1_777_777_744)))
        #expect(voiceRequest?.durationMilliseconds == 1_800)
        #expect(voiceRequest?.sizeBytes == 2_048)
        #expect(voiceRequest?.format == "m4a")
        #expect(videoRequest?.durationMilliseconds == 3_600)
        #expect(videoRequest?.width == 640)
        #expect(videoRequest?.height == 360)
        #expect(videoRequest?.sizeBytes == 8_192)
        #expect(fileRequest?.fileName == "report.pdf")
        #expect(fileRequest?.fileExtension == "pdf")
        #expect(fileRequest?.sizeBytes == 16_384)
    }

    @Test func serverMessageSendServiceMapsMediaTransportFailuresToSendFailures() async throws {
        let message = makeStoredImageMessage()
        let upload = MediaUploadAck(mediaID: "image_media", cdnURL: "https://cdn.example/image.png", md5: nil)

        let offlineResult = await ServerMessageSendService(
            httpClient: RecordingHTTPClient(error: ChatBridgeHTTPError.offline)
        ).sendImage(message: message, upload: upload)
        let timeoutResult = await ServerMessageSendService(
            httpClient: RecordingHTTPClient(error: ChatBridgeHTTPError.timeout)
        ).sendImage(message: message, upload: upload)
        let ackMissingResult = await ServerMessageSendService(
            httpClient: RecordingHTTPClient(error: ChatBridgeHTTPError.ackMissing)
        ).sendImage(message: message, upload: upload)
        let missingURLResult = await ServerMessageSendService(
            httpClient: RecordingHTTPClient()
        ).sendImage(message: message, upload: MediaUploadAck(mediaID: "image_media", cdnURL: "  ", md5: nil))

        #expect(offlineResult == .failure(.offline))
        #expect(timeoutResult == .failure(.timeout))
        #expect(ackMissingResult == .failure(.ackMissing))
        #expect(missingURLResult == .failure(.ackMissing))
    }

    @Test func serverMessageSendServiceRejectsMismatchedStoredMessageContent() async throws {
        let service = ServerMessageSendService(httpClient: RecordingHTTPClient())
        let textMessage = makeStoredTextMessage()
        let imageMessage = makeStoredImageMessage()
        let upload = MediaUploadAck(mediaID: "image_media", cdnURL: "https://cdn.example/image.png", md5: nil)

        let textAsImage = await service.sendImage(message: textMessage, upload: upload)
        let imageAsText = await service.sendText(message: imageMessage)

        #expect(textAsImage == .failure(.ackMissing))
        #expect(imageAsText == .failure(.ackMissing))
    }

    @Test func tokenRefreshingHTTPClientRefreshesAfterUnauthorizedAndRetriesWithUpdatedToken() async throws {
        let tokenBox = TokenBox(token: "expired_token")
        let httpClient = ExpiringTextHTTPClient(
            tokenProvider: {
                await tokenBox.token
            },
            response: ServerTextMessageSendResponse(
                serverMessageID: "refreshed_ack",
                sequence: 77,
                serverTime: 1_777_777_077
            )
        )
        let refreshingClient = TokenRefreshingHTTPClient(httpClient: httpClient) {
            await tokenBox.updateToken("fresh_token")
            return "fresh_token"
        }
        let service = ServerMessageSendService(httpClient: refreshingClient)

        let result = await service.sendText(message: makeStoredTextMessage(clientMessageID: "refresh_client"))

        #expect(result == .success(MessageSendAck(serverMessageID: "refreshed_ack", sequence: 77, serverTime: 1_777_777_077)))
        #expect(await httpClient.textSendCallCount == 2)
        #expect(await httpClient.observedTokens == ["expired_token", "fresh_token"])
    }

    @Test func tokenRefreshingHTTPClientDoesNotRefreshNonUnauthorizedFailures() async throws {
        let httpClient = ExpiringTextHTTPClient(error: ChatBridgeHTTPError.timeout)
        let refreshCallCount = Counter()
        let refreshingClient = TokenRefreshingHTTPClient(httpClient: httpClient) {
            await refreshCallCount.increment()
            return "fresh_token"
        }
        let service = ServerMessageSendService(httpClient: refreshingClient)

        let result = await service.sendText(message: makeStoredTextMessage())

        #expect(result == .failure(.timeout))
        #expect(await refreshCallCount.value == 0)
        #expect(await httpClient.textSendCallCount == 1)
    }

    @Test func tokenRefreshingHTTPClientRefreshesMediaSendAfterUnauthorized() async throws {
        let tokenBox = TokenBox(token: "expired_token")
        let httpClient = ExpiringTextHTTPClient(
            tokenProvider: {
                await tokenBox.token
            },
            response: ServerTextMessageSendResponse(
                serverMessageID: "refreshed_media_ack",
                sequence: 78,
                serverTime: 1_777_777_078
            )
        )
        let refreshingClient = TokenRefreshingHTTPClient(httpClient: httpClient) {
            await tokenBox.updateToken("fresh_token")
            return "fresh_token"
        }
        let service = ServerMessageSendService(httpClient: refreshingClient)

        let result = await service.sendImage(
            message: makeStoredImageMessage(clientMessageID: "refresh_image_client"),
            upload: MediaUploadAck(mediaID: "refresh_image_media", cdnURL: "https://cdn.example/refresh.png", md5: nil)
        )

        #expect(result == .success(MessageSendAck(serverMessageID: "refreshed_media_ack", sequence: 78, serverTime: 1_777_777_078)))
        #expect(await httpClient.mediaSendCallCount == 2)
        #expect(await httpClient.observedTokens == ["expired_token", "fresh_token"])
    }

    @Test func chatUseCaseQueuesPendingJobWhenUnauthorizedRefreshFails() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "refresh_fail_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "refresh_fail_conversation", userID: "refresh_fail_user", title: "Refresh Fail", sortTimestamp: 1)
        )
        let httpClient = ExpiringTextHTTPClient(error: ChatBridgeHTTPError.unacceptableStatus(401))
        let refreshingClient = TokenRefreshingHTTPClient(httpClient: httpClient) {
            nil
        }
        let useCase = LocalChatUseCase(
            userID: "refresh_fail_user",
            conversationID: "refresh_fail_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: ServerMessageSendService(httpClient: refreshingClient),
            retryPolicy: MessageRetryPolicy(initialDelaySeconds: 2, maxDelaySeconds: 10, maxRetryCount: 3)
        )

        let rows = try await collectRows(from: useCase.sendText("Queue after refresh fail"))
        let failedMessage = try await repository.message(messageID: rows[0].id)!
        let pendingJob = try #require(try await repository.pendingJob(id: PendingMessageJobFactory.messageResendJobID(clientMessageID: failedMessage.delivery.clientMessageID ?? "")))

        #expect(rows.map(\.statusText) == ["Sending", "Failed"])
        #expect(failedMessage.state.sendStatus == .failed)
        #expect(pendingJob.type == .messageResend)
        #expect(pendingJob.payloadJSON.contains("unknown"))
        #expect(await httpClient.textSendCallCount == 1)
    }

    @Test func chatUseCasePersistsServerAckFromServerMessageSendService() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "server_ack_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "server_ack_conversation", userID: "server_ack_user", title: "Server Ack", sortTimestamp: 1)
        )
        let service = ServerMessageSendService(
            httpClient: RecordingHTTPClient(
                response: ServerTextMessageSendResponse(
                    serverMessageID: "server_ack_message",
                    sequence: 909,
                    serverTime: 1_777_777_909
                )
            )
        )
        let useCase = LocalChatUseCase(
            userID: "server_ack_user",
            conversationID: "server_ack_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: service
        )

        let rows = try await collectRows(from: useCase.sendText("Persist server ack"))
        let storedMessage = try await repository.message(messageID: rows[0].id)

        #expect(rows.map(\.statusText) == ["Sending", nil])
        #expect(storedMessage?.state.sendStatus == .success)
        #expect(storedMessage?.delivery.serverMessageID == "server_ack_message")
        #expect(storedMessage?.delivery.sequence == 909)
        #expect(storedMessage?.timeline.serverTime == 1_777_777_909)
    }

    @Test func chatUseCaseQueuesPendingJobForServerAckFailureAndResendsWithSameClientMessageID() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "server_retry_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "server_retry_conversation", userID: "server_retry_user", title: "Server Retry", sortTimestamp: 1)
        )
        let failingUseCase = LocalChatUseCase(
            userID: "server_retry_user",
            conversationID: "server_retry_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: ServerMessageSendService(httpClient: RecordingHTTPClient(error: ChatBridgeHTTPError.ackMissing)),
            retryPolicy: MessageRetryPolicy(initialDelaySeconds: 2, maxDelaySeconds: 10, maxRetryCount: 3)
        )

        let failedRows = try await collectRows(from: failingUseCase.sendText("Retry with same client id"))
        let failedMessageID = failedRows[0].id
        let failedMessage = try await repository.message(messageID: failedMessageID)!
        let pendingJob = try #require(try await repository.pendingJob(id: PendingMessageJobFactory.messageResendJobID(clientMessageID: failedMessage.delivery.clientMessageID ?? "")))

        let successClient = RecordingHTTPClient(
            response: ServerTextMessageSendResponse(
                serverMessageID: "server_retry_ack",
                sequence: 808,
                serverTime: 1_777_777_808
            )
        )
        let retryingUseCase = LocalChatUseCase(
            userID: "server_retry_user",
            conversationID: "server_retry_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: ServerMessageSendService(httpClient: successClient)
        )
        let retryRows = try await collectRows(from: retryingUseCase.resend(messageID: failedMessageID))
        let storedMessages = try await repository.listMessages(conversationID: "server_retry_conversation", limit: 20, beforeSortSeq: nil)
        let resentMessage = try await repository.message(messageID: failedMessageID)
        let retryRequest = await successClient.lastTextRequest

        #expect(failedRows.map(\.statusText) == ["Sending", "Failed"])
        #expect(pendingJob.type == .messageResend)
        #expect(pendingJob.payloadJSON.contains("ackMissing"))
        #expect(retryRows.map(\.statusText) == ["Sending", nil])
        #expect(storedMessages.count == 1)
        #expect(resentMessage?.delivery.clientMessageID == failedMessage.delivery.clientMessageID)
        #expect(resentMessage?.delivery.serverMessageID == "server_retry_ack")
        #expect(retryRequest?.clientMessageID == failedMessage.delivery.clientMessageID)
    }

    @Test func chatUseCaseDoesNotSendBlankText() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "blank_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "blank_conversation", userID: "blank_user", title: "Blank", sortTimestamp: 1)
        )

        let useCase = LocalChatUseCase(
            userID: "blank_user",
            conversationID: "blank_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let rows = try await collectRows(from: useCase.sendText("   \n  "))
        let messages = try await repository.listMessages(conversationID: "blank_conversation", limit: 20, beforeSortSeq: nil)

        #expect(rows.isEmpty)
        #expect(messages.isEmpty)
    }

    @Test func chatUseCaseResendsFailedTextWithoutDuplicatingMessage() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "resend_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "resend_conversation", userID: "resend_user", title: "Resend", sortTimestamp: 1)
        )

        let failingUseCase = LocalChatUseCase(
            userID: "resend_user",
            conversationID: "resend_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(result: .failure(), delayNanoseconds: 0)
        )
        let failedRows = try await collectRows(from: failingUseCase.sendText("Retry me"))
        let failedMessageID = failedRows[0].id
        let failedMessage = try await repository.message(messageID: failedMessageID)!

        let retryingUseCase = LocalChatUseCase(
            userID: "resend_user",
            conversationID: "resend_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let retryRows = try await collectRows(from: retryingUseCase.resend(messageID: failedMessageID))
        let storedMessages = try await repository.listMessages(conversationID: "resend_conversation", limit: 20, beforeSortSeq: nil)
        let resentMessage = try await repository.message(messageID: failedMessageID)!

        #expect(failedRows.map(\.statusText) == ["Sending", "Failed"])
        #expect(failedRows.last?.canRetry == true)
        #expect(retryRows.map(\.statusText) == ["Sending", nil])
        #expect(storedMessages.count == 1)
        #expect(resentMessage.state.sendStatus == .success)
        #expect(resentMessage.delivery.clientMessageID == failedMessage.delivery.clientMessageID)
    }

    @Test func pendingJobRepositoryUpsertsAndRestoresUnfinishedJobs() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "pending_user")
        let input = PendingJobInput(
            id: "message_resend_pending_client",
            userID: "pending_user",
            type: .messageResend,
            bizKey: "pending_client",
            payloadJSON: #"{"message_id":"pending_message","client_msg_id":"pending_client"}"#,
            maxRetryCount: 3,
            nextRetryAt: 100
        )

        let insertedJob = try await repository.upsertPendingJob(input)
        let duplicateJob = try await repository.upsertPendingJob(input)
        try await repository.updatePendingJobStatus(jobID: input.id, status: .running, nextRetryAt: 100)

        let storedJob = try await repository.pendingJob(id: input.id)
        let recoverableJobs = try await repository.recoverablePendingJobs(userID: "pending_user", now: 100)

        #expect(insertedJob.status == .pending)
        #expect(duplicateJob.id == insertedJob.id)
        #expect(storedJob?.status == .running)
        #expect(recoverableJobs.map(\.id) == [input.id])
    }

    @Test func pendingJobRepositoryTracksFailedSuccessAndCancelledStates() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "pending_state_user")
        let retryInput = PendingJobInput(
            id: "retry_state_job",
            userID: "pending_state_user",
            type: .messageResend,
            bizKey: "retry_state_client",
            payloadJSON: #"{"message_id":"retry_state_message"}"#,
            maxRetryCount: 2
        )
        let successInput = PendingJobInput(
            id: "success_state_job",
            userID: "pending_state_user",
            type: .messageResend,
            bizKey: "success_state_client",
            payloadJSON: #"{"message_id":"success_state_message"}"#
        )
        let cancelledInput = PendingJobInput(
            id: "cancelled_state_job",
            userID: "pending_state_user",
            type: .messageResend,
            bizKey: "cancelled_state_client",
            payloadJSON: #"{"message_id":"cancelled_state_message"}"#
        )

        _ = try await repository.upsertPendingJob(retryInput)
        _ = try await repository.upsertPendingJob(successInput)
        _ = try await repository.upsertPendingJob(cancelledInput)
        try await repository.updatePendingJobStatus(jobID: retryInput.id, status: .failed, nextRetryAt: 200)
        try await repository.updatePendingJobStatus(jobID: successInput.id, status: .success, nextRetryAt: nil)
        try await repository.updatePendingJobStatus(jobID: cancelledInput.id, status: .cancelled, nextRetryAt: nil)

        let retryJob = try await repository.pendingJob(id: retryInput.id)
        let successJob = try await repository.pendingJob(id: successInput.id)
        let cancelledJob = try await repository.pendingJob(id: cancelledInput.id)
        let recoverableJobs = try await repository.recoverablePendingJobs(userID: "pending_state_user", now: 200)

        #expect(retryJob?.status == .failed)
        #expect(retryJob?.retryCount == 1)
        #expect(successJob?.status == .success)
        #expect(cancelledJob?.status == .cancelled)
        #expect(recoverableJobs.isEmpty)
    }

    @Test func chatUseCaseCreatesPendingJobWhenSendFails() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "send_pending_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "send_pending_conversation", userID: "send_pending_user", title: "Pending", sortTimestamp: 1)
        )

        let useCase = LocalChatUseCase(
            userID: "send_pending_user",
            conversationID: "send_pending_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(result: .failure(.timeout), delayNanoseconds: 0),
            retryPolicy: MessageRetryPolicy(initialDelaySeconds: 3, maxDelaySeconds: 30, maxRetryCount: 4)
        )

        let startedAt = Int64(Date().timeIntervalSince1970)
        let rows = try await collectRows(from: useCase.sendText("Queue me"))
        let failedMessage = try await repository.message(messageID: rows[0].id)!
        let recoverableJobs = try await repository.recoverablePendingJobs(userID: "send_pending_user", now: Int64.max)
        let job = recoverableJobs.first

        #expect(rows.map(\.statusText) == ["Sending", "Failed"])
        #expect(failedMessage.state.sendStatus == .failed)
        #expect(recoverableJobs.count == 1)
        #expect(job?.type == .messageResend)
        #expect(job?.bizKey == failedMessage.delivery.clientMessageID)
        #expect(job?.maxRetryCount == 4)
        #expect((job?.nextRetryAt ?? 0) >= startedAt + 3)
        #expect(job?.payloadJSON.contains(failedMessage.id.rawValue) == true)
        #expect(job?.payloadJSON.contains("send_pending_conversation") == true)
        #expect(job?.payloadJSON.contains("timeout") == true)
    }

    @Test func pendingMessageRetryRunnerReschedulesWeakNetworkFailuresWithBackoff() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "retry_runner_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "retry_runner_conversation", userID: "retry_runner_user", title: "Retry Runner", sortTimestamp: 1)
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "retry_runner_user",
                conversationID: "retry_runner_conversation",
                senderID: "retry_runner_user",
                text: "Retry after weak network",
                localTime: 100,
                messageID: "retry_runner_message",
                clientMessageID: "retry_runner_client",
                sortSequence: 100
            )
        )
        try await repository.updateMessageSendStatus(messageID: message.id, status: .failed, ack: nil)
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "message_resend_retry_runner_client",
                userID: "retry_runner_user",
                type: .messageResend,
                bizKey: "retry_runner_client",
                payloadJSON: #"{"messageID":"retry_runner_message","conversationID":"retry_runner_conversation","clientMessageID":"retry_runner_client","lastFailureReason":"offline"}"#,
                maxRetryCount: 3,
                nextRetryAt: 100
            )
        )
        let runner = PendingMessageRetryRunner(
            userID: "retry_runner_user",
            messageRepository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(result: .failure(.ackMissing), delayNanoseconds: 0),
            retryPolicy: MessageRetryPolicy(initialDelaySeconds: 10, maxDelaySeconds: 60, maxRetryCount: 3)
        )

        let result = try await runner.runDueJobs(now: 1_000)
        let job = try await repository.pendingJob(id: "message_resend_retry_runner_client")
        let storedMessage = try await repository.message(messageID: message.id)

        #expect(result == PendingMessageRetryRunResult(scannedJobCount: 1, attemptedCount: 1, successCount: 0, rescheduledCount: 1, exhaustedCount: 0))
        #expect(job?.status == .pending)
        #expect(job?.retryCount == 1)
        #expect(job?.nextRetryAt == 1_020)
        #expect(storedMessage?.state.sendStatus == .failed)
    }

    @Test func pendingMessageRetryRunnerMarksJobSuccessAfterRecoveredAck() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "retry_success_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "retry_success_conversation", userID: "retry_success_user", title: "Retry Success", sortTimestamp: 1)
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "retry_success_user",
                conversationID: "retry_success_conversation",
                senderID: "retry_success_user",
                text: "Recover ack",
                localTime: 200,
                messageID: "retry_success_message",
                clientMessageID: "retry_success_client",
                sortSequence: 200
            )
        )
        try await repository.updateMessageSendStatus(messageID: message.id, status: .failed, ack: nil)
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "message_resend_retry_success_client",
                userID: "retry_success_user",
                type: .messageResend,
                bizKey: "retry_success_client",
                payloadJSON: #"{"messageID":"retry_success_message","conversationID":"retry_success_conversation","clientMessageID":"retry_success_client","lastFailureReason":"ackMissing"}"#,
                maxRetryCount: 3,
                nextRetryAt: 100
            )
        )
        let runner = PendingMessageRetryRunner(
            userID: "retry_success_user",
            messageRepository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )

        let result = try await runner.runDueJobs(now: 100)
        let job = try await repository.pendingJob(id: "message_resend_retry_success_client")
        let storedMessage = try await repository.message(messageID: message.id)

        #expect(result.successCount == 1)
        #expect(job?.status == .success)
        #expect(storedMessage?.state.sendStatus == .success)
        #expect(storedMessage?.delivery.serverMessageID == "server_retry_success_message")
    }

    @Test func pendingMessageRetryRunnerStopsAtRetryLimit() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "retry_limit_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "retry_limit_conversation", userID: "retry_limit_user", title: "Retry Limit", sortTimestamp: 1)
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "retry_limit_user",
                conversationID: "retry_limit_conversation",
                senderID: "retry_limit_user",
                text: "Give up after limit",
                localTime: 300,
                messageID: "retry_limit_message",
                clientMessageID: "retry_limit_client",
                sortSequence: 300
            )
        )
        try await repository.updateMessageSendStatus(messageID: message.id, status: .failed, ack: nil)
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "message_resend_retry_limit_client",
                userID: "retry_limit_user",
                type: .messageResend,
                bizKey: "retry_limit_client",
                payloadJSON: #"{"messageID":"retry_limit_message","conversationID":"retry_limit_conversation","clientMessageID":"retry_limit_client","lastFailureReason":"timeout"}"#,
                maxRetryCount: 1,
                nextRetryAt: 100
            )
        )
        let runner = PendingMessageRetryRunner(
            userID: "retry_limit_user",
            messageRepository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(result: .failure(.timeout), delayNanoseconds: 0)
        )

        let result = try await runner.runDueJobs(now: 100)
        let job = try await repository.pendingJob(id: "message_resend_retry_limit_client")

        #expect(result.exhaustedCount == 1)
        #expect(job?.status == .failed)
        #expect(job?.retryCount == 1)
    }

    @Test func pendingMessageRetryRunnerRecoversImageUploadJob() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "image_runner_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "image_runner_conversation", userID: "image_runner_user", title: "Image Runner", sortTimestamp: 1)
        )
        let image = StoredImageContent(
            mediaID: "image_runner_media",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image_runner.png").path,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image_runner_thumb.jpg").path,
            width: 64,
            height: 64,
            sizeBytes: 256,
            format: "png"
        )
        let message = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "image_runner_user",
                conversationID: "image_runner_conversation",
                senderID: "image_runner_user",
                image: image,
                localTime: 500,
                messageID: "image_runner_message",
                clientMessageID: "image_runner_client",
                sortSequence: 500
            )
        )
        try await repository.updateImageUploadStatus(
            messageID: message.id,
            uploadStatus: .failed,
            uploadAck: nil,
            sendStatus: .failed,
            sendAck: nil,
            pendingJob: nil
        )
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "image_upload_image_runner_client",
                userID: "image_runner_user",
                type: .imageUpload,
                bizKey: "image_runner_client",
                payloadJSON: #"{"messageID":"image_runner_message","conversationID":"image_runner_conversation","clientMessageID":"image_runner_client","mediaID":"image_runner_media","lastFailureReason":"offline"}"#,
                maxRetryCount: 3,
                nextRetryAt: 100
            )
        )
        let runner = PendingMessageRetryRunner(
            userID: "image_runner_user",
            messageRepository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaUploadService: MockMediaUploadService(progressSteps: [1.0], delayNanoseconds: 0)
        )

        let result = try await runner.runDueJobs(now: 100)
        let job = try await repository.pendingJob(id: "image_upload_image_runner_client")
        let storedMessage = try await repository.message(messageID: message.id)

        #expect(result.successCount == 1)
        #expect(job?.status == .success)
        let storedImage = try requireImageContent(storedMessage)
        #expect(storedMessage?.state.sendStatus == .success)
        #expect(storedImage.uploadStatus == .success)
        #expect(storedImage.remoteURL?.contains("mock-cdn.chatbridge.local") == true)
    }

    @Test func pendingMessageRetryRunnerRecoversVideoUploadJob() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "video_runner_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "video_runner_conversation", userID: "video_runner_user", title: "Video Runner", sortTimestamp: 1)
        )
        let video = StoredVideoContent(
            mediaID: "video_runner_media",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("video_runner.mov").path,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("video_runner_thumb.jpg").path,
            durationMilliseconds: 1_000,
            width: 64,
            height: 64,
            sizeBytes: 512
        )
        let message = try await repository.insertOutgoingVideoMessage(
            OutgoingVideoMessageInput(
                userID: "video_runner_user",
                conversationID: "video_runner_conversation",
                senderID: "video_runner_user",
                video: video,
                localTime: 520,
                messageID: "video_runner_message",
                clientMessageID: "video_runner_client",
                sortSequence: 520
            )
        )
        try await repository.updateVideoUploadStatus(
            messageID: message.id,
            uploadStatus: .failed,
            uploadAck: nil,
            sendStatus: .failed,
            sendAck: nil,
            pendingJob: nil
        )
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "video_upload_video_runner_client",
                userID: "video_runner_user",
                type: .videoUpload,
                bizKey: "video_runner_client",
                payloadJSON: #"{"messageID":"video_runner_message","conversationID":"video_runner_conversation","clientMessageID":"video_runner_client","mediaID":"video_runner_media","lastFailureReason":"offline"}"#,
                maxRetryCount: 3,
                nextRetryAt: 100
            )
        )
        let runner = PendingMessageRetryRunner(
            userID: "video_runner_user",
            messageRepository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaUploadService: MockMediaUploadService(progressSteps: [1.0], delayNanoseconds: 0)
        )

        let result = try await runner.runDueJobs(now: 100)
        let job = try await repository.pendingJob(id: "video_upload_video_runner_client")
        let storedMessage = try await repository.message(messageID: message.id)

        #expect(result.successCount == 1)
        #expect(job?.status == .success)
        let storedVideo = try requireVideoContent(storedMessage)
        #expect(storedMessage?.state.sendStatus == .success)
        #expect(storedVideo.uploadStatus == .success)
        #expect(storedVideo.remoteURL?.contains("mock-cdn.chatbridge.local/video") == true)
    }

    @Test func pendingMessageRetryRunnerStopsImageUploadAtRetryLimit() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "image_limit_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "image_limit_conversation", userID: "image_limit_user", title: "Image Limit", sortTimestamp: 1)
        )
        let image = StoredImageContent(
            mediaID: "image_limit_media",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image_limit.png").path,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image_limit_thumb.jpg").path,
            width: 64,
            height: 64,
            sizeBytes: 256,
            format: "png"
        )
        let message = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "image_limit_user",
                conversationID: "image_limit_conversation",
                senderID: "image_limit_user",
                image: image,
                localTime: 600,
                messageID: "image_limit_message",
                clientMessageID: "image_limit_client",
                sortSequence: 600
            )
        )
        try await repository.updateImageUploadStatus(
            messageID: message.id,
            uploadStatus: .failed,
            uploadAck: nil,
            sendStatus: .failed,
            sendAck: nil,
            pendingJob: nil
        )
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "image_upload_image_limit_client",
                userID: "image_limit_user",
                type: .imageUpload,
                bizKey: "image_limit_client",
                payloadJSON: #"{"messageID":"image_limit_message","conversationID":"image_limit_conversation","clientMessageID":"image_limit_client","mediaID":"image_limit_media","lastFailureReason":"timeout"}"#,
                maxRetryCount: 1,
                nextRetryAt: 100
            )
        )
        let runner = PendingMessageRetryRunner(
            userID: "image_limit_user",
            messageRepository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaUploadService: MockMediaUploadService(result: .failed(.timeout), progressSteps: [0.5], delayNanoseconds: 0)
        )

        let result = try await runner.runDueJobs(now: 100)
        let job = try await repository.pendingJob(id: "image_upload_image_limit_client")
        let storedMessage = try await repository.message(messageID: message.id)

        #expect(result.exhaustedCount == 1)
        #expect(job?.status == .failed)
        #expect(job?.retryCount == 1)
        #expect(storedMessage?.state.sendStatus == .failed)
        #expect(try requireImageContent(storedMessage).uploadStatus == .failed)
    }

    @Test func crashRecoveryRestoresSendingTextMessageAsPendingJob() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "crash_text_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "crash_text_conversation", userID: "crash_text_user", title: "Crash Text", sortTimestamp: 1)
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "crash_text_user",
                conversationID: "crash_text_conversation",
                senderID: "crash_text_user",
                text: "Recover me after restart",
                localTime: 700,
                messageID: "crash_text_message",
                clientMessageID: "crash_text_client",
                sortSequence: 700
            )
        )

        let result = try await repository.recoverInterruptedOutgoingMessages(
            userID: "crash_text_user",
            retryPolicy: MessageRetryPolicy(initialDelaySeconds: 10, maxDelaySeconds: 60, maxRetryCount: 4),
            now: 1_000
        )
        let storedMessage = try await repository.message(messageID: message.id)
        let job = try await repository.pendingJob(id: "message_resend_crash_text_client")

        #expect(result == MessageCrashRecoveryResult(scannedMessageCount: 1, recoveredMessageCount: 1, pendingJobCount: 1, failedMessageCount: 0))
        #expect(storedMessage?.state.sendStatus == .pending)
        #expect(job?.status == .pending)
        #expect(job?.type == .messageResend)
        #expect(job?.bizKey == "crash_text_client")
        #expect(job?.maxRetryCount == 4)
        #expect(job?.nextRetryAt == 1_000)
        #expect(job?.payloadJSON.contains("ackMissing") == true)
    }

    @Test func crashRecoveryRestoresSendingImageMessageAsUploadJob() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "crash_image_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "crash_image_conversation", userID: "crash_image_user", title: "Crash Image", sortTimestamp: 1)
        )
        let image = StoredImageContent(
            mediaID: "crash_image_media",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("crash_image.png").path,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("crash_image_thumb.jpg").path,
            width: 64,
            height: 64,
            sizeBytes: 256,
            format: "png"
        )
        let message = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "crash_image_user",
                conversationID: "crash_image_conversation",
                senderID: "crash_image_user",
                image: image,
                localTime: 800,
                messageID: "crash_image_message",
                clientMessageID: "crash_image_client",
                sortSequence: 800
            )
        )
        try await repository.updateImageUploadStatus(
            messageID: message.id,
            uploadStatus: .uploading,
            uploadAck: nil,
            sendStatus: .sending,
            sendAck: nil,
            pendingJob: nil
        )

        let result = try await repository.recoverInterruptedOutgoingMessages(
            userID: "crash_image_user",
            retryPolicy: MessageRetryPolicy(maxRetryCount: 5),
            now: 1_100
        )
        let storedMessage = try await repository.message(messageID: message.id)
        let job = try await repository.pendingJob(id: "image_upload_crash_image_client")
        let mediaRows = try await databaseContext.databaseActor.query(
            "SELECT upload_status FROM media_resource WHERE media_id = ? LIMIT 1;",
            parameters: [.text("crash_image_media")],
            paths: databaseContext.paths
        )

        #expect(result == MessageCrashRecoveryResult(scannedMessageCount: 1, recoveredMessageCount: 1, pendingJobCount: 1, failedMessageCount: 0))
        #expect(storedMessage?.state.sendStatus == .pending)
        #expect(try requireImageContent(storedMessage).uploadStatus == .pending)
        #expect(mediaRows.first?.int("upload_status") == MediaUploadStatus.pending.rawValue)
        #expect(job?.status == .pending)
        #expect(job?.type == .imageUpload)
        #expect(job?.bizKey == "crash_image_client")
        #expect(job?.nextRetryAt == 1_100)
        #expect(job?.payloadJSON.contains("interrupted") == true)
    }

    @Test func crashRecoveryIsIdempotentAndPreservesTerminalJobs() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "crash_idempotent_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "crash_idempotent_conversation", userID: "crash_idempotent_user", title: "Crash Idempotent", sortTimestamp: 1)
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "crash_idempotent_user",
                conversationID: "crash_idempotent_conversation",
                senderID: "crash_idempotent_user",
                text: "Do not duplicate",
                localTime: 900,
                messageID: "crash_idempotent_message",
                clientMessageID: "crash_idempotent_client",
                sortSequence: 900
            )
        )
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "message_resend_crash_idempotent_client",
                userID: "crash_idempotent_user",
                type: .messageResend,
                bizKey: "crash_idempotent_client",
                payloadJSON: #"{"terminal":true}"#,
                maxRetryCount: 1,
                nextRetryAt: 123
            )
        )
        try await repository.updatePendingJobStatus(
            jobID: "message_resend_crash_idempotent_client",
            status: .success,
            nextRetryAt: nil
        )

        let firstResult = try await repository.recoverInterruptedOutgoingMessages(
            userID: "crash_idempotent_user",
            retryPolicy: MessageRetryPolicy(maxRetryCount: 5),
            now: 1_200
        )
        let secondResult = try await repository.recoverInterruptedOutgoingMessages(
            userID: "crash_idempotent_user",
            retryPolicy: MessageRetryPolicy(maxRetryCount: 5),
            now: 1_300
        )
        let storedMessage = try await repository.message(messageID: message.id)
        let job = try await repository.pendingJob(id: "message_resend_crash_idempotent_client")
        let countRows = try await databaseContext.databaseActor.query(
            "SELECT COUNT(*) AS job_count FROM pending_job WHERE job_id = ?;",
            parameters: [.text("message_resend_crash_idempotent_client")],
            paths: databaseContext.paths
        )

        #expect(firstResult == MessageCrashRecoveryResult(scannedMessageCount: 1, recoveredMessageCount: 1, pendingJobCount: 1, failedMessageCount: 0))
        #expect(secondResult == MessageCrashRecoveryResult(scannedMessageCount: 0, recoveredMessageCount: 0, pendingJobCount: 0, failedMessageCount: 0))
        #expect(storedMessage?.state.sendStatus == .pending)
        #expect(job?.status == .success)
        #expect(job?.payloadJSON == #"{"terminal":true}"#)
        #expect(job?.maxRetryCount == 1)
        #expect(countRows.first?.int("job_count") == 1)
    }

    @MainActor
    @Test func networkRecoveryCoordinatorRecoversInterruptedMessagesBeforeRetrying() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "network_crash_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(id: "network_crash_conversation", userID: "network_crash_user", title: "Network Crash", sortTimestamp: 1)
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "network_crash_user",
                conversationID: "network_crash_conversation",
                senderID: "network_crash_user",
                text: "Recover then retry",
                localTime: 950,
                messageID: "network_crash_message",
                clientMessageID: "network_crash_client",
                sortSequence: 950
            )
        )
        let monitor = TestNetworkConnectivityMonitor(isReachable: false)
        let coordinator = NetworkRecoveryCoordinator(
            userID: "network_crash_user",
            storeProvider: storeProvider,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            monitor: monitor
        )

        coordinator.start()
        monitor.setReachable(true)
        try await waitForCondition {
            let job = try await repository.pendingJob(id: "message_resend_network_crash_client")
            return job?.status == .success
        }
        coordinator.stop()

        let storedMessage = try await repository.message(messageID: message.id)

        #expect(storedMessage?.state.sendStatus == .success)
        #expect(storedMessage?.delivery.serverMessageID == "server_network_crash_message")
        #expect(coordinator.lastCrashRecoveryResult?.recoveredMessageCount == 1)
        #expect(coordinator.lastRunResult?.successCount == 1)
    }

    @MainActor
    @Test func networkRecoveryCoordinatorRunsPendingJobsWhenNetworkRecovers() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "network_recovery_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(id: "network_recovery_conversation", userID: "network_recovery_user", title: "Network", sortTimestamp: 1)
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "network_recovery_user",
                conversationID: "network_recovery_conversation",
                senderID: "network_recovery_user",
                text: "Recover when online",
                localTime: 400,
                messageID: "network_recovery_message",
                clientMessageID: "network_recovery_client",
                sortSequence: 400
            )
        )
        try await repository.updateMessageSendStatus(messageID: message.id, status: .failed, ack: nil)
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "message_resend_network_recovery_client",
                userID: "network_recovery_user",
                type: .messageResend,
                bizKey: "network_recovery_client",
                payloadJSON: #"{"messageID":"network_recovery_message","conversationID":"network_recovery_conversation","clientMessageID":"network_recovery_client","lastFailureReason":"offline"}"#,
                nextRetryAt: 1
            )
        )
        let monitor = TestNetworkConnectivityMonitor(isReachable: false)
        let coordinator = NetworkRecoveryCoordinator(
            userID: "network_recovery_user",
            storeProvider: storeProvider,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            monitor: monitor
        )

        coordinator.start()
        monitor.setReachable(true)
        try await waitForCondition {
            let job = try await repository.pendingJob(id: "message_resend_network_recovery_client")
            return job?.status == .success
        }
        coordinator.stop()

        let storedMessage = try await repository.message(messageID: message.id)

        #expect(storedMessage?.state.sendStatus == .success)
        #expect(storedMessage?.delivery.serverMessageID == "server_network_recovery_message")
        #expect(coordinator.lastRunResult?.successCount == 1)
    }

    @Test func repositoryDeletesMessageAndRefreshesConversationSummary() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "delete_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "delete_conversation", userID: "delete_user", title: "Delete", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "delete_user",
                conversationID: "delete_conversation",
                senderID: "delete_user",
                text: "First visible",
                localTime: 100,
                messageID: "delete_first",
                clientMessageID: "delete_first_client",
                sortSequence: 100
            )
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "delete_user",
                conversationID: "delete_conversation",
                senderID: "delete_user",
                text: "Delete me",
                localTime: 200,
                messageID: "delete_second",
                clientMessageID: "delete_second_client",
                sortSequence: 200
            )
        )

        try await repository.markMessageDeleted(messageID: "delete_second", userID: "delete_user")

        let messages = try await repository.listMessages(conversationID: "delete_conversation", limit: 20, beforeSortSeq: nil)
        let conversations = try await repository.listConversations(for: "delete_user")

        #expect(messages.map(\.id.rawValue) == ["delete_first"])
        #expect(conversations.first?.lastMessageDigest == "First visible")
    }

    @Test func repositoryRevokesMessageAndPersistsReplacementText() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "revoke_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "revoke_conversation", userID: "revoke_user", title: "Revoke", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "revoke_user",
                conversationID: "revoke_conversation",
                senderID: "revoke_user",
                text: "Secret",
                localTime: 300,
                messageID: "revoke_message",
                clientMessageID: "revoke_client",
                sortSequence: 300
            )
        )

        let revokedMessage = try await repository.revokeMessage(
            messageID: "revoke_message",
            userID: "revoke_user",
            replacementText: "你撤回了一条消息"
        )
        let reloadedMessage = try await repository.message(messageID: "revoke_message")!
        let conversations = try await repository.listConversations(for: "revoke_user")

        #expect(revokedMessage.state.isRevoked)
        #expect(reloadedMessage.state.isRevoked)
        #expect(reloadedMessage.state.revokeReplacementText == "你撤回了一条消息")
        #expect(conversations.first?.lastMessageDigest == "你撤回了一条消息")
    }

    @Test func draftIsPersistedAndPrioritizedInConversationList() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "draft_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let repository = try await storeProvider.repository()
        try await repository.saveDraft(
            conversationID: "system_release",
            userID: "draft_user",
            text: "Remember this"
        )

        let draftText = try await repository.draft(conversationID: "system_release", userID: "draft_user")
        let rows = try await LocalConversationListUseCase(
            userID: "draft_user",
            storeProvider: storeProvider
        ).loadConversations()
        let draftRowIndex = rows.firstIndex { $0.id == "system_release" }
        let otherUnpinnedRowIndex = rows.firstIndex { $0.id == "group_core" }

        #expect(draftText == "Remember this")
        #expect(draftRowIndex != nil)
        #expect(otherUnpinnedRowIndex != nil)
        #expect((draftRowIndex ?? 0) < (otherUnpinnedRowIndex ?? 0))
        #expect(rows[draftRowIndex ?? 0].subtitle == "Draft: Remember this")

        try await repository.clearDraft(conversationID: "system_release", userID: "draft_user")
        #expect(try await repository.draft(conversationID: "system_release", userID: "draft_user") == nil)
    }

    @Test func chatUseCaseMarksConversationReadWhenLoadingMessages() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "read_user")
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "read_conversation",
                userID: "read_user",
                title: "Read",
                unreadCount: 3,
                sortTimestamp: 1
            )
        )

        let useCase = LocalChatUseCase(
            userID: "read_user",
            conversationID: "read_conversation",
            repository: repository,
            conversationRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        _ = try await useCase.loadInitialMessages()
        let conversations = try await repository.listConversations(for: "read_user")

        #expect(conversations.first?.unreadCount == 0)
    }

    @Test func localChatRepositoryMarksIncomingMessagesReadWhenConversationIsRead() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "message_read_user")
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "message_read_conversation",
                userID: "message_read_user",
                title: "Message Read",
                unreadCount: 1,
                sortTimestamp: 1
            )
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "message_read_user",
                conversationID: "message_read_conversation",
                senderID: "friend_user",
                text: "Unread before opening",
                localTime: 10,
                messageID: "message_read_text",
                clientMessageID: "message_read_client",
                sortSequence: 10
            )
        )
        try await databaseContext.databaseActor.execute(
            "UPDATE message SET direction = ?, read_status = ? WHERE message_id = ?;",
            parameters: [
                .integer(Int64(MessageDirection.incoming.rawValue)),
                .integer(Int64(MessageReadStatus.unread.rawValue)),
                .text(message.id.rawValue)
            ],
            paths: databaseContext.paths
        )

        let unreadMessage = try await repository.message(messageID: message.id)
        try await repository.markConversationRead(conversationID: "message_read_conversation", userID: "message_read_user")

        let conversations = try await repository.listConversations(for: "message_read_user")
        let storedMessage = try await repository.message(messageID: message.id)
        #expect(unreadMessage?.state.readStatus == .unread)
        #expect(conversations.first?.unreadCount == 0)
        #expect(storedMessage?.state.readStatus == .read)
    }

    @Test func chatUseCaseMarksIncomingVoicePlayedAndClearsUnreadDot() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "voice_dot_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "voice_dot_conversation", userID: "voice_dot_user", title: "Voice Dot", sortTimestamp: 1)
        )
        let voice = StoredVoiceContent(
            mediaID: "media_voice_dot",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("voice/media_voice_dot.m4a").path,
            durationMilliseconds: 2_100,
            sizeBytes: 512,
            format: "m4a"
        )
        let insertedMessage = try await repository.insertOutgoingVoiceMessage(
            OutgoingVoiceMessageInput(
                userID: "voice_dot_user",
                conversationID: "voice_dot_conversation",
                senderID: "friend_user",
                voice: voice,
                localTime: 530,
                messageID: "voice_dot_message",
                clientMessageID: "voice_dot_client",
                sortSequence: 530
            )
        )
        try await databaseContext.databaseActor.execute(
            "UPDATE message SET read_status = ? WHERE message_id = ?;",
            parameters: [
                .integer(Int64(MessageReadStatus.unread.rawValue)),
                .text(insertedMessage.id.rawValue)
            ],
            paths: databaseContext.paths
        )

        let useCase = LocalChatUseCase(
            userID: "voice_dot_user",
            conversationID: "voice_dot_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let initialPage = try await useCase.loadInitialMessages()
        let playedRow = try await useCase.markVoicePlayed(messageID: insertedMessage.id)
        let storedMessage = try await repository.message(messageID: insertedMessage.id)

        #expect(initialPage.rows.first.map(isUnplayedVoiceContent) == true)
        #expect(initialPage.rows.first.flatMap(voiceLocalPath) == voice.localPath)
        #expect(playedRow.map(isUnplayedVoiceContent) == false)
        #expect(storedMessage?.state.readStatus == .read)
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
    @Test func chatViewControllerKeepsSentImageAboveInputBarAfterThumbnailSizing() async throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let thumbnailURL = directory.appendingPathComponent("sent-portrait.jpg")
        try makeJPEGData(width: 180, height: 320, quality: 0.9).write(to: thumbnailURL, options: [.atomic])

        let initialRows = (1...36).map { index in
            makeChatRow(
                id: MessageID(rawValue: "sent_image_initial_\(index)"),
                text: "Sent image initial \(index)",
                sortSequence: Int64(index)
            )
        }
        let useCase = ImageSendingStubChatUseCase(
            initialRows: initialRows,
            thumbnailPath: thumbnailURL.path
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Sent Image")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            guard let collectionView = findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView else {
                return false
            }
            return collectionView.numberOfItems(inSection: 0) == initialRows.count
        }
        window.layoutIfNeeded()

        let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
        let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
        collectionView.scrollToItem(at: IndexPath(item: initialRows.count - 1, section: 0), at: .bottom, animated: false)
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        viewModel.sendImage(data: samplePNGData(), preferredFileExtension: "jpg")
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            collectionView.numberOfItems(inSection: 0) == initialRows.count + 1
        }
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let disturbedOffsetY = max(
            -collectionView.adjustedContentInset.top,
            collectionView.contentOffset.y - 360
        )
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: disturbedOffsetY),
            animated: false
        )
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        #expect(
            latestMessageCellIsAboveInputBar(
                collectionView: collectionView,
                item: initialRows.count,
                inputBar: inputBar,
                in: viewController.view
            ) == false
        )

        try await Task.sleep(nanoseconds: 500_000_000)
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        #expect(
            latestMessageCellIsAboveInputBar(
                collectionView: collectionView,
                item: initialRows.count,
                inputBar: inputBar,
                in: viewController.view
            )
        )
    }

    @MainActor
    @Test func chatViewControllerPreservesVisibleAnchorWhenLoadingOlderMessages() async throws {
        let initialRows = (1...36).map { index in
            let text = "当前消息 \(index)\n用多行内容触发自适应高度\n保证历史分页补偿不能依赖固定行高"
            return makeChatRow(
                id: MessageID(rawValue: "history_anchor_current_\(index)"),
                text: text,
                sortSequence: Int64(index + 10),
                sentAt: Int64(1_000 + (index - 1) * 360)
            )
        }
        let olderRows = (1...10).map { index in
            let text = "历史消息 \(index)\n这批消息插入到顶部\n高度和当前消息不同"
            return makeChatRow(
                id: MessageID(rawValue: "history_anchor_older_\(index)"),
                text: text,
                sortSequence: Int64(index),
                sentAt: Int64(400 + index * 36)
            )
        }
        let useCase = DeferredOlderPageStubChatUseCase(
            initialPage: ChatMessagePage(rows: initialRows, hasMore: true, nextBeforeSortSequence: 11),
            olderPage: ChatMessagePage(rows: olderRows, hasMore: false, nextBeforeSortSequence: nil)
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "History Anchor")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            collectionView.numberOfItems(inSection: 0) == initialRows.count
        }
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: -collectionView.adjustedContentInset.top),
            animated: false
        )
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        // 回归点和生产逻辑一致：选取当前屏幕内第一条仍会存在的旧消息做锚点，
        // 避免测试固定第 0 条时被导航栏遮挡、时间分隔符重算等边界状态干扰。
        let visibleTopY = collectionView.contentOffset.y
        let visibleOldIndexPaths = collectionView.indexPathsForVisibleItems
            .filter { $0.item < initialRows.count && collectionView.cellForItem(at: $0) != nil }
            .sorted { $0.item < $1.item }
        let anchorIndexPathBefore = try #require(
            visibleOldIndexPaths.first { indexPath in
                guard let cell = collectionView.cellForItem(at: indexPath) else { return false }
                return cell.frame.minY >= visibleTopY
            } ?? visibleOldIndexPaths.first
        )
        let anchorCellBefore = try #require(collectionView.cellForItem(at: anchorIndexPathBefore))
        let anchorMinYBefore = anchorCellBefore.convert(anchorCellBefore.bounds, to: viewController.view).minY

        if useCase.loadOlderCallCount == 0 {
            viewModel.loadOlderMessagesIfNeeded()
        }
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            useCase.loadOlderCallCount == 1
        }
        useCase.releaseOlderPage()
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            collectionView.numberOfItems(inSection: 0) == initialRows.count + olderRows.count
        }
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            let anchorIndexPathAfter = IndexPath(item: olderRows.count + anchorIndexPathBefore.item, section: 0)
            guard let anchorCellAfter = collectionView.cellForItem(at: anchorIndexPathAfter) else {
                return false
            }
            let anchorMinYAfter = anchorCellAfter.convert(anchorCellAfter.bounds, to: viewController.view).minY
            let anchorDelta = Foundation.fabs(Double(anchorMinYAfter) - Double(anchorMinYBefore))
            return anchorDelta <= 2
        }

        let anchorCellAfter = try #require(
            collectionView.cellForItem(at: IndexPath(item: olderRows.count + anchorIndexPathBefore.item, section: 0))
        )
        let anchorMinYAfter = anchorCellAfter.convert(anchorCellAfter.bounds, to: viewController.view).minY
        let anchorDelta = Foundation.fabs(Double(anchorMinYAfter) - Double(anchorMinYBefore))

        #expect(anchorDelta <= 2)
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
    @Test func chatViewControllerUsesConversationListBackground() throws {
        let viewModel = ChatViewModel(useCase: SimulatedIncomingStubChatUseCase(), title: "Background")
        let viewController = ChatViewController(viewModel: viewModel)

        viewController.loadViewIfNeeded()

        let traits = UITraitCollection(userInterfaceStyle: .light)
        #expect(viewController.view.backgroundColor?.resolvedColor(with: traits) == UIColor.systemBackground.resolvedColor(with: traits))
        #expect(findView(ofType: GradientBackgroundView.self, in: viewController.view) == nil)
    }

    @MainActor
    @Test func chatViewControllerUsesFullscreenCollectionViewWithInputInset() async throws {
        let rows = (1...24).map { index in
            makeChatRow(
                id: MessageID(rawValue: "fullscreen_layout_\(index)"),
                text: "Fullscreen layout message \(index)",
                sortSequence: Int64(index)
            )
        }
        let useCase = PagingStubChatUseCase(
            initialPage: ChatMessagePage(rows: rows, hasMore: false, nextBeforeSortSequence: nil),
            olderPage: ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Fullscreen Layout")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            guard let collectionView = findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView else {
                return false
            }
            return collectionView.numberOfItems(inSection: 0) == rows.count
        }
        window.layoutIfNeeded()

        let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
        let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
        let collectionFrame = collectionView.convert(collectionView.bounds, to: viewController.view)
        let inputFrame = inputBar.convert(inputBar.bounds, to: viewController.view)

        #expect(abs(collectionFrame.minY - viewController.view.bounds.minY) <= 1)
        #expect(abs(collectionFrame.maxY - viewController.view.bounds.maxY) <= 1)
        #expect(collectionView.contentInset.bottom >= viewController.view.bounds.maxY - inputFrame.minY - 1)
        #expect(collectionView.verticalScrollIndicatorInsets.bottom == collectionView.contentInset.bottom)
    }

    @MainActor
    @Test func chatViewControllerKeepsBottomAnchoredWhenAttachmentPreviewAppearsAfterLayoutDrift() async throws {
        let rows = (1...28).map { index in
            makeChatRow(
                id: MessageID(rawValue: "layout_drift_\(index)"),
                text: "Layout drift message \(index)",
                sortSequence: Int64(index)
            )
        }
        let useCase = PagingStubChatUseCase(
            initialPage: ChatMessagePage(rows: rows, hasMore: false, nextBeforeSortSequence: nil),
            olderPage: ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Layout")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            guard let collectionView = findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView else {
                return false
            }
            return collectionView.numberOfItems(inSection: 0) == rows.count
        }
        window.layoutIfNeeded()

        let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
        let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
        collectionView.scrollToItem(at: IndexPath(item: rows.count - 1, section: 0), at: .bottom, animated: false)
        collectionView.layoutIfNeeded()

        let visibleHeight = collectionView.bounds.height
            - collectionView.adjustedContentInset.top
            - collectionView.adjustedContentInset.bottom
        let maxOffsetY = collectionView.contentSize.height
            - visibleHeight
            + collectionView.adjustedContentInset.bottom
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: maxOffsetY - 140),
            animated: false
        )

        inputBar.setPendingAttachmentPreviews([
            ChatPendingAttachmentPreviewItem(
                id: "layout-drift-photo",
                image: nil,
                title: "Image ready",
                durationText: nil,
                isVideo: false,
                isLoading: false
            )
        ], animated: false)
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let lastCell = try #require(collectionView.cellForItem(at: IndexPath(item: rows.count - 1, section: 0)))
        let lastCellFrame = lastCell.convert(lastCell.bounds, to: viewController.view)
        let inputBarFrame = inputBar.convert(inputBar.bounds, to: viewController.view)
        #expect(lastCellFrame.maxY <= inputBarFrame.minY + 1)
    }

    @MainActor
    @Test func chatViewControllerKeepsInitialLatestMessageAboveInputBarAfterFirstLayout() async throws {
        let rows = (1...36).map { index in
            makeChatRow(
                id: MessageID(rawValue: "initial_visible_\(index)"),
                text: "Initial visible message \(index)",
                sortSequence: Int64(index)
            )
        }
        let useCase = PagingStubChatUseCase(
            initialPage: ChatMessagePage(rows: rows, hasMore: false, nextBeforeSortSequence: nil),
            olderPage: ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Initial Visible")
        let viewController = ChatViewController(viewModel: viewModel)

        viewController.loadViewIfNeeded()
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            guard let collectionView = findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView else {
                return false
            }
            return collectionView.numberOfItems(inSection: 0) == rows.count
        }

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        window.layoutIfNeeded()

        let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
        let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
        collectionView.layoutIfNeeded()

        let lastCell = try #require(collectionView.cellForItem(at: IndexPath(item: rows.count - 1, section: 0)))
        let lastCellFrame = lastCell.convert(lastCell.bounds, to: viewController.view)
        let inputBarFrame = inputBar.convert(inputBar.bounds, to: viewController.view)
        #expect(lastCellFrame.maxY <= inputBarFrame.minY + 1)
    }

    @MainActor
    @Test func chatViewControllerDoesNotAddTopWhitespaceForShortInitialConversation() async throws {
        let rows = (1...3).map { index in
            makeChatRow(
                id: MessageID(rawValue: "short_initial_visible_\(index)"),
                text: "Short initial message \(index)",
                sortSequence: Int64(index),
                isOutgoing: index == 3
            )
        }
        let useCase = DeferredInitialPageStubChatUseCase(
            initialPage: ChatMessagePage(rows: rows, hasMore: false, nextBeforeSortSequence: nil)
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Short Initial")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        window.layoutIfNeeded()
        useCase.releaseInitialPage()
        let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            collectionView.numberOfItems(inSection: 0) == rows.count
        }
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let firstCell = try #require(collectionView.cellForItem(at: IndexPath(item: 0, section: 0)))
        let firstCellFrame = firstCell.convert(firstCell.bounds, to: viewController.view)
        let collectionFrame = collectionView.convert(collectionView.bounds, to: viewController.view)
        let expectedTopY = collectionFrame.minY + collectionView.adjustedContentInset.top

        #expect(collectionView.contentInset.top <= viewController.view.safeAreaInsets.top + 1)
        #expect(firstCellFrame.minY <= expectedTopY + 32)
    }

    @MainActor
    @Test func chatViewControllerKeepsInitialLatestMessageAboveInputBarWhenEnteringFromNavigation() async throws {
        let rows = (1...120).map { index in
            makeChatRow(
                id: MessageID(rawValue: "initial_navigation_visible_\(index)"),
                text: "模拟推送链路应立即刷新可见界面 #4ee2ef 第 \(index) 条，这是一段用于触发多行自适应高度的聊天消息内容。",
                sortSequence: Int64(index),
                isOutgoing: index % 5 == 0
            )
        }
        let useCase = DeferredInitialPageStubChatUseCase(
            initialPage: ChatMessagePage(rows: rows, hasMore: false, nextBeforeSortSequence: nil)
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Sondra")
        let viewController = ChatViewController(viewModel: viewModel)
        let navigationController = UINavigationController(rootViewController: viewController)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        window.layoutIfNeeded()
        useCase.releaseInitialPage()
        let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            collectionView.numberOfItems(inSection: 0) == rows.count
        }
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
        let lastCell = try #require(collectionView.cellForItem(at: IndexPath(item: rows.count - 1, section: 0)))
        let lastCellFrame = lastCell.convert(lastCell.bounds, to: viewController.view)
        let inputBarFrame = inputBar.convert(inputBar.bounds, to: viewController.view)
        #expect(lastCellFrame.maxY <= inputBarFrame.minY + 1)
    }

    @MainActor
    @Test func chatViewControllerKeepsInitialImageMessagesAboveInputBar() async throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let imageSizes: [(width: Int, height: Int)] = [
            (320, 180),
            (180, 320),
            (320, 180),
            (320, 180),
            (180, 320),
            (320, 180)
        ]
        let rows = try imageSizes.enumerated().map { index, size in
            let sequence = index + 1
            let thumbnailURL = directory.appendingPathComponent("initial_image_\(sequence).jpg")
            try makeJPEGData(width: size.width, height: size.height, quality: 0.9)
                .write(to: thumbnailURL, options: [.atomic])
            return ChatMessageRowState(
                id: MessageID(rawValue: "initial_image_visible_\(sequence)"),
                content: .image(.init(thumbnailPath: thumbnailURL.path)),
                sortSequence: Int64(sequence),
                timeText: "Now",
                statusText: nil,
                uploadProgress: nil,
                isOutgoing: true,
                canRetry: false,
                canDelete: true,
                canRevoke: false
            )
        }
        let useCase = DeferredInitialPageStubChatUseCase(
            initialPage: ChatMessagePage(rows: rows, hasMore: false, nextBeforeSortSequence: nil)
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Sondra")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        window.layoutIfNeeded()
        useCase.releaseInitialPage()
        let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            collectionView.numberOfItems(inSection: 0) == rows.count
        }
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
        let lastCell = try #require(collectionView.cellForItem(at: IndexPath(item: rows.count - 1, section: 0)))
        let lastCellFrame = lastCell.convert(lastCell.bounds, to: viewController.view)
        let inputBarFrame = inputBar.convert(inputBar.bounds, to: viewController.view)
        #expect(lastCellFrame.maxY <= inputBarFrame.minY + 1)
    }

    @MainActor
    @Test func chatViewControllerDoesNotScrollInitialMessagesBeforeViewEntersWindow() async throws {
        let rows = (1...36).map { index in
            makeChatRow(
                id: MessageID(rawValue: "initial_deferred_window_\(index)"),
                text: "Initial deferred window message \(index)",
                sortSequence: Int64(index)
            )
        }
        let useCase = DeferredInitialPageStubChatUseCase(
            initialPage: ChatMessagePage(rows: rows, hasMore: false, nextBeforeSortSequence: nil)
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Initial Deferred Window")
        let viewController = ChatViewController(viewModel: viewModel)

        viewController.loadViewIfNeeded()
        let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
        useCase.releaseInitialPage()

        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            return collectionView.numberOfItems(inSection: 0) == rows.count
        }
        collectionView.layoutIfNeeded()

        let topOffsetY = -collectionView.adjustedContentInset.top
        #expect(abs(collectionView.contentOffset.y - topOffsetY) <= 1)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        window.layoutIfNeeded()

        let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
        collectionView.layoutIfNeeded()

        let stableOffsetY = collectionView.contentOffset.y
        viewController.viewDidLayoutSubviews()
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        #expect(abs(collectionView.contentOffset.y - stableOffsetY) <= 1)

        let lastCell = try #require(collectionView.cellForItem(at: IndexPath(item: rows.count - 1, section: 0)))
        let lastCellFrame = lastCell.convert(lastCell.bounds, to: viewController.view)
        let inputBarFrame = inputBar.convert(inputBar.bounds, to: viewController.view)
        #expect(lastCellFrame.maxY <= inputBarFrame.minY + 1)
    }

    @MainActor
    @Test func chatViewControllerAllowsManualScrollAwayFromBottomAfterBottomBounce() async throws {
        let setup = try await makeScrollableChatViewController(
            title: "Bottom Bounce",
            rowPrefix: "bottom_bounce"
        )
        defer {
            setup.window.isHidden = true
            setup.window.rootViewController = nil
        }

        try assertChatCollectionCanLeaveBottomAfterUserDrag(
            viewController: setup.viewController,
            collectionView: setup.collectionView,
            window: setup.window
        )
    }

    @MainActor
    @Test func chatViewControllerAllowsManualScrollAwayFromBottomAfterBottomBounceWithEmojiPanel() async throws {
        let setup = try await makeScrollableChatViewController(
            title: "Emoji Bounce",
            rowPrefix: "emoji_bounce",
            useEmojiUseCase: true
        )
        defer {
            setup.window.isHidden = true
            setup.window.rootViewController = nil
        }

        setup.inputBar.onEmojiTapped?()
        setup.window.layoutIfNeeded()

        try assertChatCollectionCanLeaveBottomAfterUserDrag(
            viewController: setup.viewController,
            collectionView: setup.collectionView,
            window: setup.window
        )
    }

    @MainActor
    @Test func chatViewControllerAllowsManualScrollAwayFromBottomAfterBottomBounceWithPhotoLibraryPanel() async throws {
        let setup = try await makeScrollableChatViewController(
            title: "Photo Bounce",
            rowPrefix: "photo_bounce"
        )
        defer {
            setup.window.isHidden = true
            setup.window.rootViewController = nil
        }

        setup.inputBar.onPhotoTapped?()
        setup.window.layoutIfNeeded()

        try assertChatCollectionCanLeaveBottomAfterUserDrag(
            viewController: setup.viewController,
            collectionView: setup.collectionView,
            window: setup.window
        )
    }

    @MainActor
    @Test func chatViewControllerKeepsBottomAnchoredWhilePhotoLibraryPanelIsDragged() async throws {
        let rows = (1...28).map { index in
            makeChatRow(
                id: MessageID(rawValue: "photo_drag_\(index)"),
                text: "Photo drag message \(index)",
                sortSequence: Int64(index)
            )
        }
        let useCase = PagingStubChatUseCase(
            initialPage: ChatMessagePage(rows: rows, hasMore: false, nextBeforeSortSequence: nil),
            olderPage: ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Photo Drag")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            guard let collectionView = findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView else {
                return false
            }
            return collectionView.numberOfItems(inSection: 0) == rows.count
        }
        window.layoutIfNeeded()

        let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
        let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
        let photoPanel = try #require(findView(ofType: ChatPhotoLibraryInputView.self, in: viewController.view))

        inputBar.setPendingAttachmentPreviews([
            ChatPendingAttachmentPreviewItem(
                id: "photo-drag-1",
                image: nil,
                title: "Image ready",
                durationText: nil,
                isVideo: false,
                isLoading: false
            ),
            ChatPendingAttachmentPreviewItem(
                id: "photo-drag-2",
                image: nil,
                title: "Image ready",
                durationText: nil,
                isVideo: false,
                isLoading: false
            )
        ], animated: false)
        inputBar.onPhotoTapped?()
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(at: IndexPath(item: rows.count - 1, section: 0), at: .bottom, animated: false)
        collectionView.layoutIfNeeded()

        let visibleHeight = collectionView.bounds.height
            - collectionView.adjustedContentInset.top
            - collectionView.adjustedContentInset.bottom
        let maxOffsetY = collectionView.contentSize.height
            - visibleHeight
            + collectionView.adjustedContentInset.bottom
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: maxOffsetY - 140),
            animated: false
        )

        photoPanel.onDismissPanChanged?(96)
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let lastCell = try #require(collectionView.cellForItem(at: IndexPath(item: rows.count - 1, section: 0)))
        let lastCellFrame = lastCell.convert(lastCell.bounds, to: viewController.view)
        let inputBarFrame = inputBar.convert(inputBar.bounds, to: viewController.view)
        #expect(lastCellFrame.maxY <= inputBarFrame.minY + 1)
    }

    @MainActor
    @Test func chatInputBarAttachmentPreviewControlsSendState() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))
        inputBar.layoutIfNeeded()

        #expect(button(in: inputBar, identifier: "chat.voiceButton")?.isEnabled == true)
        #expect(button(in: inputBar, identifier: "chat.sendButton") == nil)

        inputBar.setPendingAttachmentPreviews([
            ChatPendingAttachmentPreviewItem(
                id: "photo-1",
                image: nil,
                title: "Image ready",
                durationText: nil,
                isVideo: false,
                isLoading: false
            ),
            ChatPendingAttachmentPreviewItem(
                id: "video-1",
                image: nil,
                title: "Preparing video...",
                durationText: "0:03",
                isVideo: true,
                isLoading: true
            )
        ], animated: false)
        #expect(button(in: inputBar, identifier: "chat.voiceButton")?.isEnabled == false)

        inputBar.setPendingAttachmentPreviews([
            ChatPendingAttachmentPreviewItem(
                id: "photo-1",
                image: nil,
                title: "Image ready",
                durationText: nil,
                isVideo: false,
                isLoading: false
            ),
            ChatPendingAttachmentPreviewItem(
                id: "video-1",
                image: nil,
                title: "Video ready",
                durationText: "0:03",
                isVideo: true,
                isLoading: false
            )
        ], animated: false)
        #expect(button(in: inputBar, identifier: "chat.sendButton")?.isEnabled == true)

        inputBar.clearPendingAttachmentPreviews(animated: false)
        #expect(button(in: inputBar, identifier: "chat.sendButton") == nil)
        #expect(button(in: inputBar, identifier: "chat.voiceButton")?.isEnabled == true)
    }

    @MainActor
    @Test func chatInputBarShowsRecordingWaveformAndStopButtonWhileRecording() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))

        inputBar.renderVoiceRecordingState(
            VoiceRecordingState(
                isRecording: true,
                isCanceling: false,
                elapsedMilliseconds: 4_200,
                averagePowerLevel: 0.64,
                hintText: "Release to preview"
            )
        )
        inputBar.layoutIfNeeded()

        #expect(findView(in: inputBar, identifier: "chat.recordingWaveform") != nil)
        #expect(button(in: inputBar, identifier: "chat.voiceStopButton")?.isEnabled == true)
        #expect(button(in: inputBar, identifier: "chat.sendButton") == nil)
    }

    @MainActor
    @Test func chatInputBarShowsVoicePreviewControlsAfterRecordingCompletes() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))

        inputBar.setPendingVoicePreview(durationMilliseconds: 4_200, isPlaying: false, animated: false)
        inputBar.layoutIfNeeded()

        #expect(button(in: inputBar, identifier: "chat.voicePreviewCancelButton")?.isEnabled == true)
        #expect(button(in: inputBar, identifier: "chat.voicePreviewPlayButton")?.isEnabled == true)
        #expect(findView(in: inputBar, identifier: "chat.voicePreviewWaveform") != nil)
        #expect(button(in: inputBar, identifier: "chat.voicePreviewSendButton")?.isEnabled == true)
        #expect(button(in: inputBar, identifier: "chat.sendButton") == nil)
    }

    @MainActor
    @Test func chatInputBarShowsVoicePreviewPlaybackElapsedAndTotalDuration() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))

        inputBar.setPendingVoicePreview(
            durationMilliseconds: 4_200,
            isPlaying: true,
            playbackProgress: 0.25,
            playbackElapsedMilliseconds: 1_000,
            animated: false
        )
        inputBar.layoutIfNeeded()

        #expect(findLabel(withText: "0:01/0:04", in: inputBar) != nil)
    }

    @MainActor
    @Test func chatInputBarPreviewSendDoesNotTriggerTextSend() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))
        var textSendCount = 0
        var voicePreviewSendCount = 0
        inputBar.onSend = { _ in
            textSendCount += 1
        }
        inputBar.onVoicePreviewSend = {
            voicePreviewSendCount += 1
        }

        inputBar.setPendingVoicePreview(durationMilliseconds: 4_200, isPlaying: false, animated: false)
        button(in: inputBar, identifier: "chat.voicePreviewSendButton")?.sendActions(for: .touchUpInside)

        #expect(textSendCount == 0)
        #expect(voicePreviewSendCount == 1)
    }

    @MainActor
    @Test func chatInputBarNotifiesHeightChangeWhenTransientStatusAppears() {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))
        var didAskForBottomStick = false
        var didFinishHeightChange = false

        inputBar.onHeightWillChange = {
            didAskForBottomStick = true
            return true
        }
        inputBar.onHeightDidChange = { shouldStickToBottom in
            didFinishHeightChange = shouldStickToBottom
        }

        inputBar.showTransientStatus("Voice too short")
        inputBar.layoutIfNeeded()

        #expect(didAskForBottomStick)
        #expect(didFinishHeightChange)
    }

    @MainActor
    @Test func chatInputBarClearingVoicePreviewRestoresVoiceButton() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))

        inputBar.setPendingVoicePreview(durationMilliseconds: 4_200, isPlaying: false, animated: false)
        inputBar.clearPendingVoicePreview(animated: false)
        inputBar.layoutIfNeeded()

        #expect(button(in: inputBar, identifier: "chat.voiceButton")?.isEnabled == true)
        #expect(button(in: inputBar, identifier: "chat.voicePreviewSendButton") == nil)
    }

    @MainActor
    @Test func chatInputBarRemovesSelectedAttachmentPreviewItem() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 150))
        var removedIDs: [String] = []
        inputBar.onAttachmentRemoved = { id in
            removedIDs.append(id)
        }

        inputBar.setPendingAttachmentPreviews([
            ChatPendingAttachmentPreviewItem(
                id: "photo-1",
                image: nil,
                title: "Image ready",
                durationText: nil,
                isVideo: false,
                isLoading: false
            ),
            ChatPendingAttachmentPreviewItem(
                id: "photo-2",
                image: nil,
                title: "Image ready",
                durationText: nil,
                isVideo: false,
                isLoading: false
            )
        ], animated: false)
        inputBar.layoutIfNeeded()

        button(in: inputBar, identifier: "chat.removeAttachmentButton.photo-1")?.sendActions(for: .touchUpInside)

        #expect(removedIDs == ["photo-1"])
        #expect(findView(in: inputBar, identifier: "chat.pendingAttachmentPreviewItem.photo-1") == nil)
        #expect(findView(in: inputBar, identifier: "chat.pendingAttachmentPreviewItem.photo-2") != nil)
        #expect(button(in: inputBar, identifier: "chat.sendButton")?.isEnabled == true)

        button(in: inputBar, identifier: "chat.removeAttachmentButton.photo-2")?.sendActions(for: .touchUpInside)

        #expect(removedIDs == ["photo-1", "photo-2"])
        #expect(findView(in: inputBar, identifier: "chat.pendingAttachmentPreview")?.isHidden == true)
        #expect(button(in: inputBar, identifier: "chat.voiceButton")?.isEnabled == true)
    }

    @MainActor
    @Test func chatInputBarUsesCompactMessagesAttachmentPreviewControls() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 150))

        inputBar.setPendingAttachmentPreviews([
            ChatPendingAttachmentPreviewItem(
                id: "photo-1",
                image: nil,
                title: "Image ready",
                durationText: nil,
                isVideo: false,
                isLoading: false
            )
        ], animated: false)
        inputBar.layoutIfNeeded()

        let itemView = try #require(findView(in: inputBar, identifier: "chat.pendingAttachmentPreviewItem.photo-1"))
        let removeButton = try #require(button(in: inputBar, identifier: "chat.removeAttachmentButton.photo-1"))
        let scrollView = try #require(itemView.superview?.superview as? UIScrollView)
        itemView.layoutIfNeeded()
        removeButton.layoutIfNeeded()
        let buttonFrameInItem = removeButton.convert(removeButton.bounds, to: itemView)
        let buttonFrameInScrollView = removeButton.convert(removeButton.bounds, to: scrollView)

        #expect(itemView.bounds.width == 74)
        #expect(itemView.bounds.height == 74)
        #expect(buttonFrameInItem.width == 24)
        #expect(buttonFrameInItem.height == 24)
        #expect(buttonFrameInScrollView.minX >= 0)
        #expect(buttonFrameInScrollView.minY >= 0)
        #expect(buttonFrameInScrollView.maxX <= scrollView.bounds.maxX)
        #expect(buttonFrameInScrollView.maxY <= scrollView.bounds.maxY)
        #expect(removeButton.clipsToBounds == true)
        #expect(removeButton.layer.cornerRadius == 12)
    }

    @MainActor
    @Test func chatInputBarAttachmentPreviewScrollsAcrossFullInputWidth() throws {
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 150))
        let inputBar = ChatInputBarView()
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(inputBar)
        NSLayoutConstraint.activate([
            inputBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            inputBar.topAnchor.constraint(equalTo: containerView.topAnchor),
            inputBar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        inputBar.setPendingAttachmentPreviews([
            ChatPendingAttachmentPreviewItem(
                id: "photo-1",
                image: nil,
                title: "Image ready",
                durationText: nil,
                isVideo: false,
                isLoading: false
            ),
            ChatPendingAttachmentPreviewItem(
                id: "photo-2",
                image: nil,
                title: "Image ready",
                durationText: nil,
                isVideo: false,
                isLoading: false
            ),
            ChatPendingAttachmentPreviewItem(
                id: "photo-3",
                image: nil,
                title: "Image ready",
                durationText: nil,
                isVideo: false,
                isLoading: false
            )
        ], animated: false)
        containerView.layoutIfNeeded()

        let firstItemView = try #require(findView(in: inputBar, identifier: "chat.pendingAttachmentPreviewItem.photo-1"))
        let scrollView = try #require(firstItemView.superview?.superview as? UIScrollView)
        let moreButton = try #require(button(in: inputBar, identifier: "chat.moreButton"))
        let scrollFrame = scrollView.convert(scrollView.bounds, to: inputBar)
        let moreButtonFrame = moreButton.convert(moreButton.bounds, to: inputBar)

        #expect(scrollFrame.minX == 0)
        #expect(scrollFrame.maxX == inputBar.bounds.width)
        #expect(moreButtonFrame.minX == 12)
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

    @MainActor
    @Test func accountViewControllerShowsProfileAndDispatchesActions() async throws {
        var actions: [AccountAction] = []
        let viewController = AccountViewController(
            state: AccountViewState(
                displayName: "Session User",
                userID: "session_user",
                avatarURL: nil
            ),
            onAction: { actions.append($0) }
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let navigationController = UINavigationController(rootViewController: viewController)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        viewController.view.layoutIfNeeded()

        #expect(viewController.title == "Account")
        #expect(viewController.tabBarItem.accessibilityIdentifier == "mainTab.account")
        #expect(findView(in: viewController.view, identifier: "account.profileHeader") != nil)
        #expect(findLabel(withText: "Session User", in: viewController.view) != nil)
        #expect(findLabel(withText: "session_user", in: viewController.view) != nil)

        #expect(findView(ofType: UITableView.self, in: viewController.view) == nil)

        let collectionView = try #require(findView(in: viewController.view, identifier: "account.collectionView") as? UICollectionView)
        collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: IndexPath(row: 0, section: 1))
        collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: IndexPath(row: 1, section: 1))

        #expect(actions == [.switchAccount, .logOut])
    }

    @MainActor
    @Test func accountViewControllerConfirmsBeforeDeletingLocalData() async throws {
        var actions: [AccountAction] = []
        let viewController = AccountViewController(
            state: AccountViewState(
                displayName: "Session User",
                userID: "session_user",
                avatarURL: nil
            ),
            onAction: { actions.append($0) }
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let navigationController = UINavigationController(rootViewController: viewController)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        #expect(findView(ofType: UITableView.self, in: viewController.view) == nil)

        let collectionView = try #require(findView(in: viewController.view, identifier: "account.collectionView") as? UICollectionView)
        collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: IndexPath(row: 2, section: 1))

        let confirmAlert = try #require(navigationController.presentedViewController as? UIAlertController)
        #expect(confirmAlert.title == "Delete Local Data?")
        #expect(confirmAlert.message?.contains("database") == true)
        #expect(confirmAlert.message?.contains("media") == true)
        let confirmAction = try #require(confirmAlert.actions.first { $0.title == "Delete Local Data" })
        #expect(confirmAction.value(forKey: "accessibilityIdentifier") as? String == "accountAction.confirmDeleteLocalData")
        #expect(actions.isEmpty)

        let cancelAction = try #require(confirmAlert.actions.first { $0.style == .cancel })
        cancelAction.triggerForTesting()

        #expect(actions.isEmpty)
    }

    @Test func photoLibrarySelectionStateKeepsSelectionOrderAndCapsAtNine() {
        var state = ChatPhotoLibrarySelectionState()
        let ids = (1...10).map { "asset-\($0)" }

        let firstNineResults = ids.prefix(9).map { state.toggle(assetID: $0) }
        let tenthResult = state.toggle(assetID: ids[9])

        #expect(firstNineResults.allSatisfy { $0 == .selected })
        #expect(tenthResult == .limitReached)
        #expect(state.selectedAssetIDs == Array(ids.prefix(9)))

        let cancelResult = state.toggle(assetID: "asset-3")

        #expect(cancelResult == .deselected)
        #expect(state.selectedAssetIDs == ["asset-1", "asset-2", "asset-4", "asset-5", "asset-6", "asset-7", "asset-8", "asset-9"])
    }

    @MainActor
    @Test func chatInputBarKeepsPhotoLibraryMenuAction() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))
        inputBar.layoutIfNeeded()

        let menuChildren = button(in: inputBar, identifier: "chat.moreButton")?.menu?.children ?? []

        #expect(menuChildren.contains { $0.title == "相册" })
    }

    @MainActor
    @Test func chatInputBarDoesNotInstallPhotoLibraryAsTextInputView() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))
        let textView = try #require(findView(ofType: UITextView.self, in: inputBar))

        inputBar.showPhotoLibraryInput()

        #expect(textView.inputView == nil)

        inputBar.showKeyboardInput()

        #expect(textView.inputView == nil)
    }

    @MainActor
    @Test func chatInputBarDefersSystemKeyboardWhileLeavingPhotoLibraryInput() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))
        let textView = try #require(findView(ofType: UITextView.self, in: inputBar))
        var keyboardInputRequestCount = 0
        inputBar.onKeyboardInputRequested = {
            keyboardInputRequestCount += 1
        }

        inputBar.showPhotoLibraryInput()

        #expect(inputBar.textViewShouldBeginEditing(textView) == false)
        #expect(keyboardInputRequestCount == 1)
        #expect(inputBar.textViewShouldBeginEditing(textView) == false)
        #expect(keyboardInputRequestCount == 1)

        inputBar.showKeyboardInput()

        #expect(inputBar.textViewShouldBeginEditing(textView) == true)
    }

    @MainActor
    @Test func chatInputBarDefersSystemKeyboardWhileLeavingEmojiInput() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))
        let textView = try #require(findView(ofType: UITextView.self, in: inputBar))
        var keyboardInputRequestCount = 0
        inputBar.onKeyboardInputRequested = {
            keyboardInputRequestCount += 1
        }

        inputBar.showEmojiInput()

        #expect(inputBar.textViewShouldBeginEditing(textView) == false)
        #expect(keyboardInputRequestCount == 1)
        #expect(inputBar.textViewShouldBeginEditing(textView) == false)
        #expect(keyboardInputRequestCount == 1)

        inputBar.showKeyboardInput()

        #expect(inputBar.textViewShouldBeginEditing(textView) == true)
    }

    @MainActor
    @Test func chatEmojiPanelDefaultsToFirstNonEmptySection() throws {
        let panelView = ChatEmojiPanelView(frame: CGRect(x: 0, y: 0, width: 390, height: 280))
        let state = makeEmojiPanelState(
            recentEmojis: [],
            favoriteEmojis: [makeEmojiAsset(emojiID: "favorite_stub", name: "Favorite Stub", isFavorite: true)],
            packageEmojis: [makeEmojiAsset(emojiID: "package_stub", name: "Package Stub")]
        )

        panelView.render(state)
        panelView.layoutIfNeeded()

        #expect(findView(in: panelView, identifier: "chat.emojiItem.favorite_stub") != nil)
        #expect(findView(in: panelView, identifier: "chat.emojiItem.package_stub") == nil)
    }

    @MainActor
    @Test func chatEmojiPanelSwitchesToFavoritesSection() throws {
        let panelView = ChatEmojiPanelView(frame: CGRect(x: 0, y: 0, width: 390, height: 280))
        let state = makeEmojiPanelState(
            recentEmojis: [],
            favoriteEmojis: [makeEmojiAsset(emojiID: "favorite_stub", name: "Favorite Stub", isFavorite: true)],
            packageEmojis: [makeEmojiAsset(emojiID: "package_stub", name: "Package Stub")]
        )

        panelView.render(state)
        let favoritesButton = try #require(button(in: panelView, accessibilityLabel: "收藏"))

        favoritesButton.sendActions(for: .touchUpInside)
        panelView.layoutIfNeeded()

        #expect(findView(in: panelView, identifier: "chat.emojiItem.favorite_stub") != nil)
        #expect(findView(in: panelView, identifier: "chat.emojiItem.package_stub") == nil)
    }

    @MainActor
    @Test func chatViewControllerKeepsSentEmojiAboveInputBarWhileEmojiPanelVisible() async throws {
        let rows = (1...32).map { index in
            makeChatRow(
                id: MessageID(rawValue: "emoji_visibility_\(index)"),
                text: "Emoji visibility message \(index)",
                sortSequence: Int64(index)
            )
        }
        let useCase = EmojiPanelStubChatUseCase(initialRows: rows)
        let viewModel = ChatViewModel(useCase: useCase, title: "Emoji Visibility")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            guard let collectionView = findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView else {
                return false
            }
            return collectionView.numberOfItems(inSection: 0) == rows.count
        }
        window.layoutIfNeeded()

        let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
        let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
        let emojiPanel = try #require(findView(ofType: ChatEmojiPanelView.self, in: viewController.view))

        inputBar.onEmojiTapped?()
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            button(in: emojiPanel, identifier: "chat.emojiItem.favorite_stub") != nil
        }
        window.layoutIfNeeded()

        let emojiButton = try #require(button(in: emojiPanel, identifier: "chat.emojiItem.favorite_stub"))
        emojiButton.sendActions(for: .touchUpInside)
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            collectionView.numberOfItems(inSection: 0) == rows.count + 1
        }
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            latestMessageCellIsAboveInputBar(
                collectionView: collectionView,
                item: rows.count,
                inputBar: inputBar,
                in: viewController.view
            )
        }
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let lastCell = try #require(collectionView.cellForItem(at: IndexPath(item: rows.count, section: 0)))
        let lastCellFrame = lastCell.convert(lastCell.bounds, to: viewController.view)
        let collectionFrame = collectionView.convert(collectionView.bounds, to: viewController.view)
        let inputBarFrame = inputBar.convert(inputBar.bounds, to: viewController.view)
        #expect(lastCellFrame.maxY <= collectionFrame.maxY + 1)
        #expect(lastCellFrame.maxY <= inputBarFrame.minY + 1)
    }

    @MainActor
    @Test func chatViewControllerAnimatesSentEmojiAppendFromBottom() async throws {
        let rows = (1...32).map { index in
            makeChatRow(
                id: MessageID(rawValue: "emoji_animation_\(index)"),
                text: "Emoji animation message \(index)",
                sortSequence: Int64(index)
            )
        }
        let useCase = EmojiPanelStubChatUseCase(initialRows: rows)
        let viewModel = ChatViewModel(useCase: useCase, title: "Emoji Animation")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            guard let collectionView = findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView else {
                return false
            }
            return collectionView.numberOfItems(inSection: 0) == rows.count
        }
        window.layoutIfNeeded()

        let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
        let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
        let emojiPanel = try #require(findView(ofType: ChatEmojiPanelView.self, in: viewController.view))

        inputBar.onEmojiTapped?()
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            button(in: emojiPanel, identifier: "chat.emojiItem.favorite_stub") != nil
        }
        window.layoutIfNeeded()

        let emojiButton = try #require(button(in: emojiPanel, identifier: "chat.emojiItem.favorite_stub"))
        emojiButton.sendActions(for: .touchUpInside)
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            collectionView.numberOfItems(inSection: 0) == rows.count + 1
                && viewController.lastScrollToBottomRequestedAnimationForTesting == true
        }

        #expect(viewController.lastScrollToBottomRequestedAnimationForTesting == true)
    }

    @MainActor
    @Test func chatViewControllerScrollsSentEmojiAboveOverlappingInputBar() async throws {
        let rows = (1...32).map { index in
            makeChatRow(
                id: MessageID(rawValue: "emoji_overlap_visibility_\(index)"),
                text: "Emoji overlap visibility message \(index)",
                sortSequence: Int64(index)
            )
        }
        let useCase = EmojiPanelStubChatUseCase(initialRows: rows)
        let viewModel = ChatViewModel(useCase: useCase, title: "Emoji Overlap Visibility")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            guard let collectionView = findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView else {
                return false
            }
            return collectionView.numberOfItems(inSection: 0) == rows.count
        }
        window.layoutIfNeeded()

        let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
        let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
        let emojiPanel = try #require(findView(ofType: ChatEmojiPanelView.self, in: viewController.view))
        let collectionFrame = collectionView.convert(collectionView.bounds, to: viewController.view)
        #expect(abs(collectionFrame.maxY - viewController.view.bounds.maxY) <= 1)
        window.layoutIfNeeded()

        inputBar.onEmojiTapped?()
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            button(in: emojiPanel, identifier: "chat.emojiItem.favorite_stub") != nil
        }
        window.layoutIfNeeded()

        let emojiButton = try #require(button(in: emojiPanel, identifier: "chat.emojiItem.favorite_stub"))
        emojiButton.sendActions(for: .touchUpInside)
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            collectionView.numberOfItems(inSection: 0) == rows.count + 1
        }
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            latestMessageCellIsAboveInputBar(
                collectionView: collectionView,
                item: rows.count,
                inputBar: inputBar,
                in: viewController.view
            )
        }
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let lastCell = try #require(collectionView.cellForItem(at: IndexPath(item: rows.count, section: 0)))
        let lastCellFrame = lastCell.convert(lastCell.bounds, to: viewController.view)
        let inputBarFrame = inputBar.convert(inputBar.bounds, to: viewController.view)
        #expect(lastCellFrame.maxY <= inputBarFrame.minY + 1)
    }

    @MainActor
    @Test func chatViewControllerKeepsLatestMessageAboveInputBarAfterTextInputHeightGrows() async throws {
        let setup = try await makeScrollableChatViewController(
            title: "Input Growth",
            rowPrefix: "input_growth"
        )
        defer {
            setup.window.isHidden = true
            setup.window.rootViewController = nil
        }

        let textView = try #require(findView(ofType: UITextView.self, in: setup.inputBar))
        let lastItem = setup.collectionView.numberOfItems(inSection: 0) - 1
        setup.collectionView.scrollToItem(at: IndexPath(item: lastItem, section: 0), at: .bottom, animated: false)
        setup.window.layoutIfNeeded()
        setup.collectionView.layoutIfNeeded()

        textView.text = """
        输入栏高度变化
        第二行
        第三行
        第四行
        第五行
        """
        setup.inputBar.textViewDidChange(textView)
        setup.window.layoutIfNeeded()
        setup.collectionView.layoutIfNeeded()

        let lastCell = try #require(setup.collectionView.cellForItem(at: IndexPath(item: lastItem, section: 0)))
        let lastCellFrame = lastCell.convert(lastCell.bounds, to: setup.viewController.view)
        let inputFrame = setup.inputBar.convert(setup.inputBar.bounds, to: setup.viewController.view)
        #expect(lastCellFrame.maxY <= inputFrame.minY + 1)
    }

    @MainActor
    @Test func chatViewControllerKeepsLatestMessageAboveInputBarAfterDeletingLastMessageWithGrownInput() async throws {
        let rows = (1...36).map { index in
            makeChatRow(
                id: MessageID(rawValue: "delete_input_growth_\(index)"),
                text: "Delete input growth \(index)",
                sortSequence: Int64(index)
            )
        }
        let useCase = MessageActionStubChatUseCase(initialRows: rows)
        let viewModel = ChatViewModel(useCase: useCase, title: "Delete Input Growth")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            collectionView.numberOfItems(inSection: 0) == rows.count
        }
        window.layoutIfNeeded()

        let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
        let textView = try #require(findView(ofType: UITextView.self, in: inputBar))
        collectionView.scrollToItem(at: IndexPath(item: rows.count - 1, section: 0), at: .bottom, animated: false)
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        textView.text = """
        删除最后一条前输入栏增高
        第二行
        第三行
        第四行
        """
        inputBar.textViewDidChange(textView)
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        viewModel.delete(messageID: rows.last?.id ?? "")
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            collectionView.numberOfItems(inSection: 0) == rows.count - 1
        }
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let lastCell = try #require(collectionView.cellForItem(at: IndexPath(item: rows.count - 2, section: 0)))
        let lastCellFrame = lastCell.convert(lastCell.bounds, to: viewController.view)
        let inputFrame = inputBar.convert(inputBar.bounds, to: viewController.view)
        #expect(lastCellFrame.maxY <= inputFrame.minY + 1)
    }

    @MainActor
    @Test func chatViewControllerKeepsRevokedBottomMessageAboveInputBarWithEmojiPanelOpen() async throws {
        let rows = (1...36).map { index in
            makeChatRow(
                id: MessageID(rawValue: "revoke_emoji_panel_\(index)"),
                text: "Revoke emoji panel \(index)",
                sortSequence: Int64(index)
            )
        }
        var revokedRows = rows
        revokedRows[revokedRows.count - 1] = makeRevokedChatRow(
            id: rows.last?.id ?? "",
            text: "你撤回了一条消息",
            sortSequence: Int64(rows.count)
        )
        let useCase = MessageActionStubChatUseCase(initialRows: rows, revokedRows: revokedRows)
        let viewModel = ChatViewModel(useCase: useCase, title: "Revoke Emoji Panel")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            collectionView.numberOfItems(inSection: 0) == rows.count
        }
        window.layoutIfNeeded()

        let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
        inputBar.onEmojiTapped?()
        collectionView.scrollToItem(at: IndexPath(item: rows.count - 1, section: 0), at: .bottom, animated: false)
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        viewModel.revoke(messageID: rows.last?.id ?? "")
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            guard let lastCell = collectionView.cellForItem(at: IndexPath(item: rows.count - 1, section: 0)) else {
                return false
            }
            return findLabel(withText: "你撤回了一条消息", in: lastCell) != nil
        }
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let lastCell = try #require(collectionView.cellForItem(at: IndexPath(item: rows.count - 1, section: 0)))
        let lastCellFrame = lastCell.convert(lastCell.bounds, to: viewController.view)
        let inputFrame = inputBar.convert(inputBar.bounds, to: viewController.view)
        #expect(lastCellFrame.maxY <= inputFrame.minY + 1)
    }

    @MainActor
    @Test func chatViewControllerKeepsLatestMessageAboveInputBarWhenTransientStatusAppears() async throws {
        let setup = try await makeScrollableChatViewController(
            title: "Transient Status",
            rowPrefix: "transient_status"
        )
        defer {
            setup.window.isHidden = true
            setup.window.rootViewController = nil
        }

        let lastItem = setup.collectionView.numberOfItems(inSection: 0) - 1
        setup.collectionView.scrollToItem(at: IndexPath(item: lastItem, section: 0), at: .bottom, animated: false)
        setup.window.layoutIfNeeded()
        setup.collectionView.layoutIfNeeded()

        setup.inputBar.showTransientStatus("Voice too short")
        setup.window.layoutIfNeeded()
        setup.collectionView.layoutIfNeeded()

        let lastCell = try #require(setup.collectionView.cellForItem(at: IndexPath(item: lastItem, section: 0)))
        let lastCellFrame = lastCell.convert(lastCell.bounds, to: setup.viewController.view)
        let inputFrame = setup.inputBar.convert(setup.inputBar.bounds, to: setup.viewController.view)
        #expect(lastCellFrame.maxY <= inputFrame.minY + 1)
    }

    @MainActor
    @Test func chatViewControllerRestoresBottomAlignmentWhenNearBottomLayoutDrifts() async throws {
        let setup = try await makeScrollableChatViewController(
            title: "Initial Layout Drift",
            rowPrefix: "initial_layout_drift"
        )
        defer {
            setup.window.isHidden = true
            setup.window.rootViewController = nil
        }

        let lastItem = setup.collectionView.numberOfItems(inSection: 0) - 1
        setup.collectionView.scrollToItem(at: IndexPath(item: lastItem, section: 0), at: .bottom, animated: false)
        setup.window.layoutIfNeeded()
        setup.collectionView.layoutIfNeeded()

        setup.collectionView.setContentOffset(
            CGPoint(x: setup.collectionView.contentOffset.x, y: setup.collectionView.contentOffset.y - 40),
            animated: false
        )
        setup.viewController.viewDidLayoutSubviews()
        setup.window.layoutIfNeeded()
        setup.collectionView.layoutIfNeeded()

        let lastCell = try #require(setup.collectionView.cellForItem(at: IndexPath(item: lastItem, section: 0)))
        let lastCellFrame = lastCell.convert(lastCell.bounds, to: setup.viewController.view)
        let inputFrame = setup.inputBar.convert(setup.inputBar.bounds, to: setup.viewController.view)
        #expect(lastCellFrame.maxY <= inputFrame.minY + 1)
    }

    @MainActor
    @Test func chatViewControllerKeepsLatestMessageAboveInputBarWhenKeyboardMovesInputBarUp() async throws {
        let setup = try await makeScrollableChatViewController(
            title: "Keyboard Overlay",
            rowPrefix: "keyboard_overlay"
        )
        defer {
            setup.window.isHidden = true
            setup.window.rootViewController = nil
        }

        let lastItem = setup.collectionView.numberOfItems(inSection: 0) - 1
        setup.collectionView.scrollToItem(at: IndexPath(item: lastItem, section: 0), at: .bottom, animated: false)
        setup.window.layoutIfNeeded()
        setup.collectionView.layoutIfNeeded()

        for constraint in setup.viewController.view.constraints where
            ((constraint.firstItem as? UIView) === setup.inputBar && constraint.firstAttribute == .bottom)
                || ((constraint.secondItem as? UIView) === setup.inputBar && constraint.secondAttribute == .bottom) {
            constraint.isActive = false
        }
        setup.inputBar.bottomAnchor.constraint(
            equalTo: setup.viewController.view.bottomAnchor,
            constant: -300
        ).isActive = true
        setup.window.layoutIfNeeded()
        setup.collectionView.layoutIfNeeded()

        let lastCell = try #require(setup.collectionView.cellForItem(at: IndexPath(item: lastItem, section: 0)))
        let lastCellFrame = lastCell.convert(lastCell.bounds, to: setup.viewController.view)
        let inputFrame = setup.inputBar.convert(setup.inputBar.bounds, to: setup.viewController.view)
        #expect(lastCellFrame.maxY <= inputFrame.minY + 1)
    }

    @MainActor
    @Test func chatViewControllerSimulateIncomingButtonTriggersMessageAppend() async throws {
        let useCase = SimulatedIncomingStubChatUseCase()
        let viewModel = ChatViewModel(useCase: useCase, title: "Simulated Button")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        let buttonItem = try #require(viewController.navigationItem.rightBarButtonItem)
        #expect(buttonItem.accessibilityIdentifier == "chat.simulateIncomingButton")
        #expect(buttonItem.accessibilityLabel == "后台推送对方消息")

        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.phase == .loaded
            }
        }
        UIApplication.shared.sendAction(
            try #require(buttonItem.action),
            to: buttonItem.target,
            from: buttonItem,
            for: nil
        )
        try await waitForCondition {
            await MainActor.run {
                viewModel.currentState.rows.count == 2
            }
        }

        #expect(useCase.simulateIncomingCallCount == 1)
        #expect(viewModel.currentState.rows.allSatisfy { $0.isOutgoing == false })
    }

    @MainActor
    @Test func chatViewControllerKeepsIncomingMessageAboveInputBarWhenAlreadyAtBottom() async throws {
        let initialRows = (1...36).map { index in
            makeChatRow(
                id: MessageID(rawValue: "incoming_visible_initial_\(index)"),
                text: "Incoming visible initial \(index)",
                sortSequence: Int64(index)
            )
        }
        let simulatedRows = [
            makeChatRow(
                id: MessageID(rawValue: "incoming_visible_append"),
                text: "Incoming visible append",
                sortSequence: 37,
                isOutgoing: false
            )
        ]
        let useCase = SimulatedIncomingStubChatUseCase(
            initialRows: initialRows,
            simulatedRows: simulatedRows
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Incoming Visible")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        let buttonItem = try #require(viewController.navigationItem.rightBarButtonItem)
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            guard let collectionView = findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView else {
                return false
            }
            return collectionView.numberOfItems(inSection: 0) == initialRows.count
        }
        window.layoutIfNeeded()

        let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
        let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
        collectionView.scrollToItem(at: IndexPath(item: initialRows.count - 1, section: 0), at: .bottom, animated: false)
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        UIApplication.shared.sendAction(
            try #require(buttonItem.action),
            to: buttonItem.target,
            from: buttonItem,
            for: nil
        )
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            collectionView.numberOfItems(inSection: 0) == initialRows.count + simulatedRows.count
        }
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            latestMessageCellIsAboveInputBar(
                collectionView: collectionView,
                item: initialRows.count,
                inputBar: inputBar,
                in: viewController.view
            )
        }
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let lastCell = try #require(collectionView.cellForItem(at: IndexPath(item: initialRows.count, section: 0)))
        let lastCellFrame = lastCell.convert(lastCell.bounds, to: viewController.view)
        let inputFrame = inputBar.convert(inputBar.bounds, to: viewController.view)
        #expect(lastCellFrame.maxY <= inputFrame.minY + 1)
    }

    @MainActor
    @Test func chatViewControllerKeepsIncomingMessageAboveInputBarWithEmojiPanelOpen() async throws {
        let initialRows = (1...36).map { index in
            makeChatRow(
                id: MessageID(rawValue: "incoming_emoji_panel_initial_\(index)"),
                text: "Incoming emoji panel initial \(index)",
                sortSequence: Int64(index)
            )
        }
        let simulatedRows = [
            makeChatRow(
                id: MessageID(rawValue: "incoming_emoji_panel_append"),
                text: "Incoming emoji panel append",
                sortSequence: 37,
                isOutgoing: false
            )
        ]
        let useCase = SimulatedIncomingStubChatUseCase(
            initialRows: initialRows,
            simulatedRows: simulatedRows
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Incoming Emoji Panel")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        let buttonItem = try #require(viewController.navigationItem.rightBarButtonItem)
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            guard let collectionView = findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView else {
                return false
            }
            return collectionView.numberOfItems(inSection: 0) == initialRows.count
        }
        window.layoutIfNeeded()

        let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
        let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
        let emojiPanel = try #require(findView(ofType: ChatEmojiPanelView.self, in: viewController.view))
        inputBar.onEmojiTapped?()
        window.layoutIfNeeded()
        #expect(emojiPanel.isHidden == false)

        collectionView.scrollToItem(at: IndexPath(item: initialRows.count - 1, section: 0), at: .bottom, animated: false)
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        UIApplication.shared.sendAction(
            try #require(buttonItem.action),
            to: buttonItem.target,
            from: buttonItem,
            for: nil
        )
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            collectionView.numberOfItems(inSection: 0) == initialRows.count + simulatedRows.count
        }
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            latestMessageCellIsAboveInputBar(
                collectionView: collectionView,
                item: initialRows.count,
                inputBar: inputBar,
                in: viewController.view
            )
        }
    }

    @MainActor
    @Test func chatViewControllerDoesNotAutoScrollIncomingMessageWhenUserLeftBottom() async throws {
        let initialRows = (1...44).map { index in
            makeChatRow(
                id: MessageID(rawValue: "incoming_left_bottom_initial_\(index)"),
                text: "Incoming left bottom initial \(index)",
                sortSequence: Int64(index)
            )
        }
        let simulatedRows = [
            makeChatRow(
                id: MessageID(rawValue: "incoming_left_bottom_append"),
                text: "Incoming left bottom append",
                sortSequence: 45,
                isOutgoing: false
            )
        ]
        let useCase = SimulatedIncomingStubChatUseCase(
            initialRows: initialRows,
            simulatedRows: simulatedRows
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Incoming Left Bottom")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        let buttonItem = try #require(viewController.navigationItem.rightBarButtonItem)
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            guard let collectionView = findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView else {
                return false
            }
            return collectionView.numberOfItems(inSection: 0) == initialRows.count
        }
        window.layoutIfNeeded()

        let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
        let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
        let lastInitialItem = initialRows.count - 1
        collectionView.scrollToItem(at: IndexPath(item: lastInitialItem, section: 0), at: .bottom, animated: false)
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let bottomOffsetY = collectionView.contentOffset.y
        viewController.scrollViewWillBeginDragging(collectionView)
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: bottomOffsetY - 220),
            animated: false
        )
        viewController.scrollViewDidEndDragging(collectionView, willDecelerate: false)
        let offsetBeforeIncoming = collectionView.contentOffset.y

        UIApplication.shared.sendAction(
            try #require(buttonItem.action),
            to: buttonItem.target,
            from: buttonItem,
            for: nil
        )
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            collectionView.numberOfItems(inSection: 0) == initialRows.count + simulatedRows.count
        }
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        #expect(collectionView.contentOffset.y <= offsetBeforeIncoming + 1)
        #expect(collectionView.cellForItem(at: IndexPath(item: initialRows.count, section: 0)) == nil)

        inputBar.setPendingAttachmentPreviews([
            ChatPendingAttachmentPreviewItem(
                id: "left-bottom-photo",
                image: nil,
                title: "Image ready",
                durationText: nil,
                isVideo: false,
                isLoading: false
            )
        ], animated: false)
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        #expect(collectionView.contentOffset.y <= offsetBeforeIncoming + 1)
    }

    @MainActor
    @Test func chatViewControllerAllowsScrollingAfterSimulatedIncomingButtonAppend() async throws {
        let initialRows = (1...40).map { index in
            makeChatRow(
                id: MessageID(rawValue: "simulated_scroll_initial_\(index)"),
                text: "Simulated scroll initial \(index)",
                sortSequence: Int64(index)
            )
        }
        let simulatedRows = (41...42).map { index in
            makeChatRow(
                id: MessageID(rawValue: "simulated_scroll_push_\(index)"),
                text: "Simulated scroll push \(index)",
                sortSequence: Int64(index)
            )
        }
        let useCase = SimulatedIncomingStubChatUseCase(
            initialRows: initialRows,
            simulatedRows: simulatedRows
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Simulated Scroll")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        let buttonItem = try #require(viewController.navigationItem.rightBarButtonItem)
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            guard let collectionView = findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView else {
                return false
            }
            return collectionView.numberOfItems(inSection: 0) == initialRows.count
        }
        window.layoutIfNeeded()

        UIApplication.shared.sendAction(
            try #require(buttonItem.action),
            to: buttonItem.target,
            from: buttonItem,
            for: nil
        )
        let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            collectionView.numberOfItems(inSection: 0) == initialRows.count + simulatedRows.count
        }
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let targetOffsetY = max(
            -collectionView.adjustedContentInset.top,
            collectionView.contentOffset.y - 240
        )
        viewController.scrollViewWillBeginDragging(collectionView)
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: targetOffsetY),
            animated: false
        )
        viewController.scrollViewDidEndDragging(collectionView, willDecelerate: false)
        try await Task.sleep(nanoseconds: 400_000_000)

        #expect(collectionView.contentOffset.y <= targetOffsetY + 1)
    }

    @MainActor
    @Test func chatViewControllerDoesNotPageDuringInitialSnapshotApply() async throws {
        let rows = (1...36).map { index in
            makeChatRow(
                id: MessageID(rawValue: "initial_apply_\(index)"),
                text: "Initial apply \(index)",
                sortSequence: Int64(index)
            )
        }
        let useCase = PagingStubChatUseCase(
            initialPage: ChatMessagePage(rows: rows, hasMore: true, nextBeforeSortSequence: 1),
            olderPage: ChatMessagePage(
                rows: [makeChatRow(id: "unexpected_older", text: "Unexpected", sortSequence: 0)],
                hasMore: false,
                nextBeforeSortSequence: nil
            )
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "Initial Apply")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            guard let collectionView = findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView else {
                return false
            }
            return collectionView.numberOfItems(inSection: 0) == rows.count
        }
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(useCase.loadOlderCallCount == 0)
        #expect(viewModel.currentState.rows.map(\.id.rawValue) == rows.map(\.id.rawValue))
    }

    @MainActor
    @Test func chatSnapshotRenderCoordinatorQueuesReentrantStateUntilApplyCompletes() {
        let coordinator = ChatSnapshotRenderCoordinator<String>()
        var appliedStates: [String] = []
        var firstCompletion: (() -> Void)?
        var secondCompletion: (() -> Void)?

        coordinator.apply("first") { state, completion in
            appliedStates.append(state)
            firstCompletion = completion

            coordinator.apply("second") { nestedState, nestedCompletion in
                appliedStates.append(nestedState)
                secondCompletion = nestedCompletion
            }
        }

        #expect(appliedStates == ["first"])
        #expect(coordinator.isApplying)

        firstCompletion?()

        #expect(appliedStates == ["first", "second"])
        #expect(coordinator.isApplying)

        secondCompletion?()

        #expect(coordinator.isApplying == false)
    }

    @MainActor
    @Test func chatViewControllerKeepsMoreButtonStationaryWhilePreparingKeyboardFromPhotoLibrary() async throws {
        let rows = (1...16).map { index in
            makeChatRow(
                id: MessageID(rawValue: "more_button_transition_\(index)"),
                text: "More button transition \(index)",
                sortSequence: Int64(index)
            )
        }
        let useCase = PagingStubChatUseCase(
            initialPage: ChatMessagePage(rows: rows, hasMore: false, nextBeforeSortSequence: nil),
            olderPage: ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
        )
        let viewModel = ChatViewModel(useCase: useCase, title: "More Button")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            guard let collectionView = findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView else {
                return false
            }
            return collectionView.numberOfItems(inSection: 0) == rows.count
        }
        window.layoutIfNeeded()

        let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
        let textView = try #require(findView(ofType: UITextView.self, in: inputBar))
        let moreButton = try #require(button(in: inputBar, identifier: "chat.moreButton"))

        inputBar.onPhotoTapped?()
        window.layoutIfNeeded()

        let frameBeforeKeyboardRequest = moreButton.convert(moreButton.bounds, to: viewController.view)

        #expect(inputBar.textViewShouldBeginEditing(textView) == false)
        window.layoutIfNeeded()

        let frameAfterKeyboardRequest = moreButton.convert(moreButton.bounds, to: viewController.view)
        #expect(abs(frameAfterKeyboardRequest.minY - frameBeforeKeyboardRequest.minY) <= 1)
    }

    @MainActor
    @Test func chatViewControllerKeepsMoreButtonStationaryWhilePreparingKeyboardFromEmojiPanel() async throws {
        let rows = (1...16).map { index in
            makeChatRow(
                id: MessageID(rawValue: "emoji_keyboard_transition_\(index)"),
                text: "Emoji keyboard transition \(index)",
                sortSequence: Int64(index)
            )
        }
        let useCase = EmojiPanelStubChatUseCase(initialRows: rows)
        let viewModel = ChatViewModel(useCase: useCase, title: "Emoji Keyboard")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            guard let collectionView = findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView else {
                return false
            }
            return collectionView.numberOfItems(inSection: 0) == rows.count
        }
        window.layoutIfNeeded()

        let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
        let textView = try #require(findView(ofType: UITextView.self, in: inputBar))
        let moreButton = try #require(button(in: inputBar, identifier: "chat.moreButton"))
        let emojiPanel = try #require(findView(ofType: ChatEmojiPanelView.self, in: viewController.view))

        inputBar.onEmojiTapped?()
        window.layoutIfNeeded()
        #expect(emojiPanel.isHidden == false)

        let frameBeforeKeyboardRequest = moreButton.convert(moreButton.bounds, to: viewController.view)

        #expect(inputBar.textViewShouldBeginEditing(textView) == false)
        #expect(emojiPanel.isHidden == false)
        window.layoutIfNeeded()

        let frameAfterKeyboardRequest = moreButton.convert(moreButton.bounds, to: viewController.view)
        #expect(abs(frameAfterKeyboardRequest.minY - frameBeforeKeyboardRequest.minY) <= 1)
    }

    @MainActor
    @Test func chatViewControllerKeepsPhotoLibraryPanelVisibleWhileSwitchingToEmojiPanel() async throws {
        let rows = (1...16).map { index in
            makeChatRow(
                id: MessageID(rawValue: "photo_to_emoji_transition_\(index)"),
                text: "Photo to emoji transition \(index)",
                sortSequence: Int64(index)
            )
        }
        let useCase = EmojiPanelStubChatUseCase(initialRows: rows)
        let viewModel = ChatViewModel(useCase: useCase, title: "Photo To Emoji")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            guard let collectionView = findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView else {
                return false
            }
            return collectionView.numberOfItems(inSection: 0) == rows.count
        }
        window.layoutIfNeeded()

        let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
        let photoPanel = try #require(findView(ofType: ChatPhotoLibraryInputView.self, in: viewController.view))
        let emojiPanel = try #require(findView(ofType: ChatEmojiPanelView.self, in: viewController.view))

        inputBar.onPhotoTapped?()
        window.layoutIfNeeded()
        #expect(photoPanel.isHidden == false)

        inputBar.onEmojiTapped?()
        window.layoutIfNeeded()

        let inputBarFrame = inputBar.convert(inputBar.bounds, to: viewController.view)
        let emojiPanelFrame = emojiPanel.convert(emojiPanel.bounds, to: viewController.view)
        #expect(photoPanel.isHidden == false)
        #expect(emojiPanel.isHidden == false)
        #expect(abs(inputBarFrame.maxY - (emojiPanelFrame.minY - 8)) <= 1)
    }

    @MainActor
    @Test func chatViewControllerKeepsEmojiPanelVisibleWhileSwitchingToPhotoLibraryPanel() async throws {
        let rows = (1...16).map { index in
            makeChatRow(
                id: MessageID(rawValue: "emoji_to_photo_transition_\(index)"),
                text: "Emoji to photo transition \(index)",
                sortSequence: Int64(index)
            )
        }
        let useCase = EmojiPanelStubChatUseCase(initialRows: rows)
        let viewModel = ChatViewModel(useCase: useCase, title: "Emoji To Photo")
        let viewController = ChatViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
            guard let collectionView = findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView else {
                return false
            }
            return collectionView.numberOfItems(inSection: 0) == rows.count
        }
        window.layoutIfNeeded()

        let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
        let photoPanel = try #require(findView(ofType: ChatPhotoLibraryInputView.self, in: viewController.view))
        let emojiPanel = try #require(findView(ofType: ChatEmojiPanelView.self, in: viewController.view))

        inputBar.onEmojiTapped?()
        window.layoutIfNeeded()
        #expect(emojiPanel.isHidden == false)

        inputBar.onPhotoTapped?()
        window.layoutIfNeeded()

        let inputBarFrame = inputBar.convert(inputBar.bounds, to: viewController.view)
        let photoPanelFrame = photoPanel.convert(photoPanel.bounds, to: viewController.view)
        #expect(emojiPanel.isHidden == false)
        #expect(photoPanel.isHidden == false)
        #expect(abs(inputBarFrame.maxY - (photoPanelFrame.minY - 8)) <= 1)
    }

    @MainActor
    @Test func chatPhotoLibraryInputDismissesAfterDownwardPanThreshold() throws {
        #expect(ChatPhotoLibraryInputView.shouldDismissForPan(translationY: 93, velocityY: 0))
        #expect(ChatPhotoLibraryInputView.shouldDismissForPan(translationY: 12, velocityY: 781))
        #expect(ChatPhotoLibraryInputView.shouldDismissForPan(translationY: 40, velocityY: 320) == false)
    }

    @MainActor
    @Test func chatPhotoLibraryInputStartsGridWithoutTopGap() throws {
        let photoPanel = ChatPhotoLibraryInputView(frame: CGRect(x: 0, y: 0, width: 390, height: 342))
        photoPanel.layoutIfNeeded()

        let collectionView = try #require(findView(in: photoPanel, identifier: "chat.photoLibraryGrid") as? UICollectionView)
        #expect(collectionView.contentInset.top == 0)
    }

    @MainActor
    @Test func chatPhotoLibraryInputGrabberUsesDynamicSystemLikeOverlayColor() throws {
        let photoPanel = ChatPhotoLibraryInputView(frame: CGRect(x: 0, y: 0, width: 390, height: 342))
        photoPanel.layoutIfNeeded()

        let grabberView = try #require(
            Mirror(reflecting: photoPanel).children.first { $0.label == "grabberView" }?.value as? UIView
        )
        let backgroundColor = try #require(grabberView.backgroundColor)
        let lightColor = backgroundColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let darkColor = backgroundColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        let highContrastColor = backgroundColor.resolvedColor(
            with: UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceStyle: .light),
                UITraitCollection(accessibilityContrast: .high)
            ])
        )

        let lightComponents = rgbaComponents(for: lightColor)
        let darkComponents = rgbaComponents(for: darkColor)
        let highContrastComponents = rgbaComponents(for: highContrastColor)

        #expect(lightComponents.alpha >= 0.45)
        #expect(darkComponents.alpha >= 0.65)
        #expect(lightComponents.red < darkComponents.red)
        #expect(highContrastComponents.alpha > lightComponents.alpha)
    }

    @MainActor
    @Test func chatInputBarKeepsMoreButtonOutsideInputCapsule() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))
        inputBar.layoutIfNeeded()

        let moreButton = try #require(button(in: inputBar, identifier: "chat.moreButton"))
        let inputCapsule = try #require(findView(ofType: GlassContainerView.self, in: inputBar))

        let moreFrame = moreButton.convert(moreButton.bounds, to: inputBar)
        let capsuleFrame = inputCapsule.convert(inputCapsule.bounds, to: inputBar)

        #expect(moreButton.isDescendant(of: inputCapsule) == false)
        #expect(moreFrame.maxX <= capsuleFrame.minX)
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

    @Test func chatMessageContentKindClassifiesExistingRows() {
        #expect(ChatMessageContentKind(row: makeChatRow(id: "text_kind", text: "Hello", sortSequence: 1)) == .text)
        #expect(ChatMessageContentKind(row: makeImageRow(id: "image_kind", sortSequence: 2)) == .image)
        #expect(ChatMessageContentKind(row: makeVideoRow(id: "video_kind", sortSequence: 3)) == .video)
        #expect(ChatMessageContentKind(row: makeVoiceRow(id: "voice_kind", sortSequence: 4, isUnplayed: true)) == .voice)
        #expect(ChatMessageContentKind(row: makeFileRow(id: "file_kind", sortSequence: 5)) == .file)
        #expect(ChatMessageContentKind(row: makeRevokedRow(id: "revoked_kind", sortSequence: 6)) == .revoked)
    }

    @Test func chatMessageContentFormatsVoiceDurationWithoutUnits() {
        #expect(ChatMessageRowContent.voiceDurationDisplayText(milliseconds: 999) == "0:01")
        #expect(ChatMessageRowContent.voiceDurationDisplayText(milliseconds: 4_200) == "0:04")
        #expect(ChatMessageRowContent.voiceDurationDisplayText(milliseconds: 65_000) == "1:05")
        #expect(ChatMessageRowContent.voiceElapsedDisplayText(milliseconds: 0) == "0:00")
    }

    @MainActor
    @Test func chatDesignSystemExposesAppleMessagesChatTokens() {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let outgoing = ChatBridgeDesignSystem.ColorToken.appleMessageOutgoing.resolvedColor(with: traits)
        let incoming = ChatBridgeDesignSystem.ColorToken.appleMessageIncoming.resolvedColor(with: traits)

        #expect(outgoing == UIColor.systemBlue.resolvedColor(with: traits))
        #expect(incoming == UIColor.systemGray6.resolvedColor(with: traits))
        #expect(ChatBridgeDesignSystem.RadiusToken.appleMessageBubble == 18)
        #expect(ChatBridgeDesignSystem.RadiusToken.appleMessageMedia == 20)
        #expect(ChatBridgeDesignSystem.RadiusToken.appleComposerAttachment == 16)
    }

    @MainActor
    @Test func chatMessageCellAppliesAppleMessagesTextColors() throws {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let outgoingCell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        outgoingCell.configure(
            row: makeChatRow(id: "blue_bubble", text: "蓝色发送气泡", sortSequence: 1, isOutgoing: true),
            actions: .empty
        )

        let incomingCell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        incomingCell.configure(
            row: makeChatRow(id: "gray_bubble", text: "灰色接收气泡", sortSequence: 2, isOutgoing: false),
            actions: .empty
        )

        let outgoingLabel = try #require(findLabel(withText: "蓝色发送气泡", in: outgoingCell))
        let incomingLabel = try #require(findLabel(withText: "灰色接收气泡", in: incomingCell))
        let outgoingBubble = try #require(findView(ofType: ChatBubbleBackgroundView.self, in: outgoingCell))
        let incomingBubble = try #require(findView(ofType: ChatBubbleBackgroundView.self, in: incomingCell))

        #expect(outgoingBubble.style == .outgoing)
        #expect(incomingBubble.style == .incoming)
        #expect(outgoingLabel.textColor.resolvedColor(with: traits) == UIColor.white.resolvedColor(with: traits))
        #expect(incomingLabel.textColor.resolvedColor(with: traits) == UIColor.label.resolvedColor(with: traits))
    }

    @MainActor
    @Test func outgoingMediaFallbackKeepsReadableSystemTextColor() throws {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
        cell.configure(
            row: ChatMessageRowState(
                id: "outgoing_media_fallback",
                content: .image(.init(thumbnailPath: "/tmp/missing-outgoing-media.jpg")),
                sortSequence: 1,
                timeText: "Now",
                statusText: nil,
                uploadProgress: nil,
                isOutgoing: true,
                canRetry: false,
                canDelete: true,
                canRevoke: false
            ),
            actions: .empty
        )

        let fallbackLabel = try #require(findLabel(withText: "Image unavailable", in: cell))
        let bubbleView = try #require(findView(ofType: ChatBubbleBackgroundView.self, in: cell))

        #expect(bubbleView.style == .media)
        #expect(fallbackLabel.textColor.resolvedColor(with: traits) == UIColor.label.resolvedColor(with: traits))
    }

    @MainActor
    @Test func chatBubbleTailDoesNotCreateBottomCornerSpur() {
        let bounds = CGRect(x: 0, y: 0, width: 128, height: 46)
        let outgoingPath = ChatBubbleBackgroundView.maskPath(in: bounds, style: .outgoing)
        let incomingPath = ChatBubbleBackgroundView.maskPath(in: bounds, style: .incoming)

        #expect(outgoingPath.contains(CGPoint(x: bounds.maxX - 3, y: bounds.maxY - 3)) == false)
        #expect(outgoingPath.contains(CGPoint(x: bounds.maxX - 2, y: bounds.maxY - 10)) == true)
        #expect(incomingPath.contains(CGPoint(x: bounds.minX + 3, y: bounds.maxY - 3)) == false)
        #expect(incomingPath.contains(CGPoint(x: bounds.minX + 2, y: bounds.maxY - 10)) == true)

        let bubbleView = ChatBubbleBackgroundView(frame: bounds)
        bubbleView.apply(style: ChatBubbleBackgroundView.Style.outgoing)
        bubbleView.layoutIfNeeded()

        #expect(bubbleView.layer.cornerRadius == 0)
        #expect(bubbleView.layer.masksToBounds == false)
    }

    @MainActor
    @Test func chatBubbleTailOverlapsRoundedBodyAtConnection() {
        let bounds = CGRect(x: 0, y: 0, width: 128, height: 46)
        let outgoingPath = ChatBubbleBackgroundView.maskPath(in: bounds, style: .outgoing)
        let incomingPath = ChatBubbleBackgroundView.maskPath(in: bounds, style: .incoming)

        #expect(outgoingPath.contains(CGPoint(x: bounds.maxX - 6, y: bounds.maxY - 13)))
        #expect(outgoingPath.contains(CGPoint(x: bounds.maxX - 6, y: bounds.maxY - 10)))
        #expect(incomingPath.contains(CGPoint(x: bounds.minX + 6, y: bounds.maxY - 13)))
        #expect(incomingPath.contains(CGPoint(x: bounds.minX + 6, y: bounds.maxY - 10)))
    }

    @MainActor
    @Test func chatBubbleTailUsesContinuousMaskPath() {
        let bounds = CGRect(x: 0, y: 0, width: 128, height: 46)

        #expect(moveElementCount(in: ChatBubbleBackgroundView.maskPath(in: bounds, style: .outgoing)) == 1)
        #expect(moveElementCount(in: ChatBubbleBackgroundView.maskPath(in: bounds, style: .incoming)) == 1)
    }

    @MainActor
    @Test func chatMessageContentFactoryCreatesAndReusesContentViews() throws {
        let factory = ChatMessageContentViewFactory()

        let textView = factory.view(for: .text, reusing: nil)
        #expect(textView is TextMessageContentView)

        let reusedTextView = factory.view(for: .text, reusing: textView)
        #expect(reusedTextView === textView)

        let imageView = factory.view(for: .image, reusing: textView)
        #expect(imageView is MediaMessageContentView)
        #expect(imageView !== textView)

        let videoView = factory.view(for: .video, reusing: imageView)
        #expect(videoView is MediaMessageContentView)
        #expect(videoView === imageView)

        let voiceView = factory.view(for: .voice, reusing: videoView)
        #expect(voiceView is VoiceMessageContentView)
        #expect(voiceView !== videoView)

        let fileView = factory.view(for: .file, reusing: voiceView)
        #expect(fileView is FileMessageContentView)
        #expect(fileView !== voiceView)
    }

    @MainActor
    @Test func mediaMessageCellsSizeImagesAndVideosToThumbnailAspectRatio() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let landscapeURL = directory.appendingPathComponent("landscape.jpg")
        let portraitURL = directory.appendingPathComponent("portrait.jpg")
        try makeJPEGData(width: 320, height: 180, quality: 0.9).write(to: landscapeURL, options: [.atomic])
        try makeJPEGData(width: 180, height: 320, quality: 0.9).write(to: portraitURL, options: [.atomic])

        let landscapeCell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
        landscapeCell.configure(
            row: ChatMessageRowState(
                id: "landscape_image",
                content: .image(.init(thumbnailPath: landscapeURL.path)),
                sortSequence: 1,
                timeText: "Now",
                statusText: nil,
                uploadProgress: nil,
                isOutgoing: true,
                canRetry: false,
                canDelete: true,
                canRevoke: false
            ),
            actions: .empty
        )
        landscapeCell.setNeedsLayout()
        landscapeCell.layoutIfNeeded()

        let portraitCell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 360))
        portraitCell.configure(
            row: ChatMessageRowState(
                id: "portrait_video",
                content: .video(.init(
                    thumbnailPath: portraitURL.path,
                    localPath: directory.appendingPathComponent("portrait.mov").path,
                    durationMilliseconds: 2_000
                )),
                sortSequence: 2,
                timeText: "Now",
                statusText: nil,
                uploadProgress: nil,
                isOutgoing: false,
                canRetry: false,
                canDelete: true,
                canRevoke: false
            ),
            actions: .empty
        )
        portraitCell.setNeedsLayout()
        portraitCell.layoutIfNeeded()

        let landscapeSize = try #require(largestLoadedImageView(in: landscapeCell)?.bounds.size)
        let portraitSize = try #require(largestLoadedImageView(in: portraitCell)?.bounds.size)
        let landscapeCellSize = landscapeCell.systemLayoutSizeFitting(
            CGSize(width: 390, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let portraitCellSize = portraitCell.systemLayoutSizeFitting(
            CGSize(width: 390, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        #expect(abs((landscapeSize.width / landscapeSize.height) - (16.0 / 9.0)) < 0.02)
        #expect(abs((portraitSize.width / portraitSize.height) - (9.0 / 16.0)) < 0.02)
        #expect(landscapeSize.width > landscapeSize.height)
        #expect(portraitSize.height > portraitSize.width)
        #expect(landscapeSize.width <= 240)
        #expect(portraitSize.height <= 304)
        #expect(portraitCellSize.height > landscapeCellSize.height + 90)
    }

    @MainActor
    @Test func videoMessageMediaViewActivatesPlaybackFromWholeThumbnail() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let thumbnailURL = directory.appendingPathComponent("video.jpg")
        try makeJPEGData(width: 320, height: 180, quality: 0.9).write(to: thumbnailURL, options: [.atomic])
        let row = ChatMessageRowState(
            id: "video_tap",
            content: .video(.init(
                thumbnailPath: thumbnailURL.path,
                localPath: directory.appendingPathComponent("video.mov").path,
                durationMilliseconds: 2_000
            )),
            sortSequence: 1,
            timeText: "Now",
            statusText: nil,
            uploadProgress: nil,
            isOutgoing: false,
            canRetry: false,
            canDelete: true,
            canRevoke: false
        )
        var playedRow: ChatMessageRowState?
        let mediaView = MediaMessageContentView()
        mediaView.configure(
            row: row,
            style: ChatMessageContentStyle(
                textColor: .label,
                secondaryTextColor: .secondaryLabel,
                tintColor: .systemBlue
            ),
            actions: ChatMessageCellActions(
                onRetry: { _ in },
                onDelete: { _ in },
                onRevoke: { _ in },
                onPlayVoice: { _ in },
                onPlayVideo: { playedRow = $0 }
            )
        )

        #expect(mediaView.accessibilityActivate())
        #expect(playedRow?.id == "video_tap")
    }

    @MainActor
    @Test func chatMessageCellConfigurationPreservesIdentifiersMetadataAndPlaybackState() throws {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        let row = ChatMessageRowState(
            id: "cell_voice",
            content: .voice(
                ChatMessageRowContent.VoiceContent(
                    localPath: "/tmp/cell_voice.m4a",
                    durationMilliseconds: 2_000,
                    isUnplayed: false,
                    isPlaying: true,
                    playbackProgress: 0.5,
                    playbackElapsedMilliseconds: 1_000
                )
            ),
            sortSequence: 1,
            timeText: "Now",
            statusText: "Failed",
            uploadProgress: nil,
            isOutgoing: true,
            canRetry: true,
            canDelete: true,
            canRevoke: false
        )

        cell.configure(row: row, actions: .empty)

        #expect(cell.contentConfiguration is ChatMessageCellContentConfiguration)
        #expect(cell.accessibilityIdentifier == "chat.messageCell.cell_voice")
        #expect(cell.accessibilityLabel == "Voice 0:02, Failed")
        #expect(findView(in: cell, identifier: "chat.retryButton.cell_voice") != nil)
        #expect(findLabel(withText: "Now · Failed", in: cell) != nil)
        #expect(findLabel(withText: "0:01/0:02", in: cell) != nil)

        let voiceButton = try #require(button(in: cell, accessibilityLabel: "Stop Voice"))
        #expect(voiceButton.image(for: .normal) == UIImage(systemName: "pause.fill"))
    }

    @MainActor
    @Test func chatMessageCellCentersMessageTimeMetadata() throws {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        let row = ChatMessageRowState(
            id: "cell_time",
            content: .text("Hello"),
            sortSequence: 1,
            timeText: "18:08",
            statusText: nil,
            uploadProgress: nil,
            isOutgoing: true,
            canRetry: false,
            canDelete: true,
            canRevoke: false
        )

        cell.configure(row: row, actions: .empty)
        cell.setNeedsLayout()
        cell.layoutIfNeeded()

        let timeLabel = try #require(findLabel(withText: "18:08", in: cell))
        let bubbleView = try #require(findView(ofType: ChatBubbleBackgroundView.self, in: cell))
        let timeCenterX = timeLabel.convert(timeLabel.bounds, to: cell.contentView).midX
        let timeFrame = timeLabel.convert(timeLabel.bounds, to: cell.contentView)
        let bubbleFrame = bubbleView.convert(bubbleView.bounds, to: cell.contentView)

        #expect(abs(timeCenterX - cell.contentView.bounds.midX) < 1)
        #expect(timeFrame.maxY < bubbleFrame.minY)
    }

    @MainActor
    @Test func chatMessageCellShowsOutgoingAvatarOnRight() throws {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        let row = makeChatRow(
            id: "outgoing_avatar",
            text: "发送者头像",
            sortSequence: 1,
            senderAvatarURL: "file:///tmp/current-avatar.png",
            isOutgoing: true
        )

        cell.configure(row: row, actions: .empty)
        cell.setNeedsLayout()
        cell.layoutIfNeeded()

        let avatarView = try #require(findView(ofType: GradientBackgroundView.self, in: cell))
        let bubbleView = try #require(findView(ofType: ChatBubbleBackgroundView.self, in: cell))
        let avatarFrame = avatarView.convert(avatarView.bounds, to: cell.contentView)
        let bubbleFrame = bubbleView.convert(bubbleView.bounds, to: cell.contentView)

        #expect(avatarView.isHidden == false)
        #expect(avatarFrame.minX > bubbleFrame.maxX)
    }

    @MainActor
    @Test func chatMessageCellShowsIncomingAvatarOnLeft() throws {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        let row = makeChatRow(
            id: "incoming_avatar",
            text: "对方头像",
            sortSequence: 1,
            senderAvatarURL: "file:///tmp/friend-avatar.png",
            isOutgoing: false
        )

        cell.configure(row: row, actions: .empty)
        cell.setNeedsLayout()
        cell.layoutIfNeeded()

        let avatarView = try #require(findView(ofType: GradientBackgroundView.self, in: cell))
        let bubbleView = try #require(findView(ofType: ChatBubbleBackgroundView.self, in: cell))
        let avatarFrame = avatarView.convert(avatarView.bounds, to: cell.contentView)
        let bubbleFrame = bubbleView.convert(bubbleView.bounds, to: cell.contentView)

        #expect(avatarView.isHidden == false)
        #expect(avatarFrame.maxX < bubbleFrame.minX)
    }

    @MainActor
    @Test func chatMessageCellHidesAvatarForRevokedMessage() throws {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        let row = makeRevokedRow(id: "revoked_avatar", sortSequence: 1)

        cell.configure(row: row, actions: .empty)
        cell.setNeedsLayout()
        cell.layoutIfNeeded()

        let avatarView = try #require(findView(ofType: GradientBackgroundView.self, in: cell))

        #expect(avatarView.isHidden)
    }

    @MainActor
    @Test func chatMessageCellHidesMetadataAndKeepsStableSizeWhenTimeSeparatorIsHidden() {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        let row = ChatMessageRowState(
            id: "cell_hidden_time",
            content: .text("Hello"),
            sortSequence: 1,
            timeText: "18:08",
            showsTimeSeparator: false,
            statusText: nil,
            uploadProgress: nil,
            isOutgoing: true,
            canRetry: false,
            canDelete: true,
            canRevoke: false
        )

        cell.configure(row: row, actions: .empty)
        cell.setNeedsLayout()
        cell.layoutIfNeeded()

        let fittingSize = cell.systemLayoutSizeFitting(
            CGSize(width: 390, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        #expect(findLabel(withText: "18:08", in: cell) == nil)
        #expect(fittingSize.height.isFinite)
        #expect(fittingSize.height < 160)
    }

    @MainActor
    @Test func chatMessageCellContentViewFittingIgnoresUnboundedCollectionViewHeightWhenMetadataIsHidden() throws {
        let row = ChatMessageRowState(
            id: "cell_hidden_time_unbounded",
            content: .text("Hello"),
            sortSequence: 1,
            timeText: "18:08",
            showsTimeSeparator: false,
            statusText: nil,
            uploadProgress: nil,
            isOutgoing: true,
            canRetry: false,
            canDelete: true,
            canRevoke: false
        )
        let configuration = ChatMessageCellContentConfiguration(row: row, actions: .empty)
        let contentView = configuration.makeContentView()

        let fittingSize = contentView.systemLayoutSizeFitting(
            CGSize(width: 402, height: CGFloat.greatestFiniteMagnitude),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        #expect(fittingSize.height.isFinite)
        #expect(fittingSize.height < 160)
    }

    @MainActor
    @Test func chatMessageCellContentConfigurationReusesCellAcrossContentKinds() throws {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 160))

        cell.configure(
            row: ChatMessageRowState(
                id: "reuse_text",
                content: .text("First text"),
                sortSequence: 1,
                timeText: "18:08",
                statusText: nil,
                uploadProgress: nil,
                isOutgoing: true,
                canRetry: false,
                canDelete: true,
                canRevoke: false
            ),
            actions: .empty
        )
        #expect(findLabel(withText: "First text", in: cell) != nil)

        cell.configure(
            row: ChatMessageRowState(
                id: "reuse_voice",
                content: .voice(
                    ChatMessageRowContent.VoiceContent(
                        localPath: "/tmp/reuse_voice.m4a",
                        durationMilliseconds: 3_000,
                        isUnplayed: true,
                        isPlaying: false
                    )
                ),
                sortSequence: 2,
                timeText: "18:09",
                statusText: nil,
                uploadProgress: nil,
                isOutgoing: false,
                canRetry: false,
                canDelete: true,
                canRevoke: false
            ),
            actions: .empty
        )

        #expect(findLabel(withText: "First text", in: cell) == nil)
        #expect(findLabel(withText: "0:03", in: cell) != nil)
        #expect(button(in: cell, accessibilityLabel: "Play Voice") != nil)
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

    @Test func photoLibraryVideoDataHandlerWritesChunksFromDetachedExecutor() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("picked-video.mov")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let task = Task.detached {
            let fileHandle = try FileHandle(forWritingTo: url)
            let dataHandler = ChatPhotoLibraryVideoFileIO.makeDataReceivedHandler(fileHandle: fileHandle)

            dataHandler(Data([0x01, 0x02]))
            dataHandler(Data([0x03]))
            try fileHandle.close()
        }
        try await task.value

        let data = try Data(contentsOf: url)
        #expect(data == Data([0x01, 0x02, 0x03]))
    }
}

private actor ScriptedSyncDeltaService: SyncDeltaService {
    private let batches: [SyncBatch]
    private var nextBatchIndex = 0
    private var checkpoints: [SyncCheckpoint?] = []

    init(batches: [SyncBatch]) {
        self.batches = batches
    }

    func fetchDelta(after checkpoint: SyncCheckpoint?) async throws -> SyncBatch {
        checkpoints.append(checkpoint)

        guard !batches.isEmpty else {
            return SyncBatch(messages: [], nextCursor: checkpoint?.cursor, nextSequence: checkpoint?.sequence)
        }

        let batchIndex = min(nextBatchIndex, batches.count - 1)
        nextBatchIndex += 1
        return batches[batchIndex]
    }

    func requestedCheckpoints() -> [SyncCheckpoint?] {
        checkpoints
    }
}

@MainActor
private final class TestNetworkConnectivityMonitor: NetworkConnectivityMonitoring {
    private let subject: CurrentValueSubject<Bool, Never>
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    init(isReachable: Bool) {
        self.subject = CurrentValueSubject(isReachable)
    }

    var isReachablePublisher: AnyPublisher<Bool, Never> {
        subject.eraseToAnyPublisher()
    }

    var currentIsReachable: Bool {
        subject.value
    }

    func start() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func setReachable(_ isReachable: Bool) {
        subject.send(isReachable)
    }
}

private struct StubConversationListUseCase: ConversationListUseCase {
    func loadConversations() async throws -> [ConversationListRowState] {
        [
            ConversationListRowState(
                id: "test_conversation",
                title: "Test Conversation",
                subtitle: "Loaded by ViewModel",
                timeText: "Now",
                unreadText: nil,
                isPinned: false,
                isMuted: false
            )
        ]
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        let rows = try await loadConversations()
        let requestedLimit = max(limit, 0)
        let startIndex = cursor
            .flatMap { cursor in rows.firstIndex { $0.id == cursor.conversationID } }
            .map { rows.index(after: $0) } ?? rows.startIndex
        let pageRows = Array(rows[startIndex...].prefix(requestedLimit))

        return ConversationListPage(
            rows: pageRows,
            hasMore: startIndex + pageRows.count < rows.count,
            nextCursor: pageRows.last.map { ConversationPageCursor(isPinned: $0.isPinned, sortTimestamp: 0, conversationID: $0.id) }
        )
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}
}

private actor StubContactListUseCase: ContactListUseCase {
    private(set) var queries: [String] = []

    func loadContacts(query: String) async throws -> ContactListViewState {
        queries.append(query)
        let row = ContactListRowState(
            contact: makeContactRecord(
                contactID: "contact_sondra",
                userID: "contact_vm_user",
                wxid: "sondra",
                nickname: "Sondra"
            )
        )
        return ContactListViewState(
            query: query,
            phase: .loaded,
            groupRows: [],
            starredRows: [],
            contactRows: [row]
        )
    }

    func openConversation(for contactID: ContactID) async throws -> ConversationListRowState {
        #expect(contactID == "contact_sondra")
        return ConversationListRowState(
            id: "single_sondra",
            title: "Sondra",
            subtitle: "",
            timeText: "",
            unreadText: nil,
            isPinned: false,
            isMuted: false
        )
    }
}

private struct PagedConversationListUseCase: ConversationListUseCase {
    private let rows: [ConversationListRowState] = (0..<3).map { index in
        ConversationListRowState(
            id: ConversationID(rawValue: "paged_\(index)"),
            title: "Paged \(index)",
            subtitle: "Page row \(index)",
            timeText: "Now",
            unreadText: nil,
            isPinned: false,
            isMuted: false
        )
    }

    func loadConversations() async throws -> [ConversationListRowState] {
        rows
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        let requestedLimit = max(limit, 0)
        let startIndex = cursor
            .flatMap { cursor in rows.firstIndex { $0.id == cursor.conversationID } }
            .map { rows.index(after: $0) } ?? rows.startIndex
        let pageRows = Array(rows[startIndex...].prefix(requestedLimit))

        return ConversationListPage(
            rows: pageRows,
            hasMore: startIndex + pageRows.count < rows.count,
            nextCursor: pageRows.last.map { ConversationPageCursor(isPinned: $0.isPinned, sortTimestamp: 0, conversationID: $0.id) }
        )
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}
}

private actor CursorShiftConversationListUseCase: ConversationListUseCase {
    private var didLoadFirstPage = false
    private let originalRows: [ConversationListRowState] = [
        ConversationListRowState(
            id: "shift_3",
            title: "Shift 3",
            subtitle: "Initial newest",
            timeText: "Now",
            unreadText: nil,
            isPinned: false,
            isMuted: false
        ),
        ConversationListRowState(
            id: "shift_2",
            title: "Shift 2",
            subtitle: "Initial cursor",
            timeText: "Now",
            unreadText: nil,
            isPinned: false,
            isMuted: false
        ),
        ConversationListRowState(
            id: "shift_1",
            title: "Shift 1",
            subtitle: "Older row",
            timeText: "Now",
            unreadText: nil,
            isPinned: false,
            isMuted: false
        )
    ]

    private var shiftedRows: [ConversationListRowState] {
        [
            ConversationListRowState(
                id: "shift_new",
                title: "Shift New",
                subtitle: "Inserted ahead of the cursor",
                timeText: "Now",
                unreadText: nil,
                isPinned: false,
                isMuted: false
            )
        ] + originalRows
    }

    func loadConversations() async throws -> [ConversationListRowState] {
        originalRows
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        let allRows: [ConversationListRowState]
        if cursor == nil {
            didLoadFirstPage = true
            allRows = originalRows
        } else {
            #expect(didLoadFirstPage)
            allRows = shiftedRows
        }

        let startIndex = cursor
            .flatMap { cursor in allRows.firstIndex { $0.id == cursor.conversationID } }
            .map { allRows.index(after: $0) } ?? allRows.startIndex
        let pageRows = Array(allRows[startIndex...].prefix(max(limit, 0)))

        return ConversationListPage(
            rows: pageRows,
            hasMore: startIndex + pageRows.count < allRows.count,
            nextCursor: pageRows.last.map { ConversationPageCursor(isPinned: $0.isPinned, sortTimestamp: 0, conversationID: $0.id) }
        )
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}
}

private actor MutableConversationListUseCase: ConversationListUseCase {
    private var row = ConversationListRowState(
        id: "mutable_conversation",
        title: "Mutable Conversation",
        subtitle: "Settings can change",
        timeText: "Now",
        unreadText: nil,
        isPinned: false,
        isMuted: false
    )

    func loadConversations() async throws -> [ConversationListRowState] {
        [row]
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        let allRows = try await loadConversations()
        let startIndex = cursor
            .flatMap { cursor in allRows.firstIndex { $0.id == cursor.conversationID } }
            .map { allRows.index(after: $0) } ?? allRows.startIndex
        let rows = Array(allRows[startIndex...].prefix(max(limit, 0)))
        return ConversationListPage(
            rows: rows,
            hasMore: false,
            nextCursor: rows.last.map { ConversationPageCursor(isPinned: $0.isPinned, sortTimestamp: 0, conversationID: $0.id) }
        )
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {
        guard conversationID == row.id else { return }
        row = ConversationListRowState(
            id: row.id,
            title: row.title,
            subtitle: row.subtitle,
            timeText: row.timeText,
            unreadText: row.unreadText,
            isPinned: isPinned,
            isMuted: row.isMuted
        )
    }

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {
        guard conversationID == row.id else { return }
        row = ConversationListRowState(
            id: row.id,
            title: row.title,
            subtitle: row.subtitle,
            timeText: row.timeText,
            unreadText: row.unreadText,
            isPinned: row.isPinned,
            isMuted: isMuted
        )
    }
}

private actor CountingConversationListUseCase: ConversationListUseCase {
    private(set) var loadPageCallCount = 0

    func loadConversations() async throws -> [ConversationListRowState] {
        try await loadConversationPage(limit: 50, after: nil).rows
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        loadPageCallCount += 1
        let rows = [
            ConversationListRowState(
                id: "counting_conversation",
                title: "Counting Conversation",
                subtitle: "Loaded once",
                timeText: "Now",
                unreadText: nil,
                isPinned: false,
                isMuted: false
            )
        ]
        return ConversationListPage(
            rows: rows,
            hasMore: false,
            nextCursor: rows.last.map { ConversationPageCursor(isPinned: $0.isPinned, sortTimestamp: 0, conversationID: $0.id) }
        )
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}
}

private actor ReadClearingConversationListUseCase: ConversationListUseCase {
    private(set) var loadPageCallCount = 0

    func loadConversations() async throws -> [ConversationListRowState] {
        try await loadConversationPage(limit: 50, after: nil).rows
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        loadPageCallCount += 1
        let unreadText = loadPageCallCount == 1 ? "2" : nil
        let rows = [
            ConversationListRowState(
                id: "read_clearing_conversation",
                title: "Read Clearing",
                subtitle: "Tap to read",
                timeText: "Now",
                unreadText: unreadText,
                isPinned: false,
                isMuted: false
            )
        ]
        return makeConversationListPage(rows: rows, limit: limit, after: cursor)
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}
}

private actor SimulatingConversationListUseCase: ConversationListUseCase {
    private var row = ConversationListRowState(
        id: "simulated_list_conversation",
        title: "Simulated List",
        subtitle: "Before simulation",
        timeText: "Now",
        unreadText: nil,
        isPinned: false,
        isMuted: false
    )
    private(set) var loadPageCallCount = 0
    private(set) var simulateIncomingCallCount = 0

    func loadConversations() async throws -> [ConversationListRowState] {
        try await loadConversationPage(limit: 50, after: nil).rows
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        loadPageCallCount += 1
        return makeConversationListPage(rows: [row], limit: limit, after: cursor)
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}

    func simulateIncomingMessages() async throws -> ConversationListSimulationResult? {
        simulateIncomingCallCount += 1
        row = ConversationListRowState(
            id: row.id,
            title: row.title,
            subtitle: "模拟收到 3 条列表消息 #stub",
            timeText: "Now",
            unreadText: "3",
            isPinned: row.isPinned,
            isMuted: row.isMuted
        )
        return ConversationListSimulationResult(
            conversationID: row.id,
            messageCount: 3,
            finalRow: row
        )
    }
}

private actor ExternalConversationChangeUseCase: ConversationListUseCase {
    private var row = ConversationListRowState(
        id: "external_change_conversation",
        title: "External Change",
        subtitle: "No unread yet",
        timeText: "Now",
        unreadText: nil,
        isPinned: false,
        isMuted: false
    )

    func loadConversations() async throws -> [ConversationListRowState] {
        try await loadConversationPage(limit: 50, after: nil).rows
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        makeConversationListPage(rows: [row], limit: limit, after: cursor)
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}

    func receiveUnreadMessage() {
        row = ConversationListRowState(
            id: row.id,
            title: row.title,
            subtitle: "Externally received",
            timeText: "Now",
            unreadText: "1",
            isPinned: row.isPinned,
            isMuted: row.isMuted
        )
    }
}

private actor ImmediateResultSlowRefreshConversationListUseCase: ConversationListUseCase {
    private var row = ConversationListRowState(
        id: "immediate_simulated_list_conversation",
        title: "Immediate Simulated List",
        subtitle: "Before simulation",
        timeText: "Now",
        unreadText: nil,
        isPinned: false,
        isMuted: false
    )
    private(set) var loadPageCallCount = 0
    private(set) var simulateIncomingCallCount = 0

    func loadConversations() async throws -> [ConversationListRowState] {
        try await loadConversationPage(limit: 50, after: nil).rows
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        loadPageCallCount += 1
        if loadPageCallCount > 1 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        return makeConversationListPage(rows: [row], limit: limit, after: cursor)
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}

    func simulateIncomingMessages() async throws -> ConversationListSimulationResult? {
        simulateIncomingCallCount += 1
        row = ConversationListRowState(
            id: row.id,
            title: row.title,
            subtitle: "Immediate simulation result",
            timeText: "Now",
            unreadText: "4",
            isPinned: row.isPinned,
            isMuted: row.isMuted
        )
        return ConversationListSimulationResult(
            conversationID: row.id,
            messageCount: 4,
            finalRow: row
        )
    }
}

private actor DelayedSimulatingConversationListUseCase: ConversationListUseCase {
    private var row = ConversationListRowState(
        id: "delayed_simulated_list_conversation",
        title: "Delayed Simulated List",
        subtitle: "Before simulation",
        timeText: "Now",
        unreadText: nil,
        isPinned: false,
        isMuted: false
    )
    private(set) var simulateIncomingCallCount = 0

    func loadConversations() async throws -> [ConversationListRowState] {
        [row]
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        makeConversationListPage(rows: [row], limit: limit, after: cursor)
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}

    func simulateIncomingMessages() async throws -> ConversationListSimulationResult? {
        simulateIncomingCallCount += 1
        try await Task.sleep(nanoseconds: 20_000_000)
        row = ConversationListRowState(
            id: row.id,
            title: row.title,
            subtitle: "模拟收到 \(simulateIncomingCallCount) 条列表消息 #delayed",
            timeText: "Now",
            unreadText: "\(simulateIncomingCallCount)",
            isPinned: false,
            isMuted: false
        )
        return ConversationListSimulationResult(
            conversationID: row.id,
            messageCount: simulateIncomingCallCount,
            finalRow: row
        )
    }
}

private struct FailingSimulationConversationListUseCase: ConversationListUseCase {
    func loadConversations() async throws -> [ConversationListRowState] {
        [
            ConversationListRowState(
                id: "failing_simulation_conversation",
                title: "Failing Simulation",
                subtitle: "Loaded before failure",
                timeText: "Now",
                unreadText: nil,
                isPinned: false,
                isMuted: false
            )
        ]
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        let rows = try await loadConversations()
        return makeConversationListPage(rows: rows, limit: limit, after: cursor)
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}

    func simulateIncomingMessages() async throws -> ConversationListSimulationResult? {
        throw TestChatError.expectedFailure
    }
}

private struct EmptySimulationConversationListUseCase: ConversationListUseCase {
    func loadConversations() async throws -> [ConversationListRowState] {
        []
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        ConversationListPage(rows: [], hasMore: false, nextCursor: nil)
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}

    func simulateIncomingMessages() async throws -> ConversationListSimulationResult? {
        nil
    }
}

private func makeConversationListPage(
    rows: [ConversationListRowState],
    limit: Int,
    after cursor: ConversationPageCursor?
) -> ConversationListPage {
    let startIndex = cursor
        .flatMap { cursor in rows.firstIndex { $0.id == cursor.conversationID } }
        .map { rows.index(after: $0) } ?? rows.startIndex
    let pageRows = Array(rows[startIndex...].prefix(max(limit, 0)))

    return ConversationListPage(
        rows: pageRows,
        hasMore: startIndex + pageRows.count < rows.count,
        nextCursor: pageRows.last.map {
            ConversationPageCursor(isPinned: $0.isPinned, sortTimestamp: 0, conversationID: $0.id)
        }
    )
}

private final class ConversationListLoadingDiagnosticsSpy: ConversationListLoadingDiagnostics, @unchecked Sendable {
    private let lock = NSLock()
    private var storedMessages: [String] = []

    var messages: [String] {
        lock.withLock {
            storedMessages
        }
    }

    func log(_ message: String) {
        lock.withLock {
            storedMessages.append(message)
        }
    }
}

private actor ConversationChangeNotificationSpy {
    private var records: [(userID: String?, conversationIDs: [String])] = []

    func record(userID: String?, conversationIDs: [String]) {
        records.append((userID: userID, conversationIDs: conversationIDs))
    }

    func didRecord(userID: String, conversationID: String) -> Bool {
        records.contains {
            $0.userID == userID && $0.conversationIDs.contains(conversationID)
        }
    }
}

private struct EmptySearchUseCase: SearchUseCase {
    func search(query: String) async throws -> SearchResults {
        SearchResults()
    }

    func rebuildIndex() async throws {}
}

private actor TrackingAccountStorageService: AccountStorageService {
    private let rootDirectory: URL
    private(set) var prepareCallCount = 0

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    func prepareStorage(for accountID: UserID) async throws -> AccountStoragePaths {
        prepareCallCount += 1
        let paths = try makePaths(for: accountID)
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: paths.rootDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.mediaDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.cacheDirectory, withIntermediateDirectories: true)
        createFileIfNeeded(at: paths.mainDatabase)
        createFileIfNeeded(at: paths.searchDatabase)
        createFileIfNeeded(at: paths.fileIndexDatabase)

        return paths
    }

    func deleteStorage(for accountID: UserID) async throws {
        let paths = try makePaths(for: accountID)
        if FileManager.default.fileExists(atPath: paths.rootDirectory.path) {
            try FileManager.default.removeItem(at: paths.rootDirectory)
        }
    }

    private func makePaths(for accountID: UserID) throws -> AccountStoragePaths {
        let rawID = accountID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawID.isEmpty else {
            throw AccountStorageError.emptyAccountID
        }

        let accountRoot = rootDirectory.appendingPathComponent("account_\(rawID)", isDirectory: true)
        return AccountStoragePaths(
            accountID: accountID,
            rootDirectory: accountRoot,
            mainDatabase: accountRoot.appendingPathComponent("main.db"),
            searchDatabase: accountRoot.appendingPathComponent("search.db"),
            fileIndexDatabase: accountRoot.appendingPathComponent("file_index.db"),
            mediaDirectory: accountRoot.appendingPathComponent("media", isDirectory: true),
            cacheDirectory: accountRoot.appendingPathComponent("cache", isDirectory: true)
        )
    }

    private func createFileIfNeeded(at url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: Data())
        }
    }
}

private actor TrackingAccountDatabaseKeyStore: AccountDatabaseKeyStore {
    private var keys: [UserID: Data] = [:]
    private(set) var databaseKeyCallCount = 0

    func databaseKey(for accountID: UserID) async throws -> Data {
        databaseKeyCallCount += 1
        if let key = keys[accountID] {
            return key
        }

        let key = Data(repeating: UInt8(databaseKeyCallCount), count: 32)
        keys[accountID] = key
        return key
    }

    func deleteDatabaseKey(for accountID: UserID) async throws {
        keys[accountID] = nil
    }
}

private struct StaleSearchUseCase: SearchUseCase {
    func search(query: String) async throws -> SearchResults {
        if query == "old" {
            try await Task.sleep(nanoseconds: 80_000_000)
            return SearchResults(
                messages: [
                    SearchResultRecord(
                        kind: .message,
                        id: "old_result",
                        title: "Old Result",
                        subtitle: "Old",
                        conversationID: "old_conversation",
                        messageID: "old_message"
                    )
                ]
            )
        }

        return SearchResults(
            messages: [
                SearchResultRecord(
                    kind: .message,
                    id: "new_result",
                    title: "New Result",
                    subtitle: "New",
                    conversationID: "new_conversation",
                    messageID: "new_message"
                )
            ]
        )
    }

    func rebuildIndex() async throws {}
}

private struct SlowChatUseCase: ChatUseCase {
    func loadInitialMessages() async throws -> ChatMessagePage {
        try await Task.sleep(nanoseconds: 200_000_000)
        return ChatMessagePage(
            rows: [
                makeChatRow(id: "slow_message", text: "Too late", sortSequence: 1)
            ],
            hasMore: false,
            nextBeforeSortSequence: 1
        )
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

private final class StoreRefreshingChatUseCase: @unchecked Sendable, ChatUseCase {
    let observedUserID: UserID? = "store_refresh_user"
    let observedConversationID: ConversationID? = "store_refresh_conversation"
    private var rows: [ChatMessageRowState] = []
    private(set) var loadInitialMessagesCallCount = 0

    func replaceRows(_ rows: [ChatMessageRowState]) {
        self.rows = rows
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        loadInitialMessagesCallCount += 1
        return ChatMessagePage(rows: rows, hasMore: false, nextBeforeSortSequence: rows.first?.sortSequence)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

private final class SimulatedIncomingStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private let initialRows: [ChatMessageRowState]
    private let simulatedRows: [ChatMessageRowState]
    private(set) var simulateIncomingCallCount = 0

    init(
        initialRows: [ChatMessageRowState] = [],
        simulatedRows: [ChatMessageRowState]? = nil
    ) {
        self.initialRows = initialRows
        self.simulatedRows = simulatedRows ?? [
            ChatMessageRowState(
                id: "simulated_incoming_stub_1",
                content: .text("模拟收到第 1 条后台推送"),
                sortSequence: 1,
                timeText: "Now",
                statusText: nil,
                uploadProgress: nil,
                isOutgoing: false,
                canRetry: false,
                canDelete: true,
                canRevoke: false
            ),
            ChatMessageRowState(
                id: "simulated_incoming_stub_2",
                content: .text("模拟收到第 2 条后台推送"),
                sortSequence: 2,
                timeText: "Now",
                statusText: nil,
                uploadProgress: nil,
                isOutgoing: false,
                canRetry: false,
                canDelete: true,
                canRevoke: false
            )
        ]
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: initialRows, hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func simulateIncomingMessages() async throws -> [ChatMessageRowState] {
        simulateIncomingCallCount += 1
        return simulatedRows
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

private actor CapturingSimulatedIncomingPusher: SimulatedIncomingPushing {
    private let result: SimulatedIncomingPushResult?
    private(set) var requests: [SimulatedIncomingPushRequest] = []

    init(result: SimulatedIncomingPushResult?) {
        self.result = result
    }

    func simulateIncomingPush(
        _ request: SimulatedIncomingPushRequest = SimulatedIncomingPushRequest()
    ) async throws -> SimulatedIncomingPushResult? {
        requests.append(request)
        return result
    }
}

private final class MissedSimulatedIncomingStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private(set) var simulateIncomingCallCount = 0

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func simulateIncomingMessages() async throws -> [ChatMessageRowState] {
        simulateIncomingCallCount += 1
        return []
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

private final class DelayedSimulatedIncomingStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private(set) var simulateIncomingCallCount = 0

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func simulateIncomingMessages() async throws -> [ChatMessageRowState] {
        simulateIncomingCallCount += 1
        let callCount = simulateIncomingCallCount
        try await Task.sleep(nanoseconds: 30_000_000)
        return [ChatMessageRowState(
            id: MessageID(rawValue: "simulated_incoming_delayed_\(callCount)"),
            content: .text("模拟收到第 \(callCount) 条消息"),
            sortSequence: Int64(callCount),
            timeText: "Now",
            statusText: nil,
            uploadProgress: nil,
            isOutgoing: false,
            canRetry: false,
            canDelete: true,
            canRevoke: false
        )]
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

private final class DelayedTextSendingStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private(set) var sentTexts: [String] = []

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sentTexts.append(text)
        let sortSequence = Int64(sentTexts.count)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Task.sleep(nanoseconds: 30_000_000)
                    continuation.yield(
                        makeChatRow(
                            id: MessageID(rawValue: "delayed_text_send_\(sortSequence)"),
                            text: text,
                            sortSequence: sortSequence
                        )
                    )
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

private final class PagingStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private let initialPage: ChatMessagePage
    private let olderPage: ChatMessagePage
    private let olderError: TestChatError?
    private(set) var loadOlderCallCount = 0

    init(initialPage: ChatMessagePage, olderPage: ChatMessagePage, olderError: TestChatError? = nil) {
        self.initialPage = initialPage
        self.olderPage = olderPage
        self.olderError = olderError
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        initialPage
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        loadOlderCallCount += 1

        if let olderError {
            throw olderError
        }

        return olderPage
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

private final class DeferredInitialPageStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private let initialPage: ChatMessagePage
    private var initialContinuation: CheckedContinuation<ChatMessagePage, Error>?
    private var isInitialPageReleased = false

    init(initialPage: ChatMessagePage) {
        self.initialPage = initialPage
    }

    func releaseInitialPage() {
        isInitialPageReleased = true
        let continuation = initialContinuation
        initialContinuation = nil

        continuation?.resume(returning: initialPage)
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        if isInitialPageReleased {
            return initialPage
        }

        return try await withCheckedThrowingContinuation { continuation in
            if isInitialPageReleased {
                continuation.resume(returning: initialPage)
            } else {
                initialContinuation = continuation
            }
        }
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

private final class DeferredOlderPageStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private let initialPage: ChatMessagePage
    private let olderPage: ChatMessagePage
    private var olderContinuation: CheckedContinuation<ChatMessagePage, Error>?
    private var isOlderPageReleased = false
    private(set) var loadOlderCallCount = 0

    init(initialPage: ChatMessagePage, olderPage: ChatMessagePage) {
        self.initialPage = initialPage
        self.olderPage = olderPage
    }

    func releaseOlderPage() {
        isOlderPageReleased = true
        let continuation = olderContinuation
        olderContinuation = nil

        continuation?.resume(returning: olderPage)
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        initialPage
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        loadOlderCallCount += 1
        if isOlderPageReleased {
            return olderPage
        }

        return try await withCheckedThrowingContinuation { continuation in
            if isOlderPageReleased {
                continuation.resume(returning: olderPage)
            } else {
                olderContinuation = continuation
            }
        }
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

@MainActor
private final class GroupContextStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private let context: GroupChatContext
    private(set) var sentText: String?
    private(set) var sentMentionedUserIDs: [UserID] = []
    private(set) var sentMentionsAll = false

    init(context: GroupChatContext) {
        self.context = context
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func loadGroupContext() async throws -> GroupChatContext? {
        context
    }

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sendText(text, mentionedUserIDs: [], mentionsAll: false)
    }

    func sendText(_ text: String, mentionedUserIDs: [UserID], mentionsAll: Bool) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sentText = text
        sentMentionedUserIDs = mentionedUserIDs
        sentMentionsAll = mentionsAll
        return AsyncThrowingStream { continuation in
            continuation.yield(makeChatRow(id: "group_context_sent", text: text, sortSequence: 1))
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVideo(fileURL: URL, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendFile(fileURL: URL) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

private final class RecoveringPagingStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private let initialPage: ChatMessagePage
    private let recoveredPage: ChatMessagePage
    private(set) var loadOlderCallCount = 0

    init(initialPage: ChatMessagePage, recoveredPage: ChatMessagePage) {
        self.initialPage = initialPage
        self.recoveredPage = recoveredPage
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        initialPage
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        loadOlderCallCount += 1

        if loadOlderCallCount == 1 {
            throw TestChatError.paginationFailed
        }

        return recoveredPage
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

private final class MessageActionStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private let initialRows: [ChatMessageRowState]
    private let revokedRows: [ChatMessageRowState]
    private let deleteError: TestChatError?
    private let revokeError: TestChatError?
    private var didRevoke = false
    private(set) var deletedMessageIDs: [MessageID] = []
    private(set) var revokedMessageIDs: [MessageID] = []

    init(
        initialRows: [ChatMessageRowState],
        revokedRows: [ChatMessageRowState]? = nil,
        deleteError: TestChatError? = nil,
        revokeError: TestChatError? = nil
    ) {
        self.initialRows = initialRows
        self.revokedRows = revokedRows ?? initialRows
        self.deleteError = deleteError
        self.revokeError = revokeError
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(
            rows: didRevoke ? revokedRows : initialRows,
            hasMore: false,
            nextBeforeSortSequence: nil
        )
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {
        if let deleteError {
            throw deleteError
        }
        deletedMessageIDs.append(messageID)
    }

    func revoke(messageID: MessageID) async throws {
        if let revokeError {
            throw revokeError
        }
        didRevoke = true
        revokedMessageIDs.append(messageID)
    }
}

private final class TextSendingTimeStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private let initialRows: [ChatMessageRowState]
    private var sentRows: [ChatMessageRowState]

    init(initialRows: [ChatMessageRowState], sentRows: [ChatMessageRowState]) {
        self.initialRows = initialRows
        self.sentRows = sentRows
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: initialRows, hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        let row = sentRows.removeFirst()
        return AsyncThrowingStream { continuation in
            continuation.yield(row)
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

private final class ImageSendingStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private(set) var sentImageCount = 0
    private let initialRows: [ChatMessageRowState]
    private let thumbnailPath: String

    init(initialRows: [ChatMessageRowState] = [], thumbnailPath: String = "/tmp/chat-thumb.jpg") {
        self.initialRows = initialRows
        self.thumbnailPath = thumbnailPath
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: initialRows, hasMore: false, nextBeforeSortSequence: initialRows.first?.sortSequence)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sentImageCount += 1

        return AsyncThrowingStream { continuation in
            continuation.yield(
                ChatMessageRowState(
                    id: "image_stub_message",
                    content: .image(
                        ChatMessageRowContent.ImageContent(
                            thumbnailPath: thumbnailPath
                        )
                    ),
                    sortSequence: 1,
                    timeText: "Now",
                    statusText: nil,
                    uploadProgress: nil,
                    isOutgoing: true,
                    canRetry: false,
                    canDelete: true,
                    canRevoke: false
                )
            )
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

@MainActor
private final class EmojiPanelStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private let initialRows: [ChatMessageRowState]
    let packageEmoji = EmojiAssetRecord(
        emojiID: "package_stub",
        userID: "emoji_panel_user",
        packageID: "pkg_stub",
        emojiType: .package,
        name: "Package Stub",
        md5: nil,
        localPath: "/tmp/package.png",
        thumbPath: "/tmp/package-thumb.png",
        cdnURL: nil,
        width: 128,
        height: 128,
        sizeBytes: 1024,
        useCount: 0,
        lastUsedAt: nil,
        isFavorite: false,
        isDeleted: false,
        extraJSON: nil,
        createdAt: 1,
        updatedAt: 1
    )
    private(set) var favoriteUpdates: [String] = []
    private(set) var sentEmojiIDs: [String] = []

    init(initialRows: [ChatMessageRowState] = []) {
        self.initialRows = initialRows
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: initialRows, hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func loadEmojiPanelState() async throws -> ChatEmojiPanelState {
        ChatEmojiPanelState(
            packages: [
                EmojiPackageRecord(
                    packageID: "pkg_stub",
                    userID: "emoji_panel_user",
                    title: "Stub Pack",
                    author: "Tests",
                    coverURL: nil,
                    localCoverPath: nil,
                    version: 1,
                    status: .downloaded,
                    sortOrder: 1,
                    createdAt: 1,
                    updatedAt: 1
                )
            ],
            recentEmojis: [],
            favoriteEmojis: [
                EmojiAssetRecord(
                    emojiID: "favorite_stub",
                    userID: "emoji_panel_user",
                    packageID: nil,
                    emojiType: .customImage,
                    name: "Favorite Stub",
                    md5: nil,
                    localPath: "/tmp/favorite.png",
                    thumbPath: "/tmp/favorite-thumb.png",
                    cdnURL: nil,
                    width: 128,
                    height: 128,
                    sizeBytes: 1024,
                    useCount: 2,
                    lastUsedAt: 2,
                    isFavorite: true,
                    isDeleted: false,
                    extraJSON: nil,
                    createdAt: 1,
                    updatedAt: 2
                )
            ],
            packageEmojisByPackageID: ["pkg_stub": [packageEmoji]]
        )
    }

    func toggleEmojiFavorite(emojiID: String, isFavorite: Bool) async throws -> ChatEmojiPanelState {
        favoriteUpdates.append("\(emojiID):\(isFavorite)")
        return try await loadEmojiPanelState()
    }

    func sendEmoji(_ emoji: EmojiAssetRecord) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sentEmojiIDs.append(emoji.emojiID)

        return AsyncThrowingStream { continuation in
            continuation.yield(
                ChatMessageRowState(
                    id: "sent_emoji",
                    content: .emoji(
                        ChatMessageRowContent.EmojiContent(
                            emojiID: emoji.emojiID,
                            name: emoji.name,
                            localPath: emoji.localPath,
                            thumbPath: emoji.thumbPath,
                            cdnURL: emoji.cdnURL
                        )
                    ),
                    sortSequence: 1,
                    timeText: "Now",
                    statusText: nil,
                    uploadProgress: nil,
                    isOutgoing: true,
                    canRetry: false,
                    canDelete: true,
                    canRevoke: false
                )
            )
            continuation.finish()
        }
    }

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

private final class ComposerSendingStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private(set) var events: [String] = []

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        events.append("text:\(text)")

        return AsyncThrowingStream { continuation in
            continuation.yield(
                makeChatRow(id: "composer_text", text: text, sortSequence: 2)
            )
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        events.append("image:\(preferredFileExtension ?? "")")

        return AsyncThrowingStream { continuation in
            continuation.yield(
                ChatMessageRowState(
                    id: "composer_image",
                    content: .image(
                        ChatMessageRowContent.ImageContent(
                            thumbnailPath: "/tmp/composer-image.jpg"
                        )
                    ),
                    sortSequence: 1,
                    timeText: "Now",
                    statusText: nil,
                    uploadProgress: nil,
                    isOutgoing: true,
                    canRetry: false,
                    canDelete: true,
                    canRevoke: false
                )
            )
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVideo(fileURL: URL, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        events.append("video:\(preferredFileExtension ?? "")")

        return AsyncThrowingStream { continuation in
            continuation.yield(
                ChatMessageRowState(
                    id: "composer_video",
                    content: .video(
                        ChatMessageRowContent.VideoContent(
                            thumbnailPath: "/tmp/composer-video.jpg",
                            localPath: fileURL.path,
                            durationMilliseconds: 1_000
                        )
                    ),
                    sortSequence: 1,
                    timeText: "Now",
                    statusText: nil,
                    uploadProgress: nil,
                    isOutgoing: true,
                    canRetry: false,
                    canDelete: true,
                    canRevoke: false
                )
            )
            continuation.finish()
        }
    }

    func sendFile(fileURL: URL) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

private final class VoicePlaybackStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private var rows: [ChatMessageRowState]
    private(set) var markedMessageIDs: [MessageID] = []

    init(rows: [ChatMessageRowState]) {
        self.rows = rows
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: rows, hasMore: false, nextBeforeSortSequence: rows.first?.sortSequence)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        markedMessageIDs.append(messageID)

        guard let index = rows.firstIndex(where: { $0.id == messageID }) else {
            return nil
        }

        rows[index] = rows[index].withVoicePlayback(isPlaying: false, isUnplayed: false)
        return rows[index]
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

private final class ImmediateVoiceSendStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private let row: ChatMessageRowState

    init(row: ChatMessageRowState) {
        self.row = row
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(row)
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

private enum TestChatError: Error {
    case paginationFailed
    case messageActionFailed
    case expectedFailure
}

private extension ChatUseCase {
    func sendVideo(fileURL: URL, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendFile(fileURL: URL) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private func makeChatRow(
    id: MessageID,
    text: String,
    sortSequence: Int64,
    sentAt: Int64 = 0,
    senderAvatarURL: String? = nil,
    isOutgoing: Bool = true
) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .text(text),
        sortSequence: sortSequence,
        sentAt: sentAt,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        senderAvatarURL: senderAvatarURL,
        isOutgoing: isOutgoing,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}

@MainActor
private func makeScrollableChatViewController(
    title: String,
    rowPrefix: String,
    useEmojiUseCase: Bool = false
) async throws -> (
    window: UIWindow,
    viewController: ChatViewController,
    collectionView: UICollectionView,
    inputBar: ChatInputBarView
) {
    let rows = (1...36).map { index in
        makeChatRow(
            id: MessageID(rawValue: "\(rowPrefix)_\(index)"),
            text: "\(title) message \(index)",
            sortSequence: Int64(index)
        )
    }
    let viewModel: ChatViewModel
    if useEmojiUseCase {
        viewModel = ChatViewModel(
            useCase: EmojiPanelStubChatUseCase(initialRows: rows),
            title: title
        )
    } else {
        viewModel = ChatViewModel(
            useCase: PagingStubChatUseCase(
                initialPage: ChatMessagePage(rows: rows, hasMore: false, nextBeforeSortSequence: nil),
                olderPage: ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
            ),
            title: title
        )
    }
    let viewController = ChatViewController(viewModel: viewModel)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = viewController
    window.makeKeyAndVisible()

    viewController.loadViewIfNeeded()
    try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
        guard let collectionView = findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView else {
            return false
        }
        return collectionView.numberOfItems(inSection: 0) == rows.count
    }
    window.layoutIfNeeded()

    let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
    let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
    return (window, viewController, collectionView, inputBar)
}

@MainActor
private func assertChatCollectionCanLeaveBottomAfterUserDrag(
    viewController: ChatViewController,
    collectionView: UICollectionView,
    window: UIWindow
) throws {
    let lastItem = collectionView.numberOfItems(inSection: 0) - 1
    try #require(lastItem > 0)

    collectionView.scrollToItem(at: IndexPath(item: lastItem, section: 0), at: .bottom, animated: false)
    window.layoutIfNeeded()
    collectionView.layoutIfNeeded()

    let bottomOffsetY = collectionView.contentOffset.y
    let minOffsetY = -collectionView.adjustedContentInset.top
    let targetOffsetY = max(minOffsetY, bottomOffsetY - 160)
    try #require(targetOffsetY < bottomOffsetY - 1)

    viewController.scrollViewWillBeginDragging(collectionView)
    collectionView.setContentOffset(
        CGPoint(x: collectionView.contentOffset.x, y: targetOffsetY),
        animated: false
    )
    viewController.viewDidLayoutSubviews()
    collectionView.layoutIfNeeded()

    #expect(collectionView.contentOffset.y <= targetOffsetY + 1)
}

@MainActor
private func latestMessageCellIsAboveInputBar(
    collectionView: UICollectionView,
    item: Int,
    inputBar: ChatInputBarView,
    in view: UIView
) -> Bool {
    guard let cell = collectionView.cellForItem(at: IndexPath(item: item, section: 0)) else {
        return false
    }
    let cellFrame = cell.convert(cell.bounds, to: view)
    let inputFrame = inputBar.convert(inputBar.bounds, to: view)
    return cellFrame.maxY <= inputFrame.minY + 1
}

private func timestamp(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    calendar: Calendar
) throws -> Int64 {
    let date = try #require(
        calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )
    )
    return Int64(date.timeIntervalSince1970)
}

private func makeRevokedChatRow(id: MessageID, text: String, sortSequence: Int64) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .revoked(text),
        sortSequence: sortSequence,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: true,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}

private func makeVoiceRow(id: MessageID, sortSequence: Int64, isUnplayed: Bool) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .voice(
            ChatMessageRowContent.VoiceContent(
                localPath: "/tmp/\(id.rawValue).m4a",
                durationMilliseconds: 2_000,
                isUnplayed: isUnplayed,
                isPlaying: false
            )
        ),
        sortSequence: sortSequence,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: false,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}

private func makeImageRow(id: MessageID, sortSequence: Int64) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .image(
            ChatMessageRowContent.ImageContent(
                thumbnailPath: "/tmp/\(id.rawValue).jpg"
            )
        ),
        sortSequence: sortSequence,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: false,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}

private func makeVideoRow(id: MessageID, sortSequence: Int64) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .video(
            ChatMessageRowContent.VideoContent(
                thumbnailPath: "/tmp/\(id.rawValue).jpg",
                localPath: "/tmp/\(id.rawValue).mov",
                durationMilliseconds: 3_000
            )
        ),
        sortSequence: sortSequence,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: false,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}

private func makeFileRow(id: MessageID, sortSequence: Int64) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .file(
            ChatMessageRowContent.FileContent(
                fileName: "\(id.rawValue).pdf",
                fileExtension: "pdf",
                localPath: "/tmp/\(id.rawValue).pdf",
                sizeBytes: 1_024
            )
        ),
        sortSequence: sortSequence,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: false,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}

private func makeRevokedRow(id: MessageID, sortSequence: Int64) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .revoked("你撤回了一条消息"),
        sortSequence: sortSequence,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: true,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}

@Test func chatMessageRowStateWithVoicePlaybackPreservesSenderAvatarURL() {
    let row = ChatMessageRowState(
        id: "avatar_voice",
        content: .voice(
            ChatMessageRowContent.VoiceContent(
                localPath: "/tmp/avatar_voice.m4a",
                durationMilliseconds: 2_000,
                isUnplayed: true,
                isPlaying: false
            )
        ),
        sortSequence: 1,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        senderAvatarURL: "https://example.com/voice-avatar.png",
        isOutgoing: false,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )

    let updatedRow = row.withVoicePlayback(isPlaying: true)

    #expect(updatedRow.senderAvatarURL == "https://example.com/voice-avatar.png")
    #expect(isPlayingVoiceContent(updatedRow))
}

@Test func chatMessageRowStateWithVoicePlaybackPreservesTimeSeparatorState() {
    let row = ChatMessageRowState(
        id: "time_voice",
        content: .voice(
            ChatMessageRowContent.VoiceContent(
                localPath: "/tmp/time_voice.m4a",
                durationMilliseconds: 2_000,
                isUnplayed: true,
                isPlaying: false
            )
        ),
        sortSequence: 1,
        sentAt: 1_000,
        timeText: "Now",
        showsTimeSeparator: false,
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: false,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )

    let updatedRow = row.withVoicePlayback(isPlaying: true)

    #expect(updatedRow.sentAt == 1_000)
    #expect(updatedRow.showsTimeSeparator == false)
    #expect(isPlayingVoiceContent(updatedRow))
}

private func rowText(_ row: ChatMessageRowState) -> String {
    switch row.content {
    case let .text(text), let .revoked(text):
        return text
    case .image:
        return "Image"
    case let .voice(voice):
        return "Voice \(durationText(milliseconds: voice.durationMilliseconds))"
    case let .video(video):
        return "Video \(durationText(milliseconds: video.durationMilliseconds))"
    case let .file(file):
        return file.fileName
    case let .emoji(emoji):
        return emoji.name ?? "Emoji"
    }
}

private func isImageContent(_ row: ChatMessageRowState) -> Bool {
    if case .image = row.content {
        return true
    }
    return false
}

private func imageThumbnailPath(_ row: ChatMessageRowState) -> String? {
    if case let .image(image) = row.content {
        return image.thumbnailPath
    }
    return nil
}

private func isVoiceContent(_ row: ChatMessageRowState) -> Bool {
    if case .voice = row.content {
        return true
    }
    return false
}

private func voiceLocalPath(_ row: ChatMessageRowState) -> String? {
    if case let .voice(voice) = row.content {
        return voice.localPath
    }
    return nil
}

private func isUnplayedVoiceContent(_ row: ChatMessageRowState) -> Bool {
    if case let .voice(voice) = row.content {
        return voice.isUnplayed
    }
    return false
}

private func isPlayingVoiceContent(_ row: ChatMessageRowState) -> Bool {
    if case let .voice(voice) = row.content {
        return voice.isPlaying
    }
    return false
}

private func isVideoContent(_ row: ChatMessageRowState) -> Bool {
    if case .video = row.content {
        return true
    }
    return false
}

private func videoThumbnailPath(_ row: ChatMessageRowState) -> String? {
    if case let .video(video) = row.content {
        return video.thumbnailPath
    }
    return nil
}

@MainActor
private func largestLoadedImageView(in view: UIView) -> UIImageView? {
    var candidates: [UIImageView] = []

    func collect(from view: UIView) {
        if let imageView = view as? UIImageView, imageView.image != nil {
            candidates.append(imageView)
        }
        view.subviews.forEach(collect)
    }

    collect(from: view)
    return candidates.max { lhs, rhs in
        (lhs.bounds.width * lhs.bounds.height) < (rhs.bounds.width * rhs.bounds.height)
    }
}

private func durationText(milliseconds: Int) -> String {
    ChatMessageRowContent.voiceDurationDisplayText(milliseconds: milliseconds)
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("AppleIMTests-\(UUID().uuidString)", isDirectory: true)
}

private func makeMockAccountsFile() throws -> URL {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("mock_accounts.json")
    let json = """
    [
      {
        "userID": "mock_user",
        "loginName": "mock_user",
        "password": "password123",
        "displayName": "Mock User",
        "mobile": "13700000000",
        "avatarURL": "https://example.com/mock-avatar.png"
      }
    ]
    """
    try Data(json.utf8).write(to: url, options: [.atomic])
    return url
}

private func makeMockContactsFile() throws -> URL {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("mock_contacts.json")
    let json = """
    [
      {
        "accountID": "mock_user",
        "contacts": [
          {
            "contactID": "contact_sondra",
            "wxid": "sondra",
            "nickname": "Sondra",
            "remark": "",
            "avatarURL": "https://example.com/sondra.png",
            "type": "friend",
            "isStarred": true
          },
          {
            "contactID": "group_core_contact",
            "wxid": "chatbridge_core",
            "nickname": "ChatBridge Core",
            "remark": "",
            "avatarURL": null,
            "type": "group",
            "isStarred": false
          }
        ]
      },
      {
        "accountID": "other_user",
        "contacts": [
          {
            "contactID": "contact_other",
            "wxid": "other",
            "nickname": "Other",
            "remark": "",
            "avatarURL": null,
            "type": "friend",
            "isStarred": false
          }
        ]
      }
    ]
    """
    try Data(json.utf8).write(to: url, options: [.atomic])
    return url
}

private func makeMockDemoDataFile(messageCount: Int, firstMessageDirection: String = "incoming") throws -> URL {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("mock_demo_data.json")
    let messages = (1...messageCount).map { index in
        let direction = index == 1 ? firstMessageDirection : (index.isMultiple(of: 5) ? "outgoing" : "incoming")
        let offset = index - messageCount
        return """
              {
                "conversationID": "single_sondra",
                "senderID": "\(direction == "outgoing" ? "mock_user" : "sondra")",
                "text": "Sondra JSON message \(index)",
                "localTimeOffsetSeconds": \(offset),
                "messageID": "seed_single_sondra_\(index)",
                "serverMessageID": "server_seed_single_sondra_\(index)",
                "sequenceOffsetSeconds": \(offset),
                "direction": "\(direction)",
                "readStatus": "\(direction == "incoming" ? "unread" : "read")",
                "sortSequenceOffsetSeconds": \(offset)
              }
        """
    }.joined(separator: ",\n")
    let lastOffset = 0
    let json = """
    [
      {
        "accountID": "mock_user",
        "conversations": [
          {
            "id": "single_sondra",
            "type": "single",
            "targetID": "sondra",
            "title": "Sondra",
            "avatarURL": null,
            "unreadCount": 2,
            "draftText": null,
            "isPinned": true,
            "isMuted": false,
            "isHidden": false,
            "createdAtOffsetSeconds": -7200
          },
          {
            "id": "group_core",
            "type": "group",
            "targetID": "chatbridge_core",
            "title": "ChatBridge Core",
            "avatarURL": null,
            "unreadCount": 0,
            "draftText": null,
            "isPinned": false,
            "isMuted": true,
            "isHidden": false,
            "createdAtOffsetSeconds": -7200,
            "lastMessageTimeOffsetSeconds": -1800,
            "lastMessageDigest": "群聊 JSON seed 已接入。",
            "sortTimestampOffsetSeconds": -1800
          },
          {
            "id": "system_release",
            "type": "system",
            "targetID": "system",
            "title": "系统通知",
            "avatarURL": null,
            "unreadCount": 0,
            "draftText": null,
            "isPinned": false,
            "isMuted": false,
            "isHidden": false,
            "createdAtOffsetSeconds": -7200,
            "lastMessageTimeOffsetSeconds": -3600,
            "lastMessageDigest": "系统 JSON seed 已接入。",
            "sortTimestampOffsetSeconds": -3600
          }
        ],
        "messages": [
    \(messages)
        ],
        "groupMembers": [
          {
            "conversationID": "group_core",
            "memberID": "mock_user",
            "displayName": "Me",
            "role": "admin",
            "joinTimeOffsetSeconds": -3600
          },
          {
            "conversationID": "group_core",
            "memberID": "sondra",
            "displayName": "Sondra",
            "role": "owner",
            "joinTimeOffsetSeconds": -3500
          }
        ],
        "groupAnnouncements": [
          {
            "conversationID": "group_core",
            "text": "群聊 JSON seed 已接入。"
          }
        ],
        "lastMessageTimeOffsetSeconds": \(lastOffset)
      },
      {
        "accountID": "other_user",
        "conversations": [],
        "messages": [],
        "groupMembers": [],
        "groupAnnouncements": []
      }
    ]
    """
    try Data(json.utf8).write(to: url, options: [.atomic])
    return url
}

private func samplePNGData() -> Data {
    Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")!
}

private func makeVoiceRecordingFile(in directory: URL) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("sample-\(UUID().uuidString)").appendingPathExtension("m4a")
    try Data("mock voice recording".utf8).write(to: url, options: [.atomic])
    return url
}

private func makeSampleVideoFile(in directory: URL) async throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("sample-\(UUID().uuidString)").appendingPathExtension("mov")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 64,
        AVVideoHeightKey: 64
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 64
        ]
    )

    guard writer.canAdd(input) else {
        Issue.record("Unable to add video writer input")
        return url
    }

    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    let firstPixelBuffer = try makePixelBuffer(width: 64, height: 64, colorOffset: 0)
    let secondPixelBuffer = try makePixelBuffer(width: 64, height: 64, colorOffset: 48)
    while !input.isReadyForMoreMediaData {
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    guard adaptor.append(firstPixelBuffer, withPresentationTime: .zero) else {
        throw writer.error ?? MediaFileError.invalidVideoFile
    }

    while !input.isReadyForMoreMediaData {
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    guard adaptor.append(secondPixelBuffer, withPresentationTime: CMTime(value: 1, timescale: 1)) else {
        throw writer.error ?? MediaFileError.invalidVideoFile
    }

    input.markAsFinished()
    await writer.finishWriting()

    if writer.status == .failed {
        throw writer.error ?? MediaFileError.invalidVideoFile
    }

    return url
}

private func makePixelBuffer(width: Int, height: Int, colorOffset: UInt8) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32ARGB,
        nil,
        &pixelBuffer
    )

    guard status == kCVReturnSuccess, let pixelBuffer else {
        throw MediaFileError.invalidVideoFile
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    }

    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        throw MediaFileError.invalidVideoFile
    }

    let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * 4
            buffer[offset] = 255
            buffer[offset + 1] = UInt8((x * 4 + Int(colorOffset)) % 256)
            buffer[offset + 2] = UInt8((y * 4 + Int(colorOffset)) % 256)
            buffer[offset + 3] = 180
        }
    }

    return pixelBuffer
}

private func makeJPEGData(width: Int, height: Int, quality: Double) -> Data {
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * bytesPerPixel
            pixels[offset] = UInt8(x % 256)
            pixels[offset + 1] = UInt8(y % 256)
            pixels[offset + 2] = UInt8((x + y) % 256)
            pixels[offset + 3] = 255
        }
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let image = context.makeImage()
    else {
        Issue.record("Unable to create JPEG test image")
        return Data()
    }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
        Issue.record("Unable to create JPEG destination")
        return Data()
    }

    CGImageDestinationAddImage(destination, image, [
        kCGImageDestinationLossyCompressionQuality: quality
    ] as CFDictionary)

    guard CGImageDestinationFinalize(destination) else {
        Issue.record("Unable to finalize JPEG test image")
        return Data()
    }

    return data as Data
}

private func imageDimensions(atPath path: String) -> (width: Int, height: Int) {
    guard
        let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else {
        Issue.record("Unable to read image dimensions at \(path)")
        return (0, 0)
    }

    return (
        properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
        properties[kCGImagePropertyPixelHeight] as? Int ?? 0
    )
}

private nonisolated struct DatabaseTestContext: Sendable {
    let databaseActor: DatabaseActor
    let paths: AccountStoragePaths
}

private func makeBootstrappedDatabase(rootDirectory: URL, accountID: UserID) async throws -> (DatabaseActor, AccountStoragePaths) {
    let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
    let paths = try await storageService.prepareStorage(for: accountID)
    let databaseActor = DatabaseActor()
    _ = try await databaseActor.bootstrap(paths: paths)
    return (databaseActor, paths)
}

private func makeRepository(rootDirectory: URL, accountID: UserID) async throws -> (LocalChatRepository, DatabaseTestContext) {
    let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: accountID)
    let repository = LocalChatRepository(database: databaseActor, paths: paths)
    return (repository, DatabaseTestContext(databaseActor: databaseActor, paths: paths))
}

private func seedPerformanceMessages(
    databaseContext: DatabaseTestContext,
    conversationID: ConversationID,
    userID: UserID,
    count: Int
) async throws {
    let numbersCTE = """
    WITH
        digits(d) AS (
            VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9)
        ),
        numbers(value) AS (
            SELECT ones.d + tens.d * 10 + hundreds.d * 100 + thousands.d * 1000 + tenThousands.d * 10000 + 1
            FROM digits AS ones
            CROSS JOIN digits AS tens
            CROSS JOIN digits AS hundreds
            CROSS JOIN digits AS thousands
            CROSS JOIN digits AS tenThousands
        )
    """

    try await databaseContext.databaseActor.execute(
        """
        \(numbersCTE)
        INSERT INTO message_text (content_id, text, mentions_json, at_all, rich_text_json)
        SELECT
            'perf_text_' || value,
            'Perf Message ' || value,
            NULL,
            0,
            NULL
        FROM numbers
        WHERE value <= \(count);
        """,
        paths: databaseContext.paths
    )

    try await databaseContext.databaseActor.execute(
        """
        \(numbersCTE)
        INSERT INTO message (
            message_id,
            conversation_id,
            sender_id,
            client_msg_id,
            msg_type,
            direction,
            send_status,
            delivery_status,
            read_status,
            revoke_status,
            is_deleted,
            content_table,
            content_id,
            sort_seq,
            local_time
        )
        SELECT
            'perf_message_' || value,
            ?,
            ?,
            'perf_client_' || value,
            \(MessageType.text.rawValue),
            \(MessageDirection.outgoing.rawValue),
            \(MessageSendStatus.success.rawValue),
            0,
            \(MessageReadStatus.read.rawValue),
            0,
            0,
            'message_text',
            'perf_text_' || value,
            value,
            value
        FROM numbers
        WHERE value <= \(count);
        """,
        parameters: [
            .text(conversationID.rawValue),
            .text(userID.rawValue)
        ],
        paths: databaseContext.paths
    )
}

private func databaseReadFails(using databaseActor: DatabaseActor, paths: AccountStoragePaths) async -> Bool {
    do {
        _ = try await databaseActor.tableNames(in: .main, paths: paths)
        return false
    } catch {
        return true
    }
}

private func moveElementCount(in path: UIBezierPath) -> Int {
    var count = 0
    path.cgPath.applyWithBlock { elementPointer in
        if elementPointer.pointee.type == .moveToPoint {
            count += 1
        }
    }
    return count
}

private func waitForCondition(
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    condition: @escaping () async throws -> Bool
) async throws {
    let startedAt = DispatchTime.now().uptimeNanoseconds

    while DispatchTime.now().uptimeNanoseconds - startedAt < timeoutNanoseconds {
        if try await condition() {
            return
        }

        try await Task.sleep(nanoseconds: 10_000_000)
    }

    Issue.record("Timed out waiting for condition")
}

private func makeConversationRecord(
    id: ConversationID,
    userID: UserID,
    title: String = "Conversation",
    type: ConversationType = .single,
    targetID: String? = nil,
    isPinned: Bool = false,
    isMuted: Bool = false,
    unreadCount: Int = 0,
    draftText: String? = nil,
    avatarURL: String? = nil,
    sortTimestamp: Int64 = 1
) -> ConversationRecord {
    ConversationRecord(
        id: id,
        userID: userID,
        type: type,
        targetID: targetID ?? "\(id.rawValue)_target",
        title: title,
        avatarURL: avatarURL,
        lastMessageID: nil,
        lastMessageTime: sortTimestamp,
        lastMessageDigest: "Digest \(title)",
        unreadCount: unreadCount,
        draftText: draftText,
        isPinned: isPinned,
        isMuted: isMuted,
        isHidden: false,
        sortTimestamp: sortTimestamp,
        updatedAt: sortTimestamp,
        createdAt: sortTimestamp
    )
}

private func makeContactRecord(
    contactID: ContactID,
    userID: UserID,
    wxid: String,
    nickname: String,
    remark: String? = nil,
    avatarURL: String? = nil,
    type: ContactType = .friend,
    isStarred: Bool = false,
    isBlocked: Bool = false,
    isDeleted: Bool = false,
    source: Int? = nil,
    extraJSON: String? = nil,
    timestamp: Int64 = 1
) -> ContactRecord {
    ContactRecord(
        contactID: contactID,
        userID: userID,
        wxid: wxid,
        nickname: nickname,
        remark: remark,
        avatarURL: avatarURL,
        type: type,
        isStarred: isStarred,
        isBlocked: isBlocked,
        isDeleted: isDeleted,
        source: source,
        extraJSON: extraJSON,
        updatedAt: timestamp,
        createdAt: timestamp
    )
}

private func makeEmojiPanelState(
    recentEmojis: [EmojiAssetRecord],
    favoriteEmojis: [EmojiAssetRecord],
    packageEmojis: [EmojiAssetRecord]
) -> ChatEmojiPanelState {
    let package = EmojiPackageRecord(
        packageID: "pkg_stub",
        userID: "emoji_panel_user",
        title: "ChatBridge",
        author: "Tests",
        coverURL: nil,
        localCoverPath: nil,
        version: 1,
        status: .downloaded,
        sortOrder: 1,
        createdAt: 1,
        updatedAt: 1
    )
    return ChatEmojiPanelState(
        packages: [package],
        recentEmojis: recentEmojis,
        favoriteEmojis: favoriteEmojis,
        packageEmojisByPackageID: [package.packageID: packageEmojis]
    )
}

private func makeEmojiAsset(
    emojiID: String,
    name: String,
    packageID: String? = "pkg_stub",
    isFavorite: Bool = false
) -> EmojiAssetRecord {
    EmojiAssetRecord(
        emojiID: emojiID,
        userID: "emoji_panel_user",
        packageID: packageID,
        emojiType: .package,
        name: name,
        md5: nil,
        localPath: nil,
        thumbPath: nil,
        cdnURL: nil,
        width: 128,
        height: 128,
        sizeBytes: 1024,
        useCount: 0,
        lastUsedAt: nil,
        isFavorite: isFavorite,
        isDeleted: false,
        extraJSON: nil,
        createdAt: 1,
        updatedAt: 1
    )
}

@MainActor
private func button(in view: UIView, identifier: String) -> UIButton? {
    if let button = view as? UIButton, button.accessibilityIdentifier == identifier {
        return button
    }

    for subview in view.subviews {
        if let button = button(in: subview, identifier: identifier) {
            return button
        }
    }

    return nil
}

@MainActor
private func button(in view: UIView, accessibilityLabel: String) -> UIButton? {
    if let button = view as? UIButton, button.accessibilityLabel == accessibilityLabel {
        return button
    }

    for subview in view.subviews {
        if let button = button(in: subview, accessibilityLabel: accessibilityLabel) {
            return button
        }
    }

    return nil
}

@MainActor
private func findView(in view: UIView, identifier: String) -> UIView? {
    if view.accessibilityIdentifier == identifier {
        return view
    }

    for subview in view.subviews {
        if let matchingView = findView(in: subview, identifier: identifier) {
            return matchingView
        }
    }

    return nil
}

@MainActor
private func findView<T: UIView>(ofType type: T.Type, in view: UIView) -> T? {
    if let matchingView = view as? T {
        return matchingView
    }

    for subview in view.subviews {
        if let matchingView = findView(ofType: type, in: subview) {
            return matchingView
        }
    }

    return nil
}

@MainActor
private func rgbaComponents(for color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return (red, green, blue, alpha)
}

@MainActor
private func findLabel(withText text: String, in view: UIView) -> UILabel? {
    if let label = view as? UILabel, label.text == text {
        return label
    }

    for subview in view.subviews {
        if let matchingLabel = findLabel(withText: text, in: subview) {
            return matchingLabel
        }
    }

    return nil
}

private extension UIAlertAction {
    func triggerForTesting() {
        typealias ActionHandler = @convention(block) (UIAlertAction) -> Void
        let handler = value(forKey: "handler") as? ActionHandler
        handler?(self)
    }
}

private actor CapturingLocalNotificationManager: LocalNotificationManaging {
    private var capturedPayloads: [IncomingMessageNotificationPayload] = []

    func requestAuthorization() async throws -> Bool {
        true
    }

    func scheduleIncomingMessageNotification(_ payload: IncomingMessageNotificationPayload) async throws {
        capturedPayloads.append(payload)
    }

    func payloads() -> [IncomingMessageNotificationPayload] {
        capturedPayloads
    }
}

private actor CapturingApplicationBadgeManager: ApplicationBadgeManaging {
    private var capturedValues: [Int] = []

    func setApplicationIconBadgeNumber(_ count: Int) async {
        capturedValues.append(count)
    }

    func values() -> [Int] {
        capturedValues
    }
}

private func collectRows(from stream: AsyncThrowingStream<ChatMessageRowState, Error>) async throws -> [ChatMessageRowState] {
    var rows: [ChatMessageRowState] = []

    for try await row in stream {
        rows.append(row)
    }

    return rows
}

private func requireTextContent(_ message: StoredMessage?) throws -> String {
    let message = try #require(message)
    guard case let .text(text) = message.content else {
        Issue.record("期望文本消息内容，实际为 \(message.content)")
        return ""
    }
    return text
}

private func requireTextualContent(_ message: StoredMessage?) throws -> String {
    let message = try #require(message)
    switch message.content {
    case let .text(text):
        return text
    case let .system(text), let .quote(text), let .revoked(text):
        return text ?? ""
    case .image, .voice, .video, .file, .emoji:
        Issue.record("期望可显示文本内容，实际为 \(message.content)")
        return ""
    }
}

private func requireImageContent(_ message: StoredMessage?) throws -> StoredImageContent {
    let message = try #require(message)
    guard case let .image(image) = message.content else {
        Issue.record("期望图片消息内容，实际为 \(message.content)")
        return StoredImageContent(mediaID: "", localPath: "", thumbnailPath: "", width: 0, height: 0, sizeBytes: 0, format: "")
    }
    return image
}

private func requireVoiceContent(_ message: StoredMessage?) throws -> StoredVoiceContent {
    let message = try #require(message)
    guard case let .voice(voice) = message.content else {
        Issue.record("期望语音消息内容，实际为 \(message.content)")
        return StoredVoiceContent(mediaID: "", localPath: "", durationMilliseconds: 0, sizeBytes: 0, format: "")
    }
    return voice
}

private func requireVideoContent(_ message: StoredMessage?) throws -> StoredVideoContent {
    let message = try #require(message)
    guard case let .video(video) = message.content else {
        Issue.record("期望视频消息内容，实际为 \(message.content)")
        return StoredVideoContent(mediaID: "", localPath: "", thumbnailPath: "", durationMilliseconds: 0, width: 0, height: 0, sizeBytes: 0)
    }
    return video
}

private func requireFileContent(_ message: StoredMessage?) throws -> StoredFileContent {
    let message = try #require(message)
    guard case let .file(file) = message.content else {
        Issue.record("期望文件消息内容，实际为 \(message.content)")
        return StoredFileContent(mediaID: "", localPath: "", fileName: "", fileExtension: nil, sizeBytes: 0)
    }
    return file
}

private func requireEmojiContent(_ message: StoredMessage?) throws -> StoredEmojiContent {
    let message = try #require(message)
    guard case let .emoji(emoji) = message.content else {
        Issue.record("期望表情消息内容，实际为 \(message.content)")
        return StoredEmojiContent(emojiID: "", packageID: nil, emojiType: .system, name: nil, localPath: nil, thumbPath: nil, cdnURL: nil, width: nil, height: nil, sizeBytes: nil)
    }
    return emoji
}

private func makeStoredTextMessage(
    messageID: MessageID = "local_message",
    conversationID: ConversationID = "local_conversation",
    senderID: UserID = "local_user",
    clientMessageID: String? = "local_client_message",
    text: String = "Hello",
    localTime: Int64 = 100
) -> StoredMessage {
    makeOutgoingStoredMessage(
        messageID: messageID,
        conversationID: conversationID,
        senderID: senderID,
        clientMessageID: clientMessageID,
        content: .text(text),
        localTime: localTime
    )
}

private func makeStoredImageMessage(
    messageID: MessageID = "local_image_message",
    conversationID: ConversationID = "local_conversation",
    senderID: UserID = "local_user",
    clientMessageID: String? = "local_image_client_message",
    localTime: Int64 = 100
) -> StoredMessage {
    makeOutgoingStoredMessage(
        messageID: messageID,
        conversationID: conversationID,
        senderID: senderID,
        clientMessageID: clientMessageID,
        content: .image(StoredImageContent(
            mediaID: "image_media",
            localPath: "media/image.png",
            thumbnailPath: "media/image_thumb.jpg",
            width: 320,
            height: 240,
            sizeBytes: 4_096,
            md5: "local-image-md5",
            format: "png"
        )),
        localTime: localTime
    )
}

private func makeStoredVoiceMessage(
    messageID: MessageID = "local_voice_message",
    conversationID: ConversationID = "local_conversation",
    senderID: UserID = "local_user",
    clientMessageID: String? = "local_voice_client_message",
    localTime: Int64 = 100
) -> StoredMessage {
    makeOutgoingStoredMessage(
        messageID: messageID,
        conversationID: conversationID,
        senderID: senderID,
        clientMessageID: clientMessageID,
        content: .voice(StoredVoiceContent(
            mediaID: "voice_media",
            localPath: "media/voice.m4a",
            durationMilliseconds: 1_800,
            sizeBytes: 2_048,
            format: "m4a"
        )),
        localTime: localTime
    )
}

private func makeStoredVideoMessage(
    messageID: MessageID = "local_video_message",
    conversationID: ConversationID = "local_conversation",
    senderID: UserID = "local_user",
    clientMessageID: String? = "local_video_client_message",
    localTime: Int64 = 100
) -> StoredMessage {
    makeOutgoingStoredMessage(
        messageID: messageID,
        conversationID: conversationID,
        senderID: senderID,
        clientMessageID: clientMessageID,
        content: .video(StoredVideoContent(
            mediaID: "video_media",
            localPath: "media/video.mov",
            thumbnailPath: "media/video_thumb.jpg",
            durationMilliseconds: 3_600,
            width: 640,
            height: 360,
            sizeBytes: 8_192,
            md5: "local-video-md5"
        )),
        localTime: localTime
    )
}

private func makeStoredFileMessage(
    messageID: MessageID = "local_file_message",
    conversationID: ConversationID = "local_conversation",
    senderID: UserID = "local_user",
    clientMessageID: String? = "local_file_client_message",
    localTime: Int64 = 100
) -> StoredMessage {
    makeOutgoingStoredMessage(
        messageID: messageID,
        conversationID: conversationID,
        senderID: senderID,
        clientMessageID: clientMessageID,
        content: .file(StoredFileContent(
            mediaID: "file_media",
            localPath: "media/report.pdf",
            fileName: "report.pdf",
            fileExtension: "pdf",
            sizeBytes: 16_384,
            md5: "local-file-md5"
        )),
        localTime: localTime
    )
}

private func makeOutgoingStoredMessage(
    messageID: MessageID,
    conversationID: ConversationID,
    senderID: UserID,
    clientMessageID: String?,
    content: StoredMessageContent,
    localTime: Int64
) -> StoredMessage {
    StoredMessage(
        id: messageID,
        conversationID: conversationID,
        senderID: senderID,
        delivery: StoredMessageDelivery(
            clientMessageID: clientMessageID,
            serverMessageID: nil,
            sequence: nil
        ),
        state: StoredMessageState(
            direction: .outgoing,
            sendStatus: .sending,
            readStatus: .read,
            isRevoked: false,
            isDeleted: false,
            revokeReplacementText: nil
        ),
        timeline: StoredMessageTimeline(
            serverTime: nil,
            sortSequence: localTime,
            localTime: localTime
        ),
        content: content
    )
}

private actor RecordingHTTPClient: ChatBridgeHTTPPosting {
    private let response: ServerTextMessageSendResponse?
    private let tokenRefreshResponse: ServerTokenRefreshResponse?
    private let error: ChatBridgeHTTPError?
    private let delayNanoseconds: UInt64
    private(set) var lastTextRequest: ServerTextMessageSendRequest?
    private(set) var lastImageRequest: ServerImageMessageSendRequest?
    private(set) var lastVoiceRequest: ServerVoiceMessageSendRequest?
    private(set) var lastVideoRequest: ServerVideoMessageSendRequest?
    private(set) var lastFileRequest: ServerFileMessageSendRequest?
    private(set) var lastTokenRefreshRequest: ServerTokenRefreshRequest?
    private(set) var tokenRefreshCallCount = 0

    init(
        response: ServerTextMessageSendResponse? = nil,
        tokenRefreshResponse: ServerTokenRefreshResponse? = nil,
        error: ChatBridgeHTTPError? = nil,
        delayNanoseconds: UInt64 = 0
    ) {
        self.response = response
        self.tokenRefreshResponse = tokenRefreshResponse
        self.error = error
        self.delayNanoseconds = delayNanoseconds
    }

    func postJSON<Request, Response>(
        path: String,
        body: Request,
        responseType: Response.Type
    ) async throws -> Response where Request: Encodable & Sendable, Response: Decodable & Sendable {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        if let textRequest = body as? ServerTextMessageSendRequest {
            lastTextRequest = textRequest
        }

        if let imageRequest = body as? ServerImageMessageSendRequest {
            lastImageRequest = imageRequest
        }

        if let voiceRequest = body as? ServerVoiceMessageSendRequest {
            lastVoiceRequest = voiceRequest
        }

        if let videoRequest = body as? ServerVideoMessageSendRequest {
            lastVideoRequest = videoRequest
        }

        if let fileRequest = body as? ServerFileMessageSendRequest {
            lastFileRequest = fileRequest
        }

        if let tokenRefreshRequest = body as? ServerTokenRefreshRequest {
            lastTokenRefreshRequest = tokenRefreshRequest
            tokenRefreshCallCount += 1
        }

        if let error {
            throw error
        }

        if let response = response as? Response {
            return response
        }

        if let tokenRefreshResponse = tokenRefreshResponse as? Response {
            return tokenRefreshResponse
        }

        guard let response = response as? Response else {
            throw ChatBridgeHTTPError.ackMissing
        }

        return response
    }
}

private actor ExpiringTextHTTPClient: ChatBridgeHTTPPosting {
    private let tokenProvider: (@Sendable () async -> String?)?
    private let response: ServerTextMessageSendResponse?
    private let error: ChatBridgeHTTPError?
    private(set) var textSendCallCount = 0
    private(set) var mediaSendCallCount = 0
    private(set) var observedTokens: [String?] = []

    init(
        tokenProvider: (@Sendable () async -> String?)? = nil,
        response: ServerTextMessageSendResponse? = nil,
        error: ChatBridgeHTTPError? = nil
    ) {
        self.tokenProvider = tokenProvider
        self.response = response
        self.error = error
    }

    func postJSON<Request, Response>(
        path: String,
        body: Request,
        responseType: Response.Type
    ) async throws -> Response where Request: Encodable & Sendable, Response: Decodable & Sendable {
        if body is ServerTextMessageSendRequest {
            textSendCallCount += 1
            if let tokenProvider {
                observedTokens.append(await tokenProvider())
            }
        }

        if body is ServerImageMessageSendRequest
            || body is ServerVoiceMessageSendRequest
            || body is ServerVideoMessageSendRequest
            || body is ServerFileMessageSendRequest {
            mediaSendCallCount += 1
            if let tokenProvider {
                observedTokens.append(await tokenProvider())
            }
        }

        if let error {
            throw error
        }

        if textSendCallCount + mediaSendCallCount == 1 {
            throw ChatBridgeHTTPError.unacceptableStatus(401)
        }

        guard let response = response as? Response else {
            throw ChatBridgeHTTPError.ackMissing
        }

        return response
    }
}

private actor TokenBox {
    private(set) var token: String

    init(token: String) {
        self.token = token
    }

    func updateToken(_ token: String) {
        self.token = token
    }
}

private actor Counter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private final class InMemoryAccountSessionStore: AccountSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AccountSession?

    init(session: AccountSession? = nil) {
        self.session = session
    }

    nonisolated func loadSession() -> AccountSession? {
        lock.lock()
        defer { lock.unlock() }
        return session
    }

    nonisolated func saveSession(_ session: AccountSession) throws {
        lock.lock()
        defer { lock.unlock() }
        self.session = session
    }

    nonisolated func clearSession() {
        lock.lock()
        defer { lock.unlock() }
        session = nil
    }
}
