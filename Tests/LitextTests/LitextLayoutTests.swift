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
    let layout = LTXTextLayout(attributedString: NSAttributedString(string: "Hello Litext"))
    layout.containerSize = CGSize(width: 200, height: 60)

    #expect(layout.rects(for: NSRange(location: NSNotFound, length: 1)).isEmpty)
    #expect(layout.rects(for: NSRange(location: -1, length: 1)).isEmpty)
    #expect(layout.rects(for: NSRange(location: 0, length: 0)).isEmpty)
    #expect(layout.rects(for: NSRange(location: 500, length: 5)).isEmpty)
}

#if !os(watchOS)
    @MainActor
    @Test func publicSelectionRangeIsSanitized() {
        let label = LTXLabel(attributedText: NSAttributedString(string: "Hello"))

        label.selectionRange = NSRange(location: 1, length: 100)
        #expect(label.selectionRange == NSRange(location: 1, length: 4))

        label.selectionRange = NSRange(location: NSNotFound, length: 1)
        #expect(label.selectionRange == nil)

        label.selectionRange = NSRange(location: 0, length: 0)
        #expect(label.selectionRange == nil)
    }

    @MainActor
    @Test func clearSelectionRemovesStaleSelectionLayerEvenWhenRangeIsNil() {
        let label = LTXLabel(attributedText: NSAttributedString(string: "Hello"))
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

        let attachmentRegion = try #require(label.highlightRegions.first { $0.kind == .attachment })
        let rect = try #require(attachmentRegion.cgRects.first)
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

    #expect(linkRegions.count == 2)
    #expect(attachmentRegions.count == 1)
    #expect(linkRegions.contains { $0.stringRange == NSRange(location: 6, length: 11) })
    #expect(attachmentRegions.first?.cgRects.isEmpty == false)
}

@MainActor
@Test func attachmentRunDelegateUsesRetainedMetricsAfterOriginalAttachmentDrops() throws {
    var attachment: LTXAttachment? = LTXAttachment()
    attachment?.size = CGSize(width: 24, height: 16)
    let cachedDelegate = try #require(attachment?.runDelegate) as AnyObject
    let repeatedDelegate = try #require(attachment?.runDelegate) as AnyObject
    #expect(ObjectIdentifier(cachedDelegate) == ObjectIdentifier(repeatedDelegate))

    var string: NSMutableAttributedString? = NSMutableAttributedString(string: LTXReplacementText)
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
    let layout = LTXTextLayout(attributedString: attributedText)
    let suggestedSize = layout.suggestContainerSize(
        withSize: CGSize(width: width, height: .greatestFiniteMagnitude)
    )
    layout.containerSize = CGSize(width: width, height: suggestedSize.height)

    lineDrawingProbeInvocationCount = 0
    let context = try #require(makeBitmapContext(size: layout.containerSize))
    layout.draw(in: context)

    #expect(lineDrawingProbeInvocationCount >= lineCount)
}

@MainActor
@Test func naturalSizeFastPathMatchesFramesetterForNonWrappingWidths() {
    let layout = LTXTextLayout(attributedString: NSAttributedString(
        string: "Short line",
        attributes: [.font: PlatformFont.systemFont(ofSize: 16)]
    ))
    let unconstrained = CGSize(
        width: CGFloat.greatestFiniteMagnitude,
        height: CGFloat.greatestFiniteMagnitude
    )

    let naturalSize = layout.suggestContainerSize(withSize: unconstrained)

    // A fresh layout answers a wide-enough constraint identically to the fast path.
    let reference = LTXTextLayout(attributedString: NSAttributedString(
        string: "Short line",
        attributes: [.font: PlatformFont.systemFont(ofSize: 16)]
    ))
    let wideConstraint = CGSize(width: naturalSize.width + 100, height: .greatestFiniteMagnitude)
    #expect(layout.suggestContainerSize(withSize: wideConstraint) == reference.suggestContainerSize(withSize: wideConstraint))

    // A narrower constraint must fall back to the framesetter and wrap.
    let narrowConstraint = CGSize(width: naturalSize.width / 2, height: .greatestFiniteMagnitude)
    let wrapped = layout.suggestContainerSize(withSize: narrowConstraint)
    #expect(wrapped.height > naturalSize.height)
}

@MainActor
private var lineDrawingProbeInvocationCount = 0

@MainActor
private func lineDrawingProbeText(lineCount: Int) -> NSAttributedString {
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
