//
//  AppleIMUITestsLaunchTests.swift
//  AppleIMUITests
//

import XCTest

final class AppleIMUITestsLaunchTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = makeUITestApplication()
        app.launch()
        loginAsUITestUser(in: app)
        waitForConversationList(in: app)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
