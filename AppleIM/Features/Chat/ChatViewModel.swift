//
//  ChatViewModel.swift
//  AppleIM
//
//  聊天页 ViewModel
//  负责聊天页的 UI 状态管理、用户输入处理、消息加载和发送
//  必须在 MainActor 上运行，保证 UI 更新的线程安全

import Combine
import Foundation

/// 聊天页 ViewModel
///
/// ## 职责
///
/// 1. 管理聊天页 UI 状态（加载中、已加载、失败）
/// 2. 处理用户输入（发送文本、发送图片、保存草稿）
/// 3. 加载消息列表（首屏加载、上拉加载历史）
/// 4. 处理消息操作（重发、删除、撤回）
/// 5. 通过 Combine 发布状态变化给 UI
///
/// ## 并发安全
///
/// - 标记为 `@MainActor`，所有方法和属性访问都在主线程
/// - 使用 `Task` 管理异步操作，页面离开时可取消
/// - 通过 `CurrentValueSubject` 发布状态，UI 订阅后自动刷新
///
/// ## 生命周期管理
///
/// - `load()`: 页面出现时调用，加载首屏消息
/// - `cancel()`: 页面消失时调用，取消所有进行中的任务
@MainActor
final class ChatViewModel {
    /// UseCase 依赖，处理业务逻辑
    private let useCase: any ChatUseCase
    /// 状态发布器，用于向 UI 发布状态变化
    private let stateSubject: CurrentValueSubject<ChatViewState, Never>
    /// 加载任务
    private var loadTask: Task<Void, Never>?
    /// 发送任务
    private var sendTask: Task<Void, Never>?
    /// 草稿保存任务
    private var draftTask: Task<Void, Never>?
    /// 消息操作任务（重发、删除、撤回）
    private var mutationTask: Task<Void, Never>?
    /// 语音播放状态回写任务
    private var voicePlaybackTask: Task<Void, Never>?
    /// 分页加载任务
    private var paginationTask: Task<Void, Never>?
    /// 每页加载的消息数量
    private let pageSize = 50

    /// 状态发布器，UI 订阅此 Publisher 以接收状态更新
    var statePublisher: AnyPublisher<ChatViewState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    /// 当前状态快照
    var currentState: ChatViewState {
        stateSubject.value
    }

    /// 初始化 ViewModel
    ///
    /// - Parameters:
    ///   - useCase: 聊天业务逻辑处理器
    ///   - title: 聊天页标题
    init(useCase: any ChatUseCase, title: String) {
        self.useCase = useCase
        self.stateSubject = CurrentValueSubject(ChatViewState(title: title))
    }

