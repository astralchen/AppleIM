//
//  ChatStoreProvider.swift
//  AppleIM
//
//  聊天存储提供者
//  负责初始化和缓存聊天仓储实例

import Foundation

/// 聊天存储提供者
///
/// 使用 actor 隔离，确保仓储初始化的线程安全
/// 缓存仓储实例，避免重复初始化
actor ChatStoreProvider {
    /// 账号 ID
    private let accountID: UserID
    /// 存储服务
    private let storageService: any AccountStorageService
    /// 数据库 Actor
    private let database: DatabaseActor
    /// 账号数据库密钥存储
    private let databaseKeyStore: any AccountDatabaseKeyStore
    /// 本地通知管理器
    private let localNotificationManager: (any LocalNotificationManaging)?
    /// App 角标管理器
    private let applicationBadgeManager: (any ApplicationBadgeManaging)?
    /// 缓存的仓储实例
    private var cachedRepository: LocalChatRepository?
    /// 缓存的搜索索引 Actor
    private var cachedSearchIndex: SearchIndexActor?

    /// 初始化存储提供者
    ///
    /// - Parameters:
    ///   - accountID: 账号 ID
    ///   - storageService: 存储服务
    ///   - database: 数据库 Actor
    init(
        accountID: UserID,
        storageService: any AccountStorageService,
        database: DatabaseActor,
        databaseKeyStore: any AccountDatabaseKeyStore = KeychainAccountDatabaseKeyStore(),
        localNotificationManager: (any LocalNotificationManaging)? = nil,
        applicationBadgeManager: (any ApplicationBadgeManaging)? = nil
    ) {
        self.accountID = accountID
        self.storageService = storageService
        self.database = database
        self.databaseKeyStore = databaseKeyStore
        self.localNotificationManager = localNotificationManager
        self.applicationBadgeManager = applicationBadgeManager
    }

    /// 获取聊天仓储实例
    ///
    /// 首次调用时初始化仓储，后续调用返回缓存实例
    ///
    /// ## 初始化流程
    ///
    /// 1. 准备存储目录和数据库文件
    /// 2. 执行数据库 bootstrap（创建表结构）
    /// 3. 创建仓储实例
    /// 4. 填充演示数据（如果需要）
    /// 5. 缓存仓储实例
    ///
    /// - Returns: 聊天仓储实例
    /// - Throws: 初始化失败时抛出错误
    func repository() async throws -> LocalChatRepository {
        if let cachedRepository {
            return cachedRepository
        }

        let paths = try await prepareAccountStorage()
        _ = try await database.bootstrap(paths: paths)
        let repository = LocalChatRepository(
            database: database,
            paths: paths,
            localNotificationManager: localNotificationManager,
            applicationBadgeManager: applicationBadgeManager
        )
        try await DemoDataSeeder.seedIfNeeded(repository: repository, userID: accountID)
        cachedRepository = repository
        return repository
    }

    /// 获取搜索索引实例
    ///
    /// 与仓储共用同一套账号路径和数据库 Actor，确保 search.db 与 main.db 属于同一账号。
    func searchIndex() async throws -> SearchIndexActor {
        if let cachedSearchIndex {
            return cachedSearchIndex
        }

        let paths = try await prepareAccountStorage()
        _ = try await database.bootstrap(paths: paths)
        let searchIndex = SearchIndexActor(database: database, paths: paths)
        cachedSearchIndex = searchIndex
        return searchIndex
    }

    /// 获取后台数据修复服务。
    func dataRepairService() async throws -> DataRepairService {
        let paths = try await prepareAccountStorage()
        _ = try await database.bootstrap(paths: paths)
        let repository = try await repository()
        let searchIndex = try await searchIndex()
        return DataRepairService(
            userID: accountID,
            database: database,
            paths: paths,
            repository: repository,
            searchIndex: searchIndex
        )
    }

    /// 删除当前账号本地存储和账号绑定密钥
    func deleteAccountStorage() async throws {
        cachedRepository = nil
        cachedSearchIndex = nil
        try await storageService.deleteStorage(for: accountID)
        try await databaseKeyStore.deleteDatabaseKey(for: accountID)
    }

    /// 准备账号存储并确保账号密钥已经存在
    private func prepareAccountStorage() async throws -> AccountStoragePaths {
        let databaseKey = try await databaseKeyStore.databaseKey(for: accountID)
        let paths = try await storageService.prepareStorage(for: accountID)
        await database.configureEncryptionKey(databaseKey, for: paths)
        return paths
    }
}
