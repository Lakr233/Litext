//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
@testable import Litext
import QuartzCore
import Testing

#if !os(watchOS)

    @MainActor
    private func runLayoutPass(_ label: TextLabelView) {
        #if canImport(UIKit)
            label.setNeedsLayout()
            label.layoutIfNeeded()
        #elseif canImport(AppKit)
            label.needsLayout = true
            label.layout()
        #endif
    }

    @MainActor
    private func makeLinkedText() throws -> NSAttributedString {
        let url = try #require(URL(string: "https://example.com/moved"))
        let text = NSMutableAttributedString(
            string: "Leading ",
            attributes: [.font: PlatformFont.systemFont(ofSize: 16)]
        )
        text.append(NSAttributedString(
            string: "link",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .link: url,
            ]
        ))
        text.append(NSAttributedString(
            string: " trailing",
            attributes: [.font: PlatformFont.systemFont(ofSize: 16)]
        ))
        return text
    }

    @MainActor
    private func regionIdentities(_ label: TextLabelView) -> Set<ObjectIdentifier> {
        Set(label.highlightRegions.map(ObjectIdentifier.init))
    }

    // MARK: - Frame invalidation granularity

    @MainActor
    @Test func movingTheFrameWithoutResizingKeepsTheExistingLayout() throws {
        let label = try TextLabelView(attributedText: makeLinkedText())
        label.frame = CGRect(x: 0, y: 0, width: 200, height: 60)
        runLayoutPass(label)

        let layoutBefore = label.textLayout
        let identitiesBefore = regionIdentities(label)
        let rectsBefore = label.highlightRegions.first?.rects
        #expect(!identitiesBefore.isEmpty)

        label.frame = CGRect(x: 37, y: 91, width: 200, height: 60)
        runLayoutPass(label)

        #expect(label.textLayout === layoutBefore)
        #expect(regionIdentities(label) == identitiesBefore)
        #expect(label.highlightRegions.first?.rects == rectsBefore)
    }

    @MainActor
    @Test func resizingTheFrameStillRebuildsTheLayout() throws {
        let label = try TextLabelView(attributedText: makeLinkedText())
        label.frame = CGRect(x: 0, y: 0, width: 200, height: 60)
        runLayoutPass(label)

        let identitiesBefore = regionIdentities(label)
        #expect(!identitiesBefore.isEmpty)

        label.frame = CGRect(x: 0, y: 0, width: 120, height: 90)
        runLayoutPass(label)

        #expect(label.textLayout.containerSize == CGSize(width: 120, height: 90))
        #expect(regionIdentities(label).isDisjoint(with: identitiesBefore))
    }

    // MARK: - attributedText equality guard

    @MainActor
    @Test func reassigningAnEqualAttributedStringKeepsTheLayout() {
        let font = PlatformFont.systemFont(ofSize: 16)
        let label = TextLabelView(
            attributedText: NSAttributedString(string: "Hello Litext", attributes: [.font: font])
        )
        let layoutBefore = label.textLayout

        label.attributedText = NSAttributedString(string: "Hello Litext", attributes: [.font: font])
        #expect(label.textLayout === layoutBefore)

        label.attributedText = NSAttributedString(string: "Different", attributes: [.font: font])
        #expect(label.textLayout !== layoutBefore)
        #expect(label.textLayout.attributedString.string == "Different")
    }

    @MainActor
    @Test func reloadTextLayoutSchedulesARebuildForAnUnchangedString() {
        let label = TextLabelView(attributedText: NSAttributedString(string: "Hello Litext"))
        label.frame = CGRect(x: 0, y: 0, width: 200, height: 60)
        runLayoutPass(label)
        #expect(!label.flags.layoutIsDirty)

        label.reloadTextLayout()

        #expect(label.flags.layoutIsDirty)
        runLayoutPass(label)
        #expect(label.textLayout.containerSize == CGSize(width: 200, height: 60))
    }

#endif // !os(watchOS)

// MARK: - Measurement cache across several widths

private let unconstrainedHeight = CGFloat.greatestFiniteMagnitude

