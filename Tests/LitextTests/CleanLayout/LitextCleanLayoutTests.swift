//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation
@testable import Litext
import Testing

#if canImport(UIKit) && !os(watchOS)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Requires Litext's layout output to be clean for every string in
/// `CleanLayoutCorpus` at every width in `CleanLayout.widths`.
///
/// Invariants (numbered as in `assertCleanLayout`):
/// 1. All geometry is finite and no size is negative.
/// 2. `sizeThatFits` is deterministic: repeated, fresh, cache hit and miss, after
///    `invalidateLayout()`, after a natural-size query and after laying out all agree;
///    its width fits the proposal except for single-cluster overflow; a view's
///    intrinsic size is that measurement pixel-ceiled, without jitter.
/// 3. Laid out in the measured size, every character is in exactly one line, line
///    ranges ascend contiguously over the whole string, and no line is dropped.
/// 4. Line boxes run top to bottom without overlapping, stay inside the container,
///    start at its top and end within a point of its bottom.
/// 5. Selection rects stay in the container and in their line; every character has a
///    rect (a newline may have a zero-width caret); disjoint ranges do not overlap.
/// 6. Hit testing the centre of a character returns that character.
/// 7. Centered and right-aligned lines sit where expected; justified lines that are not
///    the last of their paragraph span the full width.
/// 8. Link regions stay in the container and in a line box and match their attribute.
/// 9. Attachments keep their size, stay in the container and do not cover neighbours.
/// 10. A `TextLabelView` reports the measured size, lays out at its frame, draws ink
///     inside its bounds and none outside them.
/// 11. Laying out again, reassigning an equal string and resizing A → B → A all
///     reproduce identical geometry.
@MainActor
@Suite("Clean layout")
struct LitextCleanLayoutTests {
    /// The largest glyph overhang in the corpus is 1.9pt (Hiragino `J`).
    static let glyphOverhangLimit: CGFloat = 2.5

    static let unmeasuredWrapIssue: Comment = """
    Whitespace that CoreText wraps but does not measure (a tab narrower than the \
    proposal) yields a zero-width size, and a zero-width container means unconstrained, \
    so the container lays the text out on fewer lines than were measured.
    """

    /// Whether `text` measures zero wide at `width` yet needs more lines there than
    /// unconstrained: only whitespace CoreText wraps without letting it hang.
    static func wrapsUnmeasuredWhitespace(_ text: NSAttributedString, width: CGFloat) -> Bool {
        let layout = TextLabel.Layout(attributedString: text)
        let measured = layout.sizeThatFits(CleanLayout.proposal(width))
        let natural = layout.sizeThatFits(CleanLayout.proposal(.greatestFiniteMagnitude))
        return text.length > 0 && measured.width == 0 && measured.height > natural.height
    }

    // MARK: 2. Measurement

    @Test(arguments: CleanLayoutCorpus.allCases, CleanLayout.widths)
    func `measurement is deterministic`(corpus: CleanLayoutCorpus, width: CGFloat) {
        let text = CleanLayout.probed(corpus.makeText())
        let proposal = CleanLayout.proposal(width)
        let layout = TextLabel.Layout(attributedString: text)
        let size = layout.sizeThatFits(proposal)

        #expect(size.isCleanFinite, "\(size)")
        #expect(layout.sizeThatFits(proposal) == size, "cache hit")
        #expect(TextLabel.Layout(attributedString: text).sizeThatFits(proposal) == size, "fresh layout")

        // Evict the measurement history, then measure again.
        for other in [7, 33, 99, 250, 640, 2000] as [CGFloat] where other != width {
            _ = layout.sizeThatFits(CleanLayout.proposal(other))
        }
        #expect(layout.sizeThatFits(proposal) == size, "cache miss")

        layout.invalidateLayout()
        #expect(layout.sizeThatFits(proposal) == size, "after invalidateLayout()")

        // The natural-size fast path must agree with a direct measurement.
        let naturalFirst = TextLabel.Layout(attributedString: text)
        _ = naturalFirst.sizeThatFits(CleanLayout.proposal(.greatestFiniteMagnitude))
        #expect(naturalFirst.sizeThatFits(proposal) == size, "after a natural-size query")

        // Laying out (which adopts or rebuilds frames) must not change the answer.
        let laidOut = TextLabel.Layout(attributedString: text)
        laidOut.containerSize = CGSize(width: CleanLayout.isUnconstrained(width) ? 500 : width, height: 300)
        #expect(laidOut.sizeThatFits(proposal) == size, "after laying out first")
        laidOut.containerSize = CGSize(width: CleanLayout.pixelCeil(size.width), height: CleanLayout.pixelCeil(size.height))
        #expect(laidOut.sizeThatFits(proposal) == size, "after laying out in the measured size")
    }

    // MARK: 1, 3-9. Layout

