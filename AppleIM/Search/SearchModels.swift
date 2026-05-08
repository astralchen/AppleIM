//
//  SearchModels.swift
//  AppleIM
//
//  Search module models.

import Foundation

/// 搜索结果类型
nonisolated enum SearchResultKind: String, Codable, Sendable {
    /// 联系人结果
    case contact
    /// 会话结果
    case conversation
    /// 消息结果
    case message
}

/// 搜索索引返回的原始记录
nonisolated struct SearchResultRecord: Equatable, Sendable {
    /// 结果类型
    let kind: SearchResultKind
    /// 类型内唯一 ID
    let id: String
    /// 主标题
    let title: String
    /// 副标题或摘要
    let subtitle: String
    /// 关联会话 ID
    let conversationID: ConversationID?
    /// 关联消息 ID
    let messageID: MessageID?
}

/// 按类型分组后的搜索结果集合
nonisolated struct SearchResults: Equatable, Sendable {
    /// 联系人结果
    var contacts: [SearchResultRecord] = []
    /// 会话结果
    var conversations: [SearchResultRecord] = []
    /// 消息结果
    var messages: [SearchResultRecord] = []

    /// 是否没有任何搜索结果
    var isEmpty: Bool {
        contacts.isEmpty && conversations.isEmpty && messages.isEmpty
    }
}

/// 搜索结果列表行状态
nonisolated struct SearchResultRowState: Identifiable, Hashable, Sendable {
    /// 列表行稳定 ID，包含结果类型前缀
    let id: String
    /// 结果类型
    let kind: SearchResultKind
    /// 主标题
    let title: String
    /// 副标题或摘要
    let subtitle: String
    /// 关联会话 ID
    let conversationID: ConversationID?
    /// 关联消息 ID
    let messageID: MessageID?

    /// 根据搜索记录生成 UI 行状态
    init(record: SearchResultRecord) {
        self.id = "\(record.kind.rawValue)_\(record.id)"
        self.kind = record.kind
        self.title = record.title
        self.subtitle = record.subtitle
        self.conversationID = record.conversationID
        self.messageID = record.messageID
    }
}

/// 搜索页状态
nonisolated struct SearchViewState: Equatable, Sendable {
    /// 搜索加载阶段
    enum Phase: Equatable, Sendable {
        /// 未输入搜索词
        case idle
        /// 正在搜索
        case loading
        /// 搜索已完成
        case loaded
        /// 搜索失败并携带展示文案
        case failed(String)
    }

    /// 当前搜索词
    var query = ""
    /// 当前加载阶段
    var phase: Phase = .idle
    /// 联系人行
    var contacts: [SearchResultRowState] = []
    /// 会话行
    var conversations: [SearchResultRowState] = []
    /// 消息行
    var messages: [SearchResultRowState] = []

    /// 是否处于有关键词的搜索状态
    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 是否没有任何行可展示
    var isEmpty: Bool {
        contacts.isEmpty && conversations.isEmpty && messages.isEmpty
    }
}
