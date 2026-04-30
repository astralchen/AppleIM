//
//  DatabaseActor.swift
//  AppleIM
//
//  数据库 Actor：串行化所有数据库操作，保证线程安全
//  使用 actor 隔离确保数据库连接、事务、迁移不会并发执行
//  满足 Swift 6 严格并发检查要求

import Foundation
import SQLCipher

/// 数据库操作错误类型
/// 所有错误都包含路径和详细错误信息，便于调试
nonisolated enum DatabaseActorError: Error, Equatable, Sendable {
    case openFailed(path: String, message: String)        // 打开数据库失败
    case executeFailed(path: String, statement: String, message: String)  // 执行 SQL 失败
    case prepareFailed(path: String, statement: String, message: String)  // 预编译 SQL 失败
    case bindFailed(path: String, statement: String, message: String)     // 绑定参数失败
    case readFailed(path: String, statement: String, message: String)     // 读取数据失败
    case closeFailed(path: String, message: String)       // 关闭数据库失败
    case encryptionFailed(path: String, message: String)  // 加密或明文迁移失败
}

nonisolated extension DatabaseActorError: CustomStringConvertible, LocalizedError {
    /// 安全错误描述，不包含完整路径、SQL、绑定参数或消息明文。
    var description: String {
        safeDescription
    }

    var errorDescription: String? {
        safeDescription
    }

    var safeDescription: String {
        switch self {
        case .openFailed:
            "Database open failed."
        case .executeFailed:
            "Database execute failed."
        case .prepareFailed:
            "Database prepare failed."
        case .bindFailed:
            "Database bind failed."
        case .readFailed:
            "Database read failed."
        case .closeFailed:
            "Database close failed."
        case .encryptionFailed:
            "Database encryption failed."
        }
    }
}

/// 数据库迁移元数据
/// 记录当前数据库版本、迁移历史、维护时间等信息
/// 存储在 migration_meta 表和 migration_meta.json 文件中
nonisolated struct MigrationMetadata: Codable, Equatable, Sendable {
    let schemaVersion: Int           // 当前 schema 版本号
    let lastMigrationID: String      // 最后执行的迁移脚本 ID
    let lastVacuumAt: Int?           // 最近一次 VACUUM 压缩时间
    let lastIntegrityCheckAt: Int?   // 最近一次完整性检查时间
    let ftsRebuildVersion: Int       // FTS 索引重建版本
    let appliedScriptIDs: [String]   // 已应用的迁移脚本 ID 列表
}

/// 数据库初始化结果
/// 包含账号存储路径和迁移元数据
nonisolated struct DatabaseBootstrapResult: Equatable, Sendable {
    let paths: AccountStoragePaths   // 账号存储路径
    let metadata: MigrationMetadata  // 迁移元数据
}

/// 数据库完整性检查结果。
nonisolated struct DatabaseIntegrityCheckResult: Equatable, Sendable {
    let database: DatabaseFileKind
    let messages: [String]

    var isOK: Bool {
        messages == ["ok"]
    }
}

