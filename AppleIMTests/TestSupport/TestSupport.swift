import Testing
import AVFoundation
import Combine
import Foundation
import CoreGraphics
import ImageIO
import UIKit
import UniformTypeIdentifiers

@testable import AppleIM


actor ScriptedSyncDeltaService: SyncDeltaService {
    private let batches: [SyncBatch]
    private var nextBatchIndex = 0
    private var checkpoints: [SyncCheckpoint?] = []

    init(batches: [SyncBatch]) {
        self.batches = batches
    }

    func fetchDelta(after checkpoint: SyncCheckpoint?) async throws -> SyncBatch {
        checkpoints.append(checkpoint)

        guard !batches.isEmpty else {
            return SyncBatch(messages: [], nextCursor: checkpoint?.cursor, nextSequence: checkpoint?.sequence)
        }

        let batchIndex = min(nextBatchIndex, batches.count - 1)
        nextBatchIndex += 1
        return batches[batchIndex]
    }

    func requestedCheckpoints() -> [SyncCheckpoint?] {
        checkpoints
    }
}

@MainActor
final class TestNetworkConnectivityMonitor: NetworkConnectivityMonitoring {
    private let subject: CurrentValueSubject<Bool, Never>
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    init(isReachable: Bool) {
        self.subject = CurrentValueSubject(isReachable)
    }

    var isReachablePublisher: AnyPublisher<Bool, Never> {
        subject.eraseToAnyPublisher()
    }

    var currentIsReachable: Bool {
        subject.value
    }

    func start() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func setReachable(_ isReachable: Bool) {
        subject.send(isReachable)
    }
}

struct StubConversationListUseCase: ConversationListUseCase {
    func loadConversations() async throws -> [ConversationListRowState] {
        [
            ConversationListRowState(
                id: "test_conversation",
                title: "Test Conversation",
                subtitle: "Loaded by ViewModel",
                timeText: "Now",
                unreadText: nil,
                isPinned: false,
                isMuted: false
            )
        ]
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        let rows = try await loadConversations()
        let requestedLimit = max(limit, 0)
        let startIndex = cursor
            .flatMap { cursor in rows.firstIndex { $0.id == cursor.conversationID } }
            .map { rows.index(after: $0) } ?? rows.startIndex
        let pageRows = Array(rows[startIndex...].prefix(requestedLimit))

        return ConversationListPage(
            rows: pageRows,
            hasMore: startIndex + pageRows.count < rows.count,
            nextCursor: pageRows.last.map { ConversationPageCursor(isPinned: $0.isPinned, sortTimestamp: 0, conversationID: $0.id) }
        )
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}
}

actor StubContactListUseCase: ContactListUseCase {
    private(set) var queries: [String] = []

    func loadContacts(query: String) async throws -> ContactListViewState {
        queries.append(query)
        let row = ContactListRowState(
            contact: makeContactRecord(
                contactID: "contact_sondra",
                userID: "contact_vm_user",
                wxid: "sondra",
                nickname: "Sondra"
            )
        )
        return ContactListViewState(
            query: query,
            phase: .loaded,
            groupRows: [],
            starredRows: [],
            contactRows: [row]
        )
    }

    func openConversation(for contactID: ContactID) async throws -> ConversationListRowState {
        #expect(contactID == "contact_sondra")
        return ConversationListRowState(
            id: "single_sondra",
            title: "Sondra",
            subtitle: "",
            timeText: "",
            unreadText: nil,
            isPinned: false,
            isMuted: false
        )
    }
}

struct PagedConversationListUseCase: ConversationListUseCase {
    private let rows: [ConversationListRowState] = (0..<3).map { index in
        ConversationListRowState(
            id: ConversationID(rawValue: "paged_\(index)"),
            title: "Paged \(index)",
            subtitle: "Page row \(index)",
            timeText: "Now",
            unreadText: nil,
            isPinned: false,
            isMuted: false
        )
    }

    func loadConversations() async throws -> [ConversationListRowState] {
        rows
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        let requestedLimit = max(limit, 0)
        let startIndex = cursor
            .flatMap { cursor in rows.firstIndex { $0.id == cursor.conversationID } }
            .map { rows.index(after: $0) } ?? rows.startIndex
        let pageRows = Array(rows[startIndex...].prefix(requestedLimit))

        return ConversationListPage(
            rows: pageRows,
            hasMore: startIndex + pageRows.count < rows.count,
            nextCursor: pageRows.last.map { ConversationPageCursor(isPinned: $0.isPinned, sortTimestamp: 0, conversationID: $0.id) }
        )
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}
}

actor CursorShiftConversationListUseCase: ConversationListUseCase {
    private var didLoadFirstPage = false
    private let originalRows: [ConversationListRowState] = [
        ConversationListRowState(
            id: "shift_3",
            title: "Shift 3",
            subtitle: "Initial newest",
            timeText: "Now",
            unreadText: nil,
            isPinned: false,
            isMuted: false
        ),
        ConversationListRowState(
            id: "shift_2",
            title: "Shift 2",
            subtitle: "Initial cursor",
            timeText: "Now",
            unreadText: nil,
            isPinned: false,
            isMuted: false
        ),
        ConversationListRowState(
            id: "shift_1",
            title: "Shift 1",
            subtitle: "Older row",
            timeText: "Now",
            unreadText: nil,
            isPinned: false,
            isMuted: false
        )
    ]

    private var shiftedRows: [ConversationListRowState] {
        [
            ConversationListRowState(
                id: "shift_new",
                title: "Shift New",
                subtitle: "Inserted ahead of the cursor",
                timeText: "Now",
                unreadText: nil,
                isPinned: false,
                isMuted: false
            )
        ] + originalRows
    }

    func loadConversations() async throws -> [ConversationListRowState] {
        originalRows
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        let allRows: [ConversationListRowState]
        if cursor == nil {
            didLoadFirstPage = true
            allRows = originalRows
        } else {
            #expect(didLoadFirstPage)
            allRows = shiftedRows
        }

        let startIndex = cursor
            .flatMap { cursor in allRows.firstIndex { $0.id == cursor.conversationID } }
            .map { allRows.index(after: $0) } ?? allRows.startIndex
        let pageRows = Array(allRows[startIndex...].prefix(max(limit, 0)))

        return ConversationListPage(
            rows: pageRows,
            hasMore: startIndex + pageRows.count < allRows.count,
            nextCursor: pageRows.last.map { ConversationPageCursor(isPinned: $0.isPinned, sortTimestamp: 0, conversationID: $0.id) }
        )
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}
}

