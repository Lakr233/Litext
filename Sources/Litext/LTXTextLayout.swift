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

private func _createTruncatedLine(lastLine: CTLine, attrString: NSAttributedString, width: CGFloat) -> CTLine? {
    var truncationTokenAttributes: [NSAttributedString.Key: Any] = [:]
    let lastLineGlyphRuns = CTLineGetGlyphRuns(lastLine) as NSArray
    if let lastGlyphRun = lastLineGlyphRuns.lastObject as! CTRun? {
        let lastRunAttributes = CTRunGetAttributes(lastGlyphRun) as! [NSAttributedString.Key: Any]

        if let font = lastRunAttributes[.font] {
            truncationTokenAttributes[.font] = font
        }
        if let foregroundColor = lastRunAttributes[.foregroundColor] {
            truncationTokenAttributes[.foregroundColor] = foregroundColor
        }
        if let paragraphStyle = lastRunAttributes[.paragraphStyle] {
            truncationTokenAttributes[.paragraphStyle] = paragraphStyle
        }
    }

    let truncationTokenString = NSAttributedString(string: kTruncationToken, attributes: truncationTokenAttributes)
    let truncationLine = CTLineCreateWithAttributedString(truncationTokenString)

    let lastLineStringRange = CTLineGetStringRange(lastLine)
    let nsRange = NSRange(location: lastLineStringRange.location, length: lastLineStringRange.length)
    let lastLineString = NSMutableAttributedString(attributedString: attrString.attributedSubstring(from: nsRange))
    lastLineString.append(truncationTokenString)
    let newLastLine = CTLineCreateWithAttributedString(lastLineString)

    let truncatedLine = CTLineCreateTruncatedLine(newLastLine, width, .end, truncationLine)

    return truncatedLine
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

    private var framesetter: CTFramesetter
    private var ctFrame: CTFrame?
    private var lines: [CTLine]?
    private var highlightRegionsByLocation: [Int: LTXHighlightRegion] = [:]
    private var lineDrawingActions: Set<LTXLineDrawingAction> = []

    public class func textLayout(withAttributedString attributedString: NSAttributedString) -> LTXTextLayout {
        LTXTextLayout(attributedString: attributedString)
    }

    public init(attributedString: NSAttributedString) {
        self.attributedString = attributedString
        containerSize = .zero
        framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        _highlightRegions = [:]
        super.init()
    }

    deinit {}

    private var _highlightRegions: [Int: LTXHighlightRegion]

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

        enumerateLines { line, _, lineOrigin in
            let glyphRuns = CTLineGetGlyphRuns(line) as NSArray

            for i in 0 ..< glyphRuns.count {
                guard let glyphRun = glyphRuns[i] as! CTRun? else { continue }

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

        context.restoreGState()
    }

    public func updateHighlightRegions(with context: CGContext) {
        _highlightRegions.removeAll()
        extractHighlightRegions(with: context)
    }

    // MARK: - Private Methods

    private func generateLayout() {
        lines = nil

        let containerBounds = CGRect(origin: .zero, size: containerSize)
        let containerPath = CGPath(rect: containerBounds, transform: nil)
        ctFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), containerPath, nil)

        if let ctFrame {
            lines = CTFrameGetLines(ctFrame) as? [CTLine]
        }

        if let lines, let ctFrame {
            let visibleRange = CTFrameGetVisibleStringRange(ctFrame)
            if visibleRange.length == attributedString.length || lines.isEmpty {
                return
            }

            if let lastLine = lines.last, let truncatedLine = _createTruncatedLine(lastLine: lastLine, attrString: attributedString, width: containerBounds.width) {
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

                let attributes = CTRunGetAttributes(glyphRun) as! [NSAttributedString.Key: Any]
                if !_hasHighlightAttributes(attributes) {
                    continue
                }

                let cfStringRange = CTRunGetStringRange(glyphRun)
                let stringRange = NSRange(location: cfStringRange.location, length: cfStringRange.length)

                var effectiveRange = NSRange()
                _ = self.attributedString.attributes(at: stringRange.location, effectiveRange: &effectiveRange)

                let highlightRegion: LTXHighlightRegion
                if let existingRegion = self._highlightRegions[effectiveRange.location] {
                    highlightRegion = existingRegion
                } else {
                    highlightRegion = LTXHighlightRegion(attributes: attributes, stringRange: stringRange)
                    self._highlightRegions[effectiveRange.location] = highlightRegion
                }

                var runBounds = CTRunGetImageBounds(glyphRun, context, CFRange(location: 0, length: 0))

                if let attachment = attributes[LTXAttachmentAttributeName] as? LTXAttachment {
                    runBounds.size = attachment.size
                    runBounds.origin.y -= attachment.size.height * 0.1
                }

                runBounds.origin.x += lineOrigin.x
                runBounds.origin.y += lineOrigin.y
                highlightRegion.addRect(runBounds)
            }
        }
    }

    private func enumerateLines(using block: (CTLine, Int, CGPoint) -> Void) {
        guard let lines, let ctFrame else { return }

        let lineCount = lines.count
        var lineOrigins = [CGPoint](repeating: .zero, count: lineCount)
        CTFrameGetLineOrigins(ctFrame, CFRange(location: 0, length: 0), &lineOrigins)

        for i in 0 ..< lineCount {
            let line = lines[i]
            let origin = lineOrigins[i]
            block(line, i, origin)
        }
    }
}
