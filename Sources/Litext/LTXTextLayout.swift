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
    // 从最后一行的最后一个跑步中获取属性
    let truncationTokenAttributes = extractTruncationAttributes(from: lastLine)

    // 创建截断标记字符串
    let truncationTokenString = NSAttributedString(string: kTruncationToken, attributes: truncationTokenAttributes)
    let truncationLine = CTLineCreateWithAttributedString(truncationTokenString)

    // 获取最后一行的文本范围
    let lastLineStringRange = CTLineGetStringRange(lastLine)
    let nsRange = NSRange(location: lastLineStringRange.location, length: lastLineStringRange.length)

    // 创建新的最后一行内容，附加截断标记
    let lastLineString = NSMutableAttributedString(attributedString: attrString.attributedSubstring(from: nsRange))
    lastLineString.append(truncationTokenString)
    let newLastLine = CTLineCreateWithAttributedString(lastLineString)

    // 创建截断后的行
    let truncatedLine = CTLineCreateTruncatedLine(newLastLine, width, .end, truncationLine)

    return truncatedLine
}

private func extractTruncationAttributes(from line: CTLine) -> [NSAttributedString.Key: Any] {
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
    }

    public func updateHighlightRegions(with context: CGContext) {
        _highlightRegions.removeAll()
        extractHighlightRegions(with: context)
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

            // 如果当前行与选择范围没有重叠，跳过
            if selEnd < lineStart || selStart > lineEnd {
                continue
            }

            let overlapStart = max(lineStart, selStart)
            let overlapEnd = min(lineEnd, selEnd)

            // 如果重叠部分长度为0，跳过
            if overlapStart >= overlapEnd {
                continue
            }

            calculateAndAddTextRect(for: line, origin: origins[i], overlapStart: overlapStart,
                                    overlapEnd: overlapEnd, lineStart: lineStart, lineEnd: lineEnd,
                                    using: block)
        }
    }

    private func calculateAndAddTextRect(for line: CTLine, origin: CGPoint,
                                         overlapStart: CFIndex, overlapEnd: CFIndex,
                                         lineStart: CFIndex, lineEnd: CFIndex,
                                         using block: (CGRect) -> Void)
    {
        var startOffset: CGFloat = 0
        var endOffset: CGFloat = 0

        // 计算起始偏移
        if overlapStart > lineStart {
            startOffset = CTLineGetOffsetForStringIndex(line, overlapStart, nil)
        }

        // 计算结束偏移
        if overlapEnd < lineEnd {
            endOffset = CTLineGetOffsetForStringIndex(line, overlapEnd, nil)
        } else {
            endOffset = CTLineGetTypographicBounds(line, nil, nil, nil)
        }

        // 获取行的垂直度量
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

        // 创建文本矩形
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

        let containerBounds = CGRect(origin: .zero, size: containerSize)
        let containerPath = CGPath(rect: containerBounds, transform: nil)
        ctFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), containerPath, nil)

        if let ctFrame {
            lines = CTFrameGetLines(ctFrame) as? [CTLine]
        }

        processTruncation(in: containerBounds)
    }

    private func processTruncation(in containerBounds: CGRect) {
        if let lines, let ctFrame {
            let visibleRange = CTFrameGetVisibleStringRange(ctFrame)
            // 如果没有截断或没有行，则返回
            if visibleRange.length == attributedString.length || lines.isEmpty {
                return
            }

            // 处理文本截断
            if let lastLine = lines.last,
               let truncatedLine = _createTruncatedLine(lastLine: lastLine,
                                                        attrString: attributedString,
                                                        width: containerBounds.width)
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

                let attributes = CTRunGetAttributes(glyphRun) as! [NSAttributedString.Key: Any]
                if !_hasHighlightAttributes(attributes) {
                    continue
                }

                processHighlightRegionForRun(glyphRun, attributes: attributes, lineOrigin: lineOrigin, with: context)
            }
        }
    }

    private func processHighlightRegionForRun(_ glyphRun: CTRun, attributes: [NSAttributedString.Key: Any],
                                              lineOrigin: CGPoint, with context: CGContext)
    {
        let cfStringRange = CTRunGetStringRange(glyphRun)
        let stringRange = NSRange(location: cfStringRange.location, length: cfStringRange.length)

        var effectiveRange = NSRange()
        _ = attributedString.attributes(at: stringRange.location, effectiveRange: &effectiveRange)

        let highlightRegion: LTXHighlightRegion
        if let existingRegion = _highlightRegions[effectiveRange.location] {
            highlightRegion = existingRegion
        } else {
            highlightRegion = LTXHighlightRegion(attributes: attributes, stringRange: stringRange)
            _highlightRegions[effectiveRange.location] = highlightRegion
        }

        var runBounds = CTRunGetImageBounds(glyphRun, context, CFRange(location: 0, length: 0))

        // 如果是附件，调整边界
        if let attachment = attributes[LTXAttachmentAttributeName] as? LTXAttachment {
            runBounds.size = attachment.size
            runBounds.origin.y -= attachment.size.height * 0.1
        }

        // 调整边界位置为相对于容器的坐标
        runBounds.origin.x += lineOrigin.x
        runBounds.origin.y += lineOrigin.y
        highlightRegion.addRect(runBounds)
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
