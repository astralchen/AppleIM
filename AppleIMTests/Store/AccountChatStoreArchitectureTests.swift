import Foundation
import Testing

@testable import AppleIM

extension AppleIMTests {
    @Test func chatStoreProviderExposesAccountStoreConversationCapability() async throws {
        let rootDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
        let storeProvider = ChatStoreProvider(
            accountID: "account_store_user",
            storageService: storageService,
            database: DatabaseActor(),
            shouldSeedDemoData: false
        )

        let accountStore = try await storeProvider.accountStore()
        try await accountStore.conversations.upsertConversation(
            makeConversationRecord(
                id: "account_store_conversation",
                userID: "account_store_user",
                title: "Account Store",
                sortTimestamp: 100
            )
        )

        let conversations = try await accountStore.conversations.listConversations(for: "account_store_user")

        #expect(conversations.map { $0.id.rawValue } == ["account_store_conversation"])
        #expect(conversations.first?.title == "Account Store")
    }
}
