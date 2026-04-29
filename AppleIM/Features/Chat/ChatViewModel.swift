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
    private var draftTask: Task<Void, Never>?
    private var mutationTask: Task<Void, Never>?

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
                async let rows = useCase.loadInitialMessages()
                async let draft = useCase.loadDraft()
                let loadedRows = try await rows
                let loadedDraft = try await draft ?? ""
                guard !Task.isCancelled else { return }

                publish { state in
                    state.phase = .loaded
                    state.rows = loadedRows
                    state.draftText = loadedDraft
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
                publish { state in
                    state.draftText = ""
                }

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

    func saveDraft(_ text: String) {
        publish { state in
            state.draftText = text
        }

        draftTask?.cancel()
        draftTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                try await useCase.saveDraft(text)
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to save draft")
                }
            }
        }
    }

    func flushDraft(_ text: String) {
        publish { state in
            state.draftText = text
        }

        draftTask?.cancel()
        let useCase = self.useCase
        draftTask = Task {
            try? await useCase.saveDraft(text)
        }
    }

    func resend(messageID: MessageID) {
        mutationTask?.cancel()
        mutationTask = Task { [weak self] in
            guard let self else { return }

            do {
                for try await row in useCase.resend(messageID: messageID) {
                    guard !Task.isCancelled else { return }
                    upsert(row)
                }
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to resend message")
                }
            }
        }
    }

    func delete(messageID: MessageID) {
        mutationTask?.cancel()
        mutationTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await useCase.delete(messageID: messageID)
                guard !Task.isCancelled else { return }

                publish { state in
                    state.rows.removeAll { $0.id == messageID }
                    state.phase = .loaded
                }
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to delete message")
                }
            }
        }
    }

    func revoke(messageID: MessageID) {
        mutationTask?.cancel()
        mutationTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await useCase.revoke(messageID: messageID)
                let rows = try await useCase.loadInitialMessages()
                guard !Task.isCancelled else { return }

                publish { state in
                    state.rows = rows
                    state.phase = .loaded
                }
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to revoke message")
                }
            }
        }
    }

    func cancel() {
        loadTask?.cancel()
        sendTask?.cancel()
        draftTask?.cancel()
        mutationTask?.cancel()
        loadTask = nil
        sendTask = nil
        draftTask = nil
        mutationTask = nil
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
