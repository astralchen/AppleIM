//
//  ContactListViewState.swift
//  AppleIM
//
//  通讯录视图状态
//

import Foundation

/// 通讯录行状态
nonisolated struct ContactListRowState: Identifiable, Hashable, Sendable {
    let id: ContactID
    let title: String
    let subtitle: String
    let avatarURL: String?
    let type: ContactType
    let isStarred: Bool

    init(
        id: ContactID,
        title: String,
        subtitle: String,
        avatarURL: String?,
        type: ContactType,
        isStarred: Bool
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.avatarURL = avatarURL
        self.type = type
        self.isStarred = isStarred
    }

    init(contact: ContactRecord) {
        self.init(
            id: contact.contactID,
            title: contact.displayName,
            subtitle: contact.type == .group ? "群聊" : contact.wxid,
            avatarURL: contact.avatarURL,
            type: contact.type,
            isStarred: contact.isStarred
        )
    }
}

/// 通讯录视图状态
nonisolated struct ContactListViewState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var query = ""
    var phase: Phase = .idle
    var groupRows: [ContactListRowState] = []
    var starredRows: [ContactListRowState] = []
    var contactRows: [ContactListRowState] = []
    var emptyMessage = "No contacts yet"

    var isEmpty: Bool {
        groupRows.isEmpty && starredRows.isEmpty && contactRows.isEmpty
    }
}

