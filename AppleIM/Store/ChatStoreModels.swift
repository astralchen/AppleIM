//
//  ChatStoreModels.swift
//  AppleIM
//
//  聊天存储模型
//  定义数据库操作相关的数据结构和错误类型

import Foundation

/// 聊天存储错误
nonisolated enum ChatStoreError: Error, Equatable, Sendable {
    /// 缺少列
    case missingColumn(String)
    /// 无效的会话类型
    case invalidConversationType(Int)
    /// 无效的消息类型
    case invalidMessageType(Int)
    /// 无效的消息方向
    case invalidMessageDirection(Int)
    /// 无效的消息发送状态
    case invalidMessageSendStatus(Int)
    /// 无效的消息已读状态
    case invalidMessageReadStatus(Int)
    /// 无效的待处理任务类型
    case invalidPendingJobType(Int)
    /// 无效的待处理任务状态
    case invalidPendingJobStatus(Int)
    /// 无效的媒体上传状态
    case invalidMediaUploadStatus(Int)
    /// 无效的表情类型
    case invalidEmojiType(Int)
    /// 无效的表情包状态
    case invalidEmojiPackageStatus(Int)
    /// 消息未找到
    case messageNotFound(MessageID)
    /// 消息无法重发
    case messageCannotBeResent(MessageID)
}

/// 通知设置记录
///
/// 对应 notification_setting 表；未配置时使用默认开启、展示预览。
nonisolated struct NotificationSettingRecord: Equatable, Sendable {
    /// 用户 ID
    let userID: UserID
    /// 是否开启通知
    let isEnabled: Bool
    /// 是否展示消息预览
    let showPreview: Bool
    /// 是否开启 App 角标
    let badgeEnabled: Bool
    /// 免打扰会话是否计入 App 角标
    let badgeIncludeMuted: Bool
    /// 更新时间
    let updatedAt: Int64

    static func defaultSetting(for userID: UserID) -> NotificationSettingRecord {
        NotificationSettingRecord(
            userID: userID,
            isEnabled: true,
            showPreview: true,
            badgeEnabled: true,
            badgeIncludeMuted: true,
            updatedAt: 0
        )
    }
}

/// 会话记录
///
/// 对应数据库 conversation 表的完整记录
nonisolated struct ConversationRecord: Equatable, Sendable {
    /// 会话 ID
    let id: ConversationID
    /// 用户 ID
    let userID: UserID
    /// 会话类型
    let type: ConversationType
    /// 目标 ID（单聊为对方 ID，群聊为群 ID）
    let targetID: String
    /// 会话标题
    let title: String
    /// 头像 URL
    let avatarURL: String?
    /// 最后一条消息 ID
    let lastMessageID: MessageID?
    /// 最后一条消息时间
    let lastMessageTime: Int64?
    /// 最后一条消息摘要
    let lastMessageDigest: String
    /// 未读数
    let unreadCount: Int
    /// 草稿文本
    let draftText: String?
    /// 是否置顶
    let isPinned: Bool
    /// 是否免打扰
    let isMuted: Bool
    /// 是否隐藏
    let isHidden: Bool
    /// 排序时间戳
    let sortTimestamp: Int64
    /// 更新时间
    let updatedAt: Int64
    /// 创建时间
    let createdAt: Int64
}

/// 会话列表分页游标。
///
/// 使用与会话列表一致的排序键，避免新消息或置顶变更导致 offset 分页窗口漂移。
nonisolated struct ConversationPageCursor: Equatable, Sendable {
    /// 是否置顶
    let isPinned: Bool
    /// 排序时间戳
    let sortTimestamp: Int64
    /// 会话 ID，作为相同时间戳下的稳定排序兜底
    let conversationID: ConversationID

    init(isPinned: Bool, sortTimestamp: Int64, conversationID: ConversationID) {
        self.isPinned = isPinned
        self.sortTimestamp = sortTimestamp
        self.conversationID = conversationID
    }

    init(record: ConversationRecord) {
        self.init(
            isPinned: record.isPinned,
            sortTimestamp: record.sortTimestamp,
            conversationID: record.id
        )
    }

    init(conversation: Conversation) {
        self.init(
            isPinned: conversation.isPinned,
            sortTimestamp: conversation.sortTimestamp,
            conversationID: conversation.id
        )
    }
}

/// 发出消息的公共输入信封。
///
/// 收敛不同消息类型共有的发送上下文，具体内容由各 input 自己保存。
nonisolated struct OutgoingMessageEnvelope: Equatable, Sendable {
    let userID: UserID
    let conversationID: ConversationID
    let senderID: UserID
    let localTime: Int64
    let messageID: MessageID?
    let clientMessageID: String?
    let sortSequence: Int64?

    init(
        userID: UserID,
        conversationID: ConversationID,
        senderID: UserID,
        localTime: Int64,
        messageID: MessageID? = nil,
        clientMessageID: String? = nil,
        sortSequence: Int64? = nil
    ) {
        self.userID = userID
        self.conversationID = conversationID
        self.senderID = senderID
        self.localTime = localTime
        self.messageID = messageID
        self.clientMessageID = clientMessageID
        self.sortSequence = sortSequence
    }
}

