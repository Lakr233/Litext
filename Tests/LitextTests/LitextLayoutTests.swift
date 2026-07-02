//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
@testable import Litext
import QuartzCore
import Testing

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
    import AppKit
#endif

@MainActor
@Test func invalidRangesDoNotProduceRects() {
    let layout = TextLabel.Layout(attributedString: NSAttributedString(string: "Hello Litext"))
    layout.containerSize = CGSize(width: 200, height: 60)

    #expect(layout.rects(for: NSRange(location: NSNotFound, length: 1)).isEmpty)
    #expect(layout.rects(for: NSRange(location: -1, length: 1)).isEmpty)
    #expect(layout.rects(for: NSRange(location: 0, length: 0)).isEmpty)
    #expect(layout.rects(for: NSRange(location: 500, length: 5)).isEmpty)
}

#if !os(watchOS)
    @MainActor
    @Test func publicSelectionRangeIsSanitized() {
        let label = TextLabelView(attributedText: NSAttributedString(string: "Hello"))

        label.selectionRange = NSRange(location: 1, length: 100)
        #expect(label.selectionRange == NSRange(location: 1, length: 4))

        label.selectionRange = NSRange(location: NSNotFound, length: 1)
        #expect(label.selectionRange == nil)

        label.selectionRange = NSRange(location: 0, length: 0)
        #expect(label.selectionRange == nil)
    }

    @MainActor
    @Test func clearSelectionRemovesStaleSelectionLayerEvenWhenRangeIsNil() {
        let label = TextLabelView(attributedText: NSAttributedString(string: "Hello"))
        label.selectionLayer = CAShapeLayer()

        label.clearSelection()

        #expect(label.selectionLayer == nil)
    }

    @MainActor
    @Test func highlightRegionForTapPrioritizesLinkedAttachments() throws {
        let url = try #require(URL(string: "https://example.com/attachment"))
        let text = NSMutableAttributedString(string: "Start ")
        text.append(NSAttributedString(
            string: "link",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .link: url,
            ]
        ))
        text.append(NSAttributedString(string: " "))

        let attachment = TextLabel.Attachment()
        attachment.size = CGSize(width: 30, height: 20)
        text.append(attachment.attributedString(attributes: [
            .font: PlatformFont.systemFont(ofSize: 16),
            .link: url,
        ]))

        let label = TextLabelView(attributedText: text)
        label.frame = CGRect(x: 0, y: 0, width: 180, height: 40)
        let layout = TextLabel.Layout(attributedString: text)
        layout.containerSize = label.bounds.size
        layout.updateHighlightRegions()
        label.textLayout = layout

        let attachmentRegion = try #require(label.highlightRegions.first { $0.kind == .attachment })
        let rect = try #require(attachmentRegion.rects.first)
        let tapRect = label.convertRectFromTextLayout(rect, insetForInteraction: true)
        let tapPoint = CGPoint(x: tapRect.midX, y: tapRect.midY)

        #expect(label.highlightRegionAtPoint(tapPoint)?.kind == .link)
        let tappedRegion = try #require(label.highlightRegionForTap(at: tapPoint))
        #expect(ObjectIdentifier(tappedRegion) == ObjectIdentifier(attachmentRegion))
    }
#endif

@MainActor
@Test func highlightRegionsSeparateMultiStyleLinksAndLinkedAttachments() throws {
    let url = try #require(URL(string: "https://example.com/linked"))
    let text = NSMutableAttributedString(string: "Start ")
    text.append(NSAttributedString(
        string: "multi ",
        attributes: [
            .link: url,
            .foregroundColor: PlatformColor.systemBlue,
        ]
    ))
    text.append(NSAttributedString(
        string: "style",
        attributes: [
            .link: url,
            .foregroundColor: PlatformColor.systemPurple,
        ]
    ))
    text.append(NSAttributedString(string: " "))

    let attachment = TextLabel.Attachment()
    attachment.size = CGSize(width: 30, height: 20)
    text.append(attachment.attributedString(attributes: [
        .link: url,
    ]))

    let layout = TextLabel.Layout(attributedString: text)
    layout.containerSize = CGSize(width: 240, height: 80)
    layout.updateHighlightRegions()

    let linkRegions = layout.highlightRegions.filter { $0.kind == .link }
    let attachmentRegions = layout.highlightRegions.filter { $0.kind == .attachment }

    #expect(linkRegions.count == 2)
    #expect(attachmentRegions.count == 1)
    #expect(linkRegions.contains { $0.stringRange == NSRange(location: 6, length: 11) })
    #expect(attachmentRegions.first?.rects.isEmpty == false)
}

