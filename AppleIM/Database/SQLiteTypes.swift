//
//  SQLiteTypes.swift
//  AppleIM
//
//  SQLite 类型定义
//  封装 SQLite 的值类型、语句和查询结果

import Foundation

/// SQLite 值类型
///
/// 对应 SQLite 的 5 种基本数据类型
nonisolated enum SQLiteValue: Equatable, Sendable {
    /// NULL
    case null
    /// INTEGER
    case integer(Int64)
    /// REAL
    case real(Double)
    /// TEXT
    case text(String)
    /// BLOB
    case blob(Data)
}

/// SQLite 语句
///
/// 包含 SQL 字符串和绑定参数
nonisolated struct SQLiteStatement: Equatable, Sendable {
    /// SQL 语句
    let sql: String
    /// 绑定参数
    let parameters: [SQLiteValue]

    init(_ sql: String, parameters: [SQLiteValue] = []) {
        self.sql = sql
        self.parameters = parameters
    }
}

/// SQLite 查询结果行
///
/// 以字典形式存储列名和值的映射
nonisolated struct SQLiteRow: Equatable, Sendable {
    /// 列名到值的映射
    let values: [String: SQLiteValue]

    /// 通过列名访问值
    subscript(_ column: String) -> SQLiteValue? {
        values[column]
    }

    /// 获取字符串值
    func string(_ column: String) -> String? {
        guard case let .text(value) = values[column] else {
            return nil
        }

        return value
    }

    /// 获取整数值
    func int(_ column: String) -> Int? {
        guard case let .integer(value) = values[column] else {
            return nil
        }

        return Int(value)
    }

    /// 获取 Int64 值
    func int64(_ column: String) -> Int64? {
        guard case let .integer(value) = values[column] else {
            return nil
        }

        return value
    }

    /// 获取 Bool 值
    func bool(_ column: String) -> Bool {
        int(column) != 0
    }
}
