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
    @Test func chatInputBarVoiceButtonTapPublishesRecordAction() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))
        let recorder = ChatInputBarActionRecorder()
        inputBar.onAction = { action in
            recorder.record(action)
        }
        inputBar.layoutIfNeeded()

        button(in: inputBar, identifier: "chat.voiceButton")?.sendActions(for: .touchUpInside)

        #expect(recorder.actions == [.voiceRecordTapped])
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

        let recordingCapsule = try #require(findView(in: inputBar, identifier: "chat.recordingCapsule"))
        let waveformView = try #require(findView(in: inputBar, identifier: "chat.recordingWaveform"))
        let stopButton = try #require(button(in: inputBar, identifier: "chat.voiceStopButton"))
        let recordingContainer = try #require(recordingCapsule.superview)
        let capsuleFrame = recordingCapsule.convert(recordingCapsule.bounds, to: inputBar)
        let waveformFrame = waveformView.convert(waveformView.bounds, to: inputBar)
        let stopButtonFrame = stopButton.convert(stopButton.bounds, to: inputBar)

        #expect(capsuleFrame.height >= 60)
        #expect(abs(recordingContainer.layer.cornerRadius - recordingContainer.bounds.height / 2) <= 0.5)
        #expect(waveformFrame.width > 180)
        #expect(abs(stopButtonFrame.width - 52) < 0.5)
        #expect(abs(stopButtonFrame.height - 52) < 0.5)
        #expect(capsuleFrame.insetBy(dx: -0.5, dy: -0.5).contains(stopButtonFrame))
        #expect(stopButton.isEnabled == true)
        #expect(findView(in: inputBar, identifier: "chat.recordingMicIcon") == nil)
        #expect(button(in: inputBar, identifier: "chat.sendButton") == nil)
        #expect(button(in: inputBar, identifier: "chat.voiceButton") == nil)

        inputBar.renderVoiceRecordingState(
            VoiceRecordingState(
                isRecording: true,
                isCanceling: false,
                elapsedMilliseconds: 5_200,
                averagePowerLevel: 0.18,
                hintText: "Release to preview"
            )
        )
        inputBar.renderVoiceRecordingState(
            VoiceRecordingState(
                isRecording: true,
                isCanceling: false,
                elapsedMilliseconds: 5_300,
                averagePowerLevel: 0.72,
                hintText: "Release to preview"
            )
        )
        inputBar.layoutIfNeeded()

        let refreshedWaveformFrame = waveformView.convert(waveformView.bounds, to: inputBar)
        #expect(refreshedWaveformFrame.width > 180)
    }

    @MainActor
    @Test func chatInputBarRecordingStopPublishesVoiceRecordingStopTapped() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))
        let recorder = ChatInputBarActionRecorder()
        inputBar.onAction = { action in
            recorder.record(action)
        }

        inputBar.renderVoiceRecordingState(
            VoiceRecordingState(
                isRecording: true,
                isCanceling: false,
                elapsedMilliseconds: 4_200,
                averagePowerLevel: 0.64,
                hintText: "Release to preview"
            )
        )
        button(in: inputBar, identifier: "chat.voiceStopButton")?.sendActions(for: .touchUpInside)

        #expect(recorder.actions == [.voiceRecordingStopTapped])
    }

    @MainActor
    @Test func chatInputBarShowsVoicePreviewControlsAfterRecordingCompletes() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))

        inputBar.setPendingVoicePreview(durationMilliseconds: 4_200, isPlaying: false, animated: false)
        inputBar.layoutIfNeeded()

        #expect(button(in: inputBar, identifier: "chat.voicePreviewCancelButton") == nil)
        #expect(button(in: inputBar, identifier: "chat.voicePreviewPlayButton")?.isEnabled == true)
        #expect(findView(in: inputBar, identifier: "chat.voicePreviewWaveform") != nil)
        #expect(findLabel(withText: "+ 0:04", in: inputBar) != nil)
        #expect(button(in: inputBar, identifier: "chat.voicePreviewSendButton")?.isEnabled == true)
        #expect(button(in: inputBar, identifier: "chat.sendButton") == nil)
    }

    @MainActor
    @Test func chatInputBarRefreshesLocalizedAccessibilityWhenLanguageChanges() throws {
        AppLanguageManager.shared.setPreference(.language(.english))
        defer {
            AppLanguageManager.shared.setPreference(.system)
        }
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 150))

        inputBar.setPendingVoicePreview(durationMilliseconds: 4_200, isPlaying: false, animated: false)
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
        #expect(button(in: inputBar, accessibilityLabel: "Play Voice Preview") != nil)
        #expect(button(in: inputBar, accessibilityLabel: "Send Voice Preview") != nil)
        #expect(button(in: inputBar, accessibilityLabel: "Remove Attachment") != nil)

        AppLanguageManager.shared.setPreference(.language(.arabic))
        inputBar.applyLanguageChange(AppLanguageManager.shared.currentContext)
        inputBar.layoutIfNeeded()

        #expect(button(in: inputBar, accessibilityLabel: L10n.shared.tr("chat.voicePreview.play.accessibility")) != nil)
        #expect(button(in: inputBar, accessibilityLabel: L10n.shared.tr("chat.voicePreview.send.accessibility")) != nil)
        #expect(button(in: inputBar, accessibilityLabel: L10n.shared.tr("chat.attachment.remove.accessibility")) != nil)
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

        #expect(findLabel(withText: "+ 0:01/0:04", in: inputBar) != nil)
    }

    @MainActor
    @Test func chatInputBarHighlightsMentionTextInComposer() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))
        let text = "提醒 @Kevis 和 @所有人 "
        inputBar.setText(text, animated: false)

        let textView = try #require(findView(ofType: UITextView.self, in: inputBar))
        let attributedText = try #require(textView.attributedText)
        let nsText = textView.text as NSString
        let firstMentionRange = nsText.range(of: "@Kevis")
        let allMentionRange = nsText.range(of: "@所有人")
        let firstMentionColor = try #require(
            attributedText.attribute(.foregroundColor, at: firstMentionRange.location, effectiveRange: nil) as? UIColor
        )
        let allMentionColor = try #require(
            attributedText.attribute(.foregroundColor, at: allMentionRange.location, effectiveRange: nil) as? UIColor
        )
        let normalTextColor = try #require(
            attributedText.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        )

        #expect(inputBar.text == text)
        #expect(textView.text == text)
        #expect(firstMentionColor == .systemBlue)
        #expect(allMentionColor == .systemBlue)
        #expect(normalTextColor != .systemBlue)
    }

    @MainActor
    @Test func chatInputBarPreviewSendDoesNotTriggerTextSend() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))
        let recorder = ChatInputBarActionRecorder()
        inputBar.onAction = { action in
            recorder.record(action)
        }

        inputBar.setPendingVoicePreview(durationMilliseconds: 4_200, isPlaying: false, animated: false)
        button(in: inputBar, identifier: "chat.voicePreviewSendButton")?.sendActions(for: .touchUpInside)

        #expect(recorder.actions == [.voicePreviewSend])
    }

    @MainActor
    @Test func chatInputBarVoicePreviewDeleteFromMoreButtonAndPlayActionsStayRouted() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))
        let recorder = ChatInputBarActionRecorder()
        inputBar.onAction = { action in
            recorder.record(action)
        }

        inputBar.setPendingVoicePreview(durationMilliseconds: 4_200, isPlaying: false, animated: false)
        button(in: inputBar, identifier: "chat.voicePreviewPlayButton")?.sendActions(for: .touchUpInside)
        button(in: inputBar, identifier: "chat.moreButton")?.sendActions(for: .touchUpInside)

        #expect(recorder.actions == [.voicePreviewPlayToggle, .voicePreviewCancel])
    }

    @MainActor
    @Test func chatInputBarVoicePreviewUsesRotatedMoreButtonForDelete() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))

        inputBar.setPendingVoicePreview(durationMilliseconds: 4_200, isPlaying: false, animated: false)
        inputBar.layoutIfNeeded()

        let moreButton = try #require(button(in: inputBar, identifier: "chat.moreButton"))
        #expect(moreButton.isHidden == false)
        #expect(moreButton.showsMenuAsPrimaryAction == false)
        #expect(moreButton.menu == nil)
        #expect(abs(moreButton.transform.a - cos(.pi / 4)) < 0.001)
        #expect(abs(moreButton.transform.b - sin(.pi / 4)) < 0.001)

        inputBar.clearPendingVoicePreview(animated: false)
        inputBar.layoutIfNeeded()

        #expect(moreButton.transform == .identity)
        #expect(moreButton.showsMenuAsPrimaryAction == true)
        #expect(moreButton.menu?.children.isEmpty == false)
        #expect(button(in: inputBar, identifier: "chat.voiceButton")?.isEnabled == true)
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
        inputBar.onAction = { action in
            recorder.record(action)
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
    @Test func chatInputBarUsesMessageStyleTransparentMaterial() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))
        inputBar.layoutIfNeeded()

        #expect(countViews(ofType: ChatInputSurfaceBackgroundView.self, in: inputBar) == 1)
        #expect(countViews(ofType: UIVisualEffectView.self, in: inputBar) == 1)

        let materialView = try #require(
            findView(in: inputBar, identifier: "chat.inputBarMaterialBackground") as? UIVisualEffectView
        )
        let surfaceView = try #require(findView(in: inputBar, identifier: "chat.inputBarSurface"))
        let tintView = try #require(findView(in: inputBar, identifier: "chat.inputBarMaterialTint"))
        let separatorView = try #require(findView(in: inputBar, identifier: "chat.inputBarTopSeparator"))
        let moreButton = try #require(button(in: inputBar, identifier: "chat.moreButton"))
        let surfaceFrame = surfaceView.convert(surfaceView.bounds, to: inputBar)
        let tintColor = try #require(tintView.backgroundColor)
        let tintAlpha = rgbaComponents(
            for: tintColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        ).alpha
        let moreButtonLightColor = try #require(
            moreButton.configuration?.baseBackgroundColor?.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        )
        let moreButtonAlpha = rgbaComponents(for: moreButtonLightColor).alpha

        #expect(materialView.effect is UIBlurEffect)
        #expect(separatorView.backgroundColor != nil)
        #expect(inputBar.backgroundColor == nil || inputBar.backgroundColor == .clear)
        #expect(abs(surfaceFrame.maxY - inputBar.bounds.maxY) <= 1)
        #expect(tintAlpha >= 0.70)
        #expect(tintAlpha <= 0.95)
        #expect(moreButton.layer.shadowOpacity <= 0.08)
        #expect(moreButtonAlpha <= 0.62)
    }

    @MainActor
    @Test func chatInputBarAttachmentPreviewUsesTransparentRail() throws {
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

        let previewRail = try #require(findView(in: inputBar, identifier: "chat.pendingAttachmentPreview"))
        let itemView = try #require(findView(in: inputBar, identifier: "chat.pendingAttachmentPreviewItem.photo-1"))
        let removeButton = try #require(button(in: inputBar, identifier: "chat.removeAttachmentButton.photo-1"))
        let removeButtonColor = try #require(removeButton.backgroundColor)
        let removeButtonAlpha = rgbaComponents(
            for: removeButtonColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        ).alpha

        #expect(previewRail.backgroundColor == nil || previewRail.backgroundColor == .clear)
        #expect(itemView.backgroundColor == nil || itemView.backgroundColor == .clear)
        #expect(removeButtonAlpha <= 0.66)
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

        #expect(viewController.title == L10n.shared.tr("account.title"))
        #expect(viewController.tabBarItem.accessibilityIdentifier == "mainTab.account")
        #expect(findView(in: viewController.view, identifier: "account.profileHeader") != nil)
        #expect(findLabel(withText: "Session User", in: viewController.view) != nil)
        #expect(findLabel(withText: "session_user", in: viewController.view) != nil)

        #expect(findView(ofType: UITableView.self, in: viewController.view) == nil)

        let collectionView = try #require(findView(in: viewController.view, identifier: "account.collectionView") as? UICollectionView)
        let profileCell = try #require(collectionView.cellForItem(at: IndexPath(row: 0, section: 0)))
        #expect(findView(in: profileCell, identifier: "account.profileHeader") != nil)
        collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: IndexPath(row: 1, section: 1))
        collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: IndexPath(row: 2, section: 1))

        #expect(actions == [.switchAccount, .logOut])
    }

    @MainActor
    @Test func accountViewControllerRefreshesVisibleRowsWhenLanguageChanges() async throws {
        AppLanguageManager.shared.setPreference(.language(.english))
        defer {
            AppLanguageManager.shared.setPreference(.system)
        }

        let viewController = AccountViewController(
            state: AccountViewState(
                displayName: "Session User",
                userID: "session_user",
                avatarURL: nil
            ),
            onAction: { _ in }
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
        try await waitForCondition {
            findLabel(withText: "Language", in: viewController.view) != nil
                && findLabel(withText: "English", in: viewController.view) != nil
        }

        AppLanguageManager.shared.setPreference(.language(.arabic))
        window.applyAppLanguageContext(AppLanguageManager.shared.currentContext)

        #expect(viewController.title == "الحساب")
        try await waitForCondition {
            findLabel(withText: "اللغة", in: viewController.view) != nil
                && findLabel(withText: "العربية", in: viewController.view) != nil
        }

        AppLanguageManager.shared.setPreference(.language(.simplifiedChinese))
        window.applyAppLanguageContext(AppLanguageManager.shared.currentContext)

        #expect(viewController.title == "账号")
        try await waitForCondition {
            findLabel(withText: "语言", in: viewController.view) != nil
                && findLabel(withText: "简体中文", in: viewController.view) != nil
        }
        let displayNameLabel = try #require(findLabel(withText: "Session User", in: viewController.view))
        let languageLabel = try #require(findLabel(withText: "语言", in: viewController.view))
        #expect(displayNameLabel.convert(displayNameLabel.bounds, to: viewController.view).minX < viewController.view.bounds.midX)
        #expect(languageLabel.convert(languageLabel.bounds, to: viewController.view).minX < viewController.view.bounds.midX)
    }

    @MainActor
    @Test func accountViewControllerPresentsLanguageSettingsModally() async throws {
        let viewController = AccountViewController(
            state: AccountViewState(
                displayName: "Session User",
                userID: "session_user",
                avatarURL: nil
            ),
            onAction: { _ in }
        )
        let navigationController = UINavigationController(rootViewController: viewController)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        viewController.view.layoutIfNeeded()

        let collectionView = try #require(findView(in: viewController.view, identifier: "account.collectionView") as? UICollectionView)
        collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: IndexPath(row: 0, section: 1))

        try await waitForCondition {
            navigationController.presentedViewController is UINavigationController
        }
        let presentedNavigationController = try #require(navigationController.presentedViewController as? UINavigationController)
        #expect(presentedNavigationController.viewControllers.first is LanguageSettingsViewController)
        #expect(presentedNavigationController.modalPresentationStyle == .pageSheet)
    }

    @MainActor
    @Test func languageSettingsViewControllerImmediatelyRestoresLTRWhenSwitchingFromArabicToChinese() throws {
        AppLanguageManager.shared.setPreference(.language(.arabic))
        defer {
            AppLanguageManager.shared.setPreference(.system)
        }

        let viewController = LanguageSettingsViewController()
        let navigationController = UINavigationController(rootViewController: viewController)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        viewController.applyLanguageChange(AppLanguageManager.shared.currentContext)
        let collectionView = try #require(findView(in: viewController.view, identifier: "language.collectionView") as? UICollectionView)
        #expect(viewController.view.semanticContentAttribute == .forceRightToLeft)
        #expect(collectionView.semanticContentAttribute == .forceRightToLeft)
        #expect(navigationController.navigationBar.semanticContentAttribute == .forceRightToLeft)
        #expect(viewController.view.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(collectionView.effectiveUserInterfaceLayoutDirection == .rightToLeft)

        collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: IndexPath(item: 2, section: 0))

        #expect(AppLanguageManager.shared.currentContext.resolvedLanguage == .simplifiedChinese)
        #expect(viewController.view.semanticContentAttribute == .forceLeftToRight)
        #expect(collectionView.semanticContentAttribute == .forceLeftToRight)
        #expect(navigationController.navigationBar.semanticContentAttribute == .forceLeftToRight)
        #expect(viewController.view.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect(collectionView.effectiveUserInterfaceLayoutDirection == .leftToRight)
    }

    @MainActor
    @Test func presentedLanguageSettingsKeepsDirectionConsistentWhenSwitchingLanguages() async throws {
        AppLanguageManager.shared.setPreference(.language(.simplifiedChinese))
        defer {
            AppLanguageManager.shared.setPreference(.system)
        }

        let accountViewController = AccountViewController(
            state: AccountViewState(
                displayName: "Session User",
                userID: "session_user",
                avatarURL: nil
            ),
            onAction: { _ in }
        )
        let rootNavigationController = UINavigationController(rootViewController: accountViewController)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = rootNavigationController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        accountViewController.loadViewIfNeeded()
        accountViewController.view.layoutIfNeeded()
        let accountCollectionView = try #require(findView(in: accountViewController.view, identifier: "account.collectionView") as? UICollectionView)
        accountCollectionView.delegate?.collectionView?(accountCollectionView, didSelectItemAt: IndexPath(row: 0, section: 1))

        try await waitForCondition {
            rootNavigationController.presentedViewController is UINavigationController
        }
        let presentedNavigationController = try #require(rootNavigationController.presentedViewController as? UINavigationController)
        let languageViewController = try #require(presentedNavigationController.viewControllers.first as? LanguageSettingsViewController)
        languageViewController.loadViewIfNeeded()
        languageViewController.view.layoutIfNeeded()
        let languageCollectionView = try #require(findView(in: languageViewController.view, identifier: "language.collectionView") as? UICollectionView)

        languageCollectionView.delegate?.collectionView?(languageCollectionView, didSelectItemAt: IndexPath(item: 4, section: 0))
        #expect(AppLanguageManager.shared.currentContext.resolvedLanguage == .arabic)
        #expect(window.semanticContentAttribute == .forceRightToLeft)
        #expect(rootNavigationController.view.semanticContentAttribute == .forceRightToLeft)
        #expect(accountViewController.view.semanticContentAttribute == .forceRightToLeft)
        #expect(presentedNavigationController.view.semanticContentAttribute == .forceRightToLeft)
        #expect(languageViewController.view.semanticContentAttribute == .forceRightToLeft)
        #expect(languageCollectionView.semanticContentAttribute == .forceRightToLeft)

        languageCollectionView.delegate?.collectionView?(languageCollectionView, didSelectItemAt: IndexPath(item: 2, section: 0))
        #expect(AppLanguageManager.shared.currentContext.resolvedLanguage == .simplifiedChinese)
        #expect(window.semanticContentAttribute == .forceLeftToRight)
        #expect(rootNavigationController.view.semanticContentAttribute == .forceLeftToRight)
        #expect(accountViewController.view.semanticContentAttribute == .forceLeftToRight)
        #expect(presentedNavigationController.view.semanticContentAttribute == .forceLeftToRight)
        #expect(languageViewController.view.semanticContentAttribute == .forceLeftToRight)
        #expect(languageCollectionView.semanticContentAttribute == .forceLeftToRight)
        languageViewController.view.layoutIfNeeded()
        languageCollectionView.layoutIfNeeded()
        #expect(languageCollectionView.visibleCells.allSatisfy { $0.effectiveUserInterfaceLayoutDirection == .leftToRight })
    }

    @MainActor
    @Test func languageSettingsViewControllerUsesReferenceStyleText() throws {
        AppLanguageManager.shared.setPreference(.language(.english))
        defer {
            AppLanguageManager.shared.setPreference(.system)
        }

        let viewController = LanguageSettingsViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        viewController.view.layoutIfNeeded()
        let collectionView = try #require(findView(in: viewController.view, identifier: "language.collectionView") as? UICollectionView)
        collectionView.layoutIfNeeded()

        #expect(findView(in: viewController.view, identifier: "language.closeButton") != nil)
        #expect(findLabel(withText: "Select Language", in: viewController.view) != nil)
        #expect(findLabel(withText: "iPhone Languages", in: viewController.view) != nil)
        let searchTextField = try #require(findView(in: viewController.view, identifier: "language.searchTextField") as? UITextField)
        #expect(searchTextField.placeholder == "Search")
        #expect(findLabel(withText: "简体中文", in: viewController.view) != nil)
        #expect(findLabel(withText: "Chinese, Simplified", in: viewController.view) != nil)
        #expect(findLabel(withText: "العربية", in: viewController.view) != nil)
        #expect(findLabel(withText: "Arabic", in: viewController.view) != nil)
    }

    @MainActor
    @Test func languageSettingsRowsPreserveWritingDirectionAfterSwitchingFromArabicToChinese() throws {
        AppLanguageManager.shared.setPreference(.language(.arabic))
        defer {
            AppLanguageManager.shared.setPreference(.system)
        }

        let viewController = LanguageSettingsViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        viewController.view.layoutIfNeeded()
        let collectionView = try #require(findView(in: viewController.view, identifier: "language.collectionView") as? UICollectionView)
        collectionView.layoutIfNeeded()
        #expect(viewController.view.effectiveUserInterfaceLayoutDirection == .rightToLeft)

        collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: IndexPath(item: 2, section: 0))
        viewController.view.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        #expect(viewController.view.effectiveUserInterfaceLayoutDirection == .leftToRight)
        let englishLabel = try #require(findLabel(withText: "English", in: viewController.view))
        let simplifiedChineseLabel = try #require(findLabel(withText: "简体中文", in: viewController.view))
        let arabicLabel = try #require(findLabel(withText: "العربية", in: viewController.view))
        #expect(label(englishLabel, hasWritingDirection: .leftToRight))
        #expect(label(simplifiedChineseLabel, hasWritingDirection: .leftToRight))
        #expect(label(arabicLabel, hasWritingDirection: .rightToLeft))
        #expect(englishLabel.convert(englishLabel.bounds, to: viewController.view).minX < viewController.view.bounds.midX)
        #expect(simplifiedChineseLabel.convert(simplifiedChineseLabel.bounds, to: viewController.view).minX < viewController.view.bounds.midX)
    }

    @MainActor
    @Test func chatEmojiItemContentConfigurationRendersButtonsAndActions() throws {
        let emoji = makeEmojiAsset(emojiID: "wave", name: "Wave", isFavorite: false)
        var selectedEmoji: EmojiAssetRecord?
        var favoriteToggle: (EmojiAssetRecord, Bool)?
        let configuration = ChatEmojiItemContentConfiguration(
            emoji: emoji,
            onSelect: { selectedEmoji = $0 },
            onFavoriteToggle: { favoriteToggle = ($0, $1) }
        )

        let contentView = configuration.makeContentView()
        contentView.frame = CGRect(x: 0, y: 0, width: 74, height: 74)
        contentView.layoutIfNeeded()

        let emojiButton = try #require(button(in: contentView, identifier: "chat.emojiItem.wave"))
        let favoriteButton = try #require(button(in: contentView, identifier: "chat.emojiFavorite.wave"))

        #expect(emojiButton.configuration?.title == "Wave")
        #expect(favoriteButton.configuration?.image == UIImage(systemName: "star"))

        emojiButton.sendActions(for: .touchUpInside)
        favoriteButton.sendActions(for: .touchUpInside)

        #expect(selectedEmoji?.emojiID == "wave")
        #expect(favoriteToggle?.0.emojiID == "wave")
        #expect(favoriteToggle?.1 == true)
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
        collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: IndexPath(row: 3, section: 1))

        let confirmAlert = try #require(navigationController.presentedViewController as? UIAlertController)
        #expect(confirmAlert.title == L10n.shared.tr("account.delete.confirm.title"))
        #expect(confirmAlert.message == L10n.shared.tr("account.delete.confirm.message"))
        let confirmAction = try #require(confirmAlert.actions.first { $0.title == L10n.shared.tr("account.action.deleteLocalData") })
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

        #expect(menuChildren.contains { $0.title == L10n.shared.tr("chat.more.photoLibrary") })
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
        inputBar.onAction = { action in
            recorder.record(action)
        }

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
        inputBar.onAction = { action in
            recorder.record(action)
        }

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
    @Test func chatEmojiPanelKeepsManualRecentSelectionAcrossRenderRefresh() throws {
        let panelView = ChatEmojiPanelView(frame: CGRect(x: 0, y: 0, width: 390, height: 280))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.addSubview(panelView)
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            panelView.removeFromSuperview()
        }
        let state = makeEmojiPanelState(
            recentEmojis: [],
            favoriteEmojis: [makeEmojiAsset(emojiID: "favorite_stub", name: "Favorite Stub", isFavorite: true)],
            packageEmojis: [makeEmojiAsset(emojiID: "package_stub", name: "Package Stub")]
        )

        panelView.render(state)
        panelView.layoutIfNeeded()
        let grid = try #require(findView(in: panelView, identifier: "chat.emojiGrid") as? UICollectionView)
        #expect(grid.numberOfItems(inSection: 0) == 1)

        let recentButton = try #require(button(in: panelView, accessibilityLabel: "最近"))
        let favoritesButton = try #require(button(in: panelView, accessibilityLabel: "收藏"))

        recentButton.sendActions(for: .touchUpInside)
        panelView.render(state)
        panelView.layoutIfNeeded()

        #expect(isSelectedEmojiSectionButton(recentButton))
        #expect(isSelectedEmojiSectionButton(favoritesButton) == false)
        #expect(grid.numberOfItems(inSection: 0) == 0)
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
    @Test func chatEmojiPanelScrollsToTailEmojiWhenPackageHasManyItems() throws {
        let panelView = ChatEmojiPanelView(frame: CGRect(x: 0, y: 0, width: 390, height: 280))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.addSubview(panelView)
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            panelView.removeFromSuperview()
        }
        let packageEmojis = (1...31).map { index in
            makeEmojiAsset(emojiID: "scroll_stub_\(index)", name: "Scroll Stub \(index)")
        } + [
            makeEmojiAsset(emojiID: "scroll_tail", name: "Scroll Tail")
        ]
        let state = makeEmojiPanelState(
            recentEmojis: [],
            favoriteEmojis: [],
            packageEmojis: packageEmojis
        )

        panelView.render(state)
        button(in: panelView, accessibilityLabel: "全部表情")?.sendActions(for: .touchUpInside)
        panelView.layoutIfNeeded()

        let grid = try #require(findView(in: panelView, identifier: "chat.emojiGrid") as? UICollectionView)
        grid.layoutIfNeeded()
        let contentHeight = grid.collectionViewLayout.collectionViewContentSize.height

        #expect(contentHeight > grid.bounds.height)

        grid.scrollToItem(at: IndexPath(item: packageEmojis.count - 1, section: 0), at: .bottom, animated: false)
        grid.layoutIfNeeded()

        #expect(grid.contentOffset.y > 0)
        #expect(findView(in: panelView, identifier: "chat.emojiItem.scroll_tail") != nil)
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
    @Test func chatPhotoLibraryInputIsTransparentContentPanel() throws {
        let photoPanel = ChatPhotoLibraryInputView(frame: CGRect(x: 0, y: 0, width: 390, height: 342))
        photoPanel.layoutIfNeeded()

        #expect(photoPanel.backgroundColor == nil || photoPanel.backgroundColor == .clear)
        #expect(countViews(ofType: ChatInputSurfaceBackgroundView.self, in: photoPanel) == 0)
        #expect(findView(in: photoPanel, identifier: "chat.photoLibraryPanelMaterialBackground") == nil)
    }

    @MainActor
    @Test func chatEmojiPanelIsTransparentContentPanel() throws {
        let emojiPanel = ChatEmojiPanelView(frame: CGRect(x: 0, y: 0, width: 390, height: 280))
        emojiPanel.layoutIfNeeded()

        #expect(emojiPanel.backgroundColor == nil || emojiPanel.backgroundColor == .clear)
        #expect(countViews(ofType: ChatInputSurfaceBackgroundView.self, in: emojiPanel) == 0)
        #expect(findView(in: emojiPanel, identifier: "chat.emojiInputPanelMaterialBackground") == nil)
        #expect(emojiPanel.clipsToBounds == false)
    }

    @MainActor
    @Test func chatInputBarOwnsSingleBackgroundAcrossInstalledPanels() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 500))
        let photoPanel = ChatPhotoLibraryInputView(frame: .zero)
        let emojiPanel = ChatEmojiPanelView(frame: .zero)
        inputBar.installPhotoLibraryInputView(photoPanel)
        inputBar.installEmojiPanelView(emojiPanel)

        inputBar.showPhotoLibraryInput()
        inputBar.layoutIfNeeded()

        #expect(countViews(ofType: ChatInputSurfaceBackgroundView.self, in: inputBar) == 1)
        #expect(photoPanel.isDescendant(of: inputBar))
        #expect(photoPanel.isHidden == false)
        #expect(emojiPanel.isHidden)

        inputBar.showEmojiInput()
        inputBar.layoutIfNeeded()

        #expect(countViews(ofType: ChatInputSurfaceBackgroundView.self, in: inputBar) == 1)
        #expect(emojiPanel.isDescendant(of: inputBar))
        #expect(emojiPanel.isHidden == false)
        #expect(photoPanel.isHidden)
    }

    @MainActor
    @Test func chatInputBarBackgroundFillsInputBarBounds() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 500))
        inputBar.layoutIfNeeded()

        let backgroundView = try #require(findView(ofType: ChatInputSurfaceBackgroundView.self, in: inputBar))
        let backgroundFrame = backgroundView.convert(backgroundView.bounds, to: inputBar)

        #expect(abs(backgroundFrame.minY - inputBar.bounds.minY) <= 1)
        #expect(abs(backgroundFrame.maxY - inputBar.bounds.maxY) <= 1)
    }

    @MainActor
    @Test func chatInputBarContentStackReachesBottomWhenCustomPanelIsVisible() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 500))
        let emojiPanel = ChatEmojiPanelView(frame: .zero)
        inputBar.installEmojiPanelView(emojiPanel)
        inputBar.setCustomPanelBottomSafeAreaExtension(34)

        inputBar.showEmojiInput()
        inputBar.layoutIfNeeded()

        let contentStackView = try #require(inputBar.subviews.compactMap { $0 as? UIStackView }.first)
        let stackFrame = contentStackView.convert(contentStackView.bounds, to: inputBar)

        #expect(abs(stackFrame.maxY - inputBar.bounds.maxY) <= 1)
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
    @Test func chatInputBarKeepsMoreButtonOutsideTransparentTextContainer() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 80))
        inputBar.layoutIfNeeded()

        let moreButton = try #require(button(in: inputBar, identifier: "chat.moreButton"))
        let textView = try #require(findView(ofType: UITextView.self, in: inputBar))
        let textContainer = try #require(textView.superview)
        let readableFill = try #require(findView(in: textContainer, identifier: "chat.textInputReadableFill"))
        let readableFillColor = try #require(readableFill.backgroundColor)
        let readableFillAlpha = rgbaComponents(
            for: readableFillColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        ).alpha

        let moreFrame = moreButton.convert(moreButton.bounds, to: inputBar)
        let textContainerFrame = textContainer.convert(textContainer.bounds, to: inputBar)
        let readableFillFrame = readableFill.convert(readableFill.bounds, to: textContainer)

        #expect(moreButton.isDescendant(of: textContainer) == false)
        #expect(moreFrame.maxX <= textContainerFrame.minX)
        #expect(textContainer.backgroundColor == nil || textContainer.backgroundColor == .clear)
        #expect(readableFillFrame == textContainer.bounds)
        #expect(readableFillAlpha >= 0.42)
    }

    @MainActor
    @Test func chatInputBarKeepsTextContainerCornerRadiusFixedWhenTextGrows() throws {
        let inputBar = ChatInputBarView(frame: CGRect(x: 0, y: 0, width: 390, height: 160))
        inputBar.layoutIfNeeded()

        let textView = try #require(findView(ofType: UITextView.self, in: inputBar))
        let textContainer = try #require(textView.superview)
        textView.text = """
        输入文字换行
        第二行
        第三行
        第四行
        """
        inputBar.textViewDidChange(textView)
        inputBar.layoutIfNeeded()

        #expect(textContainer.bounds.height > 44)
        #expect(textContainer.layer.cornerRadius == 22)
    }

}
