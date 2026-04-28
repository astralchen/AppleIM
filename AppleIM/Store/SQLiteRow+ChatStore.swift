//
//  SQLiteRow+ChatStore.swift
//  AppleIM
//

import Foundation

extension SQLiteRow {
    nonisolated func requiredString(_ column: String) throws -> String {
        guard let value = string(column) else {
            throw ChatStoreError.missingColumn(column)
        }

        return value
    }

    nonisolated func requiredInt(_ column: String) throws -> Int {
        guard let value = int(column) else {
            throw ChatStoreError.missingColumn(column)
        }

        return value
    }

    nonisolated func requiredInt64(_ column: String) throws -> Int64 {
        guard let value = int64(column) else {
            throw ChatStoreError.missingColumn(column)
        }

        return value
    }
}

extension SQLiteValue {
    nonisolated static func optionalText(_ value: String?) -> SQLiteValue {
        guard let value else {
            return .null
        }

        return .text(value)
    }

    nonisolated static func optionalInteger(_ value: Int64?) -> SQLiteValue {
        guard let value else {
            return .null
        }

        return .integer(value)
    }
}
