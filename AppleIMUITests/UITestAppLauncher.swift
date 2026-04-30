//
//  UITestAppLauncher.swift
//  AppleIMUITests
//

import Foundation
import XCTest

enum UITestSendMode: String {
    case success
    case failFirst
}

@MainActor
func makeUITestApplication(sendMode: UITestSendMode = .success) -> XCUIApplication {
    let app = XCUIApplication()
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
private func sondraConversationElement(in app: XCUIApplication) -> XCUIElement {
    let identifiedCell = app.cells["conversationList.cell.single_sondra"]
    if identifiedCell.exists {
        return identifiedCell
    }

    return app.staticTexts["Sondra"]
}