@MainActor
@Test func attachmentRunDelegateUsesRetainedMetricsAfterOriginalAttachmentDrops() throws {
    var attachment: TextLabel.Attachment? = TextLabel.Attachment()
    attachment?.size = CGSize(width: 24, height: 16)
    let cachedDelegate = try #require(attachment?.runDelegate) as AnyObject
    let repeatedDelegate = try #require(attachment?.runDelegate) as AnyObject
    #expect(ObjectIdentifier(cachedDelegate) == ObjectIdentifier(repeatedDelegate))

    var string: NSMutableAttributedString? = NSMutableAttributedString(string: TextLabel.Attachment.replacementText)
    var delegate: CTRunDelegate? = try #require(attachment?.runDelegate)
    let range = NSRange(location: 0, length: string?.length ?? 0)
    try string?.addAttribute(
        kCTRunDelegateAttributeName as NSAttributedString.Key,
        value: #require(delegate),
        range: range
    )

    attachment = nil
    var line: CTLine? = try CTLineCreateWithAttributedString(#require(string))
    let width = try CTLineGetTypographicBounds(#require(line), nil, nil, nil)
    #expect(width == 24)

    line = nil
    string = nil
    delegate = nil
}

@MainActor
@Test func drawingInvokesLineDrawingActionForEveryLine() throws {
    let width: CGFloat = 260
    let lineCount = 12
    let attributedText = lineDrawingProbeText(lineCount: lineCount)
    let layout = TextLabel.Layout(attributedString: attributedText)
    let suggestedSize = layout.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    layout.containerSize = CGSize(width: width, height: suggestedSize.height)

    lineDrawingProbeInvocationCount = 0
    let context = try #require(makeBitmapContext(size: layout.containerSize))
    layout.draw(in: context)

    #expect(lineDrawingProbeInvocationCount >= lineCount)
}

@MainActor
@Test func naturalSizeFastPathMatchesFramesetterForNonWrappingWidths() {
    let layout = TextLabel.Layout(attributedString: NSAttributedString(
        string: "Short line",
        attributes: [.font: PlatformFont.systemFont(ofSize: 16)]
    ))
    let unconstrained = CGSize(
        width: CGFloat.greatestFiniteMagnitude,
        height: CGFloat.greatestFiniteMagnitude
    )

    let naturalSize = layout.sizeThatFits(unconstrained)

    // A fresh layout answers a wide-enough constraint identically to the fast path.
    let reference = TextLabel.Layout(attributedString: NSAttributedString(
        string: "Short line",
        attributes: [.font: PlatformFont.systemFont(ofSize: 16)]
    ))
    let wideConstraint = CGSize(width: naturalSize.width + 100, height: .greatestFiniteMagnitude)
    #expect(layout.sizeThatFits(wideConstraint) == reference.sizeThatFits(wideConstraint))

    // A narrower constraint must fall back to the framesetter and wrap.
    let narrowConstraint = CGSize(width: naturalSize.width / 2, height: .greatestFiniteMagnitude)
    let wrapped = layout.sizeThatFits(narrowConstraint)
    #expect(wrapped.height > naturalSize.height)
}

@MainActor
@Test func drawingWithVisibleRectStillInvokesAllLineDrawingActions() throws {
    let width: CGFloat = 260
    let lineCount = 12
    let attributedText = lineDrawingProbeText(lineCount: lineCount)
    let layout = TextLabel.Layout(attributedString: attributedText)
    let suggestedSize = layout.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    layout.containerSize = CGSize(width: width, height: suggestedSize.height)

    #expect(layout.visibleLineCount(in: nil) >= lineCount)

    let lineHeight = suggestedSize.height / CGFloat(layout.visibleLineCount(in: nil))
    let visibleRect = CGRect(x: 0, y: 0, width: width, height: lineHeight * 2)

    lineDrawingProbeInvocationCount = 0
    let context = try #require(makeBitmapContext(size: layout.containerSize))
    layout.draw(in: context, visibleRect: visibleRect)

    // Text drawing is still dirty-rect clipped, but line drawing actions can own
    // external layout side effects and must run for every laid-out line.
    #expect(layout.visibleLineCount(in: visibleRect) < layout.visibleLineCount(in: nil))
    #expect(lineDrawingProbeInvocationCount >= lineCount)
}

@MainActor
@Test func sizeThatFitsMatchesFramesetterSuggestionForLeftAlignedText() {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 5
    let text = NSMutableAttributedString(
        string: "Litext measures multi-line content through a real CoreText frame instead of a second framesetter pass.\nSecond paragraph keeps wrapping.",
        attributes: [
            .font: PlatformFont.systemFont(ofSize: 16),
            .paragraphStyle: paragraph,
        ]
    )

    let framesetter = CTFramesetterCreateWithAttributedString(text)
    for constraint in [
        CGSize(width: 220, height: CGFloat.greatestFiniteMagnitude),
        CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
        CGSize(width: 220, height: 40),
        // The framesetter treats non-positive dimensions as unconstrained.
        CGSize.zero,
        CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude),
        CGSize(width: 220, height: 0),
    ] {
        let layout = TextLabel.Layout(attributedString: text)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            constraint,
            nil
        )
        let measured = layout.sizeThatFits(constraint)
        #expect(abs(measured.width - suggested.width) < 0.001)
        #expect(abs(measured.height - suggested.height) < 0.001)
    }
}

