//
//  GRDBMessageRecords.swift
//  AppleIM
//
//  GRDB 内部表映射。
//

import Foundation
import GRDB

/// message 表的 GRDB 写入模型。
///
/// 消息列表聚合查询仍保留手写 SQL；这里承载消息主表的插入和单表状态更新。
nonisolated struct MessageDatabaseRecord: FetchableRecord, PersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "message"

    enum Columns {
        static let messageID = Column("message_id")
        static let localID = Column("local_id")
        static let conversationID = Column("conversation_id")
        static let senderID = Column("sender_id")
        static let clientMessageID = Column("client_msg_id")
        static let serverMessageID = Column("server_msg_id")
        static let sequence = Column("seq")
        static let messageType = Column("msg_type")
        static let direction = Column("direction")
        static let sendStatus = Column("send_status")
        static let deliveryStatus = Column("delivery_status")
        static let readStatus = Column("read_status")
        static let revokeStatus = Column("revoke_status")
        static let isDeleted = Column("is_deleted")
        static let quotedMessageID = Column("quoted_message_id")
        static let replyToMessageID = Column("reply_to_message_id")
        static let contentTable = Column("content_table")
        static let contentID = Column("content_id")
        static let sortSequence = Column("sort_seq")
        static let serverTime = Column("server_time")
        static let localTime = Column("local_time")
        static let editVersion = Column("edit_version")
        static let extraJSON = Column("extra_json")
    }

    let messageID: MessageID
    let conversationID: ConversationID
    let senderID: UserID
    let clientMessageID: String?
    let serverMessageID: String?
    let sequence: Int64?
    let messageType: MessageType
    let direction: MessageDirection
    let sendStatus: MessageSendStatus
    let deliveryStatus: Int64
    let readStatus: MessageReadStatus
    let revokeStatus: Int64
    let isDeleted: Bool
    let contentTable: String
    let contentID: String
    let sortSequence: Int64
    let serverTime: Int64?
    let localTime: Int64

    init(
        messageID: MessageID,
        conversationID: ConversationID,
        senderID: UserID,
        clientMessageID: String?,
        serverMessageID: String?,
        sequence: Int64?,
        messageType: MessageType,
        direction: MessageDirection,
        sendStatus: MessageSendStatus,
        deliveryStatus: Int64,
        readStatus: MessageReadStatus,
        revokeStatus: Int64,
        isDeleted: Bool,
        contentTable: String,
        contentID: String,
        sortSequence: Int64,
        serverTime: Int64?,
        localTime: Int64
    ) {
        self.messageID = messageID
        self.conversationID = conversationID
        self.senderID = senderID
        self.clientMessageID = clientMessageID
        self.serverMessageID = serverMessageID
        self.sequence = sequence
        self.messageType = messageType
        self.direction = direction
        self.sendStatus = sendStatus
        self.deliveryStatus = deliveryStatus
        self.readStatus = readStatus
        self.revokeStatus = revokeStatus
        self.isDeleted = isDeleted
        self.contentTable = contentTable
        self.contentID = contentID
        self.sortSequence = sortSequence
        self.serverTime = serverTime
        self.localTime = localTime
    }

    init(row: Row) throws {
        let typeRawValue: Int = row[Columns.messageType]
        let directionRawValue: Int = row[Columns.direction]
        let sendStatusRawValue: Int = row[Columns.sendStatus]
        let readStatusRawValue: Int = row[Columns.readStatus] ?? MessageReadStatus.unread.rawValue

        guard let messageType = MessageType(rawValue: typeRawValue) else {
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

        self.init(
            messageID: MessageID(rawValue: row[Columns.messageID]),
            conversationID: ConversationID(rawValue: row[Columns.conversationID]),
            senderID: UserID(rawValue: row[Columns.senderID]),
            clientMessageID: row[Columns.clientMessageID],
            serverMessageID: row[Columns.serverMessageID],
            sequence: row[Columns.sequence],
            messageType: messageType,
            direction: direction,
            sendStatus: sendStatus,
            deliveryStatus: row[Columns.deliveryStatus] ?? 0,
            readStatus: readStatus,
            revokeStatus: row[Columns.revokeStatus] ?? 0,
            isDeleted: row[Columns.isDeleted],
            contentTable: row[Columns.contentTable],
            contentID: row[Columns.contentID],
            sortSequence: row[Columns.sortSequence],
            serverTime: row[Columns.serverTime],
            localTime: row[Columns.localTime]
        )
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.messageID] = messageID.rawValue
        container[Columns.conversationID] = conversationID.rawValue
        container[Columns.senderID] = senderID.rawValue
        container[Columns.clientMessageID] = clientMessageID
        container[Columns.serverMessageID] = serverMessageID
        container[Columns.sequence] = sequence
        container[Columns.messageType] = messageType.rawValue
        container[Columns.direction] = direction.rawValue
        container[Columns.sendStatus] = sendStatus.rawValue
        container[Columns.deliveryStatus] = deliveryStatus
        container[Columns.readStatus] = readStatus.rawValue
        container[Columns.revokeStatus] = revokeStatus
        container[Columns.isDeleted] = isDeleted
        container[Columns.contentTable] = contentTable
        container[Columns.contentID] = contentID
        container[Columns.sortSequence] = sortSequence
        container[Columns.serverTime] = serverTime
        container[Columns.localTime] = localTime
    }
}

