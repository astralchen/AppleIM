//
//  ServerMessageSendService.swift
//  AppleIM
//
//  服务端消息发送适配层
//

import Foundation

/// 服务端文本消息发送请求。
nonisolated struct ServerTextMessageSendRequest: Codable, Equatable, Sendable {
    /// 会话 ID
    let conversationID: String
    /// 客户端消息 ID，用于服务端幂等
    let clientMessageID: String
    /// 发送者 ID
    let senderID: String
    /// 文本内容
    let text: String
    /// 本地发送时间
    let localTime: Int64

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case clientMessageID = "client_msg_id"
        case senderID = "sender_id"
        case text
        case localTime = "local_time"
    }
}

/// 服务端文本消息发送响应。
nonisolated struct ServerTextMessageSendResponse: Codable, Equatable, Sendable {
    /// 服务端消息 ID
    let serverMessageID: String
    /// 服务端会话内序号
    let sequence: Int64
    /// 服务端时间
    let serverTime: Int64

    enum CodingKeys: String, CodingKey {
        case serverMessageID = "server_msg_id"
        case sequence = "seq"
        case serverTime = "server_time"
    }

    var ack: MessageSendAck {
        MessageSendAck(
            serverMessageID: serverMessageID,
            sequence: sequence,
            serverTime: serverTime
        )
    }
}

/// 服务端图片消息发送请求。
nonisolated struct ServerImageMessageSendRequest: Codable, Equatable, Sendable {
    let conversationID: String
    let clientMessageID: String
    let senderID: String
    let mediaID: String
    let cdnURL: String
    let md5: String?
    let width: Int
    let height: Int
    let sizeBytes: Int64
    let format: String
    let localTime: Int64

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case clientMessageID = "client_msg_id"
        case senderID = "sender_id"
        case mediaID = "media_id"
        case cdnURL = "cdn_url"
        case md5
        case width
        case height
        case sizeBytes = "size_bytes"
        case format
        case localTime = "local_time"
    }
}

/// 服务端语音消息发送请求。
nonisolated struct ServerVoiceMessageSendRequest: Codable, Equatable, Sendable {
    let conversationID: String
    let clientMessageID: String
    let senderID: String
    let mediaID: String
    let cdnURL: String
    let md5: String?
    let durationMilliseconds: Int
    let sizeBytes: Int64
    let format: String
    let localTime: Int64

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case clientMessageID = "client_msg_id"
        case senderID = "sender_id"
        case mediaID = "media_id"
        case cdnURL = "cdn_url"
        case md5
        case durationMilliseconds = "duration_ms"
        case sizeBytes = "size_bytes"
        case format
        case localTime = "local_time"
    }
}

/// 服务端视频消息发送请求。
nonisolated struct ServerVideoMessageSendRequest: Codable, Equatable, Sendable {
    let conversationID: String
    let clientMessageID: String
    let senderID: String
    let mediaID: String
    let cdnURL: String
    let md5: String?
    let durationMilliseconds: Int
    let width: Int
    let height: Int
    let sizeBytes: Int64
    let localTime: Int64

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case clientMessageID = "client_msg_id"
        case senderID = "sender_id"
        case mediaID = "media_id"
        case cdnURL = "cdn_url"
        case md5
        case durationMilliseconds = "duration_ms"
        case width
        case height
        case sizeBytes = "size_bytes"
        case localTime = "local_time"
    }
}

/// 服务端文件消息发送请求。
nonisolated struct ServerFileMessageSendRequest: Codable, Equatable, Sendable {
    let conversationID: String
    let clientMessageID: String
    let senderID: String
    let mediaID: String
    let cdnURL: String
    let md5: String?
    let fileName: String
    let fileExtension: String?
    let sizeBytes: Int64
    let localTime: Int64

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case clientMessageID = "client_msg_id"
        case senderID = "sender_id"
        case mediaID = "media_id"
        case cdnURL = "cdn_url"
        case md5
        case fileName = "file_name"
        case fileExtension = "file_extension"
        case sizeBytes = "size_bytes"
        case localTime = "local_time"
    }
}

/// 服务端表情消息发送请求。
nonisolated struct ServerEmojiMessageSendRequest: Codable, Equatable, Sendable {
    let conversationID: String
    let clientMessageID: String
    let senderID: String
    let emojiID: String
    let packageID: String?
    let emojiType: Int
    let name: String?
    let cdnURL: String?
    let width: Int?
    let height: Int?
    let sizeBytes: Int64?
    let localTime: Int64

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case clientMessageID = "client_msg_id"
        case senderID = "sender_id"
        case emojiID = "emoji_id"
        case packageID = "package_id"
        case emojiType = "emoji_type"
        case name
        case cdnURL = "cdn_url"
        case width
        case height
        case sizeBytes = "size_bytes"
        case localTime = "local_time"
    }
}

