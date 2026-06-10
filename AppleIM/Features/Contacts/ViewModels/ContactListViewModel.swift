//
//  ContactListViewModel.swift
//  AppleIM
//
//  通讯录 ViewModel
//

import Combine
import Foundation

@MainActor
final class ContactListViewModel {
    private let service: any ContactListService
    private let stateSubject: CurrentValueSubject<ContactListViewState, Never>
    private var loadTask: Task<Void, Never>?
    private var openTask: Task<Void, Never>?
    private var simulatedProfileChangeTask: Task<Void, Never>?

    var statePublisher: AnyPublisher<ContactListViewState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var currentState: ContactListViewState {
        stateSubject.value
    }

    init(useCase: any ContactListService, initialState: ContactListViewState = ContactListViewState()) {
        self.service = useCase
        self.stateSubject = CurrentValueSubject(initialState)
    }

    func load() {
        load(query: stateSubject.value.query, showLoading: true)
    }

    func updateSearchQuery(_ query: String) {
        publish { state in
            state.query = query
        }
        load(query: query, showLoading: false)
    }

    func open(row: ContactListRowState, onOpenConversation: @escaping (ConversationListRowState) -> Void) {
        openTask?.cancel()
        openTask = Task { [weak self] in
            guard let self else { return }

            do {
                let conversation = try await service.openConversation(for: row.id)
                guard !Task.isCancelled else { return }
                onOpenConversation(conversation)
            } catch {
                publish { state in
                    state.phase = .failed("Unable to open contact")
                }
            }
        }
    }

    func simulateContactProfileChange() {
        simulatedProfileChangeTask?.cancel()
        let query = stateSubject.value.query
        simulatedProfileChangeTask = Task { [weak self] in
            guard let self else { return }

            do {
                _ = try await service.simulateContactProfileChange()
                guard !Task.isCancelled else { return }
                load(query: query, showLoading: false)
                simulatedProfileChangeTask = nil
            } catch {
                guard !Task.isCancelled else { return }
                publish { state in
                    state.phase = .failed("Unable to simulate contact profile change")
                }
                simulatedProfileChangeTask = nil
            }
        }
    }

    private func load(query: String, showLoading: Bool) {
        loadTask?.cancel()
        if showLoading {
            publish { state in
                state.phase = .loading
            }
        }

        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let nextState = try await service.loadContacts(query: query)
                guard !Task.isCancelled else { return }
                stateSubject.send(nextState)
                loadTask = nil
            } catch {
                guard !Task.isCancelled else { return }
                publish { state in
                    state.phase = .failed("Unable to load contacts")
                    state.groupRows = []
                    state.starredRows = []
                    state.contactRows = []
                }
                loadTask = nil
            }
        }
    }

    private func publish(_ update: (inout ContactListViewState) -> Void) {
        var state = stateSubject.value
        update(&state)
        stateSubject.send(state)
    }
}
