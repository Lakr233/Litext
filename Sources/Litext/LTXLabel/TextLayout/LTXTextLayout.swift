//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreGraphics
import CoreText
import Foundation
import QuartzCore

private let kTruncationToken = "\u{2026}"

private func _hasHighlightAttributes(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
    if attributes[.link] != nil {
        return true
    }
    if attributes[LTXAttachmentAttributeName] != nil {
        return true
    }
    return false
}

private func _createTruncatedLine(
    lastLine: CTLine,
    attrString: NSAttributedString,
    width: CGFloat
) -> CTLine? {
    let truncationTokenAttributes = extractTruncationAttributes(from: lastLine)

    let truncationTokenString = NSAttributedString(
        string: kTruncationToken,
        attributes: truncationTokenAttributes
    )
    let truncationLine = CTLineCreateWithAttributedString(
        truncationTokenString
    )

    let lastLineStringRange = CTLineGetStringRange(lastLine)
    let nsRange = NSRange(
        location: lastLineStringRange.location,
        length: lastLineStringRange.length
    )

    let lastLineString = NSMutableAttributedString(
        attributedString: attrString.attributedSubstring(
            from: nsRange
        )
    )
    lastLineString.append(truncationTokenString)
    let newLastLine = CTLineCreateWithAttributedString(
        lastLineString
    )

    let truncatedLine = CTLineCreateTruncatedLine(
        newLastLine,
        width,
        .end,
        truncationLine
    )

    return truncatedLine
}

private func extractTruncationAttributes(
    from line: CTLine
) -> [NSAttributedString.Key: Any] {
    var attributes: [NSAttributedString.Key: Any] = [:]

    let lastLineGlyphRuns = CTLineGetGlyphRuns(line) as NSArray
    if let lastGlyphRun = lastLineGlyphRuns.lastObject as! CTRun? {
        let lastRunAttributes = CTRunGetAttributes(lastGlyphRun) as! [NSAttributedString.Key: Any]

        if let font = lastRunAttributes[.font] {
            attributes[.font] = font
        }
        if let foregroundColor = lastRunAttributes[.foregroundColor] {
            attributes[.foregroundColor] = foregroundColor
        }
        if let paragraphStyle = lastRunAttributes[.paragraphStyle] {
            attributes[.paragraphStyle] = paragraphStyle
        }
    }

    return attributes
}

public class LTXTextLayout: NSObject {
    public private(set) var attributedString: NSAttributedString
    public var highlightRegions: [LTXHighlightRegion] {
        Array(_highlightRegions.values)
    }

    public var containerSize: CGSize {
        didSet {
            generateLayout()
        }
    }

    var ctFrame: CTFrame?

    private var framesetter: CTFramesetter
    private var lines: [CTLine]?
    private var _highlightRegions: [Int: LTXHighlightRegion]
    private var lineDrawingActions: Set<LTXLineDrawingAction> = []

    public class func textLayout(
        withAttributedString attributedString: NSAttributedString
    ) -> LTXTextLayout {
        LTXTextLayout(attributedString: attributedString)
    }

    public init(attributedString: NSAttributedString) {
        self.attributedString = attributedString
        containerSize = .zero
        framesetter = CTFramesetterCreateWithAttributedString(
            attributedString
        )
        _highlightRegions = [:]
        super.init()
    }

    deinit {}

    public func invalidateLayout() {
        generateLayout()
    }

