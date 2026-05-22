//
//  DatabaseActor.swift
//  AppleIM
//
//  数据库 Actor：通过 GRDB DatabasePool 管理数据库访问
//  所有新旧仓储统一通过 GRDB read/write/observe 入口访问数据库
//  满足 Swift 6 严格并发检查要求

import Combine
import Foundation
import GRDB

/// 数据库操作错误类型
/// 错误内部保留调试信息，对外描述始终脱敏。
nonisolated enum DatabaseActorError: Error, Equatable, Sendable {
    /// 打开数据库失败
    case openFailed(path: String, message: String)
    /// 读取数据失败
    case readFailed(path: String, message: String)
    /// 写入数据失败
    case writeFailed(path: String, message: String)
    /// 关闭数据库失败
    case closeFailed(path: String, message: String)
    /// 加密或明文迁移失败
    case encryptionFailed(path: String, message: String)
    /// 当前开发期 schema 重建失败
    case schemaRebuildFailed(path: String, message: String)
}

nonisolated extension DatabaseActorError: CustomStringConvertible, LocalizedError {
    /// 安全错误描述，不包含完整路径、SQL、绑定参数或消息明文。
    var description: String {
        safeDescription
    }

    /// 本地化错误描述
    var errorDescription: String? {
        safeDescription
    }

    /// 脱敏后的错误描述
    var safeDescription: String {
        switch self {
        case .openFailed:
            "Database open failed."
        case .readFailed:
            "Database read failed."
        case .writeFailed:
            "Database write failed."
        case .closeFailed:
            "Database close failed."
        case .encryptionFailed:
            "Database encryption failed."
        case .schemaRebuildFailed:
            "Database schema rebuild failed."
        }
    }
}

/// 数据库初始化结果
/// 只返回账号存储路径；项目未上架，不再维护旧 schema 迁移元数据。
nonisolated struct DatabaseBootstrapResult: Equatable, Sendable {
    /// 账号存储路径
    let paths: AccountStoragePaths
}

/// 数据库完整性检查结果。
nonisolated struct DatabaseIntegrityCheckResult: Equatable, Sendable {
    /// 接受检查的数据库文件类型
    let database: DatabaseFileKind
    /// SQLite integrity_check 返回的消息列表
    let messages: [String]

    /// 完整性检查是否全部返回 ok
    var isOK: Bool {
        messages == ["ok"]
    }
}