/// 初始演示文本消息输入参数。
///
/// 仅用于首次账号 seed，将会话摘要背后的演示消息落到真实消息表。
nonisolated struct InitialTextMessageInput: Equatable, Sendable {
    /// 用户 ID
    let userID: UserID
    /// 会话 ID
    let conversationID: ConversationID
    /// 发送者 ID
    let senderID: UserID
    /// 文本内容
    let text: String
    /// 本地时间戳
    let localTime: Int64
    /// 消息 ID
    let messageID: MessageID
    /// 客户端消息 ID
    let clientMessageID: String?
    /// 服务端消息 ID
    let serverMessageID: String?
    /// 服务端序号
    let sequence: Int64?
    /// 消息方向
    let direction: MessageDirection
    /// 已读状态
    let readStatus: MessageReadStatus
    /// 排序序号
    let sortSequence: Int64

    init(
        userID: UserID,
        conversationID: ConversationID,
        senderID: UserID,
        text: String,
        localTime: Int64,
        messageID: MessageID,
        clientMessageID: String? = nil,
        serverMessageID: String? = nil,
        sequence: Int64? = nil,
        direction: MessageDirection,
        readStatus: MessageReadStatus,
        sortSequence: Int64
    ) {
        self.userID = userID
        self.conversationID = conversationID
        self.senderID = senderID
        self.text = text
        self.localTime = localTime
        self.messageID = messageID
        self.clientMessageID = clientMessageID
        self.serverMessageID = serverMessageID
        self.sequence = sequence
        self.direction = direction
        self.readStatus = readStatus
        self.sortSequence = sortSequence
    }
}

/// 发出的文本消息输入参数
nonisolated struct OutgoingTextMessageInput: Equatable, Sendable {
    /// 公共发送上下文
    let envelope: OutgoingMessageEnvelope
    /// 文本内容
    let text: String
    /// 被 @ 的用户 ID 列表
    let mentionedUserIDs: [UserID]
    /// 是否 @ 所有人
    let mentionsAll: Bool

    var userID: UserID { envelope.userID }
    var conversationID: ConversationID { envelope.conversationID }
    var senderID: UserID { envelope.senderID }
    var localTime: Int64 { envelope.localTime }
    var messageID: MessageID? { envelope.messageID }
    var clientMessageID: String? { envelope.clientMessageID }
    var sortSequence: Int64? { envelope.sortSequence }

    init(
        userID: UserID,
        conversationID: ConversationID,
        senderID: UserID,
        text: String,
        localTime: Int64,
        messageID: MessageID? = nil,
        clientMessageID: String? = nil,
        mentionedUserIDs: [UserID] = [],
        mentionsAll: Bool = false,
        sortSequence: Int64? = nil
    ) {
        self.init(
            envelope: OutgoingMessageEnvelope(
                userID: userID,
                conversationID: conversationID,
                senderID: senderID,
                localTime: localTime,
                messageID: messageID,
                clientMessageID: clientMessageID,
                sortSequence: sortSequence
            ),
            text: text,
            mentionedUserIDs: mentionedUserIDs,
            mentionsAll: mentionsAll
        )
    }

    init(
        envelope: OutgoingMessageEnvelope,
        text: String,
        mentionedUserIDs: [UserID] = [],
        mentionsAll: Bool = false
    ) {
        self.envelope = envelope
        self.text = text
        self.mentionedUserIDs = mentionedUserIDs
        self.mentionsAll = mentionsAll
    }
}

/// 群成员角色
nonisolated enum GroupMemberRole: Int, Codable, Equatable, Sendable {
    /// 普通成员
    case member = 0
    /// 管理员
    case admin = 1
    /// 群主
    case owner = 2

    var canManageAnnouncement: Bool {
        self == .admin || self == .owner
    }
}

/// 群成员记录
nonisolated struct GroupMember: Equatable, Sendable {
    let conversationID: ConversationID
    let memberID: UserID
    let displayName: String
    let role: GroupMemberRole
    let joinTime: Int64?
}

/// 群公告
nonisolated struct GroupAnnouncement: Equatable, Sendable {
    let conversationID: ConversationID
    let text: String
    let updatedBy: UserID
    let updatedAt: Int64
}

/// 群聊本地错误
nonisolated enum GroupChatError: Error, Equatable, Sendable {
    case permissionDenied
}

/// 存储媒体内容的公共资源快照。
///
/// 对应各类媒体内容表与 media_resource 中共有的资源字段。
nonisolated struct StoredMediaResourceSnapshot: Equatable, Sendable {
    let mediaID: String
    let localPath: String
    let sizeBytes: Int64
    let remoteURL: String?
    let md5: String?
    let uploadStatus: MediaUploadStatus

    init(
        mediaID: String,
        localPath: String,
        sizeBytes: Int64,
        remoteURL: String? = nil,
        md5: String? = nil,
        uploadStatus: MediaUploadStatus = .pending
    ) {
        self.mediaID = mediaID
        self.localPath = localPath
        self.sizeBytes = sizeBytes
        self.remoteURL = remoteURL
        self.md5 = md5
        self.uploadStatus = uploadStatus
    }
}

