//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreGraphics
import CoreText
import Foundation
import QuartzCore

public extension LTXLabel {
    @objc func clearSelection() {
        selectionRange = nil
        selectionLayer?.removeFromSuperlayer()
        selectionLayer = nil
    }

    @objc func copySelectedText() {
        guard let selectedText = selectedAttributedText() else { return }

        #if canImport(UIKit)
            UIPasteboard.general.string = selectedText.string
        #elseif canImport(AppKit)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(selectedText.string, forType: .string)
        #endif
    }
}

extension LTXLabel {
    func updateSelectinoRange(withLocation location: CGPoint) {
        guard let startIndex = nearestTextIndexAtPoint(interactionState.initialTouchLocation),
              let endIndex = nearestTextIndexAtPoint(location)
        else { return }
        selectionRange = NSRange(
            location: min(startIndex, endIndex),
            length: abs(endIndex - startIndex)
        )
    }

    func nearestTextIndexAtPoint(_ point: CGPoint) -> Int? {
        guard let textLayout,
              let ctFrame = textLayout.ctFrame
        else { return nil }

        let flippedPoint = CGPoint(
            x: point.x,
            y: bounds.height - point.y
        )

        if let lineInfo = findLineContainingPoint(
            flippedPoint,
            ctFrame: ctFrame
        ) {
            return findCharacterIndexInLine(
                flippedPoint,
                lineInfo: lineInfo
            )
        }

        let lines = CTFrameGetLines(ctFrame) as [AnyObject]
        guard !lines.isEmpty else { return nil }

        var lineOrigins = [CGPoint](
            repeating: .zero,
            count: lines.count
        )
        CTFrameGetLineOrigins(
            ctFrame,
            CFRange(location: 0, length: 0),
            &lineOrigins
        )

        if flippedPoint.y > lineOrigins[0].y {
            let firstLine = lines[0] as! CTLine
            if flippedPoint.x < lineOrigins[0].x {
                return CTLineGetStringRange(firstLine).location
            } else {
                let range = CTLineGetStringRange(firstLine)
                let lineWidth = CTLineGetTypographicBounds(firstLine, nil, nil, nil)
                if flippedPoint.x > lineOrigins[0].x + lineWidth {
                    return range.location + range.length
                } else {
                    return findCharacterIndexInLine(
                        flippedPoint,
                        lineInfo: (firstLine, lineOrigins[0], 0)
                    )
                }
            }
        }

        if flippedPoint.y < lineOrigins[lines.count - 1].y {
            let lastLine = lines[lines.count - 1] as! CTLine
            if flippedPoint.x < lineOrigins[lines.count - 1].x {
                return CTLineGetStringRange(lastLine).location
            } else {
                let range = CTLineGetStringRange(lastLine)
                let lineWidth = CTLineGetTypographicBounds(lastLine, nil, nil, nil)
                if flippedPoint.x > lineOrigins[lines.count - 1].x + lineWidth {
                    return range.location + range.length
                } else {
                    return findCharacterIndexInLine(
                        flippedPoint,
                        lineInfo: (lastLine, lineOrigins[lines.count - 1], lines.count - 1)
                    )
                }
            }
        }

        var closestLineIndex = 0
        var minDistance = CGFloat.greatestFiniteMagnitude

        for i in 0 ..< lines.count {
            let line = lines[i] as! CTLine
            let origin = lineOrigins[i]
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0

            CTLineGetTypographicBounds(
                line,
                &ascent,
                &descent,
                &leading
            )

            let lineMiddleY = origin.y - descent + (ascent + descent) / 2
            let distance = abs(flippedPoint.y - lineMiddleY)

            if distance < minDistance {
                minDistance = distance
                closestLineIndex = i
            }
        }

        let closestLine = lines[closestLineIndex] as! CTLine
        let closestOrigin = lineOrigins[closestLineIndex]

        return findCharacterIndexInLine(
            flippedPoint,
            lineInfo: (closestLine, closestOrigin, closestLineIndex)
        )
    }

