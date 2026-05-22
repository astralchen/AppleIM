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

enum TestChatError: Error, Sendable {
    case paginationFailed
    case messageActionFailed
    case expectedFailure
}

func makeChatRow(
    id: MessageID,
    text: String,
    sortSequence: Int64,
    sentAt: Int64 = 0,
    senderAvatarURL: String? = nil,
    isOutgoing: Bool = true
) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .text(text),
        sortSequence: sortSequence,
        sentAt: sentAt,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        senderAvatarURL: senderAvatarURL,
        isOutgoing: isOutgoing,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}

@MainActor
func makeScrollableChatViewController(
    title: String,
    rowPrefix: String,
    useEmojiUseCase: Bool = false
) async throws -> (
    window: UIWindow,
    viewController: ChatViewController,
    collectionView: UICollectionView,
    inputBar: ChatInputBarView
) {
    let rows = (1...36).map { index in
        makeChatRow(
            id: MessageID(rawValue: "\(rowPrefix)_\(index)"),
            text: "\(title) message \(index)",
            sortSequence: Int64(index)
        )
    }
    let viewModel: ChatViewModel
    if useEmojiUseCase {
        viewModel = ChatViewModel(
            useCase: EmojiPanelStubChatUseCase(initialRows: rows),
            title: title
        )
    } else {
        viewModel = ChatViewModel(
            useCase: PagingStubChatUseCase(
                initialPage: ChatMessagePage(rows: rows, hasMore: false, nextBeforeSortSequence: nil),
                olderPage: ChatMessagePage(rows: [], hasMore: false, nextBeforeSortSequence: nil)
            ),
            title: title
        )
    }
    let viewController = ChatViewController(viewModel: viewModel)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = viewController
    window.makeKeyAndVisible()

    viewController.loadViewIfNeeded()
    try await waitForCondition(timeoutNanoseconds: 10_000_000_000) {
        guard let collectionView = findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView else {
            return false
        }
        return collectionView.numberOfItems(inSection: 0) == rows.count
    }
    window.layoutIfNeeded()

    let collectionView = try #require(findView(in: viewController.view, identifier: "chat.collection") as? UICollectionView)
    let inputBar = try #require(findView(ofType: ChatInputBarView.self, in: viewController.view))
    return (window, viewController, collectionView, inputBar)
}

@MainActor
func assertChatCollectionCanLeaveBottomAfterUserDrag(
    viewController: ChatViewController,
    collectionView: UICollectionView,
    window: UIWindow
) throws {
    let lastItem = collectionView.numberOfItems(inSection: 0) - 1
    try #require(lastItem > 0)

    collectionView.scrollToItem(at: IndexPath(item: lastItem, section: 0), at: .bottom, animated: false)
    window.layoutIfNeeded()
    collectionView.layoutIfNeeded()

    let bottomOffsetY = collectionView.contentOffset.y
    let minOffsetY = -collectionView.adjustedContentInset.top
    let targetOffsetY = max(minOffsetY, bottomOffsetY - 160)
    try #require(targetOffsetY < bottomOffsetY - 1)

    viewController.scrollViewWillBeginDragging(collectionView)
    collectionView.setContentOffset(
        CGPoint(x: collectionView.contentOffset.x, y: targetOffsetY),
        animated: false
    )
    viewController.viewDidLayoutSubviews()
    collectionView.layoutIfNeeded()

    #expect(collectionView.contentOffset.y <= targetOffsetY + 1)
}

@MainActor
func moveChatCollectionAwayFromBottom(
    viewController: ChatViewController,
    collectionView: UICollectionView,
    window: UIWindow
) throws {
    try assertChatCollectionCanLeaveBottomAfterUserDrag(
        viewController: viewController,
        collectionView: collectionView,
        window: window
    )
    viewController.scrollViewDidEndDragging(collectionView, willDecelerate: false)
}

@MainActor
func latestMessageCellIsAboveInputBar(
    collectionView: UICollectionView,
    item: Int,
    inputBar: ChatInputBarView,
    in view: UIView
) -> Bool {
    guard let cell = collectionView.cellForItem(at: IndexPath(item: item, section: 0)) else {
        return false
    }
    let cellFrame = cell.convert(cell.bounds, to: view)
    let inputFrame = inputBar.convert(inputBar.bounds, to: view)
    return cellFrame.maxY <= inputFrame.minY + 1
}

func timestamp(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    calendar: Calendar
) throws -> Int64 {
    let date = try #require(
        calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )
    )
    return Int64(date.timeIntervalSince1970)
}

