//
//  ContactListUseCase.swift
//  AppleIM
//
//  通讯录用例
//

import Foundation

protocol ContactListUseCase: Sendable {
    func loadContacts(query: String) async throws -> ContactListViewState
    func openConversation(for contactID: ContactID) async throws -> ConversationListRowState
}

nonisolated struct LocalContactListUseCase: ContactListUseCase {
    private let userID: UserID
    private let storeProvider: ChatStoreProvider

    init(userID: UserID, storeProvider: ChatStoreProvider) {
        self.userID = userID
        self.storeProvider = storeProvider
    }

    func loadContacts(query: String) async throws -> ContactListViewState {
        let repository = try await storeProvider.repository()
        let allContacts = try await repository.listContacts(for: userID)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let contacts = trimmedQuery.isEmpty
            ? allContacts
            : allContacts.filter { contact in
                contact.displayName.localizedCaseInsensitiveContains(trimmedQuery)
                    || contact.wxid.localizedCaseInsensitiveContains(trimmedQuery)
            }

        return Self.viewState(query: query, contacts: contacts)
    }

    func openConversation(for contactID: ContactID) async throws -> ConversationListRowState {
        let repository = try await storeProvider.repository()
        let conversation = try await repository.conversationForContact(contactID: contactID, userID: userID)
        return LocalConversationListUseCase.rowStates(from: [conversation]).first
            ?? ConversationListRowState(
                id: conversation.id,
                title: conversation.title,
                avatarURL: conversation.avatarURL,
                subtitle: conversation.lastMessageDigest,
                timeText: conversation.lastMessageTimeText,
                unreadText: nil,
                isPinned: conversation.isPinned,
                isMuted: conversation.isMuted
            )
    }

    private static func viewState(query: String, contacts: [ContactRecord]) -> ContactListViewState {
        let supportedContacts = contacts.filter { $0.type == .friend || $0.type == .group }
        let groupRows = supportedContacts
            .filter { $0.type == .group }
            .map(ContactListRowState.init(contact:))
            .sorted(by: contactRowSort)
        let starredRows = supportedContacts
            .filter { $0.type == .friend && $0.isStarred }
            .map(ContactListRowState.init(contact:))
            .sorted(by: contactRowSort)
        let contactRows = supportedContacts
            .filter { $0.type == .friend && !$0.isStarred }
            .map(ContactListRowState.init(contact:))
            .sorted(by: contactRowSort)

        return ContactListViewState(
            query: query,
            phase: .loaded,
            groupRows: groupRows,
            starredRows: starredRows,
            contactRows: contactRows
        )
    }

    private static func contactRowSort(_ lhs: ContactListRowState, _ rhs: ContactListRowState) -> Bool {
        if lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedSame {
            return lhs.id.rawValue < rhs.id.rawValue
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

