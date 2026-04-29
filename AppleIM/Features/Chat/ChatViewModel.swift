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
    private var paginationTask: Task<Void, Never>?
    private let pageSize = 50

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
        paginationTask?.cancel()
        paginationTask = nil
        publish { state in
            state.phase = .loading
            state.isLoadingOlderMessages = false
            state.hasMoreOlderMessages = true
            state.paginationErrorMessage = nil
        }

        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                async let page = useCase.loadInitialMessages()
                async let draft = useCase.loadDraft()
                let loadedPage = try await page
                let loadedDraft = try await draft ?? ""
                guard !Task.isCancelled else { return }

                publish { state in
                    state.phase = .loaded
                    state.rows = loadedPage.rows
                    state.draftText = loadedDraft
                    state.hasMoreOlderMessages = loadedPage.hasMore
                    state.isLoadingOlderMessages = false
                    state.paginationErrorMessage = nil
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

    func loadOlderMessagesIfNeeded() {
        guard paginationTask == nil else { return }
        let state = stateSubject.value
        guard
            state.phase == .loaded,
            state.hasMoreOlderMessages,
            !state.isLoadingOlderMessages,
            let beforeSortSequence = state.rows.first?.sortSequence
        else {
            return
        }

        publish { state in
            state.isLoadingOlderMessages = true
            state.paginationErrorMessage = nil
        }

        paginationTask = Task { [weak self] in
            guard let self else { return }

            do {
                let page = try await useCase.loadOlderMessages(
                    beforeSortSequence: beforeSortSequence,
                    limit: pageSize
                )
                guard !Task.isCancelled else { return }

                publish { state in
                    let existingIDs = Set(state.rows.map(\.id))
                    let olderRows = page.rows.filter { !existingIDs.contains($0.id) }
                    state.rows = olderRows + state.rows
                    state.hasMoreOlderMessages = page.hasMore
                    state.isLoadingOlderMessages = false
                    state.paginationErrorMessage = nil
                    state.phase = .loaded
                }
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.isLoadingOlderMessages = false
                    state.paginationErrorMessage = "Unable to load older messages"
                }
            }

            paginationTask = nil
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

    func sendImage(data: Data, preferredFileExtension: String?) {
        sendTask?.cancel()
        sendTask = Task { [weak self] in
            guard let self else { return }

            do {
                publish { state in
                    state.draftText = ""
                }

                for try await row in useCase.sendImage(data: data, preferredFileExtension: preferredFileExtension) {
                    guard !Task.isCancelled else { return }
                    upsert(row)
                }
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to send image")
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
                let page = try await useCase.loadInitialMessages()
                guard !Task.isCancelled else { return }

                publish { state in
                    state.rows = page.rows
                    state.hasMoreOlderMessages = page.hasMore
                    state.isLoadingOlderMessages = false
                    state.paginationErrorMessage = nil
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
        paginationTask?.cancel()
        loadTask = nil
        sendTask = nil
        draftTask = nil
        mutationTask = nil
        paginationTask = nil
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
