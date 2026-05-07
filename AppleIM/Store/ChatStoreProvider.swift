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
    /// 日志
    private let logger = AppLogger(category: .store)
    /// 缓存的仓储实例
    private var cachedRepository: LocalChatRepository?
    /// 缓存的搜索索引 Actor
    private var cachedSearchIndex: SearchIndexActor?
    /// 已准备并完成 bootstrap 的账号存储路径
    private var cachedBootstrappedPaths: AccountStoragePaths?

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
            logger.debug("ChatStoreProvider repository cache hit")
            return cachedRepository
        }

        let startUptime = ProcessInfo.processInfo.systemUptime
        logger.info("ChatStoreProvider repository create started")
        let paths = try await bootstrappedAccountStorage()
        let repository = LocalChatRepository(
            database: database,
            paths: paths,
            localNotificationManager: localNotificationManager,
            applicationBadgeManager: applicationBadgeManager
        )
        let seedStartUptime = ProcessInfo.processInfo.systemUptime
        try await DemoDataSeeder.seedIfNeeded(repository: repository, userID: accountID)
        logger.info("ChatStoreProvider demo seed checked elapsed=\(AppLogger.elapsedMilliseconds(since: seedStartUptime))")
        cachedRepository = repository
        logger.info("ChatStoreProvider repository create completed elapsed=\(AppLogger.elapsedMilliseconds(since: startUptime))")
        return repository
    }

    /// 获取搜索索引实例
    ///
    /// 与仓储共用同一套账号路径和数据库 Actor，确保 search.db 与 main.db 属于同一账号。
    func searchIndex() async throws -> SearchIndexActor {
        if let cachedSearchIndex {
            logger.debug("ChatStoreProvider searchIndex cache hit")
            return cachedSearchIndex
        }

        let startUptime = ProcessInfo.processInfo.systemUptime
        logger.info("ChatStoreProvider searchIndex create started")
        let paths = try await bootstrappedAccountStorage()
        let searchIndex = SearchIndexActor(database: database, paths: paths)
        cachedSearchIndex = searchIndex
        logger.info("ChatStoreProvider searchIndex create completed elapsed=\(AppLogger.elapsedMilliseconds(since: startUptime))")
        return searchIndex
    }

    /// 获取后台数据修复服务。
    func dataRepairService() async throws -> DataRepairService {
        let startUptime = ProcessInfo.processInfo.systemUptime
        logger.info("ChatStoreProvider dataRepairService create started")
        let paths = try await bootstrappedAccountStorage()
        let repository = try await repository()
        let searchIndex = try await searchIndex()
        logger.info("ChatStoreProvider dataRepairService create completed elapsed=\(AppLogger.elapsedMilliseconds(since: startUptime))")
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
        cachedBootstrappedPaths = nil
        try await storageService.deleteStorage(for: accountID)
        try await databaseKeyStore.deleteDatabaseKey(for: accountID)
    }

    /// 准备并 bootstrap 账号存储，同一账号生命周期内只执行一次。
    private func bootstrappedAccountStorage() async throws -> AccountStoragePaths {
        if let cachedBootstrappedPaths {
            logger.debug("ChatStoreProvider bootstrap cache hit")
            return cachedBootstrappedPaths
        }

        let startUptime = ProcessInfo.processInfo.systemUptime
        logger.info("ChatStoreProvider bootstrap started")
        let paths = try await prepareAccountStorage()
        let bootstrapStartUptime = ProcessInfo.processInfo.systemUptime
        _ = try await database.bootstrap(paths: paths)
        logger.info("ChatStoreProvider database bootstrap completed elapsed=\(AppLogger.elapsedMilliseconds(since: bootstrapStartUptime))")
        cachedBootstrappedPaths = paths
        logger.info("ChatStoreProvider bootstrap completed elapsed=\(AppLogger.elapsedMilliseconds(since: startUptime))")
        return paths
    }

    /// 准备账号存储并确保账号密钥已经存在
    private func prepareAccountStorage() async throws -> AccountStoragePaths {
        let startUptime = ProcessInfo.processInfo.systemUptime
        logger.info("ChatStoreProvider prepare storage started")
        let keyStartUptime = ProcessInfo.processInfo.systemUptime
        let databaseKey = try await databaseKeyStore.databaseKey(for: accountID)
        logger.info("ChatStoreProvider database key ready elapsed=\(AppLogger.elapsedMilliseconds(since: keyStartUptime))")
        let storageStartUptime = ProcessInfo.processInfo.systemUptime
        let paths = try await storageService.prepareStorage(for: accountID)
        logger.info("ChatStoreProvider account storage paths ready elapsed=\(AppLogger.elapsedMilliseconds(since: storageStartUptime))")
        await database.configureEncryptionKey(databaseKey, for: paths)
        logger.info("ChatStoreProvider prepare storage completed elapsed=\(AppLogger.elapsedMilliseconds(since: startUptime))")
        return paths
    }
}
