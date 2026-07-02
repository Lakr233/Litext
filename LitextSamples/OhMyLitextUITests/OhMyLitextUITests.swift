//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import Foundation
import XCTest

/// E2E tests for the single-document demo.
///
/// The demo renders every rendering kind (styled runs, multi-style links,
/// inline/linked attachments, RTL, custom line drawing, long selectable text)
/// inside one TextLabelView with the accessibility identifier `demo.document`.
final class OhMyLitextUITests: XCTestCase {
    private var app: XCUIApplication!

    /// Offset (in points, from the document's top-left corner) of the
    /// repository link line — the second line of the document, kept at a
    /// deterministic position for tap tests at the default theme.
    private let repoLinkOffset = CGVector(dx: 80, dy: 70)

    @MainActor
    func testDocumentRendersAndIsCaptured() throws {
        launchApp()

        let document = documentElement()
        XCTAssertTrue(document.waitForExistence(timeout: 4), "demo.document should exist")
        try captureScreenshot(named: "document-top")

        let scrollView = app.scrollViews.firstMatch
        for _ in 0 ..< 6 {
            scrollView.swipeUp()
        }
        try captureScreenshot(named: "document-bottom")
    }

    @MainActor
    func testAttachmentViewsExistInsideDocument() throws {
        launchApp()

        let inline = app.descendants(matching: .any)["demo.attachment.inline.view"]
        let linked = app.descendants(matching: .any)["demo.attachment.linked.view"]

        scrollToElement(inline)
        XCTAssertTrue(inline.waitForExistence(timeout: 4), "inline attachment view should exist")
        XCTAssertTrue(linked.waitForExistence(timeout: 4), "linked attachment view should exist")
        try captureScreenshot(named: "attachments")
    }

    @MainActor
    func testRepoLinkTapUpdatesObservableURL() throws {
        launchApp()

        let document = documentElement()
        XCTAssertTrue(document.waitForExistence(timeout: 4))

        document.coordinate(withNormalizedOffset: .zero)
            .withOffset(repoLinkOffset)
            .tap()

        XCTAssertTrue(waitForState("state.lastTappedURL", containing: "Lakr233/Litext"))
        dismissAlertIfNeeded()
        try captureScreenshot(named: "link-tap")
    }

    @MainActor
    func testLinkedAttachmentTapUpdatesObservableURL() throws {
        launchApp()

        let attachmentView = app.descendants(matching: .any)["demo.attachment.linked.view"]
        scrollToElement(attachmentView)
        XCTAssertTrue(attachmentView.waitForExistence(timeout: 4))
        attachmentView.tap()

        XCTAssertTrue(waitForState("state.lastTappedURL", containing: "linked-attachment"))
        dismissAlertIfNeeded()
        try captureScreenshot(named: "linked-attachment")
    }

    @MainActor
    func testDoubleTapSelectionUpdatesObservableSelectedText() throws {
        launchApp()

        let document = documentElement()
        XCTAssertTrue(document.waitForExistence(timeout: 4))

        document.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).doubleTap()

        XCTAssertTrue(waitForState("state.selectedText", notEqualTo: "none"))
        try captureScreenshot(named: "selection-state")
    }

    @MainActor
    func testDeepScrollKeepsDocumentInteractive() {
        launchApp()

        let document = documentElement()
        XCTAssertTrue(document.waitForExistence(timeout: 4))

        let scrollView = app.scrollViews.firstMatch
        for _ in 0 ..< 6 {
            scrollView.swipeUp()
        }
        for _ in 0 ..< 8 {
            scrollView.swipeDown()
        }

        document.coordinate(withNormalizedOffset: .zero)
            .withOffset(repoLinkOffset)
            .tap()

        XCTAssertTrue(waitForState("state.lastTappedURL", containing: "Lakr233/Litext"))
        dismissAlertIfNeeded()
    }

    // MARK: - Helpers

    @MainActor
    private func documentElement() -> XCUIElement {
        app.descendants(matching: .any)["demo.document"]
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
