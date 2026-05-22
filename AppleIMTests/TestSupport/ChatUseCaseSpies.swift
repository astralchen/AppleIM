import Testing
import AVFoundation
import Combine
import Foundation
import GRDB
import CoreGraphics
import ImageIO
import UIKit
import UniformTypeIdentifiers

@testable import AppleIM

/// 测试专用的线程安全状态盒。
///
/// Sendable 审计：这是本文件唯一允许的测试同步封装。它用 `NSLock` 保护可变状态，
/// 让具体 `ChatUseCase` spy 只持有不可变引用，避免在每个测试替身上重复声明 unchecked。
final class TestLockedBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    var snapshot: Value {
        lock.withLock {
            value
        }
    }

    func set(_ value: Value) {
        lock.withLock {
            self.value = value
        }
    }

    @discardableResult
    func withValue<Result: Sendable>(_ body: (inout Value) -> Result) -> Result {
        lock.withLock {
            body(&value)
        }
    }
}

nonisolated struct DeferredPageState: Sendable {
    var continuation: CheckedContinuation<ChatMessagePage, Error>?
    var isReleased = false
}

struct SlowChatUseCase: ChatUseCase {
    func loadInitialMessages() async throws -> ChatMessagePage {
        try await Task.sleep(nanoseconds: 200_000_000)
        return ChatMessagePage(
            rows: [
                makeChatRow(id: "slow_message", text: "Too late", sortSequence: 1)
            ],
            hasMore: false,
            nextBeforeSortSequence: 1
        )
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

final class StoreRefreshingChatUseCase: ChatUseCase {
    let observedUserID: UserID? = "store_refresh_user"
    let observedConversationID: ConversationID? = "store_refresh_conversation"
    private let rowsBox = TestLockedBox<[ChatMessageRowState]>([])
    private let loadInitialMessagesCallCountBox = TestLockedBox(0)

    var loadInitialMessagesCallCount: Int {
        loadInitialMessagesCallCountBox.snapshot
    }

    func replaceRows(_ rows: [ChatMessageRowState]) {
        rowsBox.set(rows)
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        loadInitialMessagesCallCountBox.withValue { $0 += 1 }
        let rows = rowsBox.snapshot
        return ChatMessagePage(rows: rows, hasMore: false, nextBeforeSortSequence: rows.first?.sortSequence)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

final class SimulatedIncomingStubChatUseCase: ChatUseCase {
    private let initialRows: [ChatMessageRowState]
    private let simulatedRows: [ChatMessageRowState]
    private let simulateIncomingCallCountBox = TestLockedBox(0)

    var simulateIncomingCallCount: Int {
        simulateIncomingCallCountBox.snapshot
    }

    init(
        initialRows: [ChatMessageRowState] = [],
        simulatedRows: [ChatMessageRowState]? = nil
    ) {
        self.initialRows = initialRows
        self.simulatedRows = simulatedRows ?? [
            ChatMessageRowState(
                id: "simulated_incoming_stub_1",
                content: .text("模拟收到第 1 条后台推送"),
                sortSequence: 1,
                timeText: "Now",
                statusText: nil,
                uploadProgress: nil,
                isOutgoing: false,
                canRetry: false,
                canDelete: true,
                canRevoke: false
            ),
            ChatMessageRowState(
                id: "simulated_incoming_stub_2",
                content: .text("模拟收到第 2 条后台推送"),
                sortSequence: 2,
                timeText: "Now",
                statusText: nil,
                uploadProgress: nil,
                isOutgoing: false,
                canRetry: false,
                canDelete: true,
                canRevoke: false
            )
        ]
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: initialRows, hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func simulateIncomingMessages() async throws -> [ChatMessageRowState] {
        simulateIncomingCallCountBox.withValue { $0 += 1 }
        return simulatedRows
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

actor CapturingSimulatedIncomingPusher: SimulatedIncomingPushing {
    private let result: SimulatedIncomingPushResult?
    private(set) var requests: [SimulatedIncomingPushRequest] = []

    init(result: SimulatedIncomingPushResult?) {
        self.result = result
    }

    func simulateIncomingPush(
        _ request: SimulatedIncomingPushRequest = SimulatedIncomingPushRequest()
    ) async throws -> SimulatedIncomingPushResult? {
        requests.append(request)
        return result
    }
}

final class MissedSimulatedIncomingStubChatUseCase: ChatUseCase {
    private let simulateIncomingCallCountBox = TestLockedBox(0)

    var simulateIncomingCallCount: Int {
        simulateIncomingCallCountBox.snapshot
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func simulateIncomingMessages() async throws -> [ChatMessageRowState] {
        simulateIncomingCallCountBox.withValue { $0 += 1 }
        return []
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

final class DelayedSimulatedIncomingStubChatUseCase: ChatUseCase {
    private let simulateIncomingCallCountBox = TestLockedBox(0)

    var simulateIncomingCallCount: Int {
        simulateIncomingCallCountBox.snapshot
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func simulateIncomingMessages() async throws -> [ChatMessageRowState] {
        let callCount = simulateIncomingCallCountBox.withValue { count in
            count += 1
            return count
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        return [ChatMessageRowState(
            id: MessageID(rawValue: "simulated_incoming_delayed_\(callCount)"),
            content: .text("模拟收到第 \(callCount) 条消息"),
            sortSequence: Int64(callCount),
            timeText: "Now",
            statusText: nil,
            uploadProgress: nil,
            isOutgoing: false,
            canRetry: false,
            canDelete: true,
            canRevoke: false
        )]
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

final class DelayedTextSendingStubChatUseCase: ChatUseCase {
    private let sentTextsBox = TestLockedBox<[String]>([])

    var sentTexts: [String] {
        sentTextsBox.snapshot
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        let sortSequence = sentTextsBox.withValue { sentTexts in
            sentTexts.append(text)
            return Int64(sentTexts.count)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Task.sleep(nanoseconds: 30_000_000)
                    continuation.yield(
                        makeChatRow(
                            id: MessageID(rawValue: "delayed_text_send_\(sortSequence)"),
                            text: text,
                            sortSequence: sortSequence
                        )
                    )
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

final class PagingStubChatUseCase: ChatUseCase {
    private let initialPage: ChatMessagePage
    private let olderPage: ChatMessagePage
    private let olderError: TestChatError?
    private let loadOlderCallCountBox = TestLockedBox(0)

    var loadOlderCallCount: Int {
        loadOlderCallCountBox.snapshot
    }

    init(initialPage: ChatMessagePage, olderPage: ChatMessagePage, olderError: TestChatError? = nil) {
        self.initialPage = initialPage
        self.olderPage = olderPage
        self.olderError = olderError
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        initialPage
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        loadOlderCallCountBox.withValue { $0 += 1 }

        if let olderError {
            throw olderError
        }

        return olderPage
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

final class DeferredInitialPageStubChatUseCase: ChatUseCase {
    private let initialPage: ChatMessagePage
    private let stateBox = TestLockedBox(DeferredPageState())

    init(initialPage: ChatMessagePage) {
        self.initialPage = initialPage
    }

    func releaseInitialPage() {
        let continuation = stateBox.withValue { state in
            state.isReleased = true
            let continuation = state.continuation
            state.continuation = nil
            return continuation
        }

        continuation?.resume(returning: initialPage)
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        if stateBox.snapshot.isReleased {
            return initialPage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let shouldResume = stateBox.withValue { state in
                if state.isReleased {
                    return true
                }
                state.continuation = continuation
                return false
            }
            if shouldResume {
                continuation.resume(returning: initialPage)
            }
        }
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

final class DeferredOlderPageStubChatUseCase: ChatUseCase {
    private let initialPage: ChatMessagePage
    private let olderPage: ChatMessagePage
    private let stateBox = TestLockedBox(DeferredPageState())
    private let loadOlderCallCountBox = TestLockedBox(0)

    var loadOlderCallCount: Int {
        loadOlderCallCountBox.snapshot
    }

    init(initialPage: ChatMessagePage, olderPage: ChatMessagePage) {
        self.initialPage = initialPage
        self.olderPage = olderPage
    }

    func releaseOlderPage() {
        let continuation = stateBox.withValue { state in
            state.isReleased = true
            let continuation = state.continuation
            state.continuation = nil
            return continuation
        }

        continuation?.resume(returning: olderPage)
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        initialPage
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        loadOlderCallCountBox.withValue { $0 += 1 }
        if stateBox.snapshot.isReleased {
            return olderPage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let shouldResume = stateBox.withValue { state in
                if state.isReleased {
                    return true
                }
                state.continuation = continuation
                return false
            }
            if shouldResume {
                continuation.resume(returning: olderPage)
            }
        }
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

@MainActor
final class GroupContextStubChatUseCase: ChatUseCase {
    private let context: GroupChatContext
    private let draftText: String?
    private let sentTextBox = TestLockedBox<String?>(nil)
    private let sentMentionedUserIDsBox = TestLockedBox<[UserID]>([])
    private let sentMentionsAllBox = TestLockedBox(false)

    var sentText: String? {
        sentTextBox.snapshot
    }

    var sentMentionedUserIDs: [UserID] {
        sentMentionedUserIDsBox.snapshot
    }

    var sentMentionsAll: Bool {
        sentMentionsAllBox.snapshot
    }

    init(context: GroupChatContext, draftText: String? = nil) {
        self.context = context
        self.draftText = draftText
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        draftText
    }

    func saveDraft(_ text: String) async throws {}

    func loadGroupContext() async throws -> GroupChatContext? {
        context
    }

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sendText(text, mentionedUserIDs: [], mentionsAll: false)
    }

    func sendText(_ text: String, mentionedUserIDs: [UserID], mentionsAll: Bool) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sentTextBox.set(text)
        sentMentionedUserIDsBox.set(mentionedUserIDs)
        sentMentionsAllBox.set(mentionsAll)
        return AsyncThrowingStream { continuation in
            continuation.yield(makeChatRow(id: "group_context_sent", text: text, sortSequence: 1))
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVideo(fileURL: URL, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendFile(fileURL: URL) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

final class RecoveringPagingStubChatUseCase: ChatUseCase {
    private let initialPage: ChatMessagePage
    private let recoveredPage: ChatMessagePage
    private let loadOlderCallCountBox = TestLockedBox(0)

    var loadOlderCallCount: Int {
        loadOlderCallCountBox.snapshot
    }

    init(initialPage: ChatMessagePage, recoveredPage: ChatMessagePage) {
        self.initialPage = initialPage
        self.recoveredPage = recoveredPage
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        initialPage
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        let loadOlderCallCount = loadOlderCallCountBox.withValue { count in
            count += 1
            return count
        }

        if loadOlderCallCount == 1 {
            throw TestChatError.paginationFailed
        }

        return recoveredPage
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

final class MessageActionStubChatUseCase: ChatUseCase {
    private let initialRows: [ChatMessageRowState]
    private let revokedRows: [ChatMessageRowState]
    private let deleteError: TestChatError?
    private let revokeError: TestChatError?
    private let didRevokeBox = TestLockedBox(false)
    private let deletedMessageIDsBox = TestLockedBox<[MessageID]>([])
    private let revokedMessageIDsBox = TestLockedBox<[MessageID]>([])

    var deletedMessageIDs: [MessageID] {
        deletedMessageIDsBox.snapshot
    }

    var revokedMessageIDs: [MessageID] {
        revokedMessageIDsBox.snapshot
    }

    init(
        initialRows: [ChatMessageRowState],
        revokedRows: [ChatMessageRowState]? = nil,
        deleteError: TestChatError? = nil,
        revokeError: TestChatError? = nil
    ) {
        self.initialRows = initialRows
        self.revokedRows = revokedRows ?? initialRows
        self.deleteError = deleteError
        self.revokeError = revokeError
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(
            rows: didRevokeBox.snapshot ? revokedRows : initialRows,
            hasMore: false,
            nextBeforeSortSequence: nil
        )
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {
        if let deleteError {
            throw deleteError
        }
        deletedMessageIDsBox.withValue { $0.append(messageID) }
    }

    func revoke(messageID: MessageID) async throws {
        if let revokeError {
            throw revokeError
        }
        didRevokeBox.set(true)
        revokedMessageIDsBox.withValue { $0.append(messageID) }
    }
}

final class TextSendingTimeStubChatUseCase: ChatUseCase {
    private let initialRows: [ChatMessageRowState]
    private let sentRowsBox: TestLockedBox<[ChatMessageRowState]>

    init(initialRows: [ChatMessageRowState], sentRows: [ChatMessageRowState]) {
        self.initialRows = initialRows
        self.sentRowsBox = TestLockedBox(sentRows)
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: initialRows, hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        let row = sentRowsBox.withValue { $0.removeFirst() }
        return AsyncThrowingStream { continuation in
            continuation.yield(row)
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

final class ImageSendingStubChatUseCase: ChatUseCase {
    private let sentImageCountBox = TestLockedBox(0)
    private let initialRows: [ChatMessageRowState]
    private let thumbnailPath: String

    var sentImageCount: Int {
        sentImageCountBox.snapshot
    }

    init(initialRows: [ChatMessageRowState] = [], thumbnailPath: String = "/tmp/chat-thumb.jpg") {
        self.initialRows = initialRows
        self.thumbnailPath = thumbnailPath
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: initialRows, hasMore: false, nextBeforeSortSequence: initialRows.first?.sortSequence)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sentImageCountBox.withValue { $0 += 1 }

        return AsyncThrowingStream { continuation in
            continuation.yield(
                ChatMessageRowState(
                    id: "image_stub_message",
                    content: .image(
                        ChatMessageRowContent.ImageContent(
                            thumbnailPath: thumbnailPath
                        )
                    ),
                    sortSequence: 1,
                    timeText: "Now",
                    statusText: nil,
                    uploadProgress: nil,
                    isOutgoing: true,
                    canRetry: false,
                    canDelete: true,
                    canRevoke: false
                )
            )
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

@MainActor
final class EmojiPanelStubChatUseCase: ChatUseCase {
    private let initialRows: [ChatMessageRowState]
    let packageEmoji = EmojiAssetRecord(
        emojiID: "package_stub",
        userID: "emoji_panel_user",
        packageID: "pkg_stub",
        emojiType: .package,
        name: "Package Stub",
        md5: nil,
        localPath: "/tmp/package.png",
        thumbPath: "/tmp/package-thumb.png",
        cdnURL: nil,
        width: 128,
        height: 128,
        sizeBytes: 1024,
        useCount: 0,
        lastUsedAt: nil,
        isFavorite: false,
        isDeleted: false,
        extraJSON: nil,
        createdAt: 1,
        updatedAt: 1
    )
    private let favoriteUpdatesBox = TestLockedBox<[String]>([])
    private let sentEmojiIDsBox = TestLockedBox<[String]>([])

    var favoriteUpdates: [String] {
        favoriteUpdatesBox.snapshot
    }

    var sentEmojiIDs: [String] {
        sentEmojiIDsBox.snapshot
    }

    init(initialRows: [ChatMessageRowState] = []) {
        self.initialRows = initialRows
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: initialRows, hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func loadEmojiPanelState() async throws -> ChatEmojiPanelState {
        ChatEmojiPanelState(
            packages: [
                EmojiPackageRecord(
                    packageID: "pkg_stub",
                    userID: "emoji_panel_user",
                    title: "Stub Pack",
                    author: "Tests",
                    coverURL: nil,
                    localCoverPath: nil,
                    version: 1,
                    status: .downloaded,
                    sortOrder: 1,
                    createdAt: 1,
                    updatedAt: 1
                )
            ],
            recentEmojis: [],
            favoriteEmojis: [
                EmojiAssetRecord(
                    emojiID: "favorite_stub",
                    userID: "emoji_panel_user",
                    packageID: nil,
                    emojiType: .customImage,
                    name: "Favorite Stub",
                    md5: nil,
                    localPath: "/tmp/favorite.png",
                    thumbPath: "/tmp/favorite-thumb.png",
                    cdnURL: nil,
                    width: 128,
                    height: 128,
                    sizeBytes: 1024,
                    useCount: 2,
                    lastUsedAt: 2,
                    isFavorite: true,
                    isDeleted: false,
                    extraJSON: nil,
                    createdAt: 1,
                    updatedAt: 2
                )
            ],
            packageEmojisByPackageID: ["pkg_stub": [packageEmoji]]
        )
    }

    func toggleEmojiFavorite(emojiID: String, isFavorite: Bool) async throws -> ChatEmojiPanelState {
        favoriteUpdatesBox.withValue { $0.append("\(emojiID):\(isFavorite)") }
        return try await loadEmojiPanelState()
    }

    func sendEmoji(_ emoji: EmojiAssetRecord) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sentEmojiIDsBox.withValue { $0.append(emoji.emojiID) }

        return AsyncThrowingStream { continuation in
            continuation.yield(
                ChatMessageRowState(
                    id: "sent_emoji",
                    content: .emoji(
                        ChatMessageRowContent.EmojiContent(
                            emojiID: emoji.emojiID,
                            name: emoji.name,
                            localPath: emoji.localPath,
                            thumbPath: emoji.thumbPath,
                            cdnURL: emoji.cdnURL
                        )
                    ),
                    sortSequence: 1,
                    timeText: "Now",
                    statusText: nil,
                    uploadProgress: nil,
                    isOutgoing: true,
                    canRetry: false,
                    canDelete: true,
                    canRevoke: false
                )
            )
            continuation.finish()
        }
    }

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

final class ComposerSendingStubChatUseCase: ChatUseCase {
    private let eventsBox = TestLockedBox<[String]>([])

    var events: [String] {
        eventsBox.snapshot
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        eventsBox.withValue { $0.append("text:\(text)") }

        return AsyncThrowingStream { continuation in
            continuation.yield(
                makeChatRow(id: "composer_text", text: text, sortSequence: 2)
            )
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        eventsBox.withValue { $0.append("image:\(preferredFileExtension ?? "")") }

        return AsyncThrowingStream { continuation in
            continuation.yield(
                ChatMessageRowState(
                    id: "composer_image",
                    content: .image(
                        ChatMessageRowContent.ImageContent(
                            thumbnailPath: "/tmp/composer-image.jpg"
                        )
                    ),
                    sortSequence: 1,
                    timeText: "Now",
                    statusText: nil,
                    uploadProgress: nil,
                    isOutgoing: true,
                    canRetry: false,
                    canDelete: true,
                    canRevoke: false
                )
            )
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVideo(fileURL: URL, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        eventsBox.withValue { $0.append("video:\(preferredFileExtension ?? "")") }

        return AsyncThrowingStream { continuation in
            continuation.yield(
                ChatMessageRowState(
                    id: "composer_video",
                    content: .video(
                        ChatMessageRowContent.VideoContent(
                            thumbnailPath: "/tmp/composer-video.jpg",
                            localPath: fileURL.path,
                            durationMilliseconds: 1_000
                        )
                    ),
                    sortSequence: 1,
                    timeText: "Now",
                    statusText: nil,
                    uploadProgress: nil,
                    isOutgoing: true,
                    canRetry: false,
                    canDelete: true,
                    canRevoke: false
                )
            )
            continuation.finish()
        }
    }

    func sendFile(fileURL: URL) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

final class VoicePlaybackStubChatUseCase: ChatUseCase {
    private let rowsBox: TestLockedBox<[ChatMessageRowState]>
    private let markedMessageIDsBox = TestLockedBox<[MessageID]>([])

    var markedMessageIDs: [MessageID] {
        markedMessageIDsBox.snapshot
    }

    init(rows: [ChatMessageRowState]) {
        self.rowsBox = TestLockedBox(rows)
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        let rows = rowsBox.snapshot
        return ChatMessagePage(rows: rows, hasMore: false, nextBeforeSortSequence: rows.first?.sortSequence)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        markedMessageIDsBox.withValue { $0.append(messageID) }

        return rowsBox.withValue { rows in
            guard let index = rows.firstIndex(where: { $0.id == messageID }) else {
                return nil
            }

            rows[index] = rows[index].withVoicePlayback(isPlaying: false, isUnplayed: false)
            return rows[index]
        }
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

final class ImmediateVoiceSendStubChatUseCase: ChatUseCase {
    private let row: ChatMessageRowState

    init(row: ChatMessageRowState) {
        self.row = row
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
    }

    func loadDraft() async throws -> String? {
        nil
    }

    func saveDraft(_ text: String) async throws {}

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func sendVoice(recording: VoiceRecordingFile) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(row)
            continuation.finish()
        }
    }

    func markVoicePlayed(messageID: MessageID) async throws -> ChatMessageRowState? {
        nil
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}
