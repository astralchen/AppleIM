import Testing
import AVFoundation
import Combine
import Foundation
import GRDB
import UIKit

@testable import AppleIM

extension AppleIMTests {
    @Test func conversationDAOListsPinnedThenNewestConversations() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "ordered_user")
        let dao = ConversationDAO(database: databaseActor, paths: paths)

        try await dao.upsert(makeConversationRecord(id: "normal_old", userID: "ordered_user", title: "Old", sortTimestamp: 10))
        try await dao.upsert(makeConversationRecord(id: "normal_new", userID: "ordered_user", title: "New", sortTimestamp: 30))
        try await dao.upsert(makeConversationRecord(id: "pinned_old", userID: "ordered_user", title: "Pinned", isPinned: true, sortTimestamp: 20))

        let records = try await dao.listConversations(for: "ordered_user")

        #expect(records.map(\.id.rawValue) == ["pinned_old", "normal_new", "normal_old"])
    }

    @Test func localChatRepositoryUnreadConversationCountSumsVisibleConversations() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "unread_total_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(id: "unread_total_a", userID: "unread_total_user", unreadCount: 2)
        )
        try await repository.upsertConversation(
            makeConversationRecord(id: "unread_total_b", userID: "unread_total_user", isMuted: true, unreadCount: 3)
        )
        try await repository.upsertConversation(
            ConversationRecord(
                id: "unread_total_hidden",
                userID: "unread_total_user",
                type: .single,
                targetID: "hidden_peer",
                title: "Hidden",
                avatarURL: nil,
                lastMessageID: nil,
                lastMessageTime: nil,
                lastMessageDigest: "Hidden",
                unreadCount: 8,
                draftText: nil,
                isPinned: false,
                isMuted: false,
                isHidden: true,
                sortTimestamp: 1,
                updatedAt: 1,
                createdAt: 1
            )
        )

        let unreadCount = try await repository.unreadConversationCount(for: "unread_total_user")

        #expect(unreadCount == 5)
    }

    @Test func localChatRepositoryUnreadConversationCountReturnsZeroWithoutUnreadRows() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "unread_zero_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(id: "unread_zero_conversation", userID: "unread_zero_user", unreadCount: 0)
        )

        let unreadCount = try await repository.unreadConversationCount(for: "unread_zero_user")

        #expect(unreadCount == 0)
    }

    @Test func localChatRepositoryObservesConversationListChanges() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "observe_conversation_user")
        let values = CapturingPublisherValues<[Conversation]>()
        let cancellable = try await repository
            .observeConversations(for: "observe_conversation_user", limit: 10)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { conversations in
                    Task {
                        await values.append(conversations)
                    }
                }
            )
        defer {
            cancellable.cancel()
        }

        try await waitForCondition {
            await values.values().contains(where: \.isEmpty)
        }

        try await repository.upsertConversation(
            makeConversationRecord(
                id: "observed_conversation",
                userID: "observe_conversation_user",
                title: "Observed",
                sortTimestamp: 100
            )
        )

        try await waitForCondition {
            await values.values().contains { conversations in
                conversations.first?.id == "observed_conversation"
            }
        }
    }

    @Test func localChatRepositoryObservesUnreadBadgeSettingChanges() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "observe_badge_user")
        let values = CapturingPublisherValues<Int>()
        let cancellable = try await repository
            .observeUnreadBadgeCount(for: "observe_badge_user")
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { count in
                    Task {
                        await values.append(count)
                    }
                }
            )
        defer {
            cancellable.cancel()
        }

        try await waitForCondition {
            await values.values().contains(0)
        }

        try await repository.upsertConversation(
            makeConversationRecord(
                id: "observed_badge_muted",
                userID: "observe_badge_user",
                isMuted: true,
                unreadCount: 4,
                sortTimestamp: 20
            )
        )
        try await waitForCondition {
            await values.values().contains(4)
        }

        try await repository.updateBadgeIncludeMuted(userID: "observe_badge_user", includeMuted: false)
        try await waitForCondition {
            await values.values().last == 0
        }
    }

    @Test func localChatRepositoryObservesLatestMessages() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "observe_message_user")
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "observe_message_conversation",
                userID: "observe_message_user",
                title: "Observed Message",
                sortTimestamp: 1
            )
        )

        let values = CapturingPublisherValues<[StoredMessage]>()
        let cancellable = try await repository
            .observeLatestMessages(conversationID: "observe_message_conversation", limit: 10)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { messages in
                    Task {
                        await values.append(messages)
                    }
                }
            )
        defer {
            cancellable.cancel()
        }

        try await waitForCondition {
            await values.values().contains(where: \.isEmpty)
        }

        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "observe_message_user",
                conversationID: "observe_message_conversation",
                senderID: "observe_message_user",
                text: "Observed latest message",
                localTime: 300,
                messageID: "observed_message",
                clientMessageID: "observed_client",
                sortSequence: 300
            )
        )

        try await waitForCondition {
            let snapshots = await values.values()
            return try snapshots.contains { messages in
                try requireTextContent(messages.first) == "Observed latest message"
            }
        }
    }

    @Test func conversationDAOPagesVisibleConversationsAfterCursorWhenNewConversationMovesAhead() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "paged_user")
        let dao = ConversationDAO(database: databaseActor, paths: paths)

        try await dao.upsert(makeConversationRecord(id: "normal_older", userID: "paged_user", title: "Older", sortTimestamp: 10))
        try await dao.upsert(makeConversationRecord(id: "normal_old", userID: "paged_user", title: "Old", sortTimestamp: 10))
        try await dao.upsert(makeConversationRecord(id: "normal_new", userID: "paged_user", title: "New", sortTimestamp: 30))
        try await dao.upsert(makeConversationRecord(id: "pinned_old", userID: "paged_user", title: "Pinned", isPinned: true, sortTimestamp: 20))

        let firstPage = try await dao.listConversations(for: "paged_user", limit: 2, after: nil)
        try await dao.upsert(makeConversationRecord(id: "new_arrival", userID: "paged_user", title: "New Arrival", sortTimestamp: 100))
        let cursor = ConversationPageCursor(record: try #require(firstPage.last))
        let secondPage = try await dao.listConversations(for: "paged_user", limit: 2, after: cursor)

        #expect(firstPage.map(\.id.rawValue) == ["pinned_old", "normal_new"])
        #expect(secondPage.map(\.id.rawValue) == ["normal_older", "normal_old"])
    }

    @Test func conversationDAOPagesEqualSortTimestampByConversationIDDescending() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "tie_user")
        let dao = ConversationDAO(database: databaseActor, paths: paths)

        try await dao.upsert(makeConversationRecord(id: "same_a", userID: "tie_user", title: "A", sortTimestamp: 10))
        try await dao.upsert(makeConversationRecord(id: "same_c", userID: "tie_user", title: "C", sortTimestamp: 10))
        try await dao.upsert(makeConversationRecord(id: "same_b", userID: "tie_user", title: "B", sortTimestamp: 10))

        let firstPage = try await dao.listConversations(for: "tie_user", limit: 2, after: nil)
        let cursor = ConversationPageCursor(record: try #require(firstPage.last))
        let secondPage = try await dao.listConversations(for: "tie_user", limit: 2, after: cursor)

        #expect(firstPage.map(\.id.rawValue) == ["same_c", "same_b"])
        #expect(secondPage.map(\.id.rawValue) == ["same_a"])
    }

    @Test func conversationDAOFirstPageLoadsOneThousandConversationsUnderBudget() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "scale_user")
        let dao = ConversationDAO(database: databaseActor, paths: paths)

        for index in 0..<1_000 {
            let id = ConversationID(rawValue: String(format: "scale_%04d", index))
            try await dao.upsert(
                makeConversationRecord(
                    id: id,
                    userID: "scale_user",
                    title: "Scale \(index)",
                    isPinned: index == 0,
                    sortTimestamp: Int64(index)
                )
            )
        }

        let startedAt = Date()
        let firstPage = try await dao.listConversations(for: "scale_user", limit: 50, after: nil)
        let elapsed = Date().timeIntervalSince(startedAt)

        #expect(firstPage.count == 50)
        #expect(firstPage.first?.id == "scale_0000")
        #expect(firstPage.dropFirst().first?.id == "scale_0999")
        #expect(elapsed < 0.5)
    }

    @Test func localChatRepositoryInsertsOutgoingTextMessageInTransaction() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "message_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "message_conversation", userID: "message_user", title: "Message Target", sortTimestamp: 1)
        )

        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "message_user",
                conversationID: "message_conversation",
                senderID: "message_user",
                text: "Hello from the repository",
                localTime: 200,
                messageID: "message_1",
                clientMessageID: "client_1",
                sortSequence: 200
            )
        )
        let messages = try await repository.listMessages(conversationID: "message_conversation", limit: 20, beforeSortSeq: nil)
        let conversations = try await repository.listConversations(for: "message_user")

        #expect(message.state.sendStatus == .sending)
        #expect(messages.count == 1)
        #expect(try requireTextContent(messages.first) == "Hello from the repository")
        #expect(conversations.first?.lastMessageDigest == "Hello from the repository")
    }

    @Test func mediaFileActorStoresOriginalAndThumbnailInsideAccountDirectory() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (_, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "media_user")
        let mediaFileActor = await MediaFileActor(paths: paths)
        let storedFile = try await mediaFileActor.saveImage(data: samplePNGData(), preferredFileExtension: "png")

        #expect(storedFile.content.localPath.hasPrefix(paths.mediaDirectory.path))
        #expect(storedFile.content.thumbnailPath.hasPrefix(paths.mediaDirectory.path))
        #expect(FileManager.default.fileExists(atPath: storedFile.content.localPath))
        #expect(FileManager.default.fileExists(atPath: storedFile.content.thumbnailPath))
        #expect(storedFile.content.width == 1)
        #expect(storedFile.content.height == 1)
        #expect(storedFile.content.format == "png")
    }

    @Test func mediaFileActorDownsamplesOriginalAndThumbnailForLargeImages() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (_, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "large_media_user")
        let processingOptions = MediaImageProcessingOptions(
            originalMaxPixelSize: 256,
            originalCompressionQuality: 0.68,
            thumbnailMaxPixelSize: 64,
            thumbnailCompressionQuality: 0.62
        )
        let mediaFileActor = await MediaFileActor(paths: paths, processingOptions: processingOptions)
        let sourceData = makeJPEGData(width: 1_024, height: 768, quality: 0.98)
        let storedFile = try await mediaFileActor.saveImage(data: sourceData, preferredFileExtension: "jpg")

        let originalDimensions = imageDimensions(atPath: storedFile.content.localPath)
        let thumbnailDimensions = imageDimensions(atPath: storedFile.content.thumbnailPath)

        #expect(max(storedFile.content.width, storedFile.content.height) <= 256)
        #expect(max(originalDimensions.width, originalDimensions.height) <= 256)
        #expect(max(thumbnailDimensions.width, thumbnailDimensions.height) <= 64)
        #expect(storedFile.content.sizeBytes < Int64(sourceData.count))
        #expect(storedFile.content.format == "jpg")
    }

    @Test func mediaFileActorStoresVoiceInsideAccountDirectory() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (_, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "voice_media_user")
        let recordingURL = try makeVoiceRecordingFile(in: rootDirectory)
        let mediaFileActor = await MediaFileActor(paths: paths)
        let storedFile = try await mediaFileActor.saveVoice(
            recordingURL: recordingURL,
            durationMilliseconds: 1_500,
            preferredFileExtension: "m4a"
        )

        #expect(storedFile.content.localPath.hasPrefix(paths.mediaDirectory.appendingPathComponent("voice").path))
        #expect(FileManager.default.fileExists(atPath: storedFile.content.localPath))
        #expect(storedFile.content.durationMilliseconds == 1_500)
        #expect(storedFile.content.sizeBytes > 0)
        #expect(storedFile.content.format == "m4a")
    }

    @Test func mediaFileActorStoresVideoAndThumbnailInsideAccountDirectory() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (_, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: "video_media_user")
        let sourceVideoURL = try await makeSampleVideoFile(in: rootDirectory)
        let mediaFileActor = await MediaFileActor(paths: paths)
        let storedFile = try await mediaFileActor.saveVideo(fileURL: sourceVideoURL, preferredFileExtension: "mov")

        #expect(storedFile.content.localPath.hasPrefix(paths.mediaDirectory.appendingPathComponent("video").path))
        #expect(storedFile.content.thumbnailPath.hasPrefix(paths.mediaDirectory.appendingPathComponent("video/thumb").path))
        #expect(FileManager.default.fileExists(atPath: storedFile.content.localPath))
        #expect(FileManager.default.fileExists(atPath: storedFile.content.thumbnailPath))
        #expect(storedFile.content.durationMilliseconds >= 0)
        #expect(storedFile.content.width == 64)
        #expect(storedFile.content.height == 64)
        #expect(storedFile.content.sizeBytes > 0)
    }

    @Test func localChatRepositoryInsertsOutgoingImageMessageInTransaction() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "image_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "image_conversation", userID: "image_user", title: "Image Target", sortTimestamp: 1)
        )

        let image = StoredImageContent(
            mediaID: "media_image_1",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image/original/media_image_1.png").path,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image/thumb/media_image_1.jpg").path,
            width: 120,
            height: 80,
            sizeBytes: 512,
            format: "png"
        )
        let message = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "image_user",
                conversationID: "image_conversation",
                senderID: "image_user",
                image: image,
                localTime: 500,
                messageID: "image_message_1",
                clientMessageID: "image_client_1",
                sortSequence: 500
            )
        )
        let messages = try await repository.listMessages(conversationID: "image_conversation", limit: 20, beforeSortSeq: nil)
        let contentCount = try await databaseCount(
            "SELECT COUNT(*) FROM message_image WHERE content_id = ?;",
            arguments: ["image_image_message_1"],
            databaseContext: databaseContext
        )
        let conversations = try await repository.listConversations(for: "image_user")

        #expect(message.type == .image)
        #expect(message.state.sendStatus == .sending)
        #expect(try requireImageContent(message) == image)
        #expect(try requireImageContent(messages.first) == image)
        #expect(contentCount == 1)
        #expect(conversations.first?.lastMessageDigest == "[图片]")
    }

    @Test func localChatRepositoryInsertsOutgoingVoiceMessageInTransaction() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "voice_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "voice_conversation", userID: "voice_user", title: "Voice Target", sortTimestamp: 1)
        )

        let voice = StoredVoiceContent(
            mediaID: "media_voice_1",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("voice/media_voice_1.m4a").path,
            durationMilliseconds: 2_400,
            sizeBytes: 1_024,
            format: "m4a"
        )
        let message = try await repository.insertOutgoingVoiceMessage(
            OutgoingVoiceMessageInput(
                userID: "voice_user",
                conversationID: "voice_conversation",
                senderID: "voice_user",
                voice: voice,
                localTime: 510,
                messageID: "voice_message_1",
                clientMessageID: "voice_client_1",
                sortSequence: 510
            )
        )
        let messages = try await repository.listMessages(conversationID: "voice_conversation", limit: 20, beforeSortSeq: nil)
        let contentCount = try await databaseCount(
            "SELECT COUNT(*) FROM message_voice WHERE content_id = ?;",
            arguments: ["voice_voice_message_1"],
            databaseContext: databaseContext
        )
        let resourceCount = try await databaseCount(
            "SELECT COUNT(*) FROM media_resource WHERE owner_message_id = ?;",
            arguments: [message.id.rawValue],
            databaseContext: databaseContext
        )
        let conversations = try await repository.listConversations(for: "voice_user")

        #expect(message.type == .voice)
        #expect(message.state.sendStatus == .sending)
        #expect(try requireVoiceContent(message) == voice)
        #expect(try requireVoiceContent(messages.first) == voice)
        #expect(contentCount == 1)
        #expect(resourceCount == 1)
        #expect(conversations.first?.lastMessageDigest == "[语音]")
    }

    @Test func localChatRepositoryInsertsOutgoingVideoMessageInTransaction() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "video_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "video_conversation", userID: "video_user", title: "Video Target", sortTimestamp: 1)
        )

        let video = StoredVideoContent(
            mediaID: "media_video_1",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("video/media_video_1.mov").path,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("video/thumb/media_video_1.jpg").path,
            durationMilliseconds: 1_000,
            width: 64,
            height: 64,
            sizeBytes: 2_048
        )
        let message = try await repository.insertOutgoingVideoMessage(
            OutgoingVideoMessageInput(
                userID: "video_user",
                conversationID: "video_conversation",
                senderID: "video_user",
                video: video,
                localTime: 520,
                messageID: "video_message_1",
                clientMessageID: "video_client_1",
                sortSequence: 520
            )
        )
        let messages = try await repository.listMessages(conversationID: "video_conversation", limit: 20, beforeSortSeq: nil)
        let contentCount = try await databaseCount(
            "SELECT COUNT(*) FROM message_video WHERE content_id = ?;",
            arguments: ["video_video_message_1"],
            databaseContext: databaseContext
        )
        let resourceCount = try await databaseCount(
            "SELECT COUNT(*) FROM media_resource WHERE owner_message_id = ?;",
            arguments: [message.id.rawValue],
            databaseContext: databaseContext
        )
        let conversations = try await repository.listConversations(for: "video_user")

        #expect(message.type == .video)
        #expect(message.state.sendStatus == .sending)
        #expect(try requireVideoContent(message) == video)
        #expect(try requireVideoContent(messages.first) == video)
        #expect(contentCount == 1)
        #expect(resourceCount == 1)
        #expect(conversations.first?.lastMessageDigest == "[视频]")
    }

    @Test func localChatRepositoryInsertsOutgoingFileMessageInTransaction() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "file_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "file_conversation", userID: "file_user", title: "File Target", sortTimestamp: 1)
        )

        let file = StoredFileContent(
            mediaID: "media_file_1",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("file/report.pdf").path,
            fileName: "report.pdf",
            fileExtension: "pdf",
            sizeBytes: 4_096
        )
        let message = try await repository.insertOutgoingFileMessage(
            OutgoingFileMessageInput(
                userID: "file_user",
                conversationID: "file_conversation",
                senderID: "file_user",
                file: file,
                localTime: 530,
                messageID: "file_message_1",
                clientMessageID: "file_client_1",
                sortSequence: 530
            )
        )
        let messages = try await repository.listMessages(conversationID: "file_conversation", limit: 20, beforeSortSeq: nil)
        let contentCount = try await databaseCount(
            "SELECT COUNT(*) FROM message_file WHERE content_id = ?;",
            arguments: ["file_file_message_1"],
            databaseContext: databaseContext
        )
        let conversations = try await repository.listConversations(for: "file_user")

        #expect(message.type == .file)
        #expect(message.state.sendStatus == .sending)
        #expect(try requireFileContent(message) == file)
        #expect(try requireFileContent(messages.first) == file)
        #expect(contentCount == 1)
        #expect(conversations.first?.lastMessageDigest == "[文件] report.pdf")
    }

    @Test func localChatRepositoryResolvesImagePathsAfterStorageRootMoves() async throws {
        let oldRootDirectory = temporaryDirectory()
        let newRootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: oldRootDirectory)
            try? FileManager.default.removeItem(at: newRootDirectory)
        }

        let accountID = UserID(rawValue: "image_move_user")
        let (oldRepository, oldDatabaseContext) = try await makeRepository(
            rootDirectory: oldRootDirectory,
            accountID: accountID
        )
        try await oldRepository.upsertConversation(
            makeConversationRecord(id: "image_move_conversation", userID: accountID, title: "Image Move", sortTimestamp: 1)
        )

        let image = StoredImageContent(
            mediaID: "media_image_move",
            localPath: oldDatabaseContext.paths.mediaDirectory.appendingPathComponent("image/original/media_image_move.png").path,
            thumbnailPath: oldDatabaseContext.paths.mediaDirectory.appendingPathComponent("image/thumb/media_image_move.jpg").path,
            width: 120,
            height: 80,
            sizeBytes: 512,
            format: "png"
        )
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: image.localPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: image.thumbnailPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: URL(fileURLWithPath: image.localPath))
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: URL(fileURLWithPath: image.thumbnailPath))
        _ = try await oldRepository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: accountID,
                conversationID: "image_move_conversation",
                senderID: accountID,
                image: image,
                localTime: 521,
                messageID: "image_move_message",
                clientMessageID: "image_move_client",
                sortSequence: 521
            )
        )

        try await oldDatabaseContext.databaseActor.closeConnections(for: oldDatabaseContext.paths)
        try FileManager.default.createDirectory(at: newRootDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: oldDatabaseContext.paths.rootDirectory,
            to: newRootDirectory.appendingPathComponent(
                oldDatabaseContext.paths.rootDirectory.lastPathComponent,
                isDirectory: true
            )
        )
        try FileManager.default.removeItem(at: oldRootDirectory)

        let (newRepository, newDatabaseContext) = try await makeRepository(
            rootDirectory: newRootDirectory,
            accountID: accountID
        )
        let messages = try await newRepository.listMessages(
            conversationID: "image_move_conversation",
            limit: 20,
            beforeSortSeq: nil
        )
        let reloadedImage = try requireImageContent(messages.first)

        #expect(reloadedImage.localPath == newDatabaseContext.paths.mediaDirectory.appendingPathComponent("image/original/media_image_move.png").path)
        #expect(reloadedImage.thumbnailPath == newDatabaseContext.paths.mediaDirectory.appendingPathComponent("image/thumb/media_image_move.jpg").path)
    }

    @Test func localChatRepositoryResolvesVideoPathsAfterStorageRootMoves() async throws {
        let oldRootDirectory = temporaryDirectory()
        let newRootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: oldRootDirectory)
            try? FileManager.default.removeItem(at: newRootDirectory)
        }

        let accountID = UserID(rawValue: "video_move_user")
        let (oldRepository, oldDatabaseContext) = try await makeRepository(
            rootDirectory: oldRootDirectory,
            accountID: accountID
        )
        try await oldRepository.upsertConversation(
            makeConversationRecord(id: "video_move_conversation", userID: accountID, title: "Video Move", sortTimestamp: 1)
        )

        let video = StoredVideoContent(
            mediaID: "media_video_move",
            localPath: oldDatabaseContext.paths.mediaDirectory.appendingPathComponent("video/media_video_move.mov").path,
            thumbnailPath: oldDatabaseContext.paths.mediaDirectory.appendingPathComponent("video/thumb/media_video_move.jpg").path,
            durationMilliseconds: 1_000,
            width: 64,
            height: 64,
            sizeBytes: 2_048
        )
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: video.localPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: video.thumbnailPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("mov".utf8).write(to: URL(fileURLWithPath: video.localPath))
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: URL(fileURLWithPath: video.thumbnailPath))
        _ = try await oldRepository.insertOutgoingVideoMessage(
            OutgoingVideoMessageInput(
                userID: accountID,
                conversationID: "video_move_conversation",
                senderID: accountID,
                video: video,
                localTime: 522,
                messageID: "video_move_message",
                clientMessageID: "video_move_client",
                sortSequence: 522
            )
        )

        try await oldDatabaseContext.databaseActor.closeConnections(for: oldDatabaseContext.paths)
        try FileManager.default.createDirectory(at: newRootDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: oldDatabaseContext.paths.rootDirectory,
            to: newRootDirectory.appendingPathComponent(
                oldDatabaseContext.paths.rootDirectory.lastPathComponent,
                isDirectory: true
            )
        )
        try FileManager.default.removeItem(at: oldRootDirectory)

        let (newRepository, newDatabaseContext) = try await makeRepository(
            rootDirectory: newRootDirectory,
            accountID: accountID
        )
        let messages = try await newRepository.listMessages(
            conversationID: "video_move_conversation",
            limit: 20,
            beforeSortSeq: nil
        )
        let reloadedVideo = try requireVideoContent(messages.first)

        #expect(reloadedVideo.localPath == newDatabaseContext.paths.mediaDirectory.appendingPathComponent("video/media_video_move.mov").path)
        #expect(reloadedVideo.thumbnailPath == newDatabaseContext.paths.mediaDirectory.appendingPathComponent("video/thumb/media_video_move.jpg").path)
    }

    @Test func localChatRepositoryIndexesOutgoingImageMediaFiles() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "image_index_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "image_index_conversation", userID: "image_index_user", title: "Image Index", sortTimestamp: 1)
        )

        let image = StoredImageContent(
            mediaID: "media_image_index",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image/original/media_image_index.png").path,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image/thumb/media_image_index.jpg").path,
            width: 120,
            height: 80,
            sizeBytes: 512,
            md5: "image-index-md5",
            format: "png"
        )
        _ = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "image_index_user",
                conversationID: "image_index_conversation",
                senderID: "image_index_user",
                image: image,
                localTime: 530,
                messageID: "image_index_message",
                clientMessageID: "image_index_client",
                sortSequence: 530
            )
        )

        let originalIndex = try await repository.mediaIndexRecord(mediaID: "media_image_index", userID: "image_index_user")
        let thumbnailIndex = try await repository.mediaIndexRecord(mediaID: "media_image_index_thumb", userID: "image_index_user")

        #expect(originalIndex?.localPath == image.localPath)
        #expect(originalIndex?.fileName == "media_image_index.png")
        #expect(originalIndex?.fileExtension == "png")
        #expect(originalIndex?.sizeBytes == 512)
        #expect(originalIndex?.md5 == "image-index-md5")
        #expect(thumbnailIndex?.localPath == image.thumbnailPath)
        #expect(thumbnailIndex?.fileName == "media_image_index.jpg")
        #expect(thumbnailIndex?.fileExtension == "jpg")
    }

    @Test func localChatRepositoryIndexesOutgoingVoiceMediaFile() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "voice_index_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "voice_index_conversation", userID: "voice_index_user", title: "Voice Index", sortTimestamp: 1)
        )

        let voice = StoredVoiceContent(
            mediaID: "media_voice_index",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("voice/media_voice_index.m4a").path,
            durationMilliseconds: 2_400,
            sizeBytes: 1_024,
            format: "m4a"
        )
        _ = try await repository.insertOutgoingVoiceMessage(
            OutgoingVoiceMessageInput(
                userID: "voice_index_user",
                conversationID: "voice_index_conversation",
                senderID: "voice_index_user",
                voice: voice,
                localTime: 540,
                messageID: "voice_index_message",
                clientMessageID: "voice_index_client",
                sortSequence: 540
            )
        )

        let voiceIndex = try await repository.mediaIndexRecord(mediaID: "media_voice_index", userID: "voice_index_user")

        #expect(voiceIndex?.localPath == voice.localPath)
        #expect(voiceIndex?.fileName == "media_voice_index.m4a")
        #expect(voiceIndex?.fileExtension == "m4a")
        #expect(voiceIndex?.sizeBytes == 1_024)
    }

    @Test func localChatRepositoryEnqueuesDownloadJobForMissingMediaWithoutDuplication() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "missing_media_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "missing_media_conversation", userID: "missing_media_user", title: "Missing Media", sortTimestamp: 1)
        )

        let missingLocalPath = databaseContext.paths.mediaDirectory.appendingPathComponent("image/original/missing_media.png").path
        let image = StoredImageContent(
            mediaID: "missing_media",
            localPath: missingLocalPath,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image/thumb/missing_media.jpg").path,
            width: 120,
            height: 80,
            sizeBytes: 512,
            format: "png"
        )
        _ = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "missing_media_user",
                conversationID: "missing_media_conversation",
                senderID: "missing_media_user",
                image: image,
                localTime: 550,
                messageID: "missing_media_message",
                clientMessageID: "missing_media_client",
                sortSequence: 550
            )
        )
        _ = try await databaseContext.databaseActor.write(paths: databaseContext.paths) { db in
            try db.execute(
                sql: """
                UPDATE media_resource
                SET remote_url = ?, download_status = ?
                WHERE media_id = ?;
                """,
                arguments: [
                    "https://mock-cdn.chatbridge.local/image/missing_media",
                    MediaUploadStatus.success.rawValue,
                    "missing_media"
                ]
            )
        }

        let missingResources = try await repository.scanMissingMediaResources(userID: "missing_media_user")
        let firstJobs = try await repository.enqueueMediaDownloadJobsForMissingResources(userID: "missing_media_user")
        let secondJobs = try await repository.enqueueMediaDownloadJobsForMissingResources(userID: "missing_media_user")
        let pendingJobCount = try await databaseCount(
            "SELECT COUNT(*) FROM pending_job WHERE job_type = ?;",
            arguments: [PendingJobType.mediaDownload.rawValue],
            databaseContext: databaseContext
        )
        let downloadStatus = try await databaseInt(
            "SELECT download_status FROM media_resource WHERE media_id = ?;",
            arguments: ["missing_media"],
            databaseContext: databaseContext
        )

        #expect(missingResources.map(\.mediaID) == ["missing_media"])
        #expect(firstJobs.count == 1)
        #expect(firstJobs.first?.id == "media_download_missing_media")
        #expect(firstJobs.first?.type == .mediaDownload)
        #expect(firstJobs.first?.payloadJSON.contains(#""localPath":"\#(missingLocalPath)""#) == true)
        #expect(secondJobs.count == 1)
        #expect(pendingJobCount == 1)
        #expect(downloadStatus == MediaUploadStatus.pending.rawValue)
    }

    @Test func mediaIndexRebuildRestoresExistingImageAndVoiceFiles() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "repair_media_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "repair_media_conversation", userID: "repair_media_user", title: "Repair Media", sortTimestamp: 1)
        )
        let imageDirectory = databaseContext.paths.mediaDirectory.appendingPathComponent("image/original", isDirectory: true)
        let thumbnailDirectory = databaseContext.paths.mediaDirectory.appendingPathComponent("image/thumb", isDirectory: true)
        let voiceDirectory = databaseContext.paths.mediaDirectory.appendingPathComponent("voice", isDirectory: true)
        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: voiceDirectory, withIntermediateDirectories: true)
        let imageURL = imageDirectory.appendingPathComponent("repair_image.png")
        let thumbnailURL = thumbnailDirectory.appendingPathComponent("repair_image.jpg")
        let voiceURL = voiceDirectory.appendingPathComponent("repair_voice.m4a")
        try Data("image".utf8).write(to: imageURL, options: [.atomic])
        try Data("thumb".utf8).write(to: thumbnailURL, options: [.atomic])
        try Data("voice".utf8).write(to: voiceURL, options: [.atomic])

        _ = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "repair_media_user",
                conversationID: "repair_media_conversation",
                senderID: "repair_media_user",
                image: StoredImageContent(
                    mediaID: "repair_image",
                    localPath: imageURL.path,
                    thumbnailPath: thumbnailURL.path,
                    width: 120,
                    height: 80,
                    sizeBytes: 5,
                    md5: "repair-md5",
                    format: "png"
                ),
                localTime: 570,
                messageID: "repair_image_message",
                clientMessageID: "repair_image_client",
                sortSequence: 570
            )
        )
        _ = try await repository.insertOutgoingVoiceMessage(
            OutgoingVoiceMessageInput(
                userID: "repair_media_user",
                conversationID: "repair_media_conversation",
                senderID: "repair_media_user",
                voice: StoredVoiceContent(
                    mediaID: "repair_voice",
                    localPath: voiceURL.path,
                    durationMilliseconds: 2_000,
                    sizeBytes: 5,
                    format: "m4a"
                ),
                localTime: 571,
                messageID: "repair_voice_message",
                clientMessageID: "repair_voice_client",
                sortSequence: 571
            )
        )
        _ = try await databaseContext.databaseActor.write(in: .fileIndex, paths: databaseContext.paths) { db in
            try db.execute(sql: "DELETE FROM file_index WHERE user_id = ?;", arguments: ["repair_media_user"])
        }

        let result = try await repository.rebuildMediaIndex(userID: "repair_media_user")
        let imageIndex = try await repository.mediaIndexRecord(mediaID: "repair_image", userID: "repair_media_user")
        let thumbnailIndex = try await repository.mediaIndexRecord(mediaID: "repair_image_thumb", userID: "repair_media_user")
        let voiceIndex = try await repository.mediaIndexRecord(mediaID: "repair_voice", userID: "repair_media_user")

        #expect(result == MediaIndexRebuildResult(scannedResourceCount: 2, rebuiltIndexCount: 3, missingResourceCount: 0, createdDownloadJobCount: 0))
        #expect(imageIndex?.localPath == imageURL.path)
        #expect(imageIndex?.md5 == "repair-md5")
        #expect(thumbnailIndex?.localPath == thumbnailURL.path)
        #expect(voiceIndex?.localPath == voiceURL.path)
    }

    @Test func localChatRepositoryMarksVoiceMessagePlayed() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "voice_play_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "voice_play_conversation", userID: "voice_play_user", title: "Voice Play", sortTimestamp: 1)
        )

        let voice = StoredVoiceContent(
            mediaID: "media_voice_play",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("voice/media_voice_play.m4a").path,
            durationMilliseconds: 2_000,
            sizeBytes: 512,
            format: "m4a"
        )
        let message = try await repository.insertOutgoingVoiceMessage(
            OutgoingVoiceMessageInput(
                userID: "voice_play_user",
                conversationID: "voice_play_conversation",
                senderID: "friend_user",
                voice: voice,
                localTime: 520,
                messageID: "voice_play_message",
                clientMessageID: "voice_play_client",
                sortSequence: 520
            )
        )
        _ = try await databaseContext.databaseActor.write(paths: databaseContext.paths) { db in
            try db.execute(
                sql: "UPDATE message SET read_status = ? WHERE message_id = ?;",
                arguments: [MessageReadStatus.unread.rawValue, message.id.rawValue]
            )
        }

        let unreadMessage = try await repository.message(messageID: message.id)
        try await repository.markVoicePlayed(messageID: message.id)
        let playedMessage = try await repository.message(messageID: message.id)

        #expect(unreadMessage?.state.readStatus == .unread)
        #expect(playedMessage?.state.readStatus == .read)
    }

    @Test func localChatRepositoryRollsBackWhenMessageInsertFails() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "rollback_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "rollback_conversation", userID: "rollback_user", title: "Rollback", sortTimestamp: 1)
        )

        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "rollback_user",
                conversationID: "rollback_conversation",
                senderID: "rollback_user",
                text: "Original",
                localTime: 300,
                messageID: "rollback_original",
                clientMessageID: "same_client",
                sortSequence: 300
            )
        )

        var didThrow = false

        do {
            _ = try await repository.insertOutgoingTextMessage(
                OutgoingTextMessageInput(
                    userID: "rollback_user",
                    conversationID: "rollback_conversation",
                    senderID: "rollback_user",
                    text: "Duplicate",
                    localTime: 301,
                    messageID: "rollback_duplicate",
                    clientMessageID: "same_client",
                    sortSequence: 301
                )
            )
        } catch {
            didThrow = true
        }

        let leakedContentCount = try await databaseCount(
            "SELECT COUNT(*) FROM message_text WHERE content_id = ?;",
            arguments: ["text_rollback_duplicate"],
            databaseContext: databaseContext
        )
        let conversations = try await repository.listConversations(for: "rollback_user")

        #expect(didThrow)
        #expect(leakedContentCount == 0)
        #expect(conversations.first?.lastMessageDigest == "Original")
    }

    @Test func localChatRepositoryStoresGroupMembersAndAnnouncementPermissions() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "group_repo_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "group_repo_conversation", userID: "group_repo_user", type: .group, targetID: "group_repo")
        )
        try await repository.upsertGroupMembers(
            [
                GroupMember(conversationID: "group_repo_conversation", memberID: "group_repo_user", displayName: "Me", role: .owner, joinTime: 100),
                GroupMember(conversationID: "group_repo_conversation", memberID: "admin_user", displayName: "Admin", role: .admin, joinTime: 101),
                GroupMember(conversationID: "group_repo_conversation", memberID: "member_user", displayName: "Member", role: .member, joinTime: 102)
            ]
        )

        let members = try await repository.groupMembers(conversationID: "group_repo_conversation")
        try await repository.updateGroupAnnouncement(
            conversationID: "group_repo_conversation",
            userID: "admin_user",
            text: "本周联调重点：群聊 P1。"
        )
        let announcement = try await repository.groupAnnouncement(conversationID: "group_repo_conversation")

        #expect(members.map(\.memberID) == ["group_repo_user", "admin_user", "member_user"])
        #expect(try await repository.currentMemberRole(conversationID: "group_repo_conversation", userID: "admin_user") == .admin)
        #expect(announcement?.text == "本周联调重点：群聊 P1。")
        await #expect(throws: GroupChatError.permissionDenied) {
            try await repository.updateGroupAnnouncement(
                conversationID: "group_repo_conversation",
                userID: "member_user",
                text: "普通成员不能改公告"
            )
        }
    }

    @Test func messagePaginationQueriesUseVisibleSortIndex() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "chat_plan_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "chat_plan_conversation", userID: "chat_plan_user", title: "Query Plan", sortTimestamp: 100)
        )
        try await seedPerformanceMessages(
            databaseContext: databaseContext,
            conversationID: "chat_plan_conversation",
            userID: "chat_plan_user",
            count: 100
        )

        let initialMessages = try await repository.listMessages(
            conversationID: "chat_plan_conversation",
            limit: 51,
            beforeSortSeq: nil
        )
        let olderMessages = try await repository.listMessages(
            conversationID: "chat_plan_conversation",
            limit: 51,
            beforeSortSeq: 51
        )
        let indexNames = try await databaseContext.databaseActor.read(paths: databaseContext.paths) { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_message_conversation_visible_sort';"
            )
        }

        #expect(initialMessages.count == 51)
        #expect(olderMessages.allSatisfy { $0.timeline.sortSequence < 51 })
        #expect(indexNames == ["idx_message_conversation_visible_sort"])
    }

    @Test func localChatRepositoryMarksIncomingMessagesReadWhenConversationIsRead() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "message_read_user")
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "message_read_conversation",
                userID: "message_read_user",
                title: "Message Read",
                unreadCount: 1,
                sortTimestamp: 1
            )
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "message_read_user",
                conversationID: "message_read_conversation",
                senderID: "friend_user",
                text: "Unread before opening",
                localTime: 10,
                messageID: "message_read_text",
                clientMessageID: "message_read_client",
                sortSequence: 10
            )
        )
        _ = try await databaseContext.databaseActor.write(paths: databaseContext.paths) { db in
            try db.execute(
                sql: "UPDATE message SET direction = ?, read_status = ? WHERE message_id = ?;",
                arguments: [
                    MessageDirection.incoming.rawValue,
                    MessageReadStatus.unread.rawValue,
                    message.id.rawValue
                ]
            )
        }

        let unreadMessage = try await repository.message(messageID: message.id)
        try await repository.markConversationRead(conversationID: "message_read_conversation", userID: "message_read_user")

        let conversations = try await repository.listConversations(for: "message_read_user")
        let storedMessage = try await repository.message(messageID: message.id)
        #expect(unreadMessage?.state.readStatus == .unread)
        #expect(conversations.first?.unreadCount == 0)
        #expect(storedMessage?.state.readStatus == .read)
    }
}

private func databaseCount(
    _ sql: String,
    arguments: StatementArguments = [],
    databaseContext: DatabaseTestContext
) async throws -> Int {
    try await databaseContext.databaseActor.read(paths: databaseContext.paths) { db in
        try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0
    }
}

private func databaseInt(
    _ sql: String,
    arguments: StatementArguments = [],
    databaseContext: DatabaseTestContext
) async throws -> Int? {
    try await databaseContext.databaseActor.read(paths: databaseContext.paths) { db in
        try Int.fetchOne(db, sql: sql, arguments: arguments)
    }
}

private func databasePlanDetails(
    _ sql: String,
    arguments: StatementArguments = [],
    databaseContext: DatabaseTestContext
) async throws -> String {
    try await databaseContext.databaseActor.read(paths: databaseContext.paths) { db in
        let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
        return rows.compactMap { $0["detail"] as String? }.joined(separator: "\n")
    }
}
