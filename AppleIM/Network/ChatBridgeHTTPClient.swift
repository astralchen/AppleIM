//
//  ChatBridgeHTTPClient.swift
//  AppleIM
//
//  轻量 HTTP JSON 客户端
//

import Foundation

/// ChatBridge HTTP 错误。
///
/// 只暴露脱敏后的分类，避免把 URL、token、请求体或消息明文带到上层。
nonisolated enum ChatBridgeHTTPError: Error, Equatable, Sendable {
    /// 网络不可达
    case offline
    /// 请求超时
    case timeout
    /// HTTP 状态码不可接受
    case unacceptableStatus(Int)
    /// 响应不是 HTTP 响应
    case invalidResponse
    /// 服务端确认缺失或响应无法形成业务 ack
    case ackMissing
    /// 未知错误
    case unknown
}

/// JSON POST 客户端边界。
nonisolated protocol ChatBridgeHTTPPosting: Sendable {
    /// 发送 JSON POST 请求并解码响应。
    func postJSON<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        path: String,
        body: Request,
        responseType: Response.Type
    ) async throws -> Response
}

/// 基于 URLSession 的 ChatBridge HTTP 客户端。
///
/// `URLSession` 可安全跨并发任务使用；encoder/decoder 仅在请求方法内部顺序访问。
nonisolated final class ChatBridgeHTTPClient: ChatBridgeHTTPPosting, @unchecked Sendable {
    /// 客户端配置
    nonisolated struct Configuration: Sendable {
        /// 服务端基础 URL
        let baseURL: URL
        /// 鉴权 token provider
        let authTokenProvider: @Sendable () async -> String?
        /// 请求超时时间
        let timeoutSeconds: TimeInterval

        init(
            baseURL: URL,
            authTokenProvider: @escaping @Sendable () async -> String? = { nil },
            timeoutSeconds: TimeInterval = 15
        ) {
            self.baseURL = baseURL
            self.authTokenProvider = authTokenProvider
            self.timeoutSeconds = max(1, timeoutSeconds)
        }
    }

    private let configuration: Configuration
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    nonisolated init(configuration: Configuration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func postJSON<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        path: String,
        body: Request,
        responseType: Response.Type
    ) async throws -> Response {
        var request = URLRequest(url: endpointURL(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = await configuration.authTokenProvider(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            request.httpBody = try encoder.encode(body)
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ChatBridgeHTTPError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ChatBridgeHTTPError.unacceptableStatus(httpResponse.statusCode)
            }

            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw ChatBridgeHTTPError.ackMissing
            }
        } catch let error as ChatBridgeHTTPError {
            throw error
        } catch let error as URLError {
            throw Self.httpError(from: error)
        } catch {
            throw ChatBridgeHTTPError.unknown
        }
    }

    private func endpointURL(path: String) -> URL {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return normalizedPath
            .split(separator: "/")
            .reduce(configuration.baseURL) { url, component in
                url.appendingPathComponent(String(component))
            }
    }

    private static func httpError(from error: URLError) -> ChatBridgeHTTPError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
            return .offline
        case .timedOut:
            return .timeout
        default:
            return .unknown
        }
    }
}
