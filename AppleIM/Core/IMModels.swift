//
//  IMModels.swift
//  AppleIM
//
//  核心 IM 数据模型定义
//  所有类型都满足 Sendable 协议，支持 Swift 6 严格并发检查

import Foundation

/// ChatBridge 时间文案格式化工具。
nonisolated enum ChatBridgeTimeFormatter {
    /// 按微信式层级格式化消息或会话时间。
    nonisolated static func messageTimeText(
        from timestamp: Int64,
        now: Date = Date(),
        calendar inputCalendar: Calendar = .current
    ) -> String {
        guard timestamp > 0 else {
            return ""
        }

        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let calendar = inputCalendar
        let clockText = timeText(from: date, calendar: calendar)

        if calendar.isDate(date, inSameDayAs: now) {
            return clockText
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 \(clockText)"
        }

        if isDateInSameWeek(date, as: now, calendar: calendar) {
            return "\(weekdayText(from: date, calendar: calendar)) \(clockText)"
        }

        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let nowComponents = calendar.dateComponents([.year], from: now)
        let month = dateComponents.month ?? 1
        let day = dateComponents.day ?? 1

        if dateComponents.year == nowComponents.year {
            return "\(month)月\(day)日 \(clockText)"
        }

        return "\((dateComponents.year ?? 0))年\(month)月\(day)日 \(clockText)"
    }

    nonisolated private static func timeText(from date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    nonisolated private static func isDateInSameWeek(_ date: Date, as now: Date, calendar: Calendar) -> Bool {
        let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: date)
        let nowComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: now)
        return dateComponents.weekOfYear == nowComponents.weekOfYear
            && dateComponents.yearForWeekOfYear == nowComponents.yearForWeekOfYear
    }

    nonisolated private static func weekdayText(from date: Date, calendar: Calendar) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1:
            return "星期日"
        case 2:
            return "星期一"
        case 3:
            return "星期二"
        case 4:
            return "星期三"
        case 5:
            return "星期四"
        case 6:
            return "星期五"
        default:
            return "星期六"
        }
    }
}

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

/// 消息已读状态枚举
///
/// 对应数据库 `message.read_status` 字段
nonisolated enum MessageReadStatus: Int, Codable, Sendable {
    /// 未读/未播放
    case unread = 0
    /// 已读/已播放
    case read = 1
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
    /// 会话头像 URL
    let avatarURL: String?
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
    /// 排序时间戳
    let sortTimestamp: Int64
    /// 是否有未读 @ 当前用户提示
    let hasUnreadMention: Bool

    init(
        id: ConversationID,
        type: ConversationType,
        title: String,
        avatarURL: String?,
        lastMessageDigest: String,
        lastMessageTimeText: String,
        unreadCount: Int,
        isPinned: Bool,
        isMuted: Bool,
        draftText: String?,
        sortTimestamp: Int64 = 0,
        hasUnreadMention: Bool = false
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.avatarURL = avatarURL
        self.lastMessageDigest = lastMessageDigest
        self.lastMessageTimeText = lastMessageTimeText
        self.unreadCount = unreadCount
        self.isPinned = isPinned
        self.isMuted = isMuted
        self.draftText = draftText
        self.sortTimestamp = sortTimestamp
        self.hasUnreadMention = hasUnreadMention
    }
}

/// 消息投递标识。
///
/// - `clientMessageID`: 客户端生成的 UUID，用于发送幂等和重试映射。
/// - `serverMessageID`: 服务端返回的正式消息 ID，用于多端同步。
/// - `sequence`: 服务端会话内递增序号，用于排序和增量拉取。
nonisolated struct StoredMessageDelivery: Equatable, Sendable {
    let clientMessageID: String?
    let serverMessageID: String?
    let sequence: Int64?

    init(
        clientMessageID: String?,
        serverMessageID: String?,
        sequence: Int64?
    ) {
        self.clientMessageID = clientMessageID
        self.serverMessageID = serverMessageID
        self.sequence = sequence
    }
}

