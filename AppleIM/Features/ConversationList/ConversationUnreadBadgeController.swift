//
//  ConversationUnreadBadgeController.swift
//  AppleIM
//
//  账号级消息未读数协调器
//

import Combine
import Foundation

/// 消息未读徽标文本格式化工具。
nonisolated enum ConversationUnreadBadgeFormatter {
    /// 将未读数量转换为 Apple Messages 风格的徽标文本。
    static func text(for count: Int) -> String? {
        guard count > 0 else {
            return nil
        }

        return count > 99 ? "99+" : "\(count)"
    }
}

/// 监听会话变更并发布账号级未读徽标文本。
@MainActor
final class ConversationUnreadBadgeController {
    /// 当前账号 ID。
    private let userID: UserID
    /// 聊天存储提供者。
    private let storeProvider: ChatStoreProvider
    /// 会话变更通知中心。
    private let notificationCenter: NotificationCenter
    /// 未读徽标发布源。
    private let badgeSubject = CurrentValueSubject<String?, Never>(nil)
    /// Combine 订阅集合。
    private var cancellables = Set<AnyCancellable>()
    /// 当前刷新任务。
    private var refreshTask: Task<Void, Never>?
    /// 未读数观察启动任务。
    private var observationTask: Task<Void, Never>?

    /// UI 可订阅的未读徽标文本。
    var badgePublisher: AnyPublisher<String?, Never> {
        badgeSubject.eraseToAnyPublisher()
    }

    /// 初始化未读徽标协调器。
    init(
        userID: UserID,
        storeProvider: ChatStoreProvider,
        notificationCenter: NotificationCenter = .default
    ) {
        self.userID = userID
        self.storeProvider = storeProvider
        self.notificationCenter = notificationCenter
    }

    deinit {
        refreshTask?.cancel()
        observationTask?.cancel()
    }

    /// 启动监听并立即刷新一次未读数。
    func start() {
        guard cancellables.isEmpty else {
            refresh()
            return
        }

        notificationCenter.chatStoreConversationChangesPublisher()
            .filter { [userID] event in
                event.userID == userID
            }
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            }
            .store(in: &cancellables)

        startBadgeObservation()
        refresh()
    }

    private func startBadgeObservation() {
        observationTask?.cancel()
        let userID = userID
        let storeProvider = storeProvider
        observationTask = Task { [weak self] in
            do {
                let repository = try await storeProvider.repository()
                let publisher = try await repository.observeUnreadBadgeCount(for: userID)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    publisher
                        .map(ConversationUnreadBadgeFormatter.text(for:))
                        .replaceError(with: nil)
                        .sink { text in
                            self.badgeSubject.send(text)
                        }
                        .store(in: &self.cancellables)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.refresh()
                }
            }
        }
    }

    /// 主动刷新账号级未读数。
    func refresh() {
        refreshTask?.cancel()
        let userID = userID
        let storeProvider = storeProvider
        refreshTask = Task { [weak self] in
            do {
                let repository = try await storeProvider.repository()
                let unreadCount = try await repository.unreadConversationCount(for: userID)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.badgeSubject.send(ConversationUnreadBadgeFormatter.text(for: unreadCount))
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.badgeSubject.send(nil)
                }
            }
        }
    }
}
