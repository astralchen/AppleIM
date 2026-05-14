import Testing
import Foundation
import UIKit

@testable import AppleIM

extension AppleIMTests {
    @MainActor
    @Test func chatViewControllerUsesInlineNavigationTitle() throws {
        let viewModel = ChatViewModel(useCase: SimulatedIncomingStubChatUseCase(), title: "Sondra")
        let viewController = ChatViewController(viewModel: viewModel)

        viewController.loadViewIfNeeded()

        #expect(viewController.navigationItem.largeTitleDisplayMode == .never)
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
}
