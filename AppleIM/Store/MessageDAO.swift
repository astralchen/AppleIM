//
//  MessageDAO.swift
//  AppleIM
//
//  消息数据访问对象（DAO）
//  负责消息的查询、插入、更新操作

import Combine
import Foundation
import GRDB

/// 消息写入计划。
///
/// 将“内容表 + message 主表 + 可选媒体资源 + 会话摘要”收敛为一个 GRDB 写事务内的执行单元。
nonisolated struct MessageWritePlan: Sendable {
    let message: StoredMessage
    let contentRecord: MessageContentWriteRecord
    let messageRecord: MessageDatabaseRecord
    let mediaResourceRecord: MediaResourceDatabaseRecord?
    let conversationSummary: ConversationSummaryWriteRecord

    func write(in db: Database) throws {
        try contentRecord.insert(in: db)
        try messageRecord.insert(db)
        if let mediaResourceRecord {
            try MediaResourceDatabaseRecord.upsertUploadResource(mediaResourceRecord, in: db)
        }
        try conversationSummary.apply(in: db)
    }
}

/// 消息内容表写入记录。
nonisolated enum MessageContentWriteRecord: Sendable {
    case text(MessageTextDatabaseRecord)
    case image(MessageImageDatabaseRecord)
    case voice(MessageVoiceDatabaseRecord)
    case video(MessageVideoDatabaseRecord)
    case file(MessageFileDatabaseRecord)
    case emoji(MessageEmojiDatabaseRecord)

    func insert(in db: Database) throws {
        switch self {
        case let .text(record):
            try record.insert(db)
        case let .image(record):
            try record.insert(db)
        case let .voice(record):
            try record.insert(db)
        case let .video(record):
            try record.insert(db)
        case let .file(record):
            try record.insert(db)
        case let .emoji(record):
            try record.insert(db)
        }
    }
}

/// 会话摘要写入记录。
nonisolated struct ConversationSummaryWriteRecord: Sendable {
    let messageID: MessageID
    let conversationID: ConversationID
    let userID: UserID
    let localTime: Int64
    let digest: String
    let sortSequence: Int64

    func apply(in db: Database) throws {
        try ConversationDatabaseRecord
            .filter(ConversationDatabaseRecord.Columns.conversationID == conversationID.rawValue)
            .filter(ConversationDatabaseRecord.Columns.userID == userID.rawValue)
            .updateAll(db, [
                ConversationDatabaseRecord.Columns.lastMessageID.set(to: messageID.rawValue),
                ConversationDatabaseRecord.Columns.lastMessageTime.set(to: localTime),
                ConversationDatabaseRecord.Columns.lastMessageDigest.set(to: digest),
                ConversationDatabaseRecord.Columns.sortTimestamp.set(to: sortSequence),
                ConversationDatabaseRecord.Columns.updatedAt.set(to: localTime)
            ])
    }
}

