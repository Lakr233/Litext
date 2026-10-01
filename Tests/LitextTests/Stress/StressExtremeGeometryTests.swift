//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//
//  Stress: extreme geometry. See StressSupport.swift for the quick and
//  LITEXT_STRESS=full modes. These tests are small and identical in both modes.
//
//  What Litext returns for degenerate geometry (Apple silicon, macOS 27):
//
//  - A size is valid when both dimensions are finite and not negative
//    (`CGSize.isValidLayoutSize`). Zero and `.greatestFiniteMagnitude` are valid
//    and mean "unconstrained" to both measurement and layout. NaN, negative
//    values and both infinities are invalid.
//  - An invalid container lays out nothing, without calling CoreText: no lines,
//    rects, highlight regions or attachment views, nil index lookups, and
//    drawing paints nothing. A later valid size lays the text out again.
//  - `sizeThatFits` with an invalid proposal returns `.zero`.
//  - A zero size lays out no lines. Widths 0.1 and 1 lay out one glyph per line.
//    Width 0 (with a positive height), 1e7 and `.greatestFiniteMagnitude` lay out
//    the unconstrained lines: only the sample's explicit line breaks wrap it.
//  - `.greatestFiniteMagnitude` or 1e12 heights lay the text out in full,
//    anchored to the top of a 1e8-point container, so every rect stays finite.
//  - A height too small for even the first line (a 2000-point font in a 100-point
//    proposal) measures as zero, as `CTFramesetterSuggestFrameSizeWithConstraints` does.
//  - `lineHeightMultiple` of 1e6 makes CoreText measure zero and lay out nothing.
//  - AppKit traps on a NaN view frame by itself, before Litext sees it, and
//    clamps infinite frames to 2^45 points, so view-level invalid sizes are
//    exercised through what each platform accepts plus an invalid layout size.
//

import CoreGraphics
import CoreText
import Foundation
@testable import Litext
import Testing

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

@MainActor
@Suite("Stress: extreme geometry", .tags(.stress), StressMode.enabled)
struct StressExtremeGeometryTests {
    static let dimensions: [CGFloat] = [
        0, 0.1, 1, 100, 1e7, .greatestFiniteMagnitude, .infinity, -.infinity, .nan, -50,
    ]

    private func sample() -> NSAttributedString {
        let font = PlatformFont.systemFont(ofSize: 16)
        let text = NSMutableAttributedString(
            string: "Hello world, this is Litext with words to wrap. ",
            attributes: [.font: font],
        )
        text.append(NSAttributedString(
            string: "A link here",
            attributes: [.font: font, .link: URL(string: "https://example.com")!],
        ))
        text.append(NSAttributedString(string: "\nSecond paragraph ", attributes: [.font: font]))
        text.append(TextLabel.Attachment(size: CGSize(width: 20, height: 20)).attributedString(attributes: [.font: font]))
        text.append(NSAttributedString(string: " end.", attributes: [.font: font]))
        return text
    }

    /// Every width and height combination, including NaN and infinities, lays
    /// out, draws and answers queries with finite geometry.
    @Test func `container sizes keep geometry finite`() {
        let text = sample()
        let context = makeStressContext()
        // 100 combinations: about 0.02 s on an Apple silicon Mac; invalid sizes skip CoreText.
        withinBudget("extreme container sizes", seconds: 1) {
            for width in Self.dimensions {
                for height in Self.dimensions {
                    let layout = TextLabel.Layout(attributedString: text)
                    let size = CGSize(width: width, height: height)
                    var audit = LayoutAudit()
                    audit.audit(
                        layout,
                        containerSize: size,
                        samplePoints: samplePoints(in: size, count: 16),
                        ranges: [NSRange(location: 3, length: 20), NSRange(location: text.length - 1, length: 1)],
                        context: context,
                        visibleRect: CGRect(x: 0, y: 0, width: 50, height: 50),
                    )
                    audit.record("container \(size)")
                }
            }
        }
    }

    static let invalidDimensions: [CGFloat] = [.nan, -1, -.infinity, .infinity]

    /// Every invalid container: each invalid width with a valid height, each
    /// invalid height with a valid width, and both invalid at once.
    static var invalidSizes: [CGSize] {
        invalidDimensions.flatMap { invalid in
            [
                CGSize(width: invalid, height: 100),
                CGSize(width: 200, height: invalid),
                CGSize(width: invalid, height: invalid),
                CGSize(width: invalid, height: .nan),
            ]
        }
    }

