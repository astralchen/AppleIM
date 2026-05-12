//
//  ContactRepository.swift
//  AppleIM
//
//  通讯录仓储协议
//

import Foundation

protocol ContactRepository: Sendable {
    func listContacts(for userID: UserID) async throws -> [ContactRecord]
    func countContacts(for userID: UserID) async throws -> Int
    func contact(id contactID: ContactID, userID: UserID) async throws -> ContactRecord?
    func upsertContact(_ record: ContactRecord) async throws
    func upsertContacts(_ records: [ContactRecord]) async throws
    func conversationForContact(contactID: ContactID, userID: UserID) async throws -> Conversation
}