/// 存储的图片内容
///
/// 包含图片的元数据和本地路径
nonisolated struct StoredImageContent: Equatable, Sendable {
    /// 公共媒体资源快照
    let resource: StoredMediaResourceSnapshot
    /// 缩略图本地路径
    let thumbnailPath: String
    /// 宽度（像素）
    let width: Int
    /// 高度（像素）
    let height: Int
    /// 图片格式（jpg、png 等）
    let format: String

    var mediaID: String { resource.mediaID }
    var localPath: String { resource.localPath }
    var sizeBytes: Int64 { resource.sizeBytes }
    var remoteURL: String? { resource.remoteURL }
    var md5: String? { resource.md5 }
    var uploadStatus: MediaUploadStatus { resource.uploadStatus }

    init(
        mediaID: String,
        localPath: String,
        thumbnailPath: String,
        width: Int,
        height: Int,
        sizeBytes: Int64,
        remoteURL: String? = nil,
        md5: String? = nil,
        format: String,
        uploadStatus: MediaUploadStatus = .pending
    ) {
        self.init(
            resource: StoredMediaResourceSnapshot(
                mediaID: mediaID,
                localPath: localPath,
                sizeBytes: sizeBytes,
                remoteURL: remoteURL,
                md5: md5,
                uploadStatus: uploadStatus
            ),
            thumbnailPath: thumbnailPath,
            width: width,
            height: height,
            format: format
        )
    }

    init(
        resource: StoredMediaResourceSnapshot,
        thumbnailPath: String,
        width: Int,
        height: Int,
        format: String
    ) {
        self.resource = resource
        self.thumbnailPath = thumbnailPath
        self.width = width
        self.height = height
        self.format = format
    }
}

/// 存储的语音内容
///
/// 包含语音文件元数据和本地路径
nonisolated struct StoredVoiceContent: Equatable, Sendable {
    /// 公共媒体资源快照
    let resource: StoredMediaResourceSnapshot
    /// 时长（毫秒）
    let durationMilliseconds: Int
    /// 语音格式（m4a、aac 等）
    let format: String

    var mediaID: String { resource.mediaID }
    var localPath: String { resource.localPath }
    var sizeBytes: Int64 { resource.sizeBytes }
    var remoteURL: String? { resource.remoteURL }
    var md5: String? { resource.md5 }
    var uploadStatus: MediaUploadStatus { resource.uploadStatus }

    init(
        mediaID: String,
        localPath: String,
        durationMilliseconds: Int,
        sizeBytes: Int64,
        remoteURL: String? = nil,
        format: String,
        uploadStatus: MediaUploadStatus = .pending
    ) {
        self.init(
            resource: StoredMediaResourceSnapshot(
                mediaID: mediaID,
                localPath: localPath,
                sizeBytes: sizeBytes,
                remoteURL: remoteURL,
                md5: nil,
                uploadStatus: uploadStatus
            ),
            durationMilliseconds: durationMilliseconds,
            format: format
        )
    }

    init(
        resource: StoredMediaResourceSnapshot,
        durationMilliseconds: Int,
        format: String
    ) {
        self.resource = resource
        self.durationMilliseconds = durationMilliseconds
        self.format = format
    }
}

/// 存储的视频内容
nonisolated struct StoredVideoContent: Equatable, Sendable {
    /// 公共媒体资源快照
    let resource: StoredMediaResourceSnapshot
    /// 缩略图本地路径
    let thumbnailPath: String
    /// 时长（毫秒）
    let durationMilliseconds: Int
    /// 宽度（像素）
    let width: Int
    /// 高度（像素）
    let height: Int

    var mediaID: String { resource.mediaID }
    var localPath: String { resource.localPath }
    var sizeBytes: Int64 { resource.sizeBytes }
    var remoteURL: String? { resource.remoteURL }
    var md5: String? { resource.md5 }
    var uploadStatus: MediaUploadStatus { resource.uploadStatus }

    init(
        mediaID: String,
        localPath: String,
        thumbnailPath: String,
        durationMilliseconds: Int,
        width: Int,
        height: Int,
        sizeBytes: Int64,
        remoteURL: String? = nil,
        md5: String? = nil,
        uploadStatus: MediaUploadStatus = .pending
    ) {
        self.init(
            resource: StoredMediaResourceSnapshot(
                mediaID: mediaID,
                localPath: localPath,
                sizeBytes: sizeBytes,
                remoteURL: remoteURL,
                md5: md5,
                uploadStatus: uploadStatus
            ),
            thumbnailPath: thumbnailPath,
            durationMilliseconds: durationMilliseconds,
            width: width,
            height: height
        )
    }

    init(
        resource: StoredMediaResourceSnapshot,
        thumbnailPath: String,
        durationMilliseconds: Int,
        width: Int,
        height: Int
    ) {
        self.resource = resource
        self.thumbnailPath = thumbnailPath
        self.durationMilliseconds = durationMilliseconds
        self.width = width
        self.height = height
    }
}

/// 存储的文件内容
nonisolated struct StoredFileContent: Equatable, Sendable {
    /// 公共媒体资源快照
    let resource: StoredMediaResourceSnapshot
    /// 文件名
    let fileName: String
    /// 文件扩展名
    let fileExtension: String?

    var mediaID: String { resource.mediaID }
    var localPath: String { resource.localPath }
    var sizeBytes: Int64 { resource.sizeBytes }
    var remoteURL: String? { resource.remoteURL }
    var md5: String? { resource.md5 }
    var uploadStatus: MediaUploadStatus { resource.uploadStatus }

    init(
        mediaID: String,
        localPath: String,
        fileName: String,
        fileExtension: String?,
        sizeBytes: Int64,
        remoteURL: String? = nil,
        md5: String? = nil,
        uploadStatus: MediaUploadStatus = .pending
    ) {
        self.init(
            resource: StoredMediaResourceSnapshot(
                mediaID: mediaID,
                localPath: localPath,
                sizeBytes: sizeBytes,
                remoteURL: remoteURL,
                md5: md5,
                uploadStatus: uploadStatus
            ),
            fileName: fileName,
            fileExtension: fileExtension
        )
    }

    init(
        resource: StoredMediaResourceSnapshot,
        fileName: String,
        fileExtension: String?
    ) {
        self.resource = resource
        self.fileName = fileName
        self.fileExtension = fileExtension
    }
}

