//
//  ChatMessageRowMapper.swift
//  AppleIM
//
//  存储消息到聊天行状态的映射
//

import Foundation

/// 将存储层消息转换为聊天页行状态。
nonisolated struct ChatMessageRowMapper: Sendable {
    private static let revokeWindowSeconds: Int64 = 180

    private let userID: UserID
    private let currentUserAvatarURL: String?
    private let conversationAvatarURL: String?

    init(
        userID: UserID,
        currentUserAvatarURL: String?,
        conversationAvatarURL: String?
    ) {
        self.userID = userID
        self.currentUserAvatarURL = currentUserAvatarURL
        self.conversationAvatarURL = conversationAvatarURL
    }

    func row(from message: StoredMessage, uploadProgress: Double? = nil) -> ChatMessageRowState {
        let isOutgoing = message.senderID == userID
        let isRevoked = message.state.isRevoked
        let senderAvatarURL = isOutgoing ? currentUserAvatarURL : conversationAvatarURL
        let now = Self.currentTimestamp()

        return ChatMessageRowState(
            id: message.id,
            content: Self.rowContent(
                for: message,
                isOutgoing: isOutgoing,
                isRevoked: isRevoked
            ),
            sortSequence: message.timeline.sortSequence,
            sentAt: message.timeline.localTime,
            timeText: Self.timeText(from: message.timeline.localTime),
            statusText: isRevoked ? nil : Self.statusText(for: message),
            uploadProgress: uploadProgress,
            senderAvatarURL: senderAvatarURL,
            isOutgoing: isOutgoing,
            canRetry: isOutgoing
                && (message.type == .text || message.type == .image || message.type == .video || message.type == .emoji)
                && message.state.sendStatus == .failed
                && !isRevoked,
            canDelete: !message.state.isDeleted,
            canRevoke: Self.canRevoke(
                message,
                isOutgoing: isOutgoing,
                isRevoked: isRevoked,
                now: now
            )
        )
    }

    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }

    private static func canRevoke(
        _ message: StoredMessage,
        isOutgoing: Bool,
        isRevoked: Bool,
        now: Int64
    ) -> Bool {
        guard isOutgoing,
              message.state.sendStatus == .success,
              !isRevoked,
              !message.state.isDeleted,
              isRevocableMessageType(message.type) else {
            return false
        }

        return now - message.timeline.localTime <= revokeWindowSeconds
    }

    private static func isRevocableMessageType(_ type: MessageType) -> Bool {
        switch type {
        case .text, .image, .voice, .video, .file, .emoji:
            return true
        case .system, .revoked, .quote:
            return false
        }
    }

    private static func rowContent(
        for message: StoredMessage,
        isOutgoing: Bool,
        isRevoked: Bool
    ) -> ChatMessageRowContent {
        if isRevoked {
            let editableText = message.state.revokeEditableText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let allowsReedit = isOutgoing
                && message.type == .text
                && message.state.sendStatus == .success
                && editableText?.isEmpty == false
            return .revoked(
                ChatMessageRowContent.RevokedContent(
                    noticeText: message.state.revokeReplacementText ?? "你撤回了一条消息",
                    editableText: allowsReedit ? message.state.revokeEditableText : nil,
                    allowsReedit: allowsReedit
                )
            )
        }

        switch message.content {
        case let .image(image):
            return .image(ChatMessageRowContent.ImageContent(thumbnailPath: image.thumbnailPath))
        case let .voice(voice):
            return .voice(
                ChatMessageRowContent.VoiceContent(
                    localPath: voice.localPath,
                    durationMilliseconds: voice.durationMilliseconds,
                    isUnplayed: !isOutgoing && voice.playedAt == nil,
                    isPlaying: false
                )
            )
        case let .video(video):
            return .video(
                ChatMessageRowContent.VideoContent(
                    thumbnailPath: video.thumbnailPath,
                    localPath: video.localPath,
                    durationMilliseconds: video.durationMilliseconds
                )
            )
        case let .file(file):
            return .file(
                ChatMessageRowContent.FileContent(
                    fileName: file.fileName,
                    fileExtension: file.fileExtension,
                    localPath: file.localPath,
                    sizeBytes: file.sizeBytes
                )
            )
        case let .emoji(emoji):
            return .emoji(
                ChatMessageRowContent.EmojiContent(
                    emojiID: emoji.emojiID,
                    name: emoji.name,
                    localPath: emoji.localPath,
                    thumbPath: emoji.thumbPath,
                    cdnURL: emoji.cdnURL
                )
            )
        case let .text(text):
            return .text(text)
        case let .system(text), let .quote(text), let .revoked(text):
            return .text(text ?? "")
        }
    }

    private static func statusText(for message: StoredMessage) -> String? {
        guard message.state.direction == .outgoing else {
            return nil
        }

        switch message.state.sendStatus {
        case .pending:
            return "Pending"
        case .sending:
            return "Sending"
        case .success:
            return nil
        case .failed:
            return "Failed"
        }
    }

    private static func timeText(from timestamp: Int64) -> String {
        ChatBridgeTimeFormatter.messageTimeText(from: timestamp)
    }
}