actor MutableConversationListUseCase: ConversationListUseCase {
    private var row = ConversationListRowState(
        id: "mutable_conversation",
        title: "Mutable Conversation",
        subtitle: "Settings can change",
        timeText: "Now",
        unreadText: nil,
        isPinned: false,
        isMuted: false
    )

    func loadConversations() async throws -> [ConversationListRowState] {
        [row]
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        let allRows = try await loadConversations()
        let startIndex = cursor
            .flatMap { cursor in allRows.firstIndex { $0.id == cursor.conversationID } }
            .map { allRows.index(after: $0) } ?? allRows.startIndex
        let rows = Array(allRows[startIndex...].prefix(max(limit, 0)))
        return ConversationListPage(
            rows: rows,
            hasMore: false,
            nextCursor: rows.last.map { ConversationPageCursor(isPinned: $0.isPinned, sortTimestamp: 0, conversationID: $0.id) }
        )
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {
        guard conversationID == row.id else { return }
        row = ConversationListRowState(
            id: row.id,
            title: row.title,
            subtitle: row.subtitle,
            timeText: row.timeText,
            unreadText: row.unreadText,
            isPinned: isPinned,
            isMuted: row.isMuted
        )
    }

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {
        guard conversationID == row.id else { return }
        row = ConversationListRowState(
            id: row.id,
            title: row.title,
            subtitle: row.subtitle,
            timeText: row.timeText,
            unreadText: row.unreadText,
            isPinned: row.isPinned,
            isMuted: isMuted
        )
    }
}

actor CountingConversationListUseCase: ConversationListUseCase {
    private(set) var loadPageCallCount = 0

    func loadConversations() async throws -> [ConversationListRowState] {
        try await loadConversationPage(limit: 50, after: nil).rows
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        loadPageCallCount += 1
        let rows = [
            ConversationListRowState(
                id: "counting_conversation",
                title: "Counting Conversation",
                subtitle: "Loaded once",
                timeText: "Now",
                unreadText: nil,
                isPinned: false,
                isMuted: false
            )
        ]
        return ConversationListPage(
            rows: rows,
            hasMore: false,
            nextCursor: rows.last.map { ConversationPageCursor(isPinned: $0.isPinned, sortTimestamp: 0, conversationID: $0.id) }
        )
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}
}

actor ReadClearingConversationListUseCase: ConversationListUseCase {
    private(set) var loadPageCallCount = 0

    func loadConversations() async throws -> [ConversationListRowState] {
        try await loadConversationPage(limit: 50, after: nil).rows
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        loadPageCallCount += 1
        let unreadText = loadPageCallCount == 1 ? "2" : nil
        let rows = [
            ConversationListRowState(
                id: "read_clearing_conversation",
                title: "Read Clearing",
                subtitle: "Tap to read",
                timeText: "Now",
                unreadText: unreadText,
                isPinned: false,
                isMuted: false
            )
        ]
        return makeConversationListPage(rows: rows, limit: limit, after: cursor)
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}
}

actor SimulatingConversationListUseCase: ConversationListUseCase {
    private var row = ConversationListRowState(
        id: "simulated_list_conversation",
        title: "Simulated List",
        subtitle: "Before simulation",
        timeText: "Now",
        unreadText: nil,
        isPinned: false,
        isMuted: false
    )
    private(set) var loadPageCallCount = 0
    private(set) var simulateIncomingCallCount = 0

    func loadConversations() async throws -> [ConversationListRowState] {
        try await loadConversationPage(limit: 50, after: nil).rows
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        loadPageCallCount += 1
        return makeConversationListPage(rows: [row], limit: limit, after: cursor)
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}

    func simulateIncomingMessages() async throws -> ConversationListSimulationResult? {
        simulateIncomingCallCount += 1
        row = ConversationListRowState(
            id: row.id,
            title: row.title,
            subtitle: "模拟收到 3 条列表消息 #stub",
            timeText: "Now",
            unreadText: "3",
            isPinned: row.isPinned,
            isMuted: row.isMuted
        )
        return ConversationListSimulationResult(
            conversationID: row.id,
            messageCount: 3,
            finalRow: row
        )
    }
}

actor ExternalConversationChangeUseCase: ConversationListUseCase {
    private var row = ConversationListRowState(
        id: "external_change_conversation",
        title: "External Change",
        subtitle: "No unread yet",
        timeText: "Now",
        unreadText: nil,
        isPinned: false,
        isMuted: false
    )

    func loadConversations() async throws -> [ConversationListRowState] {
        try await loadConversationPage(limit: 50, after: nil).rows
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        makeConversationListPage(rows: [row], limit: limit, after: cursor)
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}

    func receiveUnreadMessage() {
        row = ConversationListRowState(
            id: row.id,
            title: row.title,
            subtitle: "Externally received",
            timeText: "Now",
            unreadText: "1",
            isPinned: row.isPinned,
            isMuted: row.isMuted
        )
    }
}

actor ImmediateResultSlowRefreshConversationListUseCase: ConversationListUseCase {
    private var row = ConversationListRowState(
        id: "immediate_simulated_list_conversation",
        title: "Immediate Simulated List",
        subtitle: "Before simulation",
        timeText: "Now",
        unreadText: nil,
        isPinned: false,
        isMuted: false
    )
    private(set) var loadPageCallCount = 0
    private(set) var simulateIncomingCallCount = 0

    func loadConversations() async throws -> [ConversationListRowState] {
        try await loadConversationPage(limit: 50, after: nil).rows
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        loadPageCallCount += 1
        if loadPageCallCount > 1 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        return makeConversationListPage(rows: [row], limit: limit, after: cursor)
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}

    func simulateIncomingMessages() async throws -> ConversationListSimulationResult? {
        simulateIncomingCallCount += 1
        row = ConversationListRowState(
            id: row.id,
            title: row.title,
            subtitle: "Immediate simulation result",
            timeText: "Now",
            unreadText: "4",
            isPinned: row.isPinned,
            isMuted: row.isMuted
        )
        return ConversationListSimulationResult(
            conversationID: row.id,
            messageCount: 4,
            finalRow: row
        )
    }
}

actor DelayedSimulatingConversationListUseCase: ConversationListUseCase {
    private var row = ConversationListRowState(
        id: "delayed_simulated_list_conversation",
        title: "Delayed Simulated List",
        subtitle: "Before simulation",
        timeText: "Now",
        unreadText: nil,
        isPinned: false,
        isMuted: false
    )
    private(set) var simulateIncomingCallCount = 0

    func loadConversations() async throws -> [ConversationListRowState] {
        [row]
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        makeConversationListPage(rows: [row], limit: limit, after: cursor)
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}

    func simulateIncomingMessages() async throws -> ConversationListSimulationResult? {
        simulateIncomingCallCount += 1
        try await Task.sleep(nanoseconds: 20_000_000)
        row = ConversationListRowState(
            id: row.id,
            title: row.title,
            subtitle: "模拟收到 \(simulateIncomingCallCount) 条列表消息 #delayed",
            timeText: "Now",
            unreadText: "\(simulateIncomingCallCount)",
            isPinned: false,
            isMuted: false
        )
        return ConversationListSimulationResult(
            conversationID: row.id,
            messageCount: simulateIncomingCallCount,
            finalRow: row
        )
    }
}

struct FailingSimulationConversationListUseCase: ConversationListUseCase {
    func loadConversations() async throws -> [ConversationListRowState] {
        [
            ConversationListRowState(
                id: "failing_simulation_conversation",
                title: "Failing Simulation",
                subtitle: "Loaded before failure",
                timeText: "Now",
                unreadText: nil,
                isPinned: false,
                isMuted: false
            )
        ]
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        let rows = try await loadConversations()
        return makeConversationListPage(rows: rows, limit: limit, after: cursor)
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}

    func simulateIncomingMessages() async throws -> ConversationListSimulationResult? {
        throw TestChatError.expectedFailure
    }
}

struct EmptySimulationConversationListUseCase: ConversationListUseCase {
    func loadConversations() async throws -> [ConversationListRowState] {
        []
    }

    func loadConversationPage(limit: Int, after cursor: ConversationPageCursor?) async throws -> ConversationListPage {
        ConversationListPage(rows: [], hasMore: false, nextCursor: nil)
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) async throws {}

    func setMuted(conversationID: ConversationID, isMuted: Bool) async throws {}

    func simulateIncomingMessages() async throws -> ConversationListSimulationResult? {
        nil
    }
}

func makeConversationListPage(
    rows: [ConversationListRowState],
    limit: Int,
    after cursor: ConversationPageCursor?
) -> ConversationListPage {
    let startIndex = cursor
        .flatMap { cursor in rows.firstIndex { $0.id == cursor.conversationID } }
        .map { rows.index(after: $0) } ?? rows.startIndex
    let pageRows = Array(rows[startIndex...].prefix(max(limit, 0)))

    return ConversationListPage(
        rows: pageRows,
        hasMore: startIndex + pageRows.count < rows.count,
        nextCursor: pageRows.last.map {
            ConversationPageCursor(isPinned: $0.isPinned, sortTimestamp: 0, conversationID: $0.id)
        }
    )
}

final class ConversationListLoadingDiagnosticsSpy: ConversationListLoadingDiagnostics, @unchecked Sendable {
    private let lock = NSLock()
    private var storedMessages: [String] = []

    var messages: [String] {
        lock.withLock {
            storedMessages
        }
    }

    func log(_ message: String) {
        lock.withLock {
            storedMessages.append(message)
        }
    }
}

actor ConversationChangeNotificationSpy {
    private var records: [(userID: String?, conversationIDs: [String])] = []

    func record(userID: String?, conversationIDs: [String]) {
        records.append((userID: userID, conversationIDs: conversationIDs))
    }

    func didRecord(userID: String, conversationID: String) -> Bool {
        records.contains {
            $0.userID == userID && $0.conversationIDs.contains(conversationID)
        }
    }
}

struct EmptySearchUseCase: SearchUseCase {
    func search(query: String) async throws -> SearchResults {
        SearchResults()
    }

    func rebuildIndex() async throws {}
}

actor TrackingAccountStorageService: AccountStorageService {
    private let rootDirectory: URL
    private(set) var prepareCallCount = 0

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    func prepareStorage(for accountID: UserID) async throws -> AccountStoragePaths {
        prepareCallCount += 1
        let paths = try makePaths(for: accountID)
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: paths.rootDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.mediaDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.cacheDirectory, withIntermediateDirectories: true)
        createFileIfNeeded(at: paths.mainDatabase)
        createFileIfNeeded(at: paths.searchDatabase)
        createFileIfNeeded(at: paths.fileIndexDatabase)

        return paths
    }

    func deleteStorage(for accountID: UserID) async throws {
        let paths = try makePaths(for: accountID)
        if FileManager.default.fileExists(atPath: paths.rootDirectory.path) {
            try FileManager.default.removeItem(at: paths.rootDirectory)
        }
    }

    private func makePaths(for accountID: UserID) throws -> AccountStoragePaths {
        let rawID = accountID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawID.isEmpty else {
            throw AccountStorageError.emptyAccountID
        }

        let accountRoot = rootDirectory.appendingPathComponent("account_\(rawID)", isDirectory: true)
        return AccountStoragePaths(
            accountID: accountID,
            rootDirectory: accountRoot,
            mainDatabase: accountRoot.appendingPathComponent("main.db"),
            searchDatabase: accountRoot.appendingPathComponent("search.db"),
            fileIndexDatabase: accountRoot.appendingPathComponent("file_index.db"),
            mediaDirectory: accountRoot.appendingPathComponent("media", isDirectory: true),
            cacheDirectory: accountRoot.appendingPathComponent("cache", isDirectory: true)
        )
    }

    private func createFileIfNeeded(at url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: Data())
        }
    }
}