func makeRevokedChatRow(id: MessageID, text: String, sortSequence: Int64) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .revoked(ChatMessageRowContent.RevokedContent(noticeText: text)),
        sortSequence: sortSequence,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: true,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}

func makeVoiceRow(id: MessageID, sortSequence: Int64, isUnplayed: Bool) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .voice(
            ChatMessageRowContent.VoiceContent(
                localPath: "/tmp/\(id.rawValue).m4a",
                durationMilliseconds: 2_000,
                isUnplayed: isUnplayed,
                isPlaying: false
            )
        ),
        sortSequence: sortSequence,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: false,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}

func makeImageRow(id: MessageID, sortSequence: Int64) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .image(
            ChatMessageRowContent.ImageContent(
                thumbnailPath: "/tmp/\(id.rawValue).jpg"
            )
        ),
        sortSequence: sortSequence,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: false,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}

func makeVideoRow(id: MessageID, sortSequence: Int64) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .video(
            ChatMessageRowContent.VideoContent(
                thumbnailPath: "/tmp/\(id.rawValue).jpg",
                localPath: "/tmp/\(id.rawValue).mov",
                durationMilliseconds: 3_000
            )
        ),
        sortSequence: sortSequence,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: false,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}

func makeFileRow(id: MessageID, sortSequence: Int64) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .file(
            ChatMessageRowContent.FileContent(
                fileName: "\(id.rawValue).pdf",
                fileExtension: "pdf",
                localPath: "/tmp/\(id.rawValue).pdf",
                sizeBytes: 1_024
            )
        ),
        sortSequence: sortSequence,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: false,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}

func makeRevokedRow(id: MessageID, sortSequence: Int64) -> ChatMessageRowState {
    ChatMessageRowState(
        id: id,
        content: .revoked("你撤回了一条消息"),
        sortSequence: sortSequence,
        timeText: "Now",
        statusText: nil,
        uploadProgress: nil,
        isOutgoing: true,
        canRetry: false,
        canDelete: true,
        canRevoke: false
    )
}



func rowText(_ row: ChatMessageRowState) -> String {
    switch row.content {
    case let .text(text):
        return text
    case let .revoked(content):
        return content.noticeText
    case .image:
        return "Image"
    case let .voice(voice):
        return "Voice \(durationText(milliseconds: voice.durationMilliseconds))"
    case let .video(video):
        return "Video \(durationText(milliseconds: video.durationMilliseconds))"
    case let .file(file):
        return file.fileName
    case let .emoji(emoji):
        return emoji.name ?? "Emoji"
    }
}

func isImageContent(_ row: ChatMessageRowState) -> Bool {
    if case .image = row.content {
        return true
    }
    return false
}

func imageThumbnailPath(_ row: ChatMessageRowState) -> String? {
    if case let .image(image) = row.content {
        return image.thumbnailPath
    }
    return nil
}

func isVoiceContent(_ row: ChatMessageRowState) -> Bool {
    if case .voice = row.content {
        return true
    }
    return false
}

func voiceLocalPath(_ row: ChatMessageRowState) -> String? {
    if case let .voice(voice) = row.content {
        return voice.localPath
    }
    return nil
}

func isUnplayedVoiceContent(_ row: ChatMessageRowState) -> Bool {
    if case let .voice(voice) = row.content {
        return voice.isUnplayed
    }
    return false
}

func isPlayingVoiceContent(_ row: ChatMessageRowState) -> Bool {
    if case let .voice(voice) = row.content {
        return voice.isPlaying
    }
    return false
}

func isVideoContent(_ row: ChatMessageRowState) -> Bool {
    if case .video = row.content {
        return true
    }
    return false
}

func videoThumbnailPath(_ row: ChatMessageRowState) -> String? {
    if case let .video(video) = row.content {
        return video.thumbnailPath
    }
    return nil
}

@MainActor
func largestLoadedImageView(in view: UIView) -> UIImageView? {
    var candidates: [UIImageView] = []

    func collect(from view: UIView) {
        if let imageView = view as? UIImageView, imageView.image != nil {
            candidates.append(imageView)
        }
        view.subviews.forEach(collect)
    }

    collect(from: view)
    return candidates.max { lhs, rhs in
        (lhs.bounds.width * lhs.bounds.height) < (rhs.bounds.width * rhs.bounds.height)
    }
}

func durationText(milliseconds: Int) -> String {
    ChatMessageRowContent.voiceDurationDisplayText(milliseconds: milliseconds)
}