/// message_text 表的 GRDB 写入模型。
nonisolated struct MessageTextDatabaseRecord: FetchableRecord, PersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "message_text"

    enum Columns {
        static let contentID = Column("content_id")
        static let text = Column("text")
        static let mentionsJSON = Column("mentions_json")
        static let atAll = Column("at_all")
        static let richTextJSON = Column("rich_text_json")
    }

    let contentID: String
    let text: String
    let mentionsJSON: String?
    let atAll: Bool
    let richTextJSON: String?

    init(contentID: String, text: String, mentionsJSON: String?, atAll: Bool, richTextJSON: String?) {
        self.contentID = contentID
        self.text = text
        self.mentionsJSON = mentionsJSON
        self.atAll = atAll
        self.richTextJSON = richTextJSON
    }

    init(row: Row) throws {
        self.init(
            contentID: row[Columns.contentID],
            text: row[Columns.text],
            mentionsJSON: row[Columns.mentionsJSON],
            atAll: row[Columns.atAll],
            richTextJSON: row[Columns.richTextJSON]
        )
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.contentID] = contentID
        container[Columns.text] = text
        container[Columns.mentionsJSON] = mentionsJSON
        container[Columns.atAll] = atAll
        container[Columns.richTextJSON] = richTextJSON
    }
}

