//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreGraphics
import CoreText
import Foundation
import QuartzCore

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

private struct RegionKey: Hashable {
    let kind: TextLabel.HighlightRegion.Kind
    let location: Int
}

private struct LineMetrics {
    var ascent: CGFloat
    var descent: CGFloat
    var leading: CGFloat
    var width: CGFloat
    /// The width of the whitespace at the line's logical end, which CoreText lets
    /// hang past the edge of the container rather than wrapping it.
    var trailingWhitespaceWidth: CGFloat
    /// Where the typographic box starts relative to the line origin: zero, or
    /// minus the hanging whitespace on a right-to-left line, whose trailing
    /// whitespace sits to the left of the origin.
    var minX: CGFloat

    /// The line's box in CoreText layout space (lower-left origin).
    ///
    /// CoreText places the first baseline `ascent` below the top of the path and
    /// spaces each following line by `descent + leading` below the previous one,
    /// so a line's leading belongs below its descent. Every consumer — selection
    /// rects, hit testing, draw culling — shares this box so they agree.
    ///
    /// The last line has no line below it, and the measured size stops at its
    /// descent, so its `leading` is stored as zero to keep its box inside the text.
    func rect(at origin: CGPoint, includingLeading: Bool = true) -> CGRect {
        let trailingGap = includingLeading ? leading : 0
        return CGRect(
            x: origin.x + minX,
            y: origin.y - descent - trailingGap,
            width: width,
            height: ascent + descent + trailingGap,
        )
    }

    /// `rect(at:includingLeading:)` with whitespace hanging past the container cut
    /// off at its edge, so selection and highlight rects stay inside the view.
    /// Glyphs that cannot fit — a single cluster wider than the container — are
    /// never cut.
    func clippedRect(at origin: CGPoint, containerWidth: CGFloat, includingLeading: Bool = true) -> CGRect {
        let box = rect(at: origin, includingLeading: includingLeading)
        let visibleMaxX = origin.x + width - trailingWhitespaceWidth
        let minX = max(box.minX, min(0, origin.x))
        let maxX = min(box.maxX, max(containerWidth, visibleMaxX))
        return CGRect(x: minX, y: box.minY, width: max(maxX - minX, 0), height: box.height)
    }
}

private extension CGRect {
    /// This rect narrowed to the horizontal extent of `box`; empty, at the nearer
    /// edge, when it lies entirely outside.
    func clippedHorizontally(to box: CGRect) -> CGRect {
        let clippedMinX = Swift.min(Swift.max(minX, box.minX), box.maxX)
        let clippedMaxX = Swift.max(Swift.min(maxX, box.maxX), clippedMinX)
        return CGRect(x: clippedMinX, y: minY, width: clippedMaxX - clippedMinX, height: height)
    }
}

/// How a line's characters are measured, by `rects(for:)` and
/// `TextLabel.Layout.characterIndex(at:)` alike.
private enum SelectionGeometry {
    /// One span between two caret offsets: the line reads left to right in
    /// logical order. Caret offsets split ligatures between their characters.
    case caretOffsets
    /// Each character between its own caret edges: a bidirectional line.
    case caretEdges
    /// Each cluster by the advance of its glyphs: a justified line, whose caret
    /// offsets CoreText reports without the space justification adds between
    /// glyphs.
    case glyphs
}

private struct LineHit {
    var line: CTLine
    var origin: CGPoint
}

private struct FrameFill {
    var lines: [CTLine]
    var lineOrigins: [CGPoint]
    var lineMetrics: [LineMetrics]
    var pathSize: CGSize
    var measuredSize: CGSize
    /// The widest line including its trailing whitespace: a path at least this
    /// wide breaks none of these lines.
    var unbrokenWidth: CGFloat
    var isComplete: Bool
}

public extension TextLabel {
    /// One laid-out glyph run, as `TextLabel.Layout.layoutRuns(matching:)` reports it.
    @MainActor
    struct LayoutRun {
        public let lineIndex: Int
        public let attributes: [NSAttributedString.Key: Any]
        public let stringRange: NSRange
        /// The run's typographic box: its advance width by the ascent and descent
        /// of its font (or of its attachment's run delegate).
        public let rect: CGRect
        /// The line's typographic box, from the bottom of its descent to the top of
        /// its ascent. The line's leading, which sits below the descent, is excluded,
        /// and trailing whitespace hanging past the container is cut off at its edge.
        public let lineRect: CGRect
    }

    /// One laid-out line, as `TextLabel.Layout.layoutLines` reports it.
    ///
    /// Geometry is in CoreText layout space (lower-left origin). Convert it with
    /// `viewRect(fromLayoutRect:)` before comparing it with view coordinates.
    @MainActor
    struct LayoutLine {
        /// The line's position among the laid-out lines, starting at zero.
        public let index: Int
        /// The characters the line shows, including any trailing whitespace and
        /// line break it ends with.
        public let stringRange: NSRange
        /// The line's typographic box, from the bottom of its descent to the top of
        /// its ascent, matching `LayoutRun.lineRect`: the leading below the descent
        /// is excluded, and trailing whitespace hanging past the container is cut
        /// off at its edge.
        public let rect: CGRect
        /// Where the line's baseline starts, the point CoreText draws the line from.
        public let baselineOrigin: CGPoint
    }
}

extension TextLabel {
    /// Measures, lays out and draws an attributed string with CoreText.
    ///
    /// `TextLabelView` and the SwiftUI `TextLabel` build one for each string they
    /// show; a layout can also be used on its own to measure or render text into a
    /// `CGContext`. Geometry it returns is in CoreText layout space (lower-left
    /// origin, flipped against `containerSize.height`); convert it with
    /// `viewRect(fromLayoutRect:)`.
    ///
    /// Subclasses that override a method should call `super`: the base
    /// implementations keep the measurement caches, the laid-out lines and the
    /// highlight regions in step. Typesetting is the expensive part, so it runs only
    /// when `containerSize` changes or `invalidateLayout()` is called; queries read
    /// the stored lines.
    ///
    /// Lookups by position (hit testing, draw culling) find their line by binary
    /// search, so they cost about the same on a long document as on a short one. A
    /// layout whose line boxes overlap out of order, which mixed font sizes under a
    /// small `lineHeightMultiple` can produce, falls back to scanning the lines and
    /// returns the same answers.
    @MainActor
    open class Layout: NSObject {
        /// An immutable snapshot of the string the layout was created with.
        open private(set) var attributedString: NSAttributedString

        /// The link and attachment regions of the laid-out text, in no particular
        /// order. Filled by `updateHighlightRegions()`; empty until it runs.
        ///
        /// Reading it is free: the array is built once per layout pass.
        open var highlightRegions: [TextLabel.HighlightRegion] {
            _highlightRegionsArray
        }

        /// The size the text is laid out in; zero or `.greatestFiniteMagnitude`
        /// leaves a dimension unconstrained. Text is anchored to the top.
        ///
        /// - Important: Performance-sensitive. Assigning a different size
        ///   typesets the text again, unless a `sizeThatFits(_:)` call at the same
        ///   width already did. Assigning an equal size does nothing.
        open var containerSize: CGSize {
            didSet {
                guard containerSize != oldValue else { return }
                generateLayout()
            }
        }

        private var framesetter: CTFramesetter
        private var lines: [CTLine]?
        private var lineOrigins: [CGPoint]?
        private var lineMetrics: [LineMetrics]?
        /// Whether the line boxes descend in order: every box's bottom, middle and
        /// top lie at or below the previous box's. Line lookups binary-search
        /// when they do. Mixed font sizes squeezed by a small `lineHeightMultiple`
        /// can overlap boxes out of order, and those layouts keep the linear scan,
        /// so a lookup returns the same line either way.
        private(set) var lineBoxesAreOrdered = true
        private var _highlightRegions: [RegionKey: TextLabel.HighlightRegion]
        private var _highlightRegionsArray: [TextLabel.HighlightRegion] = []
        private var suggestedSizeCache: (input: CGSize, output: CGSize)?
        private var suggestedSizeHistory: [(input: CGSize, output: CGSize)] = []
        private var naturalSizeCache: CGSize?
        /// The narrowest width that keeps the natural line breaks. The measured width
        /// leaves out trailing whitespace, and CoreText wraps whitespace it does not
        /// let hang, such as a tab, so a width between the two can still break a line.
        private var naturalUnbrokenWidth: CGFloat?
        private var measurementFill: FrameFill?

