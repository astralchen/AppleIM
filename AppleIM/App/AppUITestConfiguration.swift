//
//  AppUITestConfiguration.swift
//  AppleIM
//
//  UI 测试启动配置
//

import Foundation

/// UI 测试配置
///
/// 用于在 UI 测试运行时配置应用行为
nonisolated enum AppUITestConfiguration {
    /// UI 测试启动参数
    static let launchArgument = "--chatbridge-ui-testing"

    /// 测试运行 ID 环境变量键
    private static let runIDEnvironmentKey = "CHATBRIDGE_UI_TEST_RUN_ID"
    /// 存储根目录环境变量键
    private static let storageRootEnvironmentKey = "CHATBRIDGE_UI_TEST_STORAGE_ROOT"
    /// 发送模式环境变量键
    private static let sendModeEnvironmentKey = "CHATBRIDGE_UI_TEST_SEND_MODE"
    /// 重置会话环境变量键
    private static let resetSessionEnvironmentKey = "CHATBRIDGE_UI_TEST_RESET_SESSION"

    /// 消息发送模式
    enum SendMode: String {
        /// 总是成功
        case success
        /// 第一次失败，后续成功
        case failFirst
    }

    /// UI 测试配置
    struct Configuration {
        /// 测试运行 ID（用于隔离存储）
        let runID: String
        /// 消息发送模式
        let sendMode: SendMode
        /// 是否重置会话
        let resetSession: Bool
    }

    /// 当前配置
    ///
    /// 从进程参数和环境变量读取配置
    ///
    /// - Returns: 如果包含 UI 测试启动参数，返回配置；否则返回 nil
    static var current: Configuration? {
        let processInfo = ProcessInfo.processInfo
        guard processInfo.arguments.contains(launchArgument) else {
            return nil
        }

        let environment = processInfo.environment
        let runID = environment[runIDEnvironmentKey]
            .flatMap(Self.nonEmptyValue)
            ?? UUID().uuidString
        let sendMode = environment[sendModeEnvironmentKey]
            .flatMap(SendMode.init(rawValue:))
            ?? .success
        let resetSession = environment[resetSessionEnvironmentKey] != "0"

        return Configuration(runID: runID, sendMode: sendMode, resetSession: resetSession)
    }

    /// 创建存储服务
    ///
    /// 为 UI 测试创建隔离的存储服务，每次运行使用独立的目录
    ///
    /// - Parameter configuration: UI 测试配置
    /// - Returns: 账号存储服务
    /// - Throws: 文件系统错误
    @MainActor
    static func makeStorageService(for configuration: Configuration) throws -> any AccountStorageService {
        let rootDirectory: URL
        if let rootPath = ProcessInfo.processInfo.environment[storageRootEnvironmentKey]
            .flatMap(Self.nonEmptyValue) {
            rootDirectory = URL(fileURLWithPath: rootPath, isDirectory: true)
        } else {
            rootDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ChatBridgeUITests", isDirectory: true)
                .appendingPathComponent(configuration.runID, isDirectory: true)
        }

        if FileManager.default.fileExists(atPath: rootDirectory.path) {
            try FileManager.default.removeItem(at: rootDirectory)
        }

        return FileAccountStorageService(rootDirectory: rootDirectory)
    }

    /// 创建消息发送服务
    ///
    /// 根据配置的发送模式创建模拟的消息发送服务
    ///
    /// - Parameter configuration: UI 测试配置
    /// - Returns: 消息发送服务
    @MainActor
    static func makeMessageSendService(for configuration: Configuration) -> any MessageSendService {
        switch configuration.sendMode {
        case .success:
            return MockMessageSendService(delayNanoseconds: 10_000_000)
        case .failFirst:
            return FailFirstUITestMessageSendService(delayNanoseconds: 10_000_000)
        }
    }

    /// 获取非空值
    ///
    /// 清理空白字符，如果为空返回 nil
    ///
    /// - Parameter value: 输入字符串
    /// - Returns: 非空字符串或 nil
    private static func nonEmptyValue(_ value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

/// UI 测试消息发送服务（第一次失败）
///
/// 用于测试消息发送失败和重试场景
actor FailFirstUITestMessageSendService: MessageSendService {
    /// 是否应该让下一次发送失败
    private var shouldFailNextSend = true
    /// 延迟时间（纳秒）
    private let delayNanoseconds: UInt64

    /// 初始化
    ///
    /// - Parameter delayNanoseconds: 延迟时间（纳秒）
    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    /// 发送文本消息
    func sendText(message: StoredMessage) async -> MessageSendResult {
        await send(message: message)
    }

    /// 发送图片消息
    func sendImage(message: StoredMessage, upload: MediaUploadAck) async -> MessageSendResult {
        await send(message: message)
    }

    /// 发送语音消息
    func sendVoice(message: StoredMessage, upload: MediaUploadAck) async -> MessageSendResult {
        await send(message: message)
    }

    /// 发送视频消息
    func sendVideo(message: StoredMessage, upload: MediaUploadAck) async -> MessageSendResult {
        await send(message: message)
    }

    /// 发送文件消息
    func sendFile(message: StoredMessage, upload: MediaUploadAck) async -> MessageSendResult {
        await send(message: message)
    }

    /// 发送表情消息
    func sendEmoji(message: StoredMessage) async -> MessageSendResult {
        await send(message: message)
    }

    /// 发送消息（内部实现）
    ///
    /// 第一次调用返回失败，后续调用返回成功
    ///
    /// - Parameter message: 消息
    /// - Returns: 发送结果
    private func send(message: StoredMessage) async -> MessageSendResult {
        do {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        } catch {
            return .failure(.unknown)
        }

        if shouldFailNextSend {
            shouldFailNextSend = false
            return .failure(.timeout)
        }

        return .success(
            MessageSendAck(
                serverMessageID: "ui_test_server_\(message.id.rawValue)",
                sequence: message.sortSequence,
                serverTime: Int64(Date().timeIntervalSince1970)
            )
        )
    }
}
