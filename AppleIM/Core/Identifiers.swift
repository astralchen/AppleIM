//
//  Identifiers.swift
//  AppleIM
//
//  核心标识符类型定义
//  所有 ID 类型都满足 Sendable 协议，可以安全地跨并发域传递

import Foundation

/// 用户 ID
///
/// 用于唯一标识一个用户账号
/// 满足 Sendable 协议，可在 actor 之间安全传递
/// 支持字符串字面量初始化，例如：`let id: UserID = "user_123"`
nonisolated struct UserID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    /// 原始字符串值
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }
}

/// 会话 ID
///
/// 用于唯一标识一个聊天会话（单聊、群聊、系统会话）
/// 满足 Sendable 协议，可在 actor 之间安全传递
/// 支持字符串字面量初始化，例如：`let id: ConversationID = "conv_456"`
nonisolated struct ConversationID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    /// 原始字符串值
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }
}

/// 消息 ID
///
/// 用于唯一标识一条消息
/// 满足 Sendable 协议，可在 actor 之间安全传递
/// 支持字符串字面量初始化，例如：`let id: MessageID = "msg_789"`
nonisolated struct MessageID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    /// 原始字符串值
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }
}
