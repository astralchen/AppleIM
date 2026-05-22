import Testing
import AVFoundation
import Combine
import Foundation
import GRDB
import CoreGraphics
import ImageIO
import UIKit
import UniformTypeIdentifiers

@testable import AppleIM

func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("AppleIMTests-\(UUID().uuidString)", isDirectory: true)
}

func makeMockAccountsFile() throws -> URL {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("mock_accounts.json")
    let json = """
    [
      {
        "userID": "mock_user",
        "loginName": "mock_user",
        "password": "password123",
        "displayName": "Mock User",
        "mobile": "13700000000",
        "avatarURL": "https://example.com/mock-avatar.png"
      }
    ]
    """
    try Data(json.utf8).write(to: url, options: [.atomic])
    return url
}

func makeMockContactsFile() throws -> URL {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("mock_contacts.json")
    let json = """
    [
      {
        "accountID": "mock_user",
        "contacts": [
          {
            "contactID": "contact_sondra",
            "wxid": "sondra",
            "nickname": "Sondra",
            "remark": "",
            "avatarURL": "https://example.com/sondra.png",
            "type": "friend",
            "isStarred": true
          },
          {
            "contactID": "group_core_contact",
            "wxid": "chatbridge_core",
            "nickname": "ChatBridge Core",
            "remark": "",
            "avatarURL": null,
            "type": "group",
            "isStarred": false
          }
        ]
      },
      {
        "accountID": "other_user",
        "contacts": [
          {
            "contactID": "contact_other",
            "wxid": "other",
            "nickname": "Other",
            "remark": "",
            "avatarURL": null,
            "type": "friend",
            "isStarred": false
          }
        ]
      }
    ]
    """
    try Data(json.utf8).write(to: url, options: [.atomic])
    return url
}

func makeMockDemoDataFile(messageCount: Int, firstMessageDirection: String = "incoming") throws -> URL {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("mock_demo_data.json")
    let messages = (1...messageCount).map { index in
        let direction = index == 1 ? firstMessageDirection : (index.isMultiple(of: 5) ? "outgoing" : "incoming")
        let offset = index - messageCount
        return """
              {
                "conversationID": "single_sondra",
                "senderID": "\(direction == "outgoing" ? "mock_user" : "sondra")",
                "text": "Sondra JSON message \(index)",
                "localTimeOffsetSeconds": \(offset),
                "messageID": "seed_single_sondra_\(index)",
                "serverMessageID": "server_seed_single_sondra_\(index)",
                "sequenceOffsetSeconds": \(offset),
                "direction": "\(direction)",
                "readStatus": "\(direction == "incoming" ? "unread" : "read")",
                "sortSequenceOffsetSeconds": \(offset)
              }
        """
    }.joined(separator: ",\n")
    let lastOffset = 0
    let json = """
    [
      {
        "accountID": "mock_user",
        "conversations": [
          {
            "id": "single_sondra",
            "type": "single",
            "targetID": "sondra",
            "title": "Sondra",
            "avatarURL": null,
            "unreadCount": 2,
            "draftText": null,
            "isPinned": true,
            "isMuted": false,
            "isHidden": false,
            "createdAtOffsetSeconds": -7200
          },
          {
            "id": "group_core",
            "type": "group",
            "targetID": "chatbridge_core",
            "title": "ChatBridge Core",
            "avatarURL": null,
            "unreadCount": 0,
            "draftText": null,
            "isPinned": false,
            "isMuted": true,
            "isHidden": false,
            "createdAtOffsetSeconds": -7200,
            "lastMessageTimeOffsetSeconds": -1800,
            "lastMessageDigest": "群聊 JSON seed 已接入。",
            "sortTimestampOffsetSeconds": -1800
          },
          {
            "id": "system_release",
            "type": "system",
            "targetID": "system",
            "title": "系统通知",
            "avatarURL": null,
            "unreadCount": 0,
            "draftText": null,
            "isPinned": false,
            "isMuted": false,
            "isHidden": false,
            "createdAtOffsetSeconds": -7200,
            "lastMessageTimeOffsetSeconds": -3600,
            "lastMessageDigest": "系统 JSON seed 已接入。",
            "sortTimestampOffsetSeconds": -3600
          }
        ],
        "messages": [
    \(messages)
        ],
        "groupMembers": [
          {
            "conversationID": "group_core",
            "memberID": "mock_user",
            "displayName": "Me",
            "role": "admin",
            "joinTimeOffsetSeconds": -3600
          },
          {
            "conversationID": "group_core",
            "memberID": "sondra",
            "displayName": "Sondra",
            "role": "owner",
            "joinTimeOffsetSeconds": -3500
          }
        ],
        "groupAnnouncements": [
          {
            "conversationID": "group_core",
            "text": "群聊 JSON seed 已接入。"
          }
        ],
        "lastMessageTimeOffsetSeconds": \(lastOffset)
      },
      {
        "accountID": "other_user",
        "conversations": [],
        "messages": [],
        "groupMembers": [],
        "groupAnnouncements": []
      }
    ]
    """
    try Data(json.utf8).write(to: url, options: [.atomic])
    return url
}

