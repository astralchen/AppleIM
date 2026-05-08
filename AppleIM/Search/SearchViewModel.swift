//
//  SearchViewModel.swift
//  AppleIM
//
//  搜索 UI 状态管理

import Combine
import Foundation

/// 搜索页 ViewModel
///
/// ## 职责
///
/// 1. 管理搜索 UI 状态（空闲、加载中、已加载、失败）
/// 2. 处理搜索查询输入（防抖）
/// 3. 执行搜索并更新结果
/// 4. 通过 Combine 发布状态变化给 UI
///
/// ## 并发安全
///
/// - 标记为 `@MainActor`，所有方法和属性访问都在主线程
/// - 使用 `Task` 管理异步搜索操作
/// - 使用 generation 机制防止过期结果覆盖新结果
///
/// ## 防抖机制
///
/// 用户输入后延迟 250ms 执行搜索，避免频繁查询
@MainActor
final class SearchViewModel {
    /// 搜索用例
    private let useCase: any SearchUseCase
    /// 防抖延迟（毫秒）
    private let debounceMilliseconds: Int
    /// 状态发布器
    private let stateSubject: CurrentValueSubject<SearchViewState, Never>
    /// 查询输入流
    private let querySubject = PassthroughSubject<String, Never>()
    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()
    /// 搜索任务
    private var searchTask: Task<Void, Never>?
    /// 搜索代数（用于防止过期结果）
    private var generation = 0

    /// 状态发布器
    var statePublisher: AnyPublisher<SearchViewState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    /// 当前状态
    var currentState: SearchViewState {
        stateSubject.value
    }

    /// 初始化
    ///
    /// - Parameters:
    ///   - useCase: 搜索用例
    ///   - debounceMilliseconds: 防抖延迟（毫秒），默认 250ms
    ///   - initialState: 初始状态
    init(
        useCase: any SearchUseCase,
        debounceMilliseconds: Int = 250,
        initialState: SearchViewState = SearchViewState()
    ) {
        self.useCase = useCase
        self.debounceMilliseconds = debounceMilliseconds
        self.stateSubject = CurrentValueSubject(initialState)
        bindQuery()
    }

    /// 设置搜索查询
    ///
    /// 更新查询文本，如果为空则清空结果
    ///
    /// - Parameter query: 搜索关键词
    func setQuery(_ query: String) {
        publish { state in
            state.query = query
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.phase = .idle
                state.contacts = []
                state.conversations = []
                state.messages = []
            }
        }
        querySubject.send(query)
    }

    /// 重建搜索索引
    ///
    /// 异步执行索引重建，不阻塞 UI
    func rebuildIndex() {
        Task { [useCase] in
            try? await useCase.rebuildIndex()
        }
    }

    /// 取消当前搜索
    ///
    /// 取消正在进行的搜索任务
    func cancel() {
        searchTask?.cancel()
        searchTask = nil
    }

    /// 绑定查询输入流
    ///
    /// 设置防抖和去重，延迟执行搜索
    private func bindQuery() {
        querySubject
            .debounce(for: .milliseconds(debounceMilliseconds), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                self?.performSearch(query: query)
            }
            .store(in: &cancellables)
    }

    /// 执行搜索
    ///
    /// 流程：
    /// 1. 取消之前的搜索任务
    /// 2. 递增 generation 防止过期结果
    /// 3. 更新状态为加载中
    /// 4. 调用用例执行搜索
    /// 5. 发布结果或失败状态
    ///
    /// - Parameter query: 搜索关键词
    private func performSearch(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        generation += 1
        let currentGeneration = generation

        guard !trimmedQuery.isEmpty else {
            return
        }

        publish { state in
            state.phase = .loading
        }

        searchTask = Task { [weak self, useCase] in
            do {
                let results = try await useCase.search(query: trimmedQuery)
                guard !Task.isCancelled else { return }
                self?.publishResults(results, generation: currentGeneration)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.publishFailure(generation: currentGeneration)
            }
        }
    }

    /// 发布搜索结果
    ///
    /// 检查 generation 防止过期结果覆盖新结果
    ///
    /// - Parameters:
    ///   - results: 搜索结果
    ///   - expectedGeneration: 期望的 generation
    private func publishResults(_ results: SearchResults, generation expectedGeneration: Int) {
        guard generation == expectedGeneration else {
            return
        }

        publish { state in
            state.phase = .loaded
            state.contacts = results.contacts.map(SearchResultRowState.init(record:))
            state.conversations = results.conversations.map(SearchResultRowState.init(record:))
            state.messages = results.messages.map(SearchResultRowState.init(record:))
        }
    }

    /// 发布搜索失败
    ///
    /// 检查 generation 防止过期失败覆盖新结果
    ///
    /// - Parameter expectedGeneration: 期望的 generation
    private func publishFailure(generation expectedGeneration: Int) {
        guard generation == expectedGeneration else {
            return
        }

        publish { state in
            state.phase = .failed("Unable to search")
            state.contacts = []
            state.conversations = []
            state.messages = []
        }
    }

    /// 发布状态更新
    ///
    /// - Parameter update: 状态更新闭包
    private func publish(_ update: (inout SearchViewState) -> Void) {
        var state = stateSubject.value
        update(&state)
        stateSubject.send(state)
    }
}