actor TrackingAccountDatabaseKeyStore: AccountDatabaseKeyStore {
    private var keys: [UserID: Data] = [:]
    private(set) var databaseKeyCallCount = 0

    func databaseKey(for accountID: UserID) async throws -> Data {
        databaseKeyCallCount += 1
        if let key = keys[accountID] {
            return key
        }

        let key = Data(repeating: UInt8(databaseKeyCallCount), count: 32)
        keys[accountID] = key
        return key
    }

    func deleteDatabaseKey(for accountID: UserID) async throws {
        keys[accountID] = nil
    }
}

struct StaleSearchUseCase: SearchUseCase {
    func search(query: String) async throws -> SearchResults {
        if query == "old" {
            try await Task.sleep(nanoseconds: 80_000_000)
            return SearchResults(
                messages: [
                    SearchResultRecord(
                        kind: .message,
                        id: "old_result",
                        title: "Old Result",
                        subtitle: "Old",
                        conversationID: "old_conversation",
                        messageID: "old_message"
                    )
                ]
            )
        }

        return SearchResults(
            messages: [
                SearchResultRecord(
                    kind: .message,
                    id: "new_result",
                    title: "New Result",
                    subtitle: "New",
                    conversationID: "new_conversation",
                    messageID: "new_message"
                )
            ]
        )
    }

    func rebuildIndex() async throws {}
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

final class StoreRefreshingChatUseCase: @unchecked Sendable, ChatUseCase {
    let observedUserID: UserID? = "store_refresh_user"
    let observedConversationID: ConversationID? = "store_refresh_conversation"
    private var rows: [ChatMessageRowState] = []
    private(set) var loadInitialMessagesCallCount = 0

