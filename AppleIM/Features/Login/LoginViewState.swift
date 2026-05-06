//
//  LoginViewState.swift
//  AppleIM
//
//  登录页状态
//

import Foundation

nonisolated struct LoginViewState: Equatable, Sendable {
    var accountIdentifier = ""
    var password = ""
    var errorMessage: String?
    var isLoading = false

    var canSubmit: Bool {
        !accountIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && !isLoading
    }
}
