//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
@testable import Litext
import XCTest

final class LitextSampleUnitTests: XCTestCase {
    @MainActor
    func testInvalidRangesAndSelectionRangeAreSanitized() {
        let layout = LTXTextLayout(attributedString: NSAttributedString(string: "Hello Litext"))
        layout.containerSize = CGSize(width: 200, height: 60)

        XCTAssertTrue(layout.rects(for: NSRange(location: NSNotFound, length: 1)).isEmpty)
        XCTAssertTrue(layout.rects(for: NSRange(location: -1, length: 1)).isEmpty)
        XCTAssertTrue(layout.rects(for: NSRange(location: 0, length: 0)).isEmpty)
        XCTAssertTrue(layout.rects(for: NSRange(location: 500, length: 5)).isEmpty)

        #if !os(watchOS)
            let label = LTXLabel(attributedText: NSAttributedString(string: "Hello"))

            label.selectionRange = NSRange(location: 1, length: 100)
            XCTAssertEqual(label.selectionRange, NSRange(location: 1, length: 4))

            label.selectionRange = NSRange(location: NSNotFound, length: 1)
            XCTAssertNil(label.selectionRange)

            label.selectionRange = NSRange(location: 0, length: 0)
            XCTAssertNil(label.selectionRange)
        #endif
    }

    @MainActor
    func testNativeHitTestingReturnsIndicesForBidiOverflowPoints() throws {
        let text = NSAttributedString(
            string: "LTR שלום عربى 123",
            attributes: [.font: PlatformFont.systemFont(ofSize: 18)]
        )
        let layout = LTXTextLayout(attributedString: text)
        layout.containerSize = CGSize(width: 320, height: 80)

        let textRect = try XCTUnwrap(layout.rects(for: NSRange(location: 0, length: text.length)).first)
        let leftIndex = layout.textIndex(at: CGPoint(x: textRect.minX - 48, y: textRect.midY))
        let rightIndex = layout.textIndex(at: CGPoint(x: textRect.maxX + 48, y: textRect.midY))

        XCTAssertNotNil(leftIndex)
        XCTAssertNotNil(rightIndex)
        XCTAssertNotEqual(leftIndex, rightIndex)
    }

    @MainActor
    func testNearestHitTestingUsesNearestLineWithoutHorizontalClamp() throws {
        let text = NSAttributedString(
            string: "First line\nSecond line",
            attributes: [.font: PlatformFont.systemFont(ofSize: 18)]
        )
        let secondLineStart = (text.string as NSString).range(of: "Second").location
        let layout = LTXTextLayout(attributedString: text)
        layout.containerSize = CGSize(width: 220, height: 120)

        let secondLineRect = try XCTUnwrap(layout.rects(
            for: NSRange(location: secondLineStart, length: 6)
        ).first)
        let nearestIndex = try XCTUnwrap(layout.nearestTextIndex(
            at: CGPoint(x: secondLineRect.minX - 400, y: secondLineRect.midY)
        ))

        XCTAssertGreaterThanOrEqual(nearestIndex, secondLineStart)
    }

    @MainActor
    func testHighlightRegionsSeparateMultiStyleLinksAndLinkedAttachments() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/linked"))
        let text = NSMutableAttributedString(string: "Start ")
        text.append(NSAttributedString(
            string: "multi ",
            attributes: [
                .font: PlatformFont.boldSystemFont(ofSize: 16),
                .foregroundColor: PlatformColor.systemBlue,
                .link: url,
            ]
        ))
        text.append(NSAttributedString(
            string: "style",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .foregroundColor: PlatformColor.systemPurple,
                .link: url,
            ]
        ))
        text.append(NSAttributedString(string: " "))

        let attachment = LTXAttachment()
        attachment.size = CGSize(width: 30, height: 20)
        let attachmentString = NSMutableAttributedString(string: LTXReplacementText)
        let attachmentRange = NSRange(location: 0, length: attachmentString.length)
        attachmentString.addAttributes(
            [
                .ltxAttachment: attachment,
                .link: url,
                kCTRunDelegateAttributeName as NSAttributedString.Key: attachment.runDelegate,
            ],
            range: attachmentRange
        )
        text.append(attachmentString)

        let layout = LTXTextLayout(attributedString: text)
        layout.containerSize = CGSize(width: 240, height: 80)
        layout.updateHighlightRegions()

        let linkRegions = layout.highlightRegions.filter { $0.kind == .link }
        let attachmentRegions = layout.highlightRegions.filter { $0.kind == .attachment }

        XCTAssertEqual(linkRegions.count, 2)
        XCTAssertEqual(attachmentRegions.count, 1)
        XCTAssertTrue(linkRegions.contains { $0.stringRange == NSRange(location: 6, length: 11) })
        XCTAssertEqual(attachmentRegions.first?.stringRange.location, 18)
        XCTAssertFalse(attachmentRegions.first?.cgRects.isEmpty ?? true)
    }

    @MainActor
    func testAttachmentRunDelegateDoesNotRetainAfterAttributedStringDrops() {
        weak var weakAttachment: LTXAttachment?

        do {
            let attachment = LTXAttachment()
            attachment.size = CGSize(width: 24, height: 16)
            weakAttachment = attachment

            let string = NSMutableAttributedString(string: LTXReplacementText)
            string.addAttribute(
                kCTRunDelegateAttributeName as NSAttributedString.Key,
                value: attachment.runDelegate,
                range: NSRange(location: 0, length: string.length)
            )
            _ = string
        }

        XCTAssertNil(weakAttachment)
    }
}