func samplePNGData() -> Data {
    Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")!
}

func makeVoiceRecordingFile(in directory: URL) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("sample-\(UUID().uuidString)").appendingPathExtension("m4a")
    try Data("mock voice recording".utf8).write(to: url, options: [.atomic])
    return url
}

func makeSampleVideoFile(in directory: URL) async throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("sample-\(UUID().uuidString)").appendingPathExtension("mov")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 64,
        AVVideoHeightKey: 64
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 64
        ]
    )

    guard writer.canAdd(input) else {
        Issue.record("Unable to add video writer input")
        return url
    }

    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    let firstPixelBuffer = try makePixelBuffer(width: 64, height: 64, colorOffset: 0)
    let secondPixelBuffer = try makePixelBuffer(width: 64, height: 64, colorOffset: 48)
    while !input.isReadyForMoreMediaData {
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    guard adaptor.append(firstPixelBuffer, withPresentationTime: .zero) else {
        throw writer.error ?? MediaFileError.invalidVideoFile
    }

    while !input.isReadyForMoreMediaData {
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    guard adaptor.append(secondPixelBuffer, withPresentationTime: CMTime(value: 1, timescale: 1)) else {
        throw writer.error ?? MediaFileError.invalidVideoFile
    }

    input.markAsFinished()
    await writer.finishWriting()

    if writer.status == .failed {
        throw writer.error ?? MediaFileError.invalidVideoFile
    }

    return url
}

func makePixelBuffer(width: Int, height: Int, colorOffset: UInt8) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32ARGB,
        nil,
        &pixelBuffer
    )

    guard status == kCVReturnSuccess, let pixelBuffer else {
        throw MediaFileError.invalidVideoFile
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    }

    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        throw MediaFileError.invalidVideoFile
    }

    let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * 4
            buffer[offset] = 255
            buffer[offset + 1] = UInt8((x * 4 + Int(colorOffset)) % 256)
            buffer[offset + 2] = UInt8((y * 4 + Int(colorOffset)) % 256)
            buffer[offset + 3] = 180
        }
    }

    return pixelBuffer
}

func makeJPEGData(width: Int, height: Int, quality: Double) -> Data {
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * bytesPerPixel
            pixels[offset] = UInt8(x % 256)
            pixels[offset + 1] = UInt8(y % 256)
            pixels[offset + 2] = UInt8((x + y) % 256)
            pixels[offset + 3] = 255
        }
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let image = context.makeImage()
    else {
        Issue.record("Unable to create JPEG test image")
        return Data()
    }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
        Issue.record("Unable to create JPEG destination")
        return Data()
    }

    CGImageDestinationAddImage(destination, image, [
        kCGImageDestinationLossyCompressionQuality: quality
    ] as CFDictionary)

    guard CGImageDestinationFinalize(destination) else {
        Issue.record("Unable to finalize JPEG test image")
        return Data()
    }

    return data as Data
}

func imageDimensions(atPath path: String) -> (width: Int, height: Int) {
    guard
        let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else {
        Issue.record("Unable to read image dimensions at \(path)")
        return (0, 0)
    }

    return (
        properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
        properties[kCGImagePropertyPixelHeight] as? Int ?? 0
    )
}

nonisolated struct DatabaseTestContext: Sendable {
    let databaseActor: DatabaseActor
    let paths: AccountStoragePaths
}

