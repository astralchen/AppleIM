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
func makeUITestApplication(sendMode: UITestSendMode = .success) -> XCUIApplication {
    let app = XCUIApplication()
    app.terminate()
    app.launchArguments.append("--chatbridge-ui-testing")
    app.launchEnvironment["CHATBRIDGE_UI_TEST_RUN_ID"] = UUID().uuidString
    app.launchEnvironment["CHATBRIDGE_UI_TEST_SEND_MODE"] = sendMode.rawValue
    return app
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
