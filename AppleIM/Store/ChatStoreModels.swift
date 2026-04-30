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
    /// 更新时间
    let updatedAt: Int64

    static func defaultSetting(for userID: UserID) -> NotificationSettingRecord {
        NotificationSettingRecord(
            userID: userID,
            isEnabled: true,
            showPreview: true,
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

/// 发出的文本消息输入参数
nonisolated struct OutgoingTextMessageInput: Equatable, Sendable {
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
    /// 消息 ID（可选，不传则自动生成）
    let messageID: MessageID?
    /// 客户端消息 ID（可选，不传则使用 messageID）
    let clientMessageID: String?
    /// 排序序号（可选，不传则使用 localTime）
    let sortSequence: Int64?

    init(
        userID: UserID,
        conversationID: ConversationID,
        senderID: UserID,
        text: String,
        localTime: Int64,
        messageID: MessageID? = nil,
        clientMessageID: String? = nil,
        sortSequence: Int64? = nil
    ) {
        self.userID = userID
        self.conversationID = conversationID
        self.senderID = senderID
        self.text = text
        self.localTime = localTime
        self.messageID = messageID
        self.clientMessageID = clientMessageID
        self.sortSequence = sortSequence
    }
}

/// 存储的图片内容
///
/// 包含图片的元数据和本地路径
nonisolated struct StoredImageContent: Equatable, Sendable {
    /// 媒体 ID
    let mediaID: String
    /// 原图本地路径
    let localPath: String
    /// 缩略图本地路径
    let thumbnailPath: String
    /// 宽度（像素）
    let width: Int
    /// 高度（像素）
    let height: Int
    /// 文件大小（字节）
    let sizeBytes: Int64
    /// 远程 CDN URL
    let remoteURL: String?
    /// 文件摘要
    let md5: String?
    /// 图片格式（jpg、png 等）
    let format: String
    /// 上传状态
    let uploadStatus: MediaUploadStatus

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
        self.mediaID = mediaID
        self.localPath = localPath
        self.thumbnailPath = thumbnailPath
        self.width = width
        self.height = height
        self.sizeBytes = sizeBytes
        self.remoteURL = remoteURL
        self.md5 = md5
        self.format = format
        self.uploadStatus = uploadStatus
    }
}

/// 存储的语音内容
///
/// 包含语音文件元数据和本地路径
nonisolated struct StoredVoiceContent: Equatable, Sendable {
    /// 媒体 ID
    let mediaID: String
    /// 语音本地路径
    let localPath: String
    /// 时长（毫秒）
    let durationMilliseconds: Int
    /// 文件大小（字节）
    let sizeBytes: Int64
    /// 远程 CDN URL
    let remoteURL: String?
    /// 语音格式（m4a、aac 等）
    let format: String
    /// 上传状态
    let uploadStatus: MediaUploadStatus

    init(
        mediaID: String,
        localPath: String,
        durationMilliseconds: Int,
        sizeBytes: Int64,
        remoteURL: String? = nil,
        format: String,
        uploadStatus: MediaUploadStatus = .pending
    ) {
        self.mediaID = mediaID
        self.localPath = localPath
        self.durationMilliseconds = durationMilliseconds
        self.sizeBytes = sizeBytes
        self.remoteURL = remoteURL
        self.format = format
        self.uploadStatus = uploadStatus
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
    /// 用户 ID
    let userID: UserID
    /// 会话 ID
    let conversationID: ConversationID
    /// 发送者 ID
    let senderID: UserID
    /// 图片内容
    let image: StoredImageContent
    /// 本地时间戳
    let localTime: Int64
    /// 消息 ID（可选，不传则自动生成）
    let messageID: MessageID?
    /// 客户端消息 ID（可选，不传则使用 messageID）
    let clientMessageID: String?
    /// 排序序号（可选，不传则使用 localTime）
    let sortSequence: Int64?

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
        self.userID = userID
        self.conversationID = conversationID
        self.senderID = senderID
        self.image = image
        self.localTime = localTime
        self.messageID = messageID
        self.clientMessageID = clientMessageID
        self.sortSequence = sortSequence
    }
}

/// 发出的语音消息输入参数
nonisolated struct OutgoingVoiceMessageInput: Equatable, Sendable {
    /// 用户 ID
    let userID: UserID
    /// 会话 ID
    let conversationID: ConversationID
    /// 发送者 ID
    let senderID: UserID
    /// 语音内容
    let voice: StoredVoiceContent
    /// 本地时间戳
    let localTime: Int64
    /// 消息 ID（可选，不传则自动生成）
    let messageID: MessageID?
    /// 客户端消息 ID（可选，不传则使用 messageID）
    let clientMessageID: String?
    /// 排序序号（可选，不传则使用 localTime）
    let sortSequence: Int64?

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
        self.userID = userID
        self.conversationID = conversationID
        self.senderID = senderID
        self.voice = voice
        self.localTime = localTime
        self.messageID = messageID
        self.clientMessageID = clientMessageID
        self.sortSequence = sortSequence
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

/// 会话仓储协议
protocol ConversationRepository: Sendable {
    /// 查询会话列表
    func listConversations(for userID: UserID) async throws -> [Conversation]
    /// 插入或更新会话
    func upsertConversation(_ record: ConversationRecord) async throws
    /// 标记会话已读
    func markConversationRead(conversationID: ConversationID, userID: UserID) async throws
}

/// 通知设置仓储协议
protocol NotificationSettingsRepository: Sendable {
    /// 读取通知设置
    func notificationSetting(for userID: UserID) async throws -> NotificationSettingRecord
}

/// 消息仓储协议
protocol MessageRepository: Sendable {
    /// 插入发出的文本消息
    func insertOutgoingTextMessage(_ input: OutgoingTextMessageInput) async throws -> StoredMessage
    /// 插入发出的图片消息
    func insertOutgoingImageMessage(_ input: OutgoingImageMessageInput) async throws -> StoredMessage
    /// 插入发出的语音消息
    func insertOutgoingVoiceMessage(_ input: OutgoingVoiceMessageInput) async throws -> StoredMessage
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
}
