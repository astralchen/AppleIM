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
        XCTAssertTrue(app.navigationBars["Messages"].exists)
        XCTAssertTrue(app.tabBars.buttons["Account"].exists)
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
    func testDeleteLocalDataReturnsToLoginAndReinitializesAccount() throws {
        let runID = UUID().uuidString
        let app = makeUITestApplication(runID: runID)
        app.launch()
        loginAsUITestUser(in: app)

        deleteLocalData(in: app)

        XCTAssertFalse(app.collectionViews["conversationList.collection"].exists)

        loginAsUITestUser(in: app)
        waitForConversationList(in: app)
    }

    @MainActor
    func testSwitchAccountCanLoginAsDifferentUser() throws {
        let app = makeUITestApplication()
        app.launch()
        loginAsUITestUser(in: app)

        switchAccount(in: app)
        login(account: "demo_user", password: "password123", in: app)

        XCTAssertTrue(app.collectionViews["conversationList.collection"].exists)
        XCTAssertTrue(app.navigationBars["Messages"].exists)
        XCTAssertTrue(app.tabBars.buttons["Account"].exists)
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
        XCTAssertTrue(app.buttons["chat.voiceButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["chat.sendButton"].exists)

        input.tap()
        input.typeText(message)
        XCTAssertTrue(app.buttons["chat.sendButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["chat.voiceButton"].exists)
        app.buttons["chat.sendButton"].tap()

        XCTAssertTrue(
            messageCell(containing: message, in: app).waitForExistence(timeout: 5),
            "Expected sent message to appear in chat"
        )
        let sentMessage = messageCell(containing: message, in: app)
        XCTAssertLessThanOrEqual(
            sentMessage.frame.maxY,
            input.frame.minY,
            "Expected sent message to stay above the input bar"
        )
        XCTAssertTrue(app.buttons["chat.voiceButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["chat.sendButton"].exists)
    }

    @MainActor
    func testEmojiPanelOpensFromMoreMenu() throws {
        let app = makeUITestApplication()
        app.launch()
        loginAsUITestUser(in: app)
        openSondraConversation(in: app)

        openEmojiPanel(in: app)

        XCTAssertTrue(app.otherElements["chat.emojiInputPanel"].exists)
    }

    @MainActor
    func testSendingEmojiShowsEmojiMessage() throws {
        let app = makeUITestApplication()
        app.launch()
        loginAsUITestUser(in: app)
        openSondraConversation(in: app)
        openEmojiPanel(in: app)
        selectEmojiPanelSection("收藏", in: app)

        let emoji = app.buttons["chat.emojiItem.cb_smile"]
        XCTAssertTrue(emoji.waitForExistence(timeout: 5), "Expected seeded favorite emoji")
        emoji.tap()

        let sentEmoji = app.collectionViews["chat.collection"]
            .cells
            .matching(NSPredicate(format: "label CONTAINS %@", "Smile"))
            .firstMatch
        XCTAssertTrue(sentEmoji.waitForExistence(timeout: 5), "Expected sent emoji message")
        let input = app.textViews["chat.messageInput"]
        XCTAssertTrue(
            waitForElement(sentEmoji, toStayAbove: input, timeout: 15),
            "Expected sent emoji message to stay above the input bar"
        )
    }

    @MainActor
    func testEmojiCanBeFavoritedAndUnfavorited() throws {
        let app = makeUITestApplication()
        app.launch()
        loginAsUITestUser(in: app)
        openSondraConversation(in: app)
        openEmojiPanel(in: app)
        selectEmojiPanelSection("ChatBridge", in: app)

        let favoriteButton = app.buttons["chat.emojiFavorite.cb_ok"]
        XCTAssertTrue(favoriteButton.waitForExistence(timeout: 5), "Expected package emoji favorite button")
        favoriteButton.tap()

        selectEmojiPanelSection("收藏", in: app)
        let favoritedEmoji = app.buttons["chat.emojiItem.cb_ok"]
        XCTAssertTrue(favoritedEmoji.waitForExistence(timeout: 5), "Expected favorited emoji in favorites")

        app.buttons["chat.emojiFavorite.cb_ok"].tap()
        XCTAssertTrue(waitForDisappearance(of: favoritedEmoji, timeout: 5), "Expected emoji to leave favorites")
    }

    @MainActor
    func testKeyboardDoesNotCoverLatestMessage() throws {
        let app = makeUITestApplication()
        app.launch()
        loginAsUITestUser(in: app)
        openSondraConversation(in: app)

        let message = "UI keyboard visibility \(UUID().uuidString)"
        let input = app.textViews["chat.messageInput"]
        input.tap()
        input.typeText(message)
        app.buttons["chat.sendButton"].tap()

        let sentMessage = messageCell(containing: message, in: app)
        XCTAssertTrue(sentMessage.waitForExistence(timeout: 5), "Expected sent message to appear in chat")

        let chatNavigationBar = app.navigationBars["Sondra"]
        XCTAssertTrue(chatNavigationBar.waitForExistence(timeout: 5), "Expected Sondra navigation bar")
        chatNavigationBar.buttons.firstMatch.tap()
        waitForConversationList(in: app)
        openSondraConversation(in: app)

        input.tap()

        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Expected keyboard to appear")
        let reopenedMessage = messageCell(containing: message, in: app)
        XCTAssertTrue(reopenedMessage.waitForExistence(timeout: 5), "Expected latest message to remain visible")
        XCTAssertLessThanOrEqual(
            reopenedMessage.frame.maxY,
            input.frame.minY,
            "Expected latest message to stay above the input bar when the keyboard is visible"
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
    func testGroupChatAnnouncementAndMentionPicker() throws {
        let app = makeUITestApplication()
        app.launch()
        loginAsUITestUser(in: app)
        openGroupCoreConversation(in: app)

        let announcementButton = app.descendants(matching: .any)["chat.groupAnnouncementButton"]
        XCTAssertTrue(
            waitForFiniteFrame(announcementButton, timeout: 5),
            "Expected visible group announcement entry"
        )

        let input = app.textViews["chat.messageInput"]
        input.tap()
        input.typeText("@")
        let sondraMentionOption = app.buttons["chat.mentionOption.sondra"].firstMatch
        tapCenterOfElementWhenFrameIsFinite(
            sondraMentionOption,
            in: app,
            timeout: 15,
            failureMessage: "Expected visible Sondra mention option"
        )
        input.typeText("Sondra UI group mention \(UUID().uuidString)")
        app.buttons["chat.sendButton"].tap()

        XCTAssertTrue(
            messageCell(containing: "Sondra UI group mention", in: app).waitForExistence(timeout: 5),
            "Expected group mention message to appear"
        )
        XCTAssertFalse(app.buttons["chat.mentionOption.sondra"].firstMatch.exists)
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
    func testContactsTabCanOpenChat() throws {
        let app = makeUITestApplication()
        app.launch()
        loginAsUITestUser(in: app)

        app.tabBars.buttons["通讯录"].tap()
        XCTAssertTrue(app.collectionViews["contacts.collection"].waitForExistence(timeout: 5), "Expected contacts collection")
        XCTAssertTrue(app.cells["contacts.cell.contact_sondra"].waitForExistence(timeout: 5), "Expected Sondra contact")
        XCTAssertTrue(app.cells["contacts.cell.group_core_contact"].exists, "Expected seeded group contact")

        app.cells["contacts.cell.contact_sondra"].tap()

        XCTAssertTrue(app.navigationBars["Sondra"].waitForExistence(timeout: 5), "Expected Sondra chat")
        XCTAssertTrue(app.textViews["chat.messageInput"].waitForExistence(timeout: 5), "Expected chat input")
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

    @MainActor
    func testMessageCanBeRevokedAfterConfirmation() throws {
        let app = makeUITestApplication()
        app.launch()
        loginAsUITestUser(in: app)
        openSondraConversation(in: app)

        let message = "UI revoke \(UUID().uuidString)"
        sendTextMessage(message, in: app)

        openMessageAction("Revoke", forMessageContaining: message, in: app)
        let confirmButton = app.buttons["chat.confirmRevokeMessage"].firstMatch
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5), "Expected revoke confirmation")
        confirmButton.tap()

        XCTAssertTrue(
            messageCell(containing: "你撤回了一条消息", in: app).waitForExistence(timeout: 5),
            "Expected revoked replacement text"
        )
    }

    @MainActor
    func testMessageCanBeDeletedAfterConfirmation() throws {
        let app = makeUITestApplication()
        app.launch()
        loginAsUITestUser(in: app)
        openSondraConversation(in: app)

        let message = "UI delete \(UUID().uuidString)"
        sendTextMessage(message, in: app)

        openMessageAction("Delete", forMessageContaining: message, in: app)
        let confirmButton = app.buttons["chat.confirmDeleteMessage"].firstMatch
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5), "Expected delete confirmation")
        confirmButton.tap()

        let deletedMessage = messageCell(containing: message, in: app)
        let deletedMessageHidden = NSPredicate(format: "exists == false")
        expectation(for: deletedMessageHidden, evaluatedWith: deletedMessage)
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testCancellingMessageActionKeepsMessageVisible() throws {
        let app = makeUITestApplication()
        app.launch()
        loginAsUITestUser(in: app)
        openSondraConversation(in: app)

        let message = "UI cancel action \(UUID().uuidString)"
        sendTextMessage(message, in: app)

        openMessageAction("Delete", forMessageContaining: message, in: app)
        let cancelButton = app.buttons["chat.cancelMessageAction"].firstMatch
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5), "Expected message action cancel button")
        cancelButton.tap()

        XCTAssertTrue(
            messageCell(containing: message, in: app).waitForExistence(timeout: 5),
            "Expected cancelled action to keep message visible"
        )
    }

    @MainActor
    func testSimulatedIncomingFromConversationListAppearsAfterOpeningConversation() throws {
        let app = makeUITestApplication()
        app.launch()
        loginAsUITestUser(in: app)

        app.buttons["conversationList.simulateIncomingButton"].tap()
        let simulatedConversation = app.cells
            .matching(NSPredicate(format: "label CONTAINS %@", "#"))
            .firstMatch
        XCTAssertTrue(
            simulatedConversation.waitForExistence(timeout: 15),
            "Expected simulated push to update a conversation cell"
        )
        simulatedConversation.tap()

        XCTAssertTrue(
            messageCell(containing: "#", in: app).waitForExistence(timeout: 15),
            "Expected simulated push message to appear after opening the conversation"
        )
    }
}
