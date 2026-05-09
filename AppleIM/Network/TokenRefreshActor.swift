//
//  TokenRefreshActor.swift
//  AppleIM
//
//  服务端 token 刷新协调器
//

import Foundation

/// Token provider 边界。
nonisolated protocol AuthTokenProviding: Sendable {
    /// 当前可用 token。
    func validToken() async -> String?

    /// 主动刷新 token。
    func refreshToken() async -> String?
}

/// 服务端 token 刷新请求。
nonisolated struct ServerTokenRefreshRequest: Codable, Equatable, Sendable {
    /// 当前 access token。
    let token: String

    enum CodingKeys: String, CodingKey {
        case token
    }
}

/// 服务端 token 刷新响应。
nonisolated struct ServerTokenRefreshResponse: Codable, Equatable, Sendable {
    /// 新 access token。
    let token: String

    enum CodingKeys: String, CodingKey {
        case token
    }
}

/// 账号 token 刷新 actor。
///
/// 负责合并并发刷新、更新内存会话，并在刷新成功后持久化新的 token。
actor TokenRefreshActor: AuthTokenProviding {
    /// 默认 token 刷新路径；真实接口确认后集中调整。
    private static let refreshPath = "/v1/auth/token/refresh"

    private var session: AccountSession
    private let sessionStore: any AccountSessionStore
    private let httpClient: any ChatBridgeHTTPPosting
    private var refreshTask: Task<AccountSession?, Never>?

    init(
        session: AccountSession,
        sessionStore: any AccountSessionStore,
        httpClient: any ChatBridgeHTTPPosting
    ) {
        self.session = session
        self.sessionStore = sessionStore
        self.httpClient = httpClient
    }

    init(
        session: AccountSession,
        sessionStore: any AccountSessionStore,
        configuration: ChatBridgeHTTPClient.Configuration
    ) {
        self.init(
            session: session,
            sessionStore: sessionStore,
            httpClient: ChatBridgeHTTPClient(configuration: configuration)
        )
    }

    func validToken() async -> String? {
        nonEmptyValue(session.token)
    }

    func refreshToken() async -> String? {
        if let refreshTask {
            return await refreshTask.value?.token
        }

        guard let currentToken = nonEmptyValue(session.token) else {
            return nil
        }

        let currentSession = session
        let sessionStore = sessionStore
        let httpClient = httpClient
        let task = Task<AccountSession?, Never> {
            do {
                let response = try await httpClient.postJSON(
                    path: Self.refreshPath,
                    body: ServerTokenRefreshRequest(token: currentToken),
                    responseType: ServerTokenRefreshResponse.self
                )
                guard let refreshedToken = Self.nonEmptyValue(response.token) else {
                    return nil
                }

                let refreshedSession = currentSession.replacingToken(refreshedToken)
                try sessionStore.saveSession(refreshedSession)
                return refreshedSession
            } catch {
                return nil
            }
        }

        refreshTask = task
        let refreshedSession = await task.value
        refreshTask = nil

        if let refreshedSession {
            session = refreshedSession
        }

        return refreshedSession?.token
    }

    private func nonEmptyValue(_ value: String?) -> String? {
        Self.nonEmptyValue(value)
    }

    nonisolated private static func nonEmptyValue(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated private extension AccountSession {
    func replacingToken(_ token: String) -> AccountSession {
        AccountSession(
            userID: userID,
            displayName: displayName,
            avatarURL: avatarURL,
            token: token,
            loggedInAt: loggedInAt
        )
    }
}