@MainActor
@Test func sizeThatFitsKeepsFramesetterSuggestionForCenteredText() {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let text = NSAttributedString(
        string: "Centered short\nand a much longer centered line here",
        attributes: [
            .font: PlatformFont.systemFont(ofSize: 14),
            .paragraphStyle: paragraph,
        ]
    )

    let layout = TextLabel.Layout(attributedString: text)
    let measured = layout.sizeThatFits(CGSize(
        width: CGFloat.greatestFiniteMagnitude,
        height: CGFloat.greatestFiniteMagnitude
    ))

    let framesetter = CTFramesetterCreateWithAttributedString(text)
    let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter,
        CFRange(location: 0, length: 0),
        nil,
        CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
        nil
    )
    #expect(measured == suggested)
}

@MainActor
@Test func adoptedMeasurementFrameMatchesFreshlyGeneratedLayout() {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 3
    let text = NSMutableAttributedString()
    for index in 0 ..< 40 {
        text.append(NSAttributedString(
            string: "Adoption check line \(index) wraps once the width narrows sufficiently.\n",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .paragraphStyle: paragraph,
            ]
        ))
    }

    let width: CGFloat = 240

    // Measured first, so the container assignment can adopt the measurement frame.
    let adopted = TextLabel.Layout(attributedString: text)
    let suggested = adopted.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    adopted.containerSize = CGSize(width: width, height: suggested.height.rounded(.up))

    // Never measured, so the container assignment runs a full framesetter pass.
    let fresh = TextLabel.Layout(attributedString: text)
    fresh.containerSize = CGSize(width: width, height: suggested.height.rounded(.up))

    #expect(adopted.visibleLineCount(in: nil) == fresh.visibleLineCount(in: nil))

    for range in [
        NSRange(location: 0, length: 12),
        NSRange(location: text.length / 2, length: 30),
        NSRange(location: text.length - 20, length: 20),
    ] {
        let adoptedRects = adopted.rects(for: range)
        let freshRects = fresh.rects(for: range)
        #expect(adoptedRects.count == freshRects.count)
        for (lhs, rhs) in zip(adoptedRects, freshRects) {
            #expect(abs(lhs.origin.x - rhs.origin.x) < 0.001)
            #expect(abs(lhs.origin.y - rhs.origin.y) < 0.001)
            #expect(abs(lhs.width - rhs.width) < 0.001)
            #expect(abs(lhs.height - rhs.height) < 0.001)
        }
    }
}

@MainActor
private var lineDrawingProbeInvocationCount = 0

@MainActor
private func lineDrawingProbeText(lineCount: Int) -> NSAttributedString {
    let action = TextLabel.LineDrawingAction { _, _, _ in
        lineDrawingProbeInvocationCount += 1
    }
    let text = NSMutableAttributedString()
    for index in 0 ..< lineCount {
        text.append(NSAttributedString(
            string: "Probe line \(index) keeps layout stable while drawing is clipped.\n",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .litextLineDrawingAction: action,
            ]
        ))
    }
    return text
}

private func makeBitmapContext(size: CGSize) -> CGContext? {
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