    func replaceRows(_ rows: [ChatMessageRowState]) {
        self.rows = rows
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        loadInitialMessagesCallCount += 1
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

final class SimulatedIncomingStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private let initialRows: [ChatMessageRowState]
    private let simulatedRows: [ChatMessageRowState]
    private(set) var simulateIncomingCallCount = 0

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
        simulateIncomingCallCount += 1
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

final class MissedSimulatedIncomingStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private(set) var simulateIncomingCallCount = 0

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
        simulateIncomingCallCount += 1
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

final class DelayedSimulatedIncomingStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private(set) var simulateIncomingCallCount = 0

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
        simulateIncomingCallCount += 1
        let callCount = simulateIncomingCallCount
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

final class DelayedTextSendingStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private(set) var sentTexts: [String] = []

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
        sentTexts.append(text)
        let sortSequence = Int64(sentTexts.count)
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

final class PagingStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private let initialPage: ChatMessagePage
    private let olderPage: ChatMessagePage
    private let olderError: TestChatError?
    private(set) var loadOlderCallCount = 0

    init(initialPage: ChatMessagePage, olderPage: ChatMessagePage, olderError: TestChatError? = nil) {
        self.initialPage = initialPage
        self.olderPage = olderPage
        self.olderError = olderError
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        initialPage
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        loadOlderCallCount += 1

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

final class DeferredInitialPageStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private let initialPage: ChatMessagePage
    private var initialContinuation: CheckedContinuation<ChatMessagePage, Error>?
    private var isInitialPageReleased = false

    init(initialPage: ChatMessagePage) {
        self.initialPage = initialPage
    }

    func releaseInitialPage() {
        isInitialPageReleased = true
        let continuation = initialContinuation
        initialContinuation = nil

        continuation?.resume(returning: initialPage)
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        if isInitialPageReleased {
            return initialPage
        }

        return try await withCheckedThrowingContinuation { continuation in
            if isInitialPageReleased {
                continuation.resume(returning: initialPage)
            } else {
                initialContinuation = continuation
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

final class DeferredOlderPageStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private let initialPage: ChatMessagePage
    private let olderPage: ChatMessagePage
    private var olderContinuation: CheckedContinuation<ChatMessagePage, Error>?
    private var isOlderPageReleased = false
    private(set) var loadOlderCallCount = 0

    init(initialPage: ChatMessagePage, olderPage: ChatMessagePage) {
        self.initialPage = initialPage
        self.olderPage = olderPage
    }

    func releaseOlderPage() {
        isOlderPageReleased = true
        let continuation = olderContinuation
        olderContinuation = nil

        continuation?.resume(returning: olderPage)
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        initialPage
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        loadOlderCallCount += 1
        if isOlderPageReleased {
            return olderPage
        }

        return try await withCheckedThrowingContinuation { continuation in
            if isOlderPageReleased {
                continuation.resume(returning: olderPage)
            } else {
                olderContinuation = continuation
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
final class GroupContextStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private let context: GroupChatContext
    private(set) var sentText: String?
    private(set) var sentMentionedUserIDs: [UserID] = []
    private(set) var sentMentionsAll = false

    init(context: GroupChatContext) {
        self.context = context
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

    func loadGroupContext() async throws -> GroupChatContext? {
        context
    }

    func sendText(_ text: String) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sendText(text, mentionedUserIDs: [], mentionsAll: false)
    }

    func sendText(_ text: String, mentionedUserIDs: [UserID], mentionsAll: Bool) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sentText = text
        sentMentionedUserIDs = mentionedUserIDs
        sentMentionsAll = mentionsAll
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

final class RecoveringPagingStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private let initialPage: ChatMessagePage
    private let recoveredPage: ChatMessagePage
    private(set) var loadOlderCallCount = 0

    init(initialPage: ChatMessagePage, recoveredPage: ChatMessagePage) {
        self.initialPage = initialPage
        self.recoveredPage = recoveredPage
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        initialPage
    }

    func loadOlderMessages(beforeSortSequence: Int64, limit: Int) async throws -> ChatMessagePage {
        loadOlderCallCount += 1

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

final class MessageActionStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private let initialRows: [ChatMessageRowState]
    private let revokedRows: [ChatMessageRowState]
    private let deleteError: TestChatError?
    private let revokeError: TestChatError?
    private var didRevoke = false
    private(set) var deletedMessageIDs: [MessageID] = []
    private(set) var revokedMessageIDs: [MessageID] = []

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
            rows: didRevoke ? revokedRows : initialRows,
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
        deletedMessageIDs.append(messageID)
    }

    func revoke(messageID: MessageID) async throws {
        if let revokeError {
            throw revokeError
        }
        didRevoke = true
        revokedMessageIDs.append(messageID)
    }
}

final class TextSendingTimeStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private let initialRows: [ChatMessageRowState]
    private var sentRows: [ChatMessageRowState]

    init(initialRows: [ChatMessageRowState], sentRows: [ChatMessageRowState]) {
        self.initialRows = initialRows
        self.sentRows = sentRows
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
        let row = sentRows.removeFirst()
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

final class ImageSendingStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private(set) var sentImageCount = 0
    private let initialRows: [ChatMessageRowState]
    private let thumbnailPath: String

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
        sentImageCount += 1

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
final class EmojiPanelStubChatUseCase: @unchecked Sendable, ChatUseCase {
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
    private(set) var favoriteUpdates: [String] = []
    private(set) var sentEmojiIDs: [String] = []

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
        favoriteUpdates.append("\(emojiID):\(isFavorite)")
        return try await loadEmojiPanelState()
    }

    func sendEmoji(_ emoji: EmojiAssetRecord) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        sentEmojiIDs.append(emoji.emojiID)

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

final class ComposerSendingStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private(set) var events: [String] = []

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
        events.append("text:\(text)")

        return AsyncThrowingStream { continuation in
            continuation.yield(
                makeChatRow(id: "composer_text", text: text, sortSequence: 2)
            )
            continuation.finish()
        }
    }

    func sendImage(data: Data, preferredFileExtension: String?) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        events.append("image:\(preferredFileExtension ?? "")")

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
        events.append("video:\(preferredFileExtension ?? "")")

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

final class VoicePlaybackStubChatUseCase: @unchecked Sendable, ChatUseCase {
    private var rows: [ChatMessageRowState]
    private(set) var markedMessageIDs: [MessageID] = []

    init(rows: [ChatMessageRowState]) {
        self.rows = rows
    }

    func loadInitialMessages() async throws -> ChatMessagePage {
        ChatMessagePage(rows: rows, hasMore: false, nextBeforeSortSequence: rows.first?.sortSequence)
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
        markedMessageIDs.append(messageID)

        guard let index = rows.firstIndex(where: { $0.id == messageID }) else {
            return nil
        }

        rows[index] = rows[index].withVoicePlayback(isPlaying: false, isUnplayed: false)
        return rows[index]
    }

    func resend(messageID: MessageID) -> AsyncThrowingStream<ChatMessageRowState, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func delete(messageID: MessageID) async throws {}

    func revoke(messageID: MessageID) async throws {}
}

final class ImmediateVoiceSendStubChatUseCase: @unchecked Sendable, ChatUseCase {
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

enum TestChatError: Error {
    case paginationFailed
    case messageActionFailed
    case expectedFailure
}

func makeChatRow(
    id: MessageID,
    text: String,
    sortSequence: Int64,
    sentAt: Int64 = 0,
    senderAvatarURL: String? = nil,
    isOutgoing: Bool = true
) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .text(text),
        sortSequence: sortSequence,
        sentAt: sentAt,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        senderAvatarURL: senderAvatarURL,
        isOutgoing: isOutgoing,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}

@MainActor
func makeScrollableChatViewController(
    title: String,
    rowPrefix: String,
    useEmojiUseCase: Bool = false
) async throws -> (
    window: UIWindow,
    viewController: ChatViewController,
    collectionView: UICollectionView,
    inputBar: ChatInputBarView
) {
    let rows = (1...36).map { index in
        makeChatRow(
            id: MessageID(rawValue: "\(rowPrefix)_\(index)"),
            text: "\(title) message \(index)",
            sortSequence: Int64(index)
        )
    }
    let viewModel: ChatViewModel
    if useEmojiUseCase {
        viewModel = ChatViewModel(
            useCase: EmojiPanelStubChatUseCase(initialRows: rows),
            title: title
        )
    } else {
        viewModel = ChatViewModel(
            useCase: PagingStubChatUseCase(
                initialPage: ChatMessagePage(rows: rows, hasMore: false, nextBeforeSortSequence: nil),
                olderPage: ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
            ),
            title: title
        )
    }
    let viewController = ChatViewController(viewModel: viewModel)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = viewController
    window.makeKeyAndVisible()

    viewController.loadViewIfNeeded()
    try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
        guard let collectionView = findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView else {
            return false
        }
        return collectionView.numberOfItems(inSection: 0) == rows.count
    }
    window.layoutIfNeeded()

    let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
    let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
    return (window, viewController, collectionView, inputBar)
}

@MainActor
func assertChatCollectionCanLeaveBottomAfterUserDrag(
    viewController: ChatViewController,
    collectionView: UICollectionView,
    window: UIWindow
) throws {
    let lastItem = collectionView.numberOfItems(inSection: 0) - 1
    try #require(lastItem > 0)

    collectionView.scrollToItem(at: IndexPath(item: lastItem, section: 0), at: .bottom, animated: false)
    window.layoutIfNeeded()
    collectionView.layoutIfNeeded()

    let bottomOffsetY = collectionView.contentOffset.y
    let minOffsetY = -collectionView.adjustedContentInset.top
    let targetOffsetY = max(minOffsetY, bottomOffsetY - 160)
    try #require(targetOffsetY < bottomOffsetY - 1)

    viewController.scrollViewWillBeginDragging(collectionView)
    collectionView.setContentOffset(
        CGPoint(x: collectionView.contentOffset.x, y: targetOffsetY),
        animated: false
    )
    viewController.viewDidLayoutSubviews()
    collectionView.layoutIfNeeded()

    #expect(collectionView.contentOffset.y <= targetOffsetY + 1)
}

@MainActor
func latestMessageCellIsAboveInputBar(
    collectionView: UICollectionView,
    item: Int,
    inputBar: ChatInputBarView,
    in view: UIView
) -> Bool {
    guard let cell = collectionView.cellForItem(at: IndexPath(item: item, section: 0)) else {
        return false
    }
    let cellFrame = cell.convert(cell.bounds, to: view)
    let inputFrame = inputBar.convert(inputBar.bounds, to: view)
    return cellFrame.maxY <= inputFrame.minY + 1
}

func timestamp(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    calendar: Calendar
) throws -> Int64 {
    let date = try #require(
        calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )
    )
    return Int64(date.timeIntervalSince1970)
}

func makeRevokedChatRow(id: MessageID, text: String, sortSequence: Int64) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .revoked(text),
        sortSequence: sortSequence,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: true,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}

func makeVoiceRow(id: MessageID, sortSequence: Int64, isUnplayed: Bool) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .voice(
            ChatMessageRowContent.VoiceContent(
                localPath: "/tmp/\(id.rawValue).m4a",
                durationMilliseconds: 2_000,
                isUnplayed: isUnplayed,
                isPlaying: false
            )
        ),
        sortSequence: sortSequence,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: false,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}

func makeImageRow(id: MessageID, sortSequence: Int64) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .image(
            ChatMessageRowContent.ImageContent(
                thumbnailPath: "/tmp/\(id.rawValue).jpg"
            )
        ),
        sortSequence: sortSequence,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: false,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}

func makeVideoRow(id: MessageID, sortSequence: Int64) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .video(
            ChatMessageRowContent.VideoContent(
                thumbnailPath: "/tmp/\(id.rawValue).jpg",
                localPath: "/tmp/\(id.rawValue).mov",
                durationMilliseconds: 3_000
            )
        ),
        sortSequence: sortSequence,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: false,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}

func makeFileRow(id: MessageID, sortSequence: Int64) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .file(
            ChatMessageRowContent.FileContent(
                fileName: "\(id.rawValue).pdf",
                fileExtension: "pdf",
                localPath: "/tmp/\(id.rawValue).pdf",
                sizeBytes: 1_024
            )
        ),
        sortSequence: sortSequence,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: false,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}

func makeRevokedRow(id: MessageID, sortSequence: Int64) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .revoked("你撤回了一条消息"),
        sortSequence: sortSequence,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: true,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}



