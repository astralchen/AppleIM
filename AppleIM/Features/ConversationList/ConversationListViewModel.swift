//
//  ConversationListViewModel.swift
//  AppleIM
//
//  会话列表 ViewModel
//  负责会话列表的 UI 状态管理和数据加载

import Combine
import Foundation

/// 会话列表 ViewModel
///
/// 管理会话列表的加载状态和数据，通过 Combine 发布状态变化
@MainActor
final class ConversationListViewModel {
    private static let defaultPageSize = 50

    /// UseCase 依赖
    private let useCase: any ConversationListUseCase
    /// 每页加载数量
    private let pageSize: Int
    /// 状态发布器
    private let stateSubject: CurrentValueSubject<ConversationListViewState, Never>
    /// 加载任务
    private var loadTask: Task<Void, Never>?
    /// 分页加载任务
    private var loadMoreTask: Task<Void, Never>?
    /// 会话设置更新任务
    private var settingTask: Task<Void, Never>?
    /// 下一页偏移量
    private var nextOffset = 0

    /// 状态发布器，UI 订阅此 Publisher
    var statePublisher: AnyPublisher<ConversationListViewState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    /// 当前状态快照
    var currentState: ConversationListViewState {
        stateSubject.value
    }

    init(
        useCase: any ConversationListUseCase,
        initialState: ConversationListViewState = ConversationListViewState(),
        pageSize: Int = ConversationListViewModel.defaultPageSize
    ) {
        self.useCase = useCase
        self.pageSize = max(pageSize, 1)
        self.stateSubject = CurrentValueSubject(initialState)
    }

    func load() {
        loadTask?.cancel()
        loadMoreTask?.cancel()
        nextOffset = 0

        publish { state in
            state.phase = .loading
            state.rows = []
            state.isLoadingMore = false
            state.hasMoreRows = false
        }

        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let page = try await useCase.loadConversationPage(limit: pageSize, offset: 0)
                guard !Task.isCancelled else { return }

                publish { state in
                    state.phase = .loaded
                    state.rows = page.rows
                    state.hasMoreRows = page.hasMore
                    state.isLoadingMore = false
                }
                nextOffset = page.rows.count
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to load conversations")
                    state.isLoadingMore = false
                    state.hasMoreRows = false
                }
            }
        }
    }

    func loadNextPageIfNeeded(visibleRowID: ConversationID?) {
        let state = stateSubject.value
        guard
            state.phase == .loaded,
            state.hasMoreRows,
            !state.isLoadingMore,
            loadMoreTask == nil
        else {
            return
        }

        if let visibleRowID {
            guard let visibleIndex = state.rows.firstIndex(where: { $0.id == visibleRowID }) else {
                return
            }

            let thresholdIndex = max(state.rows.count - 10, 0)
            guard visibleIndex >= thresholdIndex else {
                return
            }
        }

        publish { state in
            state.isLoadingMore = true
        }

        let offset = nextOffset
        loadMoreTask = Task { [weak self] in
            guard let self else { return }

            do {
                let page = try await useCase.loadConversationPage(limit: pageSize, offset: offset)
                guard !Task.isCancelled else { return }

                publish { state in
                    state.phase = .loaded
                    state.rows.append(contentsOf: page.rows)
                    state.hasMoreRows = page.hasMore
                    state.isLoadingMore = false
                }
                nextOffset = offset + page.rows.count
                loadMoreTask = nil
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.isLoadingMore = false
                }
                loadMoreTask = nil
            }
        }
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) {
        updateConversationSetting {
            try await $0.setPinned(conversationID: conversationID, isPinned: isPinned)
        }
    }

    func setMuted(conversationID: ConversationID, isMuted: Bool) {
        updateConversationSetting {
            try await $0.setMuted(conversationID: conversationID, isMuted: isMuted)
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        loadMoreTask?.cancel()
        loadMoreTask = nil
        settingTask?.cancel()
        settingTask = nil
    }

    private func publish(_ update: (inout ConversationListViewState) -> Void) {
        var state = stateSubject.value
        update(&state)
        stateSubject.send(state)
    }

    private func updateConversationSetting(_ operation: @escaping @Sendable (any ConversationListUseCase) async throws -> Void) {
        settingTask?.cancel()
        settingTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await operation(useCase)
                guard !Task.isCancelled else { return }
                load()
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to update conversation")
                }
            }
        }
    }
}
