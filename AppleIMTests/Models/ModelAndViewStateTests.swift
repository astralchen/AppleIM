import Testing
import Foundation

@testable import AppleIM

extension AppleIMTests {
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
}
