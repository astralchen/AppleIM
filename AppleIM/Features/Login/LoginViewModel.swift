//
//  LoginViewModel.swift
//  AppleIM
//
//  登录页 ViewModel
//

import Combine
import Foundation

@MainActor
final class LoginViewModel {
    private let authService: any AccountAuthService
    private let sessionStore: any AccountSessionStore
    private let stateSubject: CurrentValueSubject<LoginViewState, Never>
    private let sessionSubject = PassthroughSubject<AccountSession, Never>()
    private var loginTask: Task<Void, Never>?

    var statePublisher: AnyPublisher<LoginViewState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var sessionPublisher: AnyPublisher<AccountSession, Never> {
        sessionSubject.eraseToAnyPublisher()
    }

    var currentState: LoginViewState {
        stateSubject.value
    }

    init(
        authService: any AccountAuthService,
        sessionStore: any AccountSessionStore,
        initialState: LoginViewState = LoginViewState()
    ) {
        self.authService = authService
        self.sessionStore = sessionStore
        self.stateSubject = CurrentValueSubject(initialState)
    }

    func updateAccountIdentifier(_ value: String) {
        publish { state in
            state.accountIdentifier = value
            state.errorMessage = nil
        }
    }

    func updatePassword(_ value: String) {
        publish { state in
            state.password = value
            state.errorMessage = nil
        }
    }

    func login() {
        guard !stateSubject.value.isLoading else {
            return
        }

        let identifier = stateSubject.value.accountIdentifier
        let password = stateSubject.value.password

        publish { state in
            state.isLoading = true
            state.errorMessage = nil
        }

        loginTask?.cancel()
        loginTask = Task { [weak self] in
            guard let self else { return }

            do {
                let session = try await authService.login(identifier: identifier, password: password)
                guard !Task.isCancelled else { return }
                try sessionStore.saveSession(session)
                publish { state in
                    state.isLoading = false
                }
                sessionSubject.send(session)
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.isLoading = false
                    state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Unable to log in."
                }
            }
        }
    }

    func cancel() {
        loginTask?.cancel()
        loginTask = nil
    }

    private func publish(_ update: (inout LoginViewState) -> Void) {
        var state = stateSubject.value
        update(&state)
        stateSubject.send(state)
    }
}
