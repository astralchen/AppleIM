//
//  TemporaryMediaFileManager.swift
//  AppleIM
//
//  临时媒体文件管理
//  收口图片库、录音等 UI 流程中的临时文件创建、清理和存在性检查

import Foundation

/// 临时媒体文件管理接口。
nonisolated protocol TemporaryMediaFileManaging: Sendable {
    /// 创建临时文件 URL。
    func makeTemporaryFileURL(prefix: String, fileExtension: String) -> URL
    /// 创建空文件。
    @discardableResult
    func createEmptyFile(at url: URL) -> Bool
    /// 删除临时文件，文件不存在时忽略。
    func removeFileIfExists(at url: URL)
    /// 判断文件是否存在。
    func fileExists(at url: URL) -> Bool
}

/// 基于 FileManager 的临时媒体文件管理器。
nonisolated struct DefaultTemporaryMediaFileManager: TemporaryMediaFileManaging {
    static let shared = DefaultTemporaryMediaFileManager()

    init() {}

    func makeTemporaryFileURL(prefix: String, fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
    }

    @discardableResult
    func createEmptyFile(at url: URL) -> Bool {
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }

    func removeFileIfExists(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
