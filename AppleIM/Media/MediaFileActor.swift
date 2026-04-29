//
//  MediaFileActor.swift
//  AppleIM
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum MediaFileError: Error, Equatable, Sendable {
    case invalidImageData
    case imageCompressionFailed
    case thumbnailGenerationFailed
}

nonisolated struct StoredMediaImageFile: Equatable, Sendable {
    let content: StoredImageContent
}

nonisolated struct MediaImageProcessingOptions: Equatable, Sendable {
    let originalMaxPixelSize: Int
    let originalCompressionQuality: Double
    let thumbnailMaxPixelSize: Int
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

protocol MediaFileStoring: Sendable {
    func saveImage(data: Data, preferredFileExtension: String?) async throws -> StoredMediaImageFile
}

actor AccountMediaFileStore: MediaFileStoring {
    private let accountID: UserID
    private let storageService: any AccountStorageService
    private let processingOptions: MediaImageProcessingOptions

    init(
        accountID: UserID,
        storageService: any AccountStorageService,
        processingOptions: MediaImageProcessingOptions = MediaImageProcessingOptions()
    ) {
        self.accountID = accountID
        self.storageService = storageService
        self.processingOptions = processingOptions
    }

    func saveImage(data: Data, preferredFileExtension: String?) async throws -> StoredMediaImageFile {
        let paths = try await storageService.prepareStorage(for: accountID)
        let fileStore = await MediaFileActor(paths: paths, processingOptions: processingOptions)
        return try await fileStore.saveImage(data: data, preferredFileExtension: preferredFileExtension)
    }
}

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