/// 媒体上传状态
nonisolated enum MediaUploadStatus: Int, Codable, Sendable {
    /// 待上传
    case pending = 0
    /// 上传中
    case uploading = 1
    /// 上传成功
    case success = 2
    /// 上传失败
    case failed = 3
}

/// 发出的图片消息输入参数
nonisolated struct OutgoingImageMessageInput: Equatable, Sendable {
    /// 公共发送上下文
    let envelope: OutgoingMessageEnvelope
    /// 图片内容
    let image: StoredImageContent

    var userID: UserID { envelope.userID }
    var conversationID: ConversationID { envelope.conversationID }
    var senderID: UserID { envelope.senderID }
    var localTime: Int64 { envelope.localTime }
    var messageID: MessageID? { envelope.messageID }
    var clientMessageID: String? { envelope.clientMessageID }
    var sortSequence: Int64? { envelope.sortSequence }

    init(
        userID: UserID,
        conversationID: ConversationID,
        senderID: UserID,
        image: StoredImageContent,
        localTime: Int64,
        messageID: MessageID? = nil,
        clientMessageID: String? = nil,
        sortSequence: Int64? = nil
    ) {
        self.init(
            envelope: OutgoingMessageEnvelope(
                userID: userID,
                conversationID: conversationID,
                senderID: senderID,
                localTime: localTime,
                messageID: messageID,
                clientMessageID: clientMessageID,
                sortSequence: sortSequence
            ),
            image: image
        )
    }

    init(envelope: OutgoingMessageEnvelope, image: StoredImageContent) {
        self.envelope = envelope
        self.image = image
    }
}

/// 发出的语音消息输入参数
nonisolated struct OutgoingVoiceMessageInput: Equatable, Sendable {
    /// 公共发送上下文
    let envelope: OutgoingMessageEnvelope
    /// 语音内容
    let voice: StoredVoiceContent

    var userID: UserID { envelope.userID }
    var conversationID: ConversationID { envelope.conversationID }
    var senderID: UserID { envelope.senderID }
    var localTime: Int64 { envelope.localTime }
    var messageID: MessageID? { envelope.messageID }
    var clientMessageID: String? { envelope.clientMessageID }
    var sortSequence: Int64? { envelope.sortSequence }

    init(
        userID: UserID,
        conversationID: ConversationID,
        senderID: UserID,
        voice: StoredVoiceContent,
        localTime: Int64,
        messageID: MessageID? = nil,
        clientMessageID: String? = nil,
        sortSequence: Int64? = nil
    ) {
        self.init(
            envelope: OutgoingMessageEnvelope(
                userID: userID,
                conversationID: conversationID,
                senderID: senderID,
                localTime: localTime,
                messageID: messageID,
                clientMessageID: clientMessageID,
                sortSequence: sortSequence
            ),
            voice: voice
        )
    }

    init(envelope: OutgoingMessageEnvelope, voice: StoredVoiceContent) {
        self.envelope = envelope
        self.voice = voice
    }
}

/// 发出的视频消息输入参数
nonisolated struct OutgoingVideoMessageInput: Equatable, Sendable {
    let envelope: OutgoingMessageEnvelope
    let video: StoredVideoContent

    var userID: UserID { envelope.userID }
    var conversationID: ConversationID { envelope.conversationID }
    var senderID: UserID { envelope.senderID }
    var localTime: Int64 { envelope.localTime }
    var messageID: MessageID? { envelope.messageID }
    var clientMessageID: String? { envelope.clientMessageID }
    var sortSequence: Int64? { envelope.sortSequence }

    init(
        userID: UserID,
        conversationID: ConversationID,
        senderID: UserID,
        video: StoredVideoContent,
        localTime: Int64,
        messageID: MessageID? = nil,
        clientMessageID: String? = nil,
        sortSequence: Int64? = nil
    ) {
        self.init(
            envelope: OutgoingMessageEnvelope(
                userID: userID,
                conversationID: conversationID,
                senderID: senderID,
                localTime: localTime,
                messageID: messageID,
                clientMessageID: clientMessageID,
                sortSequence: sortSequence
            ),
            video: video
        )
    }

    init(envelope: OutgoingMessageEnvelope, video: StoredVideoContent) {
        self.envelope = envelope
        self.video = video
    }
}

/// 发出的文件消息输入参数
nonisolated struct OutgoingFileMessageInput: Equatable, Sendable {
    let envelope: OutgoingMessageEnvelope
    let file: StoredFileContent

    var userID: UserID { envelope.userID }
    var conversationID: ConversationID { envelope.conversationID }
    var senderID: UserID { envelope.senderID }
    var localTime: Int64 { envelope.localTime }
    var messageID: MessageID? { envelope.messageID }
    var clientMessageID: String? { envelope.clientMessageID }
    var sortSequence: Int64? { envelope.sortSequence }

    init(
        userID: UserID,
        conversationID: ConversationID,
        senderID: UserID,
        file: StoredFileContent,
        localTime: Int64,
        messageID: MessageID? = nil,
        clientMessageID: String? = nil,
        sortSequence: Int64? = nil
    ) {
        self.init(
            envelope: OutgoingMessageEnvelope(
                userID: userID,
                conversationID: conversationID,
                senderID: senderID,
                localTime: localTime,
                messageID: messageID,
                clientMessageID: clientMessageID,
                sortSequence: sortSequence
            ),
            file: file
        )
    }

    init(envelope: OutgoingMessageEnvelope, file: StoredFileContent) {
        self.envelope = envelope
        self.file = file
    }
}

