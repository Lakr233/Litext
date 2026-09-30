//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation
@testable import Litext
import QuartzCore
import Testing

/// A font whose `leading` is non-zero, so line boxes differ depending on where
/// the leading is placed. Returns nil when no such font is installed.
private func fontWithLeading(size: CGFloat) -> CTFont? {
    for name in ["HiraginoSans-W3", "Geneva", "ArialMT"] {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let postScriptName = CTFontCopyPostScriptName(font) as String
        if postScriptName == name, CTFontGetLeading(font) > 0 {
            return font
        }
    }
    return nil
}

@MainActor
private func makeLaidOutLayout(_ text: NSAttributedString, width: CGFloat) -> TextLabel.Layout {
    let layout = TextLabel.Layout(attributedString: text)
    let size = layout.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    layout.containerSize = CGSize(width: width, height: ceil(size.height))
    return layout
}

@MainActor
@Test func lineLeadingSitsBelowTheDescent() throws {
    let font = try #require(fontWithLeading(size: 16))
    let leading = CTFontGetLeading(font)
    let marker = NSAttributedString.Key("LineBoxProbe")
    let text = NSAttributedString(
        string: "First line\nSecond line",
        attributes: [.font: font, marker: true]
    )
    let layout = makeLaidOutLayout(text, width: 400)

    let runs = layout.layoutRuns(matching: marker)
    let firstLine = try #require(runs.first { $0.lineIndex == 0 }).lineRect
    let secondLine = try #require(runs.first { $0.lineIndex == 1 }).lineRect

    // The selection rect covers the line's ascent and, below its descent, its leading.
    let selection = try #require(layout.rects(for: NSRange(location: 0, length: 5)).first)
    #expect(abs(selection.maxY - firstLine.maxY) < 0.001)
    #expect(abs(selection.minY - (firstLine.minY - leading)) < 0.001)
    #expect(selection.minY >= secondLine.maxY - 0.001)

    // A point in the first line's leading band belongs to the first line.
    let gapPoint = CGPoint(x: firstLine.minX + 1, y: firstLine.minY - leading / 2)
    #expect(layout.textIndex(at: gapPoint) == 0)
    #expect(layout.nearestTextIndex(at: gapPoint) == 0)
}

@MainActor
@Test func layoutKeepsASnapshotOfAMutableString() {
    let text = NSMutableAttributedString(
        string: "Visit https://example.com today",
        attributes: [.font: PlatformFont.systemFont(ofSize: 16)]
    )
    text.addAttribute(.link, value: "https://example.com", range: NSRange(location: 6, length: 19))
    let layout = TextLabel.Layout(attributedString: text)

    text.deleteCharacters(in: NSRange(location: 0, length: text.length))
    layout.containerSize = CGSize(width: 300, height: 60)
    layout.updateHighlightRegions()

    #expect(layout.attributedString.length == 31)
    #expect(layout.highlightRegions.first?.stringRange == NSRange(location: 6, length: 19))
}

@MainActor
@Test func lineDrawingActionRunsOncePerLineAcrossRunSplits() throws {
    var invocationCount = 0
    let action = TextLabel.LineDrawingAction { _, _, _ in
        invocationCount += 1
    }
    let lineCount = 6
    let text = NSMutableAttributedString()
    for index in 0 ..< lineCount {
        // A bold span and a link split every line into several glyph runs.
        text.append(NSAttributedString(
            string: "Line \(index) ",
            attributes: [.font: PlatformFont.systemFont(ofSize: 16), .litextLineDrawingAction: action]
        ))
        text.append(NSAttributedString(
            string: "bold",
            attributes: [.font: PlatformFont.boldSystemFont(ofSize: 16), .litextLineDrawingAction: action]
        ))
        text.append(NSAttributedString(
            string: " link\n",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .link: "https://example.com/\(index)",
                .litextLineDrawingAction: action,
            ]
        ))
    }
    let layout = makeLaidOutLayout(text, width: 400)
    #expect(layout.visibleLineCount(in: nil) == lineCount)

    let width = Int(layout.containerSize.width.rounded(.up))
    let height = Int(layout.containerSize.height.rounded(.up))
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    layout.draw(in: context)

    #expect(invocationCount == lineCount)
}

