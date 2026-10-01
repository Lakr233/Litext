//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreGraphics
import CoreText
@testable import Litext
import Testing

/// `TextLabel.Layout` and `TextLabel.Attachment` are the parts watchOS shares, so these
/// tests cover the watchOS label's memory behaviour too.
///
/// Static storage in the module, audited for unbounded growth: `Layout.lastGeneration` (one
/// `Int`), `TextLabelView.appliedCursor` (one `NSCursor`, AppKit), `menuOwnerIdentifier`
/// (one `UUID`, UIKit), and constants. Nothing caches framesetters, frames or lines globally.
@MainActor
@Suite("Layout lifetime", .tags(.memory))
struct LitextLayoutLifetimeTests {
    private func bitmapContext(_ size: CGSize) -> CGContext? {
        CGContext(
            data: nil,
            width: max(1, Int(size.width.rounded(.up))),
            height: max(1, Int(size.height.rounded(.up))),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// Runs every pass a host runs: measure, lay out, extract regions, draw, query.
    private func exercise(_ layout: TextLabel.Layout, width: CGFloat = 240) {
        let size = layout.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        layout.containerSize = CGSize(width: width, height: size.height)
        layout.updateHighlightRegions()
        if let context = bitmapContext(layout.containerSize) {
            layout.draw(in: context)
        }
        _ = layout.layoutRuns(matching: .link)
        _ = layout.rects(for: NSRange(location: 0, length: 4))
    }

    // MARK: - Layout

    @Test("A layout deallocates together with its framesetter and lines")
    func layoutReleasesCoreTextObjects() throws {
        weak var weakLayout: TextLabel.Layout?
        weak var weakFramesetter: CTFramesetter?
        weak var weakLine: CTLine?
        try autoreleasepool {
            let text = uniqueText(length: 300)
            appendLink(to: text)
            let layout = TextLabel.Layout(attributedString: text)
            exercise(layout)
            weakLayout = layout
            weakFramesetter = try layoutFramesetter(layout)
            weakLine = try #require(layoutLines(layout).first)
        }
        #expect(weakLayout == nil)
        #expect(weakFramesetter == nil)
        #expect(weakLine == nil)
    }

    @Test("Rebuilding a layout releases each previous framesetter")
    func invalidateLayoutReleasesOldFramesetters() throws {
        let layout = TextLabel.Layout(attributedString: uniqueText(length: 200))
        exercise(layout)
        var oldFramesetters: [WeakBox<CTFramesetter>] = []
        for _ in 0 ..< 100 {
            try autoreleasepool {
                try oldFramesetters.append(WeakBox(layoutFramesetter(layout)))
                layout.invalidateLayout()
            }
        }
        #expect(oldFramesetters.allSatisfy { $0.value == nil })
        // Only the live framesetter remains.
        let current = try layoutFramesetter(layout)
        #expect(oldFramesetters.allSatisfy { $0.value !== current })
    }

    @Test("Many short-lived layouts leave no framesetter or layout behind")
    func manyLayoutsReleaseEverything() throws {
        var layouts: [WeakBox<TextLabel.Layout>] = []
        var framesetters: [WeakBox<CTFramesetter>] = []
        try autoreleasepool {
            for _ in 0 ..< 200 {
                let text = uniqueText(length: 120)
                appendLink(to: text)
                let layout = TextLabel.Layout(attributedString: text)
                exercise(layout, width: CGFloat.random(in: 80 ... 400))
                layouts.append(WeakBox(layout))
                try framesetters.append(WeakBox(layoutFramesetter(layout)))
            }
        }
        #expect(layouts.allSatisfy { $0.value == nil })
        #expect(framesetters.allSatisfy { $0.value == nil })
    }

    @Test("A layout with attachments deallocates, and so do its attachments")
    func layoutWithAttachmentsDeallocates() async {
        weak var weakLayout: TextLabel.Layout?
        weak var weakAttachment: TextLabel.Attachment?
        autoreleasepool {
            let attachment = TextLabel.Attachment(size: CGSize(width: 30, height: 20))
            let text = uniqueText()
            appendAttachment(to: text, attachment)
            let layout = TextLabel.Layout(attributedString: text)
            exercise(layout)
            #expect(layout.highlightRegions.contains { $0.kind == .attachment })
            weakLayout = layout
            weakAttachment = attachment
        }
        #expect(weakLayout == nil)
        // CoreText may keep the typeset run attributes in a cache for a moment.
        #expect(await waitUntil { weakAttachment == nil })
    }

    @Test("Highlight regions outlive their layout without keeping it alive")
    func highlightRegionsDoNotRetainTheLayout() {
        weak var weakLayout: TextLabel.Layout?
        var regions: [TextLabel.HighlightRegion] = []
        autoreleasepool {
            let text = uniqueText()
            appendLink(to: text)
            let layout = TextLabel.Layout(attributedString: text)
            exercise(layout)
            regions = layout.highlightRegions
            weakLayout = layout
        }
        #expect(!regions.isEmpty)
        #expect(weakLayout == nil)
    }

    // MARK: - Measurement cache

    @Test("Measuring at 1,000 widths keeps the measurement cache capped")
    func measurementCacheIsBounded() throws {
        let layout = TextLabel.Layout(attributedString: uniqueText(length: 400))
        for index in 0 ..< 1000 {
            _ = layout.sizeThatFits(CGSize(width: 100 + CGFloat(index) * 0.5, height: .greatestFiniteMagnitude))
            _ = layout.sizeThatFits(CGSize(width: 100 + CGFloat(index) * 0.5, height: 10 + CGFloat(index)))
        }
        #expect(try measurementHistoryCount(layout) <= 4)
        #expect(try measurementHistoryCount(layout) > 0)
    }

    #if !os(watchOS)
        @Test("A label measured at 1,000 widths keeps its layout's measurement cache capped")
        func labelMeasurementCacheIsBounded() throws {
            let label = makeLaidOutTestLabel(uniqueText(length: 400))
            for index in 0 ..< 1000 {
                label.preferredMaxLayoutWidth = 100 + CGFloat(index)
                _ = label.intrinsicContentSize
                if index.isMultiple(of: 10) {
                    label.frame.size.width = 100 + CGFloat(index)
                    performLayoutPass(label)
                }
            }
            #expect(try measurementHistoryCount(label.textLayout) <= 4)
        }
    #endif

    // MARK: - Attachments

    private final class ComputedAttachment: TextLabel.Attachment {
        var width: CGFloat = 10

        override var size: CGSize {
            get { CGSize(width: width, height: 12) }
            set { _ = newValue }
        }
    }

    @Test("An attachment subclass with a computed size is measured with its current size and deallocates")
    func computedSizeAttachment() async throws {
        weak var weakAttachment: ComputedAttachment?
        try autoreleasepool {
            let attachment = ComputedAttachment()
            let text = NSMutableAttributedString(attributedString: attachment.attributedString())
            let layout = TextLabel.Layout(attributedString: text)
            exercise(layout)
            let firstWidth = try #require(layout.layoutRuns(matching: .litextAttachment).first).rect.width
            #expect(firstWidth == 10)

            attachment.width = 44
            layout.invalidateLayout()
            let secondWidth = try #require(layout.layoutRuns(matching: .litextAttachment).first).rect.width
            #expect(secondWidth == 44)
            weakAttachment = attachment
        }
        #expect(await waitUntil { weakAttachment == nil })
    }

    @Test("One attachment shared by many strings and layouts survives them all and still measures")
    func sharedAttachmentAcrossLayouts() throws {
        let attachment = TextLabel.Attachment(size: CGSize(width: 21, height: 13))
        let unretainedCount = try runMetricsRetainCount(attachment)
        let delegate = attachment.runDelegate
        // The run delegate holds the box: one retain, no more and no less.
        #expect(try runMetricsRetainCount(attachment) == unretainedCount + 1)
        autoreleasepool {
            var layouts: [TextLabel.Layout] = []
            for _ in 0 ..< 100 {
                let text = uniqueText()
                appendAttachment(to: text, attachment)
                appendAttachment(to: text, attachment)
                let layout = TextLabel.Layout(attributedString: text)
                exercise(layout)
                layouts.append(layout)
            }
            for layout in layouts.shuffled() {
                layout.invalidateLayout()
            }
        }
        // Every run delegate CoreText created is released by now. An over-released metrics
        // box would be gone, and reading the size would crash or return garbage.
        #expect(attachment.runDelegate === delegate)
        #expect(try runMetricsRetainCount(attachment) == unretainedCount + 1)
        attachment.size = CGSize(width: 33, height: 17)
        let layout = TextLabel.Layout(attributedString: attachment.attributedString())
        exercise(layout)
        let run = try #require(layout.layoutRuns(matching: .litextAttachment).first)
        #expect(run.rect.width == 33)
        #expect(abs(run.rect.height - 17) < 0.001)
    }
}

#if !os(watchOS)

    @MainActor
    @Suite("Attachment lifetime in labels", .tags(.memory))
    struct LitextAttachmentLifetimeTests {
        @Test("An attachment removed from the text has its view removed from the label")
        func removedAttachmentViewLeavesTheLabel() {
            let view = PlatformView()
            let attachment = TextLabel.Attachment(size: CGSize(width: 20, height: 20), view: view)
            let text = uniqueText()
            appendAttachment(to: text, attachment)
            let label = makeLaidOutTestLabel(text)
            #expect(view.superview === label)
            #expect(label.attachmentViews.contains(view))

            label.attributedText = uniqueText()
            performLayoutPass(label)
            #expect(view.superview == nil)
            #expect(label.attachmentViews.isEmpty)
            #expect(!label.subviews.contains(view))
        }

        @Test("An attachment the host keeps stays alive and works when added again")
        func keptAttachmentWorksWhenReadded() async throws {
            let view = PlatformView()
            let attachment = TextLabel.Attachment(size: CGSize(width: 26, height: 18), view: view)
            func text() -> NSAttributedString {
                let text = uniqueText()
                appendAttachment(to: text, attachment)
                return text
            }

            weak var weakFirstLabel: TextLabelView?
            autoreleasepool {
                let label = makeLaidOutTestLabel(text())
                label.attributedText = uniqueText()
                performLayoutPass(label)
                #expect(view.superview == nil)

                // Back in the same label.
                label.attributedText = text()
                performLayoutPass(label)
                #expect(view.superview === label)
                #expect(view.frame.size == CGSize(width: 26, height: 18))
                weakFirstLabel = label
            }
            #expect(weakFirstLabel == nil)
            #expect(view.superview == nil)

            // And in a new label once the first one is gone.
            await yieldToMainActor()
            let label = makeLaidOutTestLabel(text())
            #expect(view.superview === label)
            #expect(view.frame.size == CGSize(width: 26, height: 18))
            let region = try #require(label.highlightRegions.first { $0.kind == .attachment })
            #expect(region.attributes[.litextAttachment] as? TextLabel.Attachment === attachment)
        }

        @Test("One attachment shared by 100 labels survives them all and can be reused")
        func sharedAttachmentStress() async throws {
            let view = PlatformView()
            let attachment = TextLabel.Attachment(size: CGSize(width: 19, height: 15), view: view)
            let unretainedCount = try runMetricsRetainCount(attachment)
            var weakLabels: [WeakBox<TextLabelView>] = []
            autoreleasepool {
                var labels: [TextLabelView] = []
                for index in 0 ..< 100 {
                    let text = uniqueText()
                    appendAttachment(to: text, attachment)
                    if index.isMultiple(of: 2) {
                        appendLink(to: text)
                    }
                    let label = makeLaidOutTestLabel(text)
                    render(label)
                    labels.append(label)
                }
                // A view has one superview: the label laid out last owns it.
                #expect(view.superview === labels.last)
                for label in labels.shuffled() {
                    label.reloadTextLayout()
                    performLayoutPass(label)
                }
                weakLabels = labels.map(WeakBox.init)
            }
            #expect(weakLabels.allSatisfy { $0.value == nil })
            #expect(view.superview == nil)
            // Neither over-released nor leaked by 100 labels: the cached run delegate's one.
            #expect(try runMetricsRetainCount(attachment) == unretainedCount + 1)

            await yieldToMainActor()
            attachment.size = CGSize(width: 31, height: 15)
            let text = uniqueText()
            appendAttachment(to: text, attachment)
            let label = makeLaidOutTestLabel(text)
            render(label)
            #expect(view.superview === label)
            #expect(view.frame.width == 31)
            let run = try #require(label.layoutRuns(matching: .litextAttachment).first)
            #expect(run.rect.width == 31)
        }

        @Test("A label that drops a shared attachment leaves its view in the label that shows it")
        func droppingASharedAttachmentKeepsItInTheOtherLabel() {
            let view = PlatformView()
            let attachment = TextLabel.Attachment(size: CGSize(width: 20, height: 20), view: view)
            func text() -> NSAttributedString {
                let text = uniqueText()
                appendAttachment(to: text, attachment)
                return text
            }
            let first = makeLaidOutTestLabel(text())
            let second = makeLaidOutTestLabel(text())
            #expect(view.superview === second)

            first.attributedText = uniqueText()
            performLayoutPass(first)
            #expect(view.superview === second)
            #expect(second.attachmentViews.contains(view))
        }
    }

#endif // !os(watchOS)
