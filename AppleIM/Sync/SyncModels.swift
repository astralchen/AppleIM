//
//  SyncModels.swift
//  AppleIM
//
//  同步模型
//  定义增量同步相关的数据结构

import Foundation

/// 同步检查点
///
/// 记录上次同步的位置，用于增量拉取
nonisolated struct SyncCheckpoint: Equatable, Sendable {
    /// 业务 key
    let bizKey: String
    /// 游标（服务端返回的分页标记）
    let cursor: String?
    /// 序号（服务端返回的最大序号）
    let sequence: Int64?
    /// 更新时间
    let updatedAt: Int64
}

/// 收到的同步消息
///
/// 从服务端拉取的增量消息数据
nonisolated struct IncomingSyncMessage: Equatable, Sendable {
    /// 消息 ID
    let messageID: MessageID
    /// 会话 ID
    let conversationID: ConversationID
    /// 发送者 ID
    let senderID: UserID
    /// 客户端消息 ID
    let clientMessageID: String?
    /// 服务端消息 ID
    let serverMessageID: String?
    /// 序号
    let sequence: Int64
    /// 文本内容
    let text: String
    /// 服务端时间戳
    let serverTime: Int64
    /// 本地时间戳
    let localTime: Int64
    /// 消息方向
    let direction: MessageDirection
    /// 会话标题
    let conversationTitle: String?
    /// 会话类型
    let conversationType: ConversationType
    /// 被 @ 的用户列表
    let mentionedUserIDs: [UserID]
    /// 是否 @ 所有人
    let mentionsAll: Bool

    init(
        messageID: MessageID,
        conversationID: ConversationID,
        senderID: UserID,
        clientMessageID: String? = nil,
        serverMessageID: String?,
        sequence: Int64,
        text: String,
        serverTime: Int64,
        localTime: Int64? = nil,
        direction: MessageDirection = .incoming,
        conversationTitle: String? = nil,
        conversationType: ConversationType = .single,
        mentionedUserIDs: [UserID] = [],
        mentionsAll: Bool = false
    ) {
        self.messageID = messageID
        self.conversationID = conversationID
        self.senderID = senderID
        self.clientMessageID = clientMessageID
        self.serverMessageID = serverMessageID
        self.sequence = sequence
        self.text = text
        self.serverTime = serverTime
        self.localTime = localTime ?? serverTime
        self.direction = direction
        self.conversationTitle = conversationTitle
        self.conversationType = conversationType
        self.mentionedUserIDs = mentionedUserIDs
        self.mentionsAll = mentionsAll
    }
}

/// 同步批次
///
/// 服务端返回的一批增量数据
nonisolated struct SyncBatch: Equatable, Sendable {
    /// 业务 key
    let bizKey: String
    /// 消息数组
    let messages: [IncomingSyncMessage]
    /// 下一页游标
    let nextCursor: String?
    /// 下一页序号
    let nextSequence: Int64?
    /// 是否还有更多数据
    let hasMore: Bool

    init(
        bizKey: String = SyncEngineActor.messageBizKey,
        messages: [IncomingSyncMessage],
        nextCursor: String?,
        nextSequence: Int64?,
        hasMore: Bool = false
    ) {
        self.bizKey = bizKey
        self.messages = messages
        self.nextCursor = nextCursor
        self.nextSequence = nextSequence
        self.hasMore = hasMore
    }
}

/// 同步应用结果
///
/// 应用一批增量数据后的统计信息
nonisolated struct SyncApplyResult: Equatable, Sendable {
    /// 拉取的消息数
    let fetchedCount: Int
    /// 插入的消息数
    let insertedCount: Int
    /// 跳过的重复消息数
    let skippedDuplicateCount: Int
    /// 新的检查点
    let checkpoint: SyncCheckpoint
}

/// 同步结果
///
/// 单次同步操作的结果
nonisolated struct SyncResult: Equatable, Sendable {
    /// 上次检查点
    let previousCheckpoint: SyncCheckpoint?
    /// 拉取的消息数
    let fetchedCount: Int
    /// 插入的消息数
    let insertedCount: Int
    /// 跳过的重复消息数
    let skippedDuplicateCount: Int
    /// 新的检查点
    let checkpoint: SyncCheckpoint
}

/// 同步运行结果
///
/// 多批次同步的汇总结果
nonisolated struct SyncRunResult: Equatable, Sendable {
    /// 批次数
    let batchCount: Int
    /// 总拉取消息数
    let fetchedCount: Int
    /// 总插入消息数
    let insertedCount: Int
    /// 总跳过重复消息数
    let skippedDuplicateCount: Int
    /// 初始检查点
    let initialCheckpoint: SyncCheckpoint?
    /// 最终检查点
    let finalCheckpoint: SyncCheckpoint
}

/// 同步引擎错误
nonisolated enum SyncEngineError: Error, Equatable, Sendable {
    /// 无效的最大批次数
    case invalidMaxBatches
    /// 超过最大批次数
    case exceededMaxBatches(Int)
}

/// 同步存储协议
protocol SyncStore: Sendable {
    /// 获取同步检查点
    func syncCheckpoint(for bizKey: String) async throws -> SyncCheckpoint?
    /// 应用增量同步批次
    func applyIncomingSyncBatch(_ batch: SyncBatch, userID: UserID) async throws -> SyncApplyResult
}