/// message_image 表的 GRDB 写入模型。
nonisolated struct MessageImageDatabaseRecord: FetchableRecord, PersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "message_image"

    enum Columns {
        static let contentID = Column("content_id")
        static let mediaID = Column("media_id")
        static let width = Column("width")
        static let height = Column("height")
        static let sizeBytes = Column("size_bytes")
        static let localPath = Column("local_path")
        static let thumbPath = Column("thumb_path")
        static let cdnURL = Column("cdn_url")
        static let md5 = Column("md5")
        static let format = Column("format")
        static let uploadStatus = Column("upload_status")
        static let downloadStatus = Column("download_status")
    }

    let contentID: String
    let mediaID: String
    let width: Int
    let height: Int
    let sizeBytes: Int64
    let localPath: String
    let thumbPath: String
    let cdnURL: String?
    let md5: String?
    let format: String
    let uploadStatus: MediaUploadStatus
    let downloadStatus: Int

    init(
        contentID: String,
        mediaID: String,
        width: Int,
        height: Int,
        sizeBytes: Int64,
        localPath: String,
        thumbPath: String,
        cdnURL: String?,
        md5: String?,
        format: String,
        uploadStatus: MediaUploadStatus,
        downloadStatus: Int
    ) {
        self.contentID = contentID
        self.mediaID = mediaID
        self.width = width
        self.height = height
        self.sizeBytes = sizeBytes
        self.localPath = localPath
        self.thumbPath = thumbPath
        self.cdnURL = cdnURL
        self.md5 = md5
        self.format = format
        self.uploadStatus = uploadStatus
        self.downloadStatus = downloadStatus
    }

    init(row: Row) throws {
        let uploadStatusRawValue: Int = row[Columns.uploadStatus] ?? MediaUploadStatus.pending.rawValue
        guard let uploadStatus = MediaUploadStatus(rawValue: uploadStatusRawValue) else {
            throw ChatStoreError.invalidMediaUploadStatus(uploadStatusRawValue)
        }
        self.init(
            contentID: row[Columns.contentID],
            mediaID: row[Columns.mediaID],
            width: row[Columns.width],
            height: row[Columns.height],
            sizeBytes: row[Columns.sizeBytes],
            localPath: row[Columns.localPath],
            thumbPath: row[Columns.thumbPath],
            cdnURL: row[Columns.cdnURL],
            md5: row[Columns.md5],
            format: row[Columns.format],
            uploadStatus: uploadStatus,
            downloadStatus: row[Columns.downloadStatus] ?? 0
        )
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.contentID] = contentID
        container[Columns.mediaID] = mediaID
        container[Columns.width] = width
        container[Columns.height] = height
        container[Columns.sizeBytes] = sizeBytes
        container[Columns.localPath] = localPath
        container[Columns.thumbPath] = thumbPath
        container[Columns.cdnURL] = cdnURL
        container[Columns.md5] = md5
        container[Columns.format] = format
        container[Columns.uploadStatus] = uploadStatus.rawValue
        container[Columns.downloadStatus] = downloadStatus
    }
}

/// message_voice 表的 GRDB 写入模型。
nonisolated struct MessageVoiceDatabaseRecord: FetchableRecord, PersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "message_voice"

    enum Columns {
        static let contentID = Column("content_id")
        static let mediaID = Column("media_id")
        static let durationMilliseconds = Column("duration_ms")
        static let sizeBytes = Column("size_bytes")
        static let localPath = Column("local_path")
        static let cdnURL = Column("cdn_url")
        static let format = Column("format")
        static let transcript = Column("transcript")
        static let playedAt = Column("played_at")
        static let uploadStatus = Column("upload_status")
        static let downloadStatus = Column("download_status")
    }

    let contentID: String
    let mediaID: String
    let durationMilliseconds: Int
    let sizeBytes: Int64
    let localPath: String
    let cdnURL: String?
    let format: String
    let transcript: String?
    let playedAt: Int64?
    let uploadStatus: MediaUploadStatus
    let downloadStatus: Int

    init(
        contentID: String,
        mediaID: String,
        durationMilliseconds: Int,
        sizeBytes: Int64,
        localPath: String,
        cdnURL: String?,
        format: String,
        transcript: String?,
        playedAt: Int64? = nil,
        uploadStatus: MediaUploadStatus,
        downloadStatus: Int
    ) {
        self.contentID = contentID
        self.mediaID = mediaID
        self.durationMilliseconds = durationMilliseconds
        self.sizeBytes = sizeBytes
        self.localPath = localPath
        self.cdnURL = cdnURL
        self.format = format
        self.transcript = transcript
        self.playedAt = playedAt
        self.uploadStatus = uploadStatus
        self.downloadStatus = downloadStatus
    }

    init(row: Row) throws {
        let uploadStatusRawValue: Int = row[Columns.uploadStatus] ?? MediaUploadStatus.pending.rawValue
        guard let uploadStatus = MediaUploadStatus(rawValue: uploadStatusRawValue) else {
            throw ChatStoreError.invalidMediaUploadStatus(uploadStatusRawValue)
        }
        self.init(
            contentID: row[Columns.contentID],
            mediaID: row[Columns.mediaID],
            durationMilliseconds: row[Columns.durationMilliseconds],
            sizeBytes: row[Columns.sizeBytes],
            localPath: row[Columns.localPath],
            cdnURL: row[Columns.cdnURL],
            format: row[Columns.format],
            transcript: row[Columns.transcript],
            playedAt: row[Columns.playedAt],
            uploadStatus: uploadStatus,
            downloadStatus: row[Columns.downloadStatus] ?? 0
        )
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.contentID] = contentID
        container[Columns.mediaID] = mediaID
        container[Columns.durationMilliseconds] = durationMilliseconds
        container[Columns.sizeBytes] = sizeBytes
        container[Columns.localPath] = localPath
        container[Columns.cdnURL] = cdnURL
        container[Columns.format] = format
        container[Columns.transcript] = transcript
        container[Columns.playedAt] = playedAt
        container[Columns.uploadStatus] = uploadStatus.rawValue
        container[Columns.downloadStatus] = downloadStatus
    }
}

