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
    func accountActionsAreVisible(timeout: TimeInterval) -> Bool {
        app.alerts["Account"].waitForExistence(timeout: timeout)
            || app.sheets["Account"].waitForExistence(timeout: timeout)
    }

    let candidates = [
        app.buttons["conversationList.accountButton"].firstMatch,
        app.navigationBars["Messages"].buttons["Account"].firstMatch,
        app.navigationBars["ChatBridge"].buttons["Account"].firstMatch,
        app.buttons["Account"].firstMatch
    ]

    XCTAssertTrue(
        candidates.contains { $0.waitForExistence(timeout: 2) },
        "Expected account button",
        file: file,
        line: line
    )

    for accountButton in candidates where accountButton.exists {
        if accountButton.isHittable {
            accountButton.tap()
        } else {
            accountButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        if accountActionsAreVisible(timeout: 2) {
            return
        }
    }

    app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.08)).tap()
    XCTAssertTrue(accountActionsAreVisible(timeout: 5), "Expected account actions alert", file: file, line: line)
}

@MainActor
func tapAccountAction(
    identifier: String,
    fallbackTitle: String,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
) {
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
        identifier: "accountAction.logOut",
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
        identifier: "accountAction.deleteLocalData",
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
        identifier: "accountAction.switchAccount",
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
    waitForConversationList(in: app, file: file, line: line)

    let messageInput = app.textViews["chat.messageInput"]
    if messageInput.waitForExistence(timeout: 1) {
        return
    }

    let candidates = [
        app.cells["conversationList.cell.single_sondra"].firstMatch,
        app.staticTexts["Sondra"].firstMatch
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
func openGroupCoreConversation(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    waitForConversationList(in: app, file: file, line: line)

    let messageInput = app.textViews["chat.messageInput"]
    if messageInput.waitForExistence(timeout: 1) {
        return
    }

    let candidates = [
        app.cells["conversationList.cell.group_core"].firstMatch,
        app.staticTexts["ChatBridge Core"].firstMatch
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

    XCTFail("Expected group chat message input", file: file, line: line)
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
    XCTAssertTrue(cell.waitForExistence(timeout: 5), "Expected conversation cell \(id)", file: file, line: line)

    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: cell)
    let result = XCTWaiter.wait(for: [expectation], timeout: 5)
    XCTAssertEqual(result, .completed, "Expected conversation cell \(id) label to contain \(text)", file: file, line: line)
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
    XCTAssertTrue(cell.waitForExistence(timeout: 5), "Expected conversation cell \(title)", file: file, line: line)

    let predicate = NSPredicate(format: "NOT label CONTAINS %@", text)
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: cell)
    let result = XCTWaiter.wait(for: [expectation], timeout: 5)
    XCTAssertEqual(result, .completed, "Expected conversation cell \(title) label not to contain \(text)", file: file, line: line)
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
    XCTAssertTrue(cell.waitForExistence(timeout: 5), "Expected conversation cell \(id)", file: file, line: line)

    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: cell)
    let result = XCTWaiter.wait(for: [expectation], timeout: 5)
    XCTAssertEqual(result, .completed, "Expected conversation cell \(id) label not to contain \(text)", file: file, line: line)
}

@MainActor
private func sondraConversationElement(in app: XCUIApplication) -> XCUIElement {
    let identifiedCell = app.cells["conversationList.cell.single_sondra"]
    if identifiedCell.exists {
        return identifiedCell
    }

    return app.staticTexts["Sondra"]
}
