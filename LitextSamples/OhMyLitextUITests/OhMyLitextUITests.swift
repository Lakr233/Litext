//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import Foundation
import XCTest

final class OhMyLitextUITests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor
    func testAuditFixturesAreReachableAndCaptured() throws {
        launchApp()

        let fixtureIDs = [
            "fixture.link.multistyle",
            "fixture.attachment.inline",
            "fixture.attachment.linked",
            "fixture.rtl",
            "fixture.line-drawing",
            "fixture.truncation",
            "fixture.empty",
        ]

        for fixtureID in fixtureIDs {
            let element = app.descendants(matching: .any)[fixtureID]
            scrollToElement(element)
            XCTAssertTrue(element.waitForExistence(timeout: 4), "\(fixtureID) should exist")
        }

        try captureScreenshot(named: "audit-fixtures")
    }

    @MainActor
    func testMultiStyleLinkTapUpdatesObservableURL() throws {
        launchApp()

        let linkFixture = app.descendants(matching: .any)["fixture.link.multistyle"]
        scrollToElement(linkFixture)
        XCTAssertTrue(linkFixture.waitForExistence(timeout: 4))

        linkFixture.coordinate(withNormalizedOffset: CGVector(dx: 0.32, dy: 0.5)).tap()

        XCTAssertTrue(waitForState("state.lastTappedURL", containing: "multi-style"))
        dismissAlertIfNeeded()
        try captureScreenshot(named: "multi-style-link")
    }

    @MainActor
    func testLinkedAttachmentTapUpdatesObservableURL() throws {
        launchApp()

        let attachmentView = app.descendants(matching: .any)["fixture.attachment.linked.view"]
        let fallbackFixture = app.descendants(matching: .any)["fixture.attachment.linked"]
        scrollToElement(fallbackFixture)
        XCTAssertTrue(fallbackFixture.waitForExistence(timeout: 4))

        if attachmentView.waitForExistence(timeout: 1), attachmentView.isHittable {
            attachmentView.tap()
        } else {
            fallbackFixture.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.5)).tap()
        }

        XCTAssertTrue(waitForState("state.lastTappedURL", containing: "linked-attachment"))
        dismissAlertIfNeeded()
        try captureScreenshot(named: "linked-attachment")
    }

    @MainActor
    func testDoubleTapSelectionUpdatesObservableSelectedText() throws {
        launchApp()

        let rtlFixture = app.descendants(matching: .any)["fixture.rtl"]
        scrollToElement(rtlFixture)
        XCTAssertTrue(rtlFixture.waitForExistence(timeout: 4))

        rtlFixture.tap()
        app.typeKey("a", modifierFlags: .command)
        if !waitForState("state.selectedText", notEqualTo: "none") {
            rtlFixture.doubleTap()
        }

        XCTAssertTrue(waitForState("state.selectedText", notEqualTo: "none"))
        try captureScreenshot(named: "selection-state")
    }

    @MainActor
    private func launchApp() {
        continueAfterFailure = false
        let application = XCUIApplication()
        application.launchArguments.append("-LitextUITests")
        application.launchEnvironment["LITEXT_UI_TESTS"] = "1"
        application.launch()
        app = application
    }

    @MainActor
    private func scrollToElement(_ element: XCUIElement) {
        let scrollView = app.scrollViews.firstMatch
        for _ in 0 ..< 10 {
            if element.exists, element.isHittable {
                return
            }
            scrollView.swipeUp()
        }
    }

    @MainActor
    private func waitForState(_ identifier: String, containing fragment: String) -> Bool {
        let state = app.staticTexts[identifier]
        let predicate = NSPredicate(format: "label CONTAINS %@", fragment)
        return wait(for: state, predicate: predicate, timeout: 5)
    }

    @MainActor
    private func waitForState(_ identifier: String, notEqualTo value: String) -> Bool {
        let state = app.staticTexts[identifier]
        let predicate = NSPredicate(format: "exists == true AND label != %@", value)
        return wait(for: state, predicate: predicate, timeout: 5)
    }

    @MainActor
    private func wait(
        for element: XCUIElement,
        predicate: NSPredicate,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func dismissAlertIfNeeded() {
        let alert = app.alerts.firstMatch
        guard alert.waitForExistence(timeout: 1) else { return }
        alert.buttons.firstMatch.tap()
    }

    @MainActor
    private func captureScreenshot(named name: String) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        let screenshotName = "\(screenshotPlatformName())-\(name)"
        attachment.name = screenshotName
        attachment.lifetime = .keepAlways
        add(attachment)

        let directoryURL = screenshotDirectoryURL()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try screenshot.pngRepresentation.write(
            to: directoryURL.appendingPathComponent("\(screenshotName).png")
        )
    }

    private func screenshotPlatformName() -> String {
        if let platform = ProcessInfo.processInfo.environment["LITEXT_SCREENSHOT_PLATFORM"],
           !platform.isEmpty
        {
            return platform
        }

        #if os(macOS)
            return "macos"
        #else
            return "ios"
        #endif
    }

    private func screenshotDirectoryURL() -> URL {
        if let directory = ProcessInfo.processInfo.environment["LITEXT_SCREENSHOT_DIR"],
           !directory.isEmpty
        {
            return URL(fileURLWithPath: directory, isDirectory: true)
        }

        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Artworks/RenderingAudit", isDirectory: true)
    }
}
