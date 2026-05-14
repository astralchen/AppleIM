//
//  UITestAppLauncher.swift
//  AppleIMUITests
//

import Foundation
import CoreGraphics
import XCTest

enum UITestSendMode: String {
    case success
    case failFirst
}

@MainActor
func makeUITestApplication(
    sendMode: UITestSendMode = .success,
    runID: String = UUID().uuidString,
    resetSession: Bool = true
) -> XCUIApplication {
    let app = XCUIApplication()
    app.terminate()
    app.launchArguments.append("--chatbridge-ui-testing")
    app.launchEnvironment["CHATBRIDGE_UI_TEST_RUN_ID"] = runID
    app.launchEnvironment["CHATBRIDGE_UI_TEST_SEND_MODE"] = sendMode.rawValue
    app.launchEnvironment["CHATBRIDGE_UI_TEST_RESET_SESSION"] = resetSession ? "1" : "0"
    return app
}

@MainActor
func waitForLogin(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let accountField = app.textFields["login.accountTextField"]
    XCTAssertTrue(accountField.waitForExistence(timeout: 5), "Expected login account field", file: file, line: line)
    XCTAssertTrue(app.secureTextFields["login.passwordTextField"].exists, "Expected login password field", file: file, line: line)
}

@MainActor
func loginAsUITestUser(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    login(
        account: "ui_test_user",
        password: "password123",
        in: app,
        file: file,
        line: line
    )
}

@MainActor
func login(
    account: String,
    password: String,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    waitForLogin(in: app, file: file, line: line)
    let accountField = app.textFields["login.accountTextField"]
    accountField.tap()
    accountField.typeText(account)

    let passwordField = app.secureTextFields["login.passwordTextField"]
    passwordField.tap()
    passwordField.typeText(password)

    app.buttons["login.submitButton"].tap()
    waitForConversationList(in: app, file: file, line: line)
}

@MainActor
func openAccountActions(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let candidates = [
        app.tabBars.buttons["Account"].firstMatch,
        app.buttons["mainTab.account"].firstMatch,
        app.buttons["Account"].firstMatch
    ]

    XCTAssertTrue(
        candidates.contains { $0.waitForExistence(timeout: 2) },
        "Expected account tab",
        file: file,
        line: line
    )

    for accountTab in candidates where accountTab.exists {
        if accountTab.isHittable {
            accountTab.tap()
        } else {
            accountTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        if app.tables["account.tableView"].waitForExistence(timeout: 2) {
            return
        }
    }

    XCTAssertTrue(app.tables["account.tableView"].waitForExistence(timeout: 5), "Expected account screen", file: file, line: line)
}

@MainActor
func tapAccountAction(
    identifier: String,
    fallbackTitle: String,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let identifiedCell = app.cells[identifier].firstMatch
    if identifiedCell.waitForExistence(timeout: 2) {
        identifiedCell.tap()
        return
    }

    let identifiedButton = app.buttons[identifier].firstMatch
    if identifiedButton.waitForExistence(timeout: 2) {
        identifiedButton.tap()
        return
    }

    let titledButton = app.buttons[fallbackTitle].firstMatch
    XCTAssertTrue(titledButton.waitForExistence(timeout: 5), "Expected account action \(fallbackTitle)", file: file, line: line)
    titledButton.tap()
}

@MainActor
func logOut(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    openAccountActions(in: app, file: file, line: line)
    tapAccountAction(
        identifier: "account.action.logOut",
        fallbackTitle: "Log Out",
        in: app,
        file: file,
        line: line
    )
    waitForLogin(in: app, file: file, line: line)
}

@MainActor
func deleteLocalData(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    openAccountActions(in: app, file: file, line: line)
    tapAccountAction(
        identifier: "account.action.deleteLocalData",
        fallbackTitle: "Delete Local Data",
        in: app,
        file: file,
        line: line
    )

    let confirmButton = app.buttons["accountAction.confirmDeleteLocalData"].firstMatch
    if confirmButton.waitForExistence(timeout: 2) {
        confirmButton.tap()
    } else {
        let titledButton = app.buttons["Delete Local Data"].firstMatch
        XCTAssertTrue(titledButton.waitForExistence(timeout: 5), "Expected delete confirmation", file: file, line: line)
        titledButton.tap()
    }

    waitForLogin(in: app, file: file, line: line)
}

@MainActor
func switchAccount(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    openAccountActions(in: app, file: file, line: line)
    tapAccountAction(
        identifier: "account.action.switchAccount",
        fallbackTitle: "Switch Account",
        in: app,
        file: file,
        line: line
    )
    waitForLogin(in: app, file: file, line: line)
}

@MainActor
func waitForConversationList(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let identifiedCell = app.cells["conversationList.cell.single_sondra"]
    if identifiedCell.waitForExistence(timeout: 20) {
        return
    }

    let title = app.staticTexts["Sondra"]
    XCTAssertTrue(title.waitForExistence(timeout: 5), "Expected seeded Sondra conversation", file: file, line: line)
}

@MainActor
func openSondraConversation(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    openConversation(cellID: "single_sondra", title: "Sondra", in: app, file: file, line: line)
}

@MainActor
func openGroupCoreConversation(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    openConversation(cellID: "group_core", title: "ChatBridge Core", in: app, file: file, line: line)
}

@MainActor
func openConversation(
    cellID: String,
    title: String,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    waitForConversationList(in: app, file: file, line: line)

    let messageInput = app.textViews["chat.messageInput"]
    if messageInput.waitForExistence(timeout: 1) {
        return
    }

    let candidates = [
        app.cells["conversationList.cell.\(cellID)"].firstMatch,
        app.staticTexts[title].firstMatch
    ]
    for _ in 0..<3 {
        for conversation in candidates where conversation.exists {
            if conversation.isHittable {
                conversation.tap()
            } else {
                conversation.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }

            if messageInput.waitForExistence(timeout: 3) {
                return
            }
        }
    }

    XCTFail("Expected chat message input", file: file, line: line)
}

@MainActor
func messageCell(containing text: String, in app: XCUIApplication) -> XCUIElement {
    app.staticTexts
        .matching(NSPredicate(format: "label CONTAINS %@", text))
        .firstMatch
}

@MainActor
func sendTextMessage(
    _ message: String,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let input = app.textViews["chat.messageInput"]
    XCTAssertTrue(input.waitForExistence(timeout: 5), "Expected chat input", file: file, line: line)
    input.tap()
    input.typeText(message)
    XCTAssertTrue(app.buttons["chat.sendButton"].waitForExistence(timeout: 5), "Expected send button", file: file, line: line)
    app.buttons["chat.sendButton"].tap()
    XCTAssertTrue(
        messageCell(containing: message, in: app).waitForExistence(timeout: 5),
        "Expected sent message",
        file: file,
        line: line
    )
}

@MainActor
func openEmojiPanel(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let moreButton = app.buttons["chat.moreButton"]
    XCTAssertTrue(moreButton.waitForExistence(timeout: 5), "Expected chat more button", file: file, line: line)
    moreButton.tap()

    let emojiAction = app.buttons["表情"].firstMatch
    XCTAssertTrue(emojiAction.waitForExistence(timeout: 5), "Expected emoji menu action", file: file, line: line)
    emojiAction.tap()

    XCTAssertTrue(
        app.otherElements["chat.emojiInputPanel"].waitForExistence(timeout: 5),
        "Expected emoji input panel",
        file: file,
        line: line
    )
}

@MainActor
func selectEmojiPanelSection(
    _ title: String,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let section = app.buttons[title].firstMatch
    XCTAssertTrue(section.waitForExistence(timeout: 5), "Expected emoji section \(title)", file: file, line: line)
    section.tap()
}

@MainActor
func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
    let predicate = NSPredicate(format: "exists == false")
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
}

