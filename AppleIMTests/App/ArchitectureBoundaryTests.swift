import Foundation
import Testing

@testable import AppleIM

extension AppleIMTests {
    @Test func productionFeatureAndAppLayersDoNotRequestWholeRepository() throws {
        let violations = try productionSwiftFiles()
            .filter { !$0.relativePath.hasPrefix("Store/") }
            .filter { !$0.relativePath.hasPrefix("Database/") }
            .filter { !$0.relativePath.hasPrefix("Security/") }
            .flatMap { file in
                file.linesContaining("storeProvider.repository()")
            }

        #expect(
            violations.isEmpty,
            "生产上层不得通过 ChatStoreProvider.repository() 获取全能仓储：\(violations.joined(separator: "\n"))"
        )
    }

    @Test func chatStoreProviderDoesNotExposeRepositoryAccessor() throws {
        let provider = try productionSwiftFiles()
            .first { $0.relativePath == "Store/ChatStoreProvider.swift" }
            .map(\.contents) ?? ""

        #expect(
            !provider.contains("func repository()"),
            "ChatStoreProvider 不应继续暴露 repository() 全能仓储入口"
        )
    }

    @Test func accountChatStoreCombinesConcreteStoreImplementations() throws {
        let accountStore = try productionSwiftFiles()
            .first { $0.relativePath == "Store/AccountChatStore.swift" }
            .map(\.contents) ?? ""
        let requiredStoreFields = [
            "let conversations: ConversationStoreImpl",
            "let messages: MessageStoreImpl",
            "let contacts: ContactStoreImpl",
            "let notificationSettings: NotificationSettingsStoreImpl",
            "let pendingJobs: PendingJobStoreImpl",
            "let mediaIndex: MediaIndexStoreImpl",
            "let emojis: EmojiStoreImpl",
            "let sync: SyncStoreImpl"
        ]
        let missingFields = requiredStoreFields.filter { !accountStore.contains($0) }

        #expect(
            missingFields.isEmpty,
            "AccountChatStore 应组合具体 Store 实现，缺少字段：\(missingFields.joined(separator: ", "))"
        )
    }

    @Test func chatViewModelDoesNotExposeUseCaseInitializer() throws {
        let chatViewModel = try productionSwiftFiles()
            .first { $0.relativePath == "Features/Chat/ViewModels/ChatViewModel.swift" }
            .map(\.contents) ?? ""

        #expect(
            !chatViewModel.contains("useCase: any ChatUseCase"),
            "ChatViewModel 不应继续暴露 ChatUseCase 兼容 initializer"
        )
    }

    @Test func productionServicesDoNotKeepUseCaseCompatibilityAliases() throws {
        let violations = try productionSwiftFiles()
            .filter { !$0.relativePath.hasPrefix("Features/Chat/UseCases/ChatUseCase") }
            .flatMap { file in
                file.linesContaining("typealias ").filter { line in
                    line.contains("UseCase") && line.contains("Service")
                }
            }

        #expect(
            violations.isEmpty,
            "生产服务不应保留 UseCase 兼容 typealias：\(violations.joined(separator: "\n"))"
        )
    }

    @Test func productionChatDoesNotDeclareLegacyUseCaseMainTypes() throws {
        let legacyDeclarations = [
            "protocol ChatUseCase",
            "struct LocalChatUseCase",
            "struct StoreBackedChatUseCase"
        ]
        let violations = try productionSwiftFiles()
            .flatMap { file in
                legacyDeclarations.flatMap { declaration in
                    file.linesContaining(declaration)
                }
            }

        #expect(
            violations.isEmpty,
            "生产 Chat 主链路不应继续声明旧 UseCase 主类型：\(violations.joined(separator: "\n"))"
        )
    }
}

private struct ProductionSwiftFile {
    let relativePath: String
    let contents: String

    func linesContaining(_ needle: String) -> [String] {
        contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { index, line in
                guard line.contains(needle) else {
                    return nil
                }
                return "\(relativePath):\(index + 1): \(line)"
            }
    }
}

private func productionSwiftFiles() throws -> [ProductionSwiftFile] {
    let appDirectory = repositoryRoot()
        .appendingPathComponent("AppleIM", isDirectory: true)
    let urls = try FileManager.default.swiftFiles(in: appDirectory)

    return try urls.map { url in
        let contents = try String(contentsOf: url, encoding: .utf8)
        let relativePath = String(url.path.dropFirst(appDirectory.path.count + 1))
        return ProductionSwiftFile(relativePath: relativePath, contents: contents)
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private extension FileManager {
    func swiftFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "swift" else {
                return nil
            }
            let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
            return resourceValues.isRegularFile == true ? url : nil
        }
    }
}
