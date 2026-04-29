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
    /// UseCase 依赖
    private let useCase: any ConversationListUseCase
    /// 状态发布器
    private let stateSubject: CurrentValueSubject<ConversationListViewState, Never>
    /// 加载任务
    private var loadTask: Task<Void, Never>?

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
        initialState: ConversationListViewState = ConversationListViewState()
    ) {
        self.useCase = useCase
        self.stateSubject = CurrentValueSubject(initialState)
    }

    func load() {
        loadTask?.cancel()
        publish { state in
            state.phase = .loading
        }

        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let rows = try await useCase.loadConversations()
                guard !Task.isCancelled else { return }

                publish { state in
                    state.phase = .loaded
                    state.rows = rows
                }
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to load conversations")
                }
            }
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
    }

    private func publish(_ update: (inout ConversationListViewState) -> Void) {
        var state = stateSubject.value
        update(&state)
        stateSubject.send(state)
    }
}
