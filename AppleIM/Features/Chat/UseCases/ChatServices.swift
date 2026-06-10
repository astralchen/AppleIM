//
//  ChatServices.swift
//  AppleIM
//
//  聊天页窄服务协议
//

import Foundation

/// 聊天时间线读取服务。
protocol ChatTimelineService: Sendable {
    var observedUserID: UserID? { get }
    var observedConversationID: ConversationID? { get }

    func loadInitialMessages() async throws -> ChatMessagePage
    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage
    func observeLatestMessages(limit: Int) async throws -> DatabaseObservationStream<[ChatMessageRowState]>?
}

/// 聊天草稿服务。
protocol ChatDraftService: Sendable {
    func loadDraft() async throws -> String?
    func saveDraft(_ text: String) async throws
}

/// 聊天消息发送服务。
protocol ChatSendingService: Sendable {
    func sendText(
        _ text: String,
        mentionedUserIDs: [UserID],
        mentionsAll: Bool
    ) -> AsyncThrowingStream<ChatMessageRowState, Error>
    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error>
    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error>
    func sendVideo(fileURL: URL, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error>
    func sendFile(fileURL: URL) -> AsyncThrowingStream<ChatMessageRowState, Error>
}

/// 聊天消息操作服务。
protocol ChatMessageOperationService: Sendable {
    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState?
    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error>
    func delete(messageID: MessageID) async throws
    func revoke(messageID: MessageID) async throws
}

/// 群聊上下文服务。
protocol ChatGroupService: Sendable {
    func loadGroupContext() async throws -> GroupChatContext?
    func updateGroupAnnouncement(_ text: String) async throws -> GroupAnnouncement?
}

/// 聊天表情服务。
protocol ChatEmojiService: Sendable {
    func loadEmojiPanelState() async throws -> ChatEmojiPanelState
    func toggleEmojiFavorite(emojiID: String, isFavorite: Bool) async throws -> ChatEmojiPanelState
    func sendEmoji(_ emoji: EmojiAssetRecord) -> AsyncThrowingStream<ChatMessageRowState, Error>
}

/// 模拟当前会话收到消息的服务。
protocol ChatSimulatedIncomingService: Sendable {
    func simulateIncomingMessages() async throws -> [ChatMessageRowState]
}

/// Store 支撑的聊天窄服务依赖工厂。
nonisolated struct StoreBackedChatServicesFactory: Sendable {
    private let userID: UserID
    private let conversationID: ConversationID
    private let currentUserAvatarURL: String?
    private let conversationAvatarURL: String?
    private let storeProvider: ChatStoreProvider
    private let sendService: any MessageSendService
    private let mediaFileStore: any MediaFileStoring
    private let mediaUploadService: any MediaUploadService
    private let simulatedIncomingPushService: SimulatedIncomingPushService

    init(
        userID: UserID,
        conversationID: ConversationID,
        currentUserAvatarURL: String?,
        conversationAvatarURL: String?,
        storeProvider: ChatStoreProvider,
        sendService: any MessageSendService,
        mediaFileStore: any MediaFileStoring,
        mediaUploadService: any MediaUploadService,
        simulatedIncomingPushService: SimulatedIncomingPushService
    ) {
        self.userID = userID
        self.conversationID = conversationID
        self.currentUserAvatarURL = currentUserAvatarURL
        self.conversationAvatarURL = conversationAvatarURL
        self.storeProvider = storeProvider
        self.sendService = sendService
        self.mediaFileStore = mediaFileStore
        self.mediaUploadService = mediaUploadService
        self.simulatedIncomingPushService = simulatedIncomingPushService
    }

    func makeViewModelDependencies() -> ChatViewModel.Dependencies {
        let useCase = StoreBackedChatServiceHub(
            userID: userID,
            conversationID: conversationID,
            currentUserAvatarURL: currentUserAvatarURL,
            conversationAvatarURL: conversationAvatarURL,
            storeProvider: storeProvider,
            sendService: sendService,
            mediaFileStore: mediaFileStore,
            mediaUploadService: mediaUploadService,
            simulatedIncomingPushService: simulatedIncomingPushService
        )
        let services = ChatServiceHubAdapter(useCase: useCase)
        return ChatViewModel.Dependencies(
            timeline: services,
            draft: services,
            sender: services,
            messageOperations: services,
            group: services,
            emoji: services,
            simulatedIncoming: services
        )
    }
}

/// 旧 `ChatServiceHub` 到窄服务组的适配器。
nonisolated struct ChatServiceHubAdapter:
    ChatTimelineService,
    ChatDraftService,
    ChatSendingService,
    ChatMessageOperationService,
    ChatGroupService,
    ChatEmojiService,
    ChatSimulatedIncomingService
{
    private let useCase: any ChatServiceHub

    init(useCase: any ChatServiceHub) {
        self.useCase = useCase
    }

    var observedUserID: UserID? {
        useCase.observedUserID
    }

    var observedConversationID: ConversationID? {
        useCase.observedConversationID
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        try await useCase.loadInitialMessages()
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        try await useCase.loadOlderMessages(beforeSortSequence: beforeSortSequence, limit: limit)
    }

    func observeLatestMessages(limit: Int) async throws -> DatabaseObservationStream<[ChatMessageRowState]>? {
        try await useCase.observeLatestMessages(limit: limit)
    }

    func loadDraft() async throws -> String? {
        try await useCase.loadDraft()
    }

    func saveDraft(_ text: String) async throws {
        try await useCase.saveDraft(text)
    }

    func sendText(
        _ text: String,
        mentionedUserIDs: [UserID],
        mentionsAll: Bool
    ) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        useCase.sendText(text, mentionedUserIDs: mentionedUserIDs, mentionsAll: mentionsAll)
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        useCase.sendImage(data: data, preferredFileExtension: preferredFileExtension)
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        useCase.sendVoice(recording: recording)
    }

    func sendVideo(fileURL: URL, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        useCase.sendVideo(fileURL: fileURL, preferredFileExtension: preferredFileExtension)
    }

    func sendFile(fileURL: URL) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        useCase.sendFile(fileURL: fileURL)
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        try await useCase.markVoicePlayed(messageID: messageID)
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        useCase.resend(messageID: messageID)
    }

    func delete(messageID: MessageID) async throws {
        try await useCase.delete(messageID: messageID)
    }

    func revoke(messageID: MessageID) async throws {
        try await useCase.revoke(messageID: messageID)
    }

    func loadGroupContext() async throws -> GroupChatContext? {
        try await useCase.loadGroupContext()
    }

    func updateGroupAnnouncement(_ text: String) async throws -> GroupAnnouncement? {
        try await useCase.updateGroupAnnouncement(text)
    }

    func loadEmojiPanelState() async throws -> ChatEmojiPanelState {
        try await useCase.loadEmojiPanelState()
    }

    func toggleEmojiFavorite(emojiID: String, isFavorite: Bool) async throws -> ChatEmojiPanelState {
        try await useCase.toggleEmojiFavorite(emojiID: emojiID, isFavorite: isFavorite)
    }

    func sendEmoji(_ emoji: EmojiAssetRecord) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        useCase.sendEmoji(emoji)
    }

    func simulateIncomingMessages() async throws -> [ChatMessageRowState] {
        try await useCase.simulateIncomingMessages()
    }
}