    public func suggestContainerSize(withSize size: CGSize) -> CGSize {
        CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            size,
            nil
        )
    }

    public func draw(in context: CGContext) {
        lineDrawingActions.removeAll()

        context.saveGState()

        context.setAllowsAntialiasing(true)
        context.setShouldSmoothFonts(true)

        context.translateBy(x: 0, y: containerSize.height)
        context.scaleBy(x: 1, y: -1)

        if let ctFrame { CTFrameDraw(ctFrame, context) }

        processLineDrawingActions(in: context)

        context.restoreGState()
    }

    private func processLineDrawingActions(in context: CGContext) {
        enumerateLines { line, _, lineOrigin in
            let glyphRuns = CTLineGetGlyphRuns(line) as NSArray

            for i in 0 ..< glyphRuns.count {
                guard let glyphRun = glyphRuns[i] as! CTRun?
                else { continue }

                let attributes = CTRunGetAttributes(glyphRun) as! [NSAttributedString.Key: Any]
                if let action = attributes[LTXLineDrawingCallbackName] as? LTXLineDrawingAction {
                    if self.lineDrawingActions.contains(action) {
                        continue
                    }
                    context.saveGState()
                    action.action(context, line, lineOrigin)
                    context.restoreGState()
                    if action.performOncePerAttribute {
                        self.lineDrawingActions.insert(action)
                    }
                }
            }
        }
    }

    public func updateHighlightRegions(with context: CGContext) {
        _highlightRegions.removeAll()
        extractHighlightRegions(with: context)
    }

    public func rects(for range: NSRange) -> [CGRect] {
        var rects = [CGRect]()
        enumerateTextRects(in: range) { rect in
            rects.append(rect)
        }
        return rects
    }

    public func enumerateTextRects(in range: NSRange, using block: (CGRect) -> Void) {
        guard let ctFrame else { return }

        let lines = CTFrameGetLines(ctFrame) as NSArray
        let lineCount = lines.count
        var origins = [CGPoint](repeating: .zero, count: lineCount)
        CTFrameGetLineOrigins(ctFrame, CFRange(location: 0, length: 0), &origins)

        for i in 0 ..< lineCount {
            let line = lines[i] as! CTLine
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
                origin: origins[i],
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
            lines = CTFrameGetLines(ctFrame) as? [CTLine]
        }

        processTruncation(in: containerBounds)
    }

    private func processTruncation(in containerBounds: CGRect) {
        if let lines, let ctFrame {
            let visibleRange = CTFrameGetVisibleStringRange(
                ctFrame
            )
            if visibleRange.length == attributedString.length || lines.isEmpty {
                return
            }

            if let lastLine = lines.last,
               let truncatedLine = _createTruncatedLine(
                   lastLine: lastLine,
                   attrString: attributedString,
                   width: containerBounds.width
               )
            {
                var newLines = lines
                newLines[newLines.count - 1] = truncatedLine
                self.lines = newLines
            }
        }
    }

    private func extractHighlightRegions(with context: CGContext) {
        enumerateLines { line, _, lineOrigin in
            let glyphRuns = CTLineGetGlyphRuns(line) as NSArray

            for i in 0 ..< glyphRuns.count {
                guard let glyphRun = glyphRuns[i] as! CTRun? else { continue }

                let attributes = CTRunGetAttributes(
                    glyphRun
                ) as! [NSAttributedString.Key: Any]
                if !_hasHighlightAttributes(attributes) {
                    continue
                }

                processHighlightRegionForRun(
                    glyphRun,
                    attributes: attributes,
                    lineOrigin: lineOrigin,
                    with: context
                )
            }
        }
    }

    private func processHighlightRegionForRun(
        _ glyphRun: CTRun,
        attributes: [NSAttributedString.Key: Any],
        lineOrigin: CGPoint,
        with context: CGContext
    ) {
        let cfStringRange = CTRunGetStringRange(glyphRun)
        let stringRange = NSRange(
            location: cfStringRange.location,
            length: cfStringRange.length
        )

        var effectiveRange = NSRange()
        _ = attributedString.attributes(
            at: stringRange.location,
            effectiveRange: &effectiveRange
        )

        let highlightRegion: LTXHighlightRegion
        if let existingRegion = _highlightRegions[
            effectiveRange.location
        ] {
            highlightRegion = existingRegion
        } else {
            highlightRegion = LTXHighlightRegion(
                attributes: attributes,
                stringRange: stringRange
            )
            _highlightRegions[effectiveRange.location] = highlightRegion
        }

        var runBounds = CTRunGetImageBounds(
            glyphRun,
            context,
            CFRange(location: 0, length: 0)
        )

        if let attachment = attributes[LTXAttachmentAttributeName] as? LTXAttachment {
            let size = attachment.viewProvider.boundingSize(for: attachment)
            runBounds.size = size
            runBounds.origin.y -= size.height * 0.1
        }

        runBounds.origin.x += lineOrigin.x
        runBounds.origin.y += lineOrigin.y
        highlightRegion.addRect(runBounds)
    }

    private func enumerateLines(
        using block: (CTLine, Int, CGPoint) -> Void
    ) {
        guard let lines, let ctFrame else { return }

        let lineCount = lines.count
        var lineOrigins = [CGPoint](repeating: .zero, count: lineCount)
        CTFrameGetLineOrigins(
            ctFrame,
            CFRange(location: 0, length: 0),
            &lineOrigins
        )

        for i in 0 ..< lineCount {
            let line = lines[i]
            let origin = lineOrigins[i]
            block(line, i, origin)
        }
    }

    // MARK: - Text Index Helpers

    public func textIndex(at point: CGPoint) -> Int? {
        guard let ctFrame else { return nil }

        if let lineInfo = findLineContainingPoint(point, ctFrame: ctFrame) {
            return findCharacterIndexInLine(point, lineInfo: lineInfo)
        }

        let lines = CTFrameGetLines(ctFrame) as [AnyObject]
        guard !lines.isEmpty else { return nil }
        var lineOrigins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(ctFrame, CFRange(location: 0, length: 0), &lineOrigins)

        guard point.y < lineOrigins[lines.count - 1].y else { return nil }
        let lastLine = lines[lines.count - 1] as! CTLine
        let range = CTLineGetStringRange(lastLine)
        return range.location + range.length
    }

    public func nearestTextIndex(at point: CGPoint) -> Int? {
        guard let ctFrame else { return nil }

        if let lineInfo = findLineContainingPoint(point, ctFrame: ctFrame) {
            return findCharacterIndexInLine(point, lineInfo: lineInfo)
        }

        let lines = CTFrameGetLines(ctFrame) as [AnyObject]
        guard !lines.isEmpty else { return nil }

        var lineOrigins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(ctFrame, CFRange(location: 0, length: 0), &lineOrigins)

        // 如果点在文本上方
        if point.y > lineOrigins[0].y {
            let firstLine = lines[0] as! CTLine
            if point.x < lineOrigins[0].x {
                return CTLineGetStringRange(firstLine).location
            } else {
                let range = CTLineGetStringRange(firstLine)
                let lineWidth = CTLineGetTypographicBounds(firstLine, nil, nil, nil)
                if point.x > lineOrigins[0].x + lineWidth {
                    return range.location + range.length
                } else {
                    return findCharacterIndexInLine(point, lineInfo: (firstLine, lineOrigins[0], 0))
                }
            }
        }

        // 如果点在文本下方
        if point.y < lineOrigins[lines.count - 1].y {
            let lastLine = lines[lines.count - 1] as! CTLine
            if point.x < lineOrigins[lines.count - 1].x {
                return CTLineGetStringRange(lastLine).location
            } else {
                let range = CTLineGetStringRange(lastLine)
                let lineWidth = CTLineGetTypographicBounds(lastLine, nil, nil, nil)
                if point.x > lineOrigins[lines.count - 1].x + lineWidth {
                    return range.location + range.length
                } else {
                    return findCharacterIndexInLine(point, lineInfo: (lastLine, lineOrigins[lines.count - 1], lines.count - 1))
                }
            }
        }

        // 如果点在两行之间，找到最近的行
        var closestLineIndex = 0
        var minDistance = CGFloat.greatestFiniteMagnitude

        for i in 0 ..< lines.count {
            let line = lines[i] as! CTLine
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

        let closestLine = lines[closestLineIndex] as! CTLine
        let closestOrigin = lineOrigins[closestLineIndex]

        return findCharacterIndexInLine(point, lineInfo: (closestLine, closestOrigin, closestLineIndex))
    }

    // MARK: - Private Text Index Helpers

    private func findLineContainingPoint(
        _ point: CGPoint,
        ctFrame: CTFrame
    ) -> (line: CTLine, origin: CGPoint, index: Int)? {
        let lines = CTFrameGetLines(ctFrame) as [AnyObject]
        var lineOrigins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(ctFrame, CFRange(location: 0, length: 0), &lineOrigins)

        for i in 0 ..< lines.count {
            let origin = lineOrigins[i]
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0

            let line = lines[i] as! CTLine
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

        if point.x <= lineOrigin.x {
            return lineRange.location
        }

        for characterOffset in 0 ..< lineRange.length {
            let characterIndex = lineRange.location + characterOffset
            let positionOffset = CTLineGetOffsetForStringIndex(line, characterIndex, nil)

            if positionOffset >= point.x - lineOrigin.x {
                let distanceToNextChar = positionOffset - (point.x - lineOrigin.x)
                if characterOffset > 0 {
                    let previousCharIndex = characterIndex - 1
                    let previousPositionOffset = CTLineGetOffsetForStringIndex(line, previousCharIndex, nil)
                    let distanceToPrevChar = (point.x - lineOrigin.x) - previousPositionOffset
                    if distanceToNextChar > distanceToPrevChar {
                        return previousCharIndex
                    }
                }
                return characterIndex
            }
        }

        return lineRange.location + lineRange.length
    }
}
