//
//  AccountLifecycleService.swift
//  AppleIM
//
//  账号生命周期流程协调
//

import Foundation

/// App 层账号生命周期服务。
@MainActor
final class AccountLifecycleService {
    private let sessionStore: any AccountSessionStore

    init(sessionStore: any AccountSessionStore) {
        self.sessionStore = sessionStore
    }

    /// 结束当前登录会话，并尽力关闭账号连接。
    func endSession(closeConnections: () async throws -> Void) async {
        sessionStore.clearSession()
        try? await closeConnections()
    }

    /// 删除当前账号本地数据后结束登录会话。
    ///
    /// 删除失败时向调用方抛出错误，保留现有登录态，避免用户误以为本地数据已清理。
    func deleteLocalDataThenEndSession(
        deleteLocalData: () async throws -> Void,
        closeConnections: () async throws -> Void
    ) async throws {
        try await deleteLocalData()
        await endSession(closeConnections: closeConnections)
    }
}
