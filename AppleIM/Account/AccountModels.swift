//
//  AccountModels.swift
//  AppleIM
//
//  本地模拟账号模型
//

import Foundation

/// 本地模拟账号记录
///
/// 用于开发和 UI 测试环境的账号目录，密码以明文形式存放在本地模拟数据中。
nonisolated struct MockAccount: Codable, Equatable, Sendable {
    /// 用户 ID
    let userID: UserID
    /// 登录名或账号标识
    let loginName: String
    /// 本地模拟密码
    let password: String
    /// 展示昵称
    let displayName: String
    /// 手机号
    let mobile: String?
    /// 头像 URL
    let avatarURL: String?

    /// 编解码字段名
    enum CodingKeys: String, CodingKey {
        case userID
        case loginName
        case password
        case displayName
        case mobile
        case avatarURL
    }

    init(
        userID: UserID,
        loginName: String,
        password: String,
        displayName: String,
        mobile: String? = nil,
        avatarURL: String? = nil
    ) {
        self.userID = userID
        self.loginName = loginName
        self.password = password
        self.displayName = displayName
        self.mobile = mobile
        self.avatarURL = avatarURL
    }

    /// 从持久化 JSON 解码账号记录
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userID = UserID(rawValue: try container.decode(String.self, forKey: .userID))
        self.loginName = try container.decode(String.self, forKey: .loginName)
        self.password = try container.decode(String.self, forKey: .password)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.mobile = try container.decodeIfPresent(String.self, forKey: .mobile)
        self.avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
    }

    /// 将强类型用户 ID 编码为可持久化的原始字符串
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID.rawValue, forKey: .userID)
        try container.encode(loginName, forKey: .loginName)
        try container.encode(password, forKey: .password)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(mobile, forKey: .mobile)
        try container.encodeIfPresent(avatarURL, forKey: .avatarURL)
    }
}

/// 当前登录会话
///
/// 保存登录成功后的用户身份、展示信息和本地会话令牌。
nonisolated struct AccountSession: Codable, Equatable, Sendable {
    /// 用户 ID
    let userID: UserID
    /// 展示昵称
    let displayName: String
    /// 头像 URL
    let avatarURL: String?
    /// 本地会话令牌
    let token: String
    /// 登录时间戳
    let loggedInAt: Int64

    /// 编解码字段名
    enum CodingKeys: String, CodingKey {
        case userID
        case displayName
        case avatarURL
        case token
        case loggedInAt
    }

    /// 初始化登录会话
    init(userID: UserID, displayName: String, avatarURL: String? = nil, token: String, loggedInAt: Int64) {
        self.userID = userID
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.token = token
        self.loggedInAt = loggedInAt
    }

    /// 从持久化 JSON 解码登录会话
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userID = UserID(rawValue: try container.decode(String.self, forKey: .userID))
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        self.token = try container.decode(String.self, forKey: .token)
        self.loggedInAt = try container.decode(Int64.self, forKey: .loggedInAt)
    }

    /// 将强类型用户 ID 编码为可持久化的原始字符串
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID.rawValue, forKey: .userID)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(avatarURL, forKey: .avatarURL)
        try container.encode(token, forKey: .token)
        try container.encode(loggedInAt, forKey: .loggedInAt)
    }
}
