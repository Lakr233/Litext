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
}

private struct FrameFill {
    var lines: [CTLine]
    var lineOrigins: [CGPoint]
    var lineMetrics: [LineMetrics]
    var pathSize: CGSize
    var measuredSize: CGSize
    var isComplete: Bool
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
        private var naturalSizeCache: CGSize?
        private var measurementFill: FrameFill?

        private lazy var hasLineDrawingActions: Bool = attributedStringHasLineDrawingActions()
        private lazy var usesFrameDerivedMeasurement: Bool = frameDerivedMeasurementIsSafe()

        /// CoreText positions lines from the top of the layout path, so an
        /// unconstrained measurement only needs a path comfortably taller than any
        /// real container while keeping line origins in a precise double range.
        private static let maxLayoutDimension: CGFloat = 1_000_000

        private static let linkRunKey = NSAttributedString.Key.link.rawValue as CFString
        private static let attachmentRunKey = NSAttributedString.Key.litextAttachment.rawValue as CFString
        private static let lineDrawingRunKey = NSAttributedString.Key.litextLineDrawingAction.rawValue as CFString

        public init(attributedString: NSAttributedString) {
            self.attributedString = attributedString
            containerSize = .zero
            framesetter = CTFramesetterCreateWithAttributedString(
                attributedString
            )
            _highlightRegions = [:]
            super.init()
        }

        /// Regenerates CoreText lines for the current `containerSize`.
        ///
        /// `containerSize` already triggers layout regeneration when assigned. Call this only after
        /// external state referenced by run delegates or custom drawing callbacks changes.
        open func invalidateLayout() {
            suggestedSizeCache = nil
            naturalSizeCache = nil
            measurementFill = nil
            generateLayout()
        }

        open func sizeThatFits(_ size: CGSize) -> CGSize {
            if let suggestedSizeCache, suggestedSizeCache.input == size {
                return suggestedSizeCache.output
            }

            // Fast path: once the unconstrained (natural) size is known, any constraint
            // that already fits it cannot change line breaking, so the framesetter pass
            // can be skipped for those queries.
            if let naturalSizeCache,
               naturalSizeCache.width <= size.width,
               naturalSizeCache.height <= size.height
            {
                suggestedSizeCache = (input: size, output: naturalSizeCache)
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
            suggestedSizeCache = (input: size, output: suggestedSize)
            return suggestedSize
        }

        open func draw(in context: CGContext) {
            draw(in: context, visibleRect: nil)
        }

        /// Draws the laid-out text, restricted to the lines intersecting `visibleRect`.
        ///
        /// The rect uses a top-left origin in the same space as `containerSize`, matching the
        /// dirty rect handed to a view's `draw(_:)`. Passing `nil` draws every line.
        ///
        /// Line drawing actions are always invoked for every laid-out line. They may synchronize
        /// external views with text layout, so dirty-rect culling must not skip them.
        open func draw(in context: CGContext, visibleRect: CGRect?) {
            guard let lines, let lineOrigins, !lines.isEmpty else { return }

            let textLineIndices = lineIndices(intersecting: visibleRect)
            guard !textLineIndices.isEmpty || hasLineDrawingActions else { return }

            context.saveGState()

            context.setAllowsAntialiasing(true)
            context.textMatrix = .identity

            context.translateBy(x: 0, y: containerSize.height)
            context.scaleBy(x: 1, y: -1)

            for index in textLineIndices {
                context.textPosition = lineOrigins[index]
                CTLineDraw(lines[index], context)
            }
            processLineDrawingActions(in: context, lineIndices: 0 ..< lines.count)

            context.restoreGState()
        }

        /// The number of laid-out lines intersecting `rect`; `nil` counts every line.
        open func visibleLineCount(in rect: CGRect?) -> Int {
            lineIndices(intersecting: rect).count
        }

        private func processLineDrawingActions(in context: CGContext, lineIndices: Range<Int>) {
            guard hasLineDrawingActions, let lines, let lineOrigins else { return }

            for index in lineIndices {
                let line = lines[index]
                let lineOrigin = lineOrigins[index]
                let glyphRuns = CTLineGetGlyphRuns(line) as NSArray
                for runIndex in 0 ..< glyphRuns.count {
                    let glyphRun = glyphRuns[runIndex] as! CTRun
                    guard let action = Self.runAttributeValue(glyphRun, Self.lineDrawingRunKey)
                        as? TextLabel.LineDrawingAction
                    else { continue }
                    context.saveGState()
                    action.action(context, line, lineOrigin)
                    context.restoreGState()
                }
            }
        }

        open func updateHighlightRegions() {
            _highlightRegions.removeAll()
            extractHighlightRegions()
            _highlightRegionsArray = Array(_highlightRegions.values)
        }

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

            for i in 0 ..< lines.count {
                let line = lines[i]
                let lineRange = CTLineGetStringRange(line)

                let lineStart = lineRange.location
                let lineEnd = lineStart + lineRange.length
                let selStart = range.location
                let selEnd = selStart + range.length

                if selEnd < lineStart || selStart > lineEnd {
                    continue
                }

                let overlapStart = max(lineStart, selStart)
                let overlapEnd = min(lineEnd, selEnd)

                if overlapStart >= overlapEnd {
                    continue
                }

                calculateAndAddTextRect(
                    for: line,
                    origin: lineOrigins[i],
                    metrics: lineMetrics[i],
                    overlapStart: overlapStart,
                    overlapEnd: overlapEnd,
                    lineStart: lineStart,
                    lineEnd: lineEnd,
                    using: block
                )
            }
        }

