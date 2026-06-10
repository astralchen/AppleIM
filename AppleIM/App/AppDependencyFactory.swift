//
//  AppDependencyFactory.swift
//  AppleIM
//
//  App 依赖创建工厂
//

import Foundation

/// 当前登录账号的依赖容器工厂。
@MainActor
final class AppDependencyFactory {
    private let sessionStore: any AccountSessionStore

    init(sessionStore: any AccountSessionStore) {
        self.sessionStore = sessionStore
    }

    /// 创建当前账号的依赖容器。
    func makeDependencies(for session: AccountSession) throws -> AppDependencyContainer {
        try AppDependencyContainer(
            accountID: session.userID,
            accountAvatarURL: session.avatarURL,
            serverMessageSendConfiguration: makeServerMessageSendConfiguration(for: session)
        )
    }

    private func makeServerMessageSendConfiguration(for session: AccountSession) -> ServerMessageSendService.Configuration? {
        let environment = ProcessInfo.processInfo.environment
        guard
            let baseURLValue = environment["CHATBRIDGE_SERVER_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !baseURLValue.isEmpty,
            let baseURL = URL(string: baseURLValue)
        else {
            return nil
        }

        let timeoutSeconds = environment["CHATBRIDGE_SERVER_TIMEOUT_SECONDS"]
            .flatMap { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : TimeInterval(trimmed)
            }
            ?? 15
        let tokenActor = TokenRefreshActor(
            session: session,
            sessionStore: sessionStore,
            configuration: URLSessionHTTPClient.Configuration(
                baseURL: baseURL,
                authTokenProvider: { nil },
                timeoutSeconds: timeoutSeconds
            )
        )

        return ServerMessageSendService.Configuration.fromEnvironment(
            environment,
            authTokenProvider: {
                await tokenActor.validToken()
            },
            authTokenRefresher: {
                await tokenActor.refreshToken()
            }
        )
    }
}