    @Test(arguments: CleanLayoutCorpus.allCases, CleanLayout.widths)
    func `layout in the measured size is clean`(corpus: CleanLayoutCorpus, width: CGFloat) {
        let text = corpus.makeText()
        let prepared = PreparedLayout(text, width: width)
        withKnownIssue(Self.unmeasuredWrapIssue, isIntermittent: true) {
            assertCleanLayout(prepared.layout, width: width, corpus: corpus)
        } when: {
            Self.wrapsUnmeasuredWhitespace(text, width: width)
        }

        // A host that keeps the proposed width instead of shrink-wrapping must see
        // the same lines. Pixel-ceiling a width that is not on the pixel grid can
        // round past the proposal (57.24 -> 57.5 for 57.3) and let a glyph more fit
        // on a line; a wider container never needs more lines, so only those cases
        // are skipped.
        guard !CleanLayout.isUnconstrained(width), !prepared.overflows,
              prepared.layout.containerSize.width <= width
        else { return }
        let shrinkWrapped = CleanLayoutSnapshot(prepared.layout).lines.map(\.range)
        prepared.layout.containerSize = CGSize(width: width, height: prepared.layout.containerSize.height)
        prepared.layout.updateHighlightRegions()
        assertCleanLayout(prepared.layout, width: width, corpus: corpus, context: " (proposed width)")
        withKnownIssue(Self.unmeasuredWrapIssue, isIntermittent: true) {
            #expect(
                CleanLayoutSnapshot(prepared.layout).lines.map(\.range) == shrinkWrapped,
                "shrink-wrapping the container re-broke the lines",
            )
        } when: {
            Self.wrapsUnmeasuredWhitespace(text, width: width)
        }
    }

    // MARK: 11. Stability

    @Test(arguments: CleanLayoutCorpus.allCases, CleanLayout.widths)
    func `geometry is stable`(corpus: CleanLayoutCorpus, width: CGFloat) {
        let text = corpus.makeText()
        let first = PreparedLayout(text, width: width)
        let reference = CleanLayoutSnapshot(first.layout)

        let second = PreparedLayout(text, width: width)
        #expect(CleanLayoutSnapshot(second.layout) == reference, "laying out the same string twice")

        let sizeA = first.layout.containerSize
        let sizeB = CGSize(width: max(sizeA.width * 0.5, 1) + 13, height: sizeA.height + 40)
        first.layout.containerSize = sizeB
        first.layout.updateHighlightRegions()
        first.layout.containerSize = sizeA
        first.layout.updateHighlightRegions()
        #expect(CleanLayoutSnapshot(first.layout) == reference, "resizing A -> B -> A")

        first.layout.invalidateLayout()
        first.layout.updateHighlightRegions()
        #expect(CleanLayoutSnapshot(first.layout) == reference, "after invalidateLayout()")
    }

    #if !os(watchOS)

        // MARK: 10, 11. View level

        @Test(arguments: CleanLayoutCorpus.allCases, CleanLayout.widths)
        func `label view is clean`(corpus: CleanLayoutCorpus, width: CGFloat) throws {
            let text = CleanLayout.probed(corpus.makeText())
            let label = TextLabelView(attributedText: text)
            if !CleanLayout.isUnconstrained(width) {
                label.preferredMaxLayoutWidth = width
            }
            let scale = label.displayScale
            let measured = TextLabel.Layout(attributedString: text).sizeThatFits(CleanLayout.proposal(width))
            // The width rounds up to the pixel grid but stops at the proposal, so the
            // frame never lets the text wrap into fewer lines than were measured.
            let ceiledWidth = CleanLayout.pixelCeil(measured.width, scale: scale)
            let stopsAtProposal = !CleanLayout.isUnconstrained(width)
                && measured.width <= width && ceiledWidth > width
            let expected = CGSize(
                width: stopsAtProposal ? width : ceiledWidth,
                height: CleanLayout.pixelCeil(measured.height, scale: scale),
            )

            let intrinsic = label.intrinsicContentSize
            #expect(intrinsic == expected, "intrinsic \(intrinsic), measured \(measured) at @\(scale)x")
            #expect(label.intrinsicContentSize == intrinsic, "intrinsic size jitters between calls")
            if !stopsAtProposal {
                #expect(intrinsic.width * scale == (intrinsic.width * scale).rounded(), "width is not on the pixel grid")
            }
            #expect(intrinsic.height * scale == (intrinsic.height * scale).rounded(), "height is not on the pixel grid")

            label.frame = CGRect(origin: .zero, size: intrinsic)
            runCleanLayoutPass(label)
            #expect(label.textLayout.containerSize == intrinsic, "layout container does not match the frame")
            #expect(label.intrinsicContentSize == intrinsic, "intrinsic size changed after laying out")

            let overflows = !CleanLayout.isUnconstrained(width) && measured.width > width + CleanLayout.epsilon
            if !overflows {
                withKnownIssue(Self.unmeasuredWrapIssue, isIntermittent: true) {
                    assertCleanLayout(label.textLayout, width: width, corpus: corpus, context: " (view)")
                } when: {
                    Self.wrapsUnmeasuredWhitespace(text, width: width)
                }
            }

            let ink = try #require(renderCleanLayoutInk(label, scale: scale))
            let bounds = CGRect(origin: .zero, size: intrinsic)
            // However far a glyph overhangs, ink never strays more than the overhang
            // of a glyph from the frame: misplaced lines would.
            #expect(
                ink.outsideExtent.isNull
                    || bounds.insetBy(dx: -Self.glyphOverhangLimit, dy: -Self.glyphOverhangLimit)
                    .contains(ink.outsideExtent),
                "ink spans \(ink.outsideExtent), far outside the \(intrinsic) bounds",
            )
            withKnownIssue(
                "Glyph ink outside its typographic box draws past a frame sized to typographic bounds",
                isIntermittent: true,
            ) {
                #expect(
                    ink.outside == 0,
                    "\(ink.outside) ink pixels outside the \(intrinsic) bounds, spanning \(ink.outsideExtent) in view points",
                )
            } when: {
                corpus.hasGlyphOverhang
            }
            if corpus.drawsInk {
                #expect(ink.inside > 0, "no text was drawn")
            }

            // Reassigning an equal string keeps the geometry.
            let before = CleanLayoutSnapshot(label.textLayout)
            label.attributedText = NSAttributedString(attributedString: text)
            runCleanLayoutPass(label)
            #expect(CleanLayoutSnapshot(label.textLayout) == before, "reassigning an equal string")

            label.reloadTextLayout()
            runCleanLayoutPass(label)
            #expect(CleanLayoutSnapshot(label.textLayout) == before, "reloadTextLayout()")

            label.frame = CGRect(x: 0, y: 0, width: intrinsic.width + 37, height: intrinsic.height + 20)
            runCleanLayoutPass(label)
            label.frame = CGRect(origin: .zero, size: intrinsic)
            runCleanLayoutPass(label)
            #expect(CleanLayoutSnapshot(label.textLayout) == before, "resizing the view A -> B -> A")
        }

    #endif
}

