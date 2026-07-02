//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
@testable import Litext
import QuartzCore
import XCTest

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
    import AppKit
#endif

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
    func testClearSelectionRemovesStaleSelectionLayerEvenWhenRangeIsNil() {
        let label = LTXLabel(attributedText: NSAttributedString(string: "Hello"))
        label.selectionLayer = CAShapeLayer()

        label.clearSelection()

        XCTAssertNil(label.selectionLayer)
    }

    @MainActor
    func testHighlightRegionForTapPrioritizesLinkedAttachments() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/attachment"))
        let text = NSMutableAttributedString(string: "Start ")
        text.append(NSAttributedString(
            string: "link",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
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
                .font: PlatformFont.systemFont(ofSize: 16),
                .ltxAttachment: attachment,
                .link: url,
                kCTRunDelegateAttributeName as NSAttributedString.Key: attachment.runDelegate,
            ],
            range: attachmentRange
        )
        text.append(attachmentString)

        let label = LTXLabel(attributedText: text)
        label.frame = CGRect(x: 0, y: 0, width: 180, height: 40)
        let layout = LTXTextLayout(attributedString: text)
        layout.containerSize = label.bounds.size
        layout.updateHighlightRegions()
        label.textLayout = layout

        let attachmentRegion = try XCTUnwrap(label.highlightRegions.first { $0.kind == .attachment })
        let rect = try XCTUnwrap(attachmentRegion.cgRects.first)
        let tapRect = label.convertRectFromTextLayout(rect, insetForInteraction: true)
        let tapPoint = CGPoint(x: tapRect.midX, y: tapRect.midY)

        XCTAssertEqual(label.highlightRegionAtPoint(tapPoint)?.kind, .link)
        let tappedRegion = try XCTUnwrap(label.highlightRegionForTap(at: tapPoint))
        XCTAssertEqual(ObjectIdentifier(tappedRegion), ObjectIdentifier(attachmentRegion))
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
    func testAttachmentRunDelegateUsesRetainedMetricsAfterOriginalAttachmentDrops() throws {
        var attachment: LTXAttachment? = LTXAttachment()
        attachment?.size = CGSize(width: 24, height: 16)
        let cachedDelegate = try XCTUnwrap(attachment?.runDelegate) as AnyObject
        let repeatedDelegate = try XCTUnwrap(attachment?.runDelegate) as AnyObject
        XCTAssertEqual(ObjectIdentifier(cachedDelegate), ObjectIdentifier(repeatedDelegate))

        var string: NSMutableAttributedString? = NSMutableAttributedString(string: LTXReplacementText)
        var delegate: CTRunDelegate? = try XCTUnwrap(attachment?.runDelegate)
        let range = NSRange(location: 0, length: string?.length ?? 0)
        try string?.addAttribute(
            kCTRunDelegateAttributeName as NSAttributedString.Key,
            value: XCTUnwrap(delegate),
            range: range
        )

        attachment = nil
        var line: CTLine? = try CTLineCreateWithAttributedString(XCTUnwrap(string))
        let width = try CTLineGetTypographicBounds(XCTUnwrap(line), nil, nil, nil)
        XCTAssertEqual(width, 24)

        line = nil
        string = nil
        delegate = nil
    }

    @MainActor
    func testDrawingInvokesLineDrawingActionForEveryLine() throws {
        let width: CGFloat = 260
        let lineCount = 12
        let attributedText = Self.lineDrawingProbeText(lineCount: lineCount)
        let layout = LTXTextLayout(attributedString: attributedText)
        let suggestedSize = layout.suggestContainerSize(
            withSize: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        layout.containerSize = CGSize(width: width, height: suggestedSize.height)

        Self.lineDrawingProbeInvocationCount = 0
        let context = try XCTUnwrap(Self.makeBitmapContext(size: layout.containerSize))
        layout.draw(in: context)

        XCTAssertGreaterThanOrEqual(Self.lineDrawingProbeInvocationCount, lineCount)
    }

    @MainActor
    func testFullTextDrawingPerformance() throws {
        let width: CGFloat = 320
        let attributedText = Self.lineDrawingProbeText(lineCount: 500)
        let layout = LTXTextLayout(attributedString: attributedText)
        let suggestedSize = layout.suggestContainerSize(
            withSize: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        layout.containerSize = CGSize(width: width, height: suggestedSize.height)
        let fullContext = try XCTUnwrap(Self.makeBitmapContext(size: layout.containerSize))

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            layout.draw(in: fullContext)
        }
    }

    @MainActor
    private static var lineDrawingProbeInvocationCount = 0

    @MainActor
    private static func lineDrawingProbeText(lineCount: Int) -> NSAttributedString {
        let action = LTXLineDrawingAction { _, _, _ in
            lineDrawingProbeInvocationCount += 1
        }
        let text = NSMutableAttributedString()
        for index in 0 ..< lineCount {
            text.append(NSAttributedString(
                string: "Probe line \(index) keeps layout stable while drawing is clipped.\n",
                attributes: [
                    .font: PlatformFont.systemFont(ofSize: 16),
                    .ltxLineDrawingCallback: action,
                ]
            ))
        }
        return text
    }

    private static func makeBitmapContext(size: CGSize) -> CGContext? {
        let width = max(1, Int(size.width.rounded(.up)))
        let height = max(1, Int(size.height.rounded(.up)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}
