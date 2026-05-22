//
//  MediaPathResolving.swift
//  AppleIM
//
//  媒体路径解析
//

import Foundation

/// 媒体路径解析接口。
///
/// 负责把旧账号目录下的历史媒体路径映射到当前账号媒体目录。
nonisolated protocol MediaPathResolving: Sendable {
    /// 解析媒体路径。
    ///
    /// - Parameters:
    ///   - storedPath: 数据库存储路径
    ///   - mediaDirectory: 当前账号媒体目录
    /// - Returns: 可用的当前路径；无法映射时返回原路径
    func resolvedMediaPath(_ storedPath: String, mediaDirectory: URL) -> String
}

/// 默认媒体路径解析器。
nonisolated struct DefaultMediaPathResolver: MediaPathResolving {
    private let metadataProvider: any MediaFileMetadataProviding

    init(metadataProvider: any MediaFileMetadataProviding = DefaultMediaFileMetadataProvider()) {
        self.metadataProvider = metadataProvider
    }

    func resolvedMediaPath(_ storedPath: String, mediaDirectory: URL) -> String {
        guard !metadataProvider.fileExists(atPath: storedPath) else {
            return storedPath
        }

        let standardizedPath = URL(fileURLWithPath: storedPath).standardizedFileURL.path
        guard let mediaRange = standardizedPath.range(of: "/media/") else {
            return storedPath
        }

        let relativeMediaPath = String(standardizedPath[mediaRange.upperBound...])
        let currentPath = mediaDirectory.appendingPathComponent(relativeMediaPath).path
        guard metadataProvider.fileExists(atPath: currentPath) else {
            return storedPath
        }
        return currentPath
    }
}
