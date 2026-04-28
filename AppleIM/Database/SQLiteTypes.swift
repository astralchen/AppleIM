//
//  SQLiteTypes.swift
//  AppleIM
//

import Foundation

nonisolated enum SQLiteValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

nonisolated struct SQLiteStatement: Equatable, Sendable {
    let sql: String
    let parameters: [SQLiteValue]

    init(_ sql: String, parameters: [SQLiteValue] = []) {
        self.sql = sql
        self.parameters = parameters
    }
}

nonisolated struct SQLiteRow: Equatable, Sendable {
    let values: [String: SQLiteValue]

    subscript(_ column: String) -> SQLiteValue? {
        values[column]
    }

    func string(_ column: String) -> String? {
        guard case let .text(value) = values[column] else {
            return nil
        }

        return value
    }

    func int(_ column: String) -> Int? {
        guard case let .integer(value) = values[column] else {
            return nil
        }

        return Int(value)
    }

    func int64(_ column: String) -> Int64? {
        guard case let .integer(value) = values[column] else {
            return nil
        }

        return value
    }

    func bool(_ column: String) -> Bool {
        int(column) != 0
    }
}
