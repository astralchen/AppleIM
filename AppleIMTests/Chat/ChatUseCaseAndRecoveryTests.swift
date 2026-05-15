import Testing
import Foundation
import UIKit

@testable import AppleIM

extension AppleIMTests {
    @Test func chatUseCaseSendImageYieldsProgressThenSuccess() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "image_send_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "image_send_conversation", userID: "image_send_user", title: "Image Send", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let useCase = LocalChatUseCase(
            userID: "image_send_user",
            conversationID: "image_send_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [0.25, 0.75, 1.0], delayNanoseconds: 0)
        )

        let rows = try await collectRows(from: useCase.sendImage(data: samplePNGData(), preferredFileExtension: "png"))
        let messageID = try #require(rows.first?.id)
        let storedMessage = try await repository.message(messageID: messageID)
        let imageRows = try await databaseContext.databaseActor.query(
            "SELECT cdn_url, upload_status FROM message_image WHERE content_id = ?;",
            parameters: [.text("image_\(messageID.rawValue)")],
            paths: databaseContext.paths
        )
        let resourceRows = try await databaseContext.databaseActor.query(
            "SELECT remote_url, upload_status FROM media_resource WHERE owner_message_id = ?;",
            parameters: [.text(messageID.rawValue)],
            paths: databaseContext.paths
        )

        #expect(rows.first?.statusText == "Sending")
        #expect(rows.compactMap(\.uploadProgress) == [0.25, 0.75, 1.0])
        #expect(rows.last?.statusText == nil)
        let storedImage = try requireImageContent(storedMessage)
        #expect(storedMessage?.state.sendStatus == .success)
        #expect(storedImage.remoteURL?.contains("mock-cdn.chatbridge.local") == true)
        #expect(imageRows.first?.int("upload_status") == MediaUploadStatus.success.rawValue)
        #expect(imageRows.first?.string("cdn_url") == storedImage.remoteURL)
        #expect(resourceRows.first?.int("upload_status") == MediaUploadStatus.success.rawValue)
        #expect(resourceRows.first?.string("remote_url") == storedImage.remoteURL)
    }

    @Test func chatUseCaseSendVoiceYieldsProgressThenSuccess() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "voice_send_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "voice_send_conversation", userID: "voice_send_user", title: "Voice Send", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let useCase = LocalChatUseCase(
            userID: "voice_send_user",
            conversationID: "voice_send_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [0.3, 0.6, 1.0], delayNanoseconds: 0)
        )

        let rows = try await collectRows(
            from: useCase.sendVoice(
                recording: VoiceRecordingFile(
                    fileURL: try makeVoiceRecordingFile(in: rootDirectory),
                    durationMilliseconds: 1_800,
                    fileExtension: "m4a"
                )
            )
        )
        let messageID = try #require(rows.first?.id)
        let storedMessage = try await repository.message(messageID: messageID)
        let voiceRows = try await databaseContext.databaseActor.query(
            "SELECT cdn_url, upload_status FROM message_voice WHERE content_id = ?;",
            parameters: [.text("voice_\(messageID.rawValue)")],
            paths: databaseContext.paths
        )

        #expect(rows.first?.statusText == "Sending")
        #expect(rows.first.map(isVoiceContent) == true)
        #expect(rows.compactMap(\.uploadProgress) == [0.3, 0.6, 1.0])
        #expect(rows.last?.statusText == nil)
        let storedVoice = try requireVoiceContent(storedMessage)
        #expect(storedMessage?.state.sendStatus == .success)
        #expect(storedVoice.remoteURL?.contains("mock-cdn.chatbridge.local/voice") == true)
        #expect(voiceRows.first?.int("upload_status") == MediaUploadStatus.success.rawValue)
        #expect(voiceRows.first?.string("cdn_url") == storedVoice.remoteURL)
    }

    @Test func chatUseCaseSendVideoYieldsProgressThenSuccess() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "video_send_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "video_send_conversation", userID: "video_send_user", title: "Video Send", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let useCase = LocalChatUseCase(
            userID: "video_send_user",
            conversationID: "video_send_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [0.2, 0.8, 1.0], delayNanoseconds: 0)
        )

        let rows = try await collectRows(
            from: useCase.sendVideo(
                fileURL: try await makeSampleVideoFile(in: rootDirectory),
                preferredFileExtension: "mov"
            )
        )
        let messageID = try #require(rows.first?.id)
        let storedMessage = try await repository.message(messageID: messageID)
        let videoRows = try await databaseContext.databaseActor.query(
            "SELECT cdn_url, upload_status FROM message_video WHERE content_id = ?;",
            parameters: [.text("video_\(messageID.rawValue)")],
            paths: databaseContext.paths
        )

        #expect(rows.first?.statusText == "Sending")
        #expect(rows.first.map(isVideoContent) == true)
        #expect(rows.first.flatMap(videoThumbnailPath) != nil)
        #expect(rows.compactMap(\.uploadProgress) == [0.2, 0.8, 1.0])
        #expect(rows.last?.statusText == nil)
        let storedVideo = try requireVideoContent(storedMessage)
        #expect(storedMessage?.state.sendStatus == .success)
        #expect(storedVideo.remoteURL?.contains("mock-cdn.chatbridge.local/video") == true)
        #expect(videoRows.first?.int("upload_status") == MediaUploadStatus.success.rawValue)
        #expect(videoRows.first?.string("cdn_url") == storedVideo.remoteURL)
    }

    @Test func chatUseCaseDoesNotSendTooShortVoice() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "short_voice_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "short_voice_conversation", userID: "short_voice_user", title: "Short Voice", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let useCase = LocalChatUseCase(
            userID: "short_voice_user",
            conversationID: "short_voice_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [1.0], delayNanoseconds: 0)
        )

        let rows = try await collectRows(
            from: useCase.sendVoice(
                recording: VoiceRecordingFile(
                    fileURL: try makeVoiceRecordingFile(in: rootDirectory),
                    durationMilliseconds: 600,
                    fileExtension: "m4a"
                )
            )
        )
        let messages = try await repository.listMessages(conversationID: "short_voice_conversation", limit: 20, beforeSortSeq: nil)

        #expect(rows.isEmpty)
        #expect(messages.isEmpty)
    }

    @Test func chatUseCaseQueuesImageUploadJobWhenUploadFailsAndResendsWithoutDuplication() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "image_retry_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "image_retry_conversation", userID: "image_retry_user", title: "Image Retry", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let failingUseCase = LocalChatUseCase(
            userID: "image_retry_user",
            conversationID: "image_retry_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(result: .failed(.timeout), progressSteps: [0.4], delayNanoseconds: 0)
        )

        let failedRows = try await collectRows(from: failingUseCase.sendImage(data: samplePNGData(), preferredFileExtension: "png"))
        let failedMessageID = try #require(failedRows.first?.id)
        let failedMessage = try await repository.message(messageID: failedMessageID)
        let recoverableJobs = try await repository.recoverablePendingJobs(userID: "image_retry_user", now: Int64.max)

        let retryingUseCase = LocalChatUseCase(
            userID: "image_retry_user",
            conversationID: "image_retry_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [1.0], delayNanoseconds: 0)
        )
        let retryRows = try await collectRows(from: retryingUseCase.resend(messageID: failedMessageID))
        let storedMessages = try await repository.listMessages(conversationID: "image_retry_conversation", limit: 20, beforeSortSeq: nil)
        let resentMessage = try await repository.message(messageID: failedMessageID)
        let retryJob = try await repository.pendingJob(id: "image_upload_\(failedMessage?.delivery.clientMessageID ?? "")")

        #expect(failedRows.last?.statusText == "Failed")
        #expect(failedRows.last?.canRetry == true)
        #expect(failedMessage?.state.sendStatus == .failed)
        #expect(try requireImageContent(failedMessage).uploadStatus == .failed)
        #expect(recoverableJobs.count == 1)
        #expect(recoverableJobs.first?.type == .imageUpload)
        #expect(recoverableJobs.first?.payloadJSON.contains("timeout") == true)
        #expect(retryRows.last?.statusText == nil)
        #expect(storedMessages.count == 1)
        #expect(resentMessage?.state.sendStatus == .success)
        #expect(retryJob?.status == .success)
    }

    @Test func chatUseCaseQueuesVideoUploadJobWhenUploadFailsAndResendsWithoutDuplication() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "video_retry_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "video_retry_conversation", userID: "video_retry_user", title: "Video Retry", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let failingUseCase = LocalChatUseCase(
            userID: "video_retry_user",
            conversationID: "video_retry_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(result: .failed(.timeout), progressSteps: [0.4], delayNanoseconds: 0)
        )

        let failedRows = try await collectRows(
            from: failingUseCase.sendVideo(
                fileURL: try await makeSampleVideoFile(in: rootDirectory),
                preferredFileExtension: "mov"
            )
        )
        let failedMessageID = try #require(failedRows.first?.id)
        let failedMessage = try await repository.message(messageID: failedMessageID)
        let recoverableJobs = try await repository.recoverablePendingJobs(userID: "video_retry_user", now: Int64.max)

        let retryingUseCase = LocalChatUseCase(
            userID: "video_retry_user",
            conversationID: "video_retry_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [1.0], delayNanoseconds: 0)
        )
        let retryRows = try await collectRows(from: retryingUseCase.resend(messageID: failedMessageID))
        let storedMessages = try await repository.listMessages(conversationID: "video_retry_conversation", limit: 20, beforeSortSeq: nil)
        let resentMessage = try await repository.message(messageID: failedMessageID)
        let retryJob = try await repository.pendingJob(id: "video_upload_\(failedMessage?.delivery.clientMessageID ?? "")")

        #expect(failedRows.last?.statusText == "Failed")
        #expect(failedRows.last?.canRetry == true)
        #expect(failedMessage?.state.sendStatus == .failed)
        #expect(try requireVideoContent(failedMessage).uploadStatus == .failed)
        #expect(recoverableJobs.count == 1)
        #expect(recoverableJobs.first?.type == .videoUpload)
        #expect(recoverableJobs.first?.payloadJSON.contains("timeout") == true)
        #expect(retryRows.last?.statusText == nil)
        #expect(storedMessages.count == 1)
        #expect(resentMessage?.state.sendStatus == .success)
        #expect(retryJob?.status == .success)
    }

    @Test func chatUseCasePersistsServerAckForImageAndVideoSends() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "media_server_ack_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "media_server_ack_conversation", userID: "media_server_ack_user", title: "Media Ack", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let service = ServerMessageSendService(
            httpClient: RecordingHTTPClient(
                response: ServerTextMessageSendResponse(
                    serverMessageID: "server_media_message",
                    sequence: 919,
                    serverTime: 1_777_777_919
                )
            )
        )
        let useCase = LocalChatUseCase(
            userID: "media_server_ack_user",
            conversationID: "media_server_ack_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: service,
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [1.0], delayNanoseconds: 0)
        )

        let imageRows = try await collectRows(from: useCase.sendImage(data: samplePNGData(), preferredFileExtension: "png"))
        let videoRows = try await collectRows(
            from: useCase.sendVideo(
                fileURL: try await makeSampleVideoFile(in: rootDirectory),
                preferredFileExtension: "mov"
            )
        )
        let imageMessage = try await repository.message(messageID: try #require(imageRows.first?.id))
        let videoMessage = try await repository.message(messageID: try #require(videoRows.first?.id))

        #expect(imageRows.last?.statusText == nil)
        #expect(videoRows.last?.statusText == nil)
        #expect(imageMessage?.state.sendStatus == .success)
        #expect(videoMessage?.state.sendStatus == .success)
        #expect(imageMessage?.delivery.serverMessageID == "server_media_message")
        #expect(videoMessage?.delivery.serverMessageID == "server_media_message")
        #expect(imageMessage?.delivery.sequence == 919)
        #expect(videoMessage?.delivery.sequence == 919)
        #expect(try requireImageContent(imageMessage).remoteURL?.contains("mock-cdn.chatbridge.local/image") == true)
        #expect(try requireVideoContent(videoMessage).remoteURL?.contains("mock-cdn.chatbridge.local/video") == true)
    }

    @Test func chatUseCaseQueuesMediaUploadJobWhenServerMediaSendFailsAfterUpload() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "media_server_fail_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "media_server_fail_conversation", userID: "media_server_fail_user", title: "Media Fail", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let useCase = LocalChatUseCase(
            userID: "media_server_fail_user",
            conversationID: "media_server_fail_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: ServerMessageSendService(httpClient: RecordingHTTPClient(error: ChatBridgeHTTPError.timeout)),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [1.0], delayNanoseconds: 0),
            retryPolicy: MessageRetryPolicy(initialDelaySeconds: 2, maxDelaySeconds: 10, maxRetryCount: 3)
        )

        let imageRows = try await collectRows(from: useCase.sendImage(data: samplePNGData(), preferredFileExtension: "png"))
        let videoRows = try await collectRows(
            from: useCase.sendVideo(
                fileURL: try await makeSampleVideoFile(in: rootDirectory),
                preferredFileExtension: "mov"
            )
        )
        let imageMessage = try await repository.message(messageID: try #require(imageRows.first?.id))
        let videoMessage = try await repository.message(messageID: try #require(videoRows.first?.id))
        let imageJob = try await repository.pendingJob(id: "image_upload_\(imageMessage?.delivery.clientMessageID ?? "")")
        let videoJob = try await repository.pendingJob(id: "video_upload_\(videoMessage?.delivery.clientMessageID ?? "")")

        #expect(imageRows.last?.statusText == "Failed")
        #expect(videoRows.last?.statusText == "Failed")
        let uploadedImage = try requireImageContent(imageMessage)
        let uploadedVideo = try requireVideoContent(videoMessage)
        #expect(imageMessage?.state.sendStatus == .failed)
        #expect(videoMessage?.state.sendStatus == .failed)
        #expect(uploadedImage.uploadStatus == .failed)
        #expect(uploadedVideo.uploadStatus == .failed)
        #expect(uploadedImage.remoteURL?.contains("mock-cdn.chatbridge.local/image") == true)
        #expect(uploadedVideo.remoteURL?.contains("mock-cdn.chatbridge.local/video") == true)
        #expect(imageJob?.type == .imageUpload)
        #expect(videoJob?.type == .videoUpload)
        #expect(imageJob?.payloadJSON.contains("timeout") == true)
        #expect(videoJob?.payloadJSON.contains("timeout") == true)
    }

    @Test func outgoingTextMessagePersistsMentionMetadata() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "mention_send_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "mention_send_conversation", userID: "mention_send_user", type: .group, targetID: "mention_group")
        )

        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "mention_send_user",
                conversationID: "mention_send_conversation",
                senderID: "mention_send_user",
                text: "@Sondra 请看这里",
                localTime: 200,
                messageID: "mention_send_message",
                mentionedUserIDs: ["sondra"],
                mentionsAll: false,
                sortSequence: 200
            )
        )

        let rows = try await databaseContext.databaseActor.query(
            "SELECT mentions_json, at_all FROM message_text WHERE content_id = ?;",
            parameters: [.text("text_\(message.id.rawValue)")],
            paths: databaseContext.paths
        )

        #expect(rows.first?.string("mentions_json") == "[\"sondra\"]")
        #expect(rows.first?.int("at_all") == 0)
    }

    @Test func incomingMentionMarksConversationUntilRead() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "mention_incoming_user")
        let batch = SyncBatch(
            messages: [
                IncomingSyncMessage(
                    messageID: "incoming_mention_message",
                    conversationID: "incoming_mention_conversation",
                    senderID: "teammate",
                    serverMessageID: "server_incoming_mention",
                    sequence: 10,
                    text: "@我 看下公告",
                    serverTime: 10,
                    conversationTitle: "Mention Group",
                    conversationType: .group,
                    mentionedUserIDs: ["mention_incoming_user"]
                )
            ],
            nextCursor: "cursor",
            nextSequence: 10
        )

        _ = try await repository.applyIncomingSyncBatch(batch, userID: "mention_incoming_user")
        let rowsBeforeRead = LocalConversationListUseCase.rowStates(
            from: try await repository.listConversations(for: "mention_incoming_user")
        )
        try await repository.markConversationRead(conversationID: "incoming_mention_conversation", userID: "mention_incoming_user")
        let rowsAfterRead = LocalConversationListUseCase.rowStates(
            from: try await repository.listConversations(for: "mention_incoming_user")
        )

        #expect(rowsBeforeRead.first?.mentionIndicatorText == "[有人@我]")
        #expect(rowsBeforeRead.first?.subtitle.hasPrefix("[有人@我] ") == true)
        #expect(rowsAfterRead.first?.mentionIndicatorText == nil)
    }

    @Test func messageRepositoryUpdatesSendStatusAndFindsMessageByID() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "status_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "status_conversation", userID: "status_user", title: "Status", sortTimestamp: 1)
        )

        let insertedMessage = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "status_user",
                conversationID: "status_conversation",
                senderID: "status_user",
                text: "Status update",
                localTime: 400,
                messageID: "status_message",
                clientMessageID: "status_client",
                sortSequence: 400
            )
        )

        try await repository.updateMessageSendStatus(
            messageID: insertedMessage.id,
            status: .success,
            ack: MessageSendAck(serverMessageID: "server_status", sequence: 401, serverTime: 401)
        )

        let updatedMessage = try await repository.message(messageID: insertedMessage.id)
        let missingMessage = try await repository.message(messageID: "missing_message")

        #expect(updatedMessage?.state.sendStatus == .success)
        #expect(missingMessage == nil)
    }

    @Test func chatUseCaseLoadsInitialMessagesInAscendingOrder() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "chat_order_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "chat_order_conversation", userID: "chat_order_user", title: "Chat", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "chat_order_user",
                conversationID: "chat_order_conversation",
                senderID: "chat_order_user",
                text: "First",
                localTime: 100,
                messageID: "chat_first",
                clientMessageID: "chat_first_client",
                sortSequence: 100
            )
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "chat_order_user",
                conversationID: "chat_order_conversation",
                senderID: "chat_order_user",
                text: "Second",
                localTime: 200,
                messageID: "chat_second",
                clientMessageID: "chat_second_client",
                sortSequence: 200
            )
        )

        let useCase = LocalChatUseCase(
            userID: "chat_order_user",
            conversationID: "chat_order_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let page = try await useCase.loadInitialMessages()

        #expect(page.rows.map(rowText) == ["First", "Second"])
        #expect(page.hasMore == false)
        #expect(page.nextBeforeSortSequence == 100)
    }

    @MainActor
    @Test func storeBackedChatUseCaseSimulatesIncomingTextMessageThroughSyncStore() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "simulated_store_user",
            storageService: storageService,
            database: DatabaseActor(),
            shouldSeedDemoData: false
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "simulated_store_conversation",
                userID: "simulated_store_user",
                title: "Simulated Store",
                sortTimestamp: 100
            )
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "simulated_store_user",
                conversationID: "simulated_store_conversation",
                senderID: "simulated_store_user",
                text: "Before simulated incoming",
                localTime: 100,
                messageID: "simulated_store_existing",
                clientMessageID: "simulated_store_existing_client",
                sortSequence: 100
            )
        )
        let useCase = StoreBackedChatUseCase(
            userID: "simulated_store_user",
            conversationID: "simulated_store_conversation",
            storeProvider: storeProvider,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: AccountMediaFileStore(accountID: "simulated_store_user", storageService: storageService)
        )

        let row = try #require(try await useCase.simulateIncomingMessages().first)
        let secondRow = try #require(try await useCase.simulateIncomingMessages().first)
        let storedMessage = try #require(try await repository.message(messageID: row.id))
        let secondStoredMessage = try #require(try await repository.message(messageID: secondRow.id))
        let page = try await useCase.loadInitialMessages()

        #expect(row.id.rawValue.hasPrefix("simulated_push_incoming_"))
        #expect(row.isOutgoing == false)
        let storedText = try requireTextContent(storedMessage)
        let secondStoredText = try requireTextContent(secondStoredMessage)
        #expect(storedMessage.state.direction == .incoming)
        #expect(secondStoredMessage.state.direction == .incoming)
        #expect(storedText.isEmpty == false)
        #expect(secondStoredText.isEmpty == false)
        #expect(storedText != secondStoredText)
        #expect(storedMessage.timeline.sortSequence >= 101)
        #expect(secondStoredMessage.timeline.sortSequence > storedMessage.timeline.sortSequence)
        #expect(page.rows.contains { $0.id == row.id })
        #expect(page.rows.contains { $0.id == secondRow.id })
    }

    @MainActor
    @Test func storeBackedChatUseCaseAssignsDistinctSequencesForConcurrentSimulatedIncomingMessages() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "simulated_concurrent_user",
            storageService: storageService,
            database: DatabaseActor(),
            shouldSeedDemoData: false
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "simulated_concurrent_conversation",
                userID: "simulated_concurrent_user",
                title: "Simulated Concurrent",
                sortTimestamp: 100
            )
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "simulated_concurrent_user",
                conversationID: "simulated_concurrent_conversation",
                senderID: "simulated_concurrent_user",
                text: "Before concurrent simulated incoming",
                localTime: 100,
                messageID: "simulated_concurrent_existing",
                clientMessageID: "simulated_concurrent_existing_client",
                sortSequence: 100
            )
        )
        let useCase = StoreBackedChatUseCase(
            userID: "simulated_concurrent_user",
            conversationID: "simulated_concurrent_conversation",
            storeProvider: storeProvider,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: AccountMediaFileStore(accountID: "simulated_concurrent_user", storageService: storageService)
        )

        async let first = useCase.simulateIncomingMessages()
        async let second = useCase.simulateIncomingMessages()
        let rows = try await [first, second].flatMap { $0 }
        var storedMessages: [StoredMessage] = []
        for row in rows {
            storedMessages.append(try #require(try await repository.message(messageID: row.id)))
        }
        let sortedSequences = storedMessages.map(\.timeline.sortSequence).sorted()

        #expect(rows.count >= 2)
        #expect(Set(rows.map(\.id)).count == rows.count)
        #expect(Set(storedMessages.map(\.timeline.sortSequence)).count == storedMessages.count)
        #expect(sortedSequences[1] > sortedSequences[0])
    }

    @MainActor
    @Test func storeBackedChatUseCaseKeepsSimulatedIncomingMessageReadWhenChatIsOpen() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "simulated_read_user",
            storageService: storageService,
            database: DatabaseActor(),
            shouldSeedDemoData: false
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "simulated_read_conversation",
                userID: "simulated_read_user",
                title: "Simulated Read",
                unreadCount: 0,
                sortTimestamp: 100
            )
        )
        let useCase = StoreBackedChatUseCase(
            userID: "simulated_read_user",
            conversationID: "simulated_read_conversation",
            storeProvider: storeProvider,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: AccountMediaFileStore(accountID: "simulated_read_user", storageService: storageService)
        )

        _ = try await useCase.loadInitialMessages()
        let row = try #require(try await useCase.simulateIncomingMessages().first)

        try await waitForCondition {
            let conversations = try await repository.listConversations(for: "simulated_read_user")
            let storedMessage = try await repository.message(messageID: row.id)
            let conversation = conversations.first { $0.id == "simulated_read_conversation" }
            return conversation?.unreadCount == 0 && storedMessage?.state.readStatus == .read
        }
        let conversations = try await repository.listConversations(for: "simulated_read_user")
        let storedMessage = try #require(try await repository.message(messageID: row.id))
        let conversation = try #require(conversations.first { $0.id == "simulated_read_conversation" })
        #expect(conversation.unreadCount == 0)
        #expect(storedMessage.state.readStatus == .read)
    }

    @Test func localChatUseCaseRequestsCurrentConversationWhenTriggeringChatPush() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "chat_push_request_user")
        let conversationID = ConversationID(rawValue: "chat_push_request_conversation")
        let message = IncomingSyncMessage(
            messageID: "chat_push_request_message",
            conversationID: conversationID,
            senderID: "chat_push_request_peer",
            serverMessageID: "server_chat_push_request_message",
            sequence: 101,
            text: "后台推送对方消息",
            serverTime: 101,
            direction: .incoming,
            conversationTitle: "Chat Push Request",
            conversationType: .single
        )
        let pusher = CapturingSimulatedIncomingPusher(
            result: SimulatedIncomingPushResult(
                conversationID: conversationID,
                messages: [message],
                insertedCount: 1,
                finalConversation: Conversation(
                    id: conversationID,
                    type: .single,
                    title: "Chat Push Request",
                    avatarURL: nil,
                    lastMessageDigest: message.text,
                    lastMessageTimeText: "Now",
                    unreadCount: 1,
                    isPinned: false,
                    isMuted: false,
                    draftText: nil,
                    sortTimestamp: message.sequence
                )
            )
        )
        let useCase = LocalChatUseCase(
            userID: "chat_push_request_user",
            conversationID: conversationID,
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            simulatedIncomingPushService: pusher
        )

        let rows = try await useCase.simulateIncomingMessages()
        let requests = await pusher.requests

        #expect(requests == [SimulatedIncomingPushRequest(target: .conversation(conversationID))])
        #expect(rows.map(\.id) == [message.messageID])
        #expect(rows.allSatisfy { $0.isOutgoing == false })
    }

    @MainActor
    @Test func storeBackedChatUseCasePushesOnlyIntoCurrentConversation() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "chat_current_push_user",
            storageService: storageService,
            database: DatabaseActor(),
            shouldSeedDemoData: false
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "chat_current_push_conversation",
                userID: "chat_current_push_user",
                title: "Current Push",
                targetID: "chat_current_push_peer",
                sortTimestamp: 100
            )
        )
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "chat_other_push_conversation",
                userID: "chat_current_push_user",
                title: "Other Push",
                targetID: "chat_other_push_peer",
                sortTimestamp: 200
            )
        )
        let useCase = StoreBackedChatUseCase(
            userID: "chat_current_push_user",
            conversationID: "chat_current_push_conversation",
            storeProvider: storeProvider,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: AccountMediaFileStore(accountID: "chat_current_push_user", storageService: storageService)
        )

        let rows = try await useCase.simulateIncomingMessages()
        let currentMessages = try await repository.listMessages(
            conversationID: "chat_current_push_conversation",
            limit: 10,
            beforeSortSeq: nil
        )
        let otherMessages = try await repository.listMessages(
            conversationID: "chat_other_push_conversation",
            limit: 10,
            beforeSortSeq: nil
        )

        #expect(rows.isEmpty == false)
        #expect(currentMessages.count == rows.count)
        #expect(Set(currentMessages.map(\.id)) == Set(rows.map(\.id)))
        #expect(otherMessages.isEmpty)
        #expect(currentMessages.allSatisfy { $0.state.direction == .incoming })
        #expect(currentMessages.allSatisfy { $0.senderID == "chat_current_push_peer" })
        #expect(rows.allSatisfy { $0.isOutgoing == false })
    }

    @Test func chatUseCaseMapsSenderAvatarURLsByMessageDirection() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "avatar_chat_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "avatar_chat_conversation", userID: "avatar_chat_user", title: "Avatar Chat", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "avatar_chat_user",
                conversationID: "avatar_chat_conversation",
                senderID: "avatar_chat_user",
                text: "From me",
                localTime: 100,
                messageID: "avatar_outgoing",
                clientMessageID: "avatar_outgoing_client",
                sortSequence: 100
            )
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "avatar_chat_user",
                conversationID: "avatar_chat_conversation",
                senderID: "friend_user",
                text: "From friend",
                localTime: 200,
                messageID: "avatar_incoming",
                clientMessageID: "avatar_incoming_client",
                sortSequence: 200
            )
        )

        let useCase = LocalChatUseCase(
            userID: "avatar_chat_user",
            conversationID: "avatar_chat_conversation",
            currentUserAvatarURL: "file:///tmp/current-avatar.png",
            conversationAvatarURL: "https://example.com/friend-avatar.png",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let page = try await useCase.loadInitialMessages()

        #expect(page.rows.first?.senderAvatarURL == "file:///tmp/current-avatar.png")
        #expect(page.rows.last?.senderAvatarURL == "https://example.com/friend-avatar.png")
    }

    @Test func chatUseCaseInitialPageReturnsLatestFiftyMessagesAscending() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "chat_page_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "chat_page_conversation", userID: "chat_page_user", title: "Paged", sortTimestamp: 1)
        )

        for index in 1...60 {
            _ = try await repository.insertOutgoingTextMessage(
                OutgoingTextMessageInput(
                    userID: "chat_page_user",
                    conversationID: "chat_page_conversation",
                    senderID: "chat_page_user",
                    text: "Message \(index)",
                    localTime: Int64(index),
                    messageID: MessageID(rawValue: "chat_page_\(index)"),
                    clientMessageID: "chat_page_client_\(index)",
                    sortSequence: Int64(index)
                )
            )
        }

        let useCase = LocalChatUseCase(
            userID: "chat_page_user",
            conversationID: "chat_page_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let page = try await useCase.loadInitialMessages()

        #expect(page.rows.count == 50)
        #expect(page.rows.first.map(rowText) == "Message 11")
        #expect(page.rows.last.map(rowText) == "Message 60")
        #expect(page.hasMore == true)
        #expect(page.nextBeforeSortSequence == 11)
    }

    @Test func seededSondraConversationInitialPageLoadsNewestFiftyMessages() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "mock_user")
        try await DemoDataSeeder.seedIfNeeded(
            repository: repository,
            userID: "mock_user",
            catalog: BundleDemoDataCatalog(resourceURL: try makeMockDemoDataFile(messageCount: 120)),
            contactCatalog: BundleContactCatalog(resourceURL: try makeMockContactsFile())
        )
        let useCase = LocalChatUseCase(
            userID: "mock_user",
            conversationID: "single_sondra",
            repository: repository,
            conversationRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )

        let page = try await useCase.loadInitialMessages()

        #expect(page.rows.count == 50)
        #expect(page.rows.first.map(rowText) == "Sondra JSON message 71")
        #expect(page.rows.last.map(rowText) == "Sondra JSON message 120")
        #expect(page.hasMore == true)
        #expect(page.nextBeforeSortSequence == page.rows.first?.sortSequence)
    }

    @Test func chatUseCaseOlderPageUsesSortSequenceCursor() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "older_page_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "older_page_conversation", userID: "older_page_user", title: "Older", sortTimestamp: 1)
        )

        for index in 1...60 {
            _ = try await repository.insertOutgoingTextMessage(
                OutgoingTextMessageInput(
                    userID: "older_page_user",
                    conversationID: "older_page_conversation",
                    senderID: "older_page_user",
                    text: "Older \(index)",
                    localTime: Int64(index),
                    messageID: MessageID(rawValue: "older_page_\(index)"),
                    clientMessageID: "older_page_client_\(index)",
                    sortSequence: Int64(index)
                )
            )
        }

        let useCase = LocalChatUseCase(
            userID: "older_page_user",
            conversationID: "older_page_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let olderPage = try await useCase.loadOlderMessages(beforeSortSequence: 11, limit: 50)

        #expect(olderPage.rows.count == 10)
        #expect(olderPage.rows.first.map(rowText) == "Older 1")
        #expect(olderPage.rows.last.map(rowText) == "Older 10")
        #expect(olderPage.hasMore == false)
        #expect(olderPage.nextBeforeSortSequence == 1)
    }

    @Test func chatUseCasePagesThroughOneHundredThousandMessagesWithCursor() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "chat_perf_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "chat_perf_conversation", userID: "chat_perf_user", title: "Performance", sortTimestamp: 100_000)
        )
        try await seedPerformanceMessages(
            databaseContext: databaseContext,
            conversationID: "chat_perf_conversation",
            userID: "chat_perf_user",
            count: 100_000
        )

        let useCase = LocalChatUseCase(
            userID: "chat_perf_user",
            conversationID: "chat_perf_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let initialPage = try await useCase.loadInitialMessages()
        let olderPage = try await useCase.loadOlderMessages(beforeSortSequence: 99_951, limit: 50)

        #expect(initialPage.rows.count == 50)
        #expect(initialPage.rows.first.map(rowText) == "Perf Message 99951")
        #expect(initialPage.rows.last.map(rowText) == "Perf Message 100000")
        #expect(initialPage.hasMore == true)
        #expect(initialPage.nextBeforeSortSequence == 99_951)
        #expect(olderPage.rows.count == 50)
        #expect(olderPage.rows.first.map(rowText) == "Perf Message 99901")
        #expect(olderPage.rows.last.map(rowText) == "Perf Message 99950")
        #expect(olderPage.hasMore == true)
        #expect(olderPage.nextBeforeSortSequence == 99_901)
    }

    @MainActor
    @Test func chatUseCaseSendTextYieldsSendingThenSuccess() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "chat_send_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "chat_send_conversation", userID: "chat_send_user", title: "Send", sortTimestamp: 1)
        )
        try await repository.saveDraft(conversationID: "chat_send_conversation", userID: "chat_send_user", text: "draft before send")

        let useCase = LocalChatUseCase(
            userID: "chat_send_user",
            conversationID: "chat_send_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        var iterator = useCase.sendText("Hello mock ack").makeAsyncIterator()
        let sendingRow = try #require(try await iterator.next())
        let draftAfterFirstRow = try await repository.draft(conversationID: "chat_send_conversation", userID: "chat_send_user")
        let successRow = try #require(try await iterator.next())
        let storedMessage = try await repository.message(messageID: sendingRow.id)

        #expect(sendingRow.statusText == "Sending")
        #expect(successRow.statusText == nil)
        #expect(draftAfterFirstRow == "draft before send")
        #expect(try await iterator.next() == nil)
        #expect(try await repository.draft(conversationID: "chat_send_conversation", userID: "chat_send_user") == nil)
        #expect(storedMessage?.state.sendStatus == .success)
    }

    @Test func chatUseCaseQueuesPendingJobWhenUnauthorizedRefreshFails() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "refresh_fail_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "refresh_fail_conversation", userID: "refresh_fail_user", title: "Refresh Fail", sortTimestamp: 1)
        )
        let httpClient = ExpiringTextHTTPClient(error: ChatBridgeHTTPError.unacceptableStatus(401))
        let refreshingClient = TokenRefreshingHTTPClient(httpClient: httpClient) {
            nil
        }
        let useCase = LocalChatUseCase(
            userID: "refresh_fail_user",
            conversationID: "refresh_fail_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: ServerMessageSendService(httpClient: refreshingClient),
            retryPolicy: MessageRetryPolicy(initialDelaySeconds: 2, maxDelaySeconds: 10, maxRetryCount: 3)
        )

        let rows = try await collectRows(from: useCase.sendText("Queue after refresh fail"))
        let failedMessage = try await repository.message(messageID: rows[0].id)!
        let pendingJob = try #require(try await repository.pendingJob(id: PendingMessageJobFactory.messageResendJobID(clientMessageID: failedMessage.delivery.clientMessageID ?? "")))

        #expect(rows.map(\.statusText) == ["Sending", "Failed"])
        #expect(failedMessage.state.sendStatus == .failed)
        #expect(pendingJob.type == .messageResend)
        #expect(pendingJob.payloadJSON.contains("unknown"))
        #expect(await httpClient.textSendCallCount == 1)
    }

    @Test func chatUseCasePersistsServerAckFromServerMessageSendService() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "server_ack_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "server_ack_conversation", userID: "server_ack_user", title: "Server Ack", sortTimestamp: 1)
        )
        let service = ServerMessageSendService(
            httpClient: RecordingHTTPClient(
                response: ServerTextMessageSendResponse(
                    serverMessageID: "server_ack_message",
                    sequence: 909,
                    serverTime: 1_777_777_909
                )
            )
        )
        let useCase = LocalChatUseCase(
            userID: "server_ack_user",
            conversationID: "server_ack_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: service
        )

        let rows = try await collectRows(from: useCase.sendText("Persist server ack"))
        let storedMessage = try await repository.message(messageID: rows[0].id)

        #expect(rows.map(\.statusText) == ["Sending", nil])
        #expect(storedMessage?.state.sendStatus == .success)
        #expect(storedMessage?.delivery.serverMessageID == "server_ack_message")
        #expect(storedMessage?.delivery.sequence == 909)
        #expect(storedMessage?.timeline.serverTime == 1_777_777_909)
    }

    @Test func chatUseCaseQueuesPendingJobForServerAckFailureAndResendsWithSameClientMessageID() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "server_retry_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "server_retry_conversation", userID: "server_retry_user", title: "Server Retry", sortTimestamp: 1)
        )
        let failingUseCase = LocalChatUseCase(
            userID: "server_retry_user",
            conversationID: "server_retry_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: ServerMessageSendService(httpClient: RecordingHTTPClient(error: ChatBridgeHTTPError.ackMissing)),
            retryPolicy: MessageRetryPolicy(initialDelaySeconds: 2, maxDelaySeconds: 10, maxRetryCount: 3)
        )

        let failedRows = try await collectRows(from: failingUseCase.sendText("Retry with same client id"))
        let failedMessageID = failedRows[0].id
        let failedMessage = try await repository.message(messageID: failedMessageID)!
        let pendingJob = try #require(try await repository.pendingJob(id: PendingMessageJobFactory.messageResendJobID(clientMessageID: failedMessage.delivery.clientMessageID ?? "")))

        let successClient = RecordingHTTPClient(
            response: ServerTextMessageSendResponse(
                serverMessageID: "server_retry_ack",
                sequence: 808,
                serverTime: 1_777_777_808
            )
        )
        let retryingUseCase = LocalChatUseCase(
            userID: "server_retry_user",
            conversationID: "server_retry_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: ServerMessageSendService(httpClient: successClient)
        )
        let retryRows = try await collectRows(from: retryingUseCase.resend(messageID: failedMessageID))
        let storedMessages = try await repository.listMessages(conversationID: "server_retry_conversation", limit: 20, beforeSortSeq: nil)
        let resentMessage = try await repository.message(messageID: failedMessageID)
        let retryRequest = await successClient.lastTextRequest

        #expect(failedRows.map(\.statusText) == ["Sending", "Failed"])
        #expect(pendingJob.type == .messageResend)
        #expect(pendingJob.payloadJSON.contains("ackMissing"))
        #expect(retryRows.map(\.statusText) == ["Sending", nil])
        #expect(storedMessages.count == 1)
        #expect(resentMessage?.delivery.clientMessageID == failedMessage.delivery.clientMessageID)
        #expect(resentMessage?.delivery.serverMessageID == "server_retry_ack")
        #expect(retryRequest?.clientMessageID == failedMessage.delivery.clientMessageID)
    }

    @Test func chatUseCaseDoesNotSendBlankText() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "blank_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "blank_conversation", userID: "blank_user", title: "Blank", sortTimestamp: 1)
        )

        let useCase = LocalChatUseCase(
            userID: "blank_user",
            conversationID: "blank_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let rows = try await collectRows(from: useCase.sendText("   \n  "))
        let messages = try await repository.listMessages(conversationID: "blank_conversation", limit: 20, beforeSortSeq: nil)

        #expect(rows.isEmpty)
        #expect(messages.isEmpty)
    }

    @Test func chatUseCaseResendsFailedTextWithoutDuplicatingMessage() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "resend_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "resend_conversation", userID: "resend_user", title: "Resend", sortTimestamp: 1)
        )

        let failingUseCase = LocalChatUseCase(
            userID: "resend_user",
            conversationID: "resend_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(result: .failure(), delayNanoseconds: 0)
        )
        let failedRows = try await collectRows(from: failingUseCase.sendText("Retry me"))
        let failedMessageID = failedRows[0].id
        let failedMessage = try await repository.message(messageID: failedMessageID)!

        let retryingUseCase = LocalChatUseCase(
            userID: "resend_user",
            conversationID: "resend_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let retryRows = try await collectRows(from: retryingUseCase.resend(messageID: failedMessageID))
        let storedMessages = try await repository.listMessages(conversationID: "resend_conversation", limit: 20, beforeSortSeq: nil)
        let resentMessage = try await repository.message(messageID: failedMessageID)!

        #expect(failedRows.map(\.statusText) == ["Sending", "Failed"])
        #expect(failedRows.last?.canRetry == true)
        #expect(retryRows.map(\.statusText) == ["Sending", nil])
        #expect(storedMessages.count == 1)
        #expect(resentMessage.state.sendStatus == .success)
        #expect(resentMessage.delivery.clientMessageID == failedMessage.delivery.clientMessageID)
    }

    @Test func pendingJobRepositoryUpsertsAndRestoresUnfinishedJobs() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "pending_user")
        let input = PendingJobInput(
            id: "message_resend_pending_client",
            userID: "pending_user",
            type: .messageResend,
            bizKey: "pending_client",
            payloadJSON: #"{"message_id":"pending_message","client_msg_id":"pending_client"}"#,
            maxRetryCount: 3,
            nextRetryAt: 100
        )

        let insertedJob = try await repository.upsertPendingJob(input)
        let duplicateJob = try await repository.upsertPendingJob(input)
        try await repository.updatePendingJobStatus(jobID: input.id, status: .running, nextRetryAt: 100)

        let storedJob = try await repository.pendingJob(id: input.id)
        let recoverableJobs = try await repository.recoverablePendingJobs(userID: "pending_user", now: 100)

        #expect(insertedJob.status == .pending)
        #expect(duplicateJob.id == insertedJob.id)
        #expect(storedJob?.status == .running)
        #expect(recoverableJobs.map(\.id) == [input.id])
    }

    @Test func pendingJobRepositoryTracksFailedSuccessAndCancelledStates() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "pending_state_user")
        let retryInput = PendingJobInput(
            id: "retry_state_job",
            userID: "pending_state_user",
            type: .messageResend,
            bizKey: "retry_state_client",
            payloadJSON: #"{"message_id":"retry_state_message"}"#,
            maxRetryCount: 2
        )
        let successInput = PendingJobInput(
            id: "success_state_job",
            userID: "pending_state_user",
            type: .messageResend,
            bizKey: "success_state_client",
            payloadJSON: #"{"message_id":"success_state_message"}"#
        )
        let cancelledInput = PendingJobInput(
            id: "cancelled_state_job",
            userID: "pending_state_user",
            type: .messageResend,
            bizKey: "cancelled_state_client",
            payloadJSON: #"{"message_id":"cancelled_state_message"}"#
        )

        _ = try await repository.upsertPendingJob(retryInput)
        _ = try await repository.upsertPendingJob(successInput)
        _ = try await repository.upsertPendingJob(cancelledInput)
        try await repository.updatePendingJobStatus(jobID: retryInput.id, status: .failed, nextRetryAt: 200)
        try await repository.updatePendingJobStatus(jobID: successInput.id, status: .success, nextRetryAt: nil)
        try await repository.updatePendingJobStatus(jobID: cancelledInput.id, status: .cancelled, nextRetryAt: nil)

        let retryJob = try await repository.pendingJob(id: retryInput.id)
        let successJob = try await repository.pendingJob(id: successInput.id)
        let cancelledJob = try await repository.pendingJob(id: cancelledInput.id)
        let recoverableJobs = try await repository.recoverablePendingJobs(userID: "pending_state_user", now: 200)

        #expect(retryJob?.status == .failed)
        #expect(retryJob?.retryCount == 1)
        #expect(successJob?.status == .success)
        #expect(cancelledJob?.status == .cancelled)
        #expect(recoverableJobs.isEmpty)
    }

    @Test func chatUseCaseCreatesPendingJobWhenSendFails() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "send_pending_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "send_pending_conversation", userID: "send_pending_user", title: "Pending", sortTimestamp: 1)
        )

        let useCase = LocalChatUseCase(
            userID: "send_pending_user",
            conversationID: "send_pending_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(result: .failure(.timeout), delayNanoseconds: 0),
            retryPolicy: MessageRetryPolicy(initialDelaySeconds: 3, maxDelaySeconds: 30, maxRetryCount: 4)
        )

        let startedAt = Int64(Date().timeIntervalSince1970)
        let rows = try await collectRows(from: useCase.sendText("Queue me"))
        let failedMessage = try await repository.message(messageID: rows[0].id)!
        let recoverableJobs = try await repository.recoverablePendingJobs(userID: "send_pending_user", now: Int64.max)
        let job = recoverableJobs.first

        #expect(rows.map(\.statusText) == ["Sending", "Failed"])
        #expect(failedMessage.state.sendStatus == .failed)
        #expect(recoverableJobs.count == 1)
        #expect(job?.type == .messageResend)
        #expect(job?.bizKey == failedMessage.delivery.clientMessageID)
        #expect(job?.maxRetryCount == 4)
        #expect((job?.nextRetryAt ?? 0) >= startedAt + 3)
        #expect(job?.payloadJSON.contains(failedMessage.id.rawValue) == true)
        #expect(job?.payloadJSON.contains("send_pending_conversation") == true)
        #expect(job?.payloadJSON.contains("timeout") == true)
    }

    @Test func pendingMessageRetryRunnerReschedulesWeakNetworkFailuresWithBackoff() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "retry_runner_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "retry_runner_conversation", userID: "retry_runner_user", title: "Retry Runner", sortTimestamp: 1)
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "retry_runner_user",
                conversationID: "retry_runner_conversation",
                senderID: "retry_runner_user",
                text: "Retry after weak network",
                localTime: 100,
                messageID: "retry_runner_message",
                clientMessageID: "retry_runner_client",
                sortSequence: 100
            )
        )
        try await repository.updateMessageSendStatus(messageID: message.id, status: .failed, ack: nil)
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "message_resend_retry_runner_client",
                userID: "retry_runner_user",
                type: .messageResend,
                bizKey: "retry_runner_client",
                payloadJSON: #"{"messageID":"retry_runner_message","conversationID":"retry_runner_conversation","clientMessageID":"retry_runner_client","lastFailureReason":"offline"}"#,
                maxRetryCount: 3,
                nextRetryAt: 100
            )
        )
        let runner = PendingMessageRetryRunner(
            userID: "retry_runner_user",
            messageRepository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(result: .failure(.ackMissing), delayNanoseconds: 0),
            retryPolicy: MessageRetryPolicy(initialDelaySeconds: 10, maxDelaySeconds: 60, maxRetryCount: 3)
        )

        let result = try await runner.runDueJobs(now: 1_000)
        let job = try await repository.pendingJob(id: "message_resend_retry_runner_client")
        let storedMessage = try await repository.message(messageID: message.id)

        #expect(result == PendingMessageRetryRunResult(scannedJobCount: 1, attemptedCount: 1, successCount: 0, rescheduledCount: 1, exhaustedCount: 0))
        #expect(job?.status == .pending)
        #expect(job?.retryCount == 1)
        #expect(job?.nextRetryAt == 1_020)
        #expect(storedMessage?.state.sendStatus == .failed)
    }

    @Test func pendingMessageRetryRunnerMarksJobSuccessAfterRecoveredAck() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "retry_success_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "retry_success_conversation", userID: "retry_success_user", title: "Retry Success", sortTimestamp: 1)
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "retry_success_user",
                conversationID: "retry_success_conversation",
                senderID: "retry_success_user",
                text: "Recover ack",
                localTime: 200,
                messageID: "retry_success_message",
                clientMessageID: "retry_success_client",
                sortSequence: 200
            )
        )
        try await repository.updateMessageSendStatus(messageID: message.id, status: .failed, ack: nil)
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "message_resend_retry_success_client",
                userID: "retry_success_user",
                type: .messageResend,
                bizKey: "retry_success_client",
                payloadJSON: #"{"messageID":"retry_success_message","conversationID":"retry_success_conversation","clientMessageID":"retry_success_client","lastFailureReason":"ackMissing"}"#,
                maxRetryCount: 3,
                nextRetryAt: 100
            )
        )
        let runner = PendingMessageRetryRunner(
            userID: "retry_success_user",
            messageRepository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )

        let result = try await runner.runDueJobs(now: 100)
        let job = try await repository.pendingJob(id: "message_resend_retry_success_client")
        let storedMessage = try await repository.message(messageID: message.id)

        #expect(result.successCount == 1)
        #expect(job?.status == .success)
        #expect(storedMessage?.state.sendStatus == .success)
        #expect(storedMessage?.delivery.serverMessageID == "server_retry_success_message")
    }

    @Test func pendingMessageRetryRunnerStopsAtRetryLimit() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "retry_limit_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "retry_limit_conversation", userID: "retry_limit_user", title: "Retry Limit", sortTimestamp: 1)
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "retry_limit_user",
                conversationID: "retry_limit_conversation",
                senderID: "retry_limit_user",
                text: "Give up after limit",
                localTime: 300,
                messageID: "retry_limit_message",
                clientMessageID: "retry_limit_client",
                sortSequence: 300
            )
        )
        try await repository.updateMessageSendStatus(messageID: message.id, status: .failed, ack: nil)
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "message_resend_retry_limit_client",
                userID: "retry_limit_user",
                type: .messageResend,
                bizKey: "retry_limit_client",
                payloadJSON: #"{"messageID":"retry_limit_message","conversationID":"retry_limit_conversation","clientMessageID":"retry_limit_client","lastFailureReason":"timeout"}"#,
                maxRetryCount: 1,
                nextRetryAt: 100
            )
        )
        let runner = PendingMessageRetryRunner(
            userID: "retry_limit_user",
            messageRepository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(result: .failure(.timeout), delayNanoseconds: 0)
        )

        let result = try await runner.runDueJobs(now: 100)
        let job = try await repository.pendingJob(id: "message_resend_retry_limit_client")

        #expect(result.exhaustedCount == 1)
        #expect(job?.status == .failed)
        #expect(job?.retryCount == 1)
    }

    @Test func pendingMessageRetryRunnerRecoversImageUploadJob() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "image_runner_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "image_runner_conversation", userID: "image_runner_user", title: "Image Runner", sortTimestamp: 1)
        )
        let image = StoredImageContent(
            mediaID: "image_runner_media",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image_runner.png").path,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image_runner_thumb.jpg").path,
            width: 64,
            height: 64,
            sizeBytes: 256,
            format: "png"
        )
        let message = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "image_runner_user",
                conversationID: "image_runner_conversation",
                senderID: "image_runner_user",
                image: image,
                localTime: 500,
                messageID: "image_runner_message",
                clientMessageID: "image_runner_client",
                sortSequence: 500
            )
        )
        try await repository.updateImageUploadStatus(
            messageID: message.id,
            uploadStatus: .failed,
            uploadAck: nil,
            sendStatus: .failed,
            sendAck: nil,
            pendingJob: nil
        )
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "image_upload_image_runner_client",
                userID: "image_runner_user",
                type: .imageUpload,
                bizKey: "image_runner_client",
                payloadJSON: #"{"messageID":"image_runner_message","conversationID":"image_runner_conversation","clientMessageID":"image_runner_client","mediaID":"image_runner_media","lastFailureReason":"offline"}"#,
                maxRetryCount: 3,
                nextRetryAt: 100
            )
        )
        let runner = PendingMessageRetryRunner(
            userID: "image_runner_user",
            messageRepository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaUploadService: MockMediaUploadService(progressSteps: [1.0], delayNanoseconds: 0)
        )

        let result = try await runner.runDueJobs(now: 100)
        let job = try await repository.pendingJob(id: "image_upload_image_runner_client")
        let storedMessage = try await repository.message(messageID: message.id)

        #expect(result.successCount == 1)
        #expect(job?.status == .success)
        let storedImage = try requireImageContent(storedMessage)
        #expect(storedMessage?.state.sendStatus == .success)
        #expect(storedImage.uploadStatus == .success)
        #expect(storedImage.remoteURL?.contains("mock-cdn.chatbridge.local") == true)
    }

    @Test func pendingMessageRetryRunnerRecoversVideoUploadJob() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "video_runner_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "video_runner_conversation", userID: "video_runner_user", title: "Video Runner", sortTimestamp: 1)
        )
        let video = StoredVideoContent(
            mediaID: "video_runner_media",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("video_runner.mov").path,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("video_runner_thumb.jpg").path,
            durationMilliseconds: 1_000,
            width: 64,
            height: 64,
            sizeBytes: 512
        )
        let message = try await repository.insertOutgoingVideoMessage(
            OutgoingVideoMessageInput(
                userID: "video_runner_user",
                conversationID: "video_runner_conversation",
                senderID: "video_runner_user",
                video: video,
                localTime: 520,
                messageID: "video_runner_message",
                clientMessageID: "video_runner_client",
                sortSequence: 520
            )
        )
        try await repository.updateVideoUploadStatus(
            messageID: message.id,
            uploadStatus: .failed,
            uploadAck: nil,
            sendStatus: .failed,
            sendAck: nil,
            pendingJob: nil
        )
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "video_upload_video_runner_client",
                userID: "video_runner_user",
                type: .videoUpload,
                bizKey: "video_runner_client",
                payloadJSON: #"{"messageID":"video_runner_message","conversationID":"video_runner_conversation","clientMessageID":"video_runner_client","mediaID":"video_runner_media","lastFailureReason":"offline"}"#,
                maxRetryCount: 3,
                nextRetryAt: 100
            )
        )
        let runner = PendingMessageRetryRunner(
            userID: "video_runner_user",
            messageRepository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaUploadService: MockMediaUploadService(progressSteps: [1.0], delayNanoseconds: 0)
        )

        let result = try await runner.runDueJobs(now: 100)
        let job = try await repository.pendingJob(id: "video_upload_video_runner_client")
        let storedMessage = try await repository.message(messageID: message.id)

        #expect(result.successCount == 1)
        #expect(job?.status == .success)
        let storedVideo = try requireVideoContent(storedMessage)
        #expect(storedMessage?.state.sendStatus == .success)
        #expect(storedVideo.uploadStatus == .success)
        #expect(storedVideo.remoteURL?.contains("mock-cdn.chatbridge.local/video") == true)
    }

    @Test func pendingMessageRetryRunnerStopsImageUploadAtRetryLimit() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "image_limit_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "image_limit_conversation", userID: "image_limit_user", title: "Image Limit", sortTimestamp: 1)
        )
        let image = StoredImageContent(
            mediaID: "image_limit_media",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image_limit.png").path,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("image_limit_thumb.jpg").path,
            width: 64,
            height: 64,
            sizeBytes: 256,
            format: "png"
        )
        let message = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "image_limit_user",
                conversationID: "image_limit_conversation",
                senderID: "image_limit_user",
                image: image,
                localTime: 600,
                messageID: "image_limit_message",
                clientMessageID: "image_limit_client",
                sortSequence: 600
            )
        )
        try await repository.updateImageUploadStatus(
            messageID: message.id,
            uploadStatus: .failed,
            uploadAck: nil,
            sendStatus: .failed,
            sendAck: nil,
            pendingJob: nil
        )
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "image_upload_image_limit_client",
                userID: "image_limit_user",
                type: .imageUpload,
                bizKey: "image_limit_client",
                payloadJSON: #"{"messageID":"image_limit_message","conversationID":"image_limit_conversation","clientMessageID":"image_limit_client","mediaID":"image_limit_media","lastFailureReason":"timeout"}"#,
                maxRetryCount: 1,
                nextRetryAt: 100
            )
        )
        let runner = PendingMessageRetryRunner(
            userID: "image_limit_user",
            messageRepository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaUploadService: MockMediaUploadService(result: .failed(.timeout), progressSteps: [0.5], delayNanoseconds: 0)
        )

        let result = try await runner.runDueJobs(now: 100)
        let job = try await repository.pendingJob(id: "image_upload_image_limit_client")
        let storedMessage = try await repository.message(messageID: message.id)

        #expect(result.exhaustedCount == 1)
        #expect(job?.status == .failed)
        #expect(job?.retryCount == 1)
        #expect(storedMessage?.state.sendStatus == .failed)
        #expect(try requireImageContent(storedMessage).uploadStatus == .failed)
    }

    @Test func crashRecoveryRestoresSendingTextMessageAsPendingJob() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "crash_text_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "crash_text_conversation", userID: "crash_text_user", title: "Crash Text", sortTimestamp: 1)
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "crash_text_user",
                conversationID: "crash_text_conversation",
                senderID: "crash_text_user",
                text: "Recover me after restart",
                localTime: 700,
                messageID: "crash_text_message",
                clientMessageID: "crash_text_client",
                sortSequence: 700
            )
        )

        let result = try await repository.recoverInterruptedOutgoingMessages(
            userID: "crash_text_user",
            retryPolicy: MessageRetryPolicy(initialDelaySeconds: 10, maxDelaySeconds: 60, maxRetryCount: 4),
            now: 1_000
        )
        let storedMessage = try await repository.message(messageID: message.id)
        let job = try await repository.pendingJob(id: "message_resend_crash_text_client")

        #expect(result == MessageCrashRecoveryResult(scannedMessageCount: 1, recoveredMessageCount: 1, pendingJobCount: 1, failedMessageCount: 0))
        #expect(storedMessage?.state.sendStatus == .pending)
        #expect(job?.status == .pending)
        #expect(job?.type == .messageResend)
        #expect(job?.bizKey == "crash_text_client")
        #expect(job?.maxRetryCount == 4)
        #expect(job?.nextRetryAt == 1_000)
        #expect(job?.payloadJSON.contains("ackMissing") == true)
    }

    @Test func crashRecoveryRestoresSendingImageMessageAsUploadJob() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "crash_image_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "crash_image_conversation", userID: "crash_image_user", title: "Crash Image", sortTimestamp: 1)
        )
        let image = StoredImageContent(
            mediaID: "crash_image_media",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("crash_image.png").path,
            thumbnailPath: databaseContext.paths.mediaDirectory.appendingPathComponent("crash_image_thumb.jpg").path,
            width: 64,
            height: 64,
            sizeBytes: 256,
            format: "png"
        )
        let message = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: "crash_image_user",
                conversationID: "crash_image_conversation",
                senderID: "crash_image_user",
                image: image,
                localTime: 800,
                messageID: "crash_image_message",
                clientMessageID: "crash_image_client",
                sortSequence: 800
            )
        )
        try await repository.updateImageUploadStatus(
            messageID: message.id,
            uploadStatus: .uploading,
            uploadAck: nil,
            sendStatus: .sending,
            sendAck: nil,
            pendingJob: nil
        )

        let result = try await repository.recoverInterruptedOutgoingMessages(
            userID: "crash_image_user",
            retryPolicy: MessageRetryPolicy(maxRetryCount: 5),
            now: 1_100
        )
        let storedMessage = try await repository.message(messageID: message.id)
        let job = try await repository.pendingJob(id: "image_upload_crash_image_client")
        let mediaRows = try await databaseContext.databaseActor.query(
            "SELECT upload_status FROM media_resource WHERE media_id = ? LIMIT 1;",
            parameters: [.text("crash_image_media")],
            paths: databaseContext.paths
        )

        #expect(result == MessageCrashRecoveryResult(scannedMessageCount: 1, recoveredMessageCount: 1, pendingJobCount: 1, failedMessageCount: 0))
        #expect(storedMessage?.state.sendStatus == .pending)
        #expect(try requireImageContent(storedMessage).uploadStatus == .pending)
        #expect(mediaRows.first?.int("upload_status") == MediaUploadStatus.pending.rawValue)
        #expect(job?.status == .pending)
        #expect(job?.type == .imageUpload)
        #expect(job?.bizKey == "crash_image_client")
        #expect(job?.nextRetryAt == 1_100)
        #expect(job?.payloadJSON.contains("interrupted") == true)
    }

    @Test func crashRecoveryIsIdempotentAndPreservesTerminalJobs() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "crash_idempotent_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "crash_idempotent_conversation", userID: "crash_idempotent_user", title: "Crash Idempotent", sortTimestamp: 1)
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "crash_idempotent_user",
                conversationID: "crash_idempotent_conversation",
                senderID: "crash_idempotent_user",
                text: "Do not duplicate",
                localTime: 900,
                messageID: "crash_idempotent_message",
                clientMessageID: "crash_idempotent_client",
                sortSequence: 900
            )
        )
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "message_resend_crash_idempotent_client",
                userID: "crash_idempotent_user",
                type: .messageResend,
                bizKey: "crash_idempotent_client",
                payloadJSON: #"{"terminal":true}"#,
                maxRetryCount: 1,
                nextRetryAt: 123
            )
        )
        try await repository.updatePendingJobStatus(
            jobID: "message_resend_crash_idempotent_client",
            status: .success,
            nextRetryAt: nil
        )

        let firstResult = try await repository.recoverInterruptedOutgoingMessages(
            userID: "crash_idempotent_user",
            retryPolicy: MessageRetryPolicy(maxRetryCount: 5),
            now: 1_200
        )
        let secondResult = try await repository.recoverInterruptedOutgoingMessages(
            userID: "crash_idempotent_user",
            retryPolicy: MessageRetryPolicy(maxRetryCount: 5),
            now: 1_300
        )
        let storedMessage = try await repository.message(messageID: message.id)
        let job = try await repository.pendingJob(id: "message_resend_crash_idempotent_client")
        let countRows = try await databaseContext.databaseActor.query(
            "SELECT COUNT(*) AS job_count FROM pending_job WHERE job_id = ?;",
            parameters: [.text("message_resend_crash_idempotent_client")],
            paths: databaseContext.paths
        )

        #expect(firstResult == MessageCrashRecoveryResult(scannedMessageCount: 1, recoveredMessageCount: 1, pendingJobCount: 1, failedMessageCount: 0))
        #expect(secondResult == MessageCrashRecoveryResult(scannedMessageCount: 0, recoveredMessageCount: 0, pendingJobCount: 0, failedMessageCount: 0))
        #expect(storedMessage?.state.sendStatus == .pending)
        #expect(job?.status == .success)
        #expect(job?.payloadJSON == #"{"terminal":true}"#)
        #expect(job?.maxRetryCount == 1)
        #expect(countRows.first?.int("job_count") == 1)
    }

    @MainActor
    @Test func networkRecoveryCoordinatorRecoversInterruptedMessagesBeforeRetrying() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "network_crash_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(id: "network_crash_conversation", userID: "network_crash_user", title: "Network Crash", sortTimestamp: 1)
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "network_crash_user",
                conversationID: "network_crash_conversation",
                senderID: "network_crash_user",
                text: "Recover then retry",
                localTime: 950,
                messageID: "network_crash_message",
                clientMessageID: "network_crash_client",
                sortSequence: 950
            )
        )
        let monitor = TestNetworkConnectivityMonitor(isReachable: false)
        let coordinator = NetworkRecoveryCoordinator(
            userID: "network_crash_user",
            storeProvider: storeProvider,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            monitor: monitor
        )

        coordinator.start()
        monitor.setReachable(true)
        try await waitForCondition {
            let job = try await repository.pendingJob(id: "message_resend_network_crash_client")
            return job?.status == .success
        }
        coordinator.stop()

        let storedMessage = try await repository.message(messageID: message.id)

        #expect(storedMessage?.state.sendStatus == .success)
        #expect(storedMessage?.delivery.serverMessageID == "server_network_crash_message")
        #expect(coordinator.lastCrashRecoveryResult?.recoveredMessageCount == 1)
        #expect(coordinator.lastRunResult?.successCount == 1)
    }

    @MainActor
    @Test func networkRecoveryCoordinatorRunsPendingJobsWhenNetworkRecovers() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "network_recovery_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let repository = try await storeProvider.repository()
        try await repository.upsertConversation(
            makeConversationRecord(id: "network_recovery_conversation", userID: "network_recovery_user", title: "Network", sortTimestamp: 1)
        )
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "network_recovery_user",
                conversationID: "network_recovery_conversation",
                senderID: "network_recovery_user",
                text: "Recover when online",
                localTime: 400,
                messageID: "network_recovery_message",
                clientMessageID: "network_recovery_client",
                sortSequence: 400
            )
        )
        try await repository.updateMessageSendStatus(messageID: message.id, status: .failed, ack: nil)
        _ = try await repository.upsertPendingJob(
            PendingJobInput(
                id: "message_resend_network_recovery_client",
                userID: "network_recovery_user",
                type: .messageResend,
                bizKey: "network_recovery_client",
                payloadJSON: #"{"messageID":"network_recovery_message","conversationID":"network_recovery_conversation","clientMessageID":"network_recovery_client","lastFailureReason":"offline"}"#,
                nextRetryAt: 1
            )
        )
        let monitor = TestNetworkConnectivityMonitor(isReachable: false)
        let coordinator = NetworkRecoveryCoordinator(
            userID: "network_recovery_user",
            storeProvider: storeProvider,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            monitor: monitor
        )

        coordinator.start()
        monitor.setReachable(true)
        try await waitForCondition {
            let job = try await repository.pendingJob(id: "message_resend_network_recovery_client")
            return job?.status == .success
        }
        coordinator.stop()

        let storedMessage = try await repository.message(messageID: message.id)

        #expect(storedMessage?.state.sendStatus == .success)
        #expect(storedMessage?.delivery.serverMessageID == "server_network_recovery_message")
        #expect(coordinator.lastRunResult?.successCount == 1)
    }

    @Test func repositoryDeletesMessageAndRefreshesConversationSummary() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "delete_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "delete_conversation", userID: "delete_user", title: "Delete", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "delete_user",
                conversationID: "delete_conversation",
                senderID: "delete_user",
                text: "First visible",
                localTime: 100,
                messageID: "delete_first",
                clientMessageID: "delete_first_client",
                sortSequence: 100
            )
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "delete_user",
                conversationID: "delete_conversation",
                senderID: "delete_user",
                text: "Delete me",
                localTime: 200,
                messageID: "delete_second",
                clientMessageID: "delete_second_client",
                sortSequence: 200
            )
        )

        try await repository.markMessageDeleted(messageID: "delete_second", userID: "delete_user")

        let messages = try await repository.listMessages(conversationID: "delete_conversation", limit: 20, beforeSortSeq: nil)
        let conversations = try await repository.listConversations(for: "delete_user")

        #expect(messages.map(\.id.rawValue) == ["delete_first"])
        #expect(conversations.first?.lastMessageDigest == "First visible")
    }

    @Test func repositoryRevokesMessageAndPersistsReplacementText() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "revoke_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "revoke_conversation", userID: "revoke_user", title: "Revoke", sortTimestamp: 1)
        )
        _ = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: "revoke_user",
                conversationID: "revoke_conversation",
                senderID: "revoke_user",
                text: "Secret",
                localTime: 300,
                messageID: "revoke_message",
                clientMessageID: "revoke_client",
                sortSequence: 300
            )
        )

        let revokedMessage = try await repository.revokeMessage(
            messageID: "revoke_message",
            userID: "revoke_user",
            replacementText: "你撤回了一条消息"
        )
        let reloadedMessage = try await repository.message(messageID: "revoke_message")!
        let conversations = try await repository.listConversations(for: "revoke_user")

        #expect(revokedMessage.state.isRevoked)
        #expect(reloadedMessage.state.isRevoked)
        #expect(reloadedMessage.state.revokeReplacementText == "你撤回了一条消息")
        #expect(conversations.first?.lastMessageDigest == "你撤回了一条消息")
    }

    @Test func draftIsPersistedAndPrioritizedInConversationList() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "ui_test_user",
            storageService: storageService,
            database: DatabaseActor()
        )
        let repository = try await storeProvider.repository()
        try await repository.saveDraft(
            conversationID: "system_release",
            userID: "ui_test_user",
            text: "Remember this"
        )

        let draftText = try await repository.draft(conversationID: "system_release", userID: "ui_test_user")
        let rows = try await LocalConversationListUseCase(
            userID: "ui_test_user",
            storeProvider: storeProvider
        ).loadConversations()
        let draftRowIndex = rows.firstIndex { $0.id == "system_release" }
        let otherUnpinnedRowIndex = rows.firstIndex { $0.id == "group_core" }

        #expect(draftText == "Remember this")
        #expect(draftRowIndex != nil)
        #expect(otherUnpinnedRowIndex != nil)
        #expect((draftRowIndex ?? 0) < (otherUnpinnedRowIndex ?? 0))
        #expect(rows[draftRowIndex ?? 0].subtitle == "Draft: Remember this")

        try await repository.clearDraft(conversationID: "system_release", userID: "ui_test_user")
        #expect(try await repository.draft(conversationID: "system_release", userID: "ui_test_user") == nil)
    }

    @Test func chatUseCaseMarksConversationReadWhenLoadingMessages() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: "read_user")
        try await repository.upsertConversation(
            makeConversationRecord(
                id: "read_conversation",
                userID: "read_user",
                title: "Read",
                unreadCount: 3,
                sortTimestamp: 1
            )
        )

        let useCase = LocalChatUseCase(
            userID: "read_user",
            conversationID: "read_conversation",
            repository: repository,
            conversationRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        _ = try await useCase.loadInitialMessages()
        let conversations = try await repository.listConversations(for: "read_user")

        #expect(conversations.first?.unreadCount == 0)
    }

    @Test func chatUseCaseMarksIncomingVoicePlayedAndClearsUnreadDot() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "voice_dot_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "voice_dot_conversation", userID: "voice_dot_user", title: "Voice Dot", sortTimestamp: 1)
        )
        let voice = StoredVoiceContent(
            mediaID: "media_voice_dot",
            localPath: databaseContext.paths.mediaDirectory.appendingPathComponent("voice/media_voice_dot.m4a").path,
            durationMilliseconds: 2_100,
            sizeBytes: 512,
            format: "m4a"
        )
        let insertedMessage = try await repository.insertOutgoingVoiceMessage(
            OutgoingVoiceMessageInput(
                userID: "voice_dot_user",
                conversationID: "voice_dot_conversation",
                senderID: "friend_user",
                voice: voice,
                localTime: 530,
                messageID: "voice_dot_message",
                clientMessageID: "voice_dot_client",
                sortSequence: 530
            )
        )
        try await databaseContext.databaseActor.execute(
            "UPDATE message SET read_status = ? WHERE message_id = ?;",
            parameters: [
                .integer(Int64(MessageReadStatus.unread.rawValue)),
                .text(insertedMessage.id.rawValue)
            ],
            paths: databaseContext.paths
        )

        let useCase = LocalChatUseCase(
            userID: "voice_dot_user",
            conversationID: "voice_dot_conversation",
            repository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        let initialPage = try await useCase.loadInitialMessages()
        let playedRow = try await useCase.markVoicePlayed(messageID: insertedMessage.id)
        let storedMessage = try await repository.message(messageID: insertedMessage.id)

        #expect(initialPage.rows.first.map(isUnplayedVoiceContent) == true)
        #expect(initialPage.rows.first.flatMap(voiceLocalPath) == voice.localPath)
        #expect(playedRow.map(isUnplayedVoiceContent) == false)
        #expect(storedMessage?.state.readStatus == .read)
    }
}