#if !os(watchOS)

    @MainActor
    func runCleanLayoutPass(_ label: TextLabelView) {
        #if canImport(UIKit)
            label.setNeedsLayout()
            label.layoutIfNeeded()
        #elseif canImport(AppKit)
            label.needsLayout = true
            label.layout()
        #endif
    }

    struct CleanLayoutInk {
        var inside = 0
        var outside = 0
        /// The extent of the ink outside the bounds, in the view's coordinates.
        var outsideExtent = CGRect.null
    }

    /// Draws `label` through its own `draw(_:)` into a bitmap with a transparent margin
    /// around its bounds, and counts the opaque pixels inside and outside them.
    @MainActor
    func renderCleanLayoutInk(_ label: TextLabelView, scale: CGFloat, margin: CGFloat = 24) -> CleanLayoutInk? {
        let bounds = label.bounds
        let pixelWidth = Int(((bounds.width + margin * 2) * scale).rounded(.up))
        let pixelHeight = Int(((bounds.height + margin * 2) * scale).rounded(.up))
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return nil }

        // Top-left origin, one view point per `scale` pixels, offset by the margin.
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: margin, y: margin)

        #if canImport(UIKit)
            UIGraphicsPushContext(context)
            label.draw(bounds)
            UIGraphicsPopContext()
        #elseif canImport(AppKit)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            label.draw(bounds)
            NSGraphicsContext.restoreGraphicsState()
        #endif

        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: pixelWidth * pixelHeight * 4)
        let insideX = Int((margin * scale).rounded(.down)) ..< Int(((margin + bounds.width) * scale).rounded(.up))
        let insideY = Int((margin * scale).rounded(.down)) ..< Int(((margin + bounds.height) * scale).rounded(.up))

        var ink = CleanLayoutInk()
        for row in 0 ..< pixelHeight {
            for column in 0 ..< pixelWidth {
                // Opaque ink: at least half covered, so antialiasing fringes do not count.
                guard pixels[(row * pixelWidth + column) * 4 + 3] >= 128 else { continue }
                if insideX.contains(column), insideY.contains(row) {
                    ink.inside += 1
                } else {
                    ink.outside += 1
                    ink.outsideExtent = ink.outsideExtent.union(CGRect(
                        x: CGFloat(column) / scale - margin,
                        y: CGFloat(row) / scale - margin,
                        width: 1 / scale,
                        height: 1 / scale,
                    ))
                }
            }
        }
        return ink
    }

#endif