    /// 加载首屏消息
    ///
    /// 取消之前的加载任务，重置分页状态，并行加载消息和草稿
    func load() {
        loadTask?.cancel()
        paginationTask?.cancel()
        paginationTask = nil
        publish { state in
            state.phase = .loading
            state.isLoadingOlderMessages = false
            state.hasMoreOlderMessages = true
            state.paginationErrorMessage = nil
        }

        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                async let page = useCase.loadInitialMessages()
                async let draft = useCase.loadDraft()
                let loadedPage = try await page
                let loadedDraft = try await draft ?? ""
                guard !Task.isCancelled else { return }

                publish { state in
                    state.phase = .loaded
                    state.rows = loadedPage.rows
                    state.draftText = loadedDraft
                    state.hasMoreOlderMessages = loadedPage.hasMore
                    state.isLoadingOlderMessages = false
                    state.paginationErrorMessage = nil
                }
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to load messages")
                }
            }
        }
    }

    /// 加载更早的消息（上拉加载历史）
    ///
    /// 使用游标分页，基于当前最早消息的 `sortSequence` 向前加载
    /// 防止重复加载：检查是否已有加载任务、是否还有更多消息
    func loadOlderMessagesIfNeeded() {
        guard paginationTask == nil else { return }
        let state = stateSubject.value
        guard
            state.phase == .loaded,
            state.hasMoreOlderMessages,
            !state.isLoadingOlderMessages,
            let beforeSortSequence = state.rows.first?.sortSequence
        else {
            return
        }

        publish { state in
            state.isLoadingOlderMessages = true
            state.paginationErrorMessage = nil
        }

        paginationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                paginationTask = nil
            }

            do {
                let page = try await useCase.loadOlderMessages(
                    beforeSortSequence: beforeSortSequence,
                    limit: pageSize
                )
                guard !Task.isCancelled else { return }

                publish { state in
                    let existingIDs = Set(state.rows.map(\.id))
                    let olderRows = page.rows.filter { !existingIDs.contains($0.id) }
                    state.rows = olderRows + state.rows
                    state.hasMoreOlderMessages = page.hasMore
                    state.isLoadingOlderMessages = false
                    state.paginationErrorMessage = nil
                    state.phase = .loaded
                }
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.isLoadingOlderMessages = false
                    state.paginationErrorMessage = "Unable to load older messages"
                }
            }
        }
    }

    /// 发送文本消息
    ///
    /// 流程：
    /// 1. 清空草稿
    /// 2. 调用 UseCase 发送消息
    /// 3. 通过 AsyncSequence 接收消息状态更新（sending -> success/failed）
    /// 4. 实时更新 UI
    ///
    /// - Parameter text: 要发送的文本内容
    func sendText(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        sendTask?.cancel()
        sendTask = Task { [weak self] in
            guard let self else { return }

            do {
                publish { state in
                    state.draftText = ""
                }

                for try await row in useCase.sendText(trimmedText) {
                    guard !Task.isCancelled else { return }
                    upsert(row)
                }
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to send message")
                }
            }
        }
    }

    /// 发送图片消息
    ///
    /// 流程：
    /// 1. 清空草稿
    /// 2. 调用 UseCase 处理图片（压缩、生成缩略图、落盘）
    /// 3. 通过 AsyncSequence 接收消息状态更新
    /// 4. 实时更新 UI
    ///
    /// - Parameters:
    ///   - data: 图片数据
    ///   - preferredFileExtension: 首选文件扩展名
    func sendImage(data: Data, preferredFileExtension: String?) {
        sendTask?.cancel()
        sendTask = Task { [weak self] in
            guard let self else { return }

            do {
                publish { state in
                    state.draftText = ""
                }

                for try await row in useCase.sendImage(data: data, preferredFileExtension: preferredFileExtension) {
                    guard !Task.isCancelled else { return }
                    upsert(row)
                }
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to send image")
                }
            }
        }
    }

    /// 发送语音消息
    ///
    /// - Parameter recording: 已完成的本地录音文件
    func sendVoice(recording: VoiceRecordingFile) {
        sendTask?.cancel()
        sendTask = Task { [weak self] in
            guard let self else { return }

            do {
                publish { state in
                    state.draftText = ""
                }

                for try await row in useCase.sendVoice(recording: recording) {
                    guard !Task.isCancelled else { return }
                    upsert(row)
                }
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to send voice")
                }
            }
        }
    }

    /// 发送视频消息
    ///
    /// - Parameters:
    ///   - fileURL: PHPicker 或文件提供方返回的临时视频文件
    ///   - preferredFileExtension: 首选文件扩展名
    func sendVideo(fileURL: URL, preferredFileExtension: String?) {
        sendTask?.cancel()
        sendTask = Task { [weak self] in
            guard let self else { return }

            do {
                publish { state in
                    state.draftText = ""
                }

                for try await row in useCase.sendVideo(fileURL: fileURL, preferredFileExtension: preferredFileExtension) {
                    guard !Task.isCancelled else { return }
                    upsert(row)
                }
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to send video")
                }
            }
        }
    }

    /// 标记语音开始播放
    ///
    /// 播放启动成功后调用，立即更新播放态和未播放红点，再异步回写已播放状态。
    ///
    /// - Parameter messageID: 正在播放的语音消息 ID
    func voicePlaybackStarted(messageID: MessageID) {
        publish { state in
            state.rows = state.rows.map { row in
                row.withVoicePlayback(
                    isPlaying: row.id == messageID && row.isVoice,
                    isUnplayed: row.id == messageID ? false : row.isVoiceUnplayed
                )
            }
            state.phase = .loaded
        }

        voicePlaybackTask?.cancel()
        voicePlaybackTask = Task { [weak self] in
            guard let self else { return }

            do {
                guard let updatedRow = try await useCase.markVoicePlayed(messageID: messageID) else {
                    return
                }
                guard !Task.isCancelled else { return }

                let isStillPlaying = currentState.rows.first(where: { $0.id == messageID })?.isVoicePlaying == true
                upsert(updatedRow.withVoicePlayback(isPlaying: isStillPlaying, isUnplayed: false))
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to mark voice played")
                }
            }
        }
    }

    /// 标记语音停止播放
    ///
    /// - Parameter messageID: 停止播放的语音消息 ID；为空时清理全部播放态
    func voicePlaybackStopped(messageID: MessageID?) {
        publish { state in
            state.rows = state.rows.map { row in
                guard messageID == nil || row.id == messageID else {
                    return row
                }
                return row.withVoicePlayback(isPlaying: false)
            }
            state.phase = .loaded
        }
    }

    /// 保存草稿（防抖）
    ///
    /// 用户输入时调用，延迟 250ms 后保存，避免频繁写入数据库
    ///
    /// - Parameter text: 草稿文本
    func saveDraft(_ text: String) {
        publish { state in
            state.draftText = text
        }

        draftTask?.cancel()
        draftTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                try await useCase.saveDraft(text)
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to save draft")
                }
            }
        }
    }

    /// 立即保存草稿（无防抖）
    ///
    /// 页面离开时调用，立即保存当前草稿
    ///
    /// - Parameter text: 草稿文本
    func flushDraft(_ text: String) {
        publish { state in
            state.draftText = text
        }

        draftTask?.cancel()
        let useCase = self.useCase
        draftTask = Task {
            try? await useCase.saveDraft(text)
        }
    }

    /// 重发失败的消息
    ///
    /// - Parameter messageID: 要重发的消息 ID
    func resend(messageID: MessageID) {
        mutationTask?.cancel()
        mutationTask = Task { [weak self] in
            guard let self else { return }

            do {
                for try await row in useCase.resend(messageID: messageID) {
                    guard !Task.isCancelled else { return }
                    upsert(row)
                }
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to resend message")
                }
            }
        }
    }

    /// 删除消息（本地逻辑删除）
    ///
    /// - Parameter messageID: 要删除的消息 ID
    func delete(messageID: MessageID) {
        mutationTask?.cancel()
        mutationTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await useCase.delete(messageID: messageID)
                guard !Task.isCancelled else { return }

                publish { state in
                    state.rows.removeAll { $0.id == messageID }
                    state.phase = .loaded
                }
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to delete message")
                }
            }
        }
    }

    /// 撤回消息
    ///
    /// 撤回后重新加载消息列表，因为撤回会改变消息内容
    ///
    /// - Parameter messageID: 要撤回的消息 ID
    func revoke(messageID: MessageID) {
        mutationTask?.cancel()
        mutationTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await useCase.revoke(messageID: messageID)
                let page = try await useCase.loadInitialMessages()
                guard !Task.isCancelled else { return }

                publish { state in
                    state.rows = page.rows
                    state.hasMoreOlderMessages = page.hasMore
                    state.isLoadingOlderMessages = false
                    state.paginationErrorMessage = nil
                    state.phase = .loaded
                }
            } catch is CancellationError {
                return
            } catch {
                publish { state in
                    state.phase = .failed("Unable to revoke message")
                }
            }
        }
    }

    /// 取消所有进行中的任务
    ///
    /// 页面消失时调用，释放资源
    func cancel() {
        loadTask?.cancel()
        sendTask?.cancel()
        draftTask?.cancel()
        mutationTask?.cancel()
        paginationTask?.cancel()
        voicePlaybackTask?.cancel()
        loadTask = nil
        sendTask = nil
        draftTask = nil
        mutationTask = nil
        paginationTask = nil
        voicePlaybackTask = nil
    }

    /// 更新或插入消息行
    ///
    /// 如果消息已存在则更新，否则追加到末尾
    ///
    /// - Parameter row: 消息行状态
    private func upsert(_ row: ChatMessageRowState) {
        publish { state in
            if let index = state.rows.firstIndex(where: { $0.id == row.id }) {
                state.rows[index] = row
            } else {
                state.rows.append(row)
            }

            state.phase = .loaded
        }
    }

    /// 发布状态更新
    ///
    /// - Parameter update: 状态更新闭包
    private func publish(_ update: (inout ChatViewState) -> Void) {
        var state = stateSubject.value
        update(&state)
        stateSubject.send(state)
    }
}
