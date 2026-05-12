//
//  AccountViewState.swift
//  AppleIM
//
//  账号页视图状态
//

import Foundation

/// 账号页操作
nonisolated enum AccountAction: Equatable, Sendable {
    /// 切换当前账号
    case switchAccount
    /// 退出当前账号
    case logOut
    /// 删除当前账号本地数据
    case deleteLocalData
}

/// 账号页展示状态
nonisolated struct AccountViewState: Equatable, Sendable {
    /// 展示昵称
    let displayName: String
    /// 当前用户 ID
    let userID: UserID
    /// 头像 URL
    let avatarURL: String?

    /// 初始化账号页状态
    init(displayName: String, userID: UserID, avatarURL: String?) {
        self.displayName = displayName
        self.userID = userID
        self.avatarURL = avatarURL
    }

    /// 从登录会话构造账号页状态
    init(session: AccountSession) {
        self.init(
            displayName: session.displayName,
            userID: session.userID,
            avatarURL: session.avatarURL
        )
    }
}
