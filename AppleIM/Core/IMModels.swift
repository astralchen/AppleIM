//
//  IMModels.swift
//  AppleIM
//
//  核心 IM 数据模型定义
//  所有类型都满足 Sendable 协议，支持 Swift 6 严格并发检查

import Foundation

/// 会话类型枚举
///
/// 对应数据库 `conversation.biz_type` 字段
nonisolated enum ConversationType: Int, Codable, Sendable {
    /// 单聊
    case single = 1
    /// 群聊
    case group = 2
    /// 系统会话
    case system = 3
    /// 服务号/订阅号
    case service = 4
}

/// 消息类型枚举
///
/// 对应数据库 `message.msg_type` 字段
/// 不同消息类型对应不同的内容表（`message_text`、`message_image` 等）
nonisolated enum MessageType: Int, Codable, Sendable {
    /// 文本消息
    case text = 1
    /// 图片消息
    case image = 2
    /// 语音消息
    case voice = 3
    /// 视频消息
    case video = 4
    /// 文件消息
    case file = 5
    /// 系统消息
    case system = 8
    /// 撤回消息
    case revoked = 9
    /// 表情消息
    case emoji = 10
    /// 引用消息
    case quote = 11
}

/// 消息发送状态枚举
///
/// 对应数据库 `message.send_status` 字段
/// 用于跟踪消息发送流程：`pending` -> `sending` -> `success`/`failed`
nonisolated enum MessageSendStatus: Int, Codable, Sendable {
    /// 待发送（断网或排队中）
    case pending = 0
    /// 发送中（正在请求服务端）
    case sending = 1
    /// 发送成功（已收到服务端 ack）
    case success = 2
    /// 发送失败（需要重试）
    case failed = 3
}

/// 消息方向枚举
///
/// 对应数据库 `message.direction` 字段
nonisolated enum MessageDirection: Int, Codable, Sendable {
    /// 发出的消息
    case outgoing = 1
    /// 收到的消息
    case incoming = 2
}

/// 会话模型
///
/// 用于会话列表展示，包含冗余字段以避免实时聚合消息表
/// 对应数据库 `conversation` 表
nonisolated struct Conversation: Identifiable, Equatable, Sendable {
    /// 会话 ID
    let id: ConversationID
    /// 会话类型
    let type: ConversationType
    /// 会话标题（单聊为对方昵称，群聊为群名）
    let title: String
    /// 最后一条消息摘要
    let lastMessageDigest: String
    /// 最后一条消息时间文本
    let lastMessageTimeText: String
    /// 未读数
    let unreadCount: Int
    /// 是否置顶
    let isPinned: Bool
    /// 是否免打扰
    let isMuted: Bool
    /// 草稿文本
    let draftText: String?
}

/// 存储的消息模型
///
/// 对应数据库 `message` 主表 + 内容表的聚合查询结果
/// 包含消息主表字段和对应内容表字段
///
/// ## 重要说明
///
/// - `clientMessageID`: 客户端生成的 UUID，用于发送幂等和重试映射
/// - `serverMessageID`: 服务端返回的正式消息 ID，用于多端同步
/// - `sequence`: 服务端会话内递增序号，用于排序和增量拉取
/// - `sortSequence`: 本地排序序号，优先使用 `sequence`，其次 `serverTime`，最后 `localTime`
nonisolated struct StoredMessage: Identifiable, Equatable, Sendable {
    /// 消息 ID（本地全局唯一）
    let id: MessageID
    /// 所属会话 ID
    let conversationID: ConversationID
    /// 发送者用户 ID
    let senderID: UserID
    /// 客户端消息 ID（用于幂等）
    let clientMessageID: String?
    /// 服务端消息 ID（用于同步）
    let serverMessageID: String?
    /// 服务端序号（用于排序）
    let sequence: Int64?
    /// 消息类型
    let type: MessageType
    /// 消息方向
    let direction: MessageDirection
    /// 发送状态
    let sendStatus: MessageSendStatus
    /// 服务端时间戳（毫秒）
    let serverTime: Int64?
    /// 是否已撤回
    let isRevoked: Bool
    /// 是否已删除（逻辑删除）
    let isDeleted: Bool
    /// 撤回后的替代文本
    let revokeReplacementText: String?
    /// 文本内容（仅文本消息）
    let text: String?
    /// 图片内容（仅图片消息）
    let image: StoredImageContent?
    /// 语音内容（仅语音消息）
    let voice: StoredVoiceContent?
    /// 排序序号
    let sortSequence: Int64
    /// 本地时间戳（毫秒）
    let localTime: Int64
}
