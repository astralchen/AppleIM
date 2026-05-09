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

/// 真实服务端消息发送服务。
nonisolated struct ServerMessageSendService: MessageSendService {
    /// 默认文本消息发送路径；真实接口确认后只需要在此处调整映射。
    private static let sendTextPath = "/v1/messages/text"

    /// 服务配置
    nonisolated struct Configuration: Sendable {
        /// 服务端基础 URL
        let baseURL: URL
        /// 鉴权 token provider
        let authTokenProvider: @Sendable () async -> String?
        /// 请求超时时间
        let timeoutSeconds: TimeInterval

        init(
            baseURL: URL,
            authTokenProvider: @escaping @Sendable () async -> String?,
            timeoutSeconds: TimeInterval = 15
        ) {
            self.baseURL = baseURL
            self.authTokenProvider = authTokenProvider
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
            authTokenProvider: @escaping @Sendable () async -> String?
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
        self.httpClient = ChatBridgeHTTPClient(
            configuration: ChatBridgeHTTPClient.Configuration(
                baseURL: configuration.baseURL,
                authTokenProvider: configuration.authTokenProvider,
                timeoutSeconds: configuration.timeoutSeconds
            )
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
        .failure(.unknown)
    }

    func sendVoice(message: StoredMessage, upload: MediaUploadAck) async -> MessageSendResult {
        .failure(.unknown)
    }

    func sendVideo(message: StoredMessage, upload: MediaUploadAck) async -> MessageSendResult {
        .failure(.unknown)
    }

    func sendFile(message: StoredMessage, upload: MediaUploadAck) async -> MessageSendResult {
        .failure(.unknown)
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
}