/// 真实服务端消息发送服务。
nonisolated struct ServerMessageSendService: MessageSendService {
    /// 默认文本消息发送路径；真实接口确认后只需要在此处调整映射。
    private static let sendTextPath = "/v1/messages/text"
    private static let sendImagePath = "/v1/messages/image"
    private static let sendVoicePath = "/v1/messages/voice"
    private static let sendVideoPath = "/v1/messages/video"
    private static let sendFilePath = "/v1/messages/file"
    private static let sendEmojiPath = "/v1/messages/emoji"

    /// 服务配置
    nonisolated struct Configuration: Sendable {
        /// 服务端基础 URL
        let baseURL: URL
        /// 鉴权 token provider
        let authTokenProvider: @Sendable () async -> String?
        /// 401 后主动刷新 token
        let authTokenRefresher: @Sendable () async -> String?
        /// 请求超时时间
        let timeoutSeconds: TimeInterval

        init(
            baseURL: URL,
            authTokenProvider: @escaping @Sendable () async -> String?,
            authTokenRefresher: @escaping @Sendable () async -> String? = { nil },
            timeoutSeconds: TimeInterval = 15
        ) {
            self.baseURL = baseURL
            self.authTokenProvider = authTokenProvider
            self.authTokenRefresher = authTokenRefresher
            self.timeoutSeconds = max(1, timeoutSeconds)
        }

        /// 从环境变量创建配置。
        ///
        /// 生产 App 默认不启用真实发送；只有显式提供 baseURL 且存在登录 token 时才切换到服务端适配层。
        static func fromEnvironment(
            _ environment: [String: String] = ProcessInfo.processInfo.environment,
            token: String?
        ) -> Configuration? {
            guard let token = nonEmptyValue(token) else {
                return nil
            }

            return fromEnvironment(environment) {
                token
            }
        }

        /// 从环境变量创建配置。
        ///
        /// 生产 App 默认不启用真实发送；只有显式提供 baseURL 时才切换到服务端适配层。
        static func fromEnvironment(
            _ environment: [String: String] = ProcessInfo.processInfo.environment,
            authTokenProvider: @escaping @Sendable () async -> String?,
            authTokenRefresher: @escaping @Sendable () async -> String? = { nil }
        ) -> Configuration? {
            guard
                let baseURLValue = nonEmptyValue(environment["CHATBRIDGE_SERVER_BASE_URL"]),
                let baseURL = URL(string: baseURLValue)
            else {
                return nil
            }

            let timeoutSeconds = environment["CHATBRIDGE_SERVER_TIMEOUT_SECONDS"]
                .flatMap(nonEmptyValue)
                .flatMap(TimeInterval.init)
                ?? 15

            return Configuration(
                baseURL: baseURL,
                authTokenProvider: authTokenProvider,
                authTokenRefresher: authTokenRefresher,
                timeoutSeconds: timeoutSeconds
            )
        }

        private static func nonEmptyValue(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private let httpClient: any ChatBridgeHTTPPosting

    init(configuration: Configuration) {
        let httpClient = ChatBridgeHTTPClient(
            configuration: ChatBridgeHTTPClient.Configuration(
                baseURL: configuration.baseURL,
                authTokenProvider: configuration.authTokenProvider,
                timeoutSeconds: configuration.timeoutSeconds
            )
        )
        self.httpClient = TokenRefreshingHTTPClient(
            httpClient: httpClient,
            authTokenRefresher: configuration.authTokenRefresher
        )
    }

    init(httpClient: any ChatBridgeHTTPPosting) {
        self.httpClient = httpClient
    }

    func sendText(message: StoredMessage) async -> MessageSendResult {
        guard
            message.type == .text,
            let text = message.text,
            let clientMessageID = message.clientMessageID
        else {
            return .failure(.ackMissing)
        }

        let request = ServerTextMessageSendRequest(
            conversationID: message.conversationID.rawValue,
            clientMessageID: clientMessageID,
            senderID: message.senderID.rawValue,
            text: text,
            localTime: message.localTime
        )

        do {
            let response = try await httpClient.postJSON(
                path: Self.sendTextPath,
                body: request,
                responseType: ServerTextMessageSendResponse.self
            )
            return .success(response.ack)
        } catch let error as ChatBridgeHTTPError {
            return .failure(Self.failureReason(from: error))
        } catch {
            return .failure(.unknown)
        }
    }

    func sendImage(message: StoredMessage, upload: MediaUploadAck) async -> MessageSendResult {
        guard
            message.type == .image,
            let image = message.image,
            let clientMessageID = message.clientMessageID,
            let cdnURL = Self.nonEmptyValue(upload.cdnURL)
        else {
            return .failure(.ackMissing)
        }

        let request = ServerImageMessageSendRequest(
            conversationID: message.conversationID.rawValue,
            clientMessageID: clientMessageID,
            senderID: message.senderID.rawValue,
            mediaID: Self.nonEmptyValue(upload.mediaID) ?? image.mediaID,
            cdnURL: cdnURL,
            md5: upload.md5 ?? image.md5,
            width: image.width,
            height: image.height,
            sizeBytes: image.sizeBytes,
            format: image.format,
            localTime: message.localTime
        )

        return await sendMedia(path: Self.sendImagePath, request: request)
    }

    func sendVoice(message: StoredMessage, upload: MediaUploadAck) async -> MessageSendResult {
        guard
            message.type == .voice,
            let voice = message.voice,
            let clientMessageID = message.clientMessageID,
            let cdnURL = Self.nonEmptyValue(upload.cdnURL)
        else {
            return .failure(.ackMissing)
        }

        let request = ServerVoiceMessageSendRequest(
            conversationID: message.conversationID.rawValue,
            clientMessageID: clientMessageID,
            senderID: message.senderID.rawValue,
            mediaID: Self.nonEmptyValue(upload.mediaID) ?? voice.mediaID,
            cdnURL: cdnURL,
            md5: upload.md5,
            durationMilliseconds: voice.durationMilliseconds,
            sizeBytes: voice.sizeBytes,
            format: voice.format,
            localTime: message.localTime
        )

        return await sendMedia(path: Self.sendVoicePath, request: request)
    }

    func sendVideo(message: StoredMessage, upload: MediaUploadAck) async -> MessageSendResult {
        guard
            message.type == .video,
            let video = message.video,
            let clientMessageID = message.clientMessageID,
            let cdnURL = Self.nonEmptyValue(upload.cdnURL)
        else {
            return .failure(.ackMissing)
        }

        let request = ServerVideoMessageSendRequest(
            conversationID: message.conversationID.rawValue,
            clientMessageID: clientMessageID,
            senderID: message.senderID.rawValue,
            mediaID: Self.nonEmptyValue(upload.mediaID) ?? video.mediaID,
            cdnURL: cdnURL,
            md5: upload.md5 ?? video.md5,
            durationMilliseconds: video.durationMilliseconds,
            width: video.width,
            height: video.height,
            sizeBytes: video.sizeBytes,
            localTime: message.localTime
        )

        return await sendMedia(path: Self.sendVideoPath, request: request)
    }

    func sendFile(message: StoredMessage, upload: MediaUploadAck) async -> MessageSendResult {
        guard
            message.type == .file,
            let file = message.file,
            let clientMessageID = message.clientMessageID,
            let cdnURL = Self.nonEmptyValue(upload.cdnURL)
        else {
            return .failure(.ackMissing)
        }

        let request = ServerFileMessageSendRequest(
            conversationID: message.conversationID.rawValue,
            clientMessageID: clientMessageID,
            senderID: message.senderID.rawValue,
            mediaID: Self.nonEmptyValue(upload.mediaID) ?? file.mediaID,
            cdnURL: cdnURL,
            md5: upload.md5 ?? file.md5,
            fileName: file.fileName,
            fileExtension: file.fileExtension,
            sizeBytes: file.sizeBytes,
            localTime: message.localTime
        )

        return await sendMedia(path: Self.sendFilePath, request: request)
    }

    func sendEmoji(message: StoredMessage) async -> MessageSendResult {
        guard
            message.type == .emoji,
            let emoji = message.emoji,
            let clientMessageID = message.clientMessageID
        else {
            return .failure(.ackMissing)
        }

        let request = ServerEmojiMessageSendRequest(
            conversationID: message.conversationID.rawValue,
            clientMessageID: clientMessageID,
            senderID: message.senderID.rawValue,
            emojiID: emoji.emojiID,
            packageID: emoji.packageID,
            emojiType: emoji.emojiType.rawValue,
            name: emoji.name,
            cdnURL: emoji.cdnURL,
            width: emoji.width,
            height: emoji.height,
            sizeBytes: emoji.sizeBytes,
            localTime: message.localTime
        )

        return await sendMedia(path: Self.sendEmojiPath, request: request)
    }

    private func sendMedia<Request: Encodable & Sendable>(
        path: String,
        request: Request
    ) async -> MessageSendResult {
        do {
            let response = try await httpClient.postJSON(
                path: path,
                body: request,
                responseType: ServerTextMessageSendResponse.self
            )
            return .success(response.ack)
        } catch let error as ChatBridgeHTTPError {
            return .failure(Self.failureReason(from: error))
        } catch {
            return .failure(.unknown)
        }
    }

    private static func failureReason(from error: ChatBridgeHTTPError) -> MessageSendFailureReason {
        switch error {
        case .offline:
            return .offline
        case .timeout:
            return .timeout
        case .ackMissing, .invalidResponse:
            return .ackMissing
        case .unacceptableStatus, .unknown:
            return .unknown
        }
    }

    private static func nonEmptyValue(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