func makeBootstrappedDatabase(rootDirectory: URL, accountID: UserID) async throws -> (DatabaseActor, AccountStoragePaths) {
    let storageService = await FileAccountStorageService(rootDirectory: rootDirectory)
    let paths = try await storageService.prepareStorage(for: accountID)
    let databaseActor = DatabaseActor()
    _ = try await databaseActor.bootstrap(paths: paths)
    return (databaseActor, paths)
}

func makeRepository(rootDirectory: URL, accountID: UserID) async throws -> (LocalChatRepository, DatabaseTestContext) {
    let (databaseActor, paths) = try await makeBootstrappedDatabase(rootDirectory: rootDirectory, accountID: accountID)
    let repository = LocalChatRepository(database: databaseActor, paths: paths)
    return (repository, DatabaseTestContext(databaseActor: databaseActor, paths: paths))
}

func seedPerformanceMessages(
    databaseContext: DatabaseTestContext,
    conversationID: ConversationID,
    userID: UserID,
    count: Int
) async throws {
    let numbersCTE = """
    WITH
        digits(d) AS (
            VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9)
        ),
        numbers(value) AS (
            SELECT ones.d + tens.d * 10 + hundreds.d * 100 + thousands.d * 1000 + tenThousands.d * 10000 + 1
            FROM digits AS ones
            CROSS JOIN digits AS tens
            CROSS JOIN digits AS hundreds
            CROSS JOIN digits AS thousands
            CROSS JOIN digits AS tenThousands
        )
    """

    _ = try await databaseContext.databaseActor.write(paths: databaseContext.paths) { db in
        try db.execute(
            sql: """
            \(numbersCTE)
            INSERT INTO message_text (content_id, text, mentions_json, at_all, rich_text_json)
            SELECT
                'perf_text_' || value,
                'Perf Message ' || value,
                NULL,
                0,
                NULL
            FROM numbers
            WHERE value <= \(count);
            """
        )

        try db.execute(
            sql: """
            \(numbersCTE)
            INSERT INTO message (
                message_id,
                conversation_id,
                sender_id,
                client_msg_id,
                msg_type,
                direction,
                send_status,
                delivery_status,
                read_status,
                revoke_status,
                is_deleted,
                content_table,
                content_id,
                sort_seq,
                local_time
            )
            SELECT
                'perf_message_' || value,
                ?,
                ?,
                'perf_client_' || value,
                \(MessageType.text.rawValue),
                \(MessageDirection.outgoing.rawValue),
                \(MessageSendStatus.success.rawValue),
                0,
                \(MessageReadStatus.read.rawValue),
                0,
                0,
                'message_text',
                'perf_text_' || value,
                value,
                value
            FROM numbers
            WHERE value <= \(count);
            """,
            arguments: [conversationID.rawValue, userID.rawValue]
        )
    }
}

func databaseReadFails(using databaseActor: DatabaseActor, paths: AccountStoragePaths) async -> Bool {
    do {
        _ = try await databaseActor.tableNames(in: .main, paths: paths)
        return false
    } catch {
        return true
    }
}

func moveElementCount(in path: UIBezierPath) -> Int {
    var count = 0
    path.cgPath.applyWithBlock { elementPointer in
        if elementPointer.pointee.type == .moveToPoint {
            count += 1
        }
    }
    return count
}

func waitForCondition(
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    condition: @escaping () async throws -> Bool
) async throws {
    let startedAt = DispatchTime.now().uptimeNanoseconds

    while DispatchTime.now().uptimeNanoseconds - startedAt < timeoutNanoseconds {
        if try await condition() {
            return
        }

        try await Task.sleep(nanoseconds: 10_000_000)
    }

    Issue.record("Timed out waiting for condition")
}

func makeConversationRecord(
    id: ConversationID,
    userID: UserID,
    title: String = "Conversation",
    type: ConversationType = .single,
    targetID: String? = nil,
    isPinned: Bool = false,
    isMuted: Bool = false,
    unreadCount: Int = 0,
    draftText: String? = nil,
    avatarURL: String? = nil,
    sortTimestamp: Int64 = 1
) -> ConversationRecord {
    ConversationRecord(
        id: id,
        userID: userID,
        type: type,
        targetID: targetID ?? "\(id.rawValue)_target",
        title: title,
        avatarURL: avatarURL,
        lastMessageID: nil,
        lastMessageTime: sortTimestamp,
        lastMessageDigest: "Digest \(title)",
        unreadCount: unreadCount,
        draftText: draftText,
        isPinned: isPinned,
        isMuted: isMuted,
        isHidden: false,
        sortTimestamp: sortTimestamp,
        updatedAt: sortTimestamp,
        createdAt: sortTimestamp
    )
}

