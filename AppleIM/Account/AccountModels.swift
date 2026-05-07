//
//  AccountModels.swift
//  AppleIM
//
//  本地模拟账号模型
//

import Foundation

nonisolated struct MockAccount: Codable, Equatable, Sendable {
    let userID: UserID
    let loginName: String
    let password: String
    let displayName: String
    let mobile: String?
    let avatarURL: String?

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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userID = UserID(rawValue: try container.decode(String.self, forKey: .userID))
        self.loginName = try container.decode(String.self, forKey: .loginName)
        self.password = try container.decode(String.self, forKey: .password)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.mobile = try container.decodeIfPresent(String.self, forKey: .mobile)
        self.avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
    }

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

nonisolated struct AccountSession: Codable, Equatable, Sendable {
    let userID: UserID
    let displayName: String
    let avatarURL: String?
    let token: String
    let loggedInAt: Int64

    enum CodingKeys: String, CodingKey {
        case userID
        case displayName
        case avatarURL
        case token
        case loggedInAt
    }

    init(userID: UserID, displayName: String, avatarURL: String? = nil, token: String, loggedInAt: Int64) {
        self.userID = userID
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.token = token
        self.loggedInAt = loggedInAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userID = UserID(rawValue: try container.decode(String.self, forKey: .userID))
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        self.token = try container.decode(String.self, forKey: .token)
        self.loggedInAt = try container.decode(Int64.self, forKey: .loggedInAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID.rawValue, forKey: .userID)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(avatarURL, forKey: .avatarURL)
        try container.encode(token, forKey: .token)
        try container.encode(loggedInAt, forKey: .loggedInAt)
    }
}
