//
//  EmojiStoreModels.swift
//  AppleIM
//

import Foundation

/// 表情类型。
nonisolated enum EmojiType: Int, Codable, Equatable, Sendable {
    case system = 1
    case customImage = 2
    case gif = 3
    case package = 4
    case animatedSticker = 5
}

/// 表情包下载状态。
nonisolated enum EmojiPackageStatus: Int, Codable, Equatable, Sendable {
    case notDownloaded = 0
    case downloading = 1
    case downloaded = 2
}

/// 表情包记录。
nonisolated struct EmojiPackageRecord: Equatable, Hashable, Sendable {
    let packageID: String
    let userID: UserID
    let title: String
    let author: String?
    let coverURL: String?
    let localCoverPath: String?
    let version: Int
    let status: EmojiPackageStatus
    let sortOrder: Int
    let createdAt: Int64
    let updatedAt: Int64
}

/// 表情资产记录。
nonisolated struct EmojiAssetRecord: Equatable, Hashable, Sendable {
    let emojiID: String
    let userID: UserID
    let packageID: String?
    let emojiType: EmojiType
    let name: String?
    let md5: String?
    let localPath: String?
    let thumbPath: String?
    let cdnURL: String?
    let width: Int?
    let height: Int?
    let sizeBytes: Int64?
    let useCount: Int
    let lastUsedAt: Int64?
    let isFavorite: Bool
    let isDeleted: Bool
    let extraJSON: String?
    let createdAt: Int64
    let updatedAt: Int64

    var storedContent: StoredEmojiContent {
        StoredEmojiContent(
            emojiID: emojiID,
            packageID: packageID,
            emojiType: emojiType,
            name: name,
            localPath: localPath,
            thumbPath: thumbPath,
            cdnURL: cdnURL,
            width: width,
            height: height,
            sizeBytes: sizeBytes
        )
    }
}

/// 消息中的表情内容快照。
nonisolated struct StoredEmojiContent: Equatable, Hashable, Sendable {
    let emojiID: String
    let packageID: String?
    let emojiType: EmojiType
    let name: String?
    let localPath: String?
    let thumbPath: String?
    let cdnURL: String?
    let width: Int?
    let height: Int?
    let sizeBytes: Int64?
}

/// 发出的表情消息输入。
nonisolated struct OutgoingEmojiMessageInput: Equatable, Sendable {
    let userID: UserID
    let conversationID: ConversationID
    let senderID: UserID
    let emoji: StoredEmojiContent
    let localTime: Int64
    let messageID: MessageID?
    let clientMessageID: String?
    let sortSequence: Int64?

    init(
        userID: UserID,
        conversationID: ConversationID,
        senderID: UserID,
        emoji: StoredEmojiContent,
        localTime: Int64,
        messageID: MessageID? = nil,
        clientMessageID: String? = nil,
        sortSequence: Int64? = nil
    ) {
        self.userID = userID
        self.conversationID = conversationID
        self.senderID = senderID
        self.emoji = emoji
        self.localTime = localTime
        self.messageID = messageID
        self.clientMessageID = clientMessageID
        self.sortSequence = sortSequence
    }
}

/// 表情面板状态。
nonisolated struct ChatEmojiPanelState: Equatable, Sendable {
    var packages: [EmojiPackageRecord]
    var recentEmojis: [EmojiAssetRecord]
    var favoriteEmojis: [EmojiAssetRecord]
    var packageEmojisByPackageID: [String: [EmojiAssetRecord]]
    var selectedPackageID: String?
    var isLoading: Bool
    var errorMessage: String?

    static let empty = ChatEmojiPanelState()

    init(
        packages: [EmojiPackageRecord] = [],
        recentEmojis: [EmojiAssetRecord] = [],
        favoriteEmojis: [EmojiAssetRecord] = [],
        packageEmojisByPackageID: [String: [EmojiAssetRecord]] = [:],
        selectedPackageID: String? = nil,
        isLoading: Bool = false,
        errorMessage: String? = nil
    ) {
        self.packages = packages
        self.recentEmojis = recentEmojis
        self.favoriteEmojis = favoriteEmojis
        self.packageEmojisByPackageID = packageEmojisByPackageID
        self.selectedPackageID = selectedPackageID ?? packages.first?.packageID
        self.isLoading = isLoading
        self.errorMessage = errorMessage
    }
}

/// 表情仓储协议。
protocol EmojiRepository: Sendable {
    func upsertEmojiPackage(_ package: EmojiPackageRecord) async throws
    func upsertEmojiAsset(_ emoji: EmojiAssetRecord) async throws
    func listEmojiPackages(for userID: UserID) async throws -> [EmojiPackageRecord]
    func listPackageEmojis(for userID: UserID, packageID: String) async throws -> [EmojiAssetRecord]
    func listFavoriteEmojis(for userID: UserID) async throws -> [EmojiAssetRecord]
    func listRecentEmojis(for userID: UserID, limit: Int) async throws -> [EmojiAssetRecord]
    func emoji(emojiID: String, userID: UserID) async throws -> EmojiAssetRecord?
    func setEmojiFavorite(emojiID: String, userID: UserID, isFavorite: Bool, updatedAt: Int64) async throws
    func recordEmojiUsed(emojiID: String, userID: UserID, usedAt: Int64) async throws
}
