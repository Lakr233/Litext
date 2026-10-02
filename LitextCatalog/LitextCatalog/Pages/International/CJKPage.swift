//
//  CJKPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Chinese, Japanese and Korean text, mixed with Latin, with CoreText's line
//  breaking and per-language glyph choice.
//

import CoreText
import Litext
import SwiftUI

struct CJKPage: View {
    private static let code = """
    // CJK needs nothing special: the system font falls back to PingFang,
    // Hiragino or Apple SD Gothic Neo per character.
    let text = NSMutableAttributedString(
        string: "「吾輩は猫である。」名前はまだ無い。",
        attributes: [.font: PlatformFont.systemFont(ofSize: 17)],
    )

    // Han characters shared by several languages take that language's glyph
    // shapes when the run is tagged with it.
    let language = NSAttributedString.Key(kCTLanguageAttributeName as String)
    text.addAttribute(language, value: "ja", range: range)

    TextLabel(attributedString: text)
        .selectable()
        .onSelectionChange { selected = $0 ?? "" }
        .frame(maxWidth: width)   // narrow it to watch the lines break
    """

    @State private var width = 720.0
    @State private var fontSize = 17.0
    @State private var tagsLanguages = true
    @State private var selected = ""

    var body: some View {
        CatalogPageScaffold(.cjk, code: Self.code) {
            VStack(alignment: .leading, spacing: 10) {
                TextLabel(attributedString: Self.makeText(fontSize: fontSize, tagsLanguages: tagsLanguages))
                    .selectable()
                    .onSelectionChange { selected = $0 ?? "" }
                    .frame(maxWidth: width, alignment: .leading)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.35))
                            .frame(width: 1)
                    }
                    .accessibilityIdentifier("demo.cjk.label")
                CatalogNote(
                    "Closing marks such as 。、」 never start a line and opening marks such as 「 never end one: "
                        + "CoreText follows the Unicode line breaking rules (UAX #14). Narrow the width to watch.",
                )
            }
        } controls: {
            CatalogSlider("Maximum width", value: $width, in: 120 ... 720, step: 4) { "\(Int($0)) pt" }
            CatalogSlider("Font size", value: $fontSize, in: 12 ... 30, step: 1) { "\(Int($0)) pt" }
            Toggle("Tag each paragraph with its language", isOn: $tagsLanguages)
            CatalogReadout(
                "Selected text",
                value: selected.isEmpty ? "none" : selected,
                identifier: "state.cjk.selectedText",
            )
            CatalogReadout(
                "Characters / UTF-16",
                value: selected.isEmpty ? "none" : "\(selected.count) / \(selected.utf16.count)",
                identifier: "state.cjk.counts",
            )
        }
    }

    private struct Sample {
        let caption: String
        let language: String
        let text: String
    }

    private static let samples = [
        Sample(
            caption: "简体中文",
            language: "zh-Hans",
            text: "春眠不觉晓，处处闻啼鸟。夜来风雨声，花落知多少。这一段还夹着 Litext 与 CoreText 两个英文词和数字 2025。",
        ),
        Sample(
            caption: "繁體中文",
            language: "zh-Hant",
            text: "床前明月光，疑是地上霜。舉頭望明月，低頭思故鄉。標點符號「」與『』不會出現在行首或行尾的錯誤位置。",
        ),
        Sample(
            caption: "日本語",
            language: "ja",
            text: "「吾輩は猫である。名前はまだ無い。」どこで生れたかとんと見当がつかぬ。ちょっとキャッシュをクリアしてください。",
        ),
        Sample(
            caption: "한국어",
            language: "ko",
            text: "모든 사람은 태어날 때부터 자유로우며 그 존엄과 권리에 있어 동등하다. 한국어는 낱말 사이를 띄어 쓰므로 공백에서 줄이 바뀝니다.",
        ),
    ]

    private static let hanCaption = "Han unification: the same five code points, shaped per language"

    private static func makeText(fontSize: CGFloat, tagsLanguages: Bool) -> NSAttributedString {
        let languageKey = NSAttributedString.Key(kCTLanguageAttributeName as String)
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = fontSize * 0.6
        paragraph.lineSpacing = fontSize * 0.2
        let captionStyle = NSMutableParagraphStyle()
        captionStyle.paragraphSpacing = 2
        let caption: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: max(fontSize - 5, 10), weight: .semibold),
            .foregroundColor: PlatformColor.secondaryLabel,
            .paragraphStyle: captionStyle,
        ]
        let body: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: fontSize),
            .foregroundColor: PlatformColor.label,
            .paragraphStyle: paragraph,
        ]

        let text = NSMutableAttributedString()
        for sample in samples {
            text.append(NSAttributedString(string: sample.caption + "\n", attributes: caption))
            var attributes = body
            if tagsLanguages {
                attributes[languageKey] = sample.language
            }
            text.append(NSAttributedString(string: sample.text + "\n", attributes: attributes))
        }

        text.append(NSAttributedString(string: hanCaption + "\n", attributes: caption))
        let variants = ["zh-Hans", "zh-Hant", "ja", "ko"]
        for (offset, language) in variants.enumerated() {
            var attributes = body
            attributes[.font] = PlatformFont.systemFont(ofSize: fontSize * 1.4)
            if tagsLanguages {
                attributes[languageKey] = language
            }
            text.append(NSAttributedString(string: "直骨角次返", attributes: attributes))
            var label = caption
            label[.paragraphStyle] = paragraph
            let separator = offset == variants.count - 1 ? "" : "   "
            text.append(NSAttributedString(string: " \(language)\(separator)", attributes: label))
        }
        return text
    }
}