        private func calculateAndAddTextRect(
            for line: CTLine,
            origin: CGPoint,
            metrics: LineMetrics,
            overlapStart: CFIndex,
            overlapEnd: CFIndex,
            lineStart: CFIndex,
            lineEnd: CFIndex,
            using block: (CGRect) -> Void
        ) {
            var startOffset: CGFloat = 0
            var endOffset: CGFloat = 0

            if overlapStart > lineStart {
                startOffset = CTLineGetOffsetForStringIndex(
                    line,
                    overlapStart,
                    nil
                )
            }

            if overlapEnd < lineEnd {
                endOffset = CTLineGetOffsetForStringIndex(
                    line,
                    overlapEnd,
                    nil
                )
            } else {
                endOffset = metrics.width
            }

            let rect = CGRect(
                x: origin.x + startOffset,
                y: origin.y - metrics.descent,
                width: endOffset - startOffset,
                height: metrics.ascent + metrics.descent + metrics.leading
            )

            block(rect)
        }

        // MARK: - Private Methods

        private func generateLayout() {
            lines = nil
            lineOrigins = nil
            lineMetrics = nil

            // A measurement pass over the same width already laid out every line;
            // reuse it and translate the origins into the container's height.
            if let fill = measurementFill,
               fill.isComplete,
               fill.pathSize.width == containerSize.width,
               fill.measuredSize.height <= containerSize.height,
               containerSize.height <= Self.maxLayoutDimension
            {
                let offsetY = containerSize.height - fill.pathSize.height
                lines = fill.lines
                lineMetrics = fill.lineMetrics
                if offsetY == 0 {
                    lineOrigins = fill.lineOrigins
                } else {
                    lineOrigins = fill.lineOrigins.map {
                        CGPoint(x: $0.x, y: $0.y + offsetY)
                    }
                }
                return
            }

            let fill = makeFrameFill(constraint: containerSize, clampsToMaxLayoutDimension: false)
            lines = fill.lines
            lineOrigins = fill.lineOrigins
            lineMetrics = fill.lineMetrics
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
            // justified, or right-to-left content keeps the suggestion pass.
            var isSafe = true
            attributedString.enumerateAttribute(
                .paragraphStyle,
                in: NSRange(location: 0, length: attributedString.length),
                options: []
            ) { value, _, stop in
                guard let style = value as? NSParagraphStyle else { return }
                let alignmentIsSafe = style.alignment == .left || style.alignment == .natural
                if !alignmentIsSafe || style.baseWritingDirection == .rightToLeft {
                    isSafe = false
                    stop.pointee = true
                }
            }
            guard isSafe else { return false }

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
            let lowerBound = containerSize.height - visibleRect.maxY
            let upperBound = containerSize.height - visibleRect.minY

            var first = lines.count
            var lastExclusive = 0
            for index in 0 ..< lines.count {
                let origin = lineOrigins[index]
                let metrics = lineMetrics[index]
                let lineTop = origin.y + metrics.ascent
                let lineBottom = origin.y - metrics.descent - metrics.leading
                if lineBottom > upperBound { continue }
                // Lines only descend from here on, so the remainder is offscreen.
                if lineTop < lowerBound { break }
                if index < first { first = index }
                lastExclusive = index + 1
            }
            guard first < lastExclusive else { return 0 ..< 0 }

            // Glyph ink can slightly overshoot typographic bounds; include one
            // extra line on each side so partial redraws never clip an overhang.
            return max(0, first - 1) ..< min(lines.count, lastExclusive + 1)
        }

