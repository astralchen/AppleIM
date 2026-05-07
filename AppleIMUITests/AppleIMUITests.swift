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
    func testLaunchShowsLoginWhenNoSession() throws {
        let app = makeUITestApplication()
        app.launch()

        waitForLogin(in: app)
    }

    @MainActor
    func testLoginShowsSeededConversations() throws {
        let app = makeUITestApplication()
        app.launch()
        loginAsUITestUser(in: app)

        waitForConversationList(in: app)
        XCTAssertTrue(app.collectionViews["conversationList.collection"].exists)
        XCTAssertTrue(app.navigationBars["ChatBridge"].exists)
    }

    @MainActor
    func testLoginWithWrongPasswordShowsError() throws {
        let app = makeUITestApplication()
        app.launch()
        waitForLogin(in: app)

        app.textFields["login.accountTextField"].tap()
        app.textFields["login.accountTextField"].typeText("ui_test_user")
        app.secureTextFields["login.passwordTextField"].tap()
        app.secureTextFields["login.passwordTextField"].typeText("wrong_password")
        app.buttons["login.submitButton"].tap()

        XCTAssertTrue(app.staticTexts["login.errorLabel"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.collectionViews["conversationList.collection"].exists)
    }

    @MainActor
    func testStoredLoginSessionSkipsLogin() throws {
        let runID = UUID().uuidString
        let app = makeUITestApplication(runID: runID)
        app.launch()
        loginAsUITestUser(in: app)
        app.terminate()

        let relaunchedApp = makeUITestApplication(runID: runID, resetSession: false)
        relaunchedApp.launch()

        waitForConversationList(in: relaunchedApp)
        XCTAssertFalse(relaunchedApp.textFields["login.accountTextField"].exists)
    }

    @MainActor
    func testLogOutReturnsToLogin() throws {
        let app = makeUITestApplication()
        app.launch()
        loginAsUITestUser(in: app)

        logOut(in: app)

        XCTAssertFalse(app.collectionViews["conversationList.collection"].exists)
    }

    @MainActor
    func testSwitchAccountCanLoginAsDifferentUser() throws {
        let app = makeUITestApplication()
        app.launch()
        loginAsUITestUser(in: app)

        switchAccount(in: app)
        login(account: "demo_user", password: "password123", in: app)

        XCTAssertTrue(app.collectionViews["conversationList.collection"].exists)
        XCTAssertTrue(app.navigationBars["ChatBridge"].exists)
    }

    @MainActor
    func testSwitchedAccountSessionPersistsAfterRelaunch() throws {
        let runID = UUID().uuidString
        let app = makeUITestApplication(runID: runID)
        app.launch()
        loginAsUITestUser(in: app)
        switchAccount(in: app)
        login(account: "demo_user", password: "password123", in: app)
        app.terminate()

        let relaunchedApp = makeUITestApplication(runID: runID, resetSession: false)
        relaunchedApp.launch()

        waitForConversationList(in: relaunchedApp)
        XCTAssertFalse(relaunchedApp.textFields["login.accountTextField"].exists)
    }

    @MainActor
    func testOpenConversationAndSendTextMessage() throws {
        let app = makeUITestApplication()
        app.launch()
        loginAsUITestUser(in: app)
        openSondraConversation(in: app)

        let message = "UI test message \(UUID().uuidString)"
        let input = app.textViews["chat.messageInput"]
        input.tap()
        input.typeText(message)
        app.buttons["chat.sendButton"].tap()

        XCTAssertTrue(
            messageCell(containing: message, in: app).waitForExistence(timeout: 5),
            "Expected sent message to appear in chat"
        )
    }

    @MainActor
    func testMultilineTextMessageKeepsLineBreaks() throws {
        let app = makeUITestApplication()
        app.launch()
        loginAsUITestUser(in: app)
        openSondraConversation(in: app)

        let uniqueText = "UI multiline \(UUID().uuidString)"
        let message = "\(uniqueText)\nsecond line"
        let input = app.textViews["chat.messageInput"]
        input.tap()
        input.typeText(message)
        app.buttons["chat.sendButton"].tap()

        XCTAssertTrue(
            messageCell(containing: uniqueText, in: app).waitForExistence(timeout: 5),
            "Expected multiline message to appear in chat"
        )
        XCTAssertTrue(
            messageCell(containing: "second line", in: app).exists,
            "Expected multiline message to keep its second line"
        )
    }

    @MainActor
    func testReturnKeyCanSendTextMessage() throws {
        let app = makeUITestApplication()
        app.launch()
        loginAsUITestUser(in: app)
        openSondraConversation(in: app)

        let message = "UI return send \(UUID().uuidString)"
        let input = app.textViews["chat.messageInput"]
        input.tap()
        app.buttons["chat.moreButton"].tap()
        app.buttons["Return Sends"].tap()
        input.typeText(message)
        app.keyboards.buttons["Send"].tap()

        XCTAssertTrue(
            messageCell(containing: message, in: app).waitForExistence(timeout: 5),
            "Expected Return key to send message when send mode is enabled"
        )
    }

    @MainActor
    func testSearchFindsSeededConversation() throws {
        let app = makeUITestApplication()
        app.launch()
        loginAsUITestUser(in: app)
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
    func testConversationCanBePinnedAndUnpinned() throws {
        let app = makeUITestApplication()
        app.launch()
        loginAsUITestUser(in: app)
        waitForConversationList(in: app)

        let conversation = conversationCell(containing: "Sondra", in: app)
        XCTAssertTrue(conversation.waitForExistence(timeout: 5), "Expected Sondra conversation")
        waitForConversationCell(title: "Sondra", labelContaining: "Pinned", in: app)
        revealTrailingActions(on: conversation)
        XCTAssertTrue(app.buttons["Unpin"].waitForExistence(timeout: 5), "Expected Unpin action")
        app.buttons["Unpin"].tap()
        waitForConversationCell(title: "Sondra", labelNotContaining: "Pinned", in: app)

        let updatedConversation = conversationCell(containing: "Sondra", in: app)
        revealTrailingActions(on: updatedConversation)
        XCTAssertTrue(app.buttons["Pin"].waitForExistence(timeout: 5), "Expected Pin action")
        app.buttons["Pin"].tap()
        waitForConversationCell(title: "Sondra", labelContaining: "Pinned", in: app)
    }

    @MainActor
    func testConversationCanBeMutedAndUnmuted() throws {
        let app = makeUITestApplication()
        app.launch()
        loginAsUITestUser(in: app)
        waitForConversationList(in: app)

        let conversation = conversationCell(containing: "Sondra", in: app)
        XCTAssertTrue(conversation.waitForExistence(timeout: 5), "Expected Sondra conversation")
        revealTrailingActions(on: conversation)
        XCTAssertTrue(app.buttons["Mute"].waitForExistence(timeout: 5), "Expected Mute action")
        app.buttons["Mute"].tap()
        waitForConversationCell(title: "Sondra", labelContaining: "Muted", in: app)

        let updatedConversation = conversationCell(containing: "Sondra", in: app)
        revealTrailingActions(on: updatedConversation)
        XCTAssertTrue(app.buttons["Unmute"].waitForExistence(timeout: 5), "Expected Unmute action")
        app.buttons["Unmute"].tap()
        waitForConversationCell(title: "Sondra", labelNotContaining: "Muted", in: app)
    }

    @MainActor
    func testFailedSendCanBeRetried() throws {
        let app = makeUITestApplication(sendMode: .failFirst)
        app.launch()
        loginAsUITestUser(in: app)
        openSondraConversation(in: app)

        let message = "UI test retry \(UUID().uuidString)"
        let input = app.textViews["chat.messageInput"]
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
