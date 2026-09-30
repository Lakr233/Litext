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

    /// The line's box in CoreText layout space (lower-left origin).
    ///
    /// CoreText places the first baseline `ascent` below the top of the path and
    /// spaces each following line by `descent + leading` below the previous one,
    /// so a line's leading belongs below its descent. Every consumer — selection
    /// rects, hit testing, draw culling — shares this box so they agree.
    func rect(at origin: CGPoint, includingLeading: Bool = true) -> CGRect {
        let trailingGap = includingLeading ? leading : 0
        return CGRect(
            x: origin.x,
            y: origin.y - descent - trailingGap,
            width: width,
            height: ascent + descent + trailingGap
        )
    }
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
    var isComplete: Bool
}

public extension TextLabel {
    @MainActor
    struct LayoutRun {
        public let lineIndex: Int
        public let attributes: [NSAttributedString.Key: Any]
        public let stringRange: NSRange
        /// The run's typographic box: its advance width by the ascent and descent
        /// of its font (or of its attachment's run delegate).
        public let rect: CGRect
        /// The line's typographic box, from the bottom of its descent to the top of
        /// its ascent. The line's leading, which sits below the descent, is excluded.
        public let lineRect: CGRect
    }
}

extension TextLabel {
    @MainActor
    open class Layout: NSObject {
        open private(set) var attributedString: NSAttributedString
        open var highlightRegions: [TextLabel.HighlightRegion] {
            _highlightRegionsArray
        }

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
        private var _highlightRegions: [RegionKey: TextLabel.HighlightRegion]
        private var _highlightRegionsArray: [TextLabel.HighlightRegion] = []
        private var suggestedSizeCache: (input: CGSize, output: CGSize)?
        private var suggestedSizeHistory: [(input: CGSize, output: CGSize)] = []
        private var naturalSizeCache: CGSize?
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

