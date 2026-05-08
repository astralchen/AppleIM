//
//  LoginViewModel.swift
//  AppleIM
//
//  登录页 ViewModel
//

import Combine
import Foundation

/// 登录页 ViewModel
///
/// ## 职责
///
/// 1. 管理登录 UI 状态（空闲、加载中、错误）
/// 2. 处理用户输入（账号、密码）
/// 3. 执行登录并保存会话
/// 4. 通过 Combine 发布状态变化和登录成功事件
///
/// ## 并发安全
///
/// - 标记为 `@MainActor`，所有方法和属性访问都在主线程
/// - 使用 `Task` 管理异步登录操作
///
/// ## 使用流程
///
/// 1. 订阅 `statePublisher` 更新 UI
/// 2. 订阅 `sessionPublisher` 接收登录成功事件
/// 3. 调用 `updateAccountIdentifier` 和 `updatePassword` 更新输入
/// 4. 调用 `login()` 执行登录
@MainActor
final class LoginViewModel {
    /// 账号认证服务
    private let authService: any AccountAuthService
    /// 会话存储
    private let sessionStore: any AccountSessionStore
    /// 状态发布器
    private let stateSubject: CurrentValueSubject<LoginViewState, Never>
    /// 会话发布器（登录成功时发布）
    private let sessionSubject = PassthroughSubject<AccountSession, Never>()
    /// 登录任务
    private var loginTask: Task<Void, Never>?

    /// 状态发布器
    var statePublisher: AnyPublisher<LoginViewState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    /// 会话发布器
    var sessionPublisher: AnyPublisher<AccountSession, Never> {
        sessionSubject.eraseToAnyPublisher()
    }

    /// 当前状态
    var currentState: LoginViewState {
        stateSubject.value
    }

    /// 初始化
    ///
    /// - Parameters:
    ///   - authService: 账号认证服务
    ///   - sessionStore: 会话存储
    ///   - initialState: 初始状态
    init(
        authService: any AccountAuthService,
        sessionStore: any AccountSessionStore,
        initialState: LoginViewState = LoginViewState()
    ) {
        self.authService = authService
        self.sessionStore = sessionStore
        self.stateSubject = CurrentValueSubject(initialState)
    }

    /// 更新账号标识
    ///
    /// 清空错误消息
    ///
    /// - Parameter value: 账号标识（用户名或手机号）
    func updateAccountIdentifier(_ value: String) {
        publish { state in
            state.accountIdentifier = value
            state.errorMessage = nil
        }
    }

    /// 更新密码
    ///
    /// 清空错误消息
    ///
    /// - Parameter value: 密码
    func updatePassword(_ value: String) {
        publish { state in
            state.password = value
            state.errorMessage = nil
        }
    }

    /// 执行登录
    ///
    /// 流程：
    /// 1. 检查是否正在加载
    /// 2. 更新状态为加载中
    /// 3. 调用认证服务登录
    /// 4. 保存会话到存储
    /// 5. 通过 `sessionPublisher` 发布登录成功事件
    /// 6. 如果失败，更新错误消息
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

    /// 取消登录
    ///
    /// 取消正在进行的登录任务
    func cancel() {
        loginTask?.cancel()
        loginTask = nil
    }

    /// 发布状态更新
    ///
    /// - Parameter update: 状态更新闭包
    private func publish(_ update: (inout LoginViewState) -> Void) {
        var state = stateSubject.value
        update(&state)
        stateSubject.send(state)
    }
}
