//
//  AccountStorageFactory.swift
//  AppleIM
//
//  账号存储工厂
//  创建默认的账号存储服务实例

import Foundation

/// 账号存储工厂
///
/// 提供创建账号存储服务的工厂方法
enum AccountStorageFactory {
    /// 创建默认的账号存储服务
    ///
    /// 使用应用支持目录下的 ChatBridge 目录作为根目录
    ///
    /// - Returns: 账号存储服务实例
    /// - Throws: 目录创建失败时抛出错误
    static func makeDefaultService() throws -> any AccountStorageService {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let rootDirectory = applicationSupport.appendingPathComponent(
            "ChatBridge",
            isDirectory: true
        )

        return FileAccountStorageService(rootDirectory: rootDirectory)
    }
}