        /// Changes whenever the laid-out lines change. Values are unique across
        /// layouts, so a stamp taken from one layout never matches another.
        private(set) var generation: Int
        private static var lastGeneration = 0

        private lazy var hasLineDrawingActions: Bool = attributedStringHasLineDrawingActions()
        private lazy var hasHighlightAttributes: Bool = attributedStringHasHighlightAttributes()
        private lazy var usesFrameDerivedMeasurement: Bool = frameDerivedMeasurementIsSafe()

        /// Hosts that probe several candidate widths — self-sizing cells, multi-pass
        /// constraint solving, split-view drags — alternate between a few sizes, so a
        /// single-entry cache misses on every query and re-runs the framesetter.
        private static let suggestedSizeHistoryLimit = 4

        /// CoreText positions lines from the top of the layout path, so an
        /// unconstrained measurement only needs a path comfortably taller than any
        /// real container while keeping line origins in a precise double range.
        private static let maxLayoutDimension: CGFloat = 1_000_000

        /// The tallest path the final layout grows to. Text taller than
        /// `maxLayoutDimension` (about 50,000 lines of body text) is common in long
        /// documents and would lose every line past that height, so the final
        /// layout allows far more while staying in a precise double range.
        private static let maxLayoutHeight: CGFloat = 100_000_000

        /// Attributes that produce highlight regions, in the order a run's regions
        /// are added: a run carrying both a link and an attachment yields the link
        /// region first.
        private static let highlightAttributes: [(
            key: NSAttributedString.Key,
            runKey: CFString,
            kind: TextLabel.HighlightRegion.Kind,
        )] = [
            (.link, NSAttributedString.Key.link.rawValue as CFString, .link),
            (
                .litextAttachment,
                NSAttributedString.Key.litextAttachment.rawValue as CFString,
                .attachment,
            ),
        ]
        private static let highlightRunKeys = highlightAttributes.map(\.runKey)
        private static let lineDrawingRunKey = NSAttributedString.Key.litextLineDrawingAction.rawValue as CFString

        public init(attributedString: NSAttributedString) {
            // The framesetter works from its own snapshot of the string, and CTRun
            // ranges index that snapshot. Keeping the caller's (possibly mutable)
            // object would let later edits desynchronize attribute lookups and the
            // lazily computed flags from the laid-out runs. Copying an immutable
            // string only retains it.
            let snapshot = attributedString.copy() as! NSAttributedString
            self.attributedString = snapshot
            containerSize = .zero
            Self.syncAttachmentRunMetrics(in: snapshot)
            framesetter = CTFramesetterCreateWithAttributedString(snapshot)
            _highlightRegions = [:]
            generation = Self.makeGeneration()
            super.init()
        }

        /// Regenerates CoreText lines for the current `containerSize`.
        ///
        /// `containerSize` already triggers layout regeneration when assigned. Call this only after
        /// external state referenced by run delegates or custom drawing callbacks changes.
        ///
        /// - Important: Performance-sensitive. This drops every measurement cache,
        ///   rebuilds the framesetter and typesets the whole string again.
        open func invalidateLayout() {
            suggestedSizeCache = nil
            suggestedSizeHistory.removeAll()
            naturalSizeCache = nil
            naturalUnbrokenWidth = nil
            measurementFill = nil
            // CoreText caches the typographic bounds it obtained from a run delegate inside
            // the framesetter, and never asks again for the lifetime of that framesetter.
            // Rebuilding lines from the existing one would pick up an attachment's new width
            // while keeping its old line height, so the framesetter is rebuilt too — this is
            // the only way a changed run delegate is observed.
            Self.syncAttachmentRunMetrics(in: attributedString)
            framesetter = CTFramesetterCreateWithAttributedString(attributedString)
            generateLayout()
        }

        /// Pushes each attachment's current `size` into the metrics its run delegate
        /// reports, so a subclass that computes `size` is measured with today's value.
        private static func syncAttachmentRunMetrics(in string: NSAttributedString) {
            guard string.length > 0 else { return }
            string.enumerateAttribute(
                .litextAttachment,
                in: NSRange(location: 0, length: string.length),
                options: [],
            ) { value, _, _ in
                (value as? TextLabel.Attachment)?.syncRunMetrics()
            }
        }

        /// The size the text needs within `size`. Zero or `.greatestFiniteMagnitude`
        /// leaves a dimension unconstrained; a proposal with a NaN, negative or
        /// infinite dimension is invalid and measures as `.zero`.
        ///
        /// - Important: Performance-sensitive. The last few proposals are cached,
        ///   and a proposal the unconstrained size already fits is answered without
        ///   typesetting; any other proposal runs CoreText over the whole string.
        ///   Hosts that probe many widths should reuse a few rather than vary them
        ///   continuously.
        open func sizeThatFits(_ size: CGSize) -> CGSize {
            guard size.isValidLayoutSize else { return .zero }
            if let suggestedSizeCache, suggestedSizeCache.input == size {
                return suggestedSizeCache.output
            }
            if let remembered = suggestedSizeHistory.first(where: { $0.input == size }) {
                suggestedSizeCache = remembered
                return remembered.output
            }

            // Fast path: once the unconstrained (natural) size is known, any constraint
            // that already fits it cannot change line breaking, so the framesetter pass
            // can be skipped for those queries.
            if let naturalSizeCache,
               (naturalUnbrokenWidth ?? naturalSizeCache.width) <= size.width,
               naturalSizeCache.height <= size.height
            {
                rememberSuggestedSize(input: size, output: naturalSizeCache)
                return naturalSizeCache
            }

            var measuredFill: FrameFill?
            if usesFrameDerivedMeasurement {
                // Measuring through an actual frame lets `generateLayout()` adopt the
                // laid-out lines directly instead of running a second framesetter pass.
                // The framesetter treats non-positive dimensions as unconstrained;
                // mirror that before building the frame.
                let constraint = CGSize(
                    width: size.width > 0 ? size.width : Self.maxLayoutDimension,
                    height: size.height > 0 ? size.height : Self.maxLayoutDimension,
                )
                let fill = makeFrameFill(constraint: constraint, clampsToMaxLayoutDimension: true)

                // Content that hits the maxLayoutDimension cap (dropped lines, or a
                // line soft-wrapped by the clamped path width — such a wrap always
                // leaves a line wider than half the path) cannot be trusted and is
                // measured by the framesetter below instead.
                let widthWasClamped = size.width <= 0 || size.width > Self.maxLayoutDimension
                if fill.isComplete,
                   !widthWasClamped || fill.measuredSize.width < Self.maxLayoutDimension / 2
                {
                    measuredFill = fill
                }
            }

            let suggestedSize: CGSize
            if let measuredFill {
                measurementFill = measuredFill
                suggestedSize = measuredFill.measuredSize
            } else {
                suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
                    framesetter,
                    CFRange(location: 0, length: 0),
                    nil,
                    size,
                    nil,
                )
            }
            if size.width == CGFloat.greatestFiniteMagnitude, size.height == CGFloat.greatestFiniteMagnitude {
                naturalSizeCache = suggestedSize
                naturalUnbrokenWidth = measuredFill?.unbrokenWidth
            }
            rememberSuggestedSize(input: size, output: suggestedSize)
            return suggestedSize
        }

        /// Records a measurement in both the most-recent slot and the small history
        /// consulted when a host alternates between candidate widths.
        private func rememberSuggestedSize(input: CGSize, output: CGSize) {
            suggestedSizeCache = (input: input, output: output)
            suggestedSizeHistory.removeAll { $0.input == input }
            suggestedSizeHistory.insert((input: input, output: output), at: 0)
            if suggestedSizeHistory.count > Self.suggestedSizeHistoryLimit {
                suggestedSizeHistory.removeLast()
            }
        }

        /// Draws every laid-out line into `context`, which uses a top-left origin
        /// like a view's drawing context. Same as `draw(in:visibleRect:)` with `nil`.
        open func draw(in context: CGContext) {
            draw(in: context, visibleRect: nil)
        }

