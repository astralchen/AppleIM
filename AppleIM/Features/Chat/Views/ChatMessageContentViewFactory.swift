//
//  ChatMessageContentViewFactory.swift
//  AppleIM
//

import UIKit

/// 可插拔消息内容视图
@MainActor
protocol ChatMessageContentView: AnyObject {
    func configure(
        row: ChatMessageRowState,
        style: ChatMessageContentStyle,
        actions: ChatMessageCellActions
    )
}

/// 消息内容视图工厂
@MainActor
final class ChatMessageContentViewFactory {
    func view(
        for kind: ChatMessageContentKind,
        reusing existingView: (UIView & ChatMessageContentView)?
    ) -> UIView & ChatMessageContentView {
        switch kind {
        case .text:
            if let textView = existingView as? TextMessageContentView {
                return textView
            }
            return TextMessageContentView()
        case .revoked:
            if let revokedView = existingView as? RevokedMessageContentView {
                return revokedView
            }
            return RevokedMessageContentView()
        case .file:
            if let fileView = existingView as? FileMessageContentView {
                return fileView
            }
            return FileMessageContentView()
        case .image, .video:
            if let mediaView = existingView as? MediaMessageContentView {
                return mediaView
            }
            return MediaMessageContentView()
        case .voice:
            if let voiceView = existingView as? VoiceMessageContentView {
                return voiceView
            }
            return VoiceMessageContentView()
        case .emoji:
            if let emojiView = existingView as? EmojiMessageContentView {
                return emojiView
            }
            return EmojiMessageContentView()
        }
    }
}