func rowText(_ row: ChatMessageRowState) -> String {
    switch row.content {
    case let .text(text), let .revoked(text):
        return text
    case .image:
        return "Image"
    case let .voice(voice):
        return "Voice \(durationText(milliseconds: voice.durationMilliseconds))"
    case let .video(video):
        return "Video \(durationText(milliseconds: video.durationMilliseconds))"
    case let .file(file):
        return file.fileName
    case let .emoji(emoji):
        return emoji.name ?? "Emoji"
    }
}

func isImageContent(_ row: ChatMessageRowState) -> Bool {
    if case .image = row.content {
        return true
    }
    return false
}

func imageThumbnailPath(_ row: ChatMessageRowState) -> String? {
    if case let .image(image) = row.content {
        return image.thumbnailPath
    }
    return nil
}

func isVoiceContent(_ row: ChatMessageRowState) -> Bool {
    if case .voice = row.content {
        return true
    }
    return false
}

func voiceLocalPath(_ row: ChatMessageRowState) -> String? {
    if case let .voice(voice) = row.content {
        return voice.localPath
    }
    return nil
}

func isUnplayedVoiceContent(_ row: ChatMessageRowState) -> Bool {
    if case let .voice(voice) = row.content {
        return voice.isUnplayed
    }
    return false
}

func isPlayingVoiceContent(_ row: ChatMessageRowState) -> Bool {
    if case let .voice(voice) = row.content {
        return voice.isPlaying
    }
    return false
}

func isVideoContent(_ row: ChatMessageRowState) -> Bool {
    if case .video = row.content {
        return true
    }
    return false
}

func videoThumbnailPath(_ row: ChatMessageRowState) -> String? {
    if case let .video(video) = row.content {
        return video.thumbnailPath
    }
    return nil
}

@MainActor
func largestLoadedImageView(in view: UIView) -> UIImageView? {
    var candidates: [UIImageView] = []

    func collect(from view: UIView) {
        if let imageView = view as? UIImageView, imageView.image != nil {
            candidates.append(imageView)
        }
        view.subviews.forEach(collect)
    }

    collect(from: view)
    return candidates.max { lhs, rhs in
        (lhs.bounds.width * lhs.bounds.height) < (rhs.bounds.width * rhs.bounds.height)
    }
}

func durationText(milliseconds: Int) -> String {
    ChatMessageRowContent.voiceDurationDisplayText(milliseconds: milliseconds)
}

func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("AppleIMTests-\(UUID().uuidString)", isDirectory: true)
}

func makeMockAccountsFile() throws -> URL {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("mock_accounts.json")
    let json = """
    [
      {
        "userID": "mock_user",
        "loginName": "mock_user",
        "password": "password123",
        "displayName": "Mock User",
        "mobile": "13700000000",
        "avatarURL": "https://example.com/mock-avatar.png"
      }
    ]
    """
    try Data(json.utf8).write(to: url, options: [.atomic])
    return url
}

func makeMockContactsFile() throws -> URL {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("mock_contacts.json")
    let json = """
    [
      {
        "accountID": "mock_user",
        "contacts": [
          {
            "contactID": "contact_sondra",
            "wxid": "sondra",
            "nickname": "Sondra",
            "remark": "",
            "avatarURL": "https://example.com/sondra.png",
            "type": "friend",
            "isStarred": true
          },
          {
            "contactID": "group_core_contact",
            "wxid": "chatbridge_core",
            "nickname": "ChatBridge Core",
            "remark": "",
            "avatarURL": null,
            "type": "group",
            "isStarred": false
          }
        ]
      },
      {
        "accountID": "other_user",
        "contacts": [
          {
            "contactID": "contact_other",
            "wxid": "other",
            "nickname": "Other",
            "remark": "",
            "avatarURL": null,
            "type": "friend",
            "isStarred": false
          }
        ]
      }
    ]
    """
    try Data(json.utf8).write(to: url, options: [.atomic])
    return url
}

func makeMockDemoDataFile(messageCount: Int, firstMessageDirection: String = "incoming") throws -> URL {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("mock_demo_data.json")
    let messages = (1...messageCount).map { index in
        let direction = index == 1 ? firstMessageDirection : (index.isMultiple(of: 5) ? "outgoing" : "incoming")
        let offset = index - messageCount
        return """
              {
                "conversationID": "single_sondra",
                "senderID": "\(direction == "outgoing" ? "mock_user" : "sondra")",
                "text": "Sondra JSON message \(index)",
                "localTimeOffsetSeconds": \(offset),
                "messageID": "seed_single_sondra_\(index)",
                "serverMessageID": "server_seed_single_sondra_\(index)",
                "sequenceOffsetSeconds": \(offset),
                "direction": "\(direction)",
                "readStatus": "\(direction == "incoming" ? "unread" : "read")",
                "sortSequenceOffsetSeconds": \(offset)
              }
        """
    }.joined(separator: ",\n")
    let lastOffset = 0
    let json = """
    [
      {
        "accountID": "mock_user",
        "conversations": [
          {
            "id": "single_sondra",
            "type": "single",
            "targetID": "sondra",
            "title": "Sondra",
            "avatarURL": null,
            "unreadCount": 2,
            "draftText": null,
            "isPinned": true,
            "isMuted": false,
            "isHidden": false,
            "createdAtOffsetSeconds": -7200
          },
          {
            "id": "group_core",
            "type": "group",
            "targetID": "chatbridge_core",
            "title": "ChatBridge Core",
            "avatarURL": null,
            "unreadCount": 0,
            "draftText": null,
            "isPinned": false,
            "isMuted": true,
            "isHidden": false,
            "createdAtOffsetSeconds": -7200,
            "lastMessageTimeOffsetSeconds": -1800,
            "lastMessageDigest": "群聊 JSON seed 已接入。",
            "sortTimestampOffsetSeconds": -1800
          },
          {
            "id": "system_release",
            "type": "system",
            "targetID": "system",
            "title": "系统通知",
            "avatarURL": null,
            "unreadCount": 0,
            "draftText": null,
            "isPinned": false,
            "isMuted": false,
            "isHidden": false,
            "createdAtOffsetSeconds": -7200,
            "lastMessageTimeOffsetSeconds": -3600,
            "lastMessageDigest": "系统 JSON seed 已接入。",
            "sortTimestampOffsetSeconds": -3600
          }
        ],
        "messages": [
    \(messages)
        ],
        "groupMembers": [
          {
            "conversationID": "group_core",
            "memberID": "mock_user",
            "displayName": "Me",
            "role": "admin",
            "joinTimeOffsetSeconds": -3600
          },
          {
            "conversationID": "group_core",
            "memberID": "sondra",
            "displayName": "Sondra",
            "role": "owner",
            "joinTimeOffsetSeconds": -3500
          }
        ],
        "groupAnnouncements": [
          {
            "conversationID": "group_core",
            "text": "群聊 JSON seed 已接入。"
          }
        ],
        "lastMessageTimeOffsetSeconds": \(lastOffset)
      },
      {
        "accountID": "other_user",
        "conversations": [],
        "messages": [],
        "groupMembers": [],
        "groupAnnouncements": []
      }
    ]
    """
    try Data(json.utf8).write(to: url, options: [.atomic])
    return url
}

func samplePNGData() -> Data {
    Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")!
}

func makeVoiceRecordingFile(in directory: URL) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("sample-\(UUID().uuidString)").appendingPathExtension("m4a")
    try Data("mock voice recording".utf8).write(to: url, options: [.atomic])
    return url
}

