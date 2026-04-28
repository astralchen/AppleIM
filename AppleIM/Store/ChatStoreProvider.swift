//
//  ChatStoreProvider.swift
//  AppleIM
//

import Foundation

actor ChatStoreProvider {
    private let accountID: UserID
    private let storageService: any AccountStorageService
    private let database: DatabaseActor
    private var cachedRepository: LocalChatRepository?

    init(accountID: UserID, storageService: any AccountStorageService, database: DatabaseActor) {
        self.accountID = accountID
        self.storageService = storageService
        self.database = database
    }

    func repository() async throws -> LocalChatRepository {
        if let cachedRepository {
            return cachedRepository
        }

        let paths = try await storageService.prepareStorage(for: accountID)
        _ = try await database.bootstrap(paths: paths)
        let repository = LocalChatRepository(database: database, paths: paths)
        try await DemoDataSeeder.seedIfNeeded(repository: repository, userID: accountID)
        cachedRepository = repository
        return repository
    }
}