@MainActor
func openMessageAction(
    _ actionTitle: String,
    forMessageContaining text: String,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let message = messageCell(containing: text, in: app)
    XCTAssertTrue(message.waitForExistence(timeout: 5), "Expected message \(text)", file: file, line: line)
    message.press(forDuration: 1.0)

    let action = app.buttons[actionTitle].firstMatch
    XCTAssertTrue(action.waitForExistence(timeout: 5), "Expected message action \(actionTitle)", file: file, line: line)
    action.tap()
}

@MainActor
func conversationCell(containing text: String, in app: XCUIApplication) -> XCUIElement {
    app.cells
        .matching(NSPredicate(format: "label CONTAINS %@", text))
        .firstMatch
}

@MainActor
func revealTrailingActions(on cell: XCUIElement) {
    let start = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
    let end = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
    start.press(forDuration: 0.1, thenDragTo: end)
}

@MainActor
func conversationCell(id: String, in app: XCUIApplication) -> XCUIElement {
    app.cells["conversationList.cell.\(id)"]
}

@MainActor
func waitForConversationCell(
    id: String,
    labelContaining text: String,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let predicate = NSPredicate(format: "label CONTAINS %@", text)
    let cell = conversationCell(id: id, in: app)
    assertConversationCell(cell, matches: predicate, description: "\(id) label to contain \(text)", file: file, line: line)
}

@MainActor
func waitForConversationCell(
    title: String,
    labelContaining text: String,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let predicate = NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", title, text)
    let cell = app.cells.matching(predicate).firstMatch
    XCTAssertTrue(cell.waitForExistence(timeout: 5), "Expected conversation cell \(title) label to contain \(text)", file: file, line: line)
}

@MainActor
func waitForConversationCell(
    title: String,
    labelNotContaining text: String,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let cell = conversationCell(containing: title, in: app)
    let predicate = NSPredicate(format: "NOT label CONTAINS %@", text)
    assertConversationCell(cell, matches: predicate, description: "\(title) label not to contain \(text)", file: file, line: line)
}

@MainActor
func waitForConversationCell(
    id: String,
    labelNotContaining text: String,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let predicate = NSPredicate(format: "NOT label CONTAINS %@", text)
    let cell = conversationCell(id: id, in: app)
    assertConversationCell(cell, matches: predicate, description: "\(id) label not to contain \(text)", file: file, line: line)
}

@MainActor
private func assertConversationCell(
    _ cell: XCUIElement,
    matches predicate: NSPredicate,
    description: String,
    file: StaticString,
    line: UInt
) {
    XCTAssertTrue(cell.waitForExistence(timeout: 5), "Expected conversation cell \(description)", file: file, line: line)
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: cell)
    let result = XCTWaiter.wait(for: [expectation], timeout: 5)
    XCTAssertEqual(result, .completed, "Expected conversation cell \(description)", file: file, line: line)
}

@MainActor
private func sondraConversationElement(in app: XCUIApplication) -> XCUIElement {
    let identifiedCell = app.cells["conversationList.cell.single_sondra"]
    if identifiedCell.exists {
        return identifiedCell
    }

    return app.staticTexts["Sondra"]
}