    @Test func `degenerate containers lay out as documented`() {
        let text = sample()
        func lineCount(_ size: CGSize) -> Int {
            let layout = TextLabel.Layout(attributedString: text)
            layout.containerSize = size
            return layout.visibleLineCount(in: nil)
        }
        #expect(lineCount(CGSize(width: 0, height: 0)) == 0)
        // About one glyph per line, all of them laid out.
        let glyphLines = lineCount(CGSize(width: 0.1, height: 100))
        #expect(glyphLines > 40)
        #expect(lineCount(CGSize(width: 1, height: 100)) == glyphLines)
        // Zero width is unconstrained, as in measurement: the same lines as an
        // unbounded width, not one glyph per line.
        let unconstrainedLines = lineCount(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 100))
        #expect(unconstrainedLines == 2)
        #expect(lineCount(CGSize(width: 1e7, height: 100)) == unconstrainedLines)
        #expect(lineCount(CGSize(width: 0, height: 100)) == unconstrainedLines)

        // Unbounded heights lay out everything, anchored at the top.
        let reference = TextLabel.Layout(attributedString: text)
        reference.containerSize = CGSize(width: 200, height: 300)
        let referenceRects = reference.rects(for: NSRange(location: 0, length: text.length))
            .map { reference.viewRect(fromLayoutRect: $0) }
        for height in [CGFloat.greatestFiniteMagnitude, 1e12] {
            let layout = TextLabel.Layout(attributedString: text)
            layout.containerSize = CGSize(width: 200, height: height)
            let rects = layout.rects(for: NSRange(location: 0, length: text.length))
                .map { layout.viewRect(fromLayoutRect: $0) }
            #expect(rects.count == referenceRects.count, "height \(height)")
            for (rect, expected) in zip(rects, referenceRects) {
                #expect(abs(rect.minY - expected.minY) < 0.001, "height \(height)")
            }
            // A point in the first line, in view space, hits the first line.
            let index = layout.characterIndex(at: layout.layoutPoint(fromViewPoint: CGPoint(x: 2, y: 5)))
            #expect(index == 0, "height \(height)")
        }
    }

    /// An invalid container lays out and draws nothing, and the layout recovers
    /// as soon as the container is valid again.
    @Test func `invalid containers lay out and draw nothing`() {
        let text = sample()
        let valid = CGSize(width: 200, height: 100)
        let reference = TextLabel.Layout(attributedString: text)
        reference.containerSize = valid
        reference.updateHighlightRegions()
        let referenceRects = reference.rects(for: NSRange(location: 0, length: text.length))
        #expect(inkedPixels { reference.draw(in: $0, visibleRect: nil) } > 0)

        withinBudget("invalid container transitions", seconds: 1) {
            for invalid in Self.invalidSizes {
                // Fresh, and after a valid layout: valid -> invalid -> valid -> invalid.
                let layout = TextLabel.Layout(attributedString: text)
                for size in [invalid, valid, invalid, valid, invalid] {
                    layout.containerSize = size
                    layout.updateHighlightRegions()
                    let drawn = inkedPixels { layout.draw(in: $0, visibleRect: nil) }
                    let drawnInRect = inkedPixels { layout.draw(in: $0, visibleRect: CGRect(origin: .zero, size: valid)) }
                    if size.isValidLayoutSize {
                        #expect(layout.rects(for: NSRange(location: 0, length: text.length)) == referenceRects, "\(size)")
                        #expect(layout.highlightRegions.count == reference.highlightRegions.count, "\(size)")
                        #expect(drawn > 0, "\(size)")
                    } else {
                        #expect(layout.visibleLineCount(in: nil) == 0, "\(invalid)")
                        #expect(layout.rects(for: NSRange(location: 0, length: text.length)).isEmpty, "\(invalid)")
                        #expect(layout.highlightRegions.isEmpty, "\(invalid)")
                        #expect(layout.layoutRuns(matching: .font).isEmpty, "\(invalid)")
                        #expect(layout.textIndex(at: CGPoint(x: 5, y: 5)) == nil, "\(invalid)")
                        #expect(layout.nearestTextIndex(at: CGPoint(x: 5, y: 5)) == nil, "\(invalid)")
                        #expect(drawn == 0, "\(invalid): drew \(drawn) pixels")
                        #expect(drawnInRect == 0, "\(invalid): drew \(drawnInRect) pixels")
                        #expect(layout.sizeThatFits(invalid) == .zero, "\(invalid)")
                    }
                }
            }
        }
    }

    /// A maximum line height below the font's gives lines a negative descent, and
    /// CoreText then measures less height than its frame needs for the last line.
    /// The fuzzer found the last line dropped from right-to-left, centred and
    /// re-measured text.
    @Test func `line height caps never drop the last line`() {
        let cases: [(String, NSTextAlignment, CGFloat, CGFloat)] = [
            ("Ελληνικά κείμενο εδώ", .left, 50, 69),
            ("\u{202E}한국어 텍스트", .left, 19, 4.5),
            ("centred text that wraps", .center, 0, 10),
            ("שלום עולם טקסט", .natural, 30, 12),
        ]
        for (string, alignment, minimum, maximum) in cases {
            let style = NSMutableParagraphStyle()
            style.alignment = alignment
            style.minimumLineHeight = minimum
            style.maximumLineHeight = maximum
            let text = NSMutableAttributedString(
                string: string,
                attributes: [.font: PlatformFont.systemFont(ofSize: 40), .paragraphStyle: style],
            )
            text.addAttribute(.stressCoverage, value: true, range: NSRange(location: 0, length: text.length))
            for width: CGFloat in [1, 60, 200, 100_000] {
                for height: CGFloat in [0, 100] {
                    let layout = TextLabel.Layout(attributedString: text)
                    // Measuring the natural size first answers later widths from the cache.
                    _ = layout.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
                    layout.containerSize = CGSize(width: width, height: height)
                    var audit = LayoutAudit()
                    audit.checkLinesCoverString(layout, key: .stressCoverage)
                    audit.record("\(string) at \(width) x \(height)")
                }
            }
        }
    }

    @Test func `size that fits rejects invalid proposals`() {
        let layout = TextLabel.Layout(attributedString: sample())
        let natural = layout.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        #expect(natural.isFiniteSize && natural.width > 0)
        // Zero still means unconstrained.
        #expect(layout.sizeThatFits(.zero) == natural)
        #expect(layout.sizeThatFits(CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)) == natural)
        for proposal in Self.invalidSizes {
            #expect(layout.sizeThatFits(proposal) == .zero, "sizeThatFits(\(proposal))")
        }
        // Measuring an invalid proposal leaves later valid ones intact.
        let wrapped = layout.sizeThatFits(CGSize(width: 50, height: CGFloat.greatestFiniteMagnitude))
        #expect(wrapped.isFiniteSize && wrapped.width <= 50 && wrapped.height > natural.height)
    }

    @Test func `extreme font sizes`() {
        let context = makeStressContext()
        for pointSize: CGFloat in [0.01, 0.5, 2000, 5000] {
            let text = NSAttributedString(
                string: "Hello wrapping world",
                attributes: [.font: PlatformFont.systemFont(ofSize: pointSize)],
            )
            for size in [CGSize(width: 300, height: 100), CGSize(width: 300, height: 1e6)] {
                let layout = TextLabel.Layout(attributedString: text)
                var audit = LayoutAudit()
                audit.audit(
                    layout,
                    containerSize: size,
                    samplePoints: samplePoints(in: size, count: 16),
                    context: context,
                    visibleRect: CGRect(x: 0, y: 0, width: 300, height: 100),
                )
                audit.record("font \(pointSize) in \(size)")
                // Every character is laid out even when the container is too short.
                #expect(!layout.rects(for: NSRange(location: text.length - 1, length: 1)).isEmpty)
            }
        }
        // A line taller than the proposal measures as zero, as CoreText does.
        let huge = TextLabel.Layout(attributedString: NSAttributedString(
            string: "Hi",
            attributes: [.font: PlatformFont.systemFont(ofSize: 2000)],
        ))
        #expect(huge.sizeThatFits(CGSize(width: 300, height: 100)) == .zero)
        #expect(huge.sizeThatFits(CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)).height > 2000)
    }

    @Test func `extreme paragraph styles`() {
        let styles: [(String, (NSMutableParagraphStyle) -> Void)] = [
            ("head indent +1e6", { $0.headIndent = 1e6
                $0.firstLineHeadIndent = 1e6
            }),
            ("head indent -1e6", { $0.headIndent = -1e6
                $0.firstLineHeadIndent = -1e6
            }),
            ("tail indent -1e6", { $0.tailIndent = -1e6 }),
            ("tail indent +1e6", { $0.tailIndent = 1e6 }),
            ("line spacing 1e6", { $0.lineSpacing = 1e6 }),
            ("paragraph spacing 1e6", { $0.paragraphSpacing = 1e6
                $0.paragraphSpacingBefore = 1e6
            }),
            ("minimum line height above maximum", { $0.minimumLineHeight = 100
                $0.maximumLineHeight = 10
            }),
            ("maximum line height 0.01", { $0.maximumLineHeight = 0.01 }),
            ("line height multiple 1e6", { $0.lineHeightMultiple = 1e6 }),
            ("line height multiple 1e-6", { $0.lineHeightMultiple = 1e-6 }),
            ("centered, negative indents", { $0.alignment = .center
                $0.headIndent = -500
                $0.tailIndent = -500
            }),
            ("justified right to left", { $0.alignment = .justified
                $0.baseWritingDirection = .rightToLeft
            }),
        ]
        let context = makeStressContext()
        // About 15 ms on an Apple silicon Mac.
        withinBudget("extreme paragraph styles", seconds: 1) {
            for (name, configure) in styles {
                let style = NSMutableParagraphStyle()
                configure(style)
                let text = NSAttributedString(
                    string: "Hello world wrap a lot of words here\nSecond paragraph\nThird",
                    attributes: [.font: PlatformFont.systemFont(ofSize: 16), .paragraphStyle: style],
                )
                for size in [CGSize(width: 300, height: 100), CGSize(width: 0.5, height: 100), CGSize(width: 300, height: 1e9)] {
                    let layout = TextLabel.Layout(attributedString: text)
                    var audit = LayoutAudit()
                    audit.audit(
                        layout,
                        containerSize: size,
                        samplePoints: samplePoints(in: size, count: 16),
                        ranges: [NSRange(location: 5, length: 30)],
                        context: context,
                        visibleRect: CGRect(x: 0, y: 0, width: 300, height: 100),
                    )
                    audit.record("\(name) in \(size)")
                }
            }
        }

        // Line spacing of 1e6 needs about 2e6 points; everything is still laid out.
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 1e6
        let text = NSAttributedString(
            string: "First\nSecond\nThird",
            attributes: [.font: PlatformFont.systemFont(ofSize: 16), .paragraphStyle: style],
        )
        let layout = TextLabel.Layout(attributedString: text)
        layout.containerSize = CGSize(width: 300, height: 100)
        #expect(layout.visibleLineCount(in: nil) == 3)
    }

    #if !os(watchOS)
        @Test func `view survives extreme frames`() throws {
            var frames: [CGRect] = [
                .zero,
                CGRect(x: 0, y: 0, width: -100, height: -50),
                CGRect(x: -1e6, y: -1e6, width: 0.1, height: 0.1),
                CGRect(x: 0, y: 0, width: 1e7, height: 1e7),
                CGRect(x: 0, y: 0, width: 1, height: 1e7),
                CGRect(x: 0, y: 0, width: 100, height: CGFloat.greatestFiniteMagnitude),
            ]
            #if canImport(AppKit) && !targetEnvironment(macCatalyst)
                // AppKit clamps an infinite frame to 2^45 points.
                frames.append(CGRect(x: 0, y: 0, width: CGFloat.infinity, height: CGFloat.infinity))
            #endif
            let text = sample()
            for frame in frames {
                let label = TextLabelView(attributedText: text)
                label.isSelectable = true
                label.preferredMaxLayoutWidth = try [0, -5, 1e9, 0.5][#require(frames.firstIndex(of: frame)) % 4]
                label.frame = frame
                forceLayout(label)
                label.selectAll()
                if let path = label.selectionLayer?.path {
                    #expect(path.boundingBoxOfPath.isFiniteRect, "frame \(frame)")
                }
                let intrinsic = label.intrinsicContentSize
                #expect(intrinsic.isFiniteSize, "frame \(frame): intrinsic size \(intrinsic)")
                for rect in label.textLayout.rects(for: NSRange(location: 0, length: text.length)) {
                    #expect(label.viewRect(fromLayoutRect: rect).isFiniteRect, "frame \(frame)")
                }
                for point in samplePoints(in: label.bounds.size, count: 9) {
                    _ = label.hitTarget(at: point)
                    if let index = label.nearestTextIndexAtPoint(point) {
                        #expect(index >= 0 && index <= text.length)
                    }
                }
                drawView(label, rect: label.bounds)
                label.clearSelection()
                #expect(label.selectionRange == nil)
            }
        }

        /// Invalid geometry on a view: whatever size each platform lets through,
        /// a label draws text only while its bounds are valid, drops attachment
        /// views while they are not, and recovers afterwards.
        @Test func `view draws nothing while its size is invalid`() {
            let text = NSMutableAttributedString(attributedString: sample())
            let attachment = TextLabel.Attachment(size: CGSize(width: 20, height: 20), view: PlatformView(frame: .zero))
            text.append(attachment.attributedString(attributes: [.font: PlatformFont.systemFont(ofSize: 16)]))
            let label = TextLabelView(attributedText: text)
            label.isSelectable = true
            let valid = CGRect(x: 0, y: 0, width: 200, height: 100)

            func check(_ step: String) {
                forceLayout(label)
                label.selectAll()
                let drawn = inkedPixels(viewSize: valid.size) { context in
                    drawView(label, rect: label.bounds, into: context)
                }
                let intrinsic = label.intrinsicContentSize
                #expect(intrinsic.isFiniteSize, "\(step): intrinsic \(intrinsic)")
                if label.bounds.size.isValidLayoutSize {
                    #expect(drawn > 0, "\(step): bounds \(label.bounds) drew nothing")
                    #expect(attachment.view?.superview === label, "\(step)")
                } else {
                    #expect(drawn == 0, "\(step): bounds \(label.bounds) drew \(drawn) pixels")
                    #expect(label.attachmentViews.isEmpty, "\(step)")
                    #expect(label.selectionLayer == nil, "\(step)")
                }
                expectConsistent(label, step)
            }

            label.frame = valid
            check("valid frame")
            // AppKit clamps negative sizes to zero and infinite ones to 2^45 points,
            // so its bounds stay valid; UIKit may let a negative size through.
            var sizes: [CGSize] = [CGSize(width: -1, height: 100), CGSize(width: 200, height: -1)]
            #if canImport(AppKit) && !targetEnvironment(macCatalyst)
                sizes += [CGSize(width: -CGFloat.infinity, height: 100), CGSize(width: 200, height: CGFloat.infinity)]
            #endif
            for size in sizes {
                #if canImport(AppKit) && !targetEnvironment(macCatalyst)
                    label.setFrameSize(size)
                #else
                    label.bounds.size = size
                #endif
                check("size \(size)")
                label.frame = valid
                check("valid after \(size)")
            }

            // A text layout whose size is invalid while the bounds are valid, as on a
            // platform that lets a NaN size through: nothing stale is drawn.
            for size in Self.invalidSizes {
                label.textLayout.containerSize = size
                let drawn = inkedPixels(viewSize: valid.size) { context in
                    drawView(label, rect: label.bounds, into: context)
                }
                #expect(drawn == 0, "layout size \(size) drew \(drawn) pixels")
                label.invalidateTextLayout()
                check("relaid out after layout size \(size)")
            }
            #expect(label.preferredMaxLayoutWidth == 0)
            for width in Self.invalidDimensions {
                label.preferredMaxLayoutWidth = width
                #expect(label.intrinsicContentSize.isFiniteSize, "preferredMaxLayoutWidth \(width)")
                #expect(label.intrinsicContentSize.width > 0, "preferredMaxLayoutWidth \(width)")
            }
        }

        @Test func `preferred max layout width extremes`() {
            let label = TextLabelView(attributedText: sample())
            for width: CGFloat in [0, -1, 0.1, 1, 1e7, .greatestFiniteMagnitude, .infinity, .nan] {
                label.preferredMaxLayoutWidth = width
                let intrinsic = label.intrinsicContentSize
                #expect(intrinsic.isFiniteSize, "preferredMaxLayoutWidth \(width): \(intrinsic)")
            }
        }
    #endif
}

/// Draws with `body` into a transparent bitmap flipped to a top-left origin,
/// as a view's context is, and counts the pixels it inked.
@MainActor
func inkedPixels(viewSize: CGSize = CGSize(width: 200, height: 100), _ body: (CGContext) -> Void) -> Int {
    let width = Int(viewSize.width)
    let height = Int(viewSize.height)
    let context = makeStressContext(width: width, height: height)
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    body(context)
    guard let data = context.data else { return 0 }
    let bytes = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
    var count = 0
    for row in 0 ..< height {
        for column in 0 ..< width where bytes[row * context.bytesPerRow + column * 4] != 0 {
            count += 1
        }
    }
    return count
}

#if !os(watchOS)
    /// Draws `view` into `context` (an offscreen bitmap by default) through the
    /// platform's drawing context.
    @MainActor
    func drawView(_ view: TextLabelView, rect: CGRect, into context: CGContext = makeStressContext(width: 32, height: 32)) {
        #if canImport(UIKit)
            UIGraphicsPushContext(context)
            view.draw(rect)
            UIGraphicsPopContext()
        #elseif canImport(AppKit)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            view.draw(rect)
            NSGraphicsContext.restoreGraphicsState()
        #endif
    }
#endif
