//
//  MediaFileActor.swift
//  AppleIM
//
//  媒体文件 Actor
//  负责图片的压缩、缩略图生成、文件落盘等操作

import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 媒体文件错误
nonisolated enum MediaFileError: Error, Equatable, Sendable {
    /// 无效的图片数据
    case invalidImageData
    /// 图片压缩失败
    case imageCompressionFailed
    /// 缩略图生成失败
    case thumbnailGenerationFailed
    /// 无效的语音文件
    case invalidVoiceFile
    /// 无效的视频文件
    case invalidVideoFile
    /// 无效的普通文件
    case invalidFile
    /// 视频元数据读取失败
    case videoMetadataFailed
}

/// 存储的媒体图片文件
nonisolated struct StoredMediaImageFile: Equatable, Sendable {
    let content: StoredImageContent
}

/// 存储的媒体语音文件
nonisolated struct StoredMediaVoiceFile: Equatable, Sendable {
    let content: StoredVoiceContent
}

/// 存储的媒体视频文件
nonisolated struct StoredMediaVideoFile: Equatable, Sendable {
    let content: StoredVideoContent
}

/// 存储的普通文件
nonisolated struct StoredMediaDocumentFile: Equatable, Sendable {
    let content: StoredFileContent
}

nonisolated private struct StoredVideoMetadata: Equatable, Sendable {
    let durationMilliseconds: Int
    let width: Int
    let height: Int
}

/// 媒体图片处理选项
nonisolated struct MediaImageProcessingOptions: Equatable, Sendable {
    /// 原图最大像素尺寸
    let originalMaxPixelSize: Int
    /// 原图压缩质量（0.0-1.0）
    let originalCompressionQuality: Double
    /// 缩略图最大像素尺寸
    let thumbnailMaxPixelSize: Int
    /// 缩略图压缩质量（0.0-1.0）
    let thumbnailCompressionQuality: Double

    init(
        originalMaxPixelSize: Int = 2_048,
        originalCompressionQuality: Double = 0.82,
        thumbnailMaxPixelSize: Int = 360,
        thumbnailCompressionQuality: Double = 0.72
    ) {
        self.originalMaxPixelSize = originalMaxPixelSize
        self.originalCompressionQuality = originalCompressionQuality
        self.thumbnailMaxPixelSize = thumbnailMaxPixelSize
        self.thumbnailCompressionQuality = thumbnailCompressionQuality
    }
}

nonisolated private struct ProcessedMediaImage: Sendable {
    let originalData: Data
    let thumbnailData: Data
    let width: Int
    let height: Int
    let format: String
}

/// 媒体文件存储协议
protocol MediaFileStoring: Sendable {
    /// 保存图片
    ///
    /// - Parameters:
    ///   - data: 图片数据
    ///   - preferredFileExtension: 首选文件扩展名
    /// - Returns: 存储的图片文件信息
    func saveImage(data: Data, preferredFileExtension: String?) async throws -> StoredMediaImageFile
    /// 保存语音
    ///
    /// - Parameters:
    ///   - recordingURL: 临时录音文件 URL
    ///   - durationMilliseconds: 录音时长（毫秒）
    ///   - preferredFileExtension: 首选文件扩展名
    /// - Returns: 存储的语音文件信息
    func saveVoice(recordingURL: URL, durationMilliseconds: Int, preferredFileExtension: String?) async throws -> StoredMediaVoiceFile
    /// 保存视频文件并生成封面图
    ///
    /// - Parameters:
    ///   - fileURL: 视频文件 URL
    ///   - preferredFileExtension: 首选文件扩展名
    /// - Returns: 存储的视频文件信息
    /// - Throws: 视频文件无效或处理失败
    func saveVideo(fileURL: URL, preferredFileExtension: String?) async throws -> StoredMediaVideoFile
    /// 保存普通文件
    ///
    /// - Parameter fileURL: 文件 URL
    /// - Returns: 存储的文件信息
    /// - Throws: 文件无效或保存失败
    func saveFile(fileURL: URL) async throws -> StoredMediaDocumentFile
}

