//
//  AvatarImageLoader.swift
//  AppleIM
//
//  头像图片加载服务
//  收口本地头像读取、远程头像拉取和内存缓存，避免 UI 控件直接处理 I/O

import UIKit

/// 头像加载任务。
nonisolated protocol AvatarImageLoadTask: AnyObject, Sendable {
    /// 取消头像加载。
    func cancel()
}

/// 头像图片加载接口。
@MainActor
protocol AvatarImageLoading: AnyObject {
    /// 加载头像图片。命中缓存或本地路径时会同步回调；远程图片异步回调。
    @discardableResult
    func loadImage(from value: String, completion: @escaping (UIImage?) -> Void) -> (any AvatarImageLoadTask)?
}

/// 默认头像图片加载器。
@MainActor
final class DefaultAvatarImageLoader: AvatarImageLoading {
    static let shared = DefaultAvatarImageLoader()

    private let cache = NSCache<NSString, UIImage>()

    private init() {}

    @discardableResult
    func loadImage(from value: String, completion: @escaping (UIImage?) -> Void) -> (any AvatarImageLoadTask)? {
        let avatarURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !avatarURL.isEmpty else {
            completion(nil)
            return nil
        }

        let cacheKey = avatarURL as NSString
        if let cachedImage = cache.object(forKey: cacheKey) {
            completion(cachedImage)
            return nil
        }

        if let localImage = Self.localAvatarImage(from: avatarURL) {
            cache.setObject(localImage, forKey: cacheKey)
            completion(localImage)
            return nil
        }

        guard let url = URL(string: avatarURL), ["http", "https"].contains(url.scheme?.lowercased()) else {
            completion(nil)
            return nil
        }

        let task = Task { [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                try Task.checkCancellation()
                guard let image = UIImage(data: data) else {
                    completion(nil)
                    return
                }

                self?.cache.setObject(image, forKey: cacheKey)
                completion(image)
            } catch is CancellationError {
                return
            } catch {
                completion(nil)
            }
        }
        return AvatarImageTask(task: task)
    }

    /// 从本地路径或 file URL 加载头像。
    private static func localAvatarImage(from value: String) -> UIImage? {
        if let url = URL(string: value), url.isFileURL {
            return UIImage(contentsOfFile: url.path)
        }

        guard !value.hasPrefix("http://"), !value.hasPrefix("https://") else {
            return nil
        }

        return UIImage(contentsOfFile: value)
    }
}

/// 基于 Swift Task 的头像加载任务。
nonisolated private final class AvatarImageTask: AvatarImageLoadTask, @unchecked Sendable {
    private let task: Task<Void, Never>

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task.cancel()
    }
}
