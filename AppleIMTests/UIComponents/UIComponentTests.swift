import Testing
import Foundation
import UIKit

@testable import AppleIM

extension AppleIMTests {
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
    @Test func chatMessageCellHighlightsMentionText() throws {
        let text = "你好 @Kevis 请看下 @所有人 "
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        cell.configure(
            row: makeChatRow(id: "mention_highlight_text", text: text, sortSequence: 1, isOutgoing: false),
            actions: .empty
        )

        let label = try #require(findLabel(withText: text, in: cell))
        let attributedText = try #require(label.attributedText)
        let nsText = text as NSString
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

        #expect(firstMentionColor == .systemBlue)
        #expect(allMentionColor == .systemBlue)
        #expect(normalTextColor == UIColor.label)
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
        let outgoingButton = try #require(button(in: outgoingCell, accessibilityLabel: L10n.shared.tr("chat.voice.play.accessibility")))
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

        let fallbackLabel = try #require(findLabel(withText: L10n.shared.tr("chat.media.imageUnavailable"), in: cell))
        let bubbleView = try #require(findView(ofType: ChatBubbleBackgroundView.self, in: cell))

        #expect(bubbleView.style == .media)
        #expect(fallbackLabel.textColor.resolvedColor(with: traits) == UIColor.label.resolvedColor(with: traits))
    }

    @MainActor
    @Test func chatMessageCellLocalizesMediaAndVoiceAccessibilityWhenLanguageChanges() throws {
        AppLanguageManager.shared.setPreference(.language(.english))
        defer {
            AppLanguageManager.shared.setPreference(.system)
        }
        let mediaRow = ChatMessageRowState(
            id: "localized_media_fallback",
            content: .image(.init(thumbnailPath: "/tmp/missing-localized-media.jpg")),
            sortSequence: 1,
            timeText: "Now",
            statusText: nil,
            uploadProgress: 0.42,
            isOutgoing: true,
            canRetry: false,
            canDelete: true,
            canRevoke: false
        )
        let voiceRow = makeVoiceRow(id: "localized_voice", sortSequence: 2, isUnplayed: false)
        let mediaCell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
        let voiceCell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 120))

        mediaCell.configure(row: mediaRow, actions: .empty)
        voiceCell.configure(row: voiceRow, actions: .empty)
        #expect(findLabel(withText: "Image unavailable", in: mediaCell) != nil)
        #expect(mediaCell.accessibilityLabel?.contains("Uploading 42%") == true)
        #expect(button(in: voiceCell, accessibilityLabel: "Play Voice") != nil)

        AppLanguageManager.shared.setPreference(.language(.simplifiedChinese))
        mediaCell.applyLanguageChange(AppLanguageManager.shared.currentContext)
        voiceCell.applyLanguageChange(AppLanguageManager.shared.currentContext)

        #expect(findLabel(withText: L10n.shared.tr("chat.media.imageUnavailable"), in: mediaCell) != nil)
        #expect(mediaCell.accessibilityLabel?.contains(L10n.shared.tr("chat.upload.progress.accessibility", 42)) == true)
        #expect(button(in: voiceCell, accessibilityLabel: L10n.shared.tr("chat.voice.play.accessibility")) != nil)
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
        #expect(button(in: voiceView, accessibilityLabel: L10n.shared.tr("chat.voice.play.accessibility")) != nil)
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

        let voiceButton = try #require(button(in: cell, accessibilityLabel: L10n.shared.tr("chat.voice.stop.accessibility")))
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
        #expect(button(in: cell, accessibilityLabel: L10n.shared.tr("chat.voice.play.accessibility")) != nil)
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
            let dataHandler = DefaultChatPhotoLibraryMediaPreparationService.makeDataReceivedHandler(fileHandle: fileHandle)

            dataHandler(Data([0x01, 0x02]))
            dataHandler(Data([0x03]))
            try fileHandle.close()
        }
        try await task.value

        let data = try Data(contentsOf: url)
        #expect(data == Data([0x01, 0x02, 0x03]))
    }

    @Test func photoLibraryVideoCompletionHandlerHopsToMainActorFromDetachedExecutor() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("picked-video.mov")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<URL, ChatPhotoLibraryMediaPreparationError>, Never>) in
            Task.detached {
                let fileHandle = try FileHandle(forWritingTo: url)
                let completionHandler = DefaultChatPhotoLibraryMediaPreparationService.makeCompletionHandler(
                    fileHandle: fileHandle,
                    temporaryFileManager: DefaultTemporaryMediaFileManager(),
                    temporaryURL: url,
                    completion: { result in
                        #expect(Thread.isMainThread)
                        continuation.resume(returning: result)
                    }
                )

                completionHandler(nil)
            }
        }

        #expect(try result.get() == url)
    }
}