/// 消息 DAO
///
/// 负责消息表的数据库操作，使用游标分页，支持消息主表和内容表的聚合查询
nonisolated struct MessageDAO: Sendable {
    /// 数据库 Actor
    private let database: DatabaseActor
    /// 账号存储路径
    private let paths: AccountStoragePaths

    init(database: DatabaseActor, paths: AccountStoragePaths) {
        self.database = database
        self.paths = paths
    }

    /// 本地发出消息插入过程的公共上下文。
    private struct OutgoingMessageInsertContext {
        let messageID: MessageID
        let clientMessageID: String
        let contentID: String
        let sortSequence: Int64
    }

    func listMessages(conversationID: ConversationID, limit: Int, beforeSortSeq: Int64?) async throws -> [StoredMessage] {
        return try await database.read(paths: paths) { db in
            try Self.visibleMessages(conversationID: conversationID, beforeSortSeq: beforeSortSeq)
                .limit(max(0, limit))
                .fetchAll(db)
                .map { try Self.storedMessage(from: $0, db: db, paths: paths) }
        }
    }

    /// 观察指定会话的最新消息窗口。
    func observeLatestMessages(conversationID: ConversationID, limit: Int) async throws -> AnyPublisher<[StoredMessage], Error> {
        let boundedLimit = max(1, limit)
        let observation = try await database.observe(paths: paths) { db in
            try Self.visibleMessages(conversationID: conversationID, beforeSortSeq: nil)
                .limit(boundedLimit)
                .fetchAll(db)
                .map { try Self.storedMessage(from: $0, db: db, paths: paths) }
        }
        return observation.publisher
    }

    func message(messageID: MessageID) async throws -> StoredMessage? {
        return try await database.read(paths: paths) { db in
            try MessageDatabaseRecord
                .filter(MessageDatabaseRecord.Columns.messageID == messageID.rawValue)
                .filter(MessageDatabaseRecord.Columns.isDeleted == false)
                .fetchOne(db)
                .map { try Self.storedMessage(from: $0, db: db, paths: paths) }
        }
    }

    private static func visibleMessages(
        conversationID: ConversationID,
        beforeSortSeq: Int64?
    ) -> QueryInterfaceRequest<MessageDatabaseRecord> {
        var request = MessageDatabaseRecord
            .filter(MessageDatabaseRecord.Columns.conversationID == conversationID.rawValue)
            .filter(MessageDatabaseRecord.Columns.isDeleted == false)

        if let beforeSortSeq {
            request = request.filter(MessageDatabaseRecord.Columns.sortSequence < beforeSortSeq)
        }

        return request.order(MessageDatabaseRecord.Columns.sortSequence.desc)
    }

    private static func storedMessage(
        from record: MessageDatabaseRecord,
        db: Database,
        paths: AccountStoragePaths
    ) throws -> StoredMessage {
        let revokeRecord = try MessageRevokeDatabaseRecord
            .filter(MessageRevokeDatabaseRecord.Columns.messageID == record.messageID.rawValue)
            .fetchOne(db)
        return StoredMessage(
            id: record.messageID,
            conversationID: record.conversationID,
            senderID: record.senderID,
            delivery: StoredMessageDelivery(
                clientMessageID: record.clientMessageID,
                serverMessageID: record.serverMessageID,
                sequence: record.sequence
            ),
            state: StoredMessageState(
                direction: record.direction,
                sendStatus: record.sendStatus,
                readStatus: record.readStatus,
                isRevoked: record.revokeStatus != 0,
                isDeleted: record.isDeleted,
                revokeReplacementText: revokeRecord?.replaceText,
                revokeEditableText: record.revokeStatus != 0 ? textContent(contentID: record.contentID, db: db) : nil
            ),
            timeline: StoredMessageTimeline(
                serverTime: record.serverTime,
                sortSequence: record.sortSequence,
                localTime: record.localTime
            ),
            content: try storedContent(from: record, db: db, paths: paths, revokeRecord: revokeRecord)
        )
    }

    private static func storedContent(
        from record: MessageDatabaseRecord,
        db: Database,
        paths: AccountStoragePaths,
        revokeRecord: MessageRevokeDatabaseRecord?
    ) throws -> StoredMessageContent {
        switch record.messageType {
        case .text:
            return .text(textContent(contentID: record.contentID, db: db) ?? "")
        case .image:
            if let image = try MessageImageDatabaseRecord.fetchOne(db, key: record.contentID) {
                return .image(
                    StoredImageContent(
                        mediaID: image.mediaID,
                        localPath: resolvedMediaPath(image.localPath, in: paths),
                        thumbnailPath: resolvedMediaPath(image.thumbPath, in: paths),
                        width: image.width,
                        height: image.height,
                        sizeBytes: image.sizeBytes,
                        remoteURL: image.cdnURL,
                        md5: image.md5,
                        format: image.format,
                        uploadStatus: image.uploadStatus
                    )
                )
            }
        case .voice:
            if let voice = try MessageVoiceDatabaseRecord.fetchOne(db, key: record.contentID) {
                return .voice(
                    StoredVoiceContent(
                        mediaID: voice.mediaID,
                        localPath: resolvedMediaPath(voice.localPath, in: paths),
                        durationMilliseconds: voice.durationMilliseconds,
                        sizeBytes: voice.sizeBytes,
                        remoteURL: voice.cdnURL,
                        format: voice.format,
                        uploadStatus: voice.uploadStatus
                    )
                )
            }
        case .video:
            if let video = try MessageVideoDatabaseRecord.fetchOne(db, key: record.contentID) {
                return .video(
                    StoredVideoContent(
                        mediaID: video.mediaID,
                        localPath: resolvedMediaPath(video.localPath, in: paths),
                        thumbnailPath: resolvedMediaPath(video.thumbPath, in: paths),
                        durationMilliseconds: video.durationMilliseconds,
                        width: video.width,
                        height: video.height,
                        sizeBytes: video.sizeBytes,
                        remoteURL: video.cdnURL,
                        md5: video.md5,
                        uploadStatus: video.uploadStatus
                    )
                )
            }
        case .file:
            if let file = try MessageFileDatabaseRecord.fetchOne(db, key: record.contentID) {
                return .file(
                    StoredFileContent(
                        mediaID: file.mediaID,
                        localPath: resolvedMediaPath(file.localPath, in: paths),
                        fileName: file.fileName,
                        fileExtension: file.fileExtension,
                        sizeBytes: file.sizeBytes,
                        remoteURL: file.cdnURL,
                        md5: file.md5,
                        uploadStatus: file.uploadStatus
                    )
                )
            }
        case .emoji:
            if let emoji = try MessageEmojiDatabaseRecord.fetchOne(db, key: record.contentID) {
                return .emoji(
                    StoredEmojiContent(
                        emojiID: emoji.emojiID,
                        packageID: emoji.packageID,
                        emojiType: emoji.emojiType,
                        name: emoji.name,
                        localPath: emoji.localPath.map { resolvedMediaPath($0, in: paths) },
                        thumbPath: emoji.thumbPath.map { resolvedMediaPath($0, in: paths) },
                        cdnURL: emoji.cdnURL,
                        width: emoji.width,
                        height: emoji.height,
                        sizeBytes: emoji.sizeBytes
                    )
                )
            }
        case .system:
            return .system(textContent(contentID: record.contentID, db: db))
        case .quote:
            return .quote(textContent(contentID: record.contentID, db: db))
        case .revoked:
            return .revoked(revokeRecord?.replaceText)
        }

        return .text(textContent(contentID: record.contentID, db: db) ?? "")
    }

    private static func textContent(contentID: String, db: Database) -> String? {
        try? MessageTextDatabaseRecord.fetchOne(db, key: contentID)?.text
    }

    private static func resolvedMediaPath(_ storedPath: String, in paths: AccountStoragePaths) -> String {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: storedPath) else {
            return storedPath
        }

        let standardizedPath = URL(fileURLWithPath: storedPath).standardizedFileURL.path
        guard let mediaRange = standardizedPath.range(of: "/media/") else {
            return storedPath
        }

        let relativeMediaPath = String(standardizedPath[mediaRange.upperBound...])
        let currentPath = paths.mediaDirectory.appendingPathComponent(relativeMediaPath).path
        guard fileManager.fileExists(atPath: currentPath) else {
            return storedPath
        }
        return currentPath
    }

    /// 更新消息发送状态
    ///
    /// - Parameters:
    ///   - messageID: 消息 ID
    ///   - status: 发送状态
    ///   - ack: 服务端确认信息（可选）
    /// - Throws: 数据库操作失败时抛出错误
    func updateSendStatus(messageID: MessageID, status: MessageSendStatus, ack: MessageSendAck?) async throws {
        _ = try await database.write(paths: paths) { db in
            try MessageDatabaseRecord
                .filter(MessageDatabaseRecord.Columns.messageID == messageID.rawValue)
                .updateAll(db, [
                    MessageDatabaseRecord.Columns.sendStatus.set(to: status.rawValue),
                    MessageDatabaseRecord.Columns.serverMessageID.set(to: ack?.serverMessageID),
                    MessageDatabaseRecord.Columns.sequence.set(to: ack?.sequence),
                    MessageDatabaseRecord.Columns.serverTime.set(to: ack?.serverTime)
                ])
        }
    }

    /// 准备文本消息重发
    ///
    /// 检查消息是否可以重发，并将状态更新为 sending
    ///
    /// - Parameter messageID: 消息 ID
    /// - Returns: 更新后的消息
    /// - Throws: 消息不存在或无法重发时抛出错误
    func prepareTextMessageForResend(messageID: MessageID) async throws -> StoredMessage {
        guard let existingMessage = try await message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        guard
            existingMessage.type == .text,
            existingMessage.state.sendStatus == .failed,
            !existingMessage.state.isRevoked,
            !existingMessage.state.isDeleted
        else {
            throw ChatStoreError.messageCannotBeResent(messageID)
        }

        try await updateSendStatus(messageID: messageID, status: .sending, ack: nil)

        guard let updatedMessage = try await message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        return updatedMessage
    }

    private static func outgoingInsertContext<Input: OutgoingMessageEnvelopeProviding>(
        input: Input,
        contentPrefix: String
    ) -> OutgoingMessageInsertContext {
        let messageID = input.messageID ?? MessageID(rawValue: UUID().uuidString)
        return OutgoingMessageInsertContext(
            messageID: messageID,
            clientMessageID: input.clientMessageID ?? messageID.rawValue,
            contentID: "\(contentPrefix)_\(messageID.rawValue)",
            sortSequence: input.sortSequence ?? input.localTime
        )
    }

    private static func outgoingStoredMessage<Input: OutgoingMessageEnvelopeProviding>(
        input: Input,
        context: OutgoingMessageInsertContext,
        content: StoredMessageContent
    ) -> StoredMessage {
        StoredMessage(
            id: context.messageID,
            conversationID: input.conversationID,
            senderID: input.senderID,
            clientMessageID: context.clientMessageID,
            content: content,
            sortSequence: context.sortSequence,
            localTime: input.localTime
        )
    }

    static func makeOutgoingTextWritePlan(_ input: OutgoingTextMessageInput) -> MessageWritePlan {
        let context = outgoingInsertContext(input: input, contentPrefix: "text")
        let mentionsJSON = Self.mentionsJSON(for: input.mentionedUserIDs)
        let message = outgoingStoredMessage(input: input, context: context, content: .text(input.text))
        return MessageWritePlan(
            message: message,
            contentRecord: .text(
                MessageTextDatabaseRecord(
                    contentID: context.contentID,
                    text: input.text,
                    mentionsJSON: mentionsJSON,
                    atAll: input.mentionsAll,
                    richTextJSON: nil
                )
            ),
            messageRecord: outgoingMessageRecord(message: message, input: input, context: context, messageType: .text, contentTable: "message_text"),
            mediaResourceRecord: nil,
            conversationSummary: conversationSummary(messageID: message.id, input: input, digest: input.text, sortSequence: context.sortSequence)
        )
    }

    static func makeInitialTextWritePlan(_ input: InitialTextMessageInput) -> MessageWritePlan {
        let contentID = "seed_text_\(input.messageID.rawValue)"
        let message = StoredMessage(
            id: input.messageID,
            conversationID: input.conversationID,
            senderID: input.senderID,
            delivery: StoredMessageDelivery(
                clientMessageID: input.clientMessageID,
                serverMessageID: input.serverMessageID,
                sequence: input.sequence
            ),
            state: StoredMessageState(
                direction: input.direction,
                sendStatus: .success,
                readStatus: input.readStatus,
                isRevoked: false,
                isDeleted: false,
                revokeReplacementText: nil
            ),
            timeline: StoredMessageTimeline(
                serverTime: input.localTime,
                sortSequence: input.sortSequence,
                localTime: input.localTime
            ),
            content: .text(input.text)
        )
        return MessageWritePlan(
            message: message,
            contentRecord: .text(
                MessageTextDatabaseRecord(
                    contentID: contentID,
                    text: input.text,
                    mentionsJSON: nil,
                    atAll: false,
                    richTextJSON: nil
                )
            ),
            messageRecord: MessageDatabaseRecord(
                messageID: input.messageID,
                conversationID: input.conversationID,
                senderID: input.senderID,
                clientMessageID: input.clientMessageID,
                serverMessageID: input.serverMessageID,
                sequence: input.sequence,
                messageType: .text,
                direction: input.direction,
                sendStatus: .success,
                deliveryStatus: 0,
                readStatus: input.readStatus,
                revokeStatus: 0,
                isDeleted: false,
                contentTable: "message_text",
                contentID: contentID,
                sortSequence: input.sortSequence,
                serverTime: input.localTime,
                localTime: input.localTime
            ),
            mediaResourceRecord: nil,
            conversationSummary: ConversationSummaryWriteRecord(
                messageID: input.messageID,
                conversationID: input.conversationID,
                userID: input.userID,
                localTime: input.localTime,
                digest: input.text,
                sortSequence: input.sortSequence
            )
        )
    }

    static func makeOutgoingImageWritePlan(_ input: OutgoingImageMessageInput) -> MessageWritePlan {
        let context = outgoingInsertContext(input: input, contentPrefix: "image")
        let message = outgoingStoredMessage(input: input, context: context, content: .image(input.image))
        return MessageWritePlan(
            message: message,
            contentRecord: .image(
                MessageImageDatabaseRecord(
                    contentID: context.contentID,
                    mediaID: input.image.mediaID,
                    width: input.image.width,
                    height: input.image.height,
                    sizeBytes: input.image.sizeBytes,
                    localPath: input.image.localPath,
                    thumbPath: input.image.thumbnailPath,
                    cdnURL: nil,
                    md5: input.image.md5,
                    format: input.image.format,
                    uploadStatus: .pending,
                    downloadStatus: 0
                )
            ),
            messageRecord: outgoingMessageRecord(message: message, input: input, context: context, messageType: .image, contentTable: "message_image"),
            mediaResourceRecord: mediaResourceRecord(
                mediaID: input.image.mediaID,
                userID: input.userID,
                ownerMessageID: message.id,
                localPath: input.image.localPath,
                thumbPath: input.image.thumbnailPath,
                sizeBytes: input.image.sizeBytes,
                md5: input.image.md5,
                uploadStatus: .pending,
                timestamp: input.localTime
            ),
            conversationSummary: conversationSummary(messageID: message.id, input: input, digest: "[图片]", sortSequence: context.sortSequence)
        )
    }

    static func makeOutgoingVoiceWritePlan(_ input: OutgoingVoiceMessageInput) -> MessageWritePlan {
        let context = outgoingInsertContext(input: input, contentPrefix: "voice")
        let message = outgoingStoredMessage(input: input, context: context, content: .voice(input.voice))
        return MessageWritePlan(
            message: message,
            contentRecord: .voice(
                MessageVoiceDatabaseRecord(
                    contentID: context.contentID,
                    mediaID: input.voice.mediaID,
                    durationMilliseconds: input.voice.durationMilliseconds,
                    sizeBytes: input.voice.sizeBytes,
                    localPath: input.voice.localPath,
                    cdnURL: nil,
                    format: input.voice.format,
                    transcript: nil,
                    uploadStatus: .pending,
                    downloadStatus: 0
                )
            ),
            messageRecord: outgoingMessageRecord(message: message, input: input, context: context, messageType: .voice, contentTable: "message_voice"),
            mediaResourceRecord: mediaResourceRecord(
                mediaID: input.voice.mediaID,
                userID: input.userID,
                ownerMessageID: message.id,
                localPath: input.voice.localPath,
                thumbPath: nil,
                sizeBytes: input.voice.sizeBytes,
                md5: nil,
                uploadStatus: .pending,
                timestamp: input.localTime
            ),
            conversationSummary: conversationSummary(messageID: message.id, input: input, digest: "[语音]", sortSequence: context.sortSequence)
        )
    }

    static func makeOutgoingVideoWritePlan(_ input: OutgoingVideoMessageInput) -> MessageWritePlan {
        let context = outgoingInsertContext(input: input, contentPrefix: "video")
        let message = outgoingStoredMessage(input: input, context: context, content: .video(input.video))
        return MessageWritePlan(
            message: message,
            contentRecord: .video(
                MessageVideoDatabaseRecord(
                    contentID: context.contentID,
                    mediaID: input.video.mediaID,
                    durationMilliseconds: input.video.durationMilliseconds,
                    width: input.video.width,
                    height: input.video.height,
                    sizeBytes: input.video.sizeBytes,
                    localPath: input.video.localPath,
                    thumbPath: input.video.thumbnailPath,
                    cdnURL: nil,
                    md5: input.video.md5,
                    uploadStatus: .pending,
                    downloadStatus: 0
                )
            ),
            messageRecord: outgoingMessageRecord(message: message, input: input, context: context, messageType: .video, contentTable: "message_video"),
            mediaResourceRecord: mediaResourceRecord(
                mediaID: input.video.mediaID,
                userID: input.userID,
                ownerMessageID: message.id,
                localPath: input.video.localPath,
                thumbPath: input.video.thumbnailPath,
                sizeBytes: input.video.sizeBytes,
                md5: input.video.md5,
                uploadStatus: .pending,
                timestamp: input.localTime
            ),
            conversationSummary: conversationSummary(messageID: message.id, input: input, digest: "[视频]", sortSequence: context.sortSequence)
        )
    }

    static func makeOutgoingFileWritePlan(_ input: OutgoingFileMessageInput) -> MessageWritePlan {
        let context = outgoingInsertContext(input: input, contentPrefix: "file")
        let message = outgoingStoredMessage(input: input, context: context, content: .file(input.file))
        return MessageWritePlan(
            message: message,
            contentRecord: .file(
                MessageFileDatabaseRecord(
                    contentID: context.contentID,
                    mediaID: input.file.mediaID,
                    fileName: input.file.fileName,
                    fileExtension: input.file.fileExtension,
                    sizeBytes: input.file.sizeBytes,
                    localPath: input.file.localPath,
                    cdnURL: nil,
                    md5: input.file.md5,
                    uploadStatus: .pending,
                    downloadStatus: 0
                )
            ),
            messageRecord: outgoingMessageRecord(message: message, input: input, context: context, messageType: .file, contentTable: "message_file"),
            mediaResourceRecord: mediaResourceRecord(
                mediaID: input.file.mediaID,
                userID: input.userID,
                ownerMessageID: message.id,
                localPath: input.file.localPath,
                thumbPath: nil,
                sizeBytes: input.file.sizeBytes,
                md5: input.file.md5,
                uploadStatus: .pending,
                timestamp: input.localTime
            ),
            conversationSummary: conversationSummary(messageID: message.id, input: input, digest: "[文件] \(input.file.fileName)", sortSequence: context.sortSequence)
        )
    }

    static func makeOutgoingEmojiWritePlan(_ input: OutgoingEmojiMessageInput) -> MessageWritePlan {
        let context = outgoingInsertContext(input: input, contentPrefix: "emoji")
        let message = outgoingStoredMessage(input: input, context: context, content: .emoji(input.emoji))
        return MessageWritePlan(
            message: message,
            contentRecord: .emoji(
                MessageEmojiDatabaseRecord(
                    contentID: context.contentID,
                    emojiID: input.emoji.emojiID,
                    packageID: input.emoji.packageID,
                    emojiType: input.emoji.emojiType,
                    name: input.emoji.name,
                    localPath: input.emoji.localPath,
                    thumbPath: input.emoji.thumbPath,
                    cdnURL: input.emoji.cdnURL,
                    width: input.emoji.width,
                    height: input.emoji.height,
                    sizeBytes: input.emoji.sizeBytes
                )
            ),
            messageRecord: outgoingMessageRecord(message: message, input: input, context: context, messageType: .emoji, contentTable: "message_emoji"),
            mediaResourceRecord: nil,
            conversationSummary: conversationSummary(messageID: message.id, input: input, digest: "[表情]", sortSequence: context.sortSequence)
        )
    }

    private static func outgoingMessageRecord<Input: OutgoingMessageEnvelopeProviding>(
        message: StoredMessage,
        input: Input,
        context: OutgoingMessageInsertContext,
        messageType: MessageType,
        contentTable: String
    ) -> MessageDatabaseRecord {
        MessageDatabaseRecord(
            messageID: message.id,
            conversationID: input.conversationID,
            senderID: input.senderID,
            clientMessageID: context.clientMessageID,
            serverMessageID: nil,
            sequence: nil,
            messageType: messageType,
            direction: .outgoing,
            sendStatus: .sending,
            deliveryStatus: 0,
            readStatus: .read,
            revokeStatus: 0,
            isDeleted: false,
            contentTable: contentTable,
            contentID: context.contentID,
            sortSequence: context.sortSequence,
            serverTime: nil,
            localTime: input.localTime
        )
    }

    private static func mediaResourceRecord(
        mediaID: String,
        userID: UserID,
        ownerMessageID: MessageID,
        localPath: String,
        thumbPath: String?,
        sizeBytes: Int64,
        md5: String?,
        uploadStatus: MediaUploadStatus,
        timestamp: Int64
    ) -> MediaResourceDatabaseRecord {
        MediaResourceDatabaseRecord(
            mediaID: mediaID,
            userID: userID,
            ownerMessageID: ownerMessageID,
            localPath: localPath,
            remoteURL: nil,
            thumbPath: thumbPath,
            sizeBytes: sizeBytes,
            md5: md5,
            uploadStatus: uploadStatus,
            downloadStatus: 0,
            updatedAt: timestamp,
            createdAt: timestamp
        )
    }

    private static func conversationSummary<Input: OutgoingMessageEnvelopeProviding>(
        messageID: MessageID,
        input: Input,
        digest: String,
        sortSequence: Int64
    ) -> ConversationSummaryWriteRecord {
        ConversationSummaryWriteRecord(
            messageID: messageID,
            conversationID: input.conversationID,
            userID: input.userID,
            localTime: input.localTime,
            digest: digest,
            sortSequence: sortSequence
        )
    }

    private static func mentionsJSON(for userIDs: [UserID]) -> String? {
        let values = userIDs.map(\.rawValue)
        guard !values.isEmpty else {
            return nil
        }
        guard let data = try? JSONEncoder().encode(values) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

}
