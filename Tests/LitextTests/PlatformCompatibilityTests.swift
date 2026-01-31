//
//  PlatformCompatibilityTests.swift
//  Litext
//
//  Created by Claude on 2025/1/31.
//

@testable import Litext
import XCTest

final class PlatformCompatibilityTests: XCTestCase {
    // MARK: - Platform Type Tests

    func testPlatformTypesExist() {
        // Verify all platform types are properly aliased
        #if canImport(UIKit)
            XCTAssertTrue(LTXPlatformView.self == UIView.self)
            XCTAssertTrue(LTXPlatformBezierPath.self == UIBezierPath.self)
            XCTAssertTrue(PlatformColor.self == UIColor.self)
            XCTAssertTrue(PlatformFont.self == UIFont.self)
        #elseif canImport(AppKit)
            XCTAssertTrue(LTXPlatformView.self == NSView.self)
            XCTAssertTrue(LTXPlatformBezierPath.self == NSBezierPath.self)
            XCTAssertTrue(PlatformColor.self == NSColor.self)
            XCTAssertTrue(PlatformFont.self == NSFont.self)
        #endif
    }

    // MARK: - LTXLabel Initialization Tests

    func testLTXLabelInitialization() {
        let label = LTXLabel(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertNotNil(label)
        XCTAssertEqual(label.frame.size.width, 100)
        XCTAssertEqual(label.frame.size.height, 100)
        XCTAssertFalse(label.isSelectable)
    }

    func testLTXLabelBackgroundColor() {
        let label = LTXLabel(frame: .zero)

        #if canImport(UIKit)
            XCTAssertEqual(label.backgroundColor, .clear)
        #elseif canImport(AppKit)
            XCTAssertTrue(label.wantsLayer)
            XCTAssertNotNil(label.layer)
        #endif
    }

    // MARK: - Text Layout Tests

    func testAttributedTextAssignment() {
        let label = LTXLabel(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let testString = NSAttributedString(string: "Hello, World!")

        label.attributedText = testString

        XCTAssertEqual(label.attributedText.string, "Hello, World!")
        XCTAssertNotNil(label.textLayout)
    }

    func testPreferredMaxLayoutWidth() {
        let label = LTXLabel(frame: .zero)

        label.preferredMaxLayoutWidth = 300
        XCTAssertEqual(label.preferredMaxLayoutWidth, 300)
    }

    func testFrameChangeInvalidatesLayout() {
        let label = LTXLabel(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let testString = NSAttributedString(string: "Test")
        label.attributedText = testString

        label.frame = CGRect(x: 0, y: 0, width: 200, height: 100)

        XCTAssertEqual(label.frame.size.width, 200)
    }

    // MARK: - Selection Tests

    func testSelectionEnabling() {
        let label = LTXLabel(frame: .zero)

        XCTAssertFalse(label.isSelectable)

        label.isSelectable = true
        XCTAssertTrue(label.isSelectable)
    }

    func testSelectionRange() {
        let label = LTXLabel(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let testString = NSAttributedString(string: "Hello, World!")
        label.attributedText = testString
        label.isSelectable = true

        let range = NSRange(location: 0, length: 5)
        label.selectionRange = range

        XCTAssertEqual(label.selectionRange?.location, 0)
        XCTAssertEqual(label.selectionRange?.length, 5)
    }

    func testClearSelectionWhenDisablingSelectable() {
        let label = LTXLabel(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        label.attributedText = NSAttributedString(string: "Test")
        label.isSelectable = true
        label.selectionRange = NSRange(location: 0, length: 4)

        label.isSelectable = false

        XCTAssertNil(label.selectionRange)
    }

    // MARK: - NSValue Extension Tests (AppKit)

    #if canImport(AppKit) && !canImport(UIKit)
        func testNSValueCGRectConversion() {
            let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
            let value = NSValue(cgRect: rect)
            let convertedRect = value.cgRectValue

            XCTAssertEqual(convertedRect, rect)
        }
    #endif

    // MARK: - NSBezierPath Extension Tests (AppKit)

    #if canImport(AppKit) && !canImport(UIKit)
        func testNSBezierPathAppend() {
            let path1 = NSBezierPath(rect: CGRect(x: 0, y: 0, width: 50, height: 50))
            let path2 = NSBezierPath(rect: CGRect(x: 60, y: 60, width: 50, height: 50))

            path1.appendPath(path2)

            XCTAssertGreaterThan(path1.elementCount, 0)
        }

        func testNSBezierPathQuartzPath() {
            let bezierPath = NSBezierPath(rect: CGRect(x: 0, y: 0, width: 100, height: 100))
            let quartzPath = bezierPath.quartzPath

            XCTAssertFalse(quartzPath.isEmpty)
        }

        func testNSBezierPathRoundedRect() {
            let path = NSBezierPath.bezierPath(withRoundedRect: CGRect(x: 0, y: 0, width: 100, height: 100), cornerRadius: 10)

            XCTAssertNotNil(path)
            XCTAssertGreaterThan(path.elementCount, 0)
        }
    #endif

    // MARK: - Localized Text Tests

    func testLocalizedTextStrings() {
        XCTAssertFalse(LocalizedText.copy.isEmpty)
        XCTAssertFalse(LocalizedText.selectAll.isEmpty)
        XCTAssertFalse(LocalizedText.openLink.isEmpty)
        XCTAssertFalse(LocalizedText.copyLink.isEmpty)
    }

    // MARK: - Highlight Region Tests

    func testHighlightRegionCreation() {
        let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: PlatformColor.red]
        let range = NSRange(location: 0, length: 5)
        let region = LTXHighlightRegion(attributes: attributes, stringRange: range)

        XCTAssertEqual(region.stringRange, range)
        XCTAssertEqual(region.rects.count, 0)
    }

    func testHighlightRegionAddRect() {
        let region = LTXHighlightRegion(attributes: [:], stringRange: NSRange(location: 0, length: 5))
        let rect = CGRect(x: 0, y: 0, width: 100, height: 20)

        region.addRect(rect)

        XCTAssertEqual(region.rects.count, 1)
    }

    // MARK: - Platform Specific Tests

    #if canImport(UIKit)
        func testUIKitSpecificFeatures() {
            let label = LTXLabel(frame: CGRect(x: 0, y: 0, width: 200, height: 100))

            // Test first responder capabilities
            XCTAssertFalse(label.canBecomeFocused) // isSelectable is false by default

            label.isSelectable = true
            XCTAssertTrue(label.canBecomeFocused)
        }

        #if !targetEnvironment(macCatalyst)
            func testSelectionHandles() {
                let label = LTXLabel(frame: CGRect(x: 0, y: 0, width: 200, height: 100))

                // Selection handles should exist on iOS
                XCTAssertNotNil(label.selectionHandleStart)
                XCTAssertNotNil(label.selectionHandleEnd)
                XCTAssertTrue(label.selectionHandleStart.isHidden)
                XCTAssertTrue(label.selectionHandleEnd.isHidden)
            }
        #endif
    #endif

    #if canImport(AppKit) && !canImport(UIKit)
        func testAppKitSpecificFeatures() {
            let label = LTXLabel(frame: CGRect(x: 0, y: 0, width: 200, height: 100))

            // Test first responder capabilities
            XCTAssertFalse(label.acceptsFirstResponder) // isSelectable is false by default

            label.isSelectable = true
            XCTAssertTrue(label.acceptsFirstResponder)
        }

        func testFlippedCoordinates() {
            let label = LTXLabel(frame: .zero)

            // AppKit should use flipped coordinates
            XCTAssertTrue(label.isFlipped)
        }
    #endif

    // MARK: - Delegate Tests

    func testDelegateCallbacks() {
        class TestDelegate: LTXLabelDelegate {
            var selectionChanged = false
            var tappedHighlight = false

            func ltxLabelSelectionDidChange(_: LTXLabel, selection _: NSRange?) {
                selectionChanged = true
            }

            func ltxLabelDidTapOnHighlightContent(_: LTXLabel, region _: LTXHighlightRegion, location _: CGPoint) {
                tappedHighlight = true
            }

            func ltxLabelDetectedUserEventMovingAtLocation(_: LTXLabel, location _: CGPoint) {}
        }

        let delegate = TestDelegate()
        let label = LTXLabel(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        label.delegate = delegate
        label.attributedText = NSAttributedString(string: "Test")
        label.isSelectable = true

        label.selectionRange = NSRange(location: 0, length: 4)

        XCTAssertTrue(delegate.selectionChanged)
    }

    // MARK: - Memory Management Tests

    func testLabelDeallocation() {
        weak var weakLabel: LTXLabel?

        autoreleasepool {
            let label = LTXLabel(frame: .zero)
            weakLabel = label
            XCTAssertNotNil(weakLabel)
        }

        // Label should be deallocated
        XCTAssertNil(weakLabel)
    }
}
