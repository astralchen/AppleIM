//
//  ConversationListSnapshotPlanner.swift
//  AppleIM
//
//  会话列表 snapshot 规划
//

import Foundation

/// 会话列表 diffable snapshot 操作计划。
nonisolated struct ConversationListSnapshotPlan: Equatable, Sendable {
    /// 需要执行的 snapshot 操作。
    enum Operation: Equatable, Sendable {
        /// 重建整个会话分区。
        case rebuild(animatingDifferences: Bool)
        /// 仅追加分页新行。
        case append(newRowIDs: [ConversationID])
        /// 仅刷新已有可见行内容。
        case reconfigure
        /// 无需更新 snapshot。
        case none
    }

    /// 主要 snapshot 操作。
    let operation: Operation
    /// 需要在同一次 snapshot 中刷新内容的既有会话。
    let reconfiguredRowIDs: [ConversationID]
}

/// 将列表状态变化归约成稳定、可测试的 snapshot 更新策略。
nonisolated enum ConversationListSnapshotPlanner {
    static func plan(
        previousRowIDs: [ConversationID],
        rowIDs: [ConversationID],
        changedRowIDs: [ConversationID],
        phase: ConversationListViewState.LoadingPhase,
        renderIntent: ConversationListViewState.RenderIntent
    ) -> ConversationListSnapshotPlan {
        let currentIDSet = Set(rowIDs)
        let previousIDSet = Set(previousRowIDs)
        let existingChangedRowIDs = changedRowIDs.filter { currentIDSet.contains($0) && previousIDSet.contains($0) }

        guard !previousRowIDs.isEmpty else {
            return ConversationListSnapshotPlan(operation: .rebuild(animatingDifferences: false), reconfiguredRowIDs: [])
        }

        guard phase != .loading else {
            return ConversationListSnapshotPlan(operation: .rebuild(animatingDifferences: false), reconfiguredRowIDs: existingChangedRowIDs)
        }

        guard rowIDs.count >= previousRowIDs.count else {
            return ConversationListSnapshotPlan(operation: .rebuild(animatingDifferences: false), reconfiguredRowIDs: existingChangedRowIDs)
        }

        guard rowIDs.starts(with: previousRowIDs) else {
            return ConversationListSnapshotPlan(
                operation: .rebuild(animatingDifferences: renderIntent == .simulatedIncoming),
                reconfiguredRowIDs: existingChangedRowIDs
            )
        }

        if rowIDs.count > previousRowIDs.count {
            let newRowIDs = Array(rowIDs.dropFirst(previousRowIDs.count))
            let newIDSet = Set(newRowIDs)
            return ConversationListSnapshotPlan(
                operation: .append(newRowIDs: newRowIDs),
                reconfiguredRowIDs: existingChangedRowIDs.filter { !newIDSet.contains($0) }
            )
        }

        if !existingChangedRowIDs.isEmpty {
            return ConversationListSnapshotPlan(operation: .reconfigure, reconfiguredRowIDs: existingChangedRowIDs)
        }

        return ConversationListSnapshotPlan(operation: .none, reconfiguredRowIDs: [])
    }
}