/// 待处理任务类型
nonisolated enum PendingJobType: Int, Codable, Sendable {
    /// 消息重发
    case messageResend = 1
    /// 图片上传
    case imageUpload = 2
    /// 视频上传
    case videoUpload = 3
    /// 文件上传
    case fileUpload = 4
    /// 媒体下载
    case mediaDownload = 5
    /// 缩略图生成
    case thumbnailGeneration = 6
    /// 搜索索引修复
    case searchIndexRepair = 7
    /// 消息补偿同步
    case messageCompensationSync = 8
}

/// 待处理任务状态
nonisolated enum PendingJobStatus: Int, Codable, Sendable {
    /// 待处理
    case pending = 0
    /// 运行中
    case running = 1
    /// 成功
    case success = 2
    /// 失败
    case failed = 3
    /// 已取消
    case cancelled = 4
}

/// 待处理任务
///
/// 对应数据库 pending_job 表
nonisolated struct PendingJob: Identifiable, Equatable, Sendable {
    /// 任务 ID
    let id: String
    /// 用户 ID
    let userID: UserID
    /// 任务类型
    let type: PendingJobType
    /// 业务 key
    let bizKey: String?
    /// 载荷 JSON
    let payloadJSON: String
    /// 任务状态
    let status: PendingJobStatus
    /// 重试次数
    let retryCount: Int
    /// 最大重试次数
    let maxRetryCount: Int
    /// 下次重试时间
    let nextRetryAt: Int64?
    /// 更新时间
    let updatedAt: Int64
    /// 创建时间
    let createdAt: Int64

    func decodedPayload() throws -> PendingJobPayload {
        try PendingJobPayload.decode(payloadJSON, type: type)
    }
}

/// 待处理任务输入参数
nonisolated struct PendingJobInput: Equatable, Sendable {
    /// 任务 ID
    let id: String
    /// 用户 ID
    let userID: UserID
    /// 任务类型
    let type: PendingJobType
    /// 业务 key
    let bizKey: String?
    /// 载荷 JSON
    let payloadJSON: String
    /// 最大重试次数
    let maxRetryCount: Int
    /// 下次重试时间
    let nextRetryAt: Int64?

    init(
        id: String,
        userID: UserID,
        type: PendingJobType,
        bizKey: String?,
        payloadJSON: String,
        maxRetryCount: Int = 3,
        nextRetryAt: Int64? = nil
    ) {
        self.id = id
        self.userID = userID
        self.type = type
        self.bizKey = bizKey
        self.payloadJSON = payloadJSON
        self.maxRetryCount = maxRetryCount
        self.nextRetryAt = nextRetryAt
    }

    func decodedPayload() throws -> PendingJobPayload {
        try PendingJobPayload.decode(payloadJSON, type: type)
    }
}

/// 消息重发待处理任务载荷
nonisolated struct MessageResendPendingJobPayload: Codable, Equatable, Sendable {
    let messageID: String
    let conversationID: String
    let clientMessageID: String
    let lastFailureReason: MessageSendFailureReason?
}

/// 媒体上传待处理任务载荷。
nonisolated struct MediaUploadPendingJobPayload: Codable, Equatable, Sendable {
    let messageID: String
    let conversationID: String
    let clientMessageID: String
    let mediaID: String
    let lastFailureReason: String?
}

typealias ImageUploadPendingJobPayload = MediaUploadPendingJobPayload
typealias VideoUploadPendingJobPayload = MediaUploadPendingJobPayload
typealias FileUploadPendingJobPayload = MediaUploadPendingJobPayload

/// 搜索索引修复任务载荷。
nonisolated struct SearchIndexRepairPendingJobPayload: Codable, Equatable, Sendable {
    let scope: String
    let messageID: String?
    let conversationID: String?
}

/// 媒体下载任务载荷。
nonisolated struct MediaDownloadPendingJobPayload: Codable, Equatable, Sendable {
    let mediaID: String
    let ownerMessageID: String?
    let localPath: String
    let remoteURL: String
}

/// 待处理任务的类型化载荷。
nonisolated enum PendingJobPayload: Equatable, Sendable {
    case messageResend(MessageResendPendingJobPayload)
    case mediaUpload(MediaUploadPendingJobPayload)
    case searchIndexRepair(SearchIndexRepairPendingJobPayload)
    case mediaDownload(MediaDownloadPendingJobPayload)

    var jobType: PendingJobType {
        switch self {
        case .messageResend:
            return .messageResend
        case .mediaUpload:
            return .imageUpload
        case .searchIndexRepair:
            return .searchIndexRepair
        case .mediaDownload:
            return .mediaDownload
        }
    }

    func encodedJSON() throws -> String {
        switch self {
        case let .messageResend(payload):
            return try Self.payloadJSON(from: payload)
        case let .mediaUpload(payload):
            return try Self.payloadJSON(from: payload)
        case let .searchIndexRepair(payload):
            return try Self.payloadJSON(from: payload)
        case let .mediaDownload(payload):
            return try Self.payloadJSON(from: payload)
        }
    }

    static func decode(_ payloadJSON: String, type: PendingJobType) throws -> PendingJobPayload {
        let data = Data(payloadJSON.utf8)
        let decoder = JSONDecoder()

        switch type {
        case .messageResend:
            return .messageResend(try decoder.decode(MessageResendPendingJobPayload.self, from: data))
        case .imageUpload, .videoUpload, .fileUpload:
            return .mediaUpload(try decoder.decode(MediaUploadPendingJobPayload.self, from: data))
        case .searchIndexRepair:
            return .searchIndexRepair(try decoder.decode(SearchIndexRepairPendingJobPayload.self, from: data))
        case .mediaDownload:
            return .mediaDownload(try decoder.decode(MediaDownloadPendingJobPayload.self, from: data))
        case .thumbnailGeneration, .messageCompensationSync:
            throw ChatStoreError.missingColumn("pending_job_payload")
        }
    }

    private static func payloadJSON<T: Encodable>(from payload: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let payloadData = try encoder.encode(payload)

        guard let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            throw ChatStoreError.missingColumn("pending_job_payload")
        }

        return payloadJSON
    }
}

