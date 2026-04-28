//
//  ConversationListViewModel.swift
//  AppleIM
//

import Combine
import Foundation

@MainActor
final class ConversationListViewModel {
    private let useCase: any ConversationListUseCase
    private let stateSubject: CurrentValueSubject<ConversationListViewState, Never>
    private var loadTask: Task<Void, Never>?

    var statePublisher: AnyPublisher<ConversationListViewState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

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