        /// Draws the laid-out text, restricted to the lines intersecting `visibleRect`.
        ///
        /// The rect uses a top-left origin in the same space as `containerSize`, matching the
        /// dirty rect handed to a view's `draw(_:)`. Passing `nil` draws every line.
        ///
        /// - Important: Performance-sensitive: this runs on every display pass.
        ///   Pass the dirty rect so long text draws only the lines in view, found
        ///   by binary search.
        open func draw(in context: CGContext, visibleRect: CGRect?) {
            guard containerSize.isValidLayoutSize,
                  let lines,
                  let lineOrigins,
                  !lines.isEmpty
            else { return }

            let textLineIndices = lineIndices(intersecting: visibleRect)
            guard !textLineIndices.isEmpty else { return }

            context.saveGState()

            context.setAllowsAntialiasing(true)
            context.textMatrix = .identity

            context.translateBy(x: 0, y: anchorHeight)
            context.scaleBy(x: 1, y: -1)

            for index in textLineIndices {
                context.textPosition = lineOrigins[index]
                draw(line: lines[index], at: index, in: context)
            }
            processLineDrawingActions(in: context, lineIndices: textLineIndices)

            context.restoreGState()
        }

        /// Draws one laid-out line at the text position already set on `context`.
        ///
        /// Called by `draw(in:visibleRect:)` for every visible line, with the context
        /// flipped into CoreText's coordinate space. Override to draw a line's glyph
        /// runs yourself — with per-run alpha, say — instead of `CTLineDraw`.
        ///
        /// - Important: Performance-sensitive: this runs for every visible line on
        ///   every display pass. Avoid allocating or measuring text here.
        open func draw(line: CTLine, at _: Int, in context: CGContext) {
            CTLineDraw(line, context)
        }

        /// The number of laid-out lines intersecting `rect`; `nil` counts every line.
        /// `rect` uses a top-left origin, like `draw(in:visibleRect:)`.
        open func visibleLineCount(in rect: CGRect?) -> Int {
            lineIndices(intersecting: rect).count
        }

        /// Returns laid-out glyph runs that carry `key`.
        ///
        /// Rects are in the same CoreText layout space returned by `rects(for:)`:
        /// lower-left origin, before a `TextLabelView` converts them to view space.
        ///
        /// - Important: Performance-sensitive. Each call walks every glyph run of
        ///   every line and builds a new array; cache the result for the current
        ///   layout instead of calling it per frame or per touch.
        open func layoutRuns(matching key: NSAttributedString.Key) -> [TextLabel.LayoutRun] {
            guard let lines, let lineMetrics else { return [] }

            var result = [TextLabel.LayoutRun]()
            enumerateRuns(
                inLines: 0 ..< lines.count,
                carrying: [key.rawValue as CFString],
            ) { lineIndex, _, lineOrigin, glyphRun in
                let attributes = CTRunGetAttributes(glyphRun) as? [NSAttributedString.Key: Any] ?? [:]
                result.append(TextLabel.LayoutRun(
                    lineIndex: lineIndex,
                    attributes: attributes,
                    stringRange: NSRange(CTRunGetStringRange(glyphRun)),
                    rect: runBoundingRect(glyphRun, lineOrigin: lineOrigin),
                    lineRect: lineMetrics[lineIndex].clippedRect(
                        at: lineOrigin,
                        containerWidth: containerSize.width,
                        includingLeading: false,
                    ),
                ))
            }
            return result
        }

        /// The laid-out lines, top to bottom; empty before `containerSize` is set or
        /// when there is no text.
        ///
        /// Use it to count lines, find where a line breaks, or align with the first
        /// or last baseline. Geometry is in layout space.
        ///
        /// - Important: Performance-sensitive. Each read builds a new array with one
        ///   entry per line, without typesetting; read it once per layout rather
        ///   than per frame on very long text.
        open var layoutLines: [TextLabel.LayoutLine] {
            guard let lines, let lineOrigins, let lineMetrics else { return [] }
            return lines.indices.map { index in
                TextLabel.LayoutLine(
                    index: index,
                    stringRange: NSRange(CTLineGetStringRange(lines[index])),
                    rect: lineMetrics[index].clippedRect(
                        at: lineOrigins[index],
                        containerWidth: containerSize.width,
                        includingLeading: false,
                    ),
                    baselineOrigin: lineOrigins[index],
                )
            }
        }

        private func processLineDrawingActions(in context: CGContext, lineIndices: Range<Int>) {
            guard hasLineDrawingActions else { return }

            // An action is line-scoped, but CoreText splits a line into several runs
            // wherever attributes or fonts change. Each action runs once per line.
            var invokedLineIndex = -1
            var invokedActions: [ObjectIdentifier] = []
            enumerateRuns(
                inLines: lineIndices,
                carrying: [Self.lineDrawingRunKey],
            ) { lineIndex, line, lineOrigin, glyphRun in
                guard let action = Self.runAttributeValue(glyphRun, Self.lineDrawingRunKey)
                    as? TextLabel.LineDrawingAction
                else { return }
                if lineIndex != invokedLineIndex {
                    invokedLineIndex = lineIndex
                    invokedActions.removeAll(keepingCapacity: true)
                }
                let actionID = ObjectIdentifier(action)
                guard !invokedActions.contains(actionID) else { return }
                invokedActions.append(actionID)

                context.saveGState()
                action.action(context, line, lineOrigin)
                context.restoreGState()
            }
        }

        /// Calls `body` for every glyph run in `lineIndices` that carries at least
        /// one of `keys`, in line order and then in the line's run order.
        ///
        /// Runs are pre-filtered through `runAttributeValue`, so attribute
        /// dictionaries are only bridged into Swift for runs the caller wants.
        private func enumerateRuns(
            inLines lineIndices: Range<Int>,
            carrying keys: [CFString],
            _ body: (_ lineIndex: Int, _ line: CTLine, _ lineOrigin: CGPoint, _ run: CTRun) -> Void,
        ) {
            guard let lines, let lineOrigins else { return }

            for lineIndex in lineIndices {
                let line = lines[lineIndex]
                let glyphRuns = CTLineGetGlyphRuns(line) as NSArray
                for runIndex in 0 ..< glyphRuns.count {
                    let glyphRun = glyphRuns[runIndex] as! CTRun
                    guard keys.contains(where: { Self.runAttributeValue(glyphRun, $0) != nil }) else { continue }
                    body(lineIndex, line, lineOrigins[lineIndex], glyphRun)
                }
            }
        }

        /// Rebuilds `highlightRegions` from the laid-out lines. `TextLabelView` calls
        /// it after each layout pass that changed the lines; call it yourself after
        /// setting `containerSize` on a layout you use on its own.
        ///
        /// - Important: Performance-sensitive. Text with links or attachments is
        ///   walked run by run; text with neither returns at once.
        open func updateHighlightRegions() {
            _highlightRegions.removeAll()
            // Extraction walks every glyph run of every line. Text carrying neither
            // links nor attachments can never produce a region, so the walk is skipped
            // rather than repeated on each layout pass.
            guard hasHighlightAttributes else {
                _highlightRegionsArray = []
                return
            }
            extractHighlightRegions()
            _highlightRegionsArray = Array(_highlightRegions.values)
        }

        /// The rects covering `range`, in CoreText layout space (lower-left origin).
        /// Use `viewRect(fromLayoutRect:)` to convert them to view space.
        ///
        /// A line gives one rect for the part of `range` it shows, or several on a
        /// bidirectional line. Lines outside `range` are skipped by a binary search,
        /// so the cost grows with the lines `range` covers, not the whole text.
        open func rects(for range: NSRange) -> [CGRect] {
            var rects = [CGRect]()
            enumerateTextRects(in: range) { rect in
                rects.append(rect)
            }
            return rects
        }

        /// Calls `block` with each rect `rects(for:)` would return, in line order,
        /// without collecting them into an array.
        open func enumerateTextRects(in range: NSRange, using block: (CGRect) -> Void) {
            guard let range = NSRange.sanitized(range, within: attributedString.length),
                  let lines,
                  let lineOrigins,
                  let lineMetrics
            else { return }

            let rangeEnd = range.location + range.length
            for i in Self.firstLineIndex(endingAfter: range.location, in: lines) ..< lines.count {
                let line = lines[i]
                let lineRange = CTLineGetStringRange(line)

                let lineStart = lineRange.location
                let lineEnd = lineStart + lineRange.length
                // Frame lines cover the string in order, so no later line can overlap.
                if lineStart >= rangeEnd {
                    break
                }
                let overlapStart = max(lineStart, range.location)
                let overlapEnd = min(lineEnd, rangeEnd)

                if overlapStart >= overlapEnd {
                    continue
                }

                let lineOrigin = lineOrigins[i]
                let lineBox = lineMetrics[i].clippedRect(at: lineOrigin, containerWidth: containerSize.width)
                for extent in horizontalExtents(
                    of: line,
                    width: lineMetrics[i].width,
                    overlapStart: overlapStart,
                    overlapEnd: overlapEnd,
                    lineStart: lineStart,
                    lineEnd: lineEnd,
                ) {
                    block(CGRect(
                        x: lineOrigin.x + extent.lowerBound,
                        y: lineBox.minY,
                        width: extent.upperBound - extent.lowerBound,
                        height: lineBox.height,
                    ).clippedHorizontally(to: lineBox))
                }
            }
        }

