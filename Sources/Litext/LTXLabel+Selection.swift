//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreGraphics
import CoreText
import Foundation
import QuartzCore

extension LTXLabel {
    // MARK: - Selection Methods

    public func clearSelection() {
        selectionStartPoint = nil
        selectionEndPoint = nil
        selectionRange = nil
        selectionLayer?.removeFromSuperlayer()
        selectionLayer = nil
    }

    func textIndexAtPoint(_ point: CGPoint) -> Int? {
        guard let textLayout, let ctFrame = textLayout.ctFrame else { return nil }

        let flippedPoint = CGPoint(x: point.x, y: bounds.height - point.y)

        let lines = CTFrameGetLines(ctFrame) as [AnyObject]
        var lineOrigins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(ctFrame, CFRange(location: 0, length: 0), &lineOrigins)

        // 查找点所在的行
        var lineIndex = -1
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

            if flippedPoint.y >= lineRect.minY, flippedPoint.y <= lineRect.maxY {
                lineIndex = i
                break
            }
        }

        // 如果点击位置在最后一行之后，返回文本末尾
        if lineIndex == -1, !lines.isEmpty, flippedPoint.y < lineOrigins[lines.count - 1].y {
            let lastLine = lines[lines.count - 1] as! CTLine
            let range = CTLineGetStringRange(lastLine)
            return range.location + range.length
        }

        // 如果未找到对应行，返回nil
        if lineIndex == -1 {
            return nil
        }

        let line = lines[lineIndex] as! CTLine
        let lineOrigin = lineOrigins[lineIndex]
        let lineRange = CTLineGetStringRange(line)

        // 检查点击位置是否在行的开始之前
        if flippedPoint.x <= lineOrigin.x {
            return lineRange.location
        }

        // 遍历行中的每个位置，找到最接近点击位置的字符索引
        for j in 0 ..< lineRange.length {
            let charIndex = lineRange.location + j
            let offset = CTLineGetOffsetForStringIndex(line, charIndex, nil)

            if offset >= flippedPoint.x - lineOrigin.x {
                // 如果点击位置更接近上一个字符，返回上一个索引
                if j > 0, offset - (flippedPoint.x - lineOrigin.x) > (flippedPoint.x - lineOrigin.x) - CTLineGetOffsetForStringIndex(line, charIndex - 1, nil) {
                    return charIndex - 1
                }
                return charIndex
            }
        }