@MainActor
@Test func sizeThatFitsStaysCorrectWhenWidthsAlternate() {
    let text = NSAttributedString(
        string: String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 8),
        attributes: [.font: PlatformFont.systemFont(ofSize: 16)]
    )
    let layout = TextLabel.Layout(attributedString: text)

    let wide = layout.sizeThatFits(CGSize(width: 300, height: unconstrainedHeight))
    let narrow = layout.sizeThatFits(CGSize(width: 140, height: unconstrainedHeight))
    #expect(narrow.height > wide.height)

    // Alternating back and forth must never hand back the other width's measurement.
    for _ in 0 ..< 4 {
        #expect(layout.sizeThatFits(CGSize(width: 300, height: unconstrainedHeight)) == wide)
        #expect(layout.sizeThatFits(CGSize(width: 140, height: unconstrainedHeight)) == narrow)
    }

    layout.invalidateLayout()
    #expect(layout.sizeThatFits(CGSize(width: 300, height: unconstrainedHeight)) == wide)
    #expect(layout.sizeThatFits(CGSize(width: 140, height: unconstrainedHeight)) == narrow)
}

@MainActor
@Test func measurementCacheEvictsBeyondItsLimitWithoutReturningStaleSizes() {
    let text = NSAttributedString(
        string: String(repeating: "Litext measures text with CoreText. ", count: 10),
        attributes: [.font: PlatformFont.systemFont(ofSize: 16)]
    )
    let layout = TextLabel.Layout(attributedString: text)

    let widths: [CGFloat] = [320, 280, 240, 200, 160, 120]
    let expected = widths.map { width in
        layout.sizeThatFits(CGSize(width: width, height: unconstrainedHeight))
    }

    for (width, size) in zip(widths, expected) {
        #expect(layout.sizeThatFits(CGSize(width: width, height: unconstrainedHeight)) == size)
    }
}

// MARK: - Highlight extraction guard

@MainActor
@Test func textWithoutLinksOrAttachmentsHasNoHighlightRegions() {
    let layout = TextLabel.Layout(attributedString: NSAttributedString(
        string: "Plain text carries no links and no attachments.",
        attributes: [.font: PlatformFont.systemFont(ofSize: 16)]
    ))
    layout.containerSize = CGSize(width: 200, height: 80)

    layout.updateHighlightRegions()

    #expect(layout.highlightRegions.isEmpty)
}

@MainActor
@Test func textWithLinksStillProducesHighlightRegions() throws {
    let url = try #require(URL(string: "https://example.com/kept"))
    let text = NSMutableAttributedString(
        string: "See ",
        attributes: [.font: PlatformFont.systemFont(ofSize: 16)]
    )
    text.append(NSAttributedString(
        string: "this link",
        attributes: [
            .font: PlatformFont.systemFont(ofSize: 16),
            .link: url,
        ]
    ))

    let layout = TextLabel.Layout(attributedString: text)
    layout.containerSize = CGSize(width: 200, height: 80)
    layout.updateHighlightRegions()

    let region = try #require(layout.highlightRegions.first)
    #expect(region.kind == .link)
    #expect(region.attributes[.link] as? URL == url)
    #expect(!region.rects.isEmpty)
}

@MainActor
@Test func attachmentOnlyTextStillProducesHighlightRegions() {
    let attachment = TextLabel.Attachment()
    attachment.size = CGSize(width: 24, height: 16)
    let layout = TextLabel.Layout(attributedString: attachment.attributedString(
        attributes: [.font: PlatformFont.systemFont(ofSize: 16)]
    ))
    layout.containerSize = CGSize(width: 200, height: 80)
    layout.updateHighlightRegions()

    #expect(layout.highlightRegions.contains { $0.kind == .attachment })
}

// MARK: - Run delegate metrics

@MainActor
@Test func invalidateLayoutObservesChangedAttachmentMetrics() {
    let attachment = TextLabel.Attachment()
    attachment.size = CGSize(width: 60, height: 40)
    let text = NSMutableAttributedString(
        string: "before ",
        attributes: [.font: PlatformFont.systemFont(ofSize: 16)]
    )
    text.append(attachment.attributedString(attributes: [.font: PlatformFont.systemFont(ofSize: 16)]))
    text.append(NSAttributedString(
        string: " after",
        attributes: [.font: PlatformFont.systemFont(ofSize: 16)]
    ))

    let constraint = CGSize(width: 300, height: unconstrainedHeight)
    let layout = TextLabel.Layout(attributedString: text)
    let before = layout.sizeThatFits(constraint)

    attachment.size = CGSize(width: 200, height: 120)
    layout.invalidateLayout()
    let after = layout.sizeThatFits(constraint)

    // CoreText caches typographic bounds obtained from a run delegate inside the
    // framesetter, so reusing it would report the new width with the old line height.
    // A layout rebuilt from scratch is the ground truth.
    let rebuilt = TextLabel.Layout(attributedString: text).sizeThatFits(constraint)

    #expect(after == rebuilt)
    #expect(after.height > before.height)
    #expect(after.width > before.width)
}

