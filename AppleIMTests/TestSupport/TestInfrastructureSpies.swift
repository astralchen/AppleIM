import Testing
import AVFoundation
import Combine
import Foundation
import GRDB
import CoreGraphics
import ImageIO
import UIKit
import UniformTypeIdentifiers

@testable import AppleIM

extension UIAlertAction {
    func triggerForTesting() {
        typealias ActionHandler = @convention(block) (UIAlertAction) -> Void
        let handler = value(forKey: "handler") as? ActionHandler
        handler?(self)
    }
}

actor CapturingLocalNotificationManager: LocalNotificationManaging {
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

actor CapturingApplicationBadgeManager: ApplicationBadgeManaging {
    private var capturedValues: [Int] = []

    func setApplicationIconBadgeNumber(_ count: Int) async {
        capturedValues.append(count)
    }

    func values() -> [Int] {
        capturedValues
    }
}

nonisolated struct NoopChatStoreEventDispatcher: ChatStoreEventDispatching {
    func setApplicationBadgeNumber(_ count: Int) async {}

    func scheduleIncomingMessageNotifications(_ payloads: [IncomingMessageNotificationPayload]) async {}

    func indexMessageBestEffort(messageID: MessageID, userID: UserID) {}

    func removeMessageBestEffort(messageID: MessageID, userID: UserID) {}

    func indexConversationBestEffort(conversationID: ConversationID, userID: UserID) {}

    func postConversationsDidChange(userID: UserID, conversationIDs: Set<ConversationID>) {}
}

actor CapturingPublisherValues<Value: Sendable> {
    private var capturedValues: [Value] = []

    func append(_ value: Value) {
        capturedValues.append(value)
    }

    func values() -> [Value] {
        capturedValues
    }
}

func collectRows(from stream: AsyncThrowingStream<ChatMessageRowState, Error>) async throws -> [ChatMessageRowState] {
    var rows: [ChatMessageRowState] = []

    for try await row in stream {
        rows.append(row)
    }

    return rows
}

func requireTextContent(_ message: StoredMessage?) throws -> String {
    let message = try #require(message)
    guard case let .text(text) = message.content else {
        Issue.record("期望文本消息内容，实际为 \(message.content)")
        return ""
    }
    return text
}

func requireTextualContent(_ message: StoredMessage?) throws -> String {
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

func requireImageContent(_ message: StoredMessage?) throws -> StoredImageContent {
    let message = try #require(message)
    guard case let .image(image) = message.content else {
        Issue.record("期望图片消息内容，实际为 \(message.content)")
        return StoredImageContent(mediaID: "", localPath: "", thumbnailPath: "", width: 0, height: 0, sizeBytes: 0, format: "")
    }
    return image
}

func requireVoiceContent(_ message: StoredMessage?) throws -> StoredVoiceContent {
    let message = try #require(message)
    guard case let .voice(voice) = message.content else {
        Issue.record("期望语音消息内容，实际为 \(message.content)")
        return StoredVoiceContent(mediaID: "", localPath: "", durationMilliseconds: 0, sizeBytes: 0, format: "")
    }
    return voice
}

func requireVideoContent(_ message: StoredMessage?) throws -> StoredVideoContent {
    let message = try #require(message)
    guard case let .video(video) = message.content else {
        Issue.record("期望视频消息内容，实际为 \(message.content)")
        return StoredVideoContent(mediaID: "", localPath: "", thumbnailPath: "", durationMilliseconds: 0, width: 0, height: 0, sizeBytes: 0)
    }
    return video
}

func requireFileContent(_ message: StoredMessage?) throws -> StoredFileContent {
    let message = try #require(message)
    guard case let .file(file) = message.content else {
        Issue.record("期望文件消息内容，实际为 \(message.content)")
        return StoredFileContent(mediaID: "", localPath: "", fileName: "", fileExtension: nil, sizeBytes: 0)
    }
    return file
}

func requireEmojiContent(_ message: StoredMessage?) throws -> StoredEmojiContent {
    let message = try #require(message)
    guard case let .emoji(emoji) = message.content else {
        Issue.record("期望表情消息内容，实际为 \(message.content)")
        return StoredEmojiContent(emojiID: "", packageID: nil, emojiType: .system, name: nil, localPath: nil, thumbPath: nil, cdnURL: nil, width: nil, height: nil, sizeBytes: nil)
    }
    return emoji
}

func makeStoredTextMessage(
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

func makeStoredImageMessage(
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

func makeStoredVoiceMessage(
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

func makeStoredVideoMessage(
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

func makeStoredFileMessage(
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

func makeOutgoingStoredMessage(
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

actor RecordingHTTPClient: HTTPClient {
    private let response: ServerTextMessageSendResponse?
    private let tokenRefreshResponse: ServerTokenRefreshResponse?
    private let error: HTTPClientError?
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
        error: HTTPClientError? = nil,
        delayNanoseconds: UInt64 = 0
    ) {
        self.response = response
        self.tokenRefreshResponse = tokenRefreshResponse
        self.error = error
        self.delayNanoseconds = delayNanoseconds
    }

    func sendJSON<Request, Response>(
        _ body: Request,
        to path: String,
        decoding responseType: Response.Type
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
            throw HTTPClientError.ackMissing
        }

        return response
    }
}

actor ExpiringTextHTTPClient: HTTPClient {
    private let tokenProvider: (@Sendable () async -> String?)?
    private let response: ServerTextMessageSendResponse?
    private let error: HTTPClientError?
    private(set) var textSendCallCount = 0
    private(set) var mediaSendCallCount = 0
    private(set) var observedTokens: [String?] = []

    init(
        tokenProvider: (@Sendable () async -> String?)? = nil,
        response: ServerTextMessageSendResponse? = nil,
        error: HTTPClientError? = nil
    ) {
        self.tokenProvider = tokenProvider
        self.response = response
        self.error = error
    }

    func sendJSON<Request, Response>(
        _ body: Request,
        to path: String,
        decoding responseType: Response.Type
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
            throw HTTPClientError.unacceptableStatus(401)
        }

        guard let response = response as? Response else {
            throw HTTPClientError.ackMissing
        }

        return response
    }
}

actor TokenBox {
    private(set) var token: String

    init(token: String) {
        self.token = token
    }

    func updateToken(_ token: String) {
        self.token = token
    }
}

actor Counter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

nonisolated final class InMemoryAccountSessionStore: AccountSessionStore {
    private let sessionBox: TestLockedBox<AccountSession?>

    init(session: AccountSession? = nil) {
        self.sessionBox = TestLockedBox(session)
    }

    nonisolated func loadSession() -> AccountSession? {
        sessionBox.snapshot
    }

    nonisolated func saveSession(_ session: AccountSession) throws {
        sessionBox.set(session)
    }

    nonisolated func clearSession() {
        sessionBox.set(nil)
    }
}