/// 消息待处理任务构造器
nonisolated enum PendingMessageJobFactory {
    static func messageResendJobID(clientMessageID: String) -> String {
        "message_resend_\(clientMessageID)"
    }

    static func imageUploadJobID(clientMessageID: String) -> String {
        "image_upload_\(clientMessageID)"
    }

    static func videoUploadJobID(clientMessageID: String) -> String {
        "video_upload_\(clientMessageID)"
    }

    static func fileUploadJobID(clientMessageID: String) -> String {
        "file_upload_\(clientMessageID)"
    }

    static func messageResendInput(
        messageID: MessageID,
        conversationID: ConversationID,
        clientMessageID: String,
        userID: UserID,
        failureReason: MessageSendFailureReason?,
        maxRetryCount: Int,
        nextRetryAt: Int64?
    ) throws -> PendingJobInput {
        let payload = MessageResendPendingJobPayload(
            messageID: messageID.rawValue,
            conversationID: conversationID.rawValue,
            clientMessageID: clientMessageID,
            lastFailureReason: failureReason
        )

        return PendingJobInput(
            id: messageResendJobID(clientMessageID: clientMessageID),
            userID: userID,
            type: .messageResend,
            bizKey: clientMessageID,
            payloadJSON: try PendingJobPayload.messageResend(payload).encodedJSON(),
            maxRetryCount: maxRetryCount,
            nextRetryAt: nextRetryAt
        )
    }

    static func imageUploadInput(
        messageID: MessageID,
        conversationID: ConversationID,
        clientMessageID: String,
        mediaID: String,
        userID: UserID,
        failureReason: String?,
        maxRetryCount: Int,
        nextRetryAt: Int64?
    ) throws -> PendingJobInput {
        try mediaUploadInput(
            type: .imageUpload,
            jobID: imageUploadJobID(clientMessageID: clientMessageID),
            messageID: messageID,
            conversationID: conversationID,
            clientMessageID: clientMessageID,
            mediaID: mediaID,
            userID: userID,
            failureReason: failureReason,
            maxRetryCount: maxRetryCount,
            nextRetryAt: nextRetryAt
        )
    }

    static func videoUploadInput(
        messageID: MessageID,
        conversationID: ConversationID,
        clientMessageID: String,
        mediaID: String,
        userID: UserID,
        failureReason: String?,
        maxRetryCount: Int,
        nextRetryAt: Int64?
    ) throws -> PendingJobInput {
        try mediaUploadInput(
            type: .videoUpload,
            jobID: videoUploadJobID(clientMessageID: clientMessageID),
            messageID: messageID,
            conversationID: conversationID,
            clientMessageID: clientMessageID,
            mediaID: mediaID,
            userID: userID,
            failureReason: failureReason,
            maxRetryCount: maxRetryCount,
            nextRetryAt: nextRetryAt
        )
    }

    static func fileUploadInput(
        messageID: MessageID,
        conversationID: ConversationID,
        clientMessageID: String,
        mediaID: String,
        userID: UserID,
        failureReason: String?,
        maxRetryCount: Int,
        nextRetryAt: Int64?
    ) throws -> PendingJobInput {
        try mediaUploadInput(
            type: .fileUpload,
            jobID: fileUploadJobID(clientMessageID: clientMessageID),
            messageID: messageID,
            conversationID: conversationID,
            clientMessageID: clientMessageID,
            mediaID: mediaID,
            userID: userID,
            failureReason: failureReason,
            maxRetryCount: maxRetryCount,
            nextRetryAt: nextRetryAt
        )
    }

    private static func mediaUploadInput(
        type: PendingJobType,
        jobID: String,
        messageID: MessageID,
        conversationID: ConversationID,
        clientMessageID: String,
        mediaID: String,
        userID: UserID,
        failureReason: String?,
        maxRetryCount: Int,
        nextRetryAt: Int64?
    ) throws -> PendingJobInput {
        let payload = MediaUploadPendingJobPayload(
            messageID: messageID.rawValue,
            conversationID: conversationID.rawValue,
            clientMessageID: clientMessageID,
            mediaID: mediaID,
            lastFailureReason: failureReason
        )

        return PendingJobInput(
            id: jobID,
            userID: userID,
            type: type,
            bizKey: clientMessageID,
            payloadJSON: try PendingJobPayload.mediaUpload(payload).encodedJSON(),
            maxRetryCount: maxRetryCount,
            nextRetryAt: nextRetryAt
        )
    }
}

/// 崩溃恢复结果
nonisolated struct MessageCrashRecoveryResult: Equatable, Sendable {
    /// 扫描到的发送中消息数
    let scannedMessageCount: Int
    /// 恢复为 pending 的消息数
    let recoveredMessageCount: Int
    /// 补建或更新的待处理任务数
    let pendingJobCount: Int
    /// 标记为失败的消息数
    let failedMessageCount: Int
}

