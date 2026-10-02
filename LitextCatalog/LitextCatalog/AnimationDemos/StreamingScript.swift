//
//  StreamingScript.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  A canned model reply for the streaming demos: rich text in several
//  scripts, cut into token-sized pieces the way a model streams it.
//

import Litext

#if !os(tvOS)

    /// A reply rendered once, plus where each streamed token ends in it.
    struct StreamingScript {
        /// The whole reply.
        let text: NSAttributedString

        /// The UTF-16 offset where each token ends, ascending; the last is the length.
        let tokenEnds: [Int]

        /// The reply as it stands after `count` tokens.
        func prefix(tokens count: Int) -> NSAttributedString {
            guard count > 0 else { return NSAttributedString() }
            let end = tokenEnds[min(count, tokenEnds.count) - 1]
            return text.attributedSubstring(from: NSRange(location: 0, length: end))
        }

        // MARK: - Content

        enum Style {
            case heading
            case body
            case bold
            case italic
            case code
            case link
            case strike
            case bullet
        }

        static let reply: [(Style, String)] = [
            (.heading, "Streaming with Litext\n"),
            (.body, "Each chunk a model sends lands at the end of the label, and only the "),
            (.bold, "new characters"),
            (.body, " animate. Text that arrived earlier stays exactly where it was, so the reader never loses their place. "),
            (.italic, "Nothing above the cursor is redrawn.\n"),
            (.bullet, "• Styled runs: "),
            (.code, "CTRunDraw"),
            (.bullet, " draws each stretch of glyphs at its own opacity.\n"),
            (.bullet, "• Links like "),
            (.link, "the Litext repository"),
            (.bullet, " keep their underline while they fade.\n"),
            (.bullet, "• Edits too: "),
            (.strike, "struck-through drafts"),
            (.bullet, " fade with their line.\n"),
            (.body, "流式输出的中文也会逐字淡入，标点、全角空格和换行都不会打乱节奏。日本語のかな混じり文も同じように表示されます。\n"),
            (.body, "Emoji arrive whole, never half a sequence: 👩‍💻 🧑🏽‍🚀 🇯🇵 ❤️‍🔥 — and mixed scripts like שלום or مرحبا keep their direction. "),
            (.bold, "Done."),
        ]

        /// The reply, styled at `fontSize`.
        static func make(fontSize: CGFloat = 17) -> StreamingScript {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.paragraphSpacing = 8
            let bulletParagraph = paragraph.mutableCopy() as! NSMutableParagraphStyle
            bulletParagraph.headIndent = fontSize
            bulletParagraph.paragraphSpacing = 4

            let body = PlatformFont.systemFont(ofSize: fontSize)
            let text = NSMutableAttributedString()
            for (style, string) in reply {
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: body,
                    .foregroundColor: PlatformColor.label,
                    .paragraphStyle: paragraph,
                ]
                switch style {
                case .heading:
                    attributes[.font] = PlatformFont.systemFont(ofSize: fontSize * 1.35, weight: .bold)
                case .body:
                    break
                case .bold:
                    attributes[.font] = PlatformFont.systemFont(ofSize: fontSize, weight: .semibold)
                case .italic:
                    attributes[.font] = italicFont(ofSize: fontSize)
                    attributes[.foregroundColor] = PlatformColor.secondaryLabel
                case .code:
                    attributes[.font] = PlatformFont.monospacedSystemFont(ofSize: fontSize * 0.9, weight: .medium)
                    attributes[.foregroundColor] = PlatformColor.systemPink
                    attributes[.paragraphStyle] = bulletParagraph
                case .link:
                    attributes[.link] = URL(string: "https://github.com/Lakr233/Litext")!
                    attributes[.foregroundColor] = PlatformColor.link
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    attributes[.paragraphStyle] = bulletParagraph
                case .strike:
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                    attributes[.foregroundColor] = PlatformColor.secondaryLabel
                    attributes[.paragraphStyle] = bulletParagraph
                case .bullet:
                    attributes[.paragraphStyle] = bulletParagraph
                }
                text.append(NSAttributedString(string: string, attributes: attributes))
            }
            return StreamingScript(text: text, tokenEnds: tokenize(text.string))
        }

        private static func italicFont(ofSize size: CGFloat) -> PlatformFont {
            let base = PlatformFont.systemFont(ofSize: size)
            #if canImport(UIKit)
                guard let descriptor = base.fontDescriptor.withSymbolicTraits(.traitItalic) else { return base }
                return PlatformFont(descriptor: descriptor, size: size)
            #else
                let descriptor = base.fontDescriptor.withSymbolicTraits(.italic)
                return PlatformFont(descriptor: descriptor, size: size) ?? base
            #endif
        }

        /// Cuts `string` roughly the way a model's tokenizer does: a Latin word with the
        /// space before it, one or two CJK characters, one emoji, one punctuation mark.
        static func tokenize(_ string: String) -> [Int] {
            var ends: [Int] = []
            var offset = 0
            var current = 0
            var cjkInToken = 0
            var previous: Character?
            for character in string {
                let length = character.utf16.count
                let isWordCharacter = character.isLetter && character.unicodeScalars.allSatisfy { $0.value < 0x2E80 }
                let isCJK = character.unicodeScalars.contains { $0.value >= 0x2E80 && $0.value < 0xFFEF }
                let continues: Bool = if let previous {
                    if isWordCharacter {
                        previous.isLetter || previous == " "
                    } else if isCJK {
                        cjkInToken == 1
                    } else {
                        false
                    }
                } else {
                    true
                }
                if !continues, current > 0 {
                    ends.append(offset)
                    current = 0
                    cjkInToken = 0
                }
                offset += length
                current += length
                cjkInToken = isCJK ? cjkInToken + 1 : 0
                previous = character
            }
            if current > 0 {
                ends.append(offset)
            }
            return ends
        }
    }

#endif