/// message_video 表的 GRDB 写入模型。
nonisolated struct MessageVideoDatabaseRecord: FetchableRecord, PersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "message_video"

    enum Columns {
        static let contentID = Column("content_id")
        static let mediaID = Column("media_id")
        static let durationMilliseconds = Column("duration_ms")
        static let width = Column("width")
        static let height = Column("height")
        static let sizeBytes = Column("size_bytes")
        static let localPath = Column("local_path")
        static let thumbPath = Column("thumb_path")
        static let cdnURL = Column("cdn_url")
        static let md5 = Column("md5")
        static let uploadStatus = Column("upload_status")
        static let downloadStatus = Column("download_status")
    }

    let contentID: String
    let mediaID: String
    let durationMilliseconds: Int
    let width: Int
    let height: Int
    let sizeBytes: Int64
    let localPath: String
    let thumbPath: String
    let cdnURL: String?
    let md5: String?
    let uploadStatus: MediaUploadStatus
    let downloadStatus: Int

    init(
        contentID: String,
        mediaID: String,
        durationMilliseconds: Int,
        width: Int,
        height: Int,
        sizeBytes: Int64,
        localPath: String,
        thumbPath: String,
        cdnURL: String?,
        md5: String?,
        uploadStatus: MediaUploadStatus,
        downloadStatus: Int
    ) {
        self.contentID = contentID
        self.mediaID = mediaID
        self.durationMilliseconds = durationMilliseconds
        self.width = width
        self.height = height
        self.sizeBytes = sizeBytes
        self.localPath = localPath
        self.thumbPath = thumbPath
        self.cdnURL = cdnURL
        self.md5 = md5
        self.uploadStatus = uploadStatus
        self.downloadStatus = downloadStatus
    }

    init(row: Row) throws {
        let uploadStatusRawValue: Int = row[Columns.uploadStatus] ?? MediaUploadStatus.pending.rawValue
        guard let uploadStatus = MediaUploadStatus(rawValue: uploadStatusRawValue) else {
            throw ChatStoreError.invalidMediaUploadStatus(uploadStatusRawValue)
        }
        self.init(
            contentID: row[Columns.contentID],
            mediaID: row[Columns.mediaID],
            durationMilliseconds: row[Columns.durationMilliseconds],
            width: row[Columns.width],
            height: row[Columns.height],
            sizeBytes: row[Columns.sizeBytes],
            localPath: row[Columns.localPath],
            thumbPath: row[Columns.thumbPath],
            cdnURL: row[Columns.cdnURL],
            md5: row[Columns.md5],
            uploadStatus: uploadStatus,
            downloadStatus: row[Columns.downloadStatus] ?? 0
        )
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.contentID] = contentID
        container[Columns.mediaID] = mediaID
        container[Columns.durationMilliseconds] = durationMilliseconds
        container[Columns.width] = width
        container[Columns.height] = height
        container[Columns.sizeBytes] = sizeBytes
        container[Columns.localPath] = localPath
        container[Columns.thumbPath] = thumbPath
        container[Columns.cdnURL] = cdnURL
        container[Columns.md5] = md5
        container[Columns.uploadStatus] = uploadStatus.rawValue
        container[Columns.downloadStatus] = downloadStatus
    }
}

