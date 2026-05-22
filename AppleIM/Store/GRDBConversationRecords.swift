//
//  GRDBConversationRecords.swift
//  AppleIM
//
//  GRDB 内部表映射。
//

import Foundation
import GRDB

/// conversation 表的 GRDB 读取模型。
nonisolated struct ConversationDatabaseRecord: FetchableRecord, TableRecord, Sendable {
    static let databaseTableName = "conversation"

    enum Columns {
        static let conversationID = Column("conversation_id")
        static let userID = Column("user_id")
        static let type = Column("biz_type")
        static let targetID = Column("target_id")
        static let title = Column("title")
        static let avatarURL = Column("avatar_url")
        static let lastMessageID = Column("last_message_id")
        static let lastMessageTime = Column("last_message_time")
        static let lastMessageDigest = Column("last_message_digest")
        static let unreadCount = Column("unread_count")
        static let draftText = Column("draft_text")
        static let isPinned = Column("is_pinned")
        static let isMuted = Column("is_muted")
        static let isHidden = Column("is_hidden")
        static let sortTimestamp = Column("sort_ts")
        static let extraJSON = Column("extra_json")
        static let updatedAt = Column("updated_at")
        static let createdAt = Column("created_at")
    }

    let record: ConversationRecord
    let extraJSON: String?

    init(row: Row) throws {
        let typeRawValue: Int = row[Columns.type]
        guard let type = ConversationType(rawValue: typeRawValue) else {
            throw ChatStoreError.invalidConversationType(typeRawValue)
        }

        let lastMessageID: String? = row[Columns.lastMessageID]
        extraJSON = row[Columns.extraJSON]
        record = ConversationRecord(
            id: ConversationID(rawValue: row[Columns.conversationID]),
            userID: UserID(rawValue: row[Columns.userID]),
            type: type,
            targetID: row[Columns.targetID],
            title: row[Columns.title] ?? "",
            avatarURL: row[Columns.avatarURL],
            lastMessageID: lastMessageID.map(MessageID.init(rawValue:)),
            lastMessageTime: row[Columns.lastMessageTime],
            lastMessageDigest: row[Columns.lastMessageDigest] ?? "",
            unreadCount: row[Columns.unreadCount],
            draftText: row[Columns.draftText],
            isPinned: row[Columns.isPinned],
            isMuted: row[Columns.isMuted],
            isHidden: row[Columns.isHidden],
            sortTimestamp: row[Columns.sortTimestamp],
            updatedAt: row[Columns.updatedAt] ?? 0,
            createdAt: row[Columns.createdAt] ?? 0
        )
    }
}


/// conversation_member 表的 GRDB 读取模型。
nonisolated struct GroupMemberDatabaseRecord: FetchableRecord, TableRecord, Sendable {
    static let databaseTableName = "conversation_member"

    enum Columns {
        static let id = Column("id")
        static let conversationID = Column("conversation_id")
        static let memberID = Column("member_id")
        static let displayName = Column("display_name")
        static let role = Column("role")
        static let joinTime = Column("join_time")
    }

    let member: GroupMember

    init(row: Row) throws {
        let roleRawValue: Int = row[Columns.role]
        guard let role = GroupMemberRole(rawValue: roleRawValue) else {
            throw ChatStoreError.invalidConversationType(roleRawValue)
        }

        member = GroupMember(
            conversationID: ConversationID(rawValue: row[Columns.conversationID]),
            memberID: UserID(rawValue: row[Columns.memberID]),
            displayName: row[Columns.displayName] ?? "",
            role: role,
            joinTime: row[Columns.joinTime]
        )
    }
}

extension GroupMemberDatabaseRecord: PersistableRecord {
    init(member: GroupMember) {
        self.member = member
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.conversationID] = member.conversationID.rawValue
        container[Columns.memberID] = member.memberID.rawValue
        container[Columns.displayName] = member.displayName
        container[Columns.role] = member.role.rawValue
        container[Columns.joinTime] = member.joinTime
        container[Column("extra_json")] = nil as String?
    }

    static func upsertRecord(_ member: GroupMember, in db: Database) throws {
        let request = GroupMemberDatabaseRecord
            .filter(Columns.conversationID == member.conversationID.rawValue)
            .filter(Columns.memberID == member.memberID.rawValue)

        if try request.fetchOne(db) != nil {
            try request.updateAll(db, [
                Columns.displayName.set(to: member.displayName),
                Columns.role.set(to: member.role.rawValue),
                Columns.joinTime.set(to: member.joinTime)
            ])
        } else {
            try GroupMemberDatabaseRecord(member: member).insert(db)
        }
    }
}


extension ConversationDatabaseRecord: PersistableRecord {
    init(record: ConversationRecord) {
        self.record = record
        extraJSON = nil
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.conversationID] = record.id.rawValue
        container[Columns.userID] = record.userID.rawValue
        container[Columns.type] = record.type.rawValue
        container[Columns.targetID] = record.targetID
        container[Columns.title] = record.title
        container[Columns.avatarURL] = record.avatarURL
        container[Columns.lastMessageID] = record.lastMessageID?.rawValue
        container[Columns.lastMessageTime] = record.lastMessageTime
        container[Columns.lastMessageDigest] = record.lastMessageDigest
        container[Columns.unreadCount] = record.unreadCount
        container[Columns.draftText] = record.draftText
        container[Columns.isPinned] = record.isPinned
        container[Columns.isMuted] = record.isMuted
        container[Columns.isHidden] = record.isHidden
        container[Columns.sortTimestamp] = record.sortTimestamp
        container[Columns.updatedAt] = record.updatedAt
        container[Columns.createdAt] = record.createdAt
    }

    @discardableResult
    static func upsertRecord(_ record: ConversationRecord, in db: Database) throws -> ConversationRecord {
        let databaseRecord = try ConversationDatabaseRecord(record: record)
            .upsertAndFetch(db, updating: .noColumnUnlessSpecified) { excluded in
                [
                    Columns.userID.set(to: excluded[Columns.userID]),
                    Columns.type.set(to: excluded[Columns.type]),
                    Columns.targetID.set(to: excluded[Columns.targetID]),
                    Columns.title.set(to: excluded[Columns.title]),
                    Columns.avatarURL.set(to: excluded[Columns.avatarURL]),
                    Columns.lastMessageID.set(to: excluded[Columns.lastMessageID]),
                    Columns.lastMessageTime.set(to: excluded[Columns.lastMessageTime]),
                    Columns.lastMessageDigest.set(to: excluded[Columns.lastMessageDigest]),
                    Columns.unreadCount.set(to: excluded[Columns.unreadCount]),
                    Columns.draftText.set(to: excluded[Columns.draftText]),
                    Columns.isPinned.set(to: excluded[Columns.isPinned]),
                    Columns.isMuted.set(to: excluded[Columns.isMuted]),
                    Columns.isHidden.set(to: excluded[Columns.isHidden]),
                    Columns.sortTimestamp.set(to: excluded[Columns.sortTimestamp]),
                    Columns.updatedAt.set(to: excluded[Columns.updatedAt])
                ]
            }
        return databaseRecord.record
    }
}

