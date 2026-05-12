//
//  ConversationListViewModel.swift
//  AppleIM
//
//  会话列表 ViewModel
//  负责会话列表的 UI 状态管理和数据加载

import Combine
import Foundation

/// 会话列表 ViewModel
///
/// 管理会话列表的加载状态和数据，通过 Combine 发布状态变化
@MainActor
final class ConversationListViewModel {
    private static let defaultPageSize = 50

    /// UseCase 依赖
    private let useCase: any ConversationListUseCase
    /// 每页加载数量
    private let pageSize: Int
    /// 状态发布器
    private let stateSubject: CurrentValueSubject<ConversationListViewState, Never>
    /// 加载诊断日志
    private let diagnostics: any ConversationListLoadingDiagnostics
    /// 加载任务
    private var loadTask: Task<Void, Never>?
    /// 分页加载任务
    private var loadMoreTask: Task<Void, Never>?
    /// 会话设置更新任务
    private var settingTask: Task<Void, Never>?
    /// 模拟收消息任务集合
    private var simulationTasks: [UUID: Task<Void, Never>] = [:]
    /// 下一页分页游标
    private var nextCursor: ConversationPageCursor?
    /// 首屏加载代次，用于忽略已取消的旧任务回调
    private var loadGeneration = 0

    /// 状态发布器，UI 订阅此 Publisher
    var statePublisher: AnyPublisher<ConversationListViewState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    /// 当前状态快照
    var currentState: ConversationListViewState {
        stateSubject.value
    }

    init(
        useCase: any ConversationListUseCase,
        initialState: ConversationListViewState = ConversationListViewState(),
        pageSize: Int = ConversationListViewModel.defaultPageSize,
        diagnostics: any ConversationListLoadingDiagnostics = AppConversationListLoadingDiagnostics()
    ) {
        self.useCase = useCase
        self.pageSize = max(pageSize, 1)
        self.diagnostics = diagnostics
        self.stateSubject = CurrentValueSubject(initialState)
    }

    func loadIfNeeded() {
        let state = stateSubject.value
        diagnostics.log(
            "ConversationList loadIfNeeded called phase=\(state.phase.logDescription) rows=\(state.rows.count) hasTask=\(loadTask != nil)"
        )

        guard loadTask == nil else {
            diagnostics.log("ConversationList loadIfNeeded skipped reason=active-load-task")
            return
        }

        guard state.phase != .loaded || state.rows.isEmpty else {
            diagnostics.log("ConversationList loadIfNeeded skipped reason=already-loaded rows=\(state.rows.count)")
            return
        }

        load()
    }

    func load() {
        loadFirstPage(showLoading: true)
    }

    func refresh() {
        refreshFirstPageKeepingCurrentRows()
    }

    private func refreshFirstPageKeepingCurrentRows() {
        loadFirstPage(showLoading: false)
    }