        // 如果点击位置在行尾之后，返回行尾索引
        return lineRange.location + lineRange.length
    }
    
    func selectWordAtIndex(_ index: Int) {
        guard isSelectable, let textLayout = textLayout else { return }
        let attributedString = textLayout.attributedString
        guard attributedString.length > 0, index < attributedString.length else { return }
        
        let nsString = attributedString.string as NSString
        let range = nsString.rangeOfWord(at: index)
        
        if range.location != NSNotFound && range.length > 0 {
            updateSelectionWithRange(range)
        }
    }
    
    func selectLineAtIndex(_ index: Int) {
        guard isSelectable, let textLayout = textLayout else { return }
        let attributedString = textLayout.attributedString
        guard attributedString.length > 0, index < attributedString.length else { return }
        
        let nsString = attributedString.string as NSString
        let lineRange = nsString.rangeOfLine(at: index)
        
        if lineRange.location != NSNotFound && lineRange.length > 0 {
            updateSelectionWithRange(lineRange)
        }
    }

    func updateSelectionWithRange(_ range: NSRange) {
        guard let textLayout,
              range.location != NSNotFound,
              range.length > 0,
              textLayout.attributedString.length > 0,
              range.location < textLayout.attributedString.length
        else {
            clearSelection()
            return
        }

        // 确保范围不超出文本长度
        let safeRange = NSRange(
            location: range.location,
            length: min(range.length, textLayout.attributedString.length - range.location)
        )

        selectionRange = safeRange
        drawSelectionHighlight()
    }

    func drawSelectionHighlight() {
        guard let textLayout, let range = selectionRange else { return }

        selectionLayer?.removeFromSuperlayer()

        let selectionPath = LTXPlatformBezierPath()
        var selectionRects: [NSValue] = []

        // 获取选区覆盖的所有矩形
        textLayout.enumerateTextRects(in: range) { rect in
            #if canImport(UIKit)
                selectionRects.append(NSValue(cgRect: rect))
            #elseif canImport(AppKit)
                selectionRects.append(NSValue(rect: rect))
            #else
                #error("unsupported platform")
            #endif
        }

        if selectionRects.isEmpty {
            clearSelection()
            return
        }

        // 创建选区路径
        for boxedRect in selectionRects {
            #if canImport(UIKit)
                let rect = boxedRect.cgRectValue
            #elseif canImport(AppKit)
                let rect = boxedRect.rectValue
            #else
                #error("unsupported platform")
            #endif

            let convertedRect = convertRectFromTextLayout(rect, forInteraction: false)

            #if canImport(UIKit)
                let subpath = LTXPlatformBezierPath(rect: convertedRect)
                selectionPath.append(subpath)
            #elseif canImport(AppKit)
                let subpath = LTXPlatformBezierPath(rect: convertedRect)
                selectionPath.appendPath(subpath)
            #else
                #error("unsupported platform")
            #endif
        }

        let selLayer = CAShapeLayer()

        #if canImport(UIKit)
            selLayer.path = selectionPath.cgPath
        #elseif canImport(AppKit)
            selLayer.path = selectionPath.quartzPath
        #else
            #error("unsupported platform")
        #endif

        // 设置高亮颜色，使用与链接高亮相同的颜色但透明度为0.1
        #if canImport(UIKit)
            selLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.1).cgColor
        #elseif canImport(AppKit)
            selLayer.fillColor = NSColor.linkColor.withAlphaComponent(0.1).cgColor
        #else
            #error("unsupported platform")
        #endif

        #if canImport(UIKit)
            // 将选区层插入到最底层，确保在文本下方
            layer.insertSublayer(selLayer, at: 0)
        #elseif canImport(AppKit)
            // 将选区层插入到最底层，确保在文本下方
            layer?.insertSublayer(selLayer, at: 0)
        #else
            #error("unsupported platform")
        #endif

        selectionLayer = selLayer
    }

    // MARK: - 复制相关

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

        // 确保范围不超出文本长度
        let safeRange = NSRange(
            location: range.location,
            length: min(range.length, textLayout.attributedString.length - range.location)
        )

        // 获取纯文本内容
        return textLayout.attributedString.attributedSubstring(from: safeRange)
    }

    func selectedPlainText() -> String? {
        selectedAttributedText()?.string
    }

    func copySelectedText() {
        guard let selectedText = selectedAttributedText() else { return }

        #if canImport(UIKit)
            UIPasteboard.general.string = selectedText.string
        #elseif canImport(AppKit)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(selectedText.string, forType: .string)
        #endif
    }

    // MARK: - 鼠标光标设置

    func updateCursorForPoint(_ point: CGPoint) {
        #if canImport(AppKit)
            if !isSelectable {
                NSCursor.arrow.set()
                return
            }

            if highlightRegionAtPoint(point) != nil {
                NSCursor.arrow.set()
            } else {
                NSCursor.iBeam.set()
            }
        #endif
    }

    func resetCursor() {
        #if canImport(AppKit)
            NSCursor.arrow.set()
        #endif
    }
}

extension NSString {
    func rangeOfWord(at index: Int) -> NSRange {
        let options: NSString.EnumerationOptions = [.byWords, .substringNotRequired]
        var resultRange = NSRange(location: NSNotFound, length: 0)
        
        enumerateSubstrings(in: NSRange(location: 0, length: length), options: options) { substring, substringRange, _, stop in
            if substringRange.contains(index) {
                resultRange = substringRange
                stop.pointee = true
            }
        }
        
        return resultRange
    }
    
    func rangeOfLine(at index: Int) -> NSRange {
        var startIndex = index
        while startIndex > 0 && character(at: startIndex - 1) != 0x0A { // 0x0A 是换行符 '\n'
            startIndex -= 1
        }
        
        var endIndex = index
        while endIndex < length && character(at: endIndex) != 0x0A {
            endIndex += 1
        }
        
        return NSRange(location: startIndex, length: endIndex - startIndex)
    }
}

extension NSRange {
    func contains(_ index: Int) -> Bool {
        return index >= location && index < (location + length)
    }
}