func makeSampleVideoFile(in directory: URL) async throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("sample-\(UUID().uuidString)").appendingPathExtension("mov")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 64,
        AVVideoHeightKey: 64
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 64
        ]
    )

    guard writer.canAdd(input) else {
        Issue.record("Unable to add video writer input")
        return url
    }

    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    let firstPixelBuffer = try makePixelBuffer(width: 64, height: 64, colorOffset: 0)
    let secondPixelBuffer = try makePixelBuffer(width: 64, height: 64, colorOffset: 48)
    while !input.isReadyForMoreMediaData {
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    guard adaptor.append(firstPixelBuffer, withPresentationTime: .zero) else {
        throw writer.error ?? MediaFileError.invalidVideoFile
    }

    while !input.isReadyForMoreMediaData {
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    guard adaptor.append(secondPixelBuffer, withPresentationTime: CMTime(value: 1, timescale: 1)) else {
        throw writer.error ?? MediaFileError.invalidVideoFile
    }

    input.markAsFinished()
    await writer.finishWriting()

    if writer.status == .failed {
        throw writer.error ?? MediaFileError.invalidVideoFile
    }

    return url
}

func makePixelBuffer(width: Int, height: Int, colorOffset: UInt8) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32ARGB,
        nil,
        &pixelBuffer
    )

    guard status == kCVReturnSuccess, let pixelBuffer else {
        throw MediaFileError.invalidVideoFile
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    }

    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        throw MediaFileError.invalidVideoFile
    }

    let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * 4
            buffer[offset] = 255
            buffer[offset + 1] = UInt8((x * 4 + Int(colorOffset)) % 256)
            buffer[offset + 2] = UInt8((y * 4 + Int(colorOffset)) % 256)
            buffer[offset + 3] = 180
        }
    }

    return pixelBuffer
}

func makeJPEGData(width: Int, height: Int, quality: Double) -> Data {
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * bytesPerPixel
            pixels[offset] = UInt8(x % 256)
            pixels[offset + 1] = UInt8(y % 256)
            pixels[offset + 2] = UInt8((x + y) % 256)
            pixels[offset + 3] = 255
        }
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let image = context.makeImage()
    else {
        Issue.record("Unable to create JPEG test image")
        return Data()
    }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
        Issue.record("Unable to create JPEG destination")
        return Data()
    }

    CGImageDestinationAddImage(destination, image, [
        kCGImageDestinationLossyCompressionQuality: quality
    ] as CFDictionary)

    guard CGImageDestinationFinalize(destination) else {
        Issue.record("Unable to finalize JPEG test image")
        return Data()
    }

    return data as Data
}

func imageDimensions(atPath path: String) -> (width: Int, height: Int) {
    guard
        let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else {
        Issue.record("Unable to read image dimensions at \(path)")
        return (0, 0)
    }

    return (
        properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
        properties[kCGImagePropertyPixelHeight] as? Int ?? 0
    )
}

nonisolated struct DatabaseTestContext: Sendable {
    let databaseActor: DatabaseActor
    let paths: AccountStoragePaths
}

func makeBootstrappedDatabase(rootDirectory: URL, accountID: UserID) async throws -> (DatabaseActor, AccountStoragePaths) {
    let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
    let paths = try await storageService.prepareStorage(for: accountID)
    let databaseActor = DatabaseActor()
    _ = try await databaseActor.bootstrap(paths: paths)
    return (databaseActor, paths)
}

func makeRepository(rootDirectory: URL, accountID: UserID) async throws -> (LocalChatRepository, DatabaseTestContext) {
    let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: accountID)
    let repository = LocalChatRepository(database: databaseActor, paths: paths)
    return (repository, DatabaseTestContext(databaseActor: databaseActor, paths: paths))
}

func seedPerformanceMessages(
    databaseContext: DatabaseTestContext,
    conversationID: ConversationID,
    userID: UserID,
    count: Int
) async throws {
    let numbersCTE = """
    WITH
        digits(d) AS (
            VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9)
        ),
        numbers(value) AS (
            SELECT ones.d + tens.d * 10 + hundreds.d * 100 + thousands.d * 1000 + tenThousands.d * 10000 + 1
            FROM digits AS ones
            CROSS JOIN digits AS tens
            CROSS JOIN digits AS hundreds
            CROSS JOIN digits AS thousands
            CROSS JOIN digits AS tenThousands
        )
    """

    try await databaseContext.databaseActor.execute(
        """
        \(numbersCTE)
        INSERT INTO message_text (content_id, text, mentions_json, at_all, rich_text_json)
        SELECT
            'perf_text_' || value,
            'Perf Message ' || value,
            NULL,
            0,
            NULL
        FROM numbers
        WHERE value <= \(count);
        """,
        paths: databaseContext.paths
    )

    try await databaseContext.databaseActor.execute(
        """
        \(numbersCTE)
        INSERT INTO message (
            message_id,
            conversation_id,
            sender_id,
            client_msg_id,
            msg_type,
            direction,
            send_status,
            delivery_status,
            read_status,
            revoke_status,
            is_deleted,
            content_table,
            content_id,
            sort_seq,
            local_time
        )
        SELECT
            'perf_message_' || value,
            ?,
            ?,
            'perf_client_' || value,
            \(MessageType.text.rawValue),
            \(MessageDirection.outgoing.rawValue),
            \(MessageSendStatus.success.rawValue),
            0,
            \(MessageReadStatus.read.rawValue),
            0,
            0,
            'message_text',
            'perf_text_' || value,
            value,
            value
        FROM numbers
        WHERE value <= \(count);
        """,
        parameters: [
            .text(conversationID.rawValue),
            .text(userID.rawValue)
        ],
        paths: databaseContext.paths
    )
}

func databaseReadFails(using databaseActor: DatabaseActor, paths: AccountStoragePaths) async -> Bool {
    do {
        _ = try await databaseActor.tableNames(in: .main, paths: paths)
        return false
    } catch {
        return true
    }
}

func moveElementCount(in path: UIBezierPath) -> Int {
    var count = 0
    path.cgPath.applyWithBlock { elementPointer in
        if elementPointer.pointee.type == .moveToPoint {
            count += 1
        }
    }
    return count
}

func waitForCondition(
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    condition: @escaping () async throws -> Bool
) async throws {
    let startedAt = DispatchTime.now().uptimeNanoseconds

    while DispatchTime.now().uptimeNanoseconds - startedAt < timeoutNanoseconds {
        if try await condition() {
            return
        }

        try await Task.sleep(nanoseconds: 10_000_000)
    }

    Issue.record("Timed out waiting for condition")
}

func makeConversationRecord(
    id: ConversationID,
    userID: UserID,
    title: String = "Conversation",
    type: ConversationType = .single,
    targetID: String? = nil,
    isPinned: Bool = false,
    isMuted: Bool = false,
    unreadCount: Int = 0,
    draftText: String? = nil,
    avatarURL: String? = nil,
    sortTimestamp: Int64 = 1
) -> ConversationRecord {
    ConversationRecord(
        id: id,
        userID: userID,
        type: type,
        targetID: targetID ?? "\(id.rawValue)_target",
        title: title,
        avatarURL: avatarURL,
        lastMessageID: nil,
        lastMessageTime: sortTimestamp,
        lastMessageDigest: "Digest \(title)",
        unreadCount: unreadCount,
        draftText: draftText,
        isPinned: isPinned,
        isMuted: isMuted,
        isHidden: false,
        sortTimestamp: sortTimestamp,
        updatedAt: sortTimestamp,
        createdAt: sortTimestamp
    )
}

func makeContactRecord(
    contactID: ContactID,
    userID: UserID,
    wxid: String,
    nickname: String,
    remark: String? = nil,
    avatarURL: String? = nil,
    type: ContactType = .friend,
    isStarred: Bool = false,
    isBlocked: Bool = false,
    isDeleted: Bool = false,
    source: Int? = nil,
    extraJSON: String? = nil,
    timestamp: Int64 = 1
) -> ContactRecord {
    ContactRecord(
        contactID: contactID,
        userID: userID,
        wxid: wxid,
        nickname: nickname,
        remark: remark,
        avatarURL: avatarURL,
        type: type,
        isStarred: isStarred,
        isBlocked: isBlocked,
        isDeleted: isDeleted,
        source: source,
        extraJSON: extraJSON,
        updatedAt: timestamp,
        createdAt: timestamp
    )
}

