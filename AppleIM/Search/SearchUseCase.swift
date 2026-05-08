//
//  SearchUseCase.swift
//  AppleIM
//
//  全局搜索用例

import Foundation

/// 搜索用例协议
///
/// 定义全局搜索的业务接口
protocol SearchUseCase: Sendable {
    /// 执行搜索
    ///
    /// - Parameter query: 搜索关键词
    /// - Returns: 搜索结果（联系人、会话、消息）
    /// - Throws: 搜索错误
    func search(query: String) async throws -> SearchResults

    /// 重建搜索索引
    ///
    /// 清空并重新构建全部搜索索引
    ///
    /// - Throws: 索引重建错误
    func rebuildIndex() async throws
}

/// 本地搜索用例实现
///
/// 基于 SearchIndexActor 实现的本地全文搜索
nonisolated struct LocalSearchUseCase: SearchUseCase {
    /// 当前用户 ID
    private let userID: UserID
    /// 存储提供者
    private let storeProvider: ChatStoreProvider
    /// 每次搜索返回的最大结果数
    private let limit: Int

    init(userID: UserID, storeProvider: ChatStoreProvider, limit: Int = 20) {
        self.userID = userID
        self.storeProvider = storeProvider
        self.limit = limit
    }

    /// 执行搜索
    ///
    /// 流程：
    /// 1. 清理查询关键词
    /// 2. 调用搜索索引查询
    /// 3. 按类型分组返回结果
    ///
    /// - Parameter query: 搜索关键词
    /// - Returns: 分类后的搜索结果
    /// - Throws: 搜索错误
    func search(query: String) async throws -> SearchResults {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return SearchResults()
        }

        let index = try await storeProvider.searchIndex()
        let records = try await index.search(query: trimmedQuery, limit: limit)

        return SearchResults(
            contacts: records.filter { $0.kind == .contact },
            conversations: records.filter { $0.kind == .conversation },
            messages: records.filter { $0.kind == .message }
        )
    }

    /// 重建搜索索引
    ///
    /// 清空现有索引，重新扫描数据库并构建索引
    ///
    /// - Throws: 索引重建错误
    func rebuildIndex() async throws {
        let index = try await storeProvider.searchIndex()
        try await index.rebuildAll(userID: userID)
    }
}
