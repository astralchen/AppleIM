//
//  SearchViewModel.swift
//  AppleIM
//
//  Search UI state management.

import Combine
import Foundation

@MainActor
final class SearchViewModel {
    private let useCase: any SearchUseCase
    private let debounceMilliseconds: Int
    private let stateSubject: CurrentValueSubject<SearchViewState, Never>
    private let querySubject = PassthroughSubject<String, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    private var generation = 0

    var statePublisher: AnyPublisher<SearchViewState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var currentState: SearchViewState {
        stateSubject.value
    }

    init(
        useCase: any SearchUseCase,
        debounceMilliseconds: Int = 250,
        initialState: SearchViewState = SearchViewState()
    ) {
        self.useCase = useCase
        self.debounceMilliseconds = debounceMilliseconds
        self.stateSubject = CurrentValueSubject(initialState)
        bindQuery()
    }

    func setQuery(_ query: String) {
        publish { state in
            state.query = query
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.phase = .idle
                state.contacts = []
                state.conversations = []
                state.messages = []
            }
        }
        querySubject.send(query)
    }

    func rebuildIndex() {
        Task { [useCase] in
            try? await useCase.rebuildIndex()
        }
    }

    func cancel() {
        searchTask?.cancel()
        searchTask = nil
    }

    private func bindQuery() {
        querySubject
            .debounce(for: .milliseconds(debounceMilliseconds), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                self?.performSearch(query: query)
            }
            .store(in: &cancellables)
    }

    private func performSearch(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        generation += 1
        let currentGeneration = generation

        guard !trimmedQuery.isEmpty else {
            return
        }

        publish { state in
            state.phase = .loading
        }

        searchTask = Task { [weak self, useCase] in
            do {
                let results = try await useCase.search(query: trimmedQuery)
                guard !Task.isCancelled else { return }
                self?.publishResults(results, generation: currentGeneration)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.publishFailure(generation: currentGeneration)
            }
        }
    }

    private func publishResults(_ results: SearchResults, generation expectedGeneration: Int) {
        guard generation == expectedGeneration else {
            return
        }

        publish { state in
            state.phase = .loaded
            state.contacts = results.contacts.map(SearchResultRowState.init(record:))
            state.conversations = results.conversations.map(SearchResultRowState.init(record:))
            state.messages = results.messages.map(SearchResultRowState.init(record:))
        }
    }

    private func publishFailure(generation expectedGeneration: Int) {
        guard generation == expectedGeneration else {
            return
        }

        publish { state in
            state.phase = .failed("Unable to search")
            state.contacts = []
            state.conversations = []
            state.messages = []
        }
    }

    private func publish(_ update: (inout SearchViewState) -> Void) {
        var state = stateSubject.value
        update(&state)
        stateSubject.send(state)
    }
}