@MainActor
func fittedChatMessageCell(row: ChatMessageRowState, width: CGFloat) -> ChatMessageCell {
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

enum BubbleTailEdge {
    case leading
    case trailing
}

@MainActor
func assertTailAlignsWithAvatarCenter(in cell: ChatMessageCell, edge: BubbleTailEdge) throws {
    let avatarView = try #require(findView(ofType: GradientBackgroundView.self, in: cell))
    let bubbleView = try #require(findView(ofType: ChatBubbleBackgroundView.self, in: cell))
    let avatarFrame = avatarView.convert(avatarView.bounds, to: cell.contentView)
    let bubbleFrame = bubbleView.convert(bubbleView.bounds, to: cell.contentView)
    let tailEdgeX = edge == .leading ? bubbleView.bounds.minX : bubbleView.bounds.maxX
    let tailYInBubble = try #require(tailTipY(in: ChatBubbleBackgroundView.maskPath(in: bubbleView.bounds, style: bubbleView.style), edgeX: tailEdgeX))
    let tailYInCell = bubbleFrame.minY + tailYInBubble

    #expect(abs(tailYInCell - avatarFrame.midY) < 1)
}

func tailTipY(in path: UIBezierPath, edgeX: CGFloat) -> CGFloat? {
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

@MainActor
func countViews<T: UIView>(ofType type: T.Type, in view: UIView) -> Int {
    let currentCount = view is T ? 1 : 0
    return view.subviews.reduce(currentCount) { partialResult, subview in
        partialResult + countViews(ofType: type, in: subview)
    }
}

@MainActor
func isSelectedEmojiSectionButton(_ button: UIButton) -> Bool {
    guard let backgroundColor = button.configuration?.baseBackgroundColor else {
        return false
    }
    let actual = rgbaComponents(
        for: backgroundColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    )
    let expected = rgbaComponents(
        for: UIColor.systemBlue.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    )
    return abs(actual.red - expected.red) < 0.01
        && abs(actual.green - expected.green) < 0.01
        && abs(actual.blue - expected.blue) < 0.01
        && abs(actual.alpha - expected.alpha) < 0.01
}

func makeEmojiMessageRow(id: MessageID, isOutgoing: Bool) -> ChatMessageRowState {
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
func solidFillColor(
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
func label(
    _ label: UILabel,
    hasWritingDirection direction: NSWritingDirection
) -> Bool {
    guard
        let attributedText = label.attributedText,
        attributedText.length > 0,
        let rawValue = attributedText.attribute(.writingDirection, at: 0, effectiveRange: nil)
    else {
        return false
    }

    let expectedValue = direction.rawValue | NSWritingDirectionFormatType.embedding.rawValue
    if let values = rawValue as? [NSNumber] {
        return values.contains { $0.intValue == expectedValue }
    }
    if let value = rawValue as? NSNumber {
        return value.intValue == expectedValue
    }
    return false
}

@MainActor
final class ChatInputBarActionRecorder: NSObject {
    private(set) var actions: [ChatInputBarAction] = []

    func record(_ action: ChatInputBarAction) {
        actions.append(action)
    }
}

@MainActor
final class ChatInputBarLayoutDelegateRecorder: ChatInputBarLayoutDelegate {
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
final class ChatEmojiPanelActionRecorder: NSObject {
    private(set) var actions: [ChatEmojiPanelAction] = []

    @objc func record(_ sender: ChatEmojiPanelView) {
        guard let action = sender.lastAction else { return }
        actions.append(action)
    }
}

@MainActor
final class ChatPhotoLibraryInputDelegateRecorder: ChatPhotoLibraryInputViewDelegate {
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
