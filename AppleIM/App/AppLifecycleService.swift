//
//  AppLifecycleService.swift
//  AppleIM
//
//  应用生命周期副作用协调
//

import Foundation

/// 应用运行时配置。
@MainActor
struct AppRuntimeConfiguration {
    /// 当前是否处于 UI 自动化测试模式。
    let isUITesting: Bool
    /// 服务端消息发送配置。
    let serverMessageSendConfiguration: ServerMessageSendService.Configuration?

    static func current(
        serverMessageSendConfiguration: ServerMessageSendService.Configuration?
    ) -> AppRuntimeConfiguration {
        AppRuntimeConfiguration(
            isUITesting: AppUITestConfiguration.current != nil,
            serverMessageSendConfiguration: serverMessageSendConfiguration
        )
    }
}

/// App 级生命周期副作用服务。
@MainActor
final class AppLifecycleService {
    private let userID: UserID
    private let storeProvider: ChatStoreProvider
    private let localNotificationManager: any LocalNotificationManaging
    private let networkRecoveryCoordinator: any NetworkRecoveryCoordinating
    private var didStartNetworkRecovery = false

    /// 最近一次后台数据修复报告。
    private(set) var lastDataRepairReport: DataRepairReport?

    init(
        userID: UserID,
        storeProvider: ChatStoreProvider,
        localNotificationManager: any LocalNotificationManaging,
        networkRecoveryCoordinator: any NetworkRecoveryCoordinating
    ) {
        self.userID = userID
        self.storeProvider = storeProvider
        self.localNotificationManager = localNotificationManager
        self.networkRecoveryCoordinator = networkRecoveryCoordinator
    }

    /// 启动网络恢复监听。
    func startNetworkRecovery() {
        guard !didStartNetworkRecovery else { return }

        didStartNetworkRecovery = true
        networkRecoveryCoordinator.start()
    }

    /// 请求本地通知权限。
    func requestLocalNotificationAuthorization() {
        let localNotificationManager = localNotificationManager
        Task {
            _ = try? await localNotificationManager.requestAuthorization()
        }
    }

    /// 网络可达时运行到期待处理任务。
    func runDueJobsWhenNetworkIsReachable() {
        networkRecoveryCoordinator.runDueJobsWhenReachable()
    }

    /// 刷新应用角标。
    func refreshApplicationBadge() {
        let storeProvider = storeProvider
        let userID = userID
        Task {
            guard let repository = try? await storeProvider.repository() else {
                return
            }

            _ = try? await repository.refreshApplicationBadge(userID: userID)
        }
    }

    /// 运行启动数据修复。
    func runStartupDataRepair() {
        let storeProvider = storeProvider
        Task { [weak self] in
            guard let repairService = try? await storeProvider.dataRepairService() else {
                return
            }

            guard let report = await repairService.runStartupIfNeeded() else {
                return
            }

            await MainActor.run {
                self?.lastDataRepairReport = report
            }
        }
    }
}
