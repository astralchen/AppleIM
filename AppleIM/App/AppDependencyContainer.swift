//
//  AppDependencyContainer.swift
//  AppleIM
//

import UIKit

@MainActor
final class AppDependencyContainer {
    private let storeProvider: ChatStoreProvider
    private let demoUserID: UserID

    init(
        demoUserID: UserID = "demo_user",
        storageService: (any AccountStorageService)? = nil,
        database: DatabaseActor = DatabaseActor()
    ) throws {
        let storageService = try storageService ?? AccountStorageFactory.makeDefaultService()
        self.demoUserID = demoUserID
        self.storeProvider = ChatStoreProvider(
            accountID: demoUserID,
            storageService: storageService,
            database: database
        )
    }

    func makeConversationListViewController() -> ConversationListViewController {
        let useCase = LocalConversationListUseCase(
            userID: demoUserID,
            storeProvider: storeProvider
        )
        let viewModel = ConversationListViewModel(useCase: useCase)
        return ConversationListViewController(viewModel: viewModel)
    }
}