func makeEmojiPanelState(
    recentEmojis: [EmojiAssetRecord],
    favoriteEmojis: [EmojiAssetRecord],
    packageEmojis: [EmojiAssetRecord]
) -> ChatEmojiPanelState {
    let package = EmojiPackageRecord(
        packageID: "pkg_stub",
        userID: "emoji_panel_user",
        title: "ChatBridge",
        author: "Tests",
        coverURL: nil,
        localCoverPath: nil,
        version: 1,
        status: .downloaded,
        sortOrder: 1,
        createdAt: 1,
        updatedAt: 1
    )
    return ChatEmojiPanelState(
        packages: [package],
        recentEmojis: recentEmojis,
        favoriteEmojis: favoriteEmojis,
        packageEmojisByPackageID: [package.packageID: packageEmojis]
    )
}

func makeEmojiAsset(
    emojiID: String,
    name: String,
    packageID: String? = "pkg_stub",
    isFavorite: Bool = false
) -> EmojiAssetRecord {
    EmojiAssetRecord(
        emojiID: emojiID,
        userID: "emoji_panel_user",
        packageID: packageID,
        emojiType: .package,
        name: name,
        md5: nil,
        localPath: nil,
        thumbPath: nil,
        cdnURL: nil,
        width: 128,
        height: 128,
        sizeBytes: 1024,
        useCount: 0,
        lastUsedAt: nil,
        isFavorite: isFavorite,
        isDeleted: false,
        extraJSON: nil,
        createdAt: 1,
        updatedAt: 1
    )
}

@MainActor
func button(in view: UIView, identifier: String) -> UIButton? {
    if let button = view as? UIButton, button.accessibilityIdentifier == identifier {
        return button
    }

    for subview in view.subviews {
        if let button = button(in: subview, identifier: identifier) {
            return button
        }
    }

    return nil
}

@MainActor
func button(in view: UIView, accessibilityLabel: String) -> UIButton? {
    if let button = view as? UIButton, button.accessibilityLabel == accessibilityLabel {
        return button
    }

    for subview in view.subviews {
        if let button = button(in: subview, accessibilityLabel: accessibilityLabel) {
            return button
        }
    }

    return nil
}

@MainActor
func findView(in view: UIView, identifier: String) -> UIView? {
    if view.accessibilityIdentifier == identifier {
        return view
    }

    for subview in view.subviews {
        if let matchingView = findView(in: subview, identifier: identifier) {
            return matchingView
        }
    }

    return nil
}

@MainActor
func findView<T: UIView>(ofType type: T.Type, in view: UIView) -> T? {
    if let matchingView = view as? T {
        return matchingView
    }

    for subview in view.subviews {
        if let matchingView = findView(ofType: type, in: subview) {
            return matchingView
        }
    }

    return nil
}

@MainActor
func rgbaComponents(for color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return (red, green, blue, alpha)
}

@MainActor
func findLabel(withText text: String, in view: UIView) -> UILabel? {
    if let label = view as? UILabel, label.text == text {
        return label
    }

    for subview in view.subviews {
        if let matchingLabel = findLabel(withText: text, in: subview) {
            return matchingLabel
        }
    }

    return nil
}

extension UIAlertAction {
    func triggerForTesting() {
        typealias ActionHandler = @convention(block) (UIAlertAction) -> Void
        let handler = value(forKey: "handler") as? ActionHandler
        handler?(self)
    }
}

actor CapturingLocalNotificationManager: LocalNotificationManaging {
    private var capturedPayloads: [IncomingMessageNotificationPayload] = []

    func requestAuthorization() async throws -> Bool {
        true
    }

    func scheduleIncomingMessageNotification(_ payload: IncomingMessageNotificationPayload) async throws {
        capturedPayloads.append(payload)
    }

    func payloads() -> [IncomingMessageNotificationPayload] {
        capturedPayloads
    }
}

actor CapturingApplicationBadgeManager: ApplicationBadgeManaging {
    private var capturedValues: [Int] = []

    func setApplicationIconBadgeNumber(_ count: Int) async {
        capturedValues.append(count)
    }

    func values() -> [Int] {
        capturedValues
    }
}

func collectRows(from stream: AsyncThrowingStream<ChatMessageRowState, Error>) async throws -> [ChatMessageRowState] {
    var rows: [ChatMessageRowState] = []

    for try await row in stream {
        rows.append(row)
    }

    return rows
}

func requireTextContent(_ message: StoredMessage?) throws -> String {
    let message = try #require(message)
    guard case let .text(text) = message.content else {
        Issue.record("期望文本消息内容，实际为 \(message.content)")
        return ""
    }
    return text
}

func requireTextualContent(_ message: StoredMessage?) throws -> String {
    let message = try #require(message)
    switch message.content {
    case let .text(text):
        return text
    case let .system(text), let .quote(text), let .revoked(text):
        return text ?? ""
    case .image, .voice, .video, .file, .emoji:
        Issue.record("期望可显示文本内容，实际为 \(message.content)")
        return ""
    }
}

func requireImageContent(_ message: StoredMessage?) throws -> StoredImageContent {
    let message = try #require(message)
    guard case let .image(image) = message.content else {
        Issue.record("期望图片消息内容，实际为 \(message.content)")
        return StoredImageContent(mediaID: "", localPath: "", thumbnailPath: "", width: 0, height: 0, sizeBytes: 0, format: "")
    }
    return image
}

func requireVoiceContent(_ message: StoredMessage?) throws -> StoredVoiceContent {
    let message = try #require(message)
    guard case let .voice(voice) = message.content else {
        Issue.record("期望语音消息内容，实际为 \(message.content)")
        return StoredVoiceContent(mediaID: "", localPath: "", durationMilliseconds: 0, sizeBytes: 0, format: "")
    }
    return voice
}

func requireVideoContent(_ message: StoredMessage?) throws -> StoredVideoContent {
    let message = try #require(message)
    guard case let .video(video) = message.content else {
        Issue.record("期望视频消息内容，实际为 \(message.content)")
        return StoredVideoContent(mediaID: "", localPath: "", thumbnailPath: "", durationMilliseconds: 0, width: 0, height: 0, sizeBytes: 0)
    }
    return video
}

func requireFileContent(_ message: StoredMessage?) throws -> StoredFileContent {
    let message = try #require(message)
    guard case let .file(file) = message.content else {
        Issue.record("期望文件消息内容，实际为 \(message.content)")
        return StoredFileContent(mediaID: "", localPath: "", fileName: "", fileExtension: nil, sizeBytes: 0)
    }
    return file
}

func requireEmojiContent(_ message: StoredMessage?) throws -> StoredEmojiContent {
    let message = try #require(message)
    guard case let .emoji(emoji) = message.content else {
        Issue.record("期望表情消息内容，实际为 \(message.content)")
        return StoredEmojiContent(emojiID: "", packageID: nil, emojiType: .system, name: nil, localPath: nil, thumbPath: nil, cdnURL: nil, width: nil, height: nil, sizeBytes: nil)
    }
    return emoji
}

func makeStoredTextMessage(
    messageID: MessageID = "local_message",
    conversationID: ConversationID = "local_conversation",
    senderID: UserID = "local_user",
    clientMessageID: String? = "local_client_message",
    text: String = "Hello",
    localTime: Int64 = 100
) -> StoredMessage {
    makeOutgoingStoredMessage(
        messageID: messageID,
        conversationID: conversationID,
        senderID: senderID,
        clientMessageID: clientMessageID,
        content: .text(text),
        localTime: localTime
    )
}

func makeStoredImageMessage(
    messageID: MessageID = "local_image_message",
    conversationID: ConversationID = "local_conversation",
    senderID: UserID = "local_user",
    clientMessageID: String? = "local_image_client_message",
    localTime: Int64 = 100
) -> StoredMessage {
    makeOutgoingStoredMessage(
        messageID: messageID,
        conversationID: conversationID,
        senderID: senderID,
        clientMessageID: clientMessageID,
        content: .image(StoredImageContent(
            mediaID: "image_media",
            localPath: "media/image.png",
            thumbnailPath: "media/image_thumb.jpg",
            width: 320,
            height: 240,
            sizeBytes: 4_096,
            md5: "local-image-md5",
            format: "png"
        )),
        localTime: localTime
    )
}