/// 账号媒体文件存储
///
/// 为指定账号提供媒体文件存储服务
actor AccountMediaFileStore: MediaFileStoring {
    private let accountID: UserID
    private let storageService: any AccountStorageService
    private let processingOptions: MediaImageProcessingOptions

    /// 初始化
    ///
    /// - Parameters:
    ///   - accountID: 账号 ID
    ///   - storageService: 存储服务
    ///   - processingOptions: 图片处理选项
    init(
        accountID: UserID,
        storageService: any AccountStorageService,
        processingOptions: MediaImageProcessingOptions = MediaImageProcessingOptions()
    ) {
        self.accountID = accountID
        self.storageService = storageService
        self.processingOptions = processingOptions
    }

    /// 保存图片
    ///
    /// 准备存储路径后委托给 MediaFileActor 处理
    ///
    /// - Parameters:
    ///   - data: 图片数据
    ///   - preferredFileExtension: 首选文件扩展名
    /// - Returns: 存储的图片文件信息
    /// - Throws: 存储准备失败或图片处理失败
    func saveImage(data: Data, preferredFileExtension: String?) async throws -> StoredMediaImageFile {
        let paths = try await storageService.prepareStorage(for: accountID)
        let fileStore = await MediaFileActor(paths: paths, processingOptions: processingOptions)
        return try await fileStore.saveImage(data: data, preferredFileExtension: preferredFileExtension)
    }

    /// 保存语音
    ///
    /// 准备存储路径后委托给 MediaFileActor 处理
    ///
    /// - Parameters:
    ///   - recordingURL: 临时录音文件 URL
    ///   - durationMilliseconds: 录音时长（毫秒）
    ///   - preferredFileExtension: 首选文件扩展名
    /// - Returns: 存储的语音文件信息
    /// - Throws: 存储准备失败或语音文件无效
    func saveVoice(recordingURL: URL, durationMilliseconds: Int, preferredFileExtension: String?) async throws -> StoredMediaVoiceFile {
        let paths = try await storageService.prepareStorage(for: accountID)
        let fileStore = await MediaFileActor(paths: paths, processingOptions: processingOptions)
        return try await fileStore.saveVoice(
            recordingURL: recordingURL,
            durationMilliseconds: durationMilliseconds,
            preferredFileExtension: preferredFileExtension
        )
    }

    /// 保存视频文件并生成封面图
    ///
    /// 准备存储路径后委托给 MediaFileActor 处理
    ///
    /// - Parameters:
    ///   - fileURL: 视频文件 URL
    ///   - preferredFileExtension: 首选文件扩展名
    /// - Returns: 存储的视频文件信息
    /// - Throws: 存储准备失败或视频处理失败
    func saveVideo(fileURL: URL, preferredFileExtension: String?) async throws -> StoredMediaVideoFile {
        let paths = try await storageService.prepareStorage(for: accountID)
        let fileStore = await MediaFileActor(paths: paths, processingOptions: processingOptions)
        return try await fileStore.saveVideo(fileURL: fileURL, preferredFileExtension: preferredFileExtension)
    }

    /// 保存普通文件
    ///
    /// 准备存储路径后委托给 MediaFileActor 处理
    ///
    /// - Parameter fileURL: 文件 URL
    /// - Returns: 存储的文件信息
    /// - Throws: 存储准备失败或文件无效
    func saveFile(fileURL: URL) async throws -> StoredMediaDocumentFile {
        let paths = try await storageService.prepareStorage(for: accountID)
        let fileStore = await MediaFileActor(paths: paths, processingOptions: processingOptions)
        return try await fileStore.saveFile(fileURL: fileURL)
    }
}

