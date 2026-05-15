import Testing
import Foundation
import UIKit

@testable import AppleIM

extension AppleIMTests {
    @Test func temporaryMediaFileManagerCreatesAndRemovesTemporaryFile() {
        let manager = DefaultTemporaryMediaFileManager()
        let url = manager.makeTemporaryFileURL(prefix: "ChatBridgeTestVideoPick", fileExtension: "mov")
        defer {
            manager.removeFileIfExists(at: url)
        }

        #expect(manager.fileExists(at: url) == false)
        #expect(manager.createEmptyFile(at: url) == true)
        #expect(manager.fileExists(at: url) == true)

        manager.removeFileIfExists(at: url)
        #expect(manager.fileExists(at: url) == false)
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
        let recorder = ChatInputBarActionRecorder()
        inputBar.addTarget(recorder, action: #selector(ChatInputBarActionRecorder.record(_:)), for: .primaryActionTriggered)

        inputBar.setPendingVoicePreview(durationMilliseconds: 4_200, isPlaying: false, animated: false)
        button(in: inputBar, identifier: "chat.voicePreviewSendButton")?.sendActions(for: .touchUpInside)

        #expect(recorder.actions == [.voicePreviewSend])
    }

    @MainActor
    @Test func chatInputBarNotifiesHeightChangeWhenTransientStatusAppears() {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))
        let delegate = ChatInputBarLayoutDelegateRecorder(shouldStickToBottom: true)
        inputBar.layoutDelegate = delegate

        inputBar.showTransientStatus("Voice too short")
        inputBar.layoutIfNeeded()