        /// The index of the first line whose string range ends after `index`, or
        /// `lines.count` if none does. Frame lines hold consecutive, ascending string
        /// ranges, so the lines before it cannot contain `index` or anything later.
        private static func firstLineIndex(endingAfter index: Int, in lines: [CTLine]) -> Int {
            var low = 0
            var high = lines.count
            while low < high {
                let mid = (low + high) / 2
                let lineRange = CTLineGetStringRange(lines[mid])
                if lineRange.location + lineRange.length > index {
                    high = mid
                } else {
                    low = mid + 1
                }
            }
            return low
        }

        /// The x-extents, relative to the line origin and in visual order, covered
        /// by the characters in `overlapStart ..< overlapEnd`.
        ///
        /// Lines whose runs are all left-to-right in logical order map the range
        /// to one span between two caret offsets. Bidirectional lines can show a
        /// logically contiguous range as several visual segments, so those are
        /// measured character by character between caret edges, and justified
        /// lines glyph by glyph (see `SelectionGeometry`).
        private func horizontalExtents(
            of line: CTLine,
            width: CGFloat,
            overlapStart: CFIndex,
            overlapEnd: CFIndex,
            lineStart: CFIndex,
            lineEnd: CFIndex,
        ) -> [ClosedRange<CGFloat>] {
            let glyphRuns = CTLineGetGlyphRuns(line) as NSArray
            let extents: [ClosedRange<CGFloat>]
            switch selectionGeometry(of: glyphRuns, lineStart: lineStart) {
            case .caretOffsets:
                let startOffset = overlapStart > lineStart
                    ? CTLineGetOffsetForStringIndex(line, overlapStart, nil)
                    : 0
                let endOffset = overlapEnd < lineEnd
                    ? CTLineGetOffsetForStringIndex(line, overlapEnd, nil)
                    : width
                return [startOffset ... max(startOffset, endOffset)]
            case .caretEdges:
                extents = caretEdgeExtents(
                    of: line,
                    glyphRuns: glyphRuns,
                    overlapStart: overlapStart,
                    overlapEnd: overlapEnd,
                    lineStart: lineStart,
                )
            case .glyphs:
                extents = Self.glyphExtents(of: glyphRuns, overlapStart: overlapStart, overlapEnd: overlapEnd)
            }

            // Characters that touch visually share one rect.
            var merged = [ClosedRange<CGFloat>]()
            for extent in extents.sorted(by: { $0.lowerBound < $1.lowerBound }) {
                if let last = merged.last, extent.lowerBound <= last.upperBound + 0.5 {
                    merged[merged.count - 1] = last.lowerBound ... max(last.upperBound, extent.upperBound)
                } else {
                    merged.append(extent)
                }
            }
            return merged
        }

        /// Each composed character's extent between its caret edges, relative to the
        /// line origin.
        ///
        /// Caret edges partition a bidirectional line without gaps or overlaps, split
        /// ligatures between their characters, and keep kerning and marks with negative
        /// advances from pushing one character's box into its neighbour's. A character
        /// CoreText reports no caret edge for falls back to the glyph that draws it.
        private func caretEdgeExtents(
            of line: CTLine,
            glyphRuns: NSArray,
            overlapStart: CFIndex,
            overlapEnd: CFIndex,
            lineStart: CFIndex,
        ) -> [ClosedRange<CGFloat>] {
            let edges = Self.caretEdges(of: line)
            let string = attributedString.string as NSString
            var extents = [ClosedRange<CGFloat>]()
            var index = max(string.rangeOfComposedCharacterSequence(at: overlapStart).location, lineStart)
            while index < overlapEnd {
                let characterEnd = NSMaxRange(string.rangeOfComposedCharacterSequence(at: index))
                if let extent = Self.union(of: edges, in: index ..< characterEnd) {
                    extents.append(extent)
                } else {
                    extents += Self.glyphExtents(of: glyphRuns, overlapStart: index, overlapEnd: characterEnd)
                }
                index = characterEnd
            }
            return extents
        }

        /// The caret offsets CoreText reports for each string index of `line`, as the
        /// span between the smallest and the largest.
        private static func caretEdges(of line: CTLine) -> [CFIndex: ClosedRange<CGFloat>] {
            var edges = [CFIndex: ClosedRange<CGFloat>]()
            CTLineEnumerateCaretOffsets(line) { offset, index, _, _ in
                let offset = CGFloat(offset)
                if let edge = edges[index] {
                    edges[index] = min(edge.lowerBound, offset) ... max(edge.upperBound, offset)
                } else {
                    edges[index] = offset ... offset
                }
            }
            return edges
        }

        private static func union(
            of edges: [CFIndex: ClosedRange<CGFloat>],
            in indices: Range<CFIndex>,
        ) -> ClosedRange<CGFloat>? {
            var result: ClosedRange<CGFloat>?
            for index in indices {
                guard let edge = edges[index] else { continue }
                result = result.map { min($0.lowerBound, edge.lowerBound) ... max($0.upperBound, edge.upperBound) } ?? edge
            }
            return result
        }

        /// The advance boxes of the glyphs drawing `overlapStart ..< overlapEnd`.
        ///
        /// A glyph stands for its whole cluster: a surrogate pair, a ZWJ sequence or
        /// a ligature has characters with no glyph of their own, and those are
        /// covered by the glyph that draws them.
        private static func glyphExtents(
            of glyphRuns: NSArray,
            overlapStart: CFIndex,
            overlapEnd: CFIndex,
        ) -> [ClosedRange<CGFloat>] {
            var extents = [ClosedRange<CGFloat>]()
            for runIndex in 0 ..< glyphRuns.count {
                let glyphRun = glyphRuns[runIndex] as! CTRun
                let runRange = CTRunGetStringRange(glyphRun)
                guard runRange.location < overlapEnd,
                      runRange.location + runRange.length > overlapStart
                else { continue }

                let glyphCount = CTRunGetGlyphCount(glyphRun)
                guard glyphCount > 0 else { continue }
                var stringIndices = [CFIndex](repeating: 0, count: glyphCount)
                var positions = [CGPoint](repeating: .zero, count: glyphCount)
                var advances = [CGSize](repeating: .zero, count: glyphCount)
                let allGlyphs = CFRange(location: 0, length: 0)
                CTRunGetStringIndices(glyphRun, allGlyphs, &stringIndices)
                CTRunGetPositions(glyphRun, allGlyphs, &positions)
                CTRunGetAdvances(glyphRun, allGlyphs, &advances)

                let clusterStarts = Array(Set(stringIndices)).sorted()
                let runEnd = runRange.location + runRange.length
                for glyphIndex in 0 ..< glyphCount {
                    let clusterStart = stringIndices[glyphIndex]
                    let clusterEnd = clusterEnd(startingAt: clusterStart, in: clusterStarts) ?? runEnd
                    guard clusterStart < overlapEnd, clusterEnd > overlapStart else { continue }
                    let minX = positions[glyphIndex].x
                    let maxX = minX + advances[glyphIndex].width
                    extents.append(min(minX, maxX) ... max(minX, maxX))
                }
            }
            return extents
        }

        /// The first cluster start after `start` in the sorted `clusterStarts`,
        /// which is where the cluster beginning at `start` ends; `nil` for the last one.
        private static func clusterEnd(startingAt start: CFIndex, in clusterStarts: [CFIndex]) -> CFIndex? {
            var low = 0
            var high = clusterStarts.count
            while low < high {
                let mid = (low + high) / 2
                if clusterStarts[mid] > start {
                    high = mid
                } else {
                    low = mid + 1
                }
            }
            return low < clusterStarts.count ? clusterStarts[low] : nil
        }

