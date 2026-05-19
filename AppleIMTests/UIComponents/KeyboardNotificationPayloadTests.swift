import Testing
import Foundation
import UIKit

@testable import AppleIM

extension AppleIMTests {
    @MainActor
    @Test func keyboardNotificationKindMapsAllUIKitKeyboardNotifications() throws {
        let expectedPairs: [(KeyboardNotificationKind, Notification.Name)] = [
            (.willShow, UIResponder.keyboardWillShowNotification),
            (.didShow, UIResponder.keyboardDidShowNotification),
            (.willHide, UIResponder.keyboardWillHideNotification),
            (.didHide, UIResponder.keyboardDidHideNotification),
            (.willChangeFrame, UIResponder.keyboardWillChangeFrameNotification),
            (.didChangeFrame, UIResponder.keyboardDidChangeFrameNotification)
        ]

        #expect(KeyboardNotificationKind.allCases.count == expectedPairs.count)
        for (kind, name) in expectedPairs {
            #expect(kind.notificationName == name)
            #expect(KeyboardNotificationKind(name: name) == kind)
        }
        #expect(KeyboardNotificationKind(name: Notification.Name("chatbridge.unknown")) == nil)
    }

    @MainActor
    @Test func keyboardNotificationPayloadParsesFramesAnimationAndLocalFlag() throws {
        let beginFrame = CGRect(x: 0, y: 844, width: 390, height: 0)
        let endFrame = CGRect(x: 0, y: 544, width: 390, height: 300)
        let notification = Notification(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameBeginUserInfoKey: beginFrame,
                UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: endFrame),
                UIResponder.keyboardAnimationDurationUserInfoKey: NSNumber(value: 0.35),
                UIResponder.keyboardAnimationCurveUserInfoKey: NSNumber(value: UIView.AnimationOptions.curveEaseInOut.rawValue),
                UIResponder.keyboardIsLocalUserInfoKey: NSNumber(value: true)
            ]
        )

        let payload = try #require(KeyboardNotificationPayload(notification))

        #expect(payload.kind == .willChangeFrame)
        #expect(payload.beginFrame == beginFrame)
        #expect(payload.endFrame == endFrame)
        #expect(payload.animationDuration == 0.35)
        #expect(payload.animationCurveRawValue == UIView.AnimationOptions.curveEaseInOut.rawValue)
        #expect(payload.animationOptions == UIView.AnimationOptions(rawValue: UIView.AnimationOptions.curveEaseInOut.rawValue << 16))
        #expect(payload.isLocal == true)
        #expect(payload.userInfo[UIResponder.keyboardFrameBeginUserInfoKey] as? CGRect == beginFrame)
        #expect(payload.userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect == endFrame)
        #expect(payload.userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval == 0.35)
        #expect(payload.userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt == UIView.AnimationOptions.curveEaseInOut.rawValue)
        #expect(payload.userInfo[UIResponder.keyboardIsLocalUserInfoKey] as? Bool == true)
    }

    @MainActor
    @Test func keyboardNotificationPayloadSupportsMissingFrames() throws {
        let notification = Notification(
            name: UIResponder.keyboardDidHideNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardAnimationDurationUserInfoKey: 0,
                UIResponder.keyboardAnimationCurveUserInfoKey: UIView.AnimationOptions.curveLinear.rawValue
            ]
        )
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))

        let payload = try #require(KeyboardNotificationPayload(notification))

        #expect(payload.kind == .didHide)
        #expect(payload.beginFrame == nil)
        #expect(payload.endFrame == nil)
        #expect(payload.beginFrame(in: view) == nil)
        #expect(payload.endFrame(in: view) == nil)
        #expect(payload.isVisible(in: view) == nil)
        #expect(payload.animationDuration == 0)
        #expect(payload.animationCurveRawValue == UIView.AnimationOptions.curveLinear.rawValue)
        #expect(payload.isLocal == nil)
    }
}