@MainActor
@Test func negativeTailIndentIsHonouredByMeasurement() {
    let paragraph = NSMutableParagraphStyle()
    paragraph.tailIndent = -40
    let text = NSAttributedString(
        string: "A single line with a tail indent",
        attributes: [.font: PlatformFont.systemFont(ofSize: 14), .paragraphStyle: paragraph]
    )
    let framesetter = CTFramesetterCreateWithAttributedString(text)
    let layout = TextLabel.Layout(attributedString: text)

    let natural = layout.sizeThatFits(CGSize(
        width: CGFloat.greatestFiniteMagnitude,
        height: CGFloat.greatestFiniteMagnitude
    ))
    // Narrower than the line plus its tail indent, so CoreText wraps.
    let constraint = CGSize(width: natural.width - 20, height: .greatestFiniteMagnitude)
    let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter,
        CFRange(location: 0, length: 0),
        nil,
        constraint,
        nil
    )
    let measured = layout.sizeThatFits(constraint)

    #expect(abs(measured.height - suggested.height) < 0.001)
    #expect(measured.height > natural.height)
}

@MainActor
@Test func characterIndexStaysOnTheHitLine() throws {
    let marker = NSAttributedString.Key("CharacterIndexProbe")
    let text = NSAttributedString(
        string: "Hello world\nSecond",
        attributes: [.font: PlatformFont.systemFont(ofSize: 16), marker: true]
    )
    let layout = makeLaidOutLayout(text, width: 400)
    let runs = layout.layoutRuns(matching: marker)
    let firstLine = try #require(runs.first { $0.lineIndex == 0 }).lineRect
    let lastLine = try #require(runs.first { $0.lineIndex == 1 }).lineRect

    let pastFirstLine = CGPoint(x: 390, y: firstLine.midY)
    #expect(try #require(layout.characterIndex(at: pastFirstLine)) <= 11)

    let pastLastLine = CGPoint(x: 390, y: lastLine.midY)
    #expect(layout.nearestTextIndex(at: pastLastLine) == text.length)
    #expect(layout.characterIndex(at: pastLastLine) == text.length - 1)
}

@MainActor
@Test func bidiSelectionRectsFollowTheSelectedGlyphs() throws {
    let text = NSAttributedString(
        string: "abc שלום עולם def",
        attributes: [.font: PlatformFont.systemFont(ofSize: 16)]
    )
    let layout = makeLaidOutLayout(text, width: 400)

    let firstWord = layout.rects(for: NSRange(location: 4, length: 4))
    let secondWord = layout.rects(for: NSRange(location: 9, length: 4))
    #expect(!firstWord.isEmpty)
    #expect(!secondWord.isEmpty)
    for lhs in firstWord {
        for rhs in secondWord {
            #expect(lhs.intersection(rhs).width < 0.5)
        }
    }
    // Right-to-left: the logically first word is drawn to the right of the second.
    let firstMinX = try #require(firstWord.map(\.minX).min())
    let secondMaxX = try #require(secondWord.map(\.maxX).max())
    #expect(firstMinX >= secondMaxX - 0.5)
}

@MainActor
@Test func linkRegionsUseTypographicBounds() throws {
    let text = NSMutableAttributedString(
        string: "ace gy",
        attributes: [.font: PlatformFont.systemFont(ofSize: 16)]
    )
    text.addAttribute(.link, value: "https://example.com/a", range: NSRange(location: 0, length: 3))
    text.addAttribute(.link, value: "https://example.com/b", range: NSRange(location: 4, length: 2))
    let layout = makeLaidOutLayout(text, width: 400)
    layout.updateHighlightRegions()

    let regions = layout.highlightRegions.sorted { $0.stringRange.location < $1.stringRange.location }
    #expect(regions.count == 2)
    let ace = try #require(regions.first?.rects.first)
    let gy = try #require(regions.last?.rects.first)
    #expect(abs(ace.minY - gy.minY) < 0.001)
    #expect(abs(ace.height - gy.height) < 0.001)
}

@Test func rangeOfLineHonoursEveryParagraphSeparator() {
    let crlf = "abc\r\ndef" as NSString
    #expect(crlf.rangeOfLine(at: 0) == NSRange(location: 0, length: 3))
    #expect(crlf.rangeOfLine(at: 6) == NSRange(location: 5, length: 3))

    let separators = "one\u{2029}two\rthree" as NSString
    #expect(separators.rangeOfLine(at: 0) == NSRange(location: 0, length: 3))
    #expect(separators.rangeOfLine(at: 5) == NSRange(location: 4, length: 3))
    #expect(separators.rangeOfLine(at: 9) == NSRange(location: 8, length: 5))

    // An index on the terminator selects the paragraph it ends.
    let newline = "first\nsecond" as NSString
    #expect(newline.rangeOfLine(at: 5) == NSRange(location: 0, length: 5))
}