/// 媒体文件索引记录
///
/// 对应 file_index.db 的 file_index 表
nonisolated struct MediaIndexRecord: Equatable, Sendable {
    /// 媒体 ID
    let mediaID: String
    /// 用户 ID
    let userID: UserID
    /// 本地路径
    let localPath: String
    /// 文件名
    let fileName: String?
    /// 文件扩展名
    let fileExtension: String?
    /// 文件大小
    let sizeBytes: Int64?
    /// 文件摘要
    let md5: String?
    /// 最近访问时间
    let lastAccessAt: Int64?
    /// 创建时间
    let createdAt: Int64
}

/// 缺失的媒体资源
///
/// 用于识别本地文件丢失但可通过远端地址恢复的媒体
nonisolated struct MissingMediaResource: Equatable, Sendable {
    /// 媒体 ID
    let mediaID: String
    /// 用户 ID
    let userID: UserID
    /// 归属消息 ID
    let ownerMessageID: MessageID?
    /// 本地路径
    let localPath: String
    /// 远端 URL
    let remoteURL: String
}

/// 媒体索引重建结果。
nonisolated struct MediaIndexRebuildResult: Equatable, Sendable {
    /// 扫描到的媒体资源数
    let scannedResourceCount: Int
    /// 重建的 file_index 记录数
    let rebuiltIndexCount: Int
    /// 本地文件丢失但具备远端地址的资源数
    let missingResourceCount: Int
    /// 创建或更新的媒体下载任务数
    let createdDownloadJobCount: Int
}

/// 数据修复步骤。
nonisolated enum DataRepairStep: String, Equatable, Sendable {
    case integrityCheck
    case ftsRebuild
    case mediaIndexRebuild
}

/// 单个数据修复步骤的执行结果。
nonisolated struct DataRepairStepReport: Equatable, Sendable {
    let step: DataRepairStep
    let isSuccessful: Bool
    let errorDescription: String?
}

/// 数据修复结构化报告。
nonisolated struct DataRepairReport: Equatable, Sendable {
    let userID: UserID
    let integrityResults: [DatabaseIntegrityCheckResult]
    let mediaIndexRebuildResult: MediaIndexRebuildResult?
    let steps: [DataRepairStepReport]

    var isSuccessful: Bool {
        steps.allSatisfy(\.isSuccessful)
    }
}

/// 会话仓储协议
protocol ConversationRepository: Sendable {
    /// 查询会话列表
    func listConversations(for userID: UserID) async throws -> [Conversation]
    /// 分页查询会话列表
    func listConversations(for userID: UserID, limit: Int, after cursor: ConversationPageCursor?) async throws -> [Conversation]
    /// 插入或更新会话
    func upsertConversation(_ record: ConversationRecord) async throws
    /// 标记会话已读
    func markConversationRead(conversationID: ConversationID, userID: UserID) async throws
    /// 更新会话置顶状态
    func updateConversationPin(conversationID: ConversationID, userID: UserID, isPinned: Bool) async throws
    /// 更新会话免打扰状态
    func updateConversationMute(conversationID: ConversationID, userID: UserID, isMuted: Bool) async throws
    /// 查询群成员
    func groupMembers(conversationID: ConversationID) async throws -> [GroupMember]
    /// 查询当前用户群角色
    func currentMemberRole(conversationID: ConversationID, userID: UserID) async throws -> GroupMemberRole?
    /// 查询群公告
    func groupAnnouncement(conversationID: ConversationID) async throws -> GroupAnnouncement?
    /// 更新群公告
    func updateGroupAnnouncement(conversationID: ConversationID, userID: UserID, text: String) async throws
}

extension ConversationRepository {
    func groupMembers(conversationID: ConversationID) async throws -> [GroupMember] {
        []
    }

    func currentMemberRole(conversationID: ConversationID, userID: UserID) async throws -> GroupMemberRole? {
        nil
    }

    func groupAnnouncement(conversationID: ConversationID) async throws -> GroupAnnouncement? {
        nil
    }

    func updateGroupAnnouncement(conversationID: ConversationID, userID: UserID, text: String) async throws {
        throw GroupChatError.permissionDenied
    }
}

/// 通知设置仓储协议
protocol NotificationSettingsRepository: Sendable {
    /// 读取通知设置
    func notificationSetting(for userID: UserID) async throws -> NotificationSettingRecord
    /// 更新 App 角标开关
    func updateBadgeEnabled(userID: UserID, isEnabled: Bool) async throws
    /// 更新免打扰会话是否计入 App 角标
    func updateBadgeIncludeMuted(userID: UserID, includeMuted: Bool) async throws
    /// 刷新 App 角标并返回最终角标数
    func refreshApplicationBadge(userID: UserID) async throws -> Int
}