/// 数据库观察流。
///
/// DatabaseActor 内部仍用 GRDB/Combine 生成观察事件；跨 actor 边界只暴露
/// `AsyncThrowingStream`，避免业务层依赖 `AnyPublisher` 的 Sendable 假设。
nonisolated struct DatabaseObservationStream<Output: Sendable>: Sendable, AsyncSequence {
    typealias Element = Output
    typealias AsyncIterator = AsyncThrowingStream<Output, Error>.AsyncIterator

    private let stream: AsyncThrowingStream<Output, Error>

    init(_ stream: AsyncThrowingStream<Output, Error>) {
        self.stream = stream
    }

    func makeAsyncIterator() -> AsyncIterator {
        stream.makeAsyncIterator()
    }

    func map<Mapped: Sendable>(
        _ transform: @escaping @Sendable (Output) -> Mapped
    ) -> DatabaseObservationStream<Mapped> {
        DatabaseObservationStream<Mapped>(
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await value in self {
                            continuation.yield(transform(value))
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        )
    }
}

/// Combine 订阅取消盒子。
///
/// ## Sendable 审计
///
/// 保留 `@unchecked Sendable` 的原因：
/// - `AnyCancellable` 未声明 Sendable。
/// - 本类型只保存不可变取消 token，不保存可变业务状态。
/// - 暴露方法只调用 `cancel()`，取消操作幂等。
/// - 生命周期绑定到 `DatabaseObservationStream` 的 termination 回调，不参与数据库读写状态共享。
nonisolated private final class DatabaseObservationCancellableBox: @unchecked Sendable {
    private let cancellable: AnyCancellable

    init(_ cancellable: AnyCancellable) {
        self.cancellable = cancellable
    }

    func cancel() {
        cancellable.cancel()
    }
}

/// 数据库 Actor
///
/// 核心职责：
/// 1. 管理按账号数据库路径缓存的 GRDB DatabasePool
/// 2. 为 SQLCipher 数据库连接应用账号密钥
/// 3. 用当前基线 schema 初始化数据库
/// 4. 为 Store/DAO 提供 GRDB read/write/observe 入口
actor DatabaseActor {
    /// 按数据库标准路径缓存的 SQLCipher 密钥
    private var encryptionKeysByDatabasePath: [String: Data] = [:]
    /// 按数据库标准路径缓存的 GRDB 连接池
    private var poolsByDatabasePath: [String: DatabasePool] = [:]
    /// 按数据库标准路径统计实际打开连接池次数，便于测试和诊断缓存命中。
    private var openCountsByDatabasePath: [String: Int] = [:]
    /// 数据库日志
    private let logger = AppLogger(category: .database)

    /// 为账号下的所有数据库文件配置同一个 SQLCipher 密钥。
    ///
    /// 密钥只保存在 actor 隔离状态中，不写入日志、错误描述或数据库文件。
    func configureEncryptionKey(_ key: Data, for paths: AccountStoragePaths) {
        for database in DatabaseFileKind.allCases {
            encryptionKeysByDatabasePath[normalizedPath(for: url(for: database, in: paths))] = key
        }
    }

    /// 关闭指定账号下的数据库连接。
    ///
    /// 用于切换账号、登出或删除本地数据前释放 SQLite 文件句柄。
    func closeConnections(for paths: AccountStoragePaths) throws {
        for database in DatabaseFileKind.allCases {
            try closeCachedPool(at: url(for: database, in: paths))
        }
    }

    /// 关闭当前 actor 管理的全部数据库连接。
    func closeAllConnections() throws {
        for path in poolsByDatabasePath.keys.sorted() {
            try closeCachedPool(for: path)
        }
    }

    /// 返回指定账号下当前缓存的连接数量。
    func cachedConnectionCount(for paths: AccountStoragePaths) -> Int {
        DatabaseFileKind.allCases.reduce(0) { count, database in
            let path = normalizedPath(for: url(for: database, in: paths))
            return count + (poolsByDatabasePath[path] == nil ? 0 : 1)
        }
    }

    /// 返回指定数据库实际打开连接的次数。
    func openCount(for database: DatabaseFileKind, paths: AccountStoragePaths) -> Int {
        openCountsByDatabasePath[normalizedPath(for: url(for: database, in: paths))] ?? 0
    }

    /// 初始化数据库
    /// 按当前基线 schema 初始化数据库。
    ///
    /// 项目尚未上架，本地旧库不做字段迁移或数据搬运；无法用当前 SQLCipher
    /// 密钥读取，或结构不符合当前基线时，直接删除数据库及 WAL/SHM 后重建。
    func bootstrap(paths: AccountStoragePaths) async throws -> DatabaseBootstrapResult {
        try resetUnreadableDatabases(in: paths)
        try applyBaselineSchema(to: paths)
        try rebuildDatabasesThatDoNotMatchBaseline(in: paths)
        return DatabaseBootstrapResult(paths: paths)
    }

    /// 对指定数据库运行 SQLite/SQLCipher 完整性检查。
    func integrityCheck(
        in database: DatabaseFileKind,
        paths: AccountStoragePaths
    ) async throws -> DatabaseIntegrityCheckResult {
        let messages = try await read(in: database, paths: paths) { db in
            try Row.fetchAll(db, sql: "PRAGMA integrity_check;").compactMap { row -> String? in
                row["integrity_check"] as String?
            }
        }

        return DatabaseIntegrityCheckResult(
            database: database,
            messages: messages.isEmpty ? ["ok"] : messages
        )
    }

    /// 对账号下所有数据库运行完整性检查。
    func integrityCheck(paths: AccountStoragePaths) async throws -> [DatabaseIntegrityCheckResult] {
        var results: [DatabaseIntegrityCheckResult] = []

        for database in DatabaseFileKind.allCases {
            results.append(try await integrityCheck(in: database, paths: paths))
        }

        return results
    }

    /// 获取数据库中的所有表名
    /// 用于验证数据库结构或调试
    func tableNames(in database: DatabaseFileKind, paths: AccountStoragePaths) async throws -> Set<String> {
        let statement = """
        SELECT name FROM sqlite_master
        WHERE type IN ('table', 'virtual table')
        AND name NOT LIKE 'sqlite_%'
        ORDER BY name;
        """

        return try await read(in: database, paths: paths) { db in
            let rows = try Row.fetchAll(db, sql: statement)
            return Set(rows.compactMap { $0["name"] as String? })
        }
    }

    /// 返回 SQLCipher 运行时版本，用于确认当前链接的是 SQLCipher 而非系统 SQLite。
    func cipherVersion(in database: DatabaseFileKind = .main, paths: AccountStoragePaths) async throws -> String {
        try await read(in: database, paths: paths) { db in
            let rows = try Row.fetchAll(db, sql: "PRAGMA cipher_version;")
            return rows.first?["cipher_version"] as String? ?? ""
        }
    }

    /// 在受控的 GRDB 只读闭包中访问数据库。
    ///
    /// DAO 可以逐步使用 GRDB Record / Query Interface，但连接缓存、SQLCipher
    /// 加密配置和错误脱敏仍由 DatabaseActor 统一负责。
    func read<T: Sendable>(
        in database: DatabaseFileKind = .main,
        paths: AccountStoragePaths,
        _ work: @Sendable @escaping (Database) throws -> T
    ) async throws -> T {
        let databaseURL = url(for: database, in: paths)
        let pool = try databasePool(for: databaseURL)

        do {
            let grdbWork: (Database) throws -> T = { db in
                try work(db)
            }
            return try pool.read(grdbWork)
        } catch {
            throw Self.databaseActorError(
                from: error,
                path: databaseURL.path,
                fallback: .read
            )
        }
    }

    /// 在受控的 GRDB 写事务中访问数据库。
    ///
    /// 写入仍由 GRDB 串行提交；DatabasePool 主要提升并发读和观察刷新能力。
    func write<T: Sendable>(
        in database: DatabaseFileKind = .main,
        paths: AccountStoragePaths,
        _ work: @Sendable @escaping (Database) throws -> T
    ) async throws -> T {
        let databaseURL = url(for: database, in: paths)
        let pool = try databasePool(for: databaseURL)

        do {
            let grdbWork: (Database) throws -> T = { db in
                try work(db)
            }
            return try pool.write(grdbWork)
        } catch {
            throw Self.databaseActorError(
                from: error,
                path: databaseURL.path,
                fallback: .write
            )
        }
    }

    /// 创建受控的 GRDB ValueObservation publisher。
    ///
    /// 观察入口统一复用 DatabasePool、SQLCipher 密钥和错误脱敏；UI 层只能看到业务模型 publisher，
    /// 不直接接触数据库连接。
    func observe<T: Sendable>(
        in database: DatabaseFileKind = .main,
        paths: AccountStoragePaths,
        _ fetch: @Sendable @escaping (Database) throws -> T
    ) async throws -> DatabaseObservationStream<T> {
        let databaseURL = url(for: database, in: paths)
        let pool = try databasePool(for: databaseURL)
        let path = databaseURL.path
        let observation = ValueObservation.tracking(fetch)
        let publisher = observation
            .publisher(in: pool)
            .mapError { error -> Error in
                Self.databaseActorError(
                    from: error,
                    path: path,
                    fallback: .read
                )
            }
            .eraseToAnyPublisher()
        return DatabaseObservationStream(
            AsyncThrowingStream { continuation in
                let cancellable = publisher.sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            continuation.finish()
                        case .failure(let error):
                            continuation.finish(throwing: error)
                        }
                    },
                    receiveValue: { value in
                        continuation.yield(value)
                    }
                )
                let box = DatabaseObservationCancellableBox(cancellable)
                continuation.onTermination = { _ in
                    box.cancel()
                }
            }
        )
    }

    /// 删除无法用当前配置读取的旧库。
    private func resetUnreadableDatabases(in paths: AccountStoragePaths) throws {
        for database in DatabaseFileKind.allCases {
            let databaseURL = url(for: database, in: paths)
            guard FileManager.default.fileExists(atPath: databaseURL.path) else {
                continue
            }

            if canReadDatabase(at: databaseURL, applyingConfiguredKey: true) {
                continue
            }

            try resetDatabaseFiles(at: databaseURL)
        }
    }

    /// 应用当前完整基线 schema。
    private func applyBaselineSchema(to paths: AccountStoragePaths) throws {
        for database in DatabaseFileKind.allCases {
            try applyBaselineSchema(to: database, paths: paths)
        }
    }

    /// 对单个数据库应用当前完整基线 schema。
    private func applyBaselineSchema(to database: DatabaseFileKind, paths: AccountStoragePaths) throws {
        let databaseURL = url(for: database, in: paths)
        let pool = try databasePool(for: databaseURL)
        do {
            try pool.writeWithoutTransaction { db in
                try DatabaseSchema.applyBaseline(to: db, kind: database)
                try db.execute(sql: "PRAGMA user_version = \(DatabaseSchema.currentVersion);")
            }
        } catch {
            throw Self.databaseActorError(
                from: error,
                path: databaseURL.path,
                fallback: .schemaRebuild
            )
        }
    }

    /// 校验当前库是否满足完整基线；不满足就重建。
    private func rebuildDatabasesThatDoNotMatchBaseline(in paths: AccountStoragePaths) throws {
        for database in DatabaseFileKind.allCases {
            let databaseURL = url(for: database, in: paths)
            let pool = try databasePool(for: databaseURL)
            do {
                let matchesBaseline = try pool.read { db in
                    try Self.schemaMatchesBaseline(database, db: db)
                }
                guard !matchesBaseline else {
                    continue
                }
            } catch {
                throw Self.databaseActorError(
                    from: error,
                    path: databaseURL.path,
                    fallback: .read
                )
            }

            try resetDatabaseFiles(at: databaseURL)
            try applyBaselineSchema(to: database, paths: paths)
        }
    }

    /// 删除数据库本体和 SQLite 伴生文件。
    private func resetDatabaseFiles(at databaseURL: URL) throws {
        try closeCachedPool(at: databaseURL)

        let fileManager = FileManager.default
        for url in [
            databaseURL,
            URL(fileURLWithPath: "\(databaseURL.path)-wal"),
            URL(fileURLWithPath: "\(databaseURL.path)-shm")
        ] {
            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }

            do {
                try fileManager.removeItem(at: url)
            } catch {
                throw DatabaseActorError.schemaRebuildFailed(
                    path: databaseURL.path,
                    message: String(describing: error)
                )
            }
        }
    }

    /// 检查数据库是否可读。
    private func canReadDatabase(at url: URL, applyingConfiguredKey: Bool) -> Bool {
        do {
            let queue = try makeDatabaseQueue(
                at: url,
                encryptionKey: applyingConfiguredKey ? encryptionKey(for: url) : nil
            )
            defer {
                try? queue.close()
            }

            _ = try queue.read { db in
                try Row.fetchAll(db, sql: "SELECT COUNT(*) AS table_count FROM sqlite_master;")
            }
            return true
        } catch {
            return false
        }
    }

    /// 校验数据库是否符合当前基线。
    nonisolated private static func schemaMatchesBaseline(_ database: DatabaseFileKind, db: Database) throws -> Bool {
        let userVersion = try Int.fetchOne(db, sql: "PRAGMA user_version;") ?? 0
        guard userVersion == DatabaseSchema.currentVersion else {
            return false
        }

        let tables = try tableNames(db: db)
        guard DatabaseSchema.requiredTables[database, default: []].isSubset(of: tables) else {
            return false
        }

        for (table, requiredColumns) in DatabaseSchema.requiredColumns[database, default: [:]] {
            let columns = try columnNames(in: table, db: db)
            guard requiredColumns.isSubset(of: columns) else {
                return false
            }
        }

        return true
    }

    /// 获取数据库文件 URL。
    private func url(for database: DatabaseFileKind, in paths: AccountStoragePaths) -> URL {
        switch database {
        case .main:
            paths.mainDatabase
        case .search:
            paths.searchDatabase
        case .fileIndex:
            paths.fileIndexDatabase
        }
    }

    /// 获取指定数据库 URL 对应的 SQLCipher 密钥。
    private func encryptionKey(for url: URL) -> Data? {
        encryptionKeysByDatabasePath[normalizedPath(for: url)]
    }

    /// 标准化数据库路径，用于密钥缓存查找。
    private func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    /// 获取指定数据库的缓存连接池；不存在时打开并缓存。
    private func databasePool(for url: URL) throws -> DatabasePool {
        let path = normalizedPath(for: url)
        if let pool = poolsByDatabasePath[path] {
            logger.debug("Database pool cache hit database=\(url.lastPathComponent)")
            return pool
        }

        let startUptime = AppLogger.performanceSpan()
        do {
            let pool = try makeDatabasePool(at: url, encryptionKey: encryptionKey(for: url))
            poolsByDatabasePath[path] = pool
            openCountsByDatabasePath[path, default: 0] += 1
            logger.info(
                "Database pool opened database=\(url.lastPathComponent) elapsed=\(AppLogger.elapsedMilliseconds(since: startUptime))"
            )
            return pool
        } catch {
            throw Self.databaseActorError(from: error, path: url.path, fallback: .open)
        }
    }

    /// 创建 GRDB 连接池，并在每条连接准备阶段应用 SQLCipher 密钥。
    private func makeDatabasePool(at url: URL, encryptionKey: Data?) throws -> DatabasePool {
        var configuration = makeConfiguration(for: url, encryptionKey: encryptionKey)
        configuration.label = "AppleIM.pool.\(url.lastPathComponent)"
        return try DatabasePool(path: url.path, configuration: configuration)
    }

    /// 创建 GRDB 队列，并在连接准备阶段应用 SQLCipher 密钥。
    ///
    /// 仅用于 SQLCipher 可读性探测、明文转加密导出等需要短生命周期单连接的维护流程。
    private func makeDatabaseQueue(at url: URL, encryptionKey: Data?) throws -> DatabaseQueue {
        var configuration = makeConfiguration(for: url, encryptionKey: encryptionKey)
        configuration.label = "AppleIM.queue.\(url.lastPathComponent)"
        return try DatabaseQueue(path: url.path, configuration: configuration)
    }

    /// 生成数据库连接配置。
    private func makeConfiguration(for url: URL, encryptionKey: Data?) -> Configuration {
        var configuration = Configuration()
        configuration.label = "AppleIM.\(url.lastPathComponent)"
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { db in
            if let encryptionKey {
                try db.usePassphrase(encryptionKey)
            }
        }
        return configuration
    }

    /// 关闭指定 URL 的缓存连接池。
    private func closeCachedPool(at url: URL) throws {
        try closeCachedPool(for: normalizedPath(for: url))
    }

    /// 关闭指定标准化路径的缓存连接池。
    private func closeCachedPool(for path: String) throws {
        guard let pool = poolsByDatabasePath[path] else {
            return
        }

        let startUptime = AppLogger.performanceSpan()
        let url = URL(fileURLWithPath: path)
        do {
            try pool.close()
            poolsByDatabasePath[path] = nil
            logger.info(
                "Database pool closed database=\(url.lastPathComponent) elapsed=\(AppLogger.elapsedMilliseconds(since: startUptime))"
            )
        } catch {
            throw Self.databaseActorError(from: error, path: path, fallback: .close)
        }
    }

    /// 读取表名。
    nonisolated private static func tableNames(db: Database) throws -> Set<String> {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT name FROM sqlite_master
            WHERE type IN ('table', 'virtual table')
            AND name NOT LIKE 'sqlite_%';
            """
        )
        return Set(rows.compactMap { $0["name"] as String? })
    }

    /// 读取表字段名。
    nonisolated private static func columnNames(in table: String, db: Database) throws -> Set<String> {
        let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table));")
        return Set(rows.compactMap { $0["name"] as String? })
    }

    /// 将底层错误包装为现有安全错误类型。
    nonisolated private static func databaseActorError(
        from error: any Error,
        path: String,
        fallback: DatabaseActorErrorFallback
    ) -> DatabaseActorError {
        if let databaseActorError = error as? DatabaseActorError {
            return databaseActorError
        }

        let message = String(describing: error)
        switch fallback {
        case .open:
            return .openFailed(path: path, message: message)
        case .read:
            return .readFailed(path: path, message: message)
        case .write:
            return .writeFailed(path: path, message: message)
        case .close:
            return .closeFailed(path: path, message: message)
        case .encryption:
            return .encryptionFailed(path: path, message: message)
        case .schemaRebuild:
            return .schemaRebuildFailed(path: path, message: message)
        }
    }
}

nonisolated private enum DatabaseActorErrorFallback: Sendable {
    case open
    case read
    case write
    case close
    case encryption
    case schemaRebuild
}
