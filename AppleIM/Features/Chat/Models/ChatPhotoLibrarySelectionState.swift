//
//  ChatPhotoLibrarySelectionState.swift
//  AppleIM
//
//  图片库多选状态
//

import Foundation

/// 图片库多选状态。
nonisolated struct ChatPhotoLibrarySelectionState {
    /// 选择切换结果。
    enum ToggleResult: Equatable {
        /// 已选中。
        case selected
        /// 已取消选择。
        case deselected
        /// 已达到选择上限。
        case limitReached
    }

    /// 最大可选择数量。
    static let maxSelectionCount = 9
    /// 当前已选资源 ID，保留选择顺序。
    private(set) var selectedAssetIDs: [String] = []

    /// 切换资源选择状态。
    mutating func toggle(assetID: String) -> ToggleResult {
        if let existingIndex = selectedAssetIDs.firstIndex(of: assetID) {
            selectedAssetIDs.remove(at: existingIndex)
            return .deselected
        }

        guard selectedAssetIDs.count < Self.maxSelectionCount else {
            return .limitReached
        }

        selectedAssetIDs.append(assetID)
        return .selected
    }

    /// 移除指定资源选择。
    mutating func remove(assetID: String) {
        selectedAssetIDs.removeAll { $0 == assetID }
    }

    /// 清空所有选择。
    mutating func removeAll() {
        selectedAssetIDs.removeAll()
    }

    /// 判断资源是否已选中。
    func contains(assetID: String) -> Bool {
        selectedAssetIDs.contains(assetID)
    }

    /// 返回资源的选择序号。
    func selectionNumber(for assetID: String) -> Int? {
        selectedAssetIDs.firstIndex(of: assetID).map { $0 + 1 }
    }
}
