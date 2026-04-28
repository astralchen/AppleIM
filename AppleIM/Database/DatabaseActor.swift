//
//  DatabaseActor.swift
//  AppleIM
//

import Foundation
import SQLite3

nonisolated enum DatabaseActorError: Error, Equatable, Sendable {
    case openFailed(path: String, message: String)
    case executeFailed(path: String, statement: String, message: String)
    case prepareFailed(path: String, statement: String, message: String)
    case bindFailed(path: String, statement: String, message: String)
    case readFailed(path: String, statement: String, message: String)
    case closeFailed(path: String, message: String)
}

nonisolated struct MigrationMetadata: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let lastMigrationID: String
    let lastVacuumAt: Int?
    let lastIntegrityCheckAt: Int?
    let ftsRebuildVersion: Int
    let appliedScriptIDs: [String]
}

nonisolated struct DatabaseBootstrapResult: Equatable, Sendable {
    let paths: AccountStoragePaths
    let metadata: MigrationMetadata
}

actor DatabaseActor {
    func bootstrap(paths: AccountStoragePaths) async throws -> DatabaseBootstrapResult {
        let metadata = MigrationMetadata(
            schemaVersion: DatabaseSchema.currentVersion,
            lastMigrationID: DatabaseSchema.initialScripts.last?.id ?? "",
            lastVacuumAt: nil,
            lastIntegrityCheckAt: nil,
            ftsRebuildVersion: 0,
            appliedScriptIDs: DatabaseSchema.initialScripts.map(\.id)
        )

        try applyInitialScripts(to: paths)
        try await persistMigrationMetadata(metadata, in: paths)
        try persist(metadata: metadata, in: paths)

        return DatabaseBootstrapResult(paths: paths, metadata: metadata)
    }

    func loadMigrationMetadata(paths: AccountStoragePaths) async throws -> MigrationMetadata {
        let data = try Data(contentsOf: metadataURL(in: paths))
        return try JSONDecoder().decode(MigrationMetadata.self, from: data)
    }

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

    func execute(
        _ statement: String,
        parameters: [SQLiteValue] = [],
        in database: DatabaseFileKind = .main,
        paths: AccountStoragePaths
    ) async throws {
        try executePrepared(statement, parameters: parameters, at: url(for: database, in: paths))
    }

    func query(
        _ statement: String,
        parameters: [SQLiteValue] = [],
        in database: DatabaseFileKind = .main,
        paths: AccountStoragePaths
    ) async throws -> [SQLiteRow] {
        try query(statement, parameters: parameters, at: url(for: database, in: paths))
    }

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

    private func persist(metadata: MigrationMetadata, in paths: AccountStoragePaths) throws {
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: metadataURL(in: paths), options: [.atomic])
    }

    private func metadataURL(in paths: AccountStoragePaths) -> URL {
        paths.cacheDirectory.appendingPathComponent("migration_meta.json")
    }

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

    private func executePrepared(_ statement: String, parameters: [SQLiteValue], at url: URL) throws {
        let handle = try openDatabase(at: url)
        defer {
            try? closeDatabase(handle, at: url)
        }

        try executePrepared(statement, parameters: parameters, using: handle, at: url)
    }

    private func executeRaw(_ statement: String, using handle: OpaquePointer, at url: URL) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let status = sqlite3_exec(handle, statement, nil, nil, &errorMessage)

        guard status == SQLITE_OK else {
            let message = Self.errorMessage(from: errorMessage) ?? Self.currentErrorMessage(for: handle)
            sqlite3_free(errorMessage)
            throw DatabaseActorError.executeFailed(path: url.path, statement: statement, message: message)
        }
    }

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

    private func query(_ statement: String, parameters: [SQLiteValue], at url: URL) throws -> [SQLiteRow] {
        let handle = try openDatabase(at: url)
        defer {
            try? closeDatabase(handle, at: url)
        }

        return try query(statement, parameters: parameters, using: handle, at: url)
    }

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

    private func openDatabase(at url: URL) throws -> OpaquePointer {
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

        return handle
    }

    private func closeDatabase(_ handle: OpaquePointer, at url: URL) throws {
        let status = sqlite3_close(handle)

        guard status == SQLITE_OK else {
            throw DatabaseActorError.closeFailed(path: url.path, message: Self.currentErrorMessage(for: handle))
        }
    }

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

    nonisolated private static var transientDestructor: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    nonisolated private static func optionalIntegerValue(_ value: Int?) -> SQLiteValue {
        guard let value else {
            return .null
        }

        return .integer(Int64(value))
    }
}