/// 媒体文件 Actor
///
/// 负责图片的压缩、缩略图生成和文件落盘
/// 使用 actor 隔离确保文件操作的线程安全
actor MediaFileActor: MediaFileStoring {
    private let paths: AccountStoragePaths
    private let processingOptions: MediaImageProcessingOptions

    init(
        paths: AccountStoragePaths,
        processingOptions: MediaImageProcessingOptions = MediaImageProcessingOptions()
    ) {
        self.paths = paths
        self.processingOptions = processingOptions
    }

    func saveImage(data: Data, preferredFileExtension: String?) async throws -> StoredMediaImageFile {
        let processedImage = try await Self.processImage(
            data: data,
            preferredFileExtension: preferredFileExtension,
            options: processingOptions
        )
        let mediaID = UUID().uuidString
        let imageDirectory = paths.mediaDirectory.appendingPathComponent("image", isDirectory: true)
        let originalDirectory = imageDirectory.appendingPathComponent("original", isDirectory: true)
        let thumbnailDirectory = imageDirectory.appendingPathComponent("thumb", isDirectory: true)

        try FileManager.default.createDirectory(at: originalDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)

        let originalURL = originalDirectory.appendingPathComponent(mediaID).appendingPathExtension(processedImage.format)
        let thumbnailURL = thumbnailDirectory.appendingPathComponent(mediaID).appendingPathExtension("jpg")

        try processedImage.originalData.write(to: originalURL, options: [.atomic])
        try processedImage.thumbnailData.write(to: thumbnailURL, options: [.atomic])

        return StoredMediaImageFile(
            content: StoredImageContent(
                mediaID: mediaID,
                localPath: originalURL.path,
                thumbnailPath: thumbnailURL.path,
                width: processedImage.width,
                height: processedImage.height,
                sizeBytes: Int64(processedImage.originalData.count),
                format: processedImage.format
            )
        )
    }

    func saveVoice(recordingURL: URL, durationMilliseconds: Int, preferredFileExtension: String?) async throws -> StoredMediaVoiceFile {
        guard FileManager.default.fileExists(atPath: recordingURL.path), durationMilliseconds > 0 else {
            throw MediaFileError.invalidVoiceFile
        }

        let mediaID = UUID().uuidString
        let format = Self.normalizedVoiceFileExtension(preferredFileExtension)
        let voiceDirectory = paths.mediaDirectory.appendingPathComponent("voice", isDirectory: true)
        try FileManager.default.createDirectory(at: voiceDirectory, withIntermediateDirectories: true)

        let destinationURL = voiceDirectory.appendingPathComponent(mediaID).appendingPathExtension(format)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: recordingURL, to: destinationURL)

        let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
        let sizeBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0

        return StoredMediaVoiceFile(
            content: StoredVoiceContent(
                mediaID: mediaID,
                localPath: destinationURL.path,
                durationMilliseconds: durationMilliseconds,
                sizeBytes: sizeBytes,
                format: format
            )
        )
    }

    func saveVideo(fileURL: URL, preferredFileExtension: String?) async throws -> StoredMediaVideoFile {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MediaFileError.invalidVideoFile
        }

        let mediaID = UUID().uuidString
        let format = Self.normalizedGenericFileExtension(preferredFileExtension ?? fileURL.pathExtension, fallback: "mov") ?? "mov"
        let videoDirectory = paths.mediaDirectory.appendingPathComponent("video", isDirectory: true)
        let thumbnailDirectory = videoDirectory.appendingPathComponent("thumb", isDirectory: true)
        try FileManager.default.createDirectory(at: videoDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)

        let destinationURL = videoDirectory.appendingPathComponent(mediaID).appendingPathExtension(format)
        let thumbnailURL = thumbnailDirectory.appendingPathComponent(mediaID).appendingPathExtension("jpg")
        try Self.copySecurityScopedItem(from: fileURL, to: destinationURL)

        let metadata = try await Self.videoMetadata(for: destinationURL, thumbnailURL: thumbnailURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
        let sizeBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0

        return StoredMediaVideoFile(
            content: StoredVideoContent(
                mediaID: mediaID,
                localPath: destinationURL.path,
                thumbnailPath: thumbnailURL.path,
                durationMilliseconds: metadata.durationMilliseconds,
                width: metadata.width,
                height: metadata.height,
                sizeBytes: sizeBytes
            )
        )
    }

    func saveFile(fileURL: URL) async throws -> StoredMediaDocumentFile {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MediaFileError.invalidFile
        }

        let mediaID = UUID().uuidString
        let sourceFileName = Self.normalizedFileName(fileURL.lastPathComponent, fallback: "file")
        let fileExtension = Self.normalizedGenericFileExtension(fileURL.pathExtension, fallback: nil)
        let fileDirectory = paths.mediaDirectory.appendingPathComponent("file", isDirectory: true)
        try FileManager.default.createDirectory(at: fileDirectory, withIntermediateDirectories: true)

        let destinationURL = fileDirectory.appendingPathComponent(mediaID)
            .appendingPathExtension(fileExtension ?? "dat")
        try Self.copySecurityScopedItem(from: fileURL, to: destinationURL)

        let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
        let sizeBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0

        return StoredMediaDocumentFile(
            content: StoredFileContent(
                mediaID: mediaID,
                localPath: destinationURL.path,
                fileName: sourceFileName,
                fileExtension: fileExtension,
                sizeBytes: sizeBytes
            )
        )
    }

    nonisolated private static func processImage(
        data: Data,
        preferredFileExtension: String?,
        options: MediaImageProcessingOptions
    ) async throws -> ProcessedMediaImage {
        try await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                throw MediaFileError.invalidImageData
            }

            let originalFormat = normalizedFileExtension(preferredFileExtension, source: source)
            let originalData = try makeOriginalData(
                from: source,
                originalData: data,
                format: originalFormat,
                maxPixelSize: options.originalMaxPixelSize,
                compressionQuality: options.originalCompressionQuality
            )
            let originalSource = CGImageSourceCreateWithData(originalData as CFData, nil) ?? source
            let thumbnailData = try makeThumbnailData(
                from: originalSource,
                maxPixelSize: options.thumbnailMaxPixelSize,
                compressionQuality: options.thumbnailCompressionQuality
            )
            let dimensions = dimensions(from: originalSource)

            return ProcessedMediaImage(
                originalData: originalData,
                thumbnailData: thumbnailData,
                width: dimensions.width,
                height: dimensions.height,
                format: originalFormat
            )
        }.value
    }

    nonisolated private static func normalizedFileExtension(_ preferredFileExtension: String?, source: CGImageSource) -> String {
        if let preferredFileExtension {
            let sanitized = preferredFileExtension
                .trimmingCharacters(in: CharacterSet(charactersIn: ".").union(.whitespacesAndNewlines))
                .lowercased()

            if !sanitized.isEmpty {
                return sanitized == "jpeg" ? "jpg" : sanitized
            }
        }

        guard
            let typeIdentifier = CGImageSourceGetType(source) as String?,
            let type = UTType(typeIdentifier),
            let fileExtension = type.preferredFilenameExtension
        else {
            return "jpg"
        }

        return fileExtension == "jpeg" ? "jpg" : fileExtension
    }

    nonisolated private static func normalizedVoiceFileExtension(_ preferredFileExtension: String?) -> String {
        let sanitized = preferredFileExtension?
            .trimmingCharacters(in: CharacterSet(charactersIn: ".").union(.whitespacesAndNewlines))
            .lowercased()

        guard let sanitized, !sanitized.isEmpty else {
            return "m4a"
        }

        return sanitized == "aac" ? "m4a" : sanitized
    }

    nonisolated private static func normalizedGenericFileExtension(_ preferredFileExtension: String?, fallback: String?) -> String? {
        let sanitized = preferredFileExtension?
            .trimmingCharacters(in: CharacterSet(charactersIn: ".").union(.whitespacesAndNewlines))
            .lowercased()

        if let sanitized, !sanitized.isEmpty {
            return sanitized == "jpeg" ? "jpg" : sanitized
        }

        return fallback
    }

    nonisolated private static func normalizedFileName(_ fileName: String, fallback: String) -> String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    nonisolated private static func copySecurityScopedItem(from sourceURL: URL, to destinationURL: URL) throws {
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    nonisolated private static func videoMetadata(for videoURL: URL, thumbnailURL: URL) async throws -> StoredVideoMetadata {
        try await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: videoURL)
            let durationSeconds = CMTimeGetSeconds(asset.duration)
            let durationMilliseconds = durationSeconds.isFinite ? Int(max(0, durationSeconds * 1_000)) : 0

            let track = asset.tracks(withMediaType: .video).first
            let naturalSize = track?.naturalSize.applying(track?.preferredTransform ?? .identity) ?? .zero
            let width = Int(abs(naturalSize.width).rounded())
            let height = Int(abs(naturalSize.height).rounded())

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)

            let image = try generator.copyCGImage(at: .zero, actualTime: nil)
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw MediaFileError.thumbnailGenerationFailed
            }

            CGImageDestinationAddImage(destination, image, [
                kCGImageDestinationLossyCompressionQuality: 0.72
            ] as CFDictionary)

            guard CGImageDestinationFinalize(destination) else {
                throw MediaFileError.thumbnailGenerationFailed
            }

            try (data as Data).write(to: thumbnailURL, options: [.atomic])

            return StoredVideoMetadata(
                durationMilliseconds: durationMilliseconds,
                width: width,
                height: height
            )
        }.value
    }

    nonisolated private static func dimensions(from source: CGImageSource) -> (width: Int, height: Int) {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return (0, 0)
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        return (width, height)
    }

    nonisolated private static func makeOriginalData(
        from source: CGImageSource,
        originalData: Data,
        format: String,
        maxPixelSize: Int,
        compressionQuality: Double
    ) throws -> Data {
        let dimensions = dimensions(from: source)
        let shouldDownsample = max(dimensions.width, dimensions.height) > maxPixelSize
        let isJPEG = format == "jpg" || format == "jpeg"

        guard shouldDownsample || isJPEG else {
            return originalData
        }

        guard let image = makeImage(from: source, maxPixelSize: maxPixelSize) else {
            throw MediaFileError.imageCompressionFailed
        }

        let data = NSMutableData()
        let typeIdentifier = isJPEG ? UTType.jpeg.identifier : (UTType(filenameExtension: format)?.identifier ?? UTType.png.identifier)
        guard let destination = CGImageDestinationCreateWithData(data, typeIdentifier as CFString, 1, nil) else {
            throw MediaFileError.imageCompressionFailed
        }

        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw MediaFileError.imageCompressionFailed
        }

        return data as Data
    }

    nonisolated private static func makeThumbnailData(
        from source: CGImageSource,
        maxPixelSize: Int,
        compressionQuality: Double
    ) throws -> Data {
        guard let thumbnail = makeImage(from: source, maxPixelSize: maxPixelSize) else {
            throw MediaFileError.thumbnailGenerationFailed
        }

        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else {
            throw MediaFileError.thumbnailGenerationFailed
        }

        CGImageDestinationAddImage(destination, thumbnail, [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw MediaFileError.thumbnailGenerationFailed
        }

        return data as Data
    }

    nonisolated private static func makeImage(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