    func textIndexAtPoint(_ point: CGPoint) -> Int? {
        guard let textLayout,
              let ctFrame = textLayout.ctFrame
        else { return nil }

        let flippedPoint = CGPoint(
            x: point.x,
            y: bounds.height - point.y
        )

        if let lineInfo = findLineContainingPoint(
            flippedPoint,
            ctFrame: ctFrame
        ) {
            return findCharacterIndexInLine(
                flippedPoint,
                lineInfo: lineInfo
            )
        }

        let lines = CTFrameGetLines(ctFrame) as [AnyObject]
        guard !lines.isEmpty else { return nil }
        var lineOrigins = [CGPoint](
            repeating: .zero,
            count: lines.count
        )
        CTFrameGetLineOrigins(
            ctFrame,
            CFRange(location: 0, length: 0),
            &lineOrigins
        )

        guard flippedPoint.y < lineOrigins[lines.count - 1].y else { return nil }
        let lastLine = lines[lines.count - 1] as! CTLine
        let range = CTLineGetStringRange(lastLine)
        return range.location + range.length
    }

    public func isLocationInSelection(location: CGPoint) -> Bool {
        guard let range = selectionRange,
              range.length > 0,
              let rects = textLayout?.rects(for: range)
        else { return false }
        return rects.contains { $0.contains(location) }
    }

    func selectedAttributedText() -> NSAttributedString? {
        guard let textLayout,
              let range = selectionRange,
              range.location != NSNotFound,
              range.length > 0,
              textLayout.attributedString.length > 0,
              range.location < textLayout.attributedString.length
        else {
            return nil
        }
        let maxLen = textLayout.attributedString.length - range.location

        let safeRange = NSRange(
            location: range.location,
            length: min(range.length, maxLen)
        )

        return textLayout
            .attributedString
            .attributedSubstring(from: safeRange)
    }

    func selectedPlainText() -> String? {
        selectedAttributedText()?.string
    }
}

private extension LTXLabel {
    func findLineContainingPoint(
        _ point: CGPoint,
        ctFrame: CTFrame
    ) -> (line: CTLine, origin: CGPoint, index: Int)? {
        let lines = CTFrameGetLines(ctFrame) as [AnyObject]
        var lineOrigins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(
            ctFrame,
            CFRange(location: 0, length: 0),
            &lineOrigins
        )

        for i in 0 ..< lines.count {
            let origin = lineOrigins[i]
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0

            let line = lines[i] as! CTLine
            let lineWidth = CTLineGetTypographicBounds(
                line,
                &ascent,
                &descent,
                &leading
            )
            let lineHeight = ascent + descent + leading

            let lineRect = CGRect(
                x: origin.x,
                y: origin.y - descent,
                width: lineWidth,
                height: lineHeight
            )

            if point.y >= lineRect.minY,
               point.y <= lineRect.maxY
            {
                return (line: line, origin: origin, index: i)
            }
        }

        return nil
    }

    func findCharacterIndexInLine(
        _ point: CGPoint,
        lineInfo: (line: CTLine, origin: CGPoint, index: Int)
    ) -> Int {
        let line = lineInfo.line
        let lineOrigin = lineInfo.origin
        let lineRange = CTLineGetStringRange(line)

        if point.x <= lineOrigin.x {
            return lineRange.location
        }

        for j in 0 ..< lineRange.length {
            let charIndex = lineRange.location + j
            let offset = CTLineGetOffsetForStringIndex(
                line,
                charIndex,
                nil
            )

            if offset >= point.x - lineOrigin.x {
                let v1 = offset - (point.x - lineOrigin.x)
                let v2 = (point.x - lineOrigin.x) - CTLineGetOffsetForStringIndex(line, charIndex - 1, nil)
                if j > 0, v1 > v2 {
                    return charIndex - 1
                }
                return charIndex
            }
        }

        return lineRange.location + lineRange.length
    }
}
