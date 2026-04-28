//
//  ChatViewModel.swift
//  AppleIM
//

import Combine
import Foundation

@MainActor
final class ChatViewModel {
    private let useCase: any ChatUseCase
    private let stateSubject: CurrentValueSubject<ChatViewState, Never>
    private var loadTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?

    var statePublisher: AnyPublisher<ChatViewState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var currentState: ChatViewState {
        stateSubject.value
    }

    init(useCase: any ChatUseCase, title: String) {
        self.useCase = useCase
        self.stateSubject = CurrentValueSubject(ChatViewState(title: title))
    }

    func load() {
        loadTask?.cancel()
        publish { state in
            state.phase = .loading
        }

        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let rows = try await useCase.loadInitialMessages()
                guard !Task.isCancelled else { return }

                publish { state in
                    state.phase = .loaded
                    state.rows = rows
                }
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to load messages")
                }
            }
        }
    }

    func sendText(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        sendTask?.cancel()
        sendTask = Task { [weak self] in
            guard let self else { return }

            do {
                for try await row in useCase.sendText(trimmedText) {
                    guard !Task.isCancelled else { return }
                    upsert(row)
                }
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to send message")
                }
            }
        }
    }

    func cancel() {
        loadTask?.cancel()
        sendTask?.cancel()
        loadTask = nil
        sendTask = nil
    }

    private func upsert(_ row: ChatMessageRowState) {
        publish { state in
            if let index = state.rows.firstIndex(where: { $0.id == row.id }) {
                state.rows[index] = row
            } else {
                state.rows.append(row)
            }

            state.phase = .loaded
        }
    }

    private func publish(_ update: (inout ChatViewState) -> Void) {
        var state = stateSubject.value
        update(&state)
        stateSubject.send(state)
    }
}
