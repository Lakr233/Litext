//
//  MarkdownPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Foundation parses Markdown into an AttributedString whose runs say what
//  they are (strong, emphasized, code, a link) but not how they look. The
//  page turns those intents into fonts before handing the string to Litext.
//

import Litext
import SwiftUI

struct MarkdownPage: View {
    private static let code = """
    let options = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace,
    )
    var markdown = try AttributedString(markdown: source, options: options)

    // Markdown runs carry intents, not fonts: give each one a font.
    for run in markdown.runs {
        let intent = run.inlinePresentationIntent ?? []
        markdown[run.range].font = font(for: intent)   // your mapping
    }
    TextLabel(attributedString: markdown)
    """

    private static let sample = """
    **Litext** renders *attributed strings*, so anything that produces one works, \
    including Markdown parsed by Foundation.

    Inline `code`, ~~strikethrough~~, ***bold italic*** and [links](https://github.com/Lakr233/Litext) \
    all come through as attributes.
    """

    @State private var source = Self.sample
    @State private var appliesFonts = true
    @State private var fontSize = 17.0

    var body: some View {
        CatalogPageScaffold(.markdown, code: Self.code) {
            TextLabel(attributedString: Self.render(source, appliesFonts: appliesFonts, fontSize: fontSize))
                .selectable()
                .accessibilityIdentifier("demo.markdown.label")
        } controls: {
            Toggle("Map intents to fonts", isOn: $appliesFonts)
            CatalogSlider("Font size", value: $fontSize, in: 11 ... 28, step: 1) { "\(Int($0)) pt" }
            #if os(tvOS)
                TextField("Markdown", text: $source)
            #else
                TextEditor(text: $source)
                    .font(.system(.callout, design: .monospaced))
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .background(CatalogStyle.cardBackground, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("demo.markdown.source")
            #endif
            CatalogNote("Without the mapping every run shows in the system font: Markdown gives intents, and Litext draws only the attributes it is given.")
        }
    }

    /// Parses `source` as inline Markdown and, when asked, gives every run a font and a
    /// color that match its intent. Text that fails to parse shows as it is.
    static func render(_ source: String, appliesFonts: Bool, fontSize: CGFloat) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: source, options: options) else {
            return NSAttributedString(string: source)
        }
        let result = NSMutableAttributedString(attributedString: NSAttributedString(parsed))
        guard appliesFonts else { return result }

        let whole = NSRange(location: 0, length: result.length)
        result.addAttribute(.foregroundColor, value: PlatformColor.label, range: whole)
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            let range = NSRange(run.range, in: parsed)
            let font = PlatformFont.catalogFont(
                ofSize: fontSize,
                weight: intent.contains(.stronglyEmphasized) ? .bold : .regular,
                italic: intent.contains(.emphasized),
                monospaced: intent.contains(.code),
            )
            result.addAttribute(.font, value: font, range: range)
            if intent.contains(.strikethrough) {
                result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
            if run.link != nil {
                result.addAttribute(.foregroundColor, value: PlatformColor.systemBlue, range: range)
            }
        }
        return result
    }
}
