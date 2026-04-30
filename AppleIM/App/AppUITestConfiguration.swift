//
//  AppUITestConfiguration.swift
//  AppleIM
//
//  Launch-time configuration used by AppleIMUITests.
//

import Foundation

nonisolated enum AppUITestConfiguration {
    static let launchArgument = "--chatbridge-ui-testing"

    private static let runIDEnvironmentKey = "CHATBRIDGE_UI_TEST_RUN_ID"
    private static let storageRootEnvironmentKey = "CHATBRIDGE_UI_TEST_STORAGE_ROOT"
    private static let sendModeEnvironmentKey = "CHATBRIDGE_UI_TEST_SEND_MODE"

    enum SendMode: String {
        case success
        case failFirst
    }

    struct Configuration {
        let runID: String
        let sendMode: SendMode

        var demoUserID: UserID {
            "ui_test_user"
        }
    }

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

        return Configuration(runID: runID, sendMode: sendMode)
    }

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

    @MainActor
    static func makeMessageSendService(for configuration: Configuration) -> any MessageSendService {
        switch configuration.sendMode {
        case .success:
            return MockMessageSendService(delayNanoseconds: 10_000_000)
        case .failFirst:
            return FailFirstUITestMessageSendService(delayNanoseconds: 10_000_000)
        }
    }

    private static func nonEmptyValue(_ value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

actor FailFirstUITestMessageSendService: MessageSendService {
    private var shouldFailNextSend = true
    private let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func sendText(message: StoredMessage) async -> MessageSendResult {
        await send(message: message)
    }

    func sendImage(message: StoredMessage, upload: MediaUploadAck) async -> MessageSendResult {
        await send(message: message)
    }

    func sendVoice(message: StoredMessage, upload: MediaUploadAck) async -> MessageSendResult {
        await send(message: message)
    }

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