func makeStoredVoiceMessage(
    messageID: MessageID = "local_voice_message",
    conversationID: ConversationID = "local_conversation",
    senderID: UserID = "local_user",
    clientMessageID: String? = "local_voice_client_message",
    localTime: Int64 = 100
) -> StoredMessage {
    makeOutgoingStoredMessage(
        messageID: messageID,
        conversationID: conversationID,
        senderID: senderID,
        clientMessageID: clientMessageID,
        content: .voice(StoredVoiceContent(
            mediaID: "voice_media",
            localPath: "media/voice.m4a",
            durationMilliseconds: 1_800,
            sizeBytes: 2_048,
            format: "m4a"
        )),
        localTime: localTime
    )
}

func makeStoredVideoMessage(
    messageID: MessageID = "local_video_message",
    conversationID: ConversationID = "local_conversation",
    senderID: UserID = "local_user",
    clientMessageID: String? = "local_video_client_message",
    localTime: Int64 = 100
) -> StoredMessage {
    makeOutgoingStoredMessage(
        messageID: messageID,
        conversationID: conversationID,
        senderID: senderID,
        clientMessageID: clientMessageID,
        content: .video(StoredVideoContent(
            mediaID: "video_media",
            localPath: "media/video.mov",
            thumbnailPath: "media/video_thumb.jpg",
            durationMilliseconds: 3_600,
            width: 640,
            height: 360,
            sizeBytes: 8_192,
            md5: "local-video-md5"
        )),
        localTime: localTime
    )
}

func makeStoredFileMessage(
    messageID: MessageID = "local_file_message",
    conversationID: ConversationID = "local_conversation",
    senderID: UserID = "local_user",
    clientMessageID: String? = "local_file_client_message",
    localTime: Int64 = 100
) -> StoredMessage {
    makeOutgoingStoredMessage(
        messageID: messageID,
        conversationID: conversationID,
        senderID: senderID,
        clientMessageID: clientMessageID,
        content: .file(StoredFileContent(
            mediaID: "file_media",
            localPath: "media/report.pdf",
            fileName: "report.pdf",
            fileExtension: "pdf",
            sizeBytes: 16_384,
            md5: "local-file-md5"
        )),
        localTime: localTime
    )
}

func makeOutgoingStoredMessage(
    messageID: MessageID,
    conversationID: ConversationID,
    senderID: UserID,
    clientMessageID: String?,
    content: StoredMessageContent,
    localTime: Int64
) -> StoredMessage {
    StoredMessage(
        id: messageID,
        conversationID: conversationID,
        senderID: senderID,
        delivery: StoredMessageDelivery(
            clientMessageID: clientMessageID,
            serverMessageID: nil,
            sequence: nil
        ),
        state: StoredMessageState(
            direction: .outgoing,
            sendStatus: .sending,
            readStatus: .read,
            isRevoked: false,
            isDeleted: false,
            revokeReplacementText: nil
        ),
        timeline: StoredMessageTimeline(
            serverTime: nil,
            sortSequence: localTime,
            localTime: localTime
        ),
        content: content
    )
}

actor RecordingHTTPClient: ChatBridgeHTTPPosting {
    private let response: ServerTextMessageSendResponse?
    private let tokenRefreshResponse: ServerTokenRefreshResponse?
    private let error: ChatBridgeHTTPError?
    private let delayNanoseconds: UInt64
    private(set) var lastTextRequest: ServerTextMessageSendRequest?
    private(set) var lastImageRequest: ServerImageMessageSendRequest?
    private(set) var lastVoiceRequest: ServerVoiceMessageSendRequest?
    private(set) var lastVideoRequest: ServerVideoMessageSendRequest?
    private(set) var lastFileRequest: ServerFileMessageSendRequest?
    private(set) var lastTokenRefreshRequest: ServerTokenRefreshRequest?
    private(set) var tokenRefreshCallCount = 0

    init(
        response: ServerTextMessageSendResponse? = nil,
        tokenRefreshResponse: ServerTokenRefreshResponse? = nil,
        error: ChatBridgeHTTPError? = nil,
        delayNanoseconds: UInt64 = 0
    ) {
        self.response = response
        self.tokenRefreshResponse = tokenRefreshResponse
        self.error = error
        self.delayNanoseconds = delayNanoseconds
    }

    func postJSON<Request, Response>(
        path: String,
        body: Request,
        responseType: Response.Type
    ) async throws -> Response where Request: Encodable & Sendable, Response: Decodable & Sendable {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        if let textRequest = body as? ServerTextMessageSendRequest {
            lastTextRequest = textRequest
        }

        if let imageRequest = body as? ServerImageMessageSendRequest {
            lastImageRequest = imageRequest
        }

        if let voiceRequest = body as? ServerVoiceMessageSendRequest {
            lastVoiceRequest = voiceRequest
        }

        if let videoRequest = body as? ServerVideoMessageSendRequest {
            lastVideoRequest = videoRequest
        }

        if let fileRequest = body as? ServerFileMessageSendRequest {
            lastFileRequest = fileRequest
        }

        if let tokenRefreshRequest = body as? ServerTokenRefreshRequest {
            lastTokenRefreshRequest = tokenRefreshRequest
            tokenRefreshCallCount += 1
        }

        if let error {
            throw error
        }

        if let response = response as? Response {
            return response
        }

        if let tokenRefreshResponse = tokenRefreshResponse as? Response {
            return tokenRefreshResponse
        }

        guard let response = response as? Response else {
            throw ChatBridgeHTTPError.ackMissing
        }

        return response
    }
}

actor ExpiringTextHTTPClient: ChatBridgeHTTPPosting {
    private let tokenProvider: (@Sendable () async -> String?)?
    private let response: ServerTextMessageSendResponse?
    private let error: ChatBridgeHTTPError?
    private(set) var textSendCallCount = 0
    private(set) var mediaSendCallCount = 0
    private(set) var observedTokens: [String?] = []

    init(
        tokenProvider: (@Sendable () async -> String?)? = nil,
        response: ServerTextMessageSendResponse? = nil,
        error: ChatBridgeHTTPError? = nil
    ) {
        self.tokenProvider = tokenProvider
        self.response = response
        self.error = error
    }

    func postJSON<Request, Response>(
        path: String,
        body: Request,
        responseType: Response.Type
    ) async throws -> Response where Request: Encodable & Sendable, Response: Decodable & Sendable {
        if body is ServerTextMessageSendRequest {
            textSendCallCount += 1
            if let tokenProvider {
                observedTokens.append(await tokenProvider())
            }
        }

        if body is ServerImageMessageSendRequest
            || body is ServerVoiceMessageSendRequest
            || body is ServerVideoMessageSendRequest
            || body is ServerFileMessageSendRequest {
            mediaSendCallCount += 1
            if let tokenProvider {
                observedTokens.append(await tokenProvider())
            }
        }

        if let error {
            throw error
        }

        if textSendCallCount + mediaSendCallCount == 1 {
            throw ChatBridgeHTTPError.unacceptableStatus(401)
        }

        guard let response = response as? Response else {
            throw ChatBridgeHTTPError.ackMissing
        }

        return response
    }
}

actor TokenBox {
    private(set) var token: String

    init(token: String) {
        self.token = token
    }

    func updateToken(_ token: String) {
        self.token = token
    }
}

actor Counter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

final class InMemoryAccountSessionStore: AccountSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AccountSession?

    init(session: AccountSession? = nil) {
        self.session = session
    }

    nonisolated func loadSession() -> AccountSession? {
        lock.lock()
        defer { lock.unlock() }
        return session
    }

    nonisolated func saveSession(_ session: AccountSession) throws {
        lock.lock()
        defer { lock.unlock() }
        self.session = session
    }

    nonisolated func clearSession() {
        lock.lock()
        defer { lock.unlock() }
        session = nil
    }
}
