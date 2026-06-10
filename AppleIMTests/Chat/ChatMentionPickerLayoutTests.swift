import Testing
import Foundation
import UIKit

@testable import AppleIM

extension AppleIMTests {
    @MainActor
    @Test func mentionPickerMultiSelectRowsShowSelectionControlBeforeAvatar() throws {
        let viewController = ChatMentionPickerViewController(options: mentionPickerSmallOptions)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 560))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        window.layoutIfNeeded()
        viewController.view.layoutIfNeeded()

        let multiButton = try #require(button(in: viewController.view, identifier: "chat.mentionPicker.multiButton"))
        multiButton.sendActions(for: .touchUpInside)
        window.layoutIfNeeded()
        viewController.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        window.layoutIfNeeded()
        viewController.view.layoutIfNeeded()

        let selectionControl = try #require(
            findView(in: viewController.view, identifier: "chat.mentionSelectionControl.sondra")
        )
        let selectionFrame = selectionControl.convert(selectionControl.bounds, to: viewController.view)
        let memberCell = try #require(
            findView(in: viewController.view, identifier: "chat.mentionSelection.sondra") as? UICollectionViewListCell
        )
        let contentFrame = memberCell.contentView.convert(memberCell.contentView.bounds, to: viewController.view)

        #expect(abs(selectionFrame.width - 28) <= 0.5)
        #expect(abs(selectionFrame.height - 28) <= 0.5)
        #expect(selectionFrame.minX >= viewController.view.layoutMargins.left - 0.5)
        #expect(contentFrame.minX - selectionFrame.maxX >= 12)
    }

    @MainActor
    @Test func mentionPickerSectionIndexButtonScrollsToMatchingSection() throws {
        let viewController = ChatMentionPickerViewController(options: mentionPickerIndexedOptions)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 360))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        window.layoutIfNeeded()
        viewController.view.layoutIfNeeded()

        let collectionView = try #require(
            findView(in: viewController.view, identifier: "chat.mentionPicker.collection") as? UICollectionView
        )
        collectionView.layoutIfNeeded()
        let indexButton = try #require(button(in: viewController.view, identifier: "chat.mentionPicker.sectionIndex.S"))
        let indexButtonFrame = indexButton.convert(indexButton.bounds, to: viewController.view)
        #expect(indexButtonFrame.width >= 40)

        let initialOffsetY = collectionView.contentOffset.y
        let animationsEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer {
            UIView.setAnimationsEnabled(animationsEnabled)
        }

        indexButton.sendActions(for: .touchUpInside)
        window.layoutIfNeeded()
        viewController.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        #expect(collectionView.contentOffset.y > initialOffsetY + 20)
    }

    @MainActor
    @Test func mentionPickerScrollPositionHighlightsMatchingSectionIndex() throws {
        let viewController = ChatMentionPickerViewController(options: mentionPickerIndexedOptions)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 360))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        window.layoutIfNeeded()
        viewController.view.layoutIfNeeded()

        let collectionView = try #require(
            findView(in: viewController.view, identifier: "chat.mentionPicker.collection") as? UICollectionView
        )
        collectionView.layoutIfNeeded()
        let sIndexButton = try #require(button(in: viewController.view, identifier: "chat.mentionPicker.sectionIndex.S"))
        let mIndexButton = try #require(button(in: viewController.view, identifier: "chat.mentionPicker.sectionIndex.M"))

        collectionView.scrollToItem(at: IndexPath(item: 0, section: 5), at: .top, animated: false)
        collectionView.delegate?.scrollViewDidScroll?(collectionView)
        window.layoutIfNeeded()
        viewController.view.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        #expect(sIndexButton.configuration?.baseForegroundColor == .systemBlue)
        #expect(mIndexButton.configuration?.baseForegroundColor == .secondaryLabel)
    }

    @MainActor
    @Test func mentionPickerSmallIndexTapKeepsSelectedHighlightWhenContentCannotScroll() throws {
        let viewController = ChatMentionPickerViewController(options: mentionPickerSmallOptions)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 560))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        window.layoutIfNeeded()
        viewController.view.layoutIfNeeded()

        let collectionView = try #require(
            findView(in: viewController.view, identifier: "chat.mentionPicker.collection") as? UICollectionView
        )
        collectionView.layoutIfNeeded()
        let sIndexButton = try #require(button(in: viewController.view, identifier: "chat.mentionPicker.sectionIndex.S"))
        let mIndexButton = try #require(button(in: viewController.view, identifier: "chat.mentionPicker.sectionIndex.M"))

        sIndexButton.sendActions(for: .touchUpInside)
        collectionView.delegate?.scrollViewDidScroll?(collectionView)
        window.layoutIfNeeded()
        viewController.view.layoutIfNeeded()

        #expect(sIndexButton.configuration?.baseForegroundColor == .systemBlue)
        #expect(mIndexButton.configuration?.baseForegroundColor == .secondaryLabel)
    }

    @MainActor
    @Test func mentionPickerBottomIndexTapHighlightsTappedSection() throws {
        let viewController = ChatMentionPickerViewController(options: mentionPickerSmallOptions)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 560))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        viewController.loadViewIfNeeded()
        window.layoutIfNeeded()
        viewController.view.layoutIfNeeded()

        let collectionView = try #require(
            findView(in: viewController.view, identifier: "chat.mentionPicker.collection") as? UICollectionView
        )
        collectionView.layoutIfNeeded()
        let yIndexButton = try #require(button(in: viewController.view, identifier: "chat.mentionPicker.sectionIndex.Y"))
        let mIndexButton = try #require(button(in: viewController.view, identifier: "chat.mentionPicker.sectionIndex.M"))

        yIndexButton.sendActions(for: .touchUpInside)
        collectionView.delegate?.scrollViewDidScroll?(collectionView)
        window.layoutIfNeeded()
        viewController.view.layoutIfNeeded()

        #expect(yIndexButton.configuration?.baseForegroundColor == .systemBlue)
        #expect(mIndexButton.configuration?.baseForegroundColor == .secondaryLabel)
    }

    private var mentionPickerSmallOptions: [ChatMentionOptionState] {
        [
            ChatMentionOptionState(id: "__all__", userID: nil, displayName: "所有人", mentionsAll: true),
            ChatMentionOptionState(id: "sondra", userID: "sondra", displayName: "Sondra", mentionsAll: false),
            ChatMentionOptionState(id: "qa_ming", userID: "qa_ming", displayName: "明明", mentionsAll: false),
            ChatMentionOptionState(id: "yanyan", userID: "yanyan", displayName: "Yanyan", mentionsAll: false),
            ChatMentionOptionState(id: "zara", userID: "zara", displayName: "Zara", mentionsAll: false)
        ]
    }

    private var mentionPickerIndexedOptions: [ChatMentionOptionState] {
        var options = [
            ChatMentionOptionState(id: "__all__", userID: nil, displayName: "所有人", mentionsAll: true)
        ]
        options.append(contentsOf: mentionPickerOptions(prefix: "a", displayPrefix: "Alpha", count: 20))
        options.append(contentsOf: mentionPickerOptions(prefix: "b", displayPrefix: "Beta", count: 20))
        options.append(contentsOf: mentionPickerOptions(prefix: "m", displayPrefix: "Ming", count: 20))
        options.append(contentsOf: mentionPickerOptions(prefix: "s", displayPrefix: "Sondra", count: 8))
        return options
    }

    private func mentionPickerOptions(
        prefix: String,
        displayPrefix: String,
        count: Int
    ) -> [ChatMentionOptionState] {
        (0..<count).map { index in
            let id = "\(prefix)_\(index)"
            return ChatMentionOptionState(
                id: id,
                userID: id,
                displayName: "\(displayPrefix) \(String(format: "%02d", index))",
                mentionsAll: false
            )
        }
    }
}
