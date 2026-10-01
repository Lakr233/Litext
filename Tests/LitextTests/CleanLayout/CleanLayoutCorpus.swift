//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation
@testable import Litext
import Testing

/// The strings every clean-layout invariant runs over.
///
/// Each case builds a fresh string, so attachments are new objects every time.
enum CleanLayoutCorpus: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case empty
    case singleCharacter
    case whitespaceOnly
    case trailingNewline
    case blankLines
    case crlf
    case longUnbreakableWord
    case latinParagraphs
    case cjk
    case arabic
    case hebrew
    case mixedBidi
    case emoji
    case combiningMarks
    case mixedFontSizes
    case fontWithLeading
    case paragraphSpacing
    case indents
    case centered
    case rightAligned
    case justified
    case lineHeightMultiple
    case minimumLineHeight
    case maximumLineHeight
    case links
    case attachments
    case attachmentsOnly

    var testDescription: String {
        rawValue
    }

    /// The alignment the alignment invariant checks, if any.
    var checkedAlignment: NSTextAlignment? {
        switch self {
        case .centered: .center
        case .rightAligned: .right
        case .justified: .justified
        default: nil
        }
    }

    /// How far below the top of the container the first line's box may start.
    ///
    /// `paragraphSpacingBefore` pushes the first line down, and CoreText puts the
    /// extra height of `lineHeightMultiple` above the glyphs, outside the line's
    /// typographic box. Nothing else may leave a gap (see `CleanLayout.fallbackFontTolerance`).
    @MainActor
    var topSpacingAllowance: CGFloat {
        switch self {
        case .paragraphSpacing:
            return Self.spacingBefore
        case .lineHeightMultiple:
            let font = PlatformFont.systemFont(ofSize: Self.bodySize) as CTFont
            let lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
            return (Self.lineHeightMultipleValue - 1) * lineHeight
        default:
            return 0
        }
    }

    /// Whether the text has characters that draw ink (attachments without a view do not).
    var drawsInk: Bool {
        switch self {
        case .empty, .whitespaceOnly, .attachmentsOnly: false
        default: true
        }
    }

    /// Whether some glyphs draw ink outside their typographic box, so a label sized
    /// to typographic bounds (as Litext, UILabel and CTFramesetter size it) shows
    /// ink past its frame. CoreText's own image bounds confirm each case:
    /// - `fontWithLeading`: Hiragino Sans draws Latin descenders about 1.4pt below
    ///   its declared descent, which the last line keeps no leading for, and a
    ///   line-initial `J` 1.9pt left of the origin.
    /// - `maximumLineHeight`: the clamped line is shorter than the glyphs.
    /// - `arabic`, `mixedBidi`: Arabic and Hebrew glyphs overhang their advance by
    ///   up to 1.2pt at a line edge.
    /// - `emoji`: Apple Color Emoji bitmaps reach a pixel above the line's ascent.
    /// - `rightAligned`: a glyph overhangs the right edge it is flush with.
    var hasGlyphOverhang: Bool {
        switch self {
        case .fontWithLeading, .maximumLineHeight, .arabic, .mixedBidi, .emoji, .rightAligned: true
        default: false
        }
    }

    static let spacingBefore: CGFloat = 8
    static let lineHeightMultipleValue: CGFloat = 1.6
    static let bodySize: CGFloat = 15

    @MainActor
    func makeText() -> NSAttributedString {
        let body = PlatformFont.systemFont(ofSize: Self.bodySize)
        let latin = "The quick brown fox jumps over the lazy dog. "
            + "Pack my box with five dozen liquor jugs, then sphinx of black quartz, judge my vow."

        func plain(_ string: String, font: CTFont? = nil) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [.font: font ?? body])
        }

        func styled(_ string: String, _ configure: (NSMutableParagraphStyle) -> Void) -> NSAttributedString {
            let style = NSMutableParagraphStyle()
            configure(style)
            return NSAttributedString(string: string, attributes: [.font: body, .paragraphStyle: style])
        }

        switch self {
        case .empty:
            return NSAttributedString()
        case .singleCharacter:
            return plain("W")
        case .whitespaceOnly:
            return plain("   \t  ")
        case .trailingNewline:
            return plain("Hello world, this line ends with a newline\n")
        case .blankLines:
            return plain("\nFirst paragraph\n\n\nLast paragraph after blank lines\n\n")
        case .crlf:
            return plain("Line one ends with CRLF\r\nLine two too\r\n\r\nLine four after a blank one")
        case .longUnbreakableWord:
            return plain(
                "See https://example.com/averyveryverylongpathsegmentwithoutanybreakopportunity"
                    + "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz for details",
            )
        case .latinParagraphs:
            return plain(latin + "\n" + latin + " Waltz, bad nymph, for quick jigs vex.")
        case .cjk:
            return plain(
                "日本語のテキストは単語の間にスペースを入れません。"
                    + "中文排版也是如此，标点符号「引号」需要避头尾。한국어 문장도 함께 포함합니다.",
            )
        case .arabic:
            return plain("مرحبا بالعالم، هذا نص عربي طويل لاختبار التفاف الأسطر في التخطيط. لا إله إلا الله")
        case .hebrew:
            return plain("שלום עולם, זהו טקסט עברי ארוך לבדיקת שבירת שורות בפריסה.")
        case .mixedBidi:
            return plain("Hello שלום world עולם 123 مرحبا end. (Parentheses) [עברית 42] done")
        case .emoji:
            return plain("Family 👨‍👩‍👧‍👦 thumbs 👍🏽 flag 🇯🇵 fire ❤️‍🔥 rainbow 🏳️‍🌈 done 😀😀😀")
        case .combiningMarks:
            return plain("Cafe\u{301} na\u{308}ive cre\u{300}me bru\u{302}le\u{301}e n\u{303} a\u{30A}ngstro\u{308}m")
        case .mixedFontSizes:
            let text = NSMutableAttributedString()
            for index in 0 ..< 3 {
                text.append(NSAttributedString(
                    string: "Heading \(index) ",
                    attributes: [.font: PlatformFont.boldSystemFont(ofSize: 32)],
                ))
                text.append(NSAttributedString(
                    string: "followed by small body text that keeps going for a while. ",
                    attributes: [.font: PlatformFont.systemFont(ofSize: 11)],
                ))
            }
            return text
        case .fontWithLeading:
            return plain(latin + "\n" + "日本語の行間テスト。" + latin, font: cleanLayoutFontWithLeading(size: 16))
        case .paragraphSpacing:
            return styled(latin + "\n" + latin + "\nShort last paragraph.") {
                $0.lineSpacing = 6
                $0.paragraphSpacing = 10
                $0.paragraphSpacingBefore = Self.spacingBefore
            }
        case .indents:
            return styled(latin + "\n" + latin) {
                $0.firstLineHeadIndent = 24
                $0.headIndent = 12
                $0.tailIndent = -16
            }
        case .centered:
            return styled(latin + "\nShort centered line\n" + latin) { $0.alignment = .center }
        case .rightAligned:
            return styled(latin + "\nShort right line\n" + latin) { $0.alignment = .right }
        case .justified:
            return styled(latin + " " + latin + "\n" + latin) { $0.alignment = .justified }
        case .lineHeightMultiple:
            return styled(latin + "\n" + latin) { $0.lineHeightMultiple = Self.lineHeightMultipleValue }
        case .minimumLineHeight:
            return styled(latin + "\n" + latin) { $0.minimumLineHeight = 30 }
        case .maximumLineHeight:
            return styled(latin + "\n" + latin) { $0.maximumLineHeight = 13 }
        case .links:
            let text = NSMutableAttributedString(attributedString: plain("Read the "))
            text.append(NSAttributedString(string: "documentation", attributes: [
                .font: body,
                .link: "https://example.com/docs",
            ]))
            text.append(plain(" or follow "))
            text.append(NSAttributedString(
                string: "this considerably longer link that is likely to wrap across several lines",
                attributes: [.font: body, .link: URL(string: "https://example.com/long")!],
            ))
            text.append(plain(" before the end."))
            return text
        case .attachments:
            let text = NSMutableAttributedString(attributedString: plain("Small "))
            text.append(TextLabel.Attachment(size: CGSize(width: 10, height: 10))
                .attributedString(attributes: [.font: body]))
            text.append(plain(" then a tall one "))
            text.append(TextLabel.Attachment(size: CGSize(width: 40, height: 60))
                .attributedString(attributes: [.font: body]))
            text.append(plain(" and a wide flat one "))
            text.append(TextLabel.Attachment(size: CGSize(width: 90, height: 6))
                .attributedString(attributes: [.font: body]))
            text.append(plain(" closing the paragraph."))
            return text
        case .attachmentsOnly:
            let text = NSMutableAttributedString()
            for size in [CGSize(width: 20, height: 20), CGSize(width: 30, height: 45), CGSize(width: 12, height: 8)] {
                text.append(TextLabel.Attachment(size: size).attributedString())
            }
            return text
        }
    }
}

/// A font whose `leading` is non-zero, or the system font when none is installed.
@MainActor
func cleanLayoutFontWithLeading(size: CGFloat) -> CTFont {
    for name in ["HiraginoSans-W3", "Geneva", "ArialMT"] {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        if CTFontCopyPostScriptName(font) as String == name, CTFontGetLeading(font) > 0 {
            return font
        }
    }
    return PlatformFont.systemFont(ofSize: size) as CTFont
}
