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
    let navigationAccountButton = app.navigationBars["ChatBridge"].buttons["Account"].firstMatch
    let accountButton = navigationAccountButton.waitForExistence(timeout: 3)
        ? navigationAccountButton
        : app.buttons["conversationList.accountButton"].firstMatch

    XCTAssertTrue(accountButton.waitForExistence(timeout: 5), "Expected account button", file: file, line: line)
    accountButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    if app.alerts["Account"].waitForExistence(timeout: 2) {
        return
    }

    app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.08)).tap()
    XCTAssertTrue(app.alerts["Account"].waitForExistence(timeout: 5), "Expected account actions alert", file: file, line: line)
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
    sondraConversationElement(in: app).tap()

    let messageInput = app.textFields["chat.messageInput"]
    XCTAssertTrue(messageInput.waitForExistence(timeout: 5), "Expected chat message input", file: file, line: line)
}

@MainActor
func messageCell(containing text: String, in app: XCUIApplication) -> XCUIElement {
    app.staticTexts[text]
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