        private func selectionGeometry(of glyphRuns: NSArray, lineStart: CFIndex) -> SelectionGeometry {
            if lineStart < attributedString.length,
               let style = attributedString.attribute(.paragraphStyle, at: lineStart, effectiveRange: nil)
               as? NSParagraphStyle,
               style.alignment == .justified
            {
                return .glyphs
            }
            return Self.runsAreVisuallyOrdered(glyphRuns) ? .caretOffsets : .caretEdges
        }

        /// Whether logical order matches visual order across `glyphRuns`: every run
        /// is left-to-right and each starts after the previous one in the string.
        private static func runsAreVisuallyOrdered(_ glyphRuns: NSArray) -> Bool {
            var previousEnd = 0
            for runIndex in 0 ..< glyphRuns.count {
                let glyphRun = glyphRuns[runIndex] as! CTRun
                if CTRunGetStatus(glyphRun).contains(.rightToLeft) {
                    return false
                }
                let runRange = CTRunGetStringRange(glyphRun)
                if runRange.location < previousEnd {
                    return false
                }
                previousEnd = runRange.location + runRange.length
            }
            return true
        }

        // MARK: - Private Methods

        private static func makeGeneration() -> Int {
            lastGeneration += 1
            return lastGeneration
        }

        private func generateLayout() {
            lines = nil
            lineOrigins = nil
            lineMetrics = nil

            // An invalid container (NaN, negative or infinite) holds no text. Skip
            // CoreText entirely: a NaN width, for one, fits no line, yet fails every
            // comparison, so the path width would read it as unconstrained, and
            // measuring it can hand it to the framesetter, which walks the whole path
            // looking for a line that fits: about a second for a 1e8-point one.
            guard containerSize.isValidLayoutSize else {
                adopt(FrameFill(
                    lines: [],
                    lineOrigins: [],
                    lineMetrics: [],
                    pathSize: .zero,
                    measuredSize: .zero,
                    unbrokenWidth: 0,
                    isComplete: false,
                ))
                return
            }

            // A measurement pass over the same width already laid out every line;
            // reuse it and translate the origins into the container's height.
            if adoptMeasurementFillIfMatching() {
                return
            }

            // Measuring at this width may lay out a frame; adopting it avoids
            // typesetting the same text a second time. Measurement frames stop at
            // `maxLayoutDimension`; taller text falls back to the framesetter,
            // which still reports its full height here.
            let naturalHeight = sizeThatFits(CGSize(
                width: containerSize.width,
                height: Self.maxLayoutHeight,
            )).height
            if adoptMeasurementFillIfMatching() {
                return
            }

            // CoreText fills a frame only as far as its path allows and silently
            // discards the lines beyond it. A host whose height trails its content
            // — a resize, a pending measurement — would lose the tail of the text
            // along with every attachment and run living there, so the path is as
            // tall as a measurement's. Text stays anchored to the top of
            // `containerSize`, so lines past the container simply fall outside the
            // view and are clipped rather than lost. Using the measurement's path
            // height also makes the line origins bit-identical to an adopted
            // measurement, whichever of the two produced the lines. Only text
            // taller than a measurement frame holds gets the taller path.
            let pathHeight = naturalHeight <= Self.maxLayoutDimension
                ? Self.maxLayoutDimension
                : Self.maxLayoutHeight
            var fill = makeFrameFill(
                constraint: CGSize(width: layoutPathWidth, height: pathHeight),
                clampsToMaxLayoutDimension: false,
            )
            // CoreText can need more height than it measures: a maximum line height
            // below the font's gives lines a negative descent, and the measured
            // height then stops above the last baseline, which the frame requires.
            // Text measured just under the shorter path can still overflow it, so
            // rather than lose its last line, lay out once more in the tallest path.
            if !fill.isComplete, pathHeight < Self.maxLayoutHeight {
                fill = makeFrameFill(
                    constraint: CGSize(width: layoutPathWidth, height: Self.maxLayoutHeight),
                    clampsToMaxLayoutDimension: false,
                )
            }
            adopt(fill)
        }

        /// The path width lines are broken at. Like `sizeThatFits(_:)` and the
        /// framesetter, a zero width means unconstrained, so a container sized to
        /// text that measures zero wide (whitespace only) keeps the lines that
        /// measurement counted. A negative width never gets here: it is invalid
        /// and lays out nothing.
        private var layoutPathWidth: CGFloat {
            containerSize.width > 0 ? containerSize.width : Self.maxLayoutDimension
        }

        private func adoptMeasurementFillIfMatching() -> Bool {
            guard let fill = measurementFill,
                  fill.isComplete,
                  fill.pathSize.width == layoutPathWidth,
                  anchorHeight <= Self.maxLayoutDimension
            else { return false }
            adopt(fill)
            return true
        }

        /// Takes a fill's lines and moves its origins into the current container,
        /// keeping the first line anchored to the top of `containerSize`.
        private func adopt(_ fill: FrameFill) {
            generation = Self.makeGeneration()
            lines = fill.lines
            lineMetrics = fill.lineMetrics

            let offsetY = anchorHeight - fill.pathSize.height
            if offsetY == 0 {
                lineOrigins = fill.lineOrigins
            } else {
                lineOrigins = fill.lineOrigins.map {
                    CGPoint(x: $0.x, y: $0.y + offsetY)
                }
            }
            lineBoxesAreOrdered = computeLineBoxesAreOrdered()
        }

        /// One pass over the boxes per layout, so every lookup after it can
        /// binary-search. A NaN in any box fails the comparisons and counts as
        /// out of order.
        private func computeLineBoxesAreOrdered() -> Bool {
            guard let lineOrigins, let lineMetrics, lineMetrics.count > 1 else { return true }
            var previous = lineMetrics[0].rect(at: lineOrigins[0])
            for index in 1 ..< lineMetrics.count {
                let box = lineMetrics[index].rect(at: lineOrigins[index])
                guard box.minY <= previous.minY,
                      box.midY <= previous.midY,
                      box.maxY <= previous.maxY
                else { return false }
                previous = box
            }
            return true
        }

