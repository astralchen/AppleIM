//
//  AccountStoragePaths.swift
//  AppleIM
//

import Foundation

nonisolated struct AccountStoragePaths: Equatable, Sendable {
    let accountID: UserID
    let rootDirectory: URL
    let mainDatabase: URL
    let searchDatabase: URL
    let fileIndexDatabase: URL
    let mediaDirectory: URL
    let cacheDirectory: URL
}

nonisolated enum AccountStorageError: Error, Equatable, Sendable {
    case emptyAccountID
}
