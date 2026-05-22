//
//  HTTPClient.swift
//  AppleIM
//
//  轻量 HTTP JSON 客户端
//

import Foundation

/// HTTP 客户端错误。
///
/// 只暴露脱敏后的分类，避免把 URL、token、请求体或消息明文带到上层。
nonisolated enum HTTPClientError: Error, Equatable, Sendable {
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

/// HTTP 客户端边界，当前提供 JSON POST 能力。
nonisolated protocol HTTPClient: Sendable {
    /// 发送 JSON POST 请求并解码响应。
    func sendJSON<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ body: Request,
        to path: String,
        decoding responseType: Response.Type
    ) async throws -> Response
}

/// 带 token 刷新的一次性重放 HTTP 客户端包装器。
///
/// 只在服务端返回 401 时触发刷新；刷新成功后重放原请求一次，避免无限循环。
nonisolated struct TokenRefreshingHTTPClient: HTTPClient {
    private let httpClient: any HTTPClient
    private let authTokenRefresher: @Sendable () async -> String?

    init(
        httpClient: any HTTPClient,
        authTokenRefresher: @escaping @Sendable () async -> String?
    ) {
        self.httpClient = httpClient
        self.authTokenRefresher = authTokenRefresher
    }

    func sendJSON<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ body: Request,
        to path: String,
        decoding responseType: Response.Type
    ) async throws -> Response {
        do {
            return try await httpClient.sendJSON(body, to: path, decoding: responseType)
        } catch let error as HTTPClientError {
            guard case .unacceptableStatus(401) = error else {
                throw error
            }

            guard let refreshedToken = await authTokenRefresher(), !refreshedToken.isEmpty else {
                throw error
            }

            return try await httpClient.sendJSON(body, to: path, decoding: responseType)
        }
    }
}

/// 基于 URLSession 的 HTTP 客户端。
///
/// ## Sendable 审计
///
/// 保留 `@unchecked Sendable` 的原因：
/// - `URLSession` 未在当前部署目标完整标注 Sendable，但系统支持跨任务发起请求。
/// - 本类型只保存不可变配置和不可变 session 引用，不保存可变业务状态。
/// - JSON 编解码器在单次请求方法内部创建，不跨任务共享。
/// - 请求生命周期由调用方任务管理，取消语义交给 `URLSession.data(for:)`。
nonisolated final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable {
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

    nonisolated init(configuration: Configuration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func sendJSON<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ body: Request,
        to path: String,
        decoding responseType: Response.Type
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
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(body)
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HTTPClientError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw HTTPClientError.unacceptableStatus(httpResponse.statusCode)
            }

            do {
                let decoder = JSONDecoder()
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw HTTPClientError.ackMissing
            }
        } catch let error as HTTPClientError {
            throw error
        } catch let error as URLError {
            throw Self.httpError(from: error)
        } catch {
            throw HTTPClientError.unknown
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

    private static func httpError(from error: URLError) -> HTTPClientError {
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