        private func makeFrameFill(constraint: CGSize, clampsToMaxLayoutDimension: Bool) -> FrameFill {
            var pathSize = constraint
            if clampsToMaxLayoutDimension {
                pathSize.width = min(pathSize.width, Self.maxLayoutDimension)
                pathSize.height = min(pathSize.height, Self.maxLayoutDimension)
            }
            let containerPath = CGPath(
                rect: CGRect(origin: .zero, size: pathSize),
                transform: nil,
            )
            let ctFrame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: 0, length: 0),
                containerPath,
                nil,
            )

            let frameLines = (CTFrameGetLines(ctFrame) as? [CTLine]) ?? []
            var origins = [CGPoint](repeating: .zero, count: frameLines.count)
            if !frameLines.isEmpty {
                CTFrameGetLineOrigins(ctFrame, CFRange(location: 0, length: 0), &origins)
            }

            var metrics = [LineMetrics]()
            metrics.reserveCapacity(frameLines.count)
            var maxLineTrailingX: CGFloat = 0
            var maxLineEndX: CGFloat = 0
            var minLineY = pathSize.height
            for index in 0 ..< frameLines.count {
                let line = frameLines[index]
                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                var leading: CGFloat = 0
                let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
                let isLastLine = index == frameLines.count - 1
                let trailingWhitespace = CGFloat(CTLineGetTrailingWhitespaceWidth(line))
                // A right-to-left line hangs its trailing whitespace to the left of
                // the origin; the typographic bounds report where it went. Text that
                // can contain such a line never uses frame-derived measurement.
                let minX = trailingWhitespace > 0 && !usesFrameDerivedMeasurement
                    ? CTLineGetBoundsWithOptions(line, []).minX
                    : 0
                metrics.append(LineMetrics(
                    ascent: ascent,
                    descent: descent,
                    leading: isLastLine ? 0 : leading,
                    width: width,
                    trailingWhitespaceWidth: trailingWhitespace,
                    minX: minX,
                ))

                maxLineTrailingX = max(maxLineTrailingX, origins[index].x + width - trailingWhitespace)
                maxLineEndX = max(maxLineEndX, origins[index].x + width)
                minLineY = min(minLineY, origins[index].y - descent)
            }

            // CTFramesetterSuggestFrameSizeWithConstraints reports the exact used
            // width but rounds the height up to a whole point; mirror both so
            // callers observe identical sizes on either measurement path.
            let measuredSize: CGSize = frameLines.isEmpty
                ? .zero
                : CGSize(width: maxLineTrailingX, height: ceil(pathSize.height - minLineY))

            let visibleRange = CTFrameGetVisibleStringRange(ctFrame)
            let isComplete = visibleRange.location + visibleRange.length >= attributedString.length

            return FrameFill(
                lines: frameLines,
                lineOrigins: origins,
                lineMetrics: metrics,
                pathSize: pathSize,
                measuredSize: measuredSize,
                unbrokenWidth: maxLineEndX,
                isComplete: isComplete,
            )
        }

        private func frameDerivedMeasurementIsSafe() -> Bool {
            guard attributedString.length > 0 else { return true }

            // Frame-derived measurement reads the used width from line origins,
            // which only matches the framesetter's suggestion when x-origins do
            // not scale with the layout path width. Centered, right-aligned,
            // justified, or right-to-left content keeps the suggestion pass. A
            // negative tail indent narrows every line without showing up in its
            // origin or width, so the frame would under-report the width the text
            // needs to stay on one line.
            let hasUnsafeParagraphStyle = containsAttribute(.paragraphStyle) { value in
                guard let style = value as? NSParagraphStyle else { return false }
                let alignmentIsSafe = style.alignment == .left || style.alignment == .natural
                return !alignmentIsSafe
                    || style.baseWritingDirection == .rightToLeft
                    || style.tailIndent < 0
            }
            guard !hasUnsafeParagraphStyle else { return false }

            return !containsRightToLeftContent()
        }

        private func containsRightToLeftContent() -> Bool {
            for scalar in attributedString.string.unicodeScalars {
                switch scalar.value {
                case 0x0590 ... 0x08FF, // Hebrew, Arabic, Syriac, and neighbours
                     0xFB1D ... 0xFDFF, // Hebrew and Arabic presentation forms
                     0xFE70 ... 0xFEFF, // Arabic presentation forms B
                     0x10800 ... 0x10FFF, // ancient right-to-left scripts
                     0x1E800 ... 0x1EFFF, // Adlam and other modern RTL additions
                     0x200F, 0x202B, 0x202E, 0x2067: // directional formatting marks
                    return true
                default:
                    continue
                }
            }
            return false
        }

        private func lineIndices(intersecting visibleRect: CGRect?) -> Range<Int> {
            guard let lines, !lines.isEmpty else { return 0 ..< 0 }
            guard let visibleRect, !visibleRect.isNull else { return 0 ..< lines.count }

            // Line origins live in CoreText's bottom-left space; the visible rect
            // is top-left based against the same containerSize used by draw(in:).
            let layoutRect = layoutRect(fromViewRect: visibleRect)
            let hits = lineIndices(intersectingLayoutRect: layoutRect)
            guard !hits.isEmpty else { return 0 ..< 0 }

            // Glyph ink can slightly overshoot typographic bounds; include one
            // extra line on each side so partial redraws never clip an overhang.
            return max(0, hits.lowerBound - 1) ..< min(lines.count, hits.upperBound + 1)
        }

        /// The lines whose boxes reach into `rect`'s vertical extent, in layout
        /// space, stopping at the first line wholly below it.
        func lineIndices(intersectingLayoutRect rect: CGRect) -> Range<Int> {
            guard let lineCount = lines?.count, lineBoxesAreOrdered, !rect.minY.isNaN, !rect.maxY.isNaN else {
                return linearLineIndices(intersectingLayoutRect: rect)
            }
            // Boxes descend, so the lines above `rect` and those below it each
            // form one run, found by bisection.
            let firstBelow = Self.partitionPoint(lineCount) { lineBox(at: $0).maxY < rect.minY }
            let first = Self.partitionPoint(lineCount) { lineBox(at: $0).minY <= rect.maxY }
            return first < firstBelow ? first ..< firstBelow : 0 ..< 0
        }

        /// The reference scan `lineIndices(intersectingLayoutRect:)` must agree
        /// with, and its path for boxes out of order.
        func linearLineIndices(intersectingLayoutRect rect: CGRect) -> Range<Int> {
            guard let lineCount = lines?.count else { return 0 ..< 0 }
            var first = lineCount
            var lastExclusive = 0
            for index in 0 ..< lineCount {
                let lineBox = lineBox(at: index)
                if lineBox.minY > rect.maxY {
                    continue
                }
                // Lines only descend from here on, so the remainder is offscreen.
                if lineBox.maxY < rect.minY {
                    break
                }
                if index < first {
                    first = index
                }
                lastExclusive = index + 1
            }
            return first < lastExclusive ? first ..< lastExclusive : 0 ..< 0
        }

        /// The box of line `index` in layout space, leading included: the box
        /// hit testing and draw culling share.
        func lineBox(at index: Int) -> CGRect {
            lineMetrics![index].rect(at: lineOrigins![index])
        }

        /// The first index in `0 ..< count` where `predicate` holds, or `count`.
        /// `predicate` must hold for every index after one where it holds.
        private static func partitionPoint(_ count: Int, where predicate: (Int) -> Bool) -> Int {
            var low = 0
            var high = count
            while low < high {
                let mid = (low + high) / 2
                if predicate(mid) {
                    high = mid
                } else {
                    low = mid + 1
                }
            }
            return low
        }

        private func extractHighlightRegions() {
            guard let lines, let lineMetrics else { return }
            // The effective range last found for each highlight attribute. A link
            // styled character by character splits into one run per character, and
            // looking up the longest effective range again for each of them walks
            // the whole link every time, which is quadratic in its length.
            var effectiveRanges: [NSAttributedString.Key: NSRange] = [:]
            enumerateRuns(
                inLines: 0 ..< lines.count,
                carrying: Self.highlightRunKeys,
            ) { lineIndex, _, lineOrigin, glyphRun in
                // Bridging the attribute dictionary into Swift is expensive, so
                // it is reserved for the few runs carrying highlight attributes.
                let attributes = CTRunGetAttributes(glyphRun) as? [NSAttributedString.Key: Any] ?? [:]
                processHighlightRegionForRun(
                    glyphRun,
                    attributes: attributes,
                    lineOrigin: lineOrigin,
                    lineBox: lineMetrics[lineIndex].clippedRect(at: lineOrigin, containerWidth: containerSize.width),
                    effectiveRanges: &effectiveRanges,
                )
            }
        }

        @inline(__always)
        private static func runAttributeValue(_ run: CTRun, _ key: CFString) -> AnyObject? {
            let attributes = CTRunGetAttributes(run)
            guard let value = CFDictionaryGetValue(
                attributes,
                Unmanaged.passUnretained(key).toOpaque(),
            ) else { return nil }
            return Unmanaged<AnyObject>.fromOpaque(value).takeUnretainedValue()
        }

        private var fullRange: NSRange {
            NSRange(location: 0, length: attributedString.length)
        }

        /// Whether any value of `key` in the string satisfies `predicate`.
        ///
        /// Enumerating one key at a time keeps CoreText's attribute dictionaries out
        /// of Swift; `enumerateAttributes` would bridge every run's full dictionary.
        private func containsAttribute(
            _ key: NSAttributedString.Key,
            where predicate: (Any) -> Bool,
        ) -> Bool {
            guard attributedString.length > 0 else { return false }

            var found = false
            attributedString.enumerateAttribute(key, in: fullRange, options: []) { value, _, stop in
                if let value, predicate(value) {
                    found = true
                    stop.pointee = true
                }
            }
            return found
        }

        private func attributedStringHasHighlightAttributes() -> Bool {
            Self.highlightAttributes.contains { attribute in
                containsAttribute(attribute.key) { _ in true }
            }
        }

        private func attributedStringHasLineDrawingActions() -> Bool {
            containsAttribute(.litextLineDrawingAction) { $0 is TextLabel.LineDrawingAction }
        }

        private func processHighlightRegionForRun(
            _ glyphRun: CTRun,
            attributes: [NSAttributedString.Key: Any],
            lineOrigin: CGPoint,
            lineBox: CGRect,
            effectiveRanges: inout [NSAttributedString.Key: NSRange],
        ) {
            let stringRange = NSRange(CTRunGetStringRange(glyphRun))
            // A link ending a wrapped line includes the whitespace hanging past the
            // container; the region stops at the line box like a selection does.
            let runBounds = runBoundingRect(glyphRun, lineOrigin: lineOrigin).clippedHorizontally(to: lineBox)

            for attribute in Self.highlightAttributes where attributes[attribute.key] != nil {
                // A longest effective range is maximal, so every location inside it
                // has that same range; only a run outside it needs a new lookup.
                var effectiveRange = NSRange()
                if let cached = effectiveRanges[attribute.key], cached.contains(stringRange.location) {
                    effectiveRange = cached
                } else {
                    _ = attributedString.attribute(
                        attribute.key,
                        at: stringRange.location,
                        longestEffectiveRange: &effectiveRange,
                        in: fullRange,
                    )
                    effectiveRanges[attribute.key] = effectiveRange
                }
                addHighlightRegion(
                    kind: attribute.kind,
                    attributes: attributes,
                    stringRange: effectiveRange,
                    rect: runBounds,
                )
            }
        }

        private func addHighlightRegion(
            kind: TextLabel.HighlightRegion.Kind,
            attributes: [NSAttributedString.Key: Any],
            stringRange: NSRange,
            rect: CGRect,
        ) {
            let key = RegionKey(kind: kind, location: stringRange.location)
            let highlightRegion: TextLabel.HighlightRegion
            if let existingRegion = _highlightRegions[key] {
                highlightRegion = existingRegion
            } else {
                highlightRegion = TextLabel.HighlightRegion(
                    kind: kind,
                    attributes: attributes,
                    stringRange: stringRange,
                )
                _highlightRegions[key] = highlightRegion
            }

            highlightRegion.addRect(rect)
        }

        /// The run's typographic box in layout space: its advance width by its
        /// ascent and descent. Ink bounds would skip spaces, trim side bearings and
        /// vary in height from word to word; typographic bounds keep link regions
        /// uniform and give attachments exactly their run delegate's metrics.
        private func runBoundingRect(_ glyphRun: CTRun, lineOrigin: CGPoint) -> CGRect {
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            let allGlyphs = CFRange(location: 0, length: 0)
            let width = CGFloat(CTRunGetTypographicBounds(glyphRun, allGlyphs, &ascent, &descent, nil))

            // Glyphs in a right-to-left run need not be stored left to right, so the
            // run's left edge is the smallest glyph position, not the first one.
            let glyphCount = CTRunGetGlyphCount(glyphRun)
            var minX: CGFloat = 0
            if glyphCount > 0 {
                var positions = [CGPoint](repeating: .zero, count: glyphCount)
                CTRunGetPositions(glyphRun, allGlyphs, &positions)
                minX = positions.lazy.map(\.x).min() ?? 0
            }

            return CGRect(
                x: lineOrigin.x + minX,
                y: lineOrigin.y - descent,
                width: width,
                height: ascent + descent,
            )
        }

        // MARK: - Coordinate Conversion

        // Layout geometry uses CoreText's lower-left origin; views, visible rects and
        // attachment frames use a top-left origin. Both flip against
        // `anchorHeight`, the same height `draw(in:)` flips the context by and
        // lines are anchored to, so this is the only place the flip is written down.

        /// The container height the first line is anchored below: `containerSize.height`
        /// for every height a layout can fill. An infinite height would make every line
        /// origin infinite, and `.greatestFiniteMagnitude` would round them all to the
        /// same value, so heights beyond `maxLayoutHeight` in either direction are clamped
        /// to it, and a NaN height anchors the text to a zero-height container. The text
        /// still starts at the top, so view-space geometry is unaffected.
        private var anchorHeight: CGFloat {
            let height = containerSize.height
            guard !height.isNaN else { return 0 }
            return min(max(height, -Self.maxLayoutHeight), Self.maxLayoutHeight)
        }

        /// Converts a rect from layout space to top-left view space.
        ///
        /// Layout space is the lower-left-origin space of `rects(for:)`,
        /// `layoutRuns(matching:)` and `HighlightRegion.rects`. The flip uses
        /// the container's height, so it matches what `draw(in:)` paints.
        public func viewRect(fromLayoutRect rect: CGRect) -> CGRect {
            var result = rect
            result.origin.y = anchorHeight - rect.origin.y - rect.size.height
            return result
        }

        /// Converts a rect from top-left view space to layout space.
        public func layoutRect(fromViewRect rect: CGRect) -> CGRect {
            CGRect(
                x: rect.minX,
                y: anchorHeight - rect.maxY,
                width: rect.width,
                height: rect.height,
            )
        }

        /// Converts a point from top-left view space to layout space.
        public func layoutPoint(fromViewPoint point: CGPoint) -> CGPoint {
            CGPoint(x: point.x, y: anchorHeight - point.y)
        }

        // MARK: - Text Index Helpers

        /// The caret index nearest to `point` (in layout space) on the line that
        /// contains it, or the end of the text when `point` lies below the last
        /// line; `nil` above or between lines.
        ///
        /// A caret index rounds to the nearer edge of a glyph. Use
        /// `characterIndex(at:)` for the character under the point. The line is
        /// found by binary search, then the caret within it.
        open func textIndex(at point: CGPoint) -> Int? {
            guard let lines, let lineOrigins else { return nil }

            if let hit = findLineContainingPoint(point) {
                return caretIndex(at: point, in: hit)
            }

            guard !lines.isEmpty else { return nil }

            guard point.y < lineOrigins[lines.count - 1].y else { return nil }
            let range = CTLineGetStringRange(lines[lines.count - 1])
            return range.location + range.length
        }

        /// The caret index nearest to `point` (in layout space), on the line
        /// containing it or else on the nearest line. `nil` only when there is no
        /// text. Selection drags use it, once per move. The line is found by binary
        /// search, then the caret within it.
        open func nearestTextIndex(at point: CGPoint) -> Int? {
            guard let hit = findLineContainingPoint(point) ?? nearestLine(to: point) else { return nil }
            return caretIndex(at: point, in: hit)
        }

        /// The index of the character under `point` on the nearest line, for word
        /// and line selection.
        ///
        /// `nearestTextIndex(at:)` returns a caret index, which rounds to the
        /// nearer edge of a glyph: the right half of a letter yields the next
        /// character. This one returns the character whose selection rect contains
        /// the point, in either direction: between caret offsets on a line that
        /// `rects(for:)` measures that way, otherwise the start of the cluster whose
        /// glyph contains the point. Away from every character it falls back to the
        /// caret index, kept on the hit line's last character.
        ///
        /// `point` is in layout space; convert a view point with
        /// `layoutPoint(fromViewPoint:)`. Returns `nil` only when there is no text.
        ///
        /// - Important: Performance-sensitive. The line is found by binary search,
        ///   but measuring within it walks its characters, so the cost grows with
        ///   the length of the line hit: keep it off per-frame paths for text with
        ///   very long lines.
        open func characterIndex(at point: CGPoint) -> Int? {
            guard let hit = findLineContainingPoint(point) ?? nearestLine(to: point) else { return nil }
            let lineOffset = point.x - hit.origin.x
            let lineStart = CTLineGetStringRange(hit.line).location
            let index: Int? = switch selectionGeometry(of: CTLineGetGlyphRuns(hit.line) as NSArray, lineStart: lineStart) {
            case .caretOffsets:
                characterStart(atCaretOffset: lineOffset, in: hit.line)
            case .caretEdges:
                characterStart(atCaretEdgeOffset: lineOffset, in: hit.line)
                    ?? Self.clusterStart(atLineOffset: lineOffset, in: hit.line)
            case .glyphs:
                Self.clusterStart(atLineOffset: lineOffset, in: hit.line)
            }
            if let index {
                return index
            }
            let lineRange = CTLineGetStringRange(hit.line)
            let lastCharacter = lineRange.location + max(lineRange.length - 1, 0)
            return min(caretIndex(at: point, in: hit), lastCharacter)
        }

        /// A zero-width rect at the caret offset of `caretIndex`, spanning the box
        /// of the line that holds `characterIndex`, in layout space.
        ///
        /// Selection handles use it when `rects(for:)` has nothing for the character
        /// they sit on, rather than jumping to the view's origin.
        func caretRect(at caretIndex: Int, onLineOf characterIndex: Int) -> CGRect? {
            guard let lines, let lineOrigins, let lineMetrics, !lines.isEmpty else { return nil }
            let lineIndex = min(Self.firstLineIndex(endingAfter: characterIndex, in: lines), lines.count - 1)
            let line = lines[lineIndex]
            let lineRange = CTLineGetStringRange(line)
            let clampedIndex = min(max(caretIndex, lineRange.location), lineRange.location + lineRange.length)
            let offset = CTLineGetOffsetForStringIndex(line, clampedIndex, nil)
            let lineOrigin = lineOrigins[lineIndex]
            let lineBox = lineMetrics[lineIndex].clippedRect(at: lineOrigin, containerWidth: containerSize.width)
            return CGRect(x: lineOrigin.x + offset, y: lineBox.minY, width: 0, height: lineBox.height)
                .clippedHorizontally(to: lineBox)
        }

        /// The point on the baseline where the character at `index` starts, in layout
        /// space. AppKit's Look Up draws its highlight over the text from there.
        func baselineOrigin(at index: Int) -> CGPoint? {
            guard let lines, let lineOrigins, !lines.isEmpty else { return nil }
            let lineIndex = min(Self.firstLineIndex(endingAfter: index, in: lines), lines.count - 1)
            let offset = CTLineGetOffsetForStringIndex(lines[lineIndex], index, nil)
            let lineOrigin = lineOrigins[lineIndex]
            return CGPoint(x: lineOrigin.x + offset, y: lineOrigin.y)
        }

        // MARK: - Private Text Index Helpers

        private func nearestLine(to point: CGPoint) -> LineHit? {
            guard let lines, let lineOrigins, let index = nearestLineIndex(toLayoutY: point.y) else { return nil }
            return LineHit(line: lines[index], origin: lineOrigins[index])
        }

        /// The line for a point between or beyond the lines: the first line when
        /// `y` is above its baseline, the last when below its baseline, and
        /// otherwise the line whose box's middle is nearest, the earlier one on a
        /// tie.
        func nearestLineIndex(toLayoutY y: CGFloat) -> Int? {
            guard let lines, let lineOrigins, !lines.isEmpty else { return nil }
            if y > lineOrigins[0].y {
                return 0
            }
            let lastIndex = lines.count - 1
            if y < lineOrigins[lastIndex].y {
                return lastIndex
            }
            guard lineBoxesAreOrdered, !y.isNaN else {
                return linearNearestLineIndex(toLayoutY: y)
            }
            // The middles descend, so the nearest is the last line whose middle is
            // above `y` or the first one at or below it.
            let firstAtOrBelow = Self.partitionPoint(lines.count) { lineBox(at: $0).midY <= y }
            guard firstAtOrBelow > 0 else { return firstAtOrBelow }
            let lastAbove = firstAtOrBelow - 1
            let distanceAbove = lineBox(at: lastAbove).midY - y
            if firstAtOrBelow < lines.count, y - lineBox(at: firstAtOrBelow).midY < distanceAbove {
                return firstAtOrBelow
            }
            // Distances shrink towards `lastAbove`. Of the lines as near as it,
            // which can differ in middle once rounded, the scan keeps the first.
            return Self.partitionPoint(lastAbove) { lineBox(at: $0).midY - y <= distanceAbove }
        }

        /// The reference scan `nearestLineIndex(toLayoutY:)` must agree with, and
        /// its path for boxes out of order. Skips the first- and last-line cases
        /// its caller handles.
        func linearNearestLineIndex(toLayoutY y: CGFloat) -> Int? {
            guard let lines, !lines.isEmpty else { return nil }
            var closestLineIndex = 0
            var minDistance = CGFloat.greatestFiniteMagnitude
            for index in 0 ..< lines.count {
                let distance = abs(y - lineBox(at: index).midY)
                if distance < minDistance {
                    minDistance = distance
                    closestLineIndex = index
                }
            }
            return closestLineIndex
        }

        private func findLineContainingPoint(_ point: CGPoint) -> LineHit? {
            guard let lines, let lineOrigins, let index = lineIndex(containingLayoutY: point.y) else { return nil }
            return LineHit(line: lines[index], origin: lineOrigins[index])
        }

        /// The first line whose box spans `y`, or `nil` when `y` falls between
        /// lines or outside them.
        func lineIndex(containingLayoutY y: CGFloat) -> Int? {
            guard let lineCount = lines?.count, lineBoxesAreOrdered else {
                return linearLineIndex(containingLayoutY: y)
            }
            // Every line before the first whose bottom reaches `y` lies above it,
            // and when that line's top stays below `y`, so do all after it.
            let index = Self.partitionPoint(lineCount) { lineBox(at: $0).minY <= y }
            guard index < lineCount, lineBox(at: index).maxY >= y else { return nil }
            return index
        }

        /// The reference scan `lineIndex(containingLayoutY:)` must agree with, and
        /// its path for boxes out of order.
        func linearLineIndex(containingLayoutY y: CGFloat) -> Int? {
            guard let lineCount = lines?.count else { return nil }
            for index in 0 ..< lineCount {
                let lineBox = lineBox(at: index)
                if y >= lineBox.minY, y <= lineBox.maxY {
                    return index
                }
            }
            return nil
        }

        /// The start of the composed character whose caret span contains `x`,
        /// measured from the line origin, or `nil` when none does. Mirrors the caret
        /// branch of `horizontalExtents`, so it agrees with `rects(for:)`.
        private func characterStart(atCaretOffset x: CGFloat, in line: CTLine) -> Int? {
            let lineRange = CTLineGetStringRange(line)
            let lineEnd = lineRange.location + lineRange.length
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            guard x >= 0, x < width else { return nil }

            let string = attributedString.string as NSString
            var index = lineRange.location
            var startOffset: CGFloat = 0
            while index < lineEnd {
                let next = min(NSMaxRange(string.rangeOfComposedCharacterSequence(at: index)), lineEnd)
                let endOffset = next < lineEnd ? CTLineGetOffsetForStringIndex(line, next, nil) : width
                if x >= startOffset, x < endOffset {
                    return index
                }
                index = next
                startOffset = endOffset
            }
            return nil
        }

        /// The start of the composed character whose caret edges enclose `x`,
        /// measured from the line origin, or `nil` when none does. Mirrors
        /// `caretEdgeExtents`, so it agrees with `rects(for:)`.
        private func characterStart(atCaretEdgeOffset x: CGFloat, in line: CTLine) -> Int? {
            let lineRange = CTLineGetStringRange(line)
            let lineEnd = lineRange.location + lineRange.length
            let edges = Self.caretEdges(of: line)
            let string = attributedString.string as NSString
            var index = lineRange.location
            while index < lineEnd {
                let characterEnd = min(NSMaxRange(string.rangeOfComposedCharacterSequence(at: index)), lineEnd)
                if let extent = Self.union(of: edges, in: index ..< characterEnd),
                   x >= extent.lowerBound, x < extent.upperBound
                {
                    return index
                }
                index = characterEnd
            }
            return nil
        }

        /// The string index of the glyph whose advance contains `x`, measured from
        /// the line origin, or `nil` when no glyph does.
        private static func clusterStart(atLineOffset x: CGFloat, in line: CTLine) -> Int? {
            let glyphRuns = CTLineGetGlyphRuns(line) as NSArray
            for runIndex in 0 ..< glyphRuns.count {
                let glyphRun = glyphRuns[runIndex] as! CTRun
                let glyphCount = CTRunGetGlyphCount(glyphRun)
                guard glyphCount > 0 else { continue }
                var stringIndices = [CFIndex](repeating: 0, count: glyphCount)
                var positions = [CGPoint](repeating: .zero, count: glyphCount)
                var advances = [CGSize](repeating: .zero, count: glyphCount)
                let allGlyphs = CFRange(location: 0, length: 0)
                CTRunGetStringIndices(glyphRun, allGlyphs, &stringIndices)
                CTRunGetPositions(glyphRun, allGlyphs, &positions)
                CTRunGetAdvances(glyphRun, allGlyphs, &advances)

                for glyphIndex in 0 ..< glyphCount {
                    let minX = positions[glyphIndex].x
                    let maxX = minX + advances[glyphIndex].width
                    if x >= min(minX, maxX), x < max(minX, maxX) {
                        return stringIndices[glyphIndex]
                    }
                }
            }
            return nil
        }

        private func caretIndex(at point: CGPoint, in hit: LineHit) -> Int {
            let lineRange = CTLineGetStringRange(hit.line)
            let linePoint = CGPoint(x: point.x - hit.origin.x, y: 0)
            let index = CTLineGetStringIndexForPosition(hit.line, linePoint)
            return index == kCFNotFound ? lineRange.location + lineRange.length : index
        }
    }
}
