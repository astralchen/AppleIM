//
//  ContactStoreModels.swift
//  AppleIM
//
//  通讯录存储模型
//

import Foundation

/// 联系人 ID
nonisolated struct ContactID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }
}

/// 联系人类型
nonisolated enum ContactType: Int, Codable, Equatable, Hashable, Sendable {
    /// 好友
    case friend = 1
    /// 群聊
    case group = 2
    /// 公众号
    case service = 3
    /// 系统账号
    case system = 4
    /// 陌生人
    case stranger = 5

    init?(mockValue: String) {
        switch mockValue {
        case "friend":
            self = .friend
        case "group":
            self = .group
        case "service":
            self = .service
        case "system":
            self = .system
        case "stranger":
            self = .stranger
        default:
            return nil
        }
    }

    var conversationType: ConversationType? {
        switch self {
        case .friend:
            .single
        case .group:
            .group
        case .service, .system, .stranger:
            nil
        }
    }
}

/// 联系人记录
nonisolated struct ContactRecord: Equatable, Sendable {
    let contactID: ContactID
    let userID: UserID
    let wxid: String
    let nickname: String
    let remark: String?
    let avatarURL: String?
    let type: ContactType
    let isStarred: Bool
    let isBlocked: Bool
    let isDeleted: Bool
    let source: Int?
    let extraJSON: String?
    let updatedAt: Int64
    let createdAt: Int64

    var displayName: String {
        if let remark, !remark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return remark
        }

        if !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nickname
        }

        return wxid
    }
}

/// 通讯录存储错误
nonisolated enum ContactStoreError: Error, Equatable, Sendable {
    case invalidContactType(Int)
    case contactNotFound(ContactID)
    case unsupportedContactType(ContactType)
}
