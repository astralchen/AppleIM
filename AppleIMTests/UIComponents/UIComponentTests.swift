import Testing
import Foundation
import UIKit

@testable import AppleIM

extension AppleIMTests {
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
