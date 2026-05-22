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
    private(set) var simulateProfileChangeCallCount = 0

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

    func simulateContactProfileChange() async throws -> SimulatedContactProfilePushResult? {
        simulateProfileChangeCallCount += 1
        return nil
    }
}

actor RefreshingContactListUseCase: ContactListUseCase {
    private var didSimulateProfileChange = false
    private(set) var simulateProfileChangeCallCount = 0

    func loadContacts(query: String) async throws -> ContactListViewState {
        let row = ContactListRowState(
            contact: makeContactRecord(
                contactID: "contact_refresh",
                userID: "contact_refresh_user",
                wxid: "refresh_friend",
                nickname: didSimulateProfileChange ? "新昵称" : "旧昵称"
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
        ConversationListRowState(
            id: "single_refresh_friend",
            title: "新昵称",
            subtitle: "",
            timeText: "",
            unreadText: nil,
            isPinned: false,
            isMuted: false
        )
    }

    func simulateContactProfileChange() async throws -> SimulatedContactProfilePushResult? {
        simulateProfileChangeCallCount += 1
        didSimulateProfileChange = true
        return nil
    }
}

actor GroupOnlyContactListUseCase: ContactListUseCase {
    func loadContacts(query: String) async throws -> ContactListViewState {
        let row = ContactListRowState(
            id: "group_language",
            title: "Group Language",
            subtitle: "群聊",
            avatarURL: nil,
            type: .group,
            isStarred: false
        )
        return ContactListViewState(
            query: query,
            phase: .loaded,
            groupRows: [row],
            starredRows: [],
            contactRows: []
        )
    }

    func openConversation(for contactID: ContactID) async throws -> ConversationListRowState {
        ConversationListRowState(
            id: "group_language",
            title: "Group Language",
            subtitle: "",
            timeText: "",
            unreadText: nil,
            isPinned: false,
            isMuted: false
        )
    }

    func simulateContactProfileChange() async throws -> SimulatedContactProfilePushResult? {
        nil
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

final class ConversationListLoadingDiagnosticsSpy: ConversationListLoadingDiagnostics {
    private let messagesBox = TestLockedBox<[String]>([])

    var messages: [String] {
        messagesBox.snapshot
    }

    func log(_ message: String) {
        messagesBox.withValue { $0.append(message) }
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
