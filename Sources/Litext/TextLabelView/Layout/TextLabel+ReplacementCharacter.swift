//
//  Created by Litext Team.
//  Copyright (c) 2026 Litext Team. All rights reserved.
//

import CoreText
import Foundation

extension TextLabel.Layout {
    /// The ascent and descent a bare replacement character keeps from its font.
    private struct ReplacementMetrics: Hashable {
        var ascent: CGFloat
        var descent: CGFloat
    }

    /// One run delegate per pair of font metrics, shared by every layout.
    ///
    /// CoreText compares run delegates by identity, so a delegate made per string
    /// would make every rebuilt string differ from the one before it, and a
    /// streamed document would lose `reuseTypesetting(from:)` at its first
    /// replacement character.
    private static var replacementRunDelegates: [ReplacementMetrics: CTRunDelegate] = [:]
    private static let replacementRunDelegateLimit = 64

    private static let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
    private static let runDelegateKey = NSAttributedString.Key(kCTRunDelegateAttributeName as String)

    /// `string` as CoreText typesets it: every object replacement character that
    /// carries no run delegate, and that its font does not already show as an empty,
    /// zero-width glyph, gets a run delegate that takes no width and keeps the font's
    /// ascent and descent. Returns `string` itself when there is none.
    ///
    /// A replacement character without a run delegate stands in for something drawn
    /// over the text, such as a list marker drawn by a `LineDrawingAction`, so it
    /// should take no room. Recent system fonts map it to an empty glyph, but the
    /// system font of iOS 17 and earlier has no glyph for it, nor do PingFang or
    /// Helvetica: CoreText then borrows one from another font, Menlo's 0.6 em on
    /// iOS 17, and the character pushes the rest of its line to the right. Arial and
    /// Times map it to a glyph a whole em wide.
    ///
    /// - Important: Performance-sensitive. Runs once per layout. Text without a
    ///   replacement character costs one search for it.
    static func typesettingString(for string: NSAttributedString) -> NSAttributedString {
        let text = string.string as NSString
        let replacement = TextLabel.Attachment.replacementText
        var found = text.range(of: replacement, options: .literal)
        guard found.location != NSNotFound else { return string }

        var result: NSMutableAttributedString?
        var lastFont: CTFont?
        var lastFontShowsEmpty = false
        while found.location != NSNotFound {
            let attributes = string.attributes(at: found.location, effectiveRange: nil)
            if attributes[runDelegateKey] == nil {
                let font = Self.font(in: attributes)
                if lastFont.map({ CFEqual($0, font) }) != true {
                    lastFont = font
                    lastFontShowsEmpty = Self.showsReplacementAsEmpty(font)
                }
                if !lastFontShowsEmpty, let delegate = Self.replacementRunDelegate(for: font) {
                    if result == nil {
                        result = NSMutableAttributedString(attributedString: string)
                    }
                    result?.addAttribute(runDelegateKey, value: delegate, range: found)
                }
            }
            let next = NSMaxRange(found)
            found = text.range(
                of: replacement,
                options: .literal,
                range: NSRange(location: next, length: text.length - next),
            )
        }
        return result?.copy() as? NSAttributedString ?? string
    }

    /// The font CoreText typesets `attributes` with: their font, or Helvetica at
    /// 12 points, CoreText's default.
    private static func font(in attributes: [NSAttributedString.Key: Any]) -> CTFont {
        if let value = attributes[fontKey], CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() {
            return value as! CTFont
        }
        return CTFontCreateWithName("Helvetica" as CFString, 12, nil)
    }

    /// Whether `font` maps the replacement character to a glyph that takes no width.
    private static func showsReplacementAsEmpty(_ font: CTFont) -> Bool {
        var character: UniChar = 0xFFFC
        var glyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) else { return false }
        return CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, nil, 1) == 0
    }

    private static func replacementRunDelegate(for font: CTFont) -> CTRunDelegate? {
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        guard ascent.isFinite, descent.isFinite, descent >= 0, ascent + descent >= 0 else { return nil }
        let key = ReplacementMetrics(ascent: ascent, descent: descent)
        if let delegate = replacementRunDelegates[key] {
            return delegate
        }

        let metrics = TextLabel.Attachment.RunMetrics()
        metrics.size = CGSize(width: 0, height: ascent + descent)
        metrics.descent = descent
        var callbacks = TextLabel.Attachment.RunMetrics.callbacks
        let unmanagedMetrics = Unmanaged.passRetained(metrics)
        guard let delegate = CTRunDelegateCreate(&callbacks, unmanagedMetrics.toOpaque()) else {
            unmanagedMetrics.release()
            return nil
        }
        // Strings already typeset keep their delegates alive; the cache only saves
        // making new ones.
        if replacementRunDelegates.count >= replacementRunDelegateLimit {
            replacementRunDelegates.removeAll()
        }
        replacementRunDelegates[key] = delegate
        return delegate
    }
}