/// 消息状态字段。
nonisolated struct StoredMessageState: Equatable, Sendable {
    let direction: MessageDirection
    let sendStatus: MessageSendStatus
    let readStatus: MessageReadStatus
    let isRevoked: Bool
    let isDeleted: Bool
    let revokeReplacementText: String?
    let revokeEditableText: String?

    init(
        direction: MessageDirection,
        sendStatus: MessageSendStatus,
        readStatus: MessageReadStatus,
        isRevoked: Bool,
        isDeleted: Bool,
        revokeReplacementText: String?,
        revokeEditableText: String? = nil
    ) {
        self.direction = direction
        self.sendStatus = sendStatus
        self.readStatus = readStatus
        self.isRevoked = isRevoked
        self.isDeleted = isDeleted
        self.revokeReplacementText = revokeReplacementText
        self.revokeEditableText = revokeEditableText
    }
}

/// 消息时间线字段。
///
/// `sortSequence` 是本地排序序号，优先使用 `sequence`，其次 `serverTime`，最后 `localTime`。
nonisolated struct StoredMessageTimeline: Equatable, Sendable {
    let serverTime: Int64?
    let sortSequence: Int64
    let localTime: Int64

    init(
        serverTime: Int64?,
        sortSequence: Int64,
        localTime: Int64
    ) {
        self.serverTime = serverTime
        self.sortSequence = sortSequence
        self.localTime = localTime
    }
}

/// 存储消息内容。
///
/// 每条消息只允许有一个内容分支，避免 `text/image/voice/...` 多个可选字段形成无效组合。
nonisolated enum StoredMessageContent: Equatable, Sendable {
    case text(String)
    case image(StoredImageContent)
    case voice(StoredVoiceContent)
    case video(StoredVideoContent)
    case file(StoredFileContent)
    case emoji(StoredEmojiContent)
    case system(String?)
    case quote(String?)
    case revoked(String?)

    var type: MessageType {
        switch self {
        case .text:
            return .text
        case .image:
            return .image
        case .voice:
            return .voice
        case .video:
            return .video
        case .file:
            return .file
        case .emoji:
            return .emoji
        case .system:
            return .system
        case .quote:
            return .quote
        case .revoked:
            return .revoked
        }
    }
}

/// 存储的消息模型。
///
/// 对应数据库 `message` 主表 + 内容表的聚合查询结果。
nonisolated struct StoredMessage: Identifiable, Equatable, Sendable {
    /// 消息 ID（本地全局唯一）
    let id: MessageID
    /// 所属会话 ID
    let conversationID: ConversationID
    /// 发送者用户 ID
    let senderID: UserID
    /// 消息投递标识
    let delivery: StoredMessageDelivery
    /// 消息状态
    let state: StoredMessageState
    /// 消息时间线
    let timeline: StoredMessageTimeline
    /// 消息内容
    let content: StoredMessageContent

    /// 消息类型由内容分支推导，避免类型和 payload 分离后不一致。
    var type: MessageType {
        content.type
    }

    init(
        id: MessageID,
        conversationID: ConversationID,
        senderID: UserID,
        delivery: StoredMessageDelivery,
        state: StoredMessageState,
        timeline: StoredMessageTimeline,
        content: StoredMessageContent
    ) {
        self.id = id
        self.conversationID = conversationID
        self.senderID = senderID
        self.delivery = delivery
        self.state = state
        self.timeline = timeline
        self.content = content
    }

    /// 构造本地新发出的消息，统一收敛 DAO 插入路径的默认状态。
    init(
        id: MessageID,
        conversationID: ConversationID,
        senderID: UserID,
        clientMessageID: String,
        content: StoredMessageContent,
        sortSequence: Int64,
        localTime: Int64
    ) {
        self.init(
            id: id,
            conversationID: conversationID,
            senderID: senderID,
            delivery: StoredMessageDelivery(
                clientMessageID: clientMessageID,
                serverMessageID: nil,
                sequence: nil
            ),
            state: StoredMessageState(
                direction: .outgoing,
                sendStatus: .sending,
                readStatus: .read,
                isRevoked: false,
                isDeleted: false,
                revokeReplacementText: nil
            ),
            timeline: StoredMessageTimeline(
                serverTime: nil,
                sortSequence: sortSequence,
                localTime: localTime
            ),
            content: content
        )
    }
}
