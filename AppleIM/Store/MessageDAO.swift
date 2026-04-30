//
//  MessageDAO.swift
//  AppleIM
//
//  消息数据访问对象（DAO）
//  负责消息的查询、插入、更新操作

import Foundation

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

    func listMessages(conversationID: ConversationID, limit: Int, beforeSortSeq: Int64?) async throws -> [StoredMessage] {
        let query = Self.listMessagesQuery(beforeSortSeq: beforeSortSeq)
        var parameters: [SQLiteValue] = [.text(conversationID.rawValue)]
        if let beforeSortSeq {
            parameters.append(.integer(beforeSortSeq))
        }
        parameters.append(.integer(Int64(limit)))

        let rows = try await database.query(
            query,
            parameters: parameters,
            paths: paths
        )

        return try rows.map(Self.message(from:))
    }

    static func listMessagesQuery(beforeSortSeq: Int64?) -> String {
        let cursorPredicate = beforeSortSeq == nil ? "" : "\n            AND message.sort_seq < ?"

        return """
        SELECT
            message.message_id,
            message.conversation_id,
            message.sender_id,
            message.client_msg_id,
            message.server_msg_id,
            message.seq,
            message.msg_type,
            message.direction,
            message.send_status,
            message.read_status,
            message.server_time,
            message.revoke_status,
            message.is_deleted,
            message_revoke.replace_text,
            message.sort_seq,
            message.local_time,
            message_text.text,
            message_image.media_id AS image_media_id,
            message_image.width AS image_width,
            message_image.height AS image_height,
            message_image.size_bytes AS image_size_bytes,
            message_image.local_path AS image_local_path,
            message_image.thumb_path AS image_thumb_path,
            message_image.cdn_url AS image_cdn_url,
            message_image.md5 AS image_md5,
            message_image.format AS image_format,
            message_image.upload_status AS image_upload_status,
            message_voice.media_id AS voice_media_id,
            message_voice.duration_ms AS voice_duration_ms,
            message_voice.size_bytes AS voice_size_bytes,
            message_voice.local_path AS voice_local_path,
            message_voice.cdn_url AS voice_cdn_url,
            message_voice.format AS voice_format,
            message_voice.upload_status AS voice_upload_status
        FROM message INDEXED BY idx_message_conversation_visible_sort
        LEFT JOIN message_text ON message_text.content_id = message.content_id
        LEFT JOIN message_image ON message_image.content_id = message.content_id
        LEFT JOIN message_voice ON message_voice.content_id = message.content_id
        LEFT JOIN message_revoke ON message_revoke.message_id = message.message_id
        WHERE message.conversation_id = ?
        AND message.is_deleted = 0\(cursorPredicate)
        ORDER BY message.sort_seq DESC
        LIMIT ?;
        """
    }

    func message(messageID: MessageID) async throws -> StoredMessage? {
        let rows = try await database.query(
            """
            SELECT
                message.message_id,
                message.conversation_id,
                message.sender_id,
                message.client_msg_id,
                message.server_msg_id,
                message.seq,
                message.msg_type,
                message.direction,
                message.send_status,
                message.read_status,
                message.server_time,
                message.revoke_status,
                message.is_deleted,
                message_revoke.replace_text,
                message.sort_seq,
                message.local_time,
                message_text.text,
                message_image.media_id AS image_media_id,
                message_image.width AS image_width,
                message_image.height AS image_height,
                message_image.size_bytes AS image_size_bytes,
                message_image.local_path AS image_local_path,
                message_image.thumb_path AS image_thumb_path,
                message_image.cdn_url AS image_cdn_url,
                message_image.md5 AS image_md5,
                message_image.format AS image_format,
                message_image.upload_status AS image_upload_status,
                message_voice.media_id AS voice_media_id,
                message_voice.duration_ms AS voice_duration_ms,
                message_voice.size_bytes AS voice_size_bytes,
                message_voice.local_path AS voice_local_path,
                message_voice.cdn_url AS voice_cdn_url,
                message_voice.format AS voice_format,
                message_voice.upload_status AS voice_upload_status
            FROM message
            LEFT JOIN message_text ON message_text.content_id = message.content_id
            LEFT JOIN message_image ON message_image.content_id = message.content_id
            LEFT JOIN message_voice ON message_voice.content_id = message.content_id
            LEFT JOIN message_revoke ON message_revoke.message_id = message.message_id
            WHERE message.message_id = ?
            AND message.is_deleted = 0
            LIMIT 1;
            """,
            parameters: [.text(messageID.rawValue)],
            paths: paths
        )

        guard let row = rows.first else {
            return nil
        }

        return try Self.message(from: row)
    }

    /// 更新消息发送状态
    ///
    /// - Parameters:
    ///   - messageID: 消息 ID
    ///   - status: 发送状态
    ///   - ack: 服务端确认信息（可选）
    /// - Throws: 数据库操作失败时抛出错误
    func updateSendStatus(messageID: MessageID, status: MessageSendStatus, ack: MessageSendAck?) async throws {
        try await database.execute(
            """
            UPDATE message
            SET
                send_status = ?,
                server_msg_id = ?,
                seq = ?,
                server_time = ?
            WHERE message_id = ?;
            """,
            parameters: [
                .integer(Int64(status.rawValue)),
                .optionalText(ack?.serverMessageID),
                .optionalInteger(ack?.sequence),
                .optionalInteger(ack?.serverTime),
                .text(messageID.rawValue)
            ],
            paths: paths
        )
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
            existingMessage.sendStatus == .failed,
            !existingMessage.isRevoked,
            !existingMessage.isDeleted
        else {
            throw ChatStoreError.messageCannotBeResent(messageID)
        }

        try await updateSendStatus(messageID: messageID, status: .sending, ack: nil)

        guard let updatedMessage = try await message(messageID: messageID) else {
            throw ChatStoreError.messageNotFound(messageID)
        }

        return updatedMessage
    }

    /// 生成插入发出文本消息的 SQL 语句
    ///
    /// 返回消息对象和 SQL 语句数组，由调用方在事务中执行
    ///
    /// - Parameter input: 发出的文本消息输入参数
    /// - Returns: 消息对象和 SQL 语句数组
    static func insertOutgoingTextStatements(_ input: OutgoingTextMessageInput) -> (message: StoredMessage, statements: [SQLiteStatement]) {
        let messageID = input.messageID ?? MessageID(rawValue: UUID().uuidString)
        let clientMessageID = input.clientMessageID ?? messageID.rawValue
        let contentID = "text_\(messageID.rawValue)"
        let sortSequence = input.sortSequence ?? input.localTime

        let message = StoredMessage(
            id: messageID,
            conversationID: input.conversationID,
            senderID: input.senderID,
            clientMessageID: clientMessageID,
            serverMessageID: nil,
            sequence: nil,
            type: .text,
            direction: .outgoing,
            sendStatus: .sending,
            readStatus: .read,
            serverTime: nil,
            isRevoked: false,
            isDeleted: false,
            revokeReplacementText: nil,
            text: input.text,
            image: nil,
            voice: nil,
            sortSequence: sortSequence,
            localTime: input.localTime
        )

        return (
            message,
            [
                SQLiteStatement(
                    """
                    INSERT INTO message_text (
                        content_id,
                        text,
                        mentions_json,
                        at_all,
                        rich_text_json
                    ) VALUES (?, ?, NULL, 0, NULL);
                    """,
                    parameters: [
                        .text(contentID),
                        .text(input.text)
                    ]
                ),
                SQLiteStatement(
                    """
                    INSERT INTO message (
                        message_id,
                        conversation_id,
                        sender_id,
                        client_msg_id,
                        msg_type,
                        direction,
                        send_status,
                        delivery_status,
                        read_status,
                        revoke_status,
                        is_deleted,
                        content_table,
                        content_id,
                        sort_seq,
                        local_time
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, 1, 0, 0, ?, ?, ?, ?);
                    """,
                    parameters: [
                        .text(message.id.rawValue),
                        .text(input.conversationID.rawValue),
                        .text(input.senderID.rawValue),
                        .text(clientMessageID),
                        .integer(Int64(MessageType.text.rawValue)),
                        .integer(Int64(MessageDirection.outgoing.rawValue)),
                        .integer(Int64(MessageSendStatus.sending.rawValue)),
                        .text("message_text"),
                        .text(contentID),
                        .integer(sortSequence),
                        .integer(input.localTime)
                    ]
                ),
                SQLiteStatement(
                    """
                    UPDATE conversation
                    SET
                        last_message_id = ?,
                        last_message_time = ?,
                        last_message_digest = ?,
                        sort_ts = ?,
                        updated_at = ?
                    WHERE conversation_id = ? AND user_id = ?;
                    """,
                    parameters: [
                        .text(message.id.rawValue),
                        .integer(input.localTime),
                        .text(input.text),
                        .integer(sortSequence),
                        .integer(input.localTime),
                        .text(input.conversationID.rawValue),
                        .text(input.userID.rawValue)
                    ]
                )
            ]
        )
    }

    /// 生成插入发出图片消息的 SQL 语句
    ///
    /// 返回消息对象和 SQL 语句数组，由调用方在事务中执行
    ///
    /// - Parameter input: 发出的图片消息输入参数
    /// - Returns: 消息对象和 SQL 语句数组
    static func insertOutgoingImageStatements(_ input: OutgoingImageMessageInput) -> (message: StoredMessage, statements: [SQLiteStatement]) {
        let messageID = input.messageID ?? MessageID(rawValue: UUID().uuidString)
        let clientMessageID = input.clientMessageID ?? messageID.rawValue
        let contentID = "image_\(messageID.rawValue)"
        let sortSequence = input.sortSequence ?? input.localTime

        let message = StoredMessage(
            id: messageID,
            conversationID: input.conversationID,
            senderID: input.senderID,
            clientMessageID: clientMessageID,
            serverMessageID: nil,
            sequence: nil,
            type: .image,
            direction: .outgoing,
            sendStatus: .sending,
            readStatus: .read,
            serverTime: nil,
            isRevoked: false,
            isDeleted: false,
            revokeReplacementText: nil,
            text: nil,
            image: input.image,
            voice: nil,
            sortSequence: sortSequence,
            localTime: input.localTime
        )

        return (
            message,
            [
                SQLiteStatement(
                    """
                    INSERT INTO message_image (
                        content_id,
                        media_id,
                        width,
                        height,
                        size_bytes,
                        local_path,
                        thumb_path,
                        cdn_url,
                        md5,
                        format,
                        upload_status,
                        download_status
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?, 0);
                    """,
                    parameters: [
                        .text(contentID),
                        .text(input.image.mediaID),
                        .integer(Int64(input.image.width)),
                        .integer(Int64(input.image.height)),
                        .integer(input.image.sizeBytes),
                        .text(input.image.localPath),
                        .text(input.image.thumbnailPath),
                        .text(input.image.format),
                        .integer(Int64(MediaUploadStatus.pending.rawValue))
                    ]
                ),
                SQLiteStatement(
                    """
                    INSERT INTO message (
                        message_id,
                        conversation_id,
                        sender_id,
                        client_msg_id,
                        msg_type,
                        direction,
                        send_status,
                        delivery_status,
                        read_status,
                        revoke_status,
                        is_deleted,
                        content_table,
                        content_id,
                        sort_seq,
                        local_time
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, 1, 0, 0, ?, ?, ?, ?);
                    """,
                    parameters: [
                        .text(message.id.rawValue),
                        .text(input.conversationID.rawValue),
                        .text(input.senderID.rawValue),
                        .text(clientMessageID),
                        .integer(Int64(MessageType.image.rawValue)),
                        .integer(Int64(MessageDirection.outgoing.rawValue)),
                        .integer(Int64(MessageSendStatus.sending.rawValue)),
                        .text("message_image"),
                        .text(contentID),
                        .integer(sortSequence),
                        .integer(input.localTime)
                    ]
                ),
                SQLiteStatement(
                    """
                    INSERT INTO media_resource (
                        media_id,
                        user_id,
                        owner_message_id,
                        local_path,
                        remote_url,
                        thumb_path,
                        size_bytes,
                        md5,
                        upload_status,
                        download_status,
                        updated_at,
                        created_at
                    ) VALUES (?, ?, ?, ?, NULL, ?, ?, NULL, ?, 0, ?, ?)
                    ON CONFLICT(media_id) DO UPDATE SET
                        owner_message_id = excluded.owner_message_id,
                        local_path = excluded.local_path,
                        thumb_path = excluded.thumb_path,
                        size_bytes = excluded.size_bytes,
                        upload_status = excluded.upload_status,
                        updated_at = excluded.updated_at;
                    """,
                    parameters: [
                        .text(input.image.mediaID),
                        .text(input.userID.rawValue),
                        .text(message.id.rawValue),
                        .text(input.image.localPath),
                        .text(input.image.thumbnailPath),
                        .integer(input.image.sizeBytes),
                        .integer(Int64(MediaUploadStatus.pending.rawValue)),
                        .integer(input.localTime),
                        .integer(input.localTime)
                    ]
                ),
                SQLiteStatement(
                    """
                    UPDATE conversation
                    SET
                        last_message_id = ?,
                        last_message_time = ?,
                        last_message_digest = ?,
                        sort_ts = ?,
                        updated_at = ?
                    WHERE conversation_id = ? AND user_id = ?;
                    """,
                    parameters: [
                        .text(message.id.rawValue),
                        .integer(input.localTime),
                        .text("[图片]"),
                        .integer(sortSequence),
                        .integer(input.localTime),
                        .text(input.conversationID.rawValue),
                        .text(input.userID.rawValue)
                    ]
                )
            ]
        )
    }

    /// 生成插入发出语音消息的 SQL 语句
    ///
    /// 返回消息对象和 SQL 语句数组，由调用方在事务中执行
    ///
    /// - Parameter input: 发出的语音消息输入参数
    /// - Returns: 消息对象和 SQL 语句数组
    static func insertOutgoingVoiceStatements(_ input: OutgoingVoiceMessageInput) -> (message: StoredMessage, statements: [SQLiteStatement]) {
        let messageID = input.messageID ?? MessageID(rawValue: UUID().uuidString)
        let clientMessageID = input.clientMessageID ?? messageID.rawValue
        let contentID = "voice_\(messageID.rawValue)"
        let sortSequence = input.sortSequence ?? input.localTime

        let message = StoredMessage(
            id: messageID,
            conversationID: input.conversationID,
            senderID: input.senderID,
            clientMessageID: clientMessageID,
            serverMessageID: nil,
            sequence: nil,
            type: .voice,
            direction: .outgoing,
            sendStatus: .sending,
            readStatus: .read,
            serverTime: nil,
            isRevoked: false,
            isDeleted: false,
            revokeReplacementText: nil,
            text: nil,
            image: nil,
            voice: input.voice,
            sortSequence: sortSequence,
            localTime: input.localTime
        )

        return (
            message,
            [
                SQLiteStatement(
                    """
                    INSERT INTO message_voice (
                        content_id,
                        media_id,
                        duration_ms,
                        size_bytes,
                        local_path,
                        cdn_url,
                        format,
                        transcript,
                        upload_status,
                        download_status
                    ) VALUES (?, ?, ?, ?, ?, NULL, ?, NULL, ?, 0);
                    """,
                    parameters: [
                        .text(contentID),
                        .text(input.voice.mediaID),
                        .integer(Int64(input.voice.durationMilliseconds)),
                        .integer(input.voice.sizeBytes),
                        .text(input.voice.localPath),
                        .text(input.voice.format),
                        .integer(Int64(MediaUploadStatus.pending.rawValue))
                    ]
                ),
                SQLiteStatement(
                    """
                    INSERT INTO message (
                        message_id,
                        conversation_id,
                        sender_id,
                        client_msg_id,
                        msg_type,
                        direction,
                        send_status,
                        delivery_status,
                        read_status,
                        revoke_status,
                        is_deleted,
                        content_table,
                        content_id,
                        sort_seq,
                        local_time
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, 1, 0, 0, ?, ?, ?, ?);
                    """,
                    parameters: [
                        .text(message.id.rawValue),
                        .text(input.conversationID.rawValue),
                        .text(input.senderID.rawValue),
                        .text(clientMessageID),
                        .integer(Int64(MessageType.voice.rawValue)),
                        .integer(Int64(MessageDirection.outgoing.rawValue)),
                        .integer(Int64(MessageSendStatus.sending.rawValue)),
                        .text("message_voice"),
                        .text(contentID),
                        .integer(sortSequence),
                        .integer(input.localTime)
                    ]
                ),
                SQLiteStatement(
                    """
                    INSERT INTO media_resource (
                        media_id,
                        user_id,
                        owner_message_id,
                        local_path,
                        remote_url,
                        thumb_path,
                        size_bytes,
                        md5,
                        upload_status,
                        download_status,
                        updated_at,
                        created_at
                    ) VALUES (?, ?, ?, ?, NULL, NULL, ?, NULL, ?, 0, ?, ?)
                    ON CONFLICT(media_id) DO UPDATE SET
                        owner_message_id = excluded.owner_message_id,
                        local_path = excluded.local_path,
                        size_bytes = excluded.size_bytes,
                        upload_status = excluded.upload_status,
                        updated_at = excluded.updated_at;
                    """,
                    parameters: [
                        .text(input.voice.mediaID),
                        .text(input.userID.rawValue),
                        .text(message.id.rawValue),
                        .text(input.voice.localPath),
                        .integer(input.voice.sizeBytes),
                        .integer(Int64(MediaUploadStatus.pending.rawValue)),
                        .integer(input.localTime),
                        .integer(input.localTime)
                    ]
                ),
                SQLiteStatement(
                    """
                    UPDATE conversation
                    SET
                        last_message_id = ?,
                        last_message_time = ?,
                        last_message_digest = ?,
                        sort_ts = ?,
                        updated_at = ?
                    WHERE conversation_id = ? AND user_id = ?;
                    """,
                    parameters: [
                        .text(message.id.rawValue),
                        .integer(input.localTime),
                        .text("[语音]"),
                        .integer(sortSequence),
                        .integer(input.localTime),
                        .text(input.conversationID.rawValue),
                        .text(input.userID.rawValue)
                    ]
                )
            ]
        )
    }

    /// 从数据库行构建消息对象
    ///
    /// - Parameter row: 数据库查询结果行
    /// - Returns: 消息对象
    /// - Throws: 数据格式错误时抛出错误
    private static func message(from row: SQLiteRow) throws -> StoredMessage {
        let typeRawValue = try row.requiredInt("msg_type")
        let directionRawValue = try row.requiredInt("direction")
        let sendStatusRawValue = try row.requiredInt("send_status")
        let readStatusRawValue = row.int("read_status") ?? MessageReadStatus.unread.rawValue

        guard let type = MessageType(rawValue: typeRawValue) else {
            throw ChatStoreError.invalidMessageType(typeRawValue)
        }

        guard let direction = MessageDirection(rawValue: directionRawValue) else {
            throw ChatStoreError.invalidMessageDirection(directionRawValue)
        }

        guard let sendStatus = MessageSendStatus(rawValue: sendStatusRawValue) else {
            throw ChatStoreError.invalidMessageSendStatus(sendStatusRawValue)
        }

        guard let readStatus = MessageReadStatus(rawValue: readStatusRawValue) else {
            throw ChatStoreError.invalidMessageReadStatus(readStatusRawValue)
        }

        return StoredMessage(
            id: MessageID(rawValue: try row.requiredString("message_id")),
            conversationID: ConversationID(rawValue: try row.requiredString("conversation_id")),
            senderID: UserID(rawValue: try row.requiredString("sender_id")),
            clientMessageID: row.string("client_msg_id"),
            serverMessageID: row.string("server_msg_id"),
            sequence: row.int64("seq"),
            type: type,
            direction: direction,
            sendStatus: sendStatus,
            readStatus: readStatus,
            serverTime: row.int64("server_time"),
            isRevoked: row.bool("revoke_status"),
            isDeleted: row.bool("is_deleted"),
            revokeReplacementText: row.string("replace_text"),
            text: row.string("text"),
            image: try image(from: row),
            voice: try voice(from: row),
            sortSequence: try row.requiredInt64("sort_seq"),
            localTime: try row.requiredInt64("local_time")
        )
    }

    /// 从数据库行提取图片内容
    ///
    /// - Parameter row: 数据库查询结果行
    /// - Returns: 图片内容，如果不是图片消息则返回 nil
    private static func image(from row: SQLiteRow) throws -> StoredImageContent? {
        guard
            let mediaID = row.string("image_media_id"),
            let localPath = row.string("image_local_path"),
            let thumbnailPath = row.string("image_thumb_path")
        else {
            return nil
        }

        let uploadStatusRawValue = row.int("image_upload_status") ?? MediaUploadStatus.pending.rawValue
        guard let uploadStatus = MediaUploadStatus(rawValue: uploadStatusRawValue) else {
            throw ChatStoreError.invalidMediaUploadStatus(uploadStatusRawValue)
        }

        return StoredImageContent(
            mediaID: mediaID,
            localPath: localPath,
            thumbnailPath: thumbnailPath,
            width: row.int("image_width") ?? 0,
            height: row.int("image_height") ?? 0,
            sizeBytes: row.int64("image_size_bytes") ?? 0,
            remoteURL: row.string("image_cdn_url"),
            md5: row.string("image_md5"),
            format: row.string("image_format") ?? "jpg",
            uploadStatus: uploadStatus
        )
    }

    /// 从数据库行提取语音内容
    ///
    /// - Parameter row: 数据库查询结果行
    /// - Returns: 语音内容，如果不是语音消息则返回 nil
    private static func voice(from row: SQLiteRow) throws -> StoredVoiceContent? {
        guard
            let mediaID = row.string("voice_media_id"),
            let localPath = row.string("voice_local_path")
        else {
            return nil
        }

        let uploadStatusRawValue = row.int("voice_upload_status") ?? MediaUploadStatus.pending.rawValue
        guard let uploadStatus = MediaUploadStatus(rawValue: uploadStatusRawValue) else {
            throw ChatStoreError.invalidMediaUploadStatus(uploadStatusRawValue)
        }

        return StoredVoiceContent(
            mediaID: mediaID,
            localPath: localPath,
            durationMilliseconds: row.int("voice_duration_ms") ?? 0,
            sizeBytes: row.int64("voice_size_bytes") ?? 0,
            remoteURL: row.string("voice_cdn_url"),
            format: row.string("voice_format") ?? "m4a",
            uploadStatus: uploadStatus
        )
    }
}