    private func loadFirstPage(showLoading: Bool) {
        loadGeneration += 1
        let currentGeneration = loadGeneration

        loadTask?.cancel()
        loadMoreTask?.cancel()
        nextCursor = nil
        let startUptime = ProcessInfo.processInfo.systemUptime
        diagnostics.log(
            "ConversationList initial load started generation=\(currentGeneration) pageSize=\(pageSize) showLoading=\(showLoading)"
        )

        if showLoading {
            let loadingPublishStartUptime = ProcessInfo.processInfo.systemUptime
            publish { state in
                state.phase = .loading
                state.rows = []
                state.isLoadingMore = false
                state.hasMoreRows = false
            }
            diagnostics.log(
                "ConversationList loading state published generation=\(currentGeneration) elapsed=\(AppLogger.elapsedMilliseconds(since: loadingPublishStartUptime)) total=\(AppLogger.elapsedMilliseconds(since: startUptime))"
            )
        } else {
            let refreshPublishStartUptime = ProcessInfo.processInfo.systemUptime
            publish { state in
                state.isLoadingMore = false
            }
            diagnostics.log(
                "ConversationList refresh state published generation=\(currentGeneration) elapsed=\(AppLogger.elapsedMilliseconds(since: refreshPublishStartUptime)) total=\(AppLogger.elapsedMilliseconds(since: startUptime))"
            )
        }

        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let useCaseStartUptime = ProcessInfo.processInfo.systemUptime
                let page = try await useCase.loadConversationPage(limit: pageSize, after: nil)
                guard !Task.isCancelled, loadGeneration == currentGeneration else { return }
                diagnostics.log(
                    "ConversationList initial load useCase returned generation=\(currentGeneration) rows=\(page.rows.count) elapsed=\(AppLogger.elapsedMilliseconds(since: useCaseStartUptime)) total=\(AppLogger.elapsedMilliseconds(since: startUptime))"
                )
                let elapsed = AppLogger.elapsedMilliseconds(since: startUptime)

                let loadedPublishStartUptime = ProcessInfo.processInfo.systemUptime
                publish { state in
                    state.phase = .loaded
                    state.rows = page.rows
                    state.hasMoreRows = page.hasMore
                    state.isLoadingMore = false
                }
                diagnostics.log(
                    "ConversationList loaded state published generation=\(currentGeneration) rows=\(page.rows.count) elapsed=\(AppLogger.elapsedMilliseconds(since: loadedPublishStartUptime)) total=\(AppLogger.elapsedMilliseconds(since: startUptime))"
                )
                nextCursor = page.nextCursor
                loadTask = nil
                diagnostics.log(
                    "ConversationList initial load completed generation=\(currentGeneration) rows=\(page.rows.count) hasMore=\(page.hasMore) elapsed=\(elapsed)"
                )
                if !showLoading {
                    diagnostics.log(
                        "ConversationList background refresh completed generation=\(currentGeneration) rows=\(page.rows.count) elapsed=\(elapsed)"
                    )
                }
            } catch is CancellationError {
                guard loadGeneration == currentGeneration else { return }
                loadTask = nil
                diagnostics.log(
                    "ConversationList initial load cancelled generation=\(currentGeneration) elapsed=\(AppLogger.elapsedMilliseconds(since: startUptime))"
                )
                return
            } catch {
                guard loadGeneration == currentGeneration else { return }
                publish { state in
                    state.phase = .failed("Unable to load conversations")
                    state.isLoadingMore = false
                    state.hasMoreRows = false
                }
                loadTask = nil
                diagnostics.log(
                    "ConversationList initial load failed generation=\(currentGeneration) elapsed=\(AppLogger.elapsedMilliseconds(since: startUptime)) error=\(error)"
                )
            }
        }
    }

    func loadNextPageIfNeeded(visibleRowID: ConversationID?) {
        let state = stateSubject.value
        guard
            state.phase == .loaded,
            state.hasMoreRows,
            !state.isLoadingMore,
            loadMoreTask == nil
        else {
            return
        }

        if let visibleRowID {
            guard let visibleIndex = state.rows.firstIndex(where: { $0.id == visibleRowID }) else {
                return
            }

            let thresholdIndex = max(state.rows.count - 10, 0)
            guard visibleIndex >= thresholdIndex else {
                return
            }
        }

        publish { state in
            state.isLoadingMore = true
        }

        let cursor = nextCursor
        loadMoreTask = Task { [weak self] in
            guard let self else { return }

            do {
                let page = try await useCase.loadConversationPage(limit: pageSize, after: cursor)
                guard !Task.isCancelled else { return }

                publish { state in
                    state.phase = .loaded
                    let existingIDs = Set(state.rows.map(\.id))
                    state.rows.append(contentsOf: page.rows.filter { !existingIDs.contains($0.id) })
                    state.hasMoreRows = page.hasMore
                    state.isLoadingMore = false
                }
                nextCursor = page.nextCursor
                loadMoreTask = nil
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.isLoadingMore = false
                }
                loadMoreTask = nil
            }
        }
    }

    func setPinned(conversationID: ConversationID, isPinned: Bool) {
        updateConversationSetting {
            try await $0.setPinned(conversationID: conversationID, isPinned: isPinned)
        }
    }

    func setMuted(conversationID: ConversationID, isMuted: Bool) {
        updateConversationSetting {
            try await $0.setMuted(conversationID: conversationID, isMuted: isMuted)
        }
    }

    func markConversationReadLocally(conversationID: ConversationID) {
        publish { state in
            state.rows = state.rows.map { row in
                guard row.id == conversationID, row.unreadText != nil else {
                    return row
                }

                return ConversationListRowState(
                    id: row.id,
                    title: row.title,
                    avatarURL: row.avatarURL,
                    subtitle: row.subtitle,
                    mentionIndicatorText: row.mentionIndicatorText,
                    timeText: row.timeText,
                    unreadText: nil,
                    isPinned: row.isPinned,
                    isMuted: row.isMuted
                )
            }
        }
    }

    func simulateIncomingMessages() {
        let taskID = UUID()
        let startUptime = ProcessInfo.processInfo.systemUptime
        diagnostics.log("ConversationList simulatedPush tapped taskID=\(Self.shortLogID(taskID.uuidString))")
        simulationTasks[taskID] = Task { [weak self] in
            guard let self else { return }
            defer {
                simulationTasks[taskID] = nil
            }

            do {
                let result = try await useCase.simulateIncomingMessages()
                guard !Task.isCancelled else { return }
                if let result {
                    publishSimulationResult(result)
                    diagnostics.log(
                        "ConversationList simulatedPush optimisticPublished taskID=\(Self.shortLogID(taskID.uuidString)) conversationID=\(Self.shortLogID(result.conversationID.rawValue)) count=\(result.messageCount) elapsed=\(AppLogger.elapsedMilliseconds(since: startUptime))"
                    )
                    refreshFirstPageKeepingCurrentRows()
                }
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to simulate incoming messages")
                }
            }
        }
    }

    private func publishSimulationResult(_ result: ConversationListSimulationResult) {
        publish { state in
            state.phase = .loaded
            state.rows.removeAll { $0.id == result.conversationID }

            let insertionIndex: Int
            if result.finalRow.isPinned {
                insertionIndex = 0
            } else {
                insertionIndex = state.rows.firstIndex { !$0.isPinned } ?? state.rows.count
            }

            state.rows.insert(result.finalRow, at: insertionIndex)
        }
    }

    func cancel() {
        loadGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        loadMoreTask?.cancel()
        loadMoreTask = nil
        settingTask?.cancel()
        settingTask = nil
        simulationTasks.values.forEach { $0.cancel() }
        simulationTasks.removeAll()
    }

    private func publish(_ update: (inout ConversationListViewState) -> Void) {
        var state = stateSubject.value
        update(&state)
        stateSubject.send(state)
    }

    private func updateConversationSetting(_ operation: @escaping @Sendable (any ConversationListUseCase) async throws -> Void) {
        settingTask?.cancel()
        settingTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await operation(useCase)
                guard !Task.isCancelled else { return }
                load()
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to update conversation")
                }
            }
        }
    }

    private static func shortLogID(_ rawValue: String) -> String {
        String(rawValue.prefix(8))
    }
}

private extension ConversationListViewState.LoadingPhase {
    var logDescription: String {
        switch self {
        case .idle:
            "idle"
        case .loading:
            "loading"
        case .loaded:
            "loaded"
        case .failed:
            "failed"
        }
    }
}