/// 消息仓储协议
protocol MessageRepository: Sendable {
    /// 插入发出的文本消息
    func insertOutgoingTextMessage(_ input: OutgoingTextMessageInput) async throws -> StoredMessage
    /// 插入发出的图片消息
    func insertOutgoingImageMessage(_ input: OutgoingImageMessageInput) async throws -> StoredMessage
    /// 插入发出的语音消息
    func insertOutgoingVoiceMessage(_ input: OutgoingVoiceMessageInput) async throws -> StoredMessage
    /// 插入发出的视频消息
    func insertOutgoingVideoMessage(_ input: OutgoingVideoMessageInput) async throws -> StoredMessage
    /// 插入发出的文件消息
    func insertOutgoingFileMessage(_ input: OutgoingFileMessageInput) async throws -> StoredMessage
    /// 插入发出的表情消息
    func insertOutgoingEmojiMessage(_ input: OutgoingEmojiMessageInput) async throws -> StoredMessage
    /// 查询消息列表
    func listMessages(conversationID: ConversationID, limit: Int, beforeSortSeq: Int64?) async throws -> [StoredMessage]
    /// 查询单条消息
    func message(messageID: MessageID) async throws -> StoredMessage?
    /// 更新消息发送状态
    func updateMessageSendStatus(messageID: MessageID, status: MessageSendStatus, ack: MessageSendAck?) async throws
    /// 重发文本消息
    func resendTextMessage(messageID: MessageID) async throws -> StoredMessage
    /// 重发图片消息
    func resendImageMessage(messageID: MessageID) async throws -> StoredMessage
    /// 重发视频消息
    func resendVideoMessage(messageID: MessageID) async throws -> StoredMessage
    /// 重发文件消息
    func resendFileMessage(messageID: MessageID) async throws -> StoredMessage
    /// 更新图片上传和消息发送状态
    func updateImageUploadStatus(
        messageID: MessageID,
        uploadStatus: MediaUploadStatus,
        uploadAck: MediaUploadAck?,
        sendStatus: MessageSendStatus,
        sendAck: MessageSendAck?,
        pendingJob: PendingJobInput?
    ) async throws
    /// 更新语音上传和消息发送状态
    func updateVoiceUploadStatus(
        messageID: MessageID,
        uploadStatus: MediaUploadStatus,
        uploadAck: MediaUploadAck?,
        sendStatus: MessageSendStatus,
        sendAck: MessageSendAck?
    ) async throws
    /// 更新视频上传和消息发送状态
    func updateVideoUploadStatus(
        messageID: MessageID,
        uploadStatus: MediaUploadStatus,
        uploadAck: MediaUploadAck?,
        sendStatus: MessageSendStatus,
        sendAck: MessageSendAck?,
        pendingJob: PendingJobInput?
    ) async throws
    /// 更新文件上传和消息发送状态
    func updateFileUploadStatus(
        messageID: MessageID,
        uploadStatus: MediaUploadStatus,
        uploadAck: MediaUploadAck?,
        sendStatus: MessageSendStatus,
        sendAck: MessageSendAck?,
        pendingJob: PendingJobInput?
    ) async throws
    /// 标记语音消息已播放
    func markVoicePlayed(messageID: MessageID) async throws
    /// 标记消息已删除
    func markMessageDeleted(messageID: MessageID, userID: UserID) async throws
    /// 撤回消息
    func revokeMessage(messageID: MessageID, userID: UserID, replacementText: String) async throws -> StoredMessage
    /// 保存草稿
    func saveDraft(conversationID: ConversationID, userID: UserID, text: String) async throws
    /// 查询草稿
    func draft(conversationID: ConversationID, userID: UserID) async throws -> String?
    /// 清空草稿
    func clearDraft(conversationID: ConversationID, userID: UserID) async throws
}

/// 消息发送恢复仓储协议
protocol MessageSendRecoveryRepository: Sendable {
    /// 更新消息发送状态（支持同时创建待处理任务）
    func updateMessageSendStatus(
        messageID: MessageID,
        status: MessageSendStatus,
        ack: MessageSendAck?,
        pendingJob: PendingJobInput?
    ) async throws
}

/// 消息崩溃恢复仓储协议
protocol MessageCrashRecoveryRepository: Sendable {
    /// 恢复崩溃前中断的发送中消息
    func recoverInterruptedOutgoingMessages(
        userID: UserID,
        retryPolicy: MessageRetryPolicy,
        now: Int64
    ) async throws -> MessageCrashRecoveryResult
}

/// 待处理任务仓储协议
protocol PendingJobRepository: Sendable {
    /// 插入或更新待处理任务
    func upsertPendingJob(_ input: PendingJobInput) async throws -> PendingJob
    /// 查询待处理任务
    func pendingJob(id: String) async throws -> PendingJob?
    /// 查询可恢复的待处理任务
    func recoverablePendingJobs(userID: UserID, now: Int64) async throws -> [PendingJob]
    /// 调度待处理任务重试
    func schedulePendingJobRetry(jobID: String, nextRetryAt: Int64) async throws
    /// 更新待处理任务状态
    func updatePendingJobStatus(jobID: String, status: PendingJobStatus, nextRetryAt: Int64?) async throws
}

/// 媒体索引仓储协议
protocol MediaIndexRepository: Sendable {
    /// 插入或更新媒体索引记录
    func upsertMediaIndexRecord(_ record: MediaIndexRecord) async throws
    /// 查询媒体索引记录
    func mediaIndexRecord(mediaID: String, userID: UserID) async throws -> MediaIndexRecord?
    /// 更新媒体索引最近访问时间
    func touchMediaIndexRecord(mediaID: String, userID: UserID, accessedAt: Int64) async throws
    /// 扫描本地文件缺失的媒体资源
    func scanMissingMediaResources(userID: UserID) async throws -> [MissingMediaResource]
    /// 为缺失媒体资源创建下载任务
    func enqueueMediaDownloadJobsForMissingResources(userID: UserID) async throws -> [PendingJob]
    /// 以 media_resource 为真源重建 file_index.db
    func rebuildMediaIndex(userID: UserID) async throws -> MediaIndexRebuildResult
}