func makeContactRecord(
    contactID: ContactID,
    userID: UserID,
    wxid: String,
    nickname: String,
    remark: String? = nil,
    avatarURL: String? = nil,
    type: ContactType = .friend,
    isStarred: Bool = false,
    isBlocked: Bool = false,
    isDeleted: Bool = false,
    source: Int? = nil,
    extraJSON: String? = nil,
    timestamp: Int64 = 1
) -> ContactRecord {
    ContactRecord(
        contactID: contactID,
        userID: userID,
        wxid: wxid,
        nickname: nickname,
        remark: remark,
        avatarURL: avatarURL,
        type: type,
        isStarred: isStarred,
        isBlocked: isBlocked,
        isDeleted: isDeleted,
        source: source,
        extraJSON: extraJSON,
        updatedAt: timestamp,
        createdAt: timestamp
    )
}

func makeEmojiPanelState(
    recentEmojis: [EmojiAssetRecord],
    favoriteEmojis: [EmojiAssetRecord],
    packageEmojis: [EmojiAssetRecord]
) -> ChatEmojiPanelState {
    let package = EmojiPackageRecord(
        packageID: "pkg_stub",
        userID: "emoji_panel_user",
        title: "全部表情",
        author: "Tests",
        coverURL: nil,
        localCoverPath: nil,
        version: 1,
        status: .downloaded,
        sortOrder: 1,
        createdAt: 1,
        updatedAt: 1
    )
    return ChatEmojiPanelState(
        packages: [package],
        recentEmojis: recentEmojis,
        favoriteEmojis: favoriteEmojis,
        packageEmojisByPackageID: [package.packageID: packageEmojis]
    )
}

func makeEmojiAsset(
    emojiID: String,
    name: String,
    packageID: String? = "pkg_stub",
    isFavorite: Bool = false
) -> EmojiAssetRecord {
    EmojiAssetRecord(
        emojiID: emojiID,
        userID: "emoji_panel_user",
        packageID: packageID,
        emojiType: .package,
        name: name,
        md5: nil,
        localPath: nil,
        thumbPath: nil,
        cdnURL: nil,
        width: 128,
        height: 128,
        sizeBytes: 1024,
        useCount: 0,
        lastUsedAt: nil,
        isFavorite: isFavorite,
        isDeleted: false,
        extraJSON: nil,
        createdAt: 1,
        updatedAt: 1
    )
}

@MainActor
func button(in view: UIView, identifier: String) -> UIButton? {
    if let button = view as? UIButton, button.accessibilityIdentifier == identifier {
        return button
    }

    for subview in view.subviews {
        if let button = button(in: subview, identifier: identifier) {
            return button
        }
    }

    return nil
}

@MainActor
func button(in view: UIView, accessibilityLabel: String) -> UIButton? {
    if let button = view as? UIButton, button.accessibilityLabel == accessibilityLabel {
        return button
    }

    for subview in view.subviews {
        if let button = button(in: subview, accessibilityLabel: accessibilityLabel) {
            return button
        }
    }

    return nil
}

@MainActor
func findView(in view: UIView, identifier: String) -> UIView? {
    if view.accessibilityIdentifier == identifier {
        return view
    }

    for subview in view.subviews {
        if let matchingView = findView(in: subview, identifier: identifier) {
            return matchingView
        }
    }

    return nil
}

@MainActor
func findView<T: UIView>(ofType type: T.Type, in view: UIView) -> T? {
    if let matchingView = view as? T {
        return matchingView
    }

    for subview in view.subviews {
        if let matchingView = findView(ofType: type, in: subview) {
            return matchingView
        }
    }

    return nil
}

@MainActor
func rgbaComponents(for color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return (red, green, blue, alpha)
}

@MainActor
func findLabel(withText text: String, in view: UIView) -> UILabel? {
    if let label = view as? UILabel, label.text == text {
        return label
    }

    for subview in view.subviews {
        if let matchingLabel = findLabel(withText: text, in: subview) {
            return matchingLabel
        }
    }

    return nil
}
