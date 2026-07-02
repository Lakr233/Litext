//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreGraphics
import CoreText
import Foundation
import QuartzCore

private func _hasHighlightAttributes(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
    if attributes[.link] != nil {
        return true
    }
    if attributes[LTXAttachmentAttributeName] != nil {
        return true
    }
    return false
}

private struct RegionKey: Hashable {
    let kind: LTXHighlightRegion.Kind
    let location: Int
}

@MainActor
public class LTXTextLayout: NSObject {
    public private(set) var attributedString: NSAttributedString
    public var highlightRegions: [LTXHighlightRegion] {
        _highlightRegionsArray
    }

    public var containerSize: CGSize {
        didSet {
            generateLayout()
        }
    }

    private var ctFrame: CTFrame?

    private var framesetter: CTFramesetter
    private var hasLineDrawingActions = false
    private var lines: [CTLine]?
    private var lineOrigins: [CGPoint]?
    private var _highlightRegions: [RegionKey: LTXHighlightRegion]
    private var _highlightRegionsArray: [LTXHighlightRegion] = []
    private var suggestedSizeCache: (input: CGSize, output: CGSize)?
    private var naturalSizeCache: CGSize?

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
    public func invalidateLayout() {
        suggestedSizeCache = nil
        naturalSizeCache = nil
        generateLayout()
    }

    public func suggestContainerSize(withSize size: CGSize) -> CGSize {
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

        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            size,
            nil
        )
        if size.width == CGFloat.greatestFiniteMagnitude, size.height == CGFloat.greatestFiniteMagnitude {
            naturalSizeCache = suggestedSize
        }
        suggestedSizeCache = (input: size, output: suggestedSize)
        return suggestedSize
    }

    public func draw(in context: CGContext) {
        context.saveGState()

        context.setAllowsAntialiasing(true)

        context.translateBy(x: 0, y: containerSize.height)
        context.scaleBy(x: 1, y: -1)

        if let ctFrame {
            CTFrameDraw(ctFrame, context)
            processLineDrawingActions(in: context)
        }

        context.restoreGState()
    }

    private func processLineDrawingActions(in context: CGContext) {
        guard hasLineDrawingActions else { return }

        enumerateLines { line, _, lineOrigin in
            enumerateRuns(in: line) { _, attributes in
                if let action = attributes[LTXLineDrawingCallbackName] as? LTXLineDrawingAction {
                    context.saveGState()
                    action.action(context, line, lineOrigin)
                    context.restoreGState()
                }
            }
        }
    }

    public func updateHighlightRegions() {
        _highlightRegions.removeAll()
        extractHighlightRegions()
        _highlightRegionsArray = Array(_highlightRegions.values)
    }

    public func rects(for range: NSRange) -> [CGRect] {
        var rects = [CGRect]()
        enumerateTextRects(in: range) { rect in
            rects.append(rect)
        }
        return rects
    }

    public func enumerateTextRects(in range: NSRange, using block: (CGRect) -> Void) {
        guard let range = NSRange.sanitized(range, within: attributedString.length),
              let lines,
              let lineOrigins
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
            endOffset = CTLineGetTypographicBounds(
                line,
                nil,
                nil,
                nil
            )
        }

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        CTLineGetTypographicBounds(
            line,
            &ascent,
            &descent,
            &leading
        )

        let rect = CGRect(
            x: origin.x + startOffset,
            y: origin.y - descent,
            width: endOffset - startOffset,
            height: ascent + descent + leading
        )

        block(rect)
    }

    // MARK: - Private Methods

    private func generateLayout() {
        lines = nil
        lineOrigins = nil
        hasLineDrawingActions = attributedStringHasLineDrawingActions()

        let containerBounds = CGRect(
            origin: .zero,
            size: containerSize
        )
        let containerPath = CGPath(
            rect: containerBounds,
            transform: nil
        )
        ctFrame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            containerPath,
            nil
        )

        if let ctFrame {
            let frameLines = CTFrameGetLines(ctFrame) as? [CTLine]
            lines = frameLines
            if let frameLines {
                var origins = [CGPoint](repeating: .zero, count: frameLines.count)
                CTFrameGetLineOrigins(ctFrame, CFRange(location: 0, length: 0), &origins)
                lineOrigins = origins
            }
        }
    }

    private func extractHighlightRegions() {
        enumerateLines { line, _, lineOrigin in
            enumerateRuns(in: line) { glyphRun, attributes in
                guard _hasHighlightAttributes(attributes) else { return }

                processHighlightRegionForRun(
                    glyphRun,
                    attributes: attributes,
                    lineOrigin: lineOrigin
                )
            }
        }
    }

    private func enumerateRuns(
        in line: CTLine,
        using block: (CTRun, [NSAttributedString.Key: Any]) -> Void
    ) {
        let glyphRuns = CTLineGetGlyphRuns(line) as NSArray

        for index in 0 ..< glyphRuns.count {
            let glyphRun = glyphRuns[index] as! CTRun
            let attributes = CTRunGetAttributes(glyphRun) as? [NSAttributedString.Key: Any] ?? [:]
            block(glyphRun, attributes)
        }
    }

    private func attributedStringHasLineDrawingActions() -> Bool {
        guard attributedString.length > 0 else { return false }

        var hasAction = false
        attributedString.enumerateAttribute(
            LTXLineDrawingCallbackName,
            in: NSRange(location: 0, length: attributedString.length),
            options: []
        ) { value, _, stop in
            if value is LTXLineDrawingAction {
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
            LTXAttachmentAttributeName
        ] as? LTXAttachment {
            runBounds.size = attachment.size
            runBounds.origin.y -= attachment.size.height * LTXAttachment.descentFraction
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

        if attributes[LTXAttachmentAttributeName] != nil {
            var attachmentRange = NSRange()
            _ = attributedString.attribute(
                LTXAttachmentAttributeName,
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
        kind: LTXHighlightRegion.Kind,
        attributes: [NSAttributedString.Key: Any],
        stringRange: NSRange,
        rect: CGRect
    ) {
        let key = RegionKey(kind: kind, location: stringRange.location)
        let highlightRegion: LTXHighlightRegion
        if let existingRegion = _highlightRegions[key] {
            highlightRegion = existingRegion
        } else {
            highlightRegion = LTXHighlightRegion(
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

    public func textIndex(at point: CGPoint) -> Int? {
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

    public func nearestTextIndex(at point: CGPoint) -> Int? {
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
            let line = lines[i]
            let origin = lineOrigins[i]
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0

            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

            let lineMiddleY = origin.y - descent + (ascent + descent) / 2
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
        guard let lines, let lineOrigins else { return nil }

        for i in 0 ..< lines.count {
            let origin = lineOrigins[i]
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0

            let line = lines[i]
            let lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let lineHeight = ascent + descent + leading

            let lineRect = CGRect(
                x: origin.x,
                y: origin.y - descent,
                width: lineWidth,
                height: lineHeight
            )

            if point.y >= lineRect.minY, point.y <= lineRect.maxY {
                return (line: line, origin: origin, index: i)
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
