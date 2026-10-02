//
//  PlainTextPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  The smallest use of Litext: a string, a font and a color.
//

import Litext
import SwiftUI

struct PlainTextPage: View {
    private static let code = """
    // A string with attributes; anything left out falls back to the
    // system font and the label color.
    TextLabel("Hello, Litext!", attributes: [
        .font: PlatformFont.systemFont(ofSize: 17),
        .foregroundColor: PlatformColor.label,
    ])

    // A localized key, resolved from the bundle `.litextBundle(_:)` sets.
    TextLabel(LocalizedStringKey("Hello, Litext!"))
    """

    @State private var text = "Litext lays out and draws this text with CoreText alone, the same way on every platform it supports."
    @State private var fontSize = 17.0
    @State private var usesDefaults = false

    var body: some View {
        CatalogPageScaffold(.plainText, code: Self.code) {
            if usesDefaults {
                TextLabel(text)
                    .accessibilityIdentifier("demo.plainText.label")
            } else {
                TextLabel(text, attributes: [
                    .font: PlatformFont.systemFont(ofSize: fontSize),
                    .foregroundColor: PlatformColor.label,
                ])
                .accessibilityIdentifier("demo.plainText.label")
            }
        } controls: {
            TextField("Text", text: $text)
                .accessibilityIdentifier("demo.plainText.text")
            Toggle("Default attributes only", isOn: $usesDefaults)
            CatalogSlider("Font size", value: $fontSize, in: 9 ... 48, step: 1) { "\(Int($0)) pt" }
                .disabled(usesDefaults)
            CatalogNote("With no attributes, TextLabel uses the system font at its default size and the label color.")
        }
    }
}
