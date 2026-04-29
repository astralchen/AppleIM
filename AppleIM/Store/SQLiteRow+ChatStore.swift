//
//  SQLiteRow+ChatStore.swift
//  AppleIM
//
//  SQLiteRow 扩展
//  提供便捷的必填字段读取方法

import Foundation

extension SQLiteRow {
    /// 读取必填的字符串字段
    ///
    /// - Parameter column: 列名
    /// - Returns: 字符串值
    /// - Throws: 字段不存在时抛出 missingColumn 错误
    nonisolated func requiredString(_ column: String) throws -> String {
        guard let value = string(column) else {
            throw ChatStoreError.missingColumn(column)
        }

        return value
    }

    /// 读取必填的整数字段
    ///
    /// - Parameter column: 列名
    /// - Returns: 整数值
    /// - Throws: 字段不存在时抛出 missingColumn 错误
    nonisolated func requiredInt(_ column: String) throws -> Int {
        guard let value = int(column) else {
            throw ChatStoreError.missingColumn(column)
        }

        return value
    }

    /// 读取必填的 Int64 字段
    ///
    /// - Parameter column: 列名
    /// - Returns: Int64 值
    /// - Throws: 字段不存在时抛出 missingColumn 错误
    nonisolated func requiredInt64(_ column: String) throws -> Int64 {
        guard let value = int64(column) else {
            throw ChatStoreError.missingColumn(column)
        }

        return value
    }
}

extension SQLiteValue {
    /// 创建可选文本值
    ///
    /// - Parameter value: 可选字符串
    /// - Returns: SQLiteValue（null 或 text）
    nonisolated static func optionalText(_ value: String?) -> SQLiteValue {
        guard let value else {
            return .null
        }

        return .text(value)
    }

    /// 创建可选整数值
    ///
    /// - Parameter value: 可选 Int64
    /// - Returns: SQLiteValue（null 或 integer）
    nonisolated static func optionalInteger(_ value: Int64?) -> SQLiteValue {
        guard let value else {
            return .null
        }

        return .integer(value)
    }
}
