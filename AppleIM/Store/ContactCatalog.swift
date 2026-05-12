//
//  ContactCatalog.swift
//  AppleIM
//
//  本地模拟通讯录文件读取
//

import Foundation

protocol ContactCatalog: Sendable {
    nonisolated func contacts(for accountID: UserID) async throws -> [ContactRecord]
}

nonisolated enum ContactCatalogError: Error, Equatable, Sendable {
    case resourceMissing
    case empty
    case invalidType(String)
}

/// Bundle 通讯录目录实现。
nonisolated struct BundleContactCatalog: ContactCatalog {
    private let resourceURL: URL?

    init(bundle: Bundle = .main, resourceName: String = "mock_contacts") {
        self.resourceURL = bundle.url(forResource: resourceName, withExtension: "json")
    }

    init(resourceURL: URL?) {
        self.resourceURL = resourceURL
    }

    nonisolated func contacts(for accountID: UserID) async throws -> [ContactRecord] {
        guard let resourceURL else {
            throw ContactCatalogError.resourceMissing
        }

        let data = try Data(contentsOf: resourceURL)
        let entries = try JSONDecoder().decode([MockContactAccountEntry].self, from: data)
        guard let account = entries.first(where: { $0.accountID == accountID.rawValue }) else {
            return []
        }

        let now = Int64(Date().timeIntervalSince1970)
        return try account.contacts.map { contact in
            guard let type = ContactType(mockValue: contact.type) else {
                throw ContactCatalogError.invalidType(contact.type)
            }

            return ContactRecord(
                contactID: ContactID(rawValue: contact.contactID),
                userID: accountID,
                wxid: contact.wxid,
                nickname: contact.nickname,
                remark: contact.remark,
                avatarURL: contact.avatarURL,
                type: type,
                isStarred: contact.isStarred,
                isBlocked: false,
                isDeleted: false,
                source: nil,
                extraJSON: nil,
                updatedAt: now,
                createdAt: now
            )
        }
    }
}

nonisolated private struct MockContactAccountEntry: Decodable, Sendable {
    let accountID: String
    let contacts: [MockContactEntry]
}

nonisolated private struct MockContactEntry: Decodable, Sendable {
    let contactID: String
    let wxid: String
    let nickname: String
    let remark: String?
    let avatarURL: String?
    let type: String
    let isStarred: Bool
}

