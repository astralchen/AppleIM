//
//  ChatPhotoLibraryMediaPreparationService.swift
//  AppleIM
//
//  相册媒体准备服务
//

import Foundation
@preconcurrency import Photos

/// 相册媒体准备错误。
nonisolated enum ChatPhotoLibraryMediaPreparationError: Error, Sendable {
    /// 无法创建临时文件。
    case unableToCreateTemporaryFile
    /// 无法打开临时文件。
    case unableToOpenFile
    /// 无法关闭临时文件。
    case unableToCloseFile
    /// Photos 资源请求失败。
    case requestFailed
}

/// 相册媒体准备接口。
@MainActor
protocol ChatPhotoLibraryMediaPreparing: AnyObject {
    /// 将 Photos 视频资源准备成本地临时文件。
    func prepareVideoResource(
        _ resource: PHAssetResource,
        fileExtension: String,
        resourceManager: PHAssetResourceManager,
        options: PHAssetResourceRequestOptions,
        completion: @escaping @MainActor (Result<URL, ChatPhotoLibraryMediaPreparationError>) -> Void
    )

    /// 清理已经准备出的临时媒体文件。
    func removePreparedMediaFileIfExists(at url: URL)
}

/// 默认相册媒体准备服务。
@MainActor
final class DefaultChatPhotoLibraryMediaPreparationService: ChatPhotoLibraryMediaPreparing {
    private let temporaryFileManager: any TemporaryMediaFileManaging

    init(temporaryFileManager: any TemporaryMediaFileManaging = DefaultTemporaryMediaFileManager.shared) {
        self.temporaryFileManager = temporaryFileManager
    }

    func prepareVideoResource(
        _ resource: PHAssetResource,
        fileExtension: String,
        resourceManager: PHAssetResourceManager,
        options: PHAssetResourceRequestOptions,
        completion: @escaping @MainActor (Result<URL, ChatPhotoLibraryMediaPreparationError>) -> Void
    ) {
        let temporaryURL = temporaryFileManager.makeTemporaryFileURL(
            prefix: "ChatBridgeVideoPick",
            fileExtension: fileExtension
        )

        guard temporaryFileManager.createEmptyFile(at: temporaryURL) else {
            completion(.failure(.unableToCreateTemporaryFile))
            return
        }

        stream(
            resource,
            to: temporaryURL,
            resourceManager: resourceManager,
            options: options,
            completion: completion
        )
    }

    func removePreparedMediaFileIfExists(at url: URL) {
        temporaryFileManager.removeFileIfExists(at: url)
    }

    /// 创建资源数据接收回调。
    nonisolated static func makeDataReceivedHandler(fileHandle: FileHandle) -> (Data) -> Void {
        { data in
            fileHandle.write(data)
        }
    }

    /// 创建 Photos 资源请求完成回调。
    nonisolated static func makeCompletionHandler(
        fileHandle: FileHandle,
        temporaryFileManager: any TemporaryMediaFileManaging,
        temporaryURL: URL,
        completion: @escaping @MainActor (Result<URL, ChatPhotoLibraryMediaPreparationError>) -> Void
    ) -> (Error?) -> Void {
        { error in
            let result: Result<URL, ChatPhotoLibraryMediaPreparationError>
            do {
                try fileHandle.close()
            } catch {
                temporaryFileManager.removeFileIfExists(at: temporaryURL)
                result = .failure(.unableToCloseFile)
                Task { @MainActor in
                    completion(result)
                }
                return
            }

            if error == nil {
                result = .success(temporaryURL)
            } else {
                temporaryFileManager.removeFileIfExists(at: temporaryURL)
                result = .failure(.requestFailed)
            }

            Task { @MainActor in
                completion(result)
            }
        }
    }

    /// 将 Photos 视频资源流式写入临时文件。
    private func stream(
        _ resource: PHAssetResource,
        to temporaryURL: URL,
        resourceManager: PHAssetResourceManager,
        options: PHAssetResourceRequestOptions,
        completion: @escaping @MainActor (Result<URL, ChatPhotoLibraryMediaPreparationError>) -> Void
    ) {
        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forWritingTo: temporaryURL)
        } catch {
            Task { @MainActor in
                completion(.failure(.unableToOpenFile))
            }
            return
        }

        resourceManager.requestData(
            for: resource,
            options: options,
            dataReceivedHandler: Self.makeDataReceivedHandler(fileHandle: fileHandle),
            completionHandler: Self.makeCompletionHandler(
                fileHandle: fileHandle,
                temporaryFileManager: temporaryFileManager,
                temporaryURL: temporaryURL,
                completion: completion
            )
        )
    }
}
