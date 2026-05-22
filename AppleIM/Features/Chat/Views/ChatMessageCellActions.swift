//
//  ChatMessageCellActions.swift
//  AppleIM
//

import UIKit

/// 聊天消息单元格动作集合
@MainActor
struct ChatMessageCellActions {
    let onRetry: (MessageID) -> Void
    let onDelete: (MessageID) -> Void
    let onRevoke: (MessageID) -> Void
    let onReeditRevokedText: (MessageID, String) -> Void
    let onPlayVoice: (ChatMessageRowState) -> Void
    let onPlayVideo: (ChatMessageRowState) -> Void

    static let empty = ChatMessageCellActions(
        onRetry: { _ in },
        onDelete: { _ in },
        onRevoke: { _ in },
        onReeditRevokedText: { _, _ in },
        onPlayVoice: { _ in },
        onPlayVideo: { _ in }
    )
}
