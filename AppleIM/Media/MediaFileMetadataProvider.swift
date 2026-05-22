//
//  MediaFileMetadataProvider.swift
//  AppleIM
//
//  媒体文件元数据读取边界
//

import Foundation

/// 媒体文件元数据读取能力。
nonisolated protocol MediaFileMetadataProviding: Sendable {
    /// 文件是否存在。
    func fileExists(atPath path: String) -> Bool
    /// 文件大小，读取失败或不存在时返回 nil。
    func fileSize(atPath path: String) -> Int64?
}

/// 基于 FileManager 的默认媒体文件元数据读取器。
nonisolated struct DefaultMediaFileMetadataProvider: MediaFileMetadataProviding {
    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func fileSize(atPath path: String) -> Int64? {
        guard
            fileExists(atPath: path),
            let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber
        else {
            return nil
        }

        return size.int64Value
    }
}
