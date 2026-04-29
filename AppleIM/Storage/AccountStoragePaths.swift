//
//  AccountStoragePaths.swift
//  AppleIM
//
//  账号存储路径
//  定义每个账号的独立存储目录结构

import Foundation

/// 账号存储路径
///
/// 每个账号拥有独立的目录，包含数据库、媒体文件、缓存等
nonisolated struct AccountStoragePaths: Equatable, Sendable {
    /// 账号 ID
    let accountID: UserID
    /// 根目录
    let rootDirectory: URL
    /// 主数据库路径
    let mainDatabase: URL
    /// 搜索数据库路径
    let searchDatabase: URL
    /// 文件索引数据库路径
    let fileIndexDatabase: URL
    /// 媒体文件目录
    let mediaDirectory: URL
    /// 缓存目录
    let cacheDirectory: URL
}

/// 账号存储错误
nonisolated enum AccountStorageError: Error, Equatable, Sendable {
    /// 账号 ID 为空
    case emptyAccountID
}