        private func extractHighlightRegions() {
            enumerateLines { line, _, lineOrigin in
                let glyphRuns = CTLineGetGlyphRuns(line) as NSArray
                for runIndex in 0 ..< glyphRuns.count {
                    let glyphRun = glyphRuns[runIndex] as! CTRun
                    guard Self.runAttributeValue(glyphRun, Self.linkRunKey) != nil
                        || Self.runAttributeValue(glyphRun, Self.attachmentRunKey) != nil
                    else { continue }

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

        private func attributedStringHasLineDrawingActions() -> Bool {
            guard attributedString.length > 0 else { return false }

            var hasAction = false
            attributedString.enumerateAttribute(
                .litextLineDrawingAction,
                in: NSRange(location: 0, length: attributedString.length),
                options: []
            ) { value, _, stop in
                if value is TextLabel.LineDrawingAction {
                    hasAction = true
                    stop.pointee = true
                }
            }
            return hasAction
        }

        private func processHighlightRegionForRun(
            _ glyphRun: CTRun,
            attributes: [NSAttributedString.Key: Any],
            lineOrigin: CGPoint
        ) {
            let cfStringRange = CTRunGetStringRange(glyphRun)
            let stringRange = NSRange(
                location: cfStringRange.location,
                length: cfStringRange.length
            )

            var runBounds = CTRunGetImageBounds(
                glyphRun,
                nil,
                CFRange(location: 0, length: 0)
            )

            if let attachment = attributes[
                .litextAttachment
            ] as? TextLabel.Attachment {
                runBounds.size = attachment.size
                runBounds.origin.y -= attachment.size.height * TextLabel.Attachment.descentFraction
            }

            runBounds.origin.x += lineOrigin.x
            runBounds.origin.y += lineOrigin.y

            if attributes[.link] != nil {
                var linkRange = NSRange()
                _ = attributedString.attribute(
                    .link,
                    at: stringRange.location,
                    longestEffectiveRange: &linkRange,
                    in: NSRange(location: 0, length: attributedString.length)
                )
                addHighlightRegion(
                    kind: .link,
                    attributes: attributes,
                    stringRange: linkRange,
                    rect: runBounds
                )
            }

            if attributes[.litextAttachment] != nil {
                var attachmentRange = NSRange()
                _ = attributedString.attribute(
                    .litextAttachment,
                    at: stringRange.location,
                    longestEffectiveRange: &attachmentRange,
                    in: NSRange(location: 0, length: attributedString.length)
                )
                addHighlightRegion(
                    kind: .attachment,
                    attributes: attributes,
                    stringRange: attachmentRange,
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

        private func enumerateLines(
            using block: (CTLine, Int, CGPoint) -> Void
        ) {
            guard let lines, let lineOrigins else { return }

            for i in 0 ..< lines.count {
                let line = lines[i]
                let origin = lineOrigins[i]
                block(line, i, origin)
            }
        }

        // MARK: - Text Index Helpers

        open func textIndex(at point: CGPoint) -> Int? {
            guard let lines, let lineOrigins else { return nil }

            if let lineInfo = findLineContainingPoint(point) {
                return findCharacterIndexInLine(point, lineInfo: lineInfo)
            }

            guard !lines.isEmpty else { return nil }

            guard point.y < lineOrigins[lines.count - 1].y else { return nil }
            let lastLine = lines[lines.count - 1]
            let range = CTLineGetStringRange(lastLine)
            return range.location + range.length
        }

        open func nearestTextIndex(at point: CGPoint) -> Int? {
            guard let lines, let lineOrigins else { return nil }

            if let lineInfo = findLineContainingPoint(point) {
                return findCharacterIndexInLine(point, lineInfo: lineInfo)
            }

            guard !lines.isEmpty else { return nil }

            guard let lineInfo = nearestLineInfo(to: point, lines: lines, lineOrigins: lineOrigins) else {
                return nil
            }

            return findCharacterIndexInLine(point, lineInfo: lineInfo)
        }

        // MARK: - Private Text Index Helpers

        private func nearestLineInfo(
            to point: CGPoint,
            lines: [CTLine],
            lineOrigins: [CGPoint]
        ) -> (line: CTLine, origin: CGPoint, index: Int)? {
            if point.y > lineOrigins[0].y {
                return (line: lines[0], origin: lineOrigins[0], index: 0)
            }

            let lastIndex = lines.count - 1
            if point.y < lineOrigins[lastIndex].y {
                return (line: lines[lastIndex], origin: lineOrigins[lastIndex], index: lastIndex)
            }

            var closestLineIndex = 0
            var minDistance = CGFloat.greatestFiniteMagnitude

            for i in 0 ..< lines.count {
                let origin = lineOrigins[i]
                guard let metrics = lineMetrics?[i] else { continue }

                let lineMiddleY = origin.y - metrics.descent + (metrics.ascent + metrics.descent) / 2
                let distance = abs(point.y - lineMiddleY)

                if distance < minDistance {
                    minDistance = distance
                    closestLineIndex = i
                }
            }

            return (
                line: lines[closestLineIndex],
                origin: lineOrigins[closestLineIndex],
                index: closestLineIndex
            )
        }

        private func findLineContainingPoint(
            _ point: CGPoint
        ) -> (line: CTLine, origin: CGPoint, index: Int)? {
            guard let lines, let lineOrigins, let lineMetrics else { return nil }

            for i in 0 ..< lines.count {
                let origin = lineOrigins[i]
                let metrics = lineMetrics[i]
                let lineHeight = metrics.ascent + metrics.descent + metrics.leading

                let lineRect = CGRect(
                    x: origin.x,
                    y: origin.y - metrics.descent,
                    width: metrics.width,
                    height: lineHeight
                )

                if point.y >= lineRect.minY, point.y <= lineRect.maxY {
                    return (line: lines[i], origin: origin, index: i)
                }
            }

            return nil
        }

        private func findCharacterIndexInLine(
            _ point: CGPoint,
            lineInfo: (line: CTLine, origin: CGPoint, index: Int)
        ) -> Int {
            let line = lineInfo.line
            let lineOrigin = lineInfo.origin
            let lineRange = CTLineGetStringRange(line)
            let linePoint = CGPoint(x: point.x - lineOrigin.x, y: 0)
            let index = CTLineGetStringIndexForPosition(line, linePoint)
            return index == kCFNotFound ? lineRange.location + lineRange.length : index
        }
    }
}
