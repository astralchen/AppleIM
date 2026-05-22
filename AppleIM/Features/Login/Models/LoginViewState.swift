//
//  LoginViewState.swift
//  AppleIM
//
//  登录页状态
//

import Foundation

/// 登录页 UI 状态
nonisolated struct LoginViewState: Equatable, Sendable {
    /// 账号、手机号或其他登录标识
    var accountIdentifier = ""
    /// 密码输入
    var password = ""
    /// 当前错误提示
    var errorMessage: String?
    /// 是否正在提交登录请求
    var isLoading = false

    /// 登录按钮是否可提交
    var canSubmit: Bool {
        !accountIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && !isLoading
    }
}
