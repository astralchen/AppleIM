//
//  AccountStorageFactory.swift
//  AppleIM
//

import Foundation

enum AccountStorageFactory {
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
