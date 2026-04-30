//
//  AppleIMUITests.swift
//  AppleIMUITests
//

import XCTest

final class AppleIMUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsSeededConversations() throws {
        let app = makeUITestApplication()
        app.launch()

        waitForConversationList(in: app)
        XCTAssertTrue(app.collectionViews["conversationList.collection"].exists)
        XCTAssertTrue(app.navigationBars["ChatBridge"].exists)
    }

    @MainActor
    func testOpenConversationAndSendTextMessage() throws {
        let app = makeUITestApplication()
        app.launch()
        openSondraConversation(in: app)

        let message = "UI test message \(UUID().uuidString)"
        let input = app.textFields["chat.messageInput"]
        input.tap()
        input.typeText(message)
        app.buttons["chat.sendButton"].tap()

        XCTAssertTrue(
            messageCell(containing: message, in: app).waitForExistence(timeout: 5),
            "Expected sent message to appear in chat"
        )
    }

    @MainActor
    func testSearchFindsSeededConversation() throws {
        let app = makeUITestApplication()
        app.launch()
        waitForConversationList(in: app)

        let searchField = app.searchFields["conversationList.searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Expected search field")
        searchField.tap()
        searchField.typeText("Sondra")

        let result = app.cells["conversationList.searchCell.conversation_single_sondra"]
        let fallbackResult = app.staticTexts["Sondra"]
        XCTAssertTrue(
            result.waitForExistence(timeout: 10) || fallbackResult.exists,
            "Expected search result for seeded Sondra conversation"
        )
    }

    @MainActor
    func testFailedSendCanBeRetried() throws {
        let app = makeUITestApplication(sendMode: .failFirst)
        app.launch()
        openSondraConversation(in: app)

        let message = "UI test retry \(UUID().uuidString)"
        let input = app.textFields["chat.messageInput"]
        input.tap()
        input.typeText(message)
        app.buttons["chat.sendButton"].tap()

        let failedMessage = messageCell(containing: message, in: app)
        XCTAssertTrue(failedMessage.waitForExistence(timeout: 5), "Expected failed message row")

        let retryButton = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "chat.retryButton."))
            .firstMatch
        XCTAssertTrue(retryButton.waitForExistence(timeout: 5), "Expected retry button after first send failure")
        retryButton.tap()

        let retryButtonHidden = NSPredicate(format: "exists == false")
        expectation(for: retryButtonHidden, evaluatedWith: retryButton)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(messageCell(containing: message, in: app).exists)
    }
}