        /// Attributes that produce highlight regions, in the order a run's regions
        /// are added: a run carrying both a link and an attachment yields the link
        /// region first.
        private static let highlightAttributes: [(
            key: NSAttributedString.Key,
            runKey: CFString,
            kind: TextLabel.HighlightRegion.Kind
        )] = [
            (.link, NSAttributedString.Key.link.rawValue as CFString, .link),
            (
                .litextAttachment,
                NSAttributedString.Key.litextAttachment.rawValue as CFString,
                .attachment
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
            framesetter = CTFramesetterCreateWithAttributedString(snapshot)
            _highlightRegions = [:]
            generation = Self.makeGeneration()
            super.init()
        }

        /// Regenerates CoreText lines for the current `containerSize`.
        ///
        /// `containerSize` already triggers layout regeneration when assigned. Call this only after
        /// external state referenced by run delegates or custom drawing callbacks changes.
        open func invalidateLayout() {
            suggestedSizeCache = nil
            suggestedSizeHistory.removeAll()
            naturalSizeCache = nil
            measurementFill = nil
            // CoreText caches the typographic bounds it obtained from a run delegate inside
            // the framesetter, and never asks again for the lifetime of that framesetter.
            // Rebuilding lines from the existing one would pick up an attachment's new width
            // while keeping its old line height, so the framesetter is rebuilt too — this is
            // the only way a changed run delegate is observed.
            framesetter = CTFramesetterCreateWithAttributedString(attributedString)
            generateLayout()
        }

        open func sizeThatFits(_ size: CGSize) -> CGSize {
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
               naturalSizeCache.width <= size.width,
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
                    height: size.height > 0 ? size.height : Self.maxLayoutDimension
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
                    nil
                )
            }
            if size.width == CGFloat.greatestFiniteMagnitude, size.height == CGFloat.greatestFiniteMagnitude {
                naturalSizeCache = suggestedSize
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

        open func draw(in context: CGContext) {
            draw(in: context, visibleRect: nil)
        }

        /// Draws the laid-out text, restricted to the lines intersecting `visibleRect`.
        ///
        /// The rect uses a top-left origin in the same space as `containerSize`, matching the
        /// dirty rect handed to a view's `draw(_:)`. Passing `nil` draws every line.
        open func draw(in context: CGContext, visibleRect: CGRect?) {
            guard let lines, let lineOrigins, !lines.isEmpty else { return }

            let textLineIndices = lineIndices(intersecting: visibleRect)
            guard !textLineIndices.isEmpty else { return }

            context.saveGState()

            context.setAllowsAntialiasing(true)
            context.textMatrix = .identity

            context.translateBy(x: 0, y: containerSize.height)
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
        open func draw(line: CTLine, at _: Int, in context: CGContext) {
            CTLineDraw(line, context)
        }

        /// The number of laid-out lines intersecting `rect`; `nil` counts every line.
        open func visibleLineCount(in rect: CGRect?) -> Int {
            lineIndices(intersecting: rect).count
        }

        /// Returns laid-out glyph runs that carry `key`.
        ///
        /// Rects are in the same CoreText layout space returned by `rects(for:)`:
        /// lower-left origin, before a `TextLabelView` converts them to view space.
        open func layoutRuns(matching key: NSAttributedString.Key) -> [TextLabel.LayoutRun] {
            guard let lines, let lineMetrics else { return [] }

            var result = [TextLabel.LayoutRun]()
            enumerateRuns(
                inLines: 0 ..< lines.count,
                carrying: [key.rawValue as CFString]
            ) { lineIndex, _, lineOrigin, glyphRun in
                let attributes = CTRunGetAttributes(glyphRun) as? [NSAttributedString.Key: Any] ?? [:]
                result.append(TextLabel.LayoutRun(
                    lineIndex: lineIndex,
                    attributes: attributes,
                    stringRange: NSRange(CTRunGetStringRange(glyphRun)),
                    rect: runBoundingRect(glyphRun, lineOrigin: lineOrigin),
                    lineRect: lineMetrics[lineIndex].rect(at: lineOrigin, includingLeading: false)
                ))
            }
            return result
        }

        private func processLineDrawingActions(in context: CGContext, lineIndices: Range<Int>) {
            guard hasLineDrawingActions else { return }

            // An action is line-scoped, but CoreText splits a line into several runs
            // wherever attributes or fonts change. Each action runs once per line.
            var invokedLineIndex = -1
            var invokedActions: [ObjectIdentifier] = []
            enumerateRuns(
                inLines: lineIndices,
                carrying: [Self.lineDrawingRunKey]
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
            _ body: (_ lineIndex: Int, _ line: CTLine, _ lineOrigin: CGPoint, _ run: CTRun) -> Void
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
        open func rects(for range: NSRange) -> [CGRect] {
            var rects = [CGRect]()
            enumerateTextRects(in: range) { rect in
                rects.append(rect)
            }
            return rects
        }

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

                let lineBox = lineMetrics[i].rect(at: lineOrigins[i])
                for extent in horizontalExtents(
                    of: line,
                    width: lineMetrics[i].width,
                    overlapStart: overlapStart,
                    overlapEnd: overlapEnd,
                    lineStart: lineStart,
                    lineEnd: lineEnd
                ) {
                    block(CGRect(
                        x: lineBox.minX + extent.lowerBound,
                        y: lineBox.minY,
                        width: extent.upperBound - extent.lowerBound,
                        height: lineBox.height
                    ))
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
        /// measured glyph by glyph.
        private func horizontalExtents(
            of line: CTLine,
            width: CGFloat,
            overlapStart: CFIndex,
            overlapEnd: CFIndex,
            lineStart: CFIndex,
            lineEnd: CFIndex
        ) -> [ClosedRange<CGFloat>] {
            let glyphRuns = CTLineGetGlyphRuns(line) as NSArray
            if Self.runsAreVisuallyOrdered(glyphRuns) {
                let startOffset = overlapStart > lineStart
                    ? CTLineGetOffsetForStringIndex(line, overlapStart, nil)
                    : 0
                let endOffset = overlapEnd < lineEnd
                    ? CTLineGetOffsetForStringIndex(line, overlapEnd, nil)
                    : width
                return [startOffset ... max(startOffset, endOffset)]
            }

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

                for glyphIndex in 0 ..< glyphCount {
                    let stringIndex = stringIndices[glyphIndex]
                    guard stringIndex >= overlapStart, stringIndex < overlapEnd else { continue }
                    let minX = positions[glyphIndex].x
                    let maxX = minX + advances[glyphIndex].width
                    extents.append(min(minX, maxX) ... max(minX, maxX))
                }
            }

            // Glyphs that touch visually share one rect.
            extents.sort { $0.lowerBound < $1.lowerBound }
            var merged = [ClosedRange<CGFloat>]()
            for extent in extents {
                if let last = merged.last, extent.lowerBound <= last.upperBound + 0.5 {
                    merged[merged.count - 1] = last.lowerBound ... max(last.upperBound, extent.upperBound)
                } else {
                    merged.append(extent)
                }
            }
            return merged
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

            // A measurement pass over the same width already laid out every line;
            // reuse it and translate the origins into the container's height.
            if adoptMeasurementFillIfMatching() {
                return
            }

            // CoreText fills a frame only as far as its path allows and silently
            // discards the lines beyond it. A host whose height trails its content
            // — a resize, a pending measurement — would lose the tail of the text
            // along with every attachment and run living there, so the path is
            // grown to whatever the text needs. Text stays anchored to the top of
            // `containerSize`, so lines past the container simply fall outside the
            // view and are clipped rather than lost.
            let naturalHeight = naturalHeight(forWidth: containerSize.width)

            // Measuring the natural height may itself have laid out a frame at this
            // width; adopting it avoids typesetting the same text a second time.
            if adoptMeasurementFillIfMatching() {
                return
            }

            var pathSize = containerSize
            pathSize.height = min(
                max(containerSize.height, naturalHeight),
                Self.maxLayoutDimension
            )
            adopt(makeFrameFill(constraint: pathSize, clampsToMaxLayoutDimension: false))
        }

        private func adoptMeasurementFillIfMatching() -> Bool {
            guard let fill = measurementFill,
                  fill.isComplete,
                  fill.pathSize.width == containerSize.width,
                  containerSize.height <= Self.maxLayoutDimension
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

            let offsetY = containerSize.height - fill.pathSize.height
            if offsetY == 0 {
                lineOrigins = fill.lineOrigins
            } else {
                lineOrigins = fill.lineOrigins.map {
                    CGPoint(x: $0.x, y: $0.y + offsetY)
                }
            }
        }

        /// The height the text needs at `width`, unconstrained vertically.
        private func naturalHeight(forWidth width: CGFloat) -> CGFloat {
            sizeThatFits(CGSize(
                width: width,
                height: Self.maxLayoutDimension
            )).height
        }

        private func makeFrameFill(constraint: CGSize, clampsToMaxLayoutDimension: Bool) -> FrameFill {
            var pathSize = constraint
            if clampsToMaxLayoutDimension {
                pathSize.width = min(pathSize.width, Self.maxLayoutDimension)
                pathSize.height = min(pathSize.height, Self.maxLayoutDimension)
            }
            let containerPath = CGPath(
                rect: CGRect(origin: .zero, size: pathSize),
                transform: nil
            )
            let ctFrame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: 0, length: 0),
                containerPath,
                nil
            )

            let frameLines = (CTFrameGetLines(ctFrame) as? [CTLine]) ?? []
            var origins = [CGPoint](repeating: .zero, count: frameLines.count)
            if !frameLines.isEmpty {
                CTFrameGetLineOrigins(ctFrame, CFRange(location: 0, length: 0), &origins)
            }

            var metrics = [LineMetrics]()
            metrics.reserveCapacity(frameLines.count)
            var maxLineTrailingX: CGFloat = 0
            var minLineY = pathSize.height
            for index in 0 ..< frameLines.count {
                let line = frameLines[index]
                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                var leading: CGFloat = 0
                let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
                metrics.append(LineMetrics(ascent: ascent, descent: descent, leading: leading, width: width))

                let trailingWhitespace = CGFloat(CTLineGetTrailingWhitespaceWidth(line))
                maxLineTrailingX = max(maxLineTrailingX, origins[index].x + width - trailingWhitespace)
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
                isComplete: isComplete
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
            guard let lines, let lineOrigins, let lineMetrics, !lines.isEmpty else { return 0 ..< 0 }
            guard let visibleRect, !visibleRect.isNull else { return 0 ..< lines.count }

            // Line origins live in CoreText's bottom-left space; the visible rect
            // is top-left based against the same containerSize used by draw(in:).
            let layoutRect = layoutRect(fromViewRect: visibleRect)

            var first = lines.count
            var lastExclusive = 0
            for index in 0 ..< lines.count {
                let lineBox = lineMetrics[index].rect(at: lineOrigins[index])
                if lineBox.minY > layoutRect.maxY {
                    continue
                }
                // Lines only descend from here on, so the remainder is offscreen.
                if lineBox.maxY < layoutRect.minY {
                    break
                }
                if index < first {
                    first = index
                }
                lastExclusive = index + 1
            }
            guard first < lastExclusive else { return 0 ..< 0 }

            // Glyph ink can slightly overshoot typographic bounds; include one
            // extra line on each side so partial redraws never clip an overhang.
            return max(0, first - 1) ..< min(lines.count, lastExclusive + 1)
        }

        private func extractHighlightRegions() {
            guard let lines else { return }
            enumerateRuns(
                inLines: 0 ..< lines.count,
                carrying: Self.highlightRunKeys
            ) { _, _, lineOrigin, glyphRun in
                // Bridging the attribute dictionary into Swift is expensive, so
                // it is reserved for the few runs carrying highlight attributes.
                let attributes = CTRunGetAttributes(glyphRun) as? [NSAttributedString.Key: Any] ?? [:]
                processHighlightRegionForRun(
                    glyphRun,
                    attributes: attributes,
                    lineOrigin: lineOrigin
                )
            }
        }

        @inline(__always)
        private static func runAttributeValue(_ run: CTRun, _ key: CFString) -> AnyObject? {
            let attributes = CTRunGetAttributes(run)
            guard let value = CFDictionaryGetValue(
                attributes,
                Unmanaged.passUnretained(key).toOpaque()
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
            where predicate: (Any) -> Bool
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
            lineOrigin: CGPoint
        ) {
            let stringRange = NSRange(CTRunGetStringRange(glyphRun))
            let runBounds = runBoundingRect(glyphRun, lineOrigin: lineOrigin)

            for attribute in Self.highlightAttributes where attributes[attribute.key] != nil {
                var effectiveRange = NSRange()
                _ = attributedString.attribute(
                    attribute.key,
                    at: stringRange.location,
                    longestEffectiveRange: &effectiveRange,
                    in: fullRange
                )
                addHighlightRegion(
                    kind: attribute.kind,
                    attributes: attributes,
                    stringRange: effectiveRange,
                    rect: runBounds
                )
            }
        }

        private func addHighlightRegion(
            kind: TextLabel.HighlightRegion.Kind,
            attributes: [NSAttributedString.Key: Any],
            stringRange: NSRange,
            rect: CGRect
        ) {
            let key = RegionKey(kind: kind, location: stringRange.location)
            let highlightRegion: TextLabel.HighlightRegion
            if let existingRegion = _highlightRegions[key] {
                highlightRegion = existingRegion
            } else {
                highlightRegion = TextLabel.HighlightRegion(
                    kind: kind,
                    attributes: attributes,
                    stringRange: stringRange
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
                height: ascent + descent
            )
        }

        // MARK: - Coordinate Conversion

        // Layout geometry uses CoreText's lower-left origin; views, visible rects and
        // attachment frames use a top-left origin. Both flip against
        // `containerSize.height`, the same height `draw(in:)` flips the context by,
        // so this is the only place the flip is written down.

        /// Converts a rect from layout space to top-left view space.
        ///
        /// Layout space is the lower-left-origin space of `rects(for:)`,
        /// `layoutRuns(matching:)` and `HighlightRegion.rects`. The flip uses
        /// `containerSize.height`, so it matches what `draw(in:)` paints.
        public func viewRect(fromLayoutRect rect: CGRect) -> CGRect {
            var result = rect
            result.origin.y = containerSize.height - rect.origin.y - rect.size.height
            return result
        }

        /// Converts a rect from top-left view space to layout space.
        public func layoutRect(fromViewRect rect: CGRect) -> CGRect {
            CGRect(
                x: rect.minX,
                y: containerSize.height - rect.maxY,
                width: rect.width,
                height: rect.height
            )
        }

        /// Converts a point from top-left view space to layout space.
        public func layoutPoint(fromViewPoint point: CGPoint) -> CGPoint {
            CGPoint(x: point.x, y: containerSize.height - point.y)
        }

        // MARK: - Text Index Helpers

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

        open func nearestTextIndex(at point: CGPoint) -> Int? {
            guard let hit = findLineContainingPoint(point) ?? nearestLine(to: point) else { return nil }
            return caretIndex(at: point, in: hit)
        }

        /// The index of the character under `point` on the nearest line, for word
        /// and line selection.
        ///
        /// `nearestTextIndex(at:)` returns a caret index, which past a line's
        /// trailing edge is the first character of the next line. This one stays
        /// on the hit line's last character instead.
        func characterIndex(at point: CGPoint) -> Int? {
            guard let hit = findLineContainingPoint(point) ?? nearestLine(to: point) else { return nil }
            let lineRange = CTLineGetStringRange(hit.line)
            let lastCharacter = lineRange.location + max(lineRange.length - 1, 0)
            return min(caretIndex(at: point, in: hit), lastCharacter)
        }

        // MARK: - Private Text Index Helpers

        private func nearestLine(to point: CGPoint) -> LineHit? {
            guard let lines, let lineOrigins, !lines.isEmpty else { return nil }

            if point.y > lineOrigins[0].y {
                return LineHit(line: lines[0], origin: lineOrigins[0])
            }

            let lastIndex = lines.count - 1
            if point.y < lineOrigins[lastIndex].y {
                return LineHit(line: lines[lastIndex], origin: lineOrigins[lastIndex])
            }

            var closestLineIndex = 0
            if let lineMetrics {
                var minDistance = CGFloat.greatestFiniteMagnitude
                for i in 0 ..< lines.count {
                    let distance = abs(point.y - lineMetrics[i].rect(at: lineOrigins[i]).midY)
                    if distance < minDistance {
                        minDistance = distance
                        closestLineIndex = i
                    }
                }
            }

            return LineHit(line: lines[closestLineIndex], origin: lineOrigins[closestLineIndex])
        }

        private func findLineContainingPoint(_ point: CGPoint) -> LineHit? {
            guard let lines, let lineOrigins, let lineMetrics else { return nil }

            for i in 0 ..< lines.count {
                let lineBox = lineMetrics[i].rect(at: lineOrigins[i])
                if point.y >= lineBox.minY, point.y <= lineBox.maxY {
                    return LineHit(line: lines[i], origin: lineOrigins[i])
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