/// message_file 表的 GRDB 写入模型。
nonisolated struct MessageFileDatabaseRecord: FetchableRecord, PersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "message_file"

    enum Columns {
        static let contentID = Column("content_id")
        static let mediaID = Column("media_id")
        static let fileName = Column("file_name")
        static let fileExtension = Column("file_ext")
        static let sizeBytes = Column("size_bytes")
        static let localPath = Column("local_path")
        static let cdnURL = Column("cdn_url")
        static let md5 = Column("md5")
        static let uploadStatus = Column("upload_status")
        static let downloadStatus = Column("download_status")
    }

    let contentID: String
    let mediaID: String
    let fileName: String
    let fileExtension: String?
    let sizeBytes: Int64
    let localPath: String
    let cdnURL: String?
    let md5: String?
    let uploadStatus: MediaUploadStatus
    let downloadStatus: Int

    init(
        contentID: String,
        mediaID: String,
        fileName: String,
        fileExtension: String?,
        sizeBytes: Int64,
        localPath: String,
        cdnURL: String?,
        md5: String?,
        uploadStatus: MediaUploadStatus,
        downloadStatus: Int
    ) {
        self.contentID = contentID
        self.mediaID = mediaID
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.sizeBytes = sizeBytes
        self.localPath = localPath
        self.cdnURL = cdnURL
        self.md5 = md5
        self.uploadStatus = uploadStatus
        self.downloadStatus = downloadStatus
    }

    init(row: Row) throws {
        let uploadStatusRawValue: Int = row[Columns.uploadStatus] ?? MediaUploadStatus.pending.rawValue
        guard let uploadStatus = MediaUploadStatus(rawValue: uploadStatusRawValue) else {
            throw ChatStoreError.invalidMediaUploadStatus(uploadStatusRawValue)
        }
        self.init(
            contentID: row[Columns.contentID],
            mediaID: row[Columns.mediaID],
            fileName: row[Columns.fileName],
            fileExtension: row[Columns.fileExtension],
            sizeBytes: row[Columns.sizeBytes],
            localPath: row[Columns.localPath],
            cdnURL: row[Columns.cdnURL],
            md5: row[Columns.md5],
            uploadStatus: uploadStatus,
            downloadStatus: row[Columns.downloadStatus] ?? 0
        )
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.contentID] = contentID
        container[Columns.mediaID] = mediaID
        container[Columns.fileName] = fileName
        container[Columns.fileExtension] = fileExtension
        container[Columns.sizeBytes] = sizeBytes
        container[Columns.localPath] = localPath
        container[Columns.cdnURL] = cdnURL
        container[Columns.md5] = md5
        container[Columns.uploadStatus] = uploadStatus.rawValue
        container[Columns.downloadStatus] = downloadStatus
    }
}