#if !os(watchOS)

    // MARK: - UIKit / AppKit phase separation

    @MainActor
    @Test func drawingIsSkippedWhileTheLayoutTrailsTheBounds() {
        let text = NSAttributedString(
            string: String(repeating: "wrap me across several lines please. ", count: 12),
            attributes: [.font: PlatformFont.systemFont(ofSize: 16)]
        )
        let label = TextLabelView(attributedText: text)
        label.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        runLayoutPass(label)
        #expect(label.canDrawTextLayout)

        // Growing the view leaves the layout describing the old container until the next
        // layout pass. Lines are positioned against that container height, so painting now
        // would offset every one of them.
        label.frame = CGRect(x: 0, y: 0, width: 300, height: 420)
        #expect(label.textLayout.containerSize != label.bounds.size)
        #expect(!label.canDrawTextLayout)

        runLayoutPass(label)
        #expect(label.textLayout.containerSize == label.bounds.size)
        #expect(label.canDrawTextLayout)
    }

    /// Pins the reported value. Whether a height-only change still *dirties* the intrinsic
    /// size is not observable from here — `invalidateIntrinsicContentSize()` changes no public
    /// state — so that half is covered by the instrumented benchmark rather than this test.
    @MainActor
    @Test func heightOnlyChangesDoNotDisturbTheIntrinsicSize() {
        let text = NSAttributedString(
            string: String(repeating: "measure me. ", count: 20),
            attributes: [.font: PlatformFont.systemFont(ofSize: 16)]
        )
        let label = TextLabelView(attributedText: text)
        label.preferredMaxLayoutWidth = 240
        label.frame = CGRect(x: 0, y: 0, width: 240, height: 100)
        runLayoutPass(label)

        let intrinsicAtWidth = label.intrinsicContentSize
        label.frame = CGRect(x: 0, y: 0, width: 240, height: 400)
        runLayoutPass(label)
        #expect(label.intrinsicContentSize == intrinsicAtWidth)

        label.preferredMaxLayoutWidth = 160
        runLayoutPass(label)
        #expect(label.intrinsicContentSize.height > intrinsicAtWidth.height)
    }

    /// Pins the deduplication contract across layout passes.
    ///
    /// This does not prove the phase fix in `performLayout()`: a layout pass only reaches the
    /// deduplication broadcast when the view being laid out owns a selection, and the
    /// deduplication itself keeps at most one label selected, so the broadcast is a no-op in
    /// practice. Suppressing the menu during layout is the part that matters, and it lives
    /// behind `canImport(UIKit)` — unreachable from a macOS test run.
    @MainActor
    @Test func aLayoutPassDoesNotClearASiblingSelection() {
        let font = PlatformFont.systemFont(ofSize: 16)
        let first = TextLabelView(attributedText: NSAttributedString(string: "first label text", attributes: [.font: font]))
        let second = TextLabelView(attributedText: NSAttributedString(string: "second label text", attributes: [.font: font]))
        first.isSelectable = true
        second.isSelectable = true
        first.frame = CGRect(x: 0, y: 0, width: 300, height: 60)
        second.frame = CGRect(x: 0, y: 80, width: 300, height: 60)
        runLayoutPass(first)
        runLayoutPass(second)

        first.selectionRange = NSRange(location: 0, length: 5)
        #expect(first.selectionRange != nil)

        // Re-laying out `second` runs its selection-layer update. That update must not
        // broadcast the deduplication notification, which would reach into `first`.
        second.frame = CGRect(x: 0, y: 80, width: 260, height: 60)
        runLayoutPass(second)
        #expect(first.selectionRange != nil)

        // A genuine selection change still wins the selection away.
        second.selectionRange = NSRange(location: 0, length: 6)
        #expect(first.selectionRange == nil)
    }

    @MainActor
    @Test func selectionHighlightFollowsAReflow() {
        let text = NSAttributedString(
            string: String(repeating: "wrap me across several lines please. ", count: 12),
            attributes: [.font: PlatformFont.systemFont(ofSize: 16)]
        )
        let label = TextLabelView(attributedText: text)
        label.isSelectable = true
        label.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        runLayoutPass(label)
        label.selectionRange = NSRange(location: 0, length: 40)

        let before = label.selectionLayer?.path?.boundingBox
        #expect(before != nil)

        label.frame = CGRect(x: 0, y: 0, width: 200, height: 300)
        runLayoutPass(label)

        let after = label.selectionLayer?.path?.boundingBox
        #expect(after != nil)
        #expect(after != before)
    }

#endif // !os(watchOS)