/// 数据库 Actor
///
/// 核心职责：
/// 1. 串行化所有数据库操作，避免并发写入冲突
/// 2. 管理数据库连接的打开和关闭
/// 3. 执行事务，保证原子性
/// 4. 处理数据库迁移和版本管理
///
/// 重要说明：
/// - 所有公开方法都是 async，调用时会自动切换到 actor 的串行执行队列
/// - 数据库连接在每次操作时打开，操作完成后立即关闭，避免长时间持有连接
/// - 事务使用 BEGIN/COMMIT/ROLLBACK 手动管理，失败时自动回滚
/// - 参数绑定使用预编译语句，防止 SQL 注入
actor DatabaseActor {
    private var encryptionKeysByDatabasePath: [String: Data] = [:]

    /// 为账号下的所有数据库文件配置同一个 SQLCipher 密钥。
    ///
    /// 密钥只保存在 actor 隔离状态中，不写入日志、错误描述或数据库文件。
    func configureEncryptionKey(_ key: Data, for paths: AccountStoragePaths) {
        for database in DatabaseFileKind.allCases {
            encryptionKeysByDatabasePath[normalizedPath(for: url(for: database, in: paths))] = key
        }
    }

    /// 初始化数据库
    /// 执行初始建表脚本，创建 migration_meta 表和元数据文件
    ///
    /// - Parameter paths: 账号存储路径
    /// - Returns: 初始化结果，包含路径和元数据
    /// - Throws: 数据库操作失败时抛出错误
    func bootstrap(paths: AccountStoragePaths) async throws -> DatabaseBootstrapResult {
        let previousMetadata = try? await loadMigrationMetadata(paths: paths)
        try migratePlaintextDatabasesIfNeeded(in: paths)
        try applyInitialScripts(to: paths)
        try applyIdempotentMigrations(to: paths)

        let persistedMetadata = previousMetadata ?? (try? loadMigrationMetadataFromDatabase(in: paths))
        let metadata = MigrationMetadata(
            schemaVersion: DatabaseSchema.currentVersion,
            lastMigrationID: DatabaseSchema.allScripts.last?.id ?? "",
            lastVacuumAt: persistedMetadata?.lastVacuumAt,
            lastIntegrityCheckAt: persistedMetadata?.lastIntegrityCheckAt,
            ftsRebuildVersion: persistedMetadata?.ftsRebuildVersion ?? 0,
            appliedScriptIDs: DatabaseSchema.allScripts.map(\.id)
        )

        try await persistMigrationMetadata(metadata, in: paths)
        try persist(metadata: metadata, in: paths)

        return DatabaseBootstrapResult(paths: paths, metadata: metadata)
    }

    /// 加载迁移元数据
    /// 从 migration_meta.json 文件读取元数据
    ///
    /// - Parameter paths: 账号存储路径
    /// - Returns: 迁移元数据
    /// - Throws: 文件读取或解码失败时抛出错误
    func loadMigrationMetadata(paths: AccountStoragePaths) async throws -> MigrationMetadata {
        let data = try Data(contentsOf: metadataURL(in: paths))
        return try JSONDecoder().decode(MigrationMetadata.self, from: data)
    }

    /// 对指定数据库运行 SQLite/SQLCipher 完整性检查。
    func integrityCheck(
        in database: DatabaseFileKind,
        paths: AccountStoragePaths
    ) async throws -> DatabaseIntegrityCheckResult {
        let rows = try await query("PRAGMA integrity_check;", in: database, paths: paths)
        let messages = rows.compactMap { row -> String? in
            row.string("integrity_check") ?? row.values.values.compactMap { value -> String? in
                guard case let .text(text) = value else {
                    return nil
                }

                return text
            }.first
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

    /// 更新维护元数据，用于记录后台修复任务的检查时间和 FTS 重建版本。
    func recordMaintenanceMetadata(
        paths: AccountStoragePaths,
        integrityCheckedAt: Int64?,
        ftsRebuildVersion: Int?
    ) async throws -> MigrationMetadata {
        let previousMetadata = (try? await loadMigrationMetadata(paths: paths))
            ?? (try? loadMigrationMetadataFromDatabase(in: paths))
        let metadata = MigrationMetadata(
            schemaVersion: DatabaseSchema.currentVersion,
            lastMigrationID: DatabaseSchema.allScripts.last?.id ?? "",
            lastVacuumAt: previousMetadata?.lastVacuumAt,
            lastIntegrityCheckAt: integrityCheckedAt.map(Int.init) ?? previousMetadata?.lastIntegrityCheckAt,
            ftsRebuildVersion: ftsRebuildVersion ?? previousMetadata?.ftsRebuildVersion ?? 0,
            appliedScriptIDs: DatabaseSchema.allScripts.map(\.id)
        )

        try await persistMigrationMetadata(metadata, in: paths)
        try persist(metadata: metadata, in: paths)
        return metadata
    }

    /// 获取数据库中的所有表名
    /// 用于验证数据库结构或调试
    ///
    /// - Parameters:
    ///   - database: 数据库类型（main/search/fileIndex）
    ///   - paths: 账号存储路径
    /// - Returns: 表名集合
    /// - Throws: 查询失败时抛出错误
    func tableNames(in database: DatabaseFileKind, paths: AccountStoragePaths) async throws -> Set<String> {
        let statement = """
        SELECT name FROM sqlite_master
        WHERE type IN ('table', 'virtual table')
        AND name NOT LIKE 'sqlite_%'
        ORDER BY name;
        """

        let rows = try await query(statement, in: database, paths: paths)
        return Set(rows.compactMap { $0.string("name") })
    }

    /// 返回 SQLCipher 运行时版本，用于确认当前链接的是 SQLCipher 而非系统 SQLite。
    func cipherVersion(in database: DatabaseFileKind = .main, paths: AccountStoragePaths) async throws -> String {
        let rows = try await query("PRAGMA cipher_version;", in: database, paths: paths)
        return rows.first?.values.values.compactMap { value -> String? in
            guard case let .text(text) = value else {
                return nil
            }

            return text
        }.first ?? ""
    }

    /// 执行单条 SQL 语句（不返回结果）
    /// 用于 INSERT、UPDATE、DELETE 等操作
    ///
    /// - Parameters:
    ///   - statement: SQL 语句
    ///   - parameters: 绑定参数
    ///   - database: 数据库类型，默认为 main
    ///   - paths: 账号存储路径
    /// - Throws: 执行失败时抛出错误
    func execute(
        _ statement: String,
        parameters: [SQLiteValue] = [],
        in database: DatabaseFileKind = .main,
        paths: AccountStoragePaths
    ) async throws {
        try executePrepared(statement, parameters: parameters, at: url(for: database, in: paths))
    }

    /// 执行查询语句（返回结果集）
    /// 用于 SELECT 操作
    ///
    /// - Parameters:
    ///   - statement: SQL 查询语句
    ///   - parameters: 绑定参数
    ///   - database: 数据库类型，默认为 main
    ///   - paths: 账号存储路径
    /// - Returns: 查询结果行数组
    /// - Throws: 查询失败时抛出错误
    func query(
        _ statement: String,
        parameters: [SQLiteValue] = [],
        in database: DatabaseFileKind = .main,
        paths: AccountStoragePaths
    ) async throws -> [SQLiteRow] {
        try query(statement, parameters: parameters, at: url(for: database, in: paths))
    }

    /// 执行事务
    /// 将多条 SQL 语句包装在一个事务中，保证原子性
    ///
    /// 重要说明：
    /// - 所有语句要么全部成功，要么全部回滚
    /// - 失败时自动执行 ROLLBACK
    /// - 适用于消息入库 + 会话摘要更新等需要原子性的操作
    ///
    /// - Parameters:
    ///   - statements: SQL 语句数组
    ///   - database: 数据库类型，默认为 main
    ///   - paths: 账号存储路径
    /// - Throws: 任何语句执行失败时抛出错误并回滚
    func performTransaction(
        _ statements: [SQLiteStatement],
        in database: DatabaseFileKind = .main,
        paths: AccountStoragePaths
    ) async throws {
        let databaseURL = url(for: database, in: paths)
        let handle = try openDatabase(at: databaseURL)
        defer {
            try? closeDatabase(handle, at: databaseURL)
        }

        try executeRaw("BEGIN TRANSACTION;", using: handle, at: databaseURL)

        do {
            for statement in statements {
                try executePrepared(statement.sql, parameters: statement.parameters, using: handle, at: databaseURL)
            }

            try executeRaw("COMMIT;", using: handle, at: databaseURL)
        } catch {
            try? executeRaw("ROLLBACK;", using: handle, at: databaseURL)
            throw error
        }
    }

    /// 应用初始化脚本
    ///
    /// 在事务中执行所有初始化脚本，创建表结构
    ///
    /// - Parameter paths: 账号存储路径
    /// - Throws: 脚本执行失败时抛出错误
    private func applyInitialScripts(to paths: AccountStoragePaths) throws {
        for script in DatabaseSchema.initialScripts {
            let databaseURL = url(for: script.database, in: paths)
            let handle = try openDatabase(at: databaseURL)
            defer {
                try? closeDatabase(handle, at: databaseURL)
            }

            try executeRaw("BEGIN TRANSACTION;", using: handle, at: databaseURL)

            do {
                for statement in script.statements {
                    try executeRaw(statement, using: handle, at: databaseURL)
                }

                try executeRaw("COMMIT;", using: handle, at: databaseURL)
            } catch {
                try? executeRaw("ROLLBACK;", using: handle, at: databaseURL)
                throw error
            }
        }
    }

    /// 将已有明文 SQLite 库迁移为 SQLCipher 加密库。
    ///
    /// 新安装的 0 字节数据库会直接按加密连接初始化；只有“带 key 打不开、无 key 可读”的旧库才会导出迁移。
    private func migratePlaintextDatabasesIfNeeded(in paths: AccountStoragePaths) throws {
        for database in DatabaseFileKind.allCases {
            let databaseURL = url(for: database, in: paths)
            guard encryptionKey(for: databaseURL) != nil else {
                continue
            }

            guard FileManager.default.fileExists(atPath: databaseURL.path) else {
                continue
            }

            if canReadDatabase(at: databaseURL, applyingConfiguredKey: true) {
                continue
            }

            guard canReadDatabase(at: databaseURL, applyingConfiguredKey: false) else {
                throw DatabaseActorError.encryptionFailed(
                    path: databaseURL.path,
                    message: "Database cannot be opened with the configured key or as plaintext."
                )
            }

            try migratePlaintextDatabase(at: databaseURL)
        }
    }

    private func migratePlaintextDatabase(at databaseURL: URL) throws {
        guard let key = encryptionKey(for: databaseURL) else {
            return
        }

        let fileManager = FileManager.default
        let tempURL = databaseURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(databaseURL.lastPathComponent).encrypted-\(UUID().uuidString)")
        let backupURL = databaseURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(databaseURL.lastPathComponent).plaintext-backup-\(UUID().uuidString)")

        defer {
            try? fileManager.removeItem(at: tempURL)
            try? fileManager.removeItem(at: backupURL)
        }

        do {
            let handle = try openDatabase(at: databaseURL, applyingConfiguredKey: false)
            defer {
                try? closeDatabase(handle, at: databaseURL)
            }

            try executeRaw(
                "ATTACH DATABASE '\(Self.escapedSQLString(tempURL.path))' AS encrypted;",
                using: handle,
                at: databaseURL
            )
            try applyEncryptionKey(key, to: handle, databaseName: "encrypted", at: databaseURL)
            try executeRaw("SELECT sqlcipher_export('encrypted');", using: handle, at: databaseURL)
            try executeRaw("DETACH DATABASE encrypted;", using: handle, at: databaseURL)
        }

        guard canReadDatabase(at: tempURL, applyingKey: key) else {
            throw DatabaseActorError.encryptionFailed(
                path: databaseURL.path,
                message: "Encrypted database verification failed."
            )
        }

        try fileManager.moveItem(at: databaseURL, to: backupURL)
        do {
            try fileManager.moveItem(at: tempURL, to: databaseURL)
        } catch {
            if fileManager.fileExists(atPath: backupURL.path), !fileManager.fileExists(atPath: databaseURL.path) {
                try? fileManager.moveItem(at: backupURL, to: databaseURL)
            }

            throw DatabaseActorError.encryptionFailed(
                path: databaseURL.path,
                message: "Encrypted database replacement failed."
            )
        }
    }

    private func canReadDatabase(at url: URL, applyingConfiguredKey: Bool) -> Bool {
        do {
            let handle = try openDatabase(at: url, applyingConfiguredKey: applyingConfiguredKey)
            defer {
                try? closeDatabase(handle, at: url)
            }

            _ = try query("SELECT COUNT(*) AS table_count FROM sqlite_master;", parameters: [], using: handle, at: url)
            return true
        } catch {
            return false
        }
    }

    private func canReadDatabase(at url: URL, applyingKey key: Data) -> Bool {
        do {
            let handle = try openDatabase(at: url, encryptionKey: key)
            defer {
                try? closeDatabase(handle, at: url)
            }

            _ = try query("SELECT COUNT(*) AS table_count FROM sqlite_master;", parameters: [], using: handle, at: url)
            return true
        } catch {
            return false
        }
    }

    /// 应用可重复执行的轻量迁移
    ///
    /// 初始建表脚本使用 `CREATE TABLE IF NOT EXISTS`，不会自动给旧表补列。
    /// 这里通过表结构检查补齐新增字段，保证已有账号目录再次启动后也能升级。
    private func applyIdempotentMigrations(to paths: AccountStoragePaths) throws {
        try addColumnIfMissing(
            table: "notification_setting",
            column: "badge_enabled",
            definition: "INTEGER DEFAULT 1",
            in: .main,
            paths: paths
        )
        try addColumnIfMissing(
            table: "notification_setting",
            column: "badge_include_muted",
            definition: "INTEGER DEFAULT 1",
            in: .main,
            paths: paths
        )
        try executeIdempotentStatement(
            "CREATE INDEX IF NOT EXISTS idx_conversation_user_visible_sort ON conversation(user_id, is_hidden, is_pinned DESC, sort_ts DESC);",
            in: .main,
            paths: paths
        )
        try executeIdempotentStatement(
            "CREATE INDEX IF NOT EXISTS idx_message_conversation_visible_sort ON message(conversation_id, is_deleted, sort_seq DESC);",
            in: .main,
            paths: paths
        )
    }

    /// 执行幂等 SQL
    private func executeIdempotentStatement(
        _ statement: String,
        in database: DatabaseFileKind,
        paths: AccountStoragePaths
    ) throws {
        let databaseURL = url(for: database, in: paths)
        let handle = try openDatabase(at: databaseURL)
        defer {
            try? closeDatabase(handle, at: databaseURL)
        }

        try executeRaw(statement, using: handle, at: databaseURL)
    }

    /// 按需补充字段
    private func addColumnIfMissing(
        table: String,
        column: String,
        definition: String,
        in database: DatabaseFileKind,
        paths: AccountStoragePaths
    ) throws {
        let databaseURL = url(for: database, in: paths)
        let handle = try openDatabase(at: databaseURL)
        defer {
            try? closeDatabase(handle, at: databaseURL)
        }

        let columns = try columnNames(in: table, using: handle, at: databaseURL)
        guard !columns.contains(column) else {
            return
        }

        try executeRaw("ALTER TABLE \(table) ADD COLUMN \(column) \(definition);", using: handle, at: databaseURL)
    }

    /// 读取表字段名
    private func columnNames(in table: String, using handle: OpaquePointer, at url: URL) throws -> Set<String> {
        let rows = try query("PRAGMA table_info(\(table));", parameters: [], using: handle, at: url)
        return Set(rows.compactMap { $0.string("name") })
    }

    private func loadMigrationMetadataFromDatabase(in paths: AccountStoragePaths) throws -> MigrationMetadata? {
        let databaseURL = url(for: .main, in: paths)
        let handle = try openDatabase(at: databaseURL)
        defer {
            try? closeDatabase(handle, at: databaseURL)
        }

        let rows = try query(
            """
            SELECT
                schema_version,
                last_migration_id,
                last_vacuum_at,
                last_integrity_check_at,
                fts_rebuild_version
            FROM migration_meta
            LIMIT 1;
            """,
            parameters: [],
            using: handle,
            at: databaseURL
        )

        guard let row = rows.first else {
            return nil
        }

        return MigrationMetadata(
            schemaVersion: row.int("schema_version") ?? DatabaseSchema.currentVersion,
            lastMigrationID: row.string("last_migration_id") ?? DatabaseSchema.allScripts.last?.id ?? "",
            lastVacuumAt: row.int("last_vacuum_at"),
            lastIntegrityCheckAt: row.int("last_integrity_check_at"),
            ftsRebuildVersion: row.int("fts_rebuild_version") ?? 0,
            appliedScriptIDs: DatabaseSchema.allScripts.map(\.id)
        )
    }

    /// 持久化迁移元数据到数据库
    ///
    /// - Parameters:
    ///   - metadata: 迁移元数据
    ///   - paths: 账号存储路径
    /// - Throws: 数据库操作失败时抛出错误
    private func persistMigrationMetadata(_ metadata: MigrationMetadata, in paths: AccountStoragePaths) async throws {
        try await performTransaction(
            [
                SQLiteStatement("DELETE FROM migration_meta;"),
                SQLiteStatement(
                    """
                    INSERT INTO migration_meta (
                        schema_version,
                        last_migration_id,
                        last_vacuum_at,
                        last_integrity_check_at,
                        fts_rebuild_version
                    ) VALUES (?, ?, ?, ?, ?);
                    """,
                    parameters: [
                        .integer(Int64(metadata.schemaVersion)),
                        .text(metadata.lastMigrationID),
                        Self.optionalIntegerValue(metadata.lastVacuumAt),
                        Self.optionalIntegerValue(metadata.lastIntegrityCheckAt),
                        .integer(Int64(metadata.ftsRebuildVersion))
                    ]
                )
            ],
            paths: paths
        )
    }

    /// 持久化迁移元数据到 JSON 文件
    ///
    /// - Parameters:
    ///   - metadata: 迁移元数据
    ///   - paths: 账号存储路径
    /// - Throws: 文件写入失败时抛出错误
    private func persist(metadata: MigrationMetadata, in paths: AccountStoragePaths) throws {
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: metadataURL(in: paths), options: [.atomic])
    }

    /// 获取元数据文件 URL
    private func metadataURL(in paths: AccountStoragePaths) -> URL {
        paths.cacheDirectory.appendingPathComponent("migration_meta.json")
    }

    /// 获取数据库文件 URL
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

    private func encryptionKey(for url: URL) -> Data? {
        encryptionKeysByDatabasePath[normalizedPath(for: url)]
    }

    private func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    /// 执行预编译语句（打开连接、执行、关闭连接）
    private func executePrepared(_ statement: String, parameters: [SQLiteValue], at url: URL) throws {
        let handle = try openDatabase(at: url)
        defer {
            try? closeDatabase(handle, at: url)
        }

        try executePrepared(statement, parameters: parameters, using: handle, at: url)
    }

    /// 执行原始 SQL 语句（不使用预编译）
    ///
    /// 用于执行 BEGIN、COMMIT、ROLLBACK 等事务控制语句
    private func executeRaw(_ statement: String, using handle: OpaquePointer, at url: URL) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let status = sqlite3_exec(handle, statement, nil, nil, &errorMessage)

        guard status == SQLITE_OK else {
            let message = Self.errorMessage(from: errorMessage) ?? Self.currentErrorMessage(for: handle)
            sqlite3_free(errorMessage)
            throw DatabaseActorError.executeFailed(path: url.path, statement: statement, message: message)
        }
    }

    /// 执行预编译语句（使用已有连接）
    private func executePrepared(
        _ statement: String,
        parameters: [SQLiteValue],
        using handle: OpaquePointer,
        at url: URL
    ) throws {
        let preparedStatement = try prepare(statement, using: handle, at: url)
        defer {
            sqlite3_finalize(preparedStatement)
        }

        try bind(parameters, to: preparedStatement, statement: statement, handle: handle, at: url)

        let status = sqlite3_step(preparedStatement)

        guard status == SQLITE_DONE else {
            throw DatabaseActorError.executeFailed(
                path: url.path,
                statement: statement,
                message: Self.currentErrorMessage(for: handle)
            )
        }
    }

    /// 执行查询（打开连接、查询、关闭连接）
    private func query(_ statement: String, parameters: [SQLiteValue], at url: URL) throws -> [SQLiteRow] {
        let handle = try openDatabase(at: url)
        defer {
            try? closeDatabase(handle, at: url)
        }

        return try query(statement, parameters: parameters, using: handle, at: url)
    }

    /// 执行查询（使用已有连接）
    private func query(
        _ statement: String,
        parameters: [SQLiteValue],
        using handle: OpaquePointer,
        at url: URL
    ) throws -> [SQLiteRow] {
        let preparedStatement = try prepare(statement, using: handle, at: url)
        defer {
            sqlite3_finalize(preparedStatement)
        }

        try bind(parameters, to: preparedStatement, statement: statement, handle: handle, at: url)

        var rows: [SQLiteRow] = []

        while true {
            let stepStatus = sqlite3_step(preparedStatement)

            switch stepStatus {
            case SQLITE_ROW:
                rows.append(row(from: preparedStatement))
            case SQLITE_DONE:
                return rows
            default:
                throw DatabaseActorError.readFailed(
                    path: url.path,
                    statement: statement,
                    message: Self.currentErrorMessage(for: handle)
                )
            }
        }
    }

    private func prepare(_ statement: String, using handle: OpaquePointer, at url: URL) throws -> OpaquePointer {
        var preparedStatement: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(handle, statement, -1, &preparedStatement, nil)

        guard prepareStatus == SQLITE_OK, let preparedStatement else {
            throw DatabaseActorError.prepareFailed(
                path: url.path,
                statement: statement,
                message: Self.currentErrorMessage(for: handle)
            )
        }

        return preparedStatement
    }

    /// 绑定参数到预编译语句
    private func bind(
        _ parameters: [SQLiteValue],
        to preparedStatement: OpaquePointer,
        statement: String,
        handle: OpaquePointer,
        at url: URL
    ) throws {
        for (offset, parameter) in parameters.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32

            switch parameter {
            case .null:
                status = sqlite3_bind_null(preparedStatement, index)
            case let .integer(value):
                status = sqlite3_bind_int64(preparedStatement, index, value)
            case let .real(value):
                status = sqlite3_bind_double(preparedStatement, index, value)
            case let .text(value):
                status = sqlite3_bind_text(preparedStatement, index, value, -1, Self.transientDestructor)
            case let .blob(data):
                status = data.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(
                        preparedStatement,
                        index,
                        buffer.baseAddress,
                        Int32(data.count),
                        Self.transientDestructor
                    )
                }
            }

            guard status == SQLITE_OK else {
                throw DatabaseActorError.bindFailed(
                    path: url.path,
                    statement: statement,
                    message: Self.currentErrorMessage(for: handle)
                )
            }
        }
    }

    /// 从预编译语句提取当前行数据
    private func row(from preparedStatement: OpaquePointer) -> SQLiteRow {
        let columnCount = sqlite3_column_count(preparedStatement)
        var values: [String: SQLiteValue] = [:]

        for columnIndex in 0..<columnCount {
            guard let columnName = sqlite3_column_name(preparedStatement, columnIndex) else {
                continue
            }

            let name = String(cString: columnName)

            switch sqlite3_column_type(preparedStatement, columnIndex) {
            case SQLITE_INTEGER:
                values[name] = .integer(sqlite3_column_int64(preparedStatement, columnIndex))
            case SQLITE_FLOAT:
                values[name] = .real(sqlite3_column_double(preparedStatement, columnIndex))
            case SQLITE_TEXT:
                if let text = sqlite3_column_text(preparedStatement, columnIndex) {
                    values[name] = .text(String(cString: text))
                } else {
                    values[name] = .null
                }
            case SQLITE_BLOB:
                let byteCount = Int(sqlite3_column_bytes(preparedStatement, columnIndex))

                if let bytes = sqlite3_column_blob(preparedStatement, columnIndex) {
                    values[name] = .blob(Data(bytes: bytes, count: byteCount))
                } else {
                    values[name] = .blob(Data())
                }
            default:
                values[name] = .null
            }
        }

        return SQLiteRow(values: values)
    }

    /// 打开数据库连接
    private func openDatabase(at url: URL) throws -> OpaquePointer {
        try openDatabase(at: url, applyingConfiguredKey: true)
    }

    private func openDatabase(at url: URL, applyingConfiguredKey: Bool) throws -> OpaquePointer {
        try openDatabase(at: url, encryptionKey: applyingConfiguredKey ? encryptionKey(for: url) : nil)
    }

    private func openDatabase(at url: URL, encryptionKey: Data?) throws -> OpaquePointer {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(url.path, &handle, flags, nil)

        guard status == SQLITE_OK, let handle else {
            let message = handle.map(Self.currentErrorMessage(for:)) ?? "Unable to allocate SQLite handle."

            if let handle {
                sqlite3_close(handle)
            }

            throw DatabaseActorError.openFailed(path: url.path, message: message)
        }

        if let encryptionKey {
            do {
                try applyEncryptionKey(encryptionKey, to: handle, at: url)
            } catch {
                sqlite3_close(handle)
                throw error
            }
        }

        return handle
    }

    private func applyEncryptionKey(_ key: Data, to handle: OpaquePointer, at url: URL) throws {
        let status = key.withUnsafeBytes { buffer in
            sqlite3_key(handle, buffer.baseAddress, Int32(buffer.count))
        }

        guard status == SQLITE_OK else {
            throw DatabaseActorError.encryptionFailed(path: url.path, message: Self.currentErrorMessage(for: handle))
        }
    }

    private func applyEncryptionKey(_ key: Data, to handle: OpaquePointer, databaseName: String, at url: URL) throws {
        let status = databaseName.withCString { databaseNamePointer in
            key.withUnsafeBytes { buffer in
                sqlite3_key_v2(handle, databaseNamePointer, buffer.baseAddress, Int32(buffer.count))
            }
        }

        guard status == SQLITE_OK else {
            throw DatabaseActorError.encryptionFailed(path: url.path, message: Self.currentErrorMessage(for: handle))
        }
    }

    /// 关闭数据库连接
    private func closeDatabase(_ handle: OpaquePointer, at url: URL) throws {
        let status = sqlite3_close(handle)

        guard status == SQLITE_OK else {
            throw DatabaseActorError.closeFailed(path: url.path, message: Self.currentErrorMessage(for: handle))
        }
    }

    /// 获取当前错误消息
    nonisolated private static func currentErrorMessage(for handle: OpaquePointer) -> String {
        guard let message = sqlite3_errmsg(handle) else {
            return "Unknown SQLite error."
        }

        return String(cString: message)
    }

    nonisolated private static func errorMessage(from pointer: UnsafeMutablePointer<Int8>?) -> String? {
        guard let pointer else {
            return nil
        }

        return String(cString: pointer)
    }

    nonisolated private static func escapedSQLString(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    nonisolated private static var transientDestructor: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    /// 将可选整数转换为 SQLiteValue
    nonisolated private static func optionalIntegerValue(_ value: Int?) -> SQLiteValue {
        guard let value else {
            return .null
        }

        return .integer(Int64(value))
    }
}