/// message_emoji 表的 GRDB 写入模型。
nonisolated struct MessageEmojiDatabaseRecord: FetchableRecord, PersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "message_emoji"

    enum Columns {
        static let contentID = Column("content_id")
        static let emojiID = Column("emoji_id")
        static let packageID = Column("package_id")
        static let emojiType = Column("emoji_type")
        static let name = Column("name")
        static let localPath = Column("local_path")
        static let thumbPath = Column("thumb_path")
        static let cdnURL = Column("cdn_url")
        static let width = Column("width")
        static let height = Column("height")
        static let sizeBytes = Column("size_bytes")
    }

    let contentID: String
    let emojiID: String
    let packageID: String?
    let emojiType: EmojiType
    let name: String?
    let localPath: String?
    let thumbPath: String?
    let cdnURL: String?
    let width: Int?
    let height: Int?
    let sizeBytes: Int64?

    init(
        contentID: String,
        emojiID: String,
        packageID: String?,
        emojiType: EmojiType,
        name: String?,
        localPath: String?,
        thumbPath: String?,
        cdnURL: String?,
        width: Int?,
        height: Int?,
        sizeBytes: Int64?
    ) {
        self.contentID = contentID
        self.emojiID = emojiID
        self.packageID = packageID
        self.emojiType = emojiType
        self.name = name
        self.localPath = localPath
        self.thumbPath = thumbPath
        self.cdnURL = cdnURL
        self.width = width
        self.height = height
        self.sizeBytes = sizeBytes
    }

    init(row: Row) throws {
        let emojiTypeRawValue: Int = row[Columns.emojiType]
        guard let emojiType = EmojiType(rawValue: emojiTypeRawValue) else {
            throw ChatStoreError.invalidEmojiType(emojiTypeRawValue)
        }
        self.init(
            contentID: row[Columns.contentID],
            emojiID: row[Columns.emojiID],
            packageID: row[Columns.packageID],
            emojiType: emojiType,
            name: row[Columns.name],
            localPath: row[Columns.localPath],
            thumbPath: row[Columns.thumbPath],
            cdnURL: row[Columns.cdnURL],
            width: row[Columns.width],
            height: row[Columns.height],
            sizeBytes: row[Columns.sizeBytes]
        )
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.contentID] = contentID
        container[Columns.emojiID] = emojiID
        container[Columns.packageID] = packageID
        container[Columns.emojiType] = emojiType.rawValue
        container[Columns.name] = name
        container[Columns.localPath] = localPath
        container[Columns.thumbPath] = thumbPath
        container[Columns.cdnURL] = cdnURL
        container[Columns.width] = width
        container[Columns.height] = height
        container[Columns.sizeBytes] = sizeBytes
    }
}


/// draft 表的 GRDB 写入模型。
nonisolated struct DraftDatabaseRecord: FetchableRecord, PersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "draft"

    enum Columns {
        static let conversationID = Column("conversation_id")
        static let text = Column("text")
        static let updatedAt = Column("updated_at")
    }

    let conversationID: ConversationID
    let text: String
    let updatedAt: Int64

    init(conversationID: ConversationID, text: String, updatedAt: Int64) {
        self.conversationID = conversationID
        self.text = text
        self.updatedAt = updatedAt
    }

    init(row: Row) throws {
        self.init(
            conversationID: ConversationID(rawValue: row[Columns.conversationID]),
            text: row[Columns.text],
            updatedAt: row[Columns.updatedAt]
        )
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.conversationID] = conversationID.rawValue
        container[Columns.text] = text
        container[Columns.updatedAt] = updatedAt
    }

    static func upsertRecord(_ record: DraftDatabaseRecord, in db: Database) throws {
        try record.upsert(db)
    }
}

/// message_revoke 表的 GRDB 写入模型。
nonisolated struct MessageRevokeDatabaseRecord: FetchableRecord, PersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "message_revoke"

    enum Columns {
        static let messageID = Column("message_id")
        static let operatorID = Column("operator_id")
        static let revokeTime = Column("revoke_time")
        static let reason = Column("reason")
        static let replaceText = Column("replace_text")
    }

    let messageID: MessageID
    let operatorID: UserID
    let revokeTime: Int64
    let replaceText: String

    init(messageID: MessageID, operatorID: UserID, revokeTime: Int64, replaceText: String) {
        self.messageID = messageID
        self.operatorID = operatorID
        self.revokeTime = revokeTime
        self.replaceText = replaceText
    }

    init(row: Row) throws {
        self.init(
            messageID: MessageID(rawValue: row[Columns.messageID]),
            operatorID: UserID(rawValue: row[Columns.operatorID]),
            revokeTime: row[Columns.revokeTime],
            replaceText: row[Columns.replaceText]
        )
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.messageID] = messageID.rawValue
        container[Columns.operatorID] = operatorID.rawValue
        container[Columns.revokeTime] = revokeTime
        container[Columns.reason] = nil as String?
        container[Columns.replaceText] = replaceText
    }

    static func upsertRecord(_ record: MessageRevokeDatabaseRecord, in db: Database) throws {
        try record.upsert(db)
    }
}

// MARK: - 写入映射
