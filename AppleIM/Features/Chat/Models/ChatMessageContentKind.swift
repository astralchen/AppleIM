//
//  ChatMessageContentKind.swift
//  AppleIM
//
//  聊天消息内容类型
//

import Foundation

/// 聊天消息内容类型。
nonisolated enum ChatMessageContentKind: Equatable {
    case text
    case image
    case voice
    case video
    case file
    case emoji
    case revoked

    init(row: ChatMessageRowState) {
        switch row.content.kind {
        case .revoked:
            self = .revoked
        case .voice:
            self = .voice
        case .video:
            self = .video
        case .image:
            self = .image
        case .file:
            self = .file
        case .emoji:
            self = .emoji
        case .text:
            self = .text
        }
    }
}
