//
//  NetworkRecoveryCoordinator.swift
//  AppleIM
//
//  网络恢复协调器
//  监听网络状态变化，网络恢复时自动重试失败的消息

import Combine
import Foundation
import Network

/// 网络连接监控协议
@MainActor
protocol NetworkConnectivityMonitoring: AnyObject {
    /// 网络可达性发布器
    var isReachablePublisher: AnyPublisher<Bool, Never> { get }
    /// 当前是否可达
    var currentIsReachable: Bool { get }

    /// 开始监控
    func start()
    /// 停止监控
    func stop()
}

/// 基于 NWPathMonitor 的网络连接监控器
@MainActor
final class NWPathConnectivityMonitor: NetworkConnectivityMonitoring {
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.sondra.AppleIM.network-monitor")
    private let subject: CurrentValueSubject<Bool, Never>
    private var isStarted = false

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        self.subject = CurrentValueSubject(false)
    }

    var isReachablePublisher: AnyPublisher<Bool, Never> {
        subject.eraseToAnyPublisher()
    }

    var currentIsReachable: Bool {
        subject.value
    }

    /// 开始监控网络状态
    func start() {
        guard !isStarted else { return }

        isStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.subject.send(path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }

    /// 停止监控网络状态
    func stop() {
        guard isStarted else { return }

        isStarted = false
        monitor.cancel()
    }

    deinit {
        monitor.cancel()
    }
}

/// 网络恢复协调器
///
/// 监听网络状态变化，当网络从不可达变为可达时，自动触发失败消息的重试
/// 使用 pending_job 表管理待重试的任务
@MainActor
final class NetworkRecoveryCoordinator {
    private let userID: UserID
    private let storeProvider: ChatStoreProvider
    private let sendService: any MessageSendService
    private let mediaUploadService: any MediaUploadService
    private let monitor: any NetworkConnectivityMonitoring
    private let retryPolicy: MessageRetryPolicy
    private var cancellables: Set<AnyCancellable> = []
    private var recoveryTask: Task<Void, Never>?

    /// 最后一次运行结果
    private(set) var lastRunResult: PendingMessageRetryRunResult?

    init(
        userID: UserID,
        storeProvider: ChatStoreProvider,
        sendService: any MessageSendService,
        mediaUploadService: any MediaUploadService = MockMediaUploadService(),
        monitor: any NetworkConnectivityMonitoring = NWPathConnectivityMonitor(),
        retryPolicy: MessageRetryPolicy = MessageRetryPolicy()
    ) {
        self.userID = userID
        self.storeProvider = storeProvider
        self.sendService = sendService
        self.mediaUploadService = mediaUploadService
        self.monitor = monitor
        self.retryPolicy = retryPolicy
    }

    /// 启动网络恢复协调器
    ///
    /// 订阅网络状态变化，网络恢复时自动触发重试
    func start() {
        monitor.isReachablePublisher
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                self?.runDueJobs()
            }
            .store(in: &cancellables)

        monitor.start()

        if monitor.currentIsReachable {
            runDueJobs()
        }
    }

    /// 停止网络恢复协调器
    func stop() {
        recoveryTask?.cancel()
        recoveryTask = nil
        cancellables.removeAll()
        monitor.stop()
    }

    /// 当网络可达时运行待处理任务
    ///
    /// 用于应用前台时主动触发重试
    func runDueJobsWhenReachable() {
        guard monitor.currentIsReachable else { return }

        runDueJobs()
    }

    /// 运行待处理任务
    ///
    /// 防止重复运行，同一时间只允许一个重试任务
    private func runDueJobs() {
        guard recoveryTask == nil else { return }

        recoveryTask = Task { [userID, storeProvider, sendService, mediaUploadService, retryPolicy, weak self] in
            do {
                let repository = try await storeProvider.repository()
                let runner = PendingMessageRetryRunner(
                    userID: userID,
                    messageRepository: repository,
                    pendingJobRepository: repository,
                    sendService: sendService,
                    mediaUploadService: mediaUploadService,
                    retryPolicy: retryPolicy
                )
                let result = try await runner.runDueJobs()
                await MainActor.run {
                    self?.lastRunResult = result
                    self?.recoveryTask = nil
                }
            } catch {
                await MainActor.run {
                    self?.recoveryTask = nil
                }
            }
        }
    }
}
