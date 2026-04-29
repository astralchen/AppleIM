//
//  NetworkRecoveryCoordinator.swift
//  AppleIM
//

import Combine
import Foundation
import Network

@MainActor
protocol NetworkConnectivityMonitoring: AnyObject {
    var isReachablePublisher: AnyPublisher<Bool, Never> { get }
    var currentIsReachable: Bool { get }

    func start()
    func stop()
}

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

    func stop() {
        guard isStarted else { return }

        isStarted = false
        monitor.cancel()
    }

    deinit {
        monitor.cancel()
    }
}

@MainActor
final class NetworkRecoveryCoordinator {
    private let userID: UserID
    private let storeProvider: ChatStoreProvider
    private let sendService: any MessageSendService
    private let monitor: any NetworkConnectivityMonitoring
    private let retryPolicy: MessageRetryPolicy
    private var cancellables: Set<AnyCancellable> = []
    private var recoveryTask: Task<Void, Never>?

    private(set) var lastRunResult: PendingMessageRetryRunResult?

    init(
        userID: UserID,
        storeProvider: ChatStoreProvider,
        sendService: any MessageSendService,
        monitor: any NetworkConnectivityMonitoring = NWPathConnectivityMonitor(),
        retryPolicy: MessageRetryPolicy = MessageRetryPolicy()
    ) {
        self.userID = userID
        self.storeProvider = storeProvider
        self.sendService = sendService
        self.monitor = monitor
        self.retryPolicy = retryPolicy
    }

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

    func stop() {
        recoveryTask?.cancel()
        recoveryTask = nil
        cancellables.removeAll()
        monitor.stop()
    }

    func runDueJobsWhenReachable() {
        guard monitor.currentIsReachable else { return }

        runDueJobs()
    }

    private func runDueJobs() {
        guard recoveryTask == nil else { return }

        recoveryTask = Task { [userID, storeProvider, sendService, retryPolicy, weak self] in
            do {
                let repository = try await storeProvider.repository()
                let runner = PendingMessageRetryRunner(
                    userID: userID,
                    messageRepository: repository,
                    pendingJobRepository: repository,
                    sendService: sendService,
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
