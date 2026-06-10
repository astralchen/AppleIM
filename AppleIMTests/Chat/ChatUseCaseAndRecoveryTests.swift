import Testing
import Foundation
import GRDB
import UIKit

@testable import AppleIM

extension AppleIMTests {
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
        let mediaUploadStatus = try await databaseContext.databaseActor.read(paths: databaseContext.paths) { db in
            try Int.fetchOne(
                db,
                sql: "SELECT upload_status FROM media_resource WHERE media_id = ? LIMIT 1;",
                arguments: ["crash_image_media"]
            )
        }

        #expect(result == MessageCrashRecoveryResult(scannedMessageCount: 1, recoveredMessageCount: 1, pendingJobCount: 1, failedMessageCount: 0))
        #expect(storedMessage?.state.sendStatus == .pending)
        #expect(try requireImageContent(storedMessage).uploadStatus == .pending)
        #expect(mediaUploadStatus == MediaUploadStatus.pending.rawValue)
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
        let jobCount = try await databaseContext.databaseActor.read(paths: databaseContext.paths) { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM pending_job WHERE job_id = ?;",
                arguments: ["message_resend_crash_idempotent_client"]
            ) ?? 0
        }

        #expect(firstResult == MessageCrashRecoveryResult(scannedMessageCount: 1, recoveredMessageCount: 1, pendingJobCount: 1, failedMessageCount: 0))
        #expect(secondResult == MessageCrashRecoveryResult(scannedMessageCount: 0, recoveredMessageCount: 0, pendingJobCount: 0, failedMessageCount: 0))
        #expect(storedMessage?.state.sendStatus == .pending)
        #expect(job?.status == .success)
        #expect(job?.payloadJSON == #"{"terminal":true}"#)
        #expect(job?.maxRetryCount == 1)
        #expect(jobCount == 1)
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
        let repository = (try await storeProvider.accountStore()).dataRepairRepository
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
        let repository = (try await storeProvider.accountStore()).dataRepairRepository
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
        #expect(reloadedMessage.state.revokeEditableText == "Secret")
        #expect(conversations.first?.lastMessageDigest == "你撤回了一条消息")
    }

    @Test func chatUseCaseLoadsRevokedTextMessageWithReeditPayload() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, databaseContext) = try await makeRepository(rootDirectory: rootDirectory, accountID: "reedit_user")
        try await repository.upsertConversation(
            makeConversationRecord(id: "reedit_conversation", userID: "reedit_user", title: "Reedit", sortTimestamp: 1)
        )
        let mediaFileActor = await MediaFileActor(paths: databaseContext.paths)
        let useCase = LocalChatUseCase(
            userID: "reedit_user",
            conversationID: "reedit_conversation",
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0),
            mediaFileStore: mediaFileActor,
            mediaUploadService: MockMediaUploadService(progressSteps: [1.0], delayNanoseconds: 0)
        )

        let sentRows = try await collectRows(from: useCase.sendText("需要重新编辑"))
        let messageID = try #require(sentRows.first?.id)
        try await useCase.revoke(messageID: messageID)
        let page = try await useCase.loadInitialMessages()
        let revokedContent = try #require(page.rows.first?.content.revokedContent)

        #expect(revokedContent.noticeText == "你撤回了一条消息")
        #expect(revokedContent.editableText == "需要重新编辑")
        #expect(revokedContent.allowsReedit)
    }

    @Test func chatUseCaseAllowsAllSuccessfulOutgoingUserMessagesToRevokeWithinThreeMinutes() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, useCase) = try await makeRevokeEligibilityUseCase(
            rootDirectory: rootDirectory,
            userID: "revoke_window_user",
            conversationID: "revoke_window_conversation"
        )
        let now = Int64(Date().timeIntervalSince1970)
        let insertedIDs = try await insertSuccessfulOutgoingUserMessages(
            into: repository,
            userID: "revoke_window_user",
            conversationID: "revoke_window_conversation",
            localTime: now - 60
        )

        let rows = try await useCase.loadInitialMessages().rows
        let canRevokeByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.canRevoke) })

        for messageID in insertedIDs {
            #expect(canRevokeByID[messageID] == true)
        }
    }

    @Test func chatUseCaseRejectsRevokeOutsideWindowOrForNonEligibleMessages() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let (repository, useCase) = try await makeRevokeEligibilityUseCase(
            rootDirectory: rootDirectory,
            userID: "revoke_reject_user",
            conversationID: "revoke_reject_conversation"
        )
        let now = Int64(Date().timeIntervalSince1970)
        let oldText = try await insertOutgoingText(
            into: repository,
            userID: "revoke_reject_user",
            conversationID: "revoke_reject_conversation",
            senderID: "revoke_reject_user",
            messageID: "old_text",
            text: "超过三分钟",
            localTime: now - 181,
            status: .success
        )
        let incomingText = try await insertOutgoingText(
            into: repository,
            userID: "revoke_reject_user",
            conversationID: "revoke_reject_conversation",
            senderID: "peer_user",
            messageID: "incoming_text",
            text: "对方消息",
            localTime: now - 60,
            status: .success
        )
        let failedText = try await insertOutgoingText(
            into: repository,
            userID: "revoke_reject_user",
            conversationID: "revoke_reject_conversation",
            senderID: "revoke_reject_user",
            messageID: "failed_text",
            text: "发送失败",
            localTime: now - 60,
            status: .failed
        )
        let sendingText = try await insertOutgoingText(
            into: repository,
            userID: "revoke_reject_user",
            conversationID: "revoke_reject_conversation",
            senderID: "revoke_reject_user",
            messageID: "sending_text",
            text: "发送中",
            localTime: now - 60,
            status: nil
        )
        let revokedText = try await insertOutgoingText(
            into: repository,
            userID: "revoke_reject_user",
            conversationID: "revoke_reject_conversation",
            senderID: "revoke_reject_user",
            messageID: "revoked_text",
            text: "已撤回",
            localTime: now - 60,
            status: .success
        )
        _ = try await repository.revokeMessage(
            messageID: revokedText,
            userID: "revoke_reject_user",
            replacementText: "你撤回了一条消息"
        )

        let rows = try await useCase.loadInitialMessages().rows
        let canRevokeByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.canRevoke) })

        for messageID in [oldText, incomingText, failedText, sendingText, revokedText] {
            #expect(canRevokeByID[messageID] == false)
        }
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
        let repository = (try await storeProvider.accountStore()).dataRepairRepository
        try await repository.saveDraft(
            conversationID: "system_release",
            userID: "ui_test_user",
            text: "Remember this"
        )

        let draftText = try await repository.draft(conversationID: "system_release", userID: "ui_test_user")
        let rows = try await LocalConversationListService(
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
        _ = try await databaseContext.databaseActor.write(paths: databaseContext.paths) { db in
            try db.execute(
                sql: "UPDATE message SET read_status = ? WHERE message_id = ?;",
                arguments: [MessageReadStatus.unread.rawValue, insertedMessage.id.rawValue]
            )
        }

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

    private func makeRevokeEligibilityUseCase(
        rootDirectory: URL,
        userID: UserID,
        conversationID: ConversationID
    ) async throws -> (LocalChatRepository, LocalChatUseCase) {
        let (repository, _) = try await makeRepository(rootDirectory: rootDirectory, accountID: userID)
        try await repository.upsertConversation(
            makeConversationRecord(id: conversationID, userID: userID, title: "Revoke Eligibility", sortTimestamp: 1)
        )
        let useCase = LocalChatUseCase(
            userID: userID,
            conversationID: conversationID,
            repository: repository,
            pendingJobRepository: repository,
            sendService: MockMessageSendService(delayNanoseconds: 0)
        )
        return (repository, useCase)
    }

    private func insertSuccessfulOutgoingUserMessages(
        into repository: LocalChatRepository,
        userID: UserID,
        conversationID: ConversationID,
        localTime: Int64
    ) async throws -> [MessageID] {
        var messageIDs: [MessageID] = []

        messageIDs.append(
            try await insertOutgoingText(
                into: repository,
                userID: userID,
                conversationID: conversationID,
                senderID: userID,
                messageID: "revoke_text",
                text: "文本",
                localTime: localTime,
                status: .success
            )
        )

        let imageMessage = try await repository.insertOutgoingImageMessage(
            OutgoingImageMessageInput(
                userID: userID,
                conversationID: conversationID,
                senderID: userID,
                image: StoredImageContent(
                    mediaID: "revoke_image_media",
                    localPath: "media/revoke_image.png",
                    thumbnailPath: "media/revoke_image_thumb.jpg",
                    width: 320,
                    height: 240,
                    sizeBytes: 4_096,
                    format: "png"
                ),
                localTime: localTime,
                messageID: "revoke_image",
                clientMessageID: "revoke_image_client",
                sortSequence: localTime + 1
            )
        )
        try await markMessageSendStatus(repository, messageID: imageMessage.id, status: .success, serverTime: localTime + 1)
        messageIDs.append(imageMessage.id)

        let voiceMessage = try await repository.insertOutgoingVoiceMessage(
            OutgoingVoiceMessageInput(
                userID: userID,
                conversationID: conversationID,
                senderID: userID,
                voice: StoredVoiceContent(
                    mediaID: "revoke_voice_media",
                    localPath: "media/revoke_voice.m4a",
                    durationMilliseconds: 1_800,
                    sizeBytes: 2_048,
                    format: "m4a"
                ),
                localTime: localTime,
                messageID: "revoke_voice",
                clientMessageID: "revoke_voice_client",
                sortSequence: localTime + 2
            )
        )
        try await markMessageSendStatus(repository, messageID: voiceMessage.id, status: .success, serverTime: localTime + 2)
        messageIDs.append(voiceMessage.id)

        let videoMessage = try await repository.insertOutgoingVideoMessage(
            OutgoingVideoMessageInput(
                userID: userID,
                conversationID: conversationID,
                senderID: userID,
                video: StoredVideoContent(
                    mediaID: "revoke_video_media",
                    localPath: "media/revoke_video.mov",
                    thumbnailPath: "media/revoke_video_thumb.jpg",
                    durationMilliseconds: 3_600,
                    width: 640,
                    height: 360,
                    sizeBytes: 8_192
                ),
                localTime: localTime,
                messageID: "revoke_video",
                clientMessageID: "revoke_video_client",
                sortSequence: localTime + 3
            )
        )
        try await markMessageSendStatus(repository, messageID: videoMessage.id, status: .success, serverTime: localTime + 3)
        messageIDs.append(videoMessage.id)

        let fileMessage = try await repository.insertOutgoingFileMessage(
            OutgoingFileMessageInput(
                userID: userID,
                conversationID: conversationID,
                senderID: userID,
                file: StoredFileContent(
                    mediaID: "revoke_file_media",
                    localPath: "media/revoke_file.pdf",
                    fileName: "revoke.pdf",
                    fileExtension: "pdf",
                    sizeBytes: 16_384
                ),
                localTime: localTime,
                messageID: "revoke_file",
                clientMessageID: "revoke_file_client",
                sortSequence: localTime + 4
            )
        )
        try await markMessageSendStatus(repository, messageID: fileMessage.id, status: .success, serverTime: localTime + 4)
        messageIDs.append(fileMessage.id)

        let emojiMessage = try await repository.insertOutgoingEmojiMessage(
            OutgoingEmojiMessageInput(
                userID: userID,
                conversationID: conversationID,
                senderID: userID,
                emoji: StoredEmojiContent(
                    emojiID: "revoke_emoji_asset",
                    packageID: nil,
                    emojiType: .system,
                    name: "Smile",
                    localPath: nil,
                    thumbPath: nil,
                    cdnURL: nil,
                    width: nil,
                    height: nil,
                    sizeBytes: nil
                ),
                localTime: localTime,
                messageID: "revoke_emoji",
                clientMessageID: "revoke_emoji_client",
                sortSequence: localTime + 5
            )
        )
        try await markMessageSendStatus(repository, messageID: emojiMessage.id, status: .success, serverTime: localTime + 5)
        messageIDs.append(emojiMessage.id)

        return messageIDs
    }

    private func insertOutgoingText(
        into repository: LocalChatRepository,
        userID: UserID,
        conversationID: ConversationID,
        senderID: UserID,
        messageID: MessageID,
        text: String,
        localTime: Int64,
        status: MessageSendStatus?
    ) async throws -> MessageID {
        let message = try await repository.insertOutgoingTextMessage(
            OutgoingTextMessageInput(
                userID: userID,
                conversationID: conversationID,
                senderID: senderID,
                text: text,
                localTime: localTime,
                messageID: messageID,
                clientMessageID: "\(messageID.rawValue)_client",
                sortSequence: localTime
            )
        )
        if let status {
            try await markMessageSendStatus(repository, messageID: message.id, status: status, serverTime: localTime)
        }
        return message.id
    }

    private func markMessageSendStatus(
        _ repository: LocalChatRepository,
        messageID: MessageID,
        status: MessageSendStatus,
        serverTime: Int64
    ) async throws {
        let ack = status == .success
            ? MessageSendAck(serverMessageID: "server_\(messageID.rawValue)", sequence: serverTime, serverTime: serverTime)
            : nil
        try await repository.updateMessageSendStatus(messageID: messageID, status: status, ack: ack)
    }
}
