//
//  Created by Litext Team.
//  Copyright (c) 2026 Litext Team. All rights reserved.
//
//  An object replacement character without a run delegate stands in for
//  something drawn over the text, such as a list marker. It must take no room
//  whatever its font: the system font of iOS 17 and earlier has no glyph for
//  it, and CoreText then borrows a wide one from another font.
//

import CoreText
import Foundation
@testable import Litext
import Testing

@MainActor
@Suite("Bare object replacement characters")
struct LitextReplacementCharacterTests {
    private static let replacement = TextLabel.Attachment.replacementText
    private static let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
    private static let paragraphStyleKey = NSAttributedString.Key(kCTParagraphStyleAttributeName as String)
    private static let runDelegateKey = NSAttributedString.Key(kCTRunDelegateAttributeName as String)

    /// Whether `font` maps the replacement character to a glyph, and how wide it is.
    private nonisolated static func replacementGlyph(in font: CTFont) -> CGFloat? {
        var character: UniChar = 0xFFFC
        var glyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) else { return nil }
        return CGFloat(CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, nil, 1))
    }

    /// A font with no glyph for the replacement character, as the iOS 17 system font.
    private static func fontWithoutReplacementGlyph(size: CGFloat = 17) -> CTFont? {
        ["PingFangSC-Regular", "Helvetica"]
            .map { CTFontCreateWithName($0 as CFString, size, nil) }
            .first { replacementGlyph(in: $0) == nil }
    }

    /// A font that maps the replacement character to a glyph with a width.
    private static func fontWithWideReplacementGlyph(size: CGFloat = 17) -> CTFont? {
        ["ArialMT", "TimesNewRomanPSMT"]
            .map { CTFontCreateWithName($0 as CFString, size, nil) }
            .first { (replacementGlyph(in: $0) ?? 0) > 0 }
    }

    private nonisolated static let systemFontShowsReplacementAsEmpty: Bool = {
        guard let font = CTFontCreateUIFontForLanguage(.system, 17, nil) else { return false }
        return replacementGlyph(in: font) == 0
    }()

    private static func layOut(_ layout: TextLabel.Layout, width: CGFloat) {
        let size = layout.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        layout.containerSize = CGSize(width: width, height: ceil(size.height))
    }

    /// A paragraph that opens with a bare replacement character, indented like a list item.
    private static func listItem(_ text: String, font: CTFont, indent: CGFloat = 24) -> NSAttributedString {
        var headIndent = indent
        let settings = withUnsafeBytes(of: &headIndent) { bytes in
            [
                CTParagraphStyleSetting(spec: .firstLineHeadIndent, valueSize: bytes.count, value: bytes.baseAddress!),
                CTParagraphStyleSetting(spec: .headIndent, valueSize: bytes.count, value: bytes.baseAddress!),
            ]
        }
        let style = CTParagraphStyleCreate(settings, settings.count)
        return NSAttributedString(
            string: replacement + text,
            attributes: [fontKey: font, paragraphStyleKey: style],
        )
    }

    private static func firstRun(of line: CTLine) -> CTRun {
        (CTLineGetGlyphRuns(line) as! [CTRun])[0]
    }

    @Test
    func `a replacement character its font has no glyph for takes no width`() throws {
        let font = try #require(Self.fontWithoutReplacementGlyph())
        let layout = TextLabel.Layout(attributedString: NSAttributedString(
            string: Self.replacement + "Text",
            attributes: [Self.fontKey: font],
        ))
        Self.layOut(layout, width: 300)
        let line = try #require(layout.layoutLines.first)
        #expect(CTLineGetOffsetForStringIndex(line.line, 1, nil) == 0)
    }

    @Test
    func `the first line of a list item starts where its wrapped lines do`() throws {
        let font = try #require(Self.fontWithoutReplacementGlyph())
        let item = Self.listItem(
            "打开后默认是前置镜头，对准脸就会自动盖上鬼脸，鬼脸会随脸移动、缩放和歪头。",
            font: font,
        )
        let layout = TextLabel.Layout(attributedString: item)
        Self.layOut(layout, width: 240)
        let lines = layout.layoutLines
        try #require(lines.count >= 2)
        let firstTextStart = lines[0].baselineOrigin.x + CTLineGetOffsetForStringIndex(lines[0].line, 1, nil)
        #expect(firstTextStart == lines[1].baselineOrigin.x)
    }

    @Test
    func `a replacement character keeps the height and font of its own run`() throws {
        let font = try #require(Self.fontWithoutReplacementGlyph())
        let layout = TextLabel.Layout(attributedString: NSAttributedString(
            string: Self.replacement,
            attributes: [Self.fontKey: font],
        ))
        Self.layOut(layout, width: 300)
        let line = try #require(layout.layoutLines.first)
        #expect(abs(line.rect.height - (CTFontGetAscent(font) + CTFontGetDescent(font))) < 0.001)
        let runAttributes = CTRunGetAttributes(Self.firstRun(of: line.line)) as NSDictionary
        let runFont = try #require(runAttributes[kCTFontAttributeName] as CFTypeRef?)
        #expect(CFEqual(runFont, font))
    }

    @Test
    func `a replacement character its font draws with a width takes none`() throws {
        let font = try #require(Self.fontWithWideReplacementGlyph())
        let layout = TextLabel.Layout(attributedString: NSAttributedString(
            string: Self.replacement + "Text",
            attributes: [Self.fontKey: font],
        ))
        Self.layOut(layout, width: 300)
        let line = try #require(layout.layoutLines.first)
        #expect(CTLineGetOffsetForStringIndex(line.line, 1, nil) == 0)
    }

    @Test
    func `a replacement character without a font takes no width`() throws {
        let layout = TextLabel.Layout(attributedString: NSAttributedString(string: Self.replacement + "Text"))
        Self.layOut(layout, width: 300)
        let line = try #require(layout.layoutLines.first)
        #expect(CTLineGetOffsetForStringIndex(line.line, 1, nil) == 0)
    }

    @Test(.enabled(if: systemFontShowsReplacementAsEmpty))
    func `a replacement character the font already shows as empty is left to the font`() throws {
        let font = try #require(CTFontCreateUIFontForLanguage(.system, 17, nil))
        let layout = TextLabel.Layout(attributedString: NSAttributedString(
            string: Self.replacement + "Text",
            attributes: [Self.fontKey: font],
        ))
        Self.layOut(layout, width: 300)
        let line = try #require(layout.layoutLines.first)
        let runAttributes = CTRunGetAttributes(Self.firstRun(of: line.line)) as NSDictionary
        #expect(runAttributes[kCTRunDelegateAttributeName] == nil)
    }

    @Test
    func `an attachment keeps the room it reserves`() throws {
        let font = try #require(Self.fontWithoutReplacementGlyph())
        let attachment = TextLabel.Attachment(size: CGSize(width: 40, height: 10))
        let text = NSMutableAttributedString(attributedString: attachment.attributedString(attributes: [Self.fontKey: font]))
        text.append(NSAttributedString(string: "Text", attributes: [Self.fontKey: font]))
        let layout = TextLabel.Layout(attributedString: text)
        Self.layOut(layout, width: 300)
        let line = try #require(layout.layoutLines.first)
        #expect(CTLineGetOffsetForStringIndex(line.line, 1, nil) == 40)
    }

    @Test
    func `the layout keeps the string it was given`() throws {
        let font = try #require(Self.fontWithoutReplacementGlyph())
        let string = NSAttributedString(string: Self.replacement + "Text", attributes: [Self.fontKey: font])
        let layout = TextLabel.Layout(attributedString: string)
        Self.layOut(layout, width: 300)
        #expect(layout.attributedString.isEqual(to: string))
        #expect(layout.attributedString.attribute(Self.runDelegateKey, at: 0, effectiveRange: nil) == nil)
    }

    @Test
    func `a replacement character draws nothing`() throws {
        let font = try #require(Self.fontWithoutReplacementGlyph())
        let layout = TextLabel.Layout(attributedString: NSAttributedString(
            string: Self.replacement,
            attributes: [Self.fontKey: font],
        ))
        Self.layOut(layout, width: 300)
        let width = Int(ceil(layout.containerSize.width))
        let height = Int(ceil(layout.containerSize.height))
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        layout.draw(in: context)
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let inked = (0 ..< width * height).contains { pixels[$0 * 4 + 3] != 0 }
        #expect(!inked)
    }

    @Test
    func `a streamed list reuses the lines before its last item`() throws {
        let font = try #require(Self.fontWithoutReplacementGlyph(size: 15))
        let items = (0 ..< 8).map { index in
            Self.listItem("Item \(index) has enough words in it to wrap onto a second line.\n", font: font)
        }
        func document(_ count: Int) -> NSAttributedString {
            let text = NSMutableAttributedString()
            items.prefix(count).forEach(text.append)
            return text
        }

        let previous = TextLabel.Layout(attributedString: document(6))
        Self.layOut(previous, width: 220)
        let reused = TextLabel.Layout(attributedString: document(8))
        reused.reuseTypesetting(from: previous)
        Self.layOut(reused, width: 220)
        let fresh = TextLabel.Layout(attributedString: document(8))
        Self.layOut(fresh, width: 220)

        #expect(reused.reusedLineCount > 0)
        let reusedLines = reused.layoutLines
        let freshLines = fresh.layoutLines
        #expect(reusedLines.count == freshLines.count)
        for (lhs, rhs) in zip(reusedLines, freshLines) {
            #expect(lhs.stringRange == rhs.stringRange)
            #expect(lhs.baselineOrigin == rhs.baselineOrigin)
        }
        for line in reusedLines where (reused.attributedString.string as NSString).character(at: line.stringRange.location) == 0xFFFC {
            #expect(CTLineGetOffsetForStringIndex(line.line, line.stringRange.location + 1, nil) == 0)
        }
    }
}
