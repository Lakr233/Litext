//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
@testable import Litext
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
    @Test func visibleTextDrawingRectKeepsGuardBandDuringPartialDirtyRedraw() throws {
        let label = LTXLabel(attributedText: NSAttributedString(string: "Hello"))
        label.frame = CGRect(x: 0, y: 0, width: 320, height: 600)

        let dirtyStrip = CGRect(x: 0, y: 280, width: 320, height: 2)
        let clippedDirtyRect = try #require(label.visibleTextDrawingRect(for: dirtyStrip))

        #expect(clippedDirtyRect.height > dirtyStrip.height)
        #expect(clippedDirtyRect.minY <= dirtyStrip.minY)
        #expect(clippedDirtyRect.maxY >= dirtyStrip.maxY)
        #expect(clippedDirtyRect.maxY <= label.bounds.maxY)

        label.drawsOnlyVisibleText = false
        #expect(label.visibleTextDrawingRect(for: dirtyStrip) == dirtyStrip)
    }

    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        @MainActor
        @Test func appKitVisibleRenderingObservesScrollClipBounds() {
            let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
            let label = LTXLabel(attributedText: NSAttributedString(string: "Hello"))
            label.frame = CGRect(x: 0, y: 0, width: 320, height: 600)

            scrollView.documentView = label
            label.updateVisibleRenderingObservation()

            #expect(label.visibleRenderingClipView === scrollView.contentView)
            #expect(label.visibleRenderingBoundsObserver != nil)
            #expect(scrollView.contentView.postsBoundsChangedNotifications)
        }
    #endif
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
@Test func visibleRectDrawingSkipsOffscreenLineActionsWithoutChangingLayoutHeight() throws {
    let width: CGFloat = 260
    let attributedText = lineDrawingProbeText(lineCount: 80)
    let layout = LTXTextLayout(attributedString: attributedText)
    let suggestedSize = layout.suggestContainerSize(
        withSize: CGSize(width: width, height: .greatestFiniteMagnitude)
    )
    layout.containerSize = CGSize(width: width, height: suggestedSize.height)

    let fullLineCount = layout.visibleLineCount(in: nil)
    let visibleRect = CGRect(x: 0, y: 0, width: width, height: 90)
    let visibleLineCount = layout.visibleLineCount(in: visibleRect)

    #expect(fullLineCount > visibleLineCount)
    #expect(visibleLineCount > 0)
    #expect(layout.suggestContainerSize(
        withSize: CGSize(width: width, height: .greatestFiniteMagnitude)
    ) == suggestedSize)

    lineDrawingProbeInvocationCount = 0
    let context = try #require(makeBitmapContext(size: layout.containerSize))
    layout.draw(in: context, visibleRect: visibleRect)

    #expect(lineDrawingProbeInvocationCount == visibleLineCount)
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