        #expect(delegate.willChangeCount == 1)
        #expect(delegate.didChangeValues == [true])
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
        let recorder = ChatInputBarActionRecorder()
        inputBar.addTarget(recorder, action: #selector(ChatInputBarActionRecorder.record(_:)), for: .primaryActionTriggered)

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

        #expect(recorder.actions == [.attachmentRemoved("photo-1")])
        #expect(findView(in: inputBar, identifier: "chat.pendingAttachmentPreviewItem.photo-1") == nil)
        #expect(findView(in: inputBar, identifier: "chat.pendingAttachmentPreviewItem.photo-2") != nil)
        #expect(button(in: inputBar, identifier: "chat.sendButton")?.isEnabled == true)

        button(in: inputBar, identifier: "chat.removeAttachmentButton.photo-2")?.sendActions(for: .touchUpInside)

        #expect(recorder.actions == [.attachmentRemoved("photo-1"), .attachmentRemoved("photo-2")])
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
        let profileCell = try #require(collectionView.cellForItem(at: IndexPath(row: 0, section: 0)))
        #expect(profileCell.contentConfiguration is AccountProfileContentConfiguration)
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
        let recorder = ChatInputBarActionRecorder()
        inputBar.addTarget(recorder, action: #selector(ChatInputBarActionRecorder.record(_:)), for: .primaryActionTriggered)

        inputBar.showPhotoLibraryInput()

        #expect(inputBar.textViewShouldBeginEditing(textView) == false)
        #expect(recorder.actions == [.keyboardInputRequested])
        #expect(inputBar.textViewShouldBeginEditing(textView) == false)
        #expect(recorder.actions == [.keyboardInputRequested])

        inputBar.showKeyboardInput()

        #expect(inputBar.textViewShouldBeginEditing(textView) == true)
    }

    @MainActor
    @Test func chatInputBarDefersSystemKeyboardWhileLeavingEmojiInput() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))
        let textView = try #require(findView(ofType: UITextView.self, in: inputBar))
        let recorder = ChatInputBarActionRecorder()
        inputBar.addTarget(recorder, action: #selector(ChatInputBarActionRecorder.record(_:)), for: .primaryActionTriggered)

        inputBar.showEmojiInput()

        #expect(inputBar.textViewShouldBeginEditing(textView) == false)
        #expect(recorder.actions == [.keyboardInputRequested])
        #expect(inputBar.textViewShouldBeginEditing(textView) == false)
        #expect(recorder.actions == [.keyboardInputRequested])

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
    @Test func chatEmojiPanelPublishesControlActionsForSelectionAndFavoriteToggle() throws {
        let panelView = ChatEmojiPanelView(frame: CGRect(x: 0, y: 0, width: 390, height: 280))
        let recorder = ChatEmojiPanelActionRecorder()
        panelView.addTarget(recorder, action: #selector(ChatEmojiPanelActionRecorder.record(_:)), for: .primaryActionTriggered)
        let state = makeEmojiPanelState(
            recentEmojis: [makeEmojiAsset(emojiID: "recent_stub", name: "Recent Stub")],
            favoriteEmojis: [],
            packageEmojis: []
        )

        panelView.render(state)
        button(in: panelView, identifier: "chat.emojiItem.recent_stub")?.sendActions(for: .touchUpInside)
        button(in: panelView, identifier: "chat.emojiFavorite.recent_stub")?.sendActions(for: .touchUpInside)

        #expect(recorder.actions.map(\.emojiID) == ["recent_stub", "recent_stub"])
        #expect(recorder.actions.map(\.kind) == [.selected, .favoriteToggled])
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
    @Test func chatPhotoLibraryInputUsesDelegateForDismissPanReset() throws {
        let photoPanel = ChatPhotoLibraryInputView(frame: CGRect(x: 0, y: 0, width: 390, height: 342))
        let delegate = ChatPhotoLibraryInputDelegateRecorder()
        photoPanel.inputDelegate = delegate

        photoPanel.resetDismissGestureState()

        #expect(delegate.dismissPanTranslations == [0])
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
    @Test func chatDesignSystemExposesWeChatMessageBubbleTokens() {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let outgoing = ChatBridgeDesignSystem.ColorToken.weChatOutgoingMessage.resolvedColor(with: traits)
        let incoming = ChatBridgeDesignSystem.ColorToken.weChatIncomingMessage.resolvedColor(with: traits)

        #expect(outgoing == UIColor.chatBridgeHex(0x95EC69).resolvedColor(with: traits))
        #expect(incoming == UIColor.white.resolvedColor(with: traits))
        #expect(ChatBridgeDesignSystem.RadiusToken.weChatMessageBubble == 6)
        #expect(ChatBridgeDesignSystem.RadiusToken.appleMessageMedia == 20)
        #expect(ChatBridgeDesignSystem.RadiusToken.appleComposerAttachment == 16)
    }

    @MainActor
    @Test func chatMessageCellAppliesWeChatTextBubbleStyle() throws {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let outgoingCell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        outgoingCell.configure(
            row: makeChatRow(id: "wechat_green_bubble", text: "微信绿色发送气泡", sortSequence: 1, isOutgoing: true),
            actions: .empty
        )

        let incomingCell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        incomingCell.configure(
            row: makeChatRow(id: "wechat_white_bubble", text: "微信白色接收气泡", sortSequence: 2, isOutgoing: false),
            actions: .empty
        )

        let outgoingLabel = try #require(findLabel(withText: "微信绿色发送气泡", in: outgoingCell))
        let incomingLabel = try #require(findLabel(withText: "微信白色接收气泡", in: incomingCell))
        let outgoingBubble = try #require(findView(ofType: ChatBubbleBackgroundView.self, in: outgoingCell))
        let incomingBubble = try #require(findView(ofType: ChatBubbleBackgroundView.self, in: incomingCell))

        #expect(outgoingBubble.style == .weChatOutgoing)
        #expect(incomingBubble.style == .weChatIncoming)
        #expect(solidFillColor(of: outgoingBubble, traits: traits) == UIColor.chatBridgeHex(0x95EC69).resolvedColor(with: traits))
        #expect(solidFillColor(of: incomingBubble, traits: traits) == UIColor.white.resolvedColor(with: traits))
        #expect(outgoingLabel.textColor.resolvedColor(with: traits) == UIColor.label.resolvedColor(with: traits))
        #expect(incomingLabel.textColor.resolvedColor(with: traits) == UIColor.label.resolvedColor(with: traits))
    }

    @MainActor
    @Test func chatMessageCellAppliesWeChatVoiceBubbleFrame() throws {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let outgoingCell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        outgoingCell.configure(
            row: ChatMessageRowState(
                id: "wechat_outgoing_voice",
                content: .voice(
                    ChatMessageRowContent.VoiceContent(
                        localPath: "/tmp/wechat_outgoing_voice.m4a",
                        durationMilliseconds: 2_000,
                        isUnplayed: false,
                        isPlaying: false
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
            ),
            actions: .empty
        )

        let incomingCell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        incomingCell.configure(
            row: makeVoiceRow(id: "wechat_incoming_voice", sortSequence: 2, isUnplayed: false),
            actions: .empty
        )

        let outgoingBubble = try #require(findView(ofType: ChatBubbleBackgroundView.self, in: outgoingCell))
        let incomingBubble = try #require(findView(ofType: ChatBubbleBackgroundView.self, in: incomingCell))
        let outgoingButton = try #require(button(in: outgoingCell, accessibilityLabel: "Play Voice"))
        let outgoingDuration = try #require(findLabel(withText: "0:02", in: outgoingCell))

        #expect(outgoingBubble.style == .weChatOutgoing)
        #expect(incomingBubble.style == .weChatIncoming)
        #expect(solidFillColor(of: outgoingBubble, traits: traits) == UIColor.chatBridgeHex(0x95EC69).resolvedColor(with: traits))
        #expect(solidFillColor(of: incomingBubble, traits: traits) == UIColor.white.resolvedColor(with: traits))
        #expect(outgoingButton.tintColor.resolvedColor(with: traits) == UIColor.label.resolvedColor(with: traits))
        #expect(outgoingDuration.textColor.resolvedColor(with: traits) == UIColor.label.resolvedColor(with: traits))
    }

    @MainActor
    @Test func chatMessageCellRendersEmojiWithoutBubbleFrame() throws {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let outgoingCell = fittedChatMessageCell(
            row: makeEmojiMessageRow(id: "outgoing_plain_emoji", isOutgoing: true),
            width: 390
        )
        let incomingCell = fittedChatMessageCell(
            row: makeEmojiMessageRow(id: "incoming_plain_emoji", isOutgoing: false),
            width: 390
        )

        let outgoingBubble = try #require(findView(ofType: ChatBubbleBackgroundView.self, in: outgoingCell))
        let incomingBubble = try #require(findView(ofType: ChatBubbleBackgroundView.self, in: incomingCell))
        let outgoingEmojiView = try #require(findView(ofType: EmojiMessageContentView.self, in: outgoingCell))
        let incomingEmojiView = try #require(findView(ofType: EmojiMessageContentView.self, in: incomingCell))

        #expect(outgoingBubble.style == .plain)
        #expect(incomingBubble.style == .plain)
        #expect(solidFillColor(of: outgoingBubble, traits: traits) == UIColor.clear.resolvedColor(with: traits))
        #expect(solidFillColor(of: incomingBubble, traits: traits) == UIColor.clear.resolvedColor(with: traits))

        let outgoingBubbleFrame = outgoingBubble.convert(outgoingBubble.bounds, to: outgoingCell.contentView)
        let incomingBubbleFrame = incomingBubble.convert(incomingBubble.bounds, to: incomingCell.contentView)
        let outgoingEmojiFrame = outgoingEmojiView.convert(outgoingEmojiView.bounds, to: outgoingCell.contentView)
        let incomingEmojiFrame = incomingEmojiView.convert(incomingEmojiView.bounds, to: incomingCell.contentView)

        #expect(abs(outgoingBubbleFrame.minX - outgoingEmojiFrame.minX) < 1)
        #expect(abs(outgoingBubbleFrame.minY - outgoingEmojiFrame.minY) < 1)
        #expect(abs(outgoingBubbleFrame.maxX - outgoingEmojiFrame.maxX) < 1)
        #expect(abs(outgoingBubbleFrame.maxY - outgoingEmojiFrame.maxY) < 1)
        #expect(abs(incomingBubbleFrame.minX - incomingEmojiFrame.minX) < 1)
        #expect(abs(incomingBubbleFrame.minY - incomingEmojiFrame.minY) < 1)
        #expect(abs(incomingBubbleFrame.maxX - incomingEmojiFrame.maxX) < 1)
        #expect(abs(incomingBubbleFrame.maxY - incomingEmojiFrame.maxY) < 1)
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
    @Test func chatBubbleTailUsesContinuousMaskPath() throws {
        let bounds = CGRect(x: 0, y: 0, width: 128, height: 46)

        #expect(moveElementCount(in: ChatBubbleBackgroundView.maskPath(in: bounds, style: .outgoing)) == 1)
        #expect(moveElementCount(in: ChatBubbleBackgroundView.maskPath(in: bounds, style: .incoming)) == 1)

        let tallBounds = CGRect(x: 0, y: 0, width: 180, height: 120)
        let tallOutgoingPath = ChatBubbleBackgroundView.maskPath(in: tallBounds, style: .weChatOutgoing)
        let tallIncomingPath = ChatBubbleBackgroundView.maskPath(in: tallBounds, style: .weChatIncoming)
        let tallOutgoingTailY = try #require(tailTipY(in: tallOutgoingPath, edgeX: tallBounds.maxX))
        let tallIncomingTailY = try #require(tailTipY(in: tallIncomingPath, edgeX: tallBounds.minX))

        #expect(abs(tallOutgoingTailY - 20) < 0.5)
        #expect(abs(tallIncomingTailY - 20) < 0.5)
        #expect(abs(tallOutgoingTailY - tallBounds.midY) > 20)
        #expect(abs(tallIncomingTailY - tallBounds.midY) > 20)

        let singleLineBounds = CGRect(x: 0, y: 0, width: 128, height: 40)
        let singleLineOutgoingPath = ChatBubbleBackgroundView.maskPath(in: singleLineBounds, style: .weChatOutgoing)
        let singleLineIncomingPath = ChatBubbleBackgroundView.maskPath(in: singleLineBounds, style: .weChatIncoming)
        let singleLineOutgoingTailY = try #require(tailTipY(in: singleLineOutgoingPath, edgeX: singleLineBounds.maxX))
        let singleLineIncomingTailY = try #require(tailTipY(in: singleLineIncomingPath, edgeX: singleLineBounds.minX))

        #expect(abs(singleLineOutgoingTailY - singleLineBounds.midY) < 0.5)
        #expect(abs(singleLineIncomingTailY - singleLineBounds.midY) < 0.5)
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
                onReeditRevokedText: { _, _ in },
                onPlayVoice: { _ in },
                onPlayVideo: { playedRow = $0 }
            )
        )

        #expect(mediaView.accessibilityActivate())
        #expect(playedRow?.id == "video_tap")
    }

    @MainActor
    @Test func voiceMessageContentViewPlaysVoiceFromBubbleActivation() throws {
        let row = makeVoiceRow(id: "voice_bubble_tap", sortSequence: 1, isUnplayed: true)
        var playedRow: ChatMessageRowState?
        let voiceView = VoiceMessageContentView()

        voiceView.configure(
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
                onReeditRevokedText: { _, _ in },
                onPlayVoice: { playedRow = $0 },
                onPlayVideo: { _ in }
            )
        )

        #expect(voiceView.gestureRecognizers?.contains { $0 is UITapGestureRecognizer } == true)
        #expect(button(in: voiceView, accessibilityLabel: "Play Voice") != nil)
        #expect(voiceView.accessibilityActivate())
        #expect(playedRow?.id == "voice_bubble_tap")
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

        let multilineCell = fittedChatMessageCell(
            row: makeChatRow(
                id: "outgoing_tail_avatar_center",
                text: "多行文本气泡\n尾巴应该对齐头像中点\n而不是对齐整块气泡中点",
                sortSequence: 2,
                isOutgoing: true
            ),
            width: 390
        )
        try assertTailAlignsWithAvatarCenter(in: multilineCell, edge: .trailing)
    }

    @MainActor
    @Test func chatMessageCellMatchesAvatarHeightToSingleLineTextBubble() throws {
        let row = ChatMessageRowState(
            id: "avatar_text_height",
            content: .text("一行文字"),
            sortSequence: 1,
            timeText: "Now",
            showsTimeSeparator: false,
            statusText: nil,
            uploadProgress: nil,
            senderAvatarURL: "file:///tmp/current-avatar.png",
            isOutgoing: true,
            canRetry: false,
            canDelete: true,
            canRevoke: false
        )
        let cell = fittedChatMessageCell(row: row, width: 390)

        let avatarView = try #require(findView(ofType: GradientBackgroundView.self, in: cell))
        let bubbleView = try #require(findView(ofType: ChatBubbleBackgroundView.self, in: cell))
        let avatarFrame = avatarView.convert(avatarView.bounds, to: cell.contentView)
        let bubbleFrame = bubbleView.convert(bubbleView.bounds, to: cell.contentView)

        #expect(avatarView.isHidden == false)
        #expect(abs(avatarFrame.height - bubbleFrame.height) <= 1)
    }

    @MainActor
    @Test func chatMessageCellMatchesSingleLineTextAndVoiceBubbleHeights() throws {
        let textRow = ChatMessageRowState(
            id: "single_line_text_height",
            content: .text("一行文字"),
            sortSequence: 1,
            timeText: "Now",
            showsTimeSeparator: false,
            statusText: nil,
            uploadProgress: nil,
            isOutgoing: true,
            canRetry: false,
            canDelete: true,
            canRevoke: false
        )
        let voiceRow = ChatMessageRowState(
            id: "single_line_voice_height",
            content: .voice(
                ChatMessageRowContent.VoiceContent(
                    localPath: "/tmp/single_line_voice_height.m4a",
                    durationMilliseconds: 2_000,
                    isUnplayed: false,
                    isPlaying: false
                )
            ),
            sortSequence: 2,
            timeText: "Now",
            showsTimeSeparator: false,
            statusText: nil,
            uploadProgress: nil,
            isOutgoing: true,
            canRetry: false,
            canDelete: true,
            canRevoke: false
        )

        let textCell = fittedChatMessageCell(row: textRow, width: 390)
        let voiceCell = fittedChatMessageCell(row: voiceRow, width: 390)
        let textBubbleView = try #require(findView(ofType: ChatBubbleBackgroundView.self, in: textCell))
        let voiceBubbleView = try #require(findView(ofType: ChatBubbleBackgroundView.self, in: voiceCell))
        let textBubbleFrame = textBubbleView.convert(textBubbleView.bounds, to: textCell.contentView)
        let voiceBubbleFrame = voiceBubbleView.convert(voiceBubbleView.bounds, to: voiceCell.contentView)

        #expect(abs(textBubbleFrame.height - voiceBubbleFrame.height) <= 1)
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

        let multilineCell = fittedChatMessageCell(
            row: makeChatRow(
                id: "incoming_tail_avatar_center",
                text: "多行文本气泡\n尾巴应该对齐头像中点\n而不是对齐整块气泡中点",
                sortSequence: 1,
                isOutgoing: false
            ),
            width: 390
        )
        try assertTailAlignsWithAvatarCenter(in: multilineCell, edge: .leading)
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
    @Test func chatMessageCellCentersRevokedMessageAndShowsReeditButton() throws {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        var reeditRequest: (MessageID, String)?
        let row = ChatMessageRowState(
            id: "revoked_reedit",
            content: .revoked(
                ChatMessageRowContent.RevokedContent(
                    noticeText: "你撤回了一条消息",
                    editableText: "原始文本",
                    allowsReedit: true
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

        cell.configure(
            row: row,
            actions: ChatMessageCellActions(
                onRetry: { _ in },
                onDelete: { _ in },
                onRevoke: { _ in },
                onReeditRevokedText: { reeditRequest = ($0, $1) },
                onPlayVoice: { _ in },
                onPlayVideo: { _ in }
            )
        )
        cell.setNeedsLayout()
        cell.layoutIfNeeded()

        let bubbleView = try #require(findView(ofType: ChatBubbleBackgroundView.self, in: cell))
        let reeditButton = try #require(button(in: cell, identifier: "chat.revokedReeditButton.revoked_reedit"))
        let bubbleFrame = bubbleView.convert(bubbleView.bounds, to: cell.contentView)

        #expect(abs(bubbleFrame.midX - cell.contentView.bounds.midX) < 1)
        #expect(findLabel(withText: "你撤回了一条消息", in: cell) != nil)
        #expect(reeditButton.title(for: .normal) == "重新编辑")

        reeditButton.sendActions(for: .touchUpInside)
        #expect(reeditRequest?.0 == "revoked_reedit")
        #expect(reeditRequest?.1 == "原始文本")
    }

    @MainActor
    @Test func chatMessageCellHidesReeditButtonWhenRevokedMessageIsNotEditable() throws {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 120))

        cell.configure(row: makeRevokedRow(id: "revoked_notice_only", sortSequence: 1), actions: .empty)
        cell.setNeedsLayout()
        cell.layoutIfNeeded()

        #expect(button(in: cell, identifier: "chat.revokedReeditButton.revoked_notice_only") == nil)
    }

    @MainActor
    @Test func chatMessageCellShowsContextMenuForRevocableNonTextMessage() throws {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        let row = ChatMessageRowState(
            id: "revocable_image",
            content: .image(
                ChatMessageRowContent.ImageContent(
                    thumbnailPath: "/tmp/revocable_image.png"
                )
            ),
            sortSequence: 1,
            timeText: "Now",
            statusText: nil,
            uploadProgress: nil,
            isOutgoing: true,
            canRetry: false,
            canDelete: false,
            canRevoke: true
        )

        cell.configure(row: row, actions: .empty)
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        let contentView = try #require(findView(ofType: ChatMessageCellContentView.self, in: cell))
        let menuConfiguration = contentView.contextMenuInteraction(
            UIContextMenuInteraction(delegate: contentView),
            configurationForMenuAtLocation: .zero
        )

        #expect(menuConfiguration != nil)
    }

    @MainActor
    @Test func chatMessageCellDoesNotShowContextMenuForNonRevocableNonTextMessage() throws {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        let row = ChatMessageRowState(
            id: "stale_image",
            content: .image(
                ChatMessageRowContent.ImageContent(
                    thumbnailPath: "/tmp/stale_image.png"
                )
            ),
            sortSequence: 1,
            timeText: "Now",
            statusText: nil,
            uploadProgress: nil,
            isOutgoing: true,
            canRetry: false,
            canDelete: false,
            canRevoke: false
        )

        cell.configure(row: row, actions: .empty)
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        let contentView = try #require(findView(ofType: ChatMessageCellContentView.self, in: cell))
        let menuConfiguration = contentView.contextMenuInteraction(
            UIContextMenuInteraction(delegate: contentView),
            configurationForMenuAtLocation: .zero
        )

        #expect(menuConfiguration == nil)
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

@MainActor
private func fittedChatMessageCell(row: ChatMessageRowState, width: CGFloat) -> ChatMessageCell {
    let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: width, height: 120))
    cell.configure(row: row, actions: .empty)

    let fittingSize = cell.systemLayoutSizeFitting(
        CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
        withHorizontalFittingPriority: .required,
        verticalFittingPriority: .fittingSizeLevel
    )
    cell.frame = CGRect(x: 0, y: 0, width: width, height: fittingSize.height)
    cell.setNeedsLayout()
    cell.layoutIfNeeded()
    return cell
}

private enum BubbleTailEdge {
    case leading
    case trailing
}

@MainActor
private func assertTailAlignsWithAvatarCenter(in cell: ChatMessageCell, edge: BubbleTailEdge) throws {
    let avatarView = try #require(findView(ofType: GradientBackgroundView.self, in: cell))
    let bubbleView = try #require(findView(ofType: ChatBubbleBackgroundView.self, in: cell))
    let avatarFrame = avatarView.convert(avatarView.bounds, to: cell.contentView)
    let bubbleFrame = bubbleView.convert(bubbleView.bounds, to: cell.contentView)
    let tailEdgeX = edge == .leading ? bubbleView.bounds.minX : bubbleView.bounds.maxX
    let tailYInBubble = try #require(tailTipY(in: ChatBubbleBackgroundView.maskPath(in: bubbleView.bounds, style: bubbleView.style), edgeX: tailEdgeX))
    let tailYInCell = bubbleFrame.minY + tailYInBubble

    #expect(abs(tailYInCell - avatarFrame.midY) < 1)
}

private func tailTipY(in path: UIBezierPath, edgeX: CGFloat) -> CGFloat? {
    var candidateY: CGFloat?
    path.cgPath.applyWithBlock { elementPointer in
        let element = elementPointer.pointee
        let pointCount: Int
        switch element.type {
        case .moveToPoint, .addLineToPoint:
            pointCount = 1
        case .addQuadCurveToPoint:
            pointCount = 2
        case .addCurveToPoint:
            pointCount = 3
        case .closeSubpath:
            pointCount = 0
        @unknown default:
            pointCount = 0
        }

        for index in 0..<pointCount {
            let point = element.points[index]
            if abs(point.x - edgeX) < 0.5 {
                candidateY = point.y
            }
        }
    }
    return candidateY
}

private func makeEmojiMessageRow(id: MessageID, isOutgoing: Bool) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .emoji(
            ChatMessageRowContent.EmojiContent(
                emojiID: id.rawValue,
                name: "表情消息",
                localPath: nil,
                thumbPath: nil,
                cdnURL: nil
            )
        ),
        sortSequence: 1,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: isOutgoing,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}

@MainActor
private func solidFillColor(
    of bubbleView: ChatBubbleBackgroundView,
    traits: UITraitCollection
) -> UIColor? {
    guard
        let gradientLayer = bubbleView.layer as? CAGradientLayer,
        let firstObject = gradientLayer.colors?.first
    else {
        return nil
    }

    let firstColor = firstObject as! CGColor
    return UIColor(cgColor: firstColor).resolvedColor(with: traits)
}

@MainActor
private final class ChatInputBarActionRecorder: NSObject {
    private(set) var actions: [ChatInputBarAction] = []

    @objc func record(_ sender: ChatInputBarView) {
        guard let action = sender.lastAction else { return }
        actions.append(action)
    }
}

@MainActor
private final class ChatInputBarLayoutDelegateRecorder: ChatInputBarLayoutDelegate {
    private let shouldStickToBottom: Bool
    private(set) var willChangeCount = 0
    private(set) var didChangeValues: [Bool] = []

    init(shouldStickToBottom: Bool) {
        self.shouldStickToBottom = shouldStickToBottom
    }

    func chatInputBarWillChangeHeight(_ inputBar: ChatInputBarView) -> Bool {
        willChangeCount += 1
        return shouldStickToBottom
    }

    func chatInputBar(_ inputBar: ChatInputBarView, didChangeHeightKeepingBottom shouldStickToBottom: Bool) {
        didChangeValues.append(shouldStickToBottom)
    }
}

@MainActor
private final class ChatEmojiPanelActionRecorder: NSObject {
    private(set) var actions: [ChatEmojiPanelAction] = []

    @objc func record(_ sender: ChatEmojiPanelView) {
        guard let action = sender.lastAction else { return }
        actions.append(action)
    }
}

@MainActor
private final class ChatPhotoLibraryInputDelegateRecorder: ChatPhotoLibraryInputViewDelegate {
    private(set) var dismissPanTranslations: [CGFloat] = []

    func chatPhotoLibraryInputView(_ inputView: ChatPhotoLibraryInputView, didChangeDismissPanTranslation translationY: CGFloat) {
        dismissPanTranslations.append(translationY)
    }

    func chatPhotoLibraryInputViewDidRequestDismiss(_ inputView: ChatPhotoLibraryInputView) {}

    func chatPhotoLibraryInputView(_ inputView: ChatPhotoLibraryInputView, didStartSelection preview: ChatPhotoLibrarySelectionPreview) {}

    func chatPhotoLibraryInputView(_ inputView: ChatPhotoLibraryInputView, didPrepareSelection preparedMedia: ChatPhotoLibraryPreparedMedia) {}

    func chatPhotoLibraryInputView(_ inputView: ChatPhotoLibraryInputView, didRemoveSelection id: String) {}

    func chatPhotoLibraryInputView(_ inputView: ChatPhotoLibraryInputView, didFailSelection id: String, message: String) {}

    func chatPhotoLibraryInputView(_ inputView: ChatPhotoLibraryInputView, didReachSelectionLimit message: String) {}
}
