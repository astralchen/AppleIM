//
//  ChatViewControllerCoordinators.swift
//  AppleIM
//
//  聊天页 UI 协调 helper
//

import AVKit
import UIKit

/// 输入附件状态协调器。
@MainActor
final class ChatInputAttachmentCoordinator {
    private(set) var previews: [ChatPendingAttachmentPreviewItem] = []
    private var mediaByID: [String: ChatComposerMedia] = [:]

    func mediaForSendingAndClear() -> [ChatComposerMedia] {
        let media = previews.compactMap { mediaByID[$0.id] }
        previews.removeAll()
        mediaByID.removeAll()
        return media
    }

    func upsertPreview(_ item: ChatPendingAttachmentPreviewItem) -> [ChatPendingAttachmentPreviewItem] {
        if let index = previews.firstIndex(where: { $0.id == item.id }) {
            previews[index] = item
        } else {
            previews.append(item)
        }
        return previews
    }

    func storePreparedMedia(_ preparedMedia: ChatPhotoLibraryPreparedMedia) -> [ChatPendingAttachmentPreviewItem] {
        mediaByID[preparedMedia.id] = preparedMedia.media
        return upsertPreview(
            ChatPendingAttachmentPreviewItem(
                id: preparedMedia.id,
                image: preparedMedia.preview.image,
                title: preparedMedia.preview.title,
                durationText: preparedMedia.preview.durationText,
                isVideo: preparedMedia.preview.isVideo,
                isLoading: false
            )
        )
    }

    func remove(id: String) -> [ChatPendingAttachmentPreviewItem] {
        previews.removeAll { $0.id == id }
        mediaByID[id] = nil
        return previews
    }
}

/// 媒体预览与播放协调器。
@MainActor
final class ChatMediaPreviewPresenter {
    private let temporaryMediaFileManager: any TemporaryMediaFileManaging

    init(temporaryMediaFileManager: any TemporaryMediaFileManaging) {
        self.temporaryMediaFileManager = temporaryMediaFileManager
    }

    func makeVideoPlayer(for row: ChatMessageRowState) -> AVPlayerViewController? {
        guard case let .video(video) = row.content else {
            return nil
        }
        let url = URL(fileURLWithPath: video.localPath)
        guard temporaryMediaFileManager.fileExists(at: url) else {
            return nil
        }

        let playerViewController = AVPlayerViewController()
        playerViewController.player = AVPlayer(url: url)
        return playerViewController
    }
}
