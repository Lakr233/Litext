//
//  FontsPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Fonts come from the attributed string: Litext draws whatever font each run
//  carries, so weights, traits, designs and custom faces all work the same way.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct FontsPage: View {
    private static let code = """
    // Weight and design through a font descriptor.
    var descriptor = PlatformFont.systemFont(ofSize: 24, weight: .semibold).fontDescriptor
    descriptor = descriptor.withDesign(.serif) ?? descriptor
    // Italic and bold are symbolic traits (.italic and .bold on AppKit).
    descriptor = descriptor.withSymbolicTraits(.traitItalic) ?? descriptor
    let font = PlatformFont(descriptor: descriptor, size: 24)

    // Digits that line up in columns.
    let digits = PlatformFont.monospacedDigitSystemFont(ofSize: 17, weight: .regular)

    // A custom font by name, with a fallback when it is not installed.
    let custom = PlatformFont(name: "AvenirNext-DemiBold", size: 17)
        ?? .systemFont(ofSize: 17, weight: .semibold)

    // Text styles. The font is fixed once it is in the string:
    // build the string again when the content size category changes.
    let body = PlatformFont.preferredFont(forTextStyle: .body)

    TextLabel(attributedString: NSAttributedString(
        string: "The quick brown fox",
        attributes: [.font: font, .foregroundColor: PlatformColor.label],
    ))
    """

    private static let weights: [(name: String, weight: PlatformFont.Weight)] = [
        ("Ultralight", .ultraLight),
        ("Thin", .thin),
        ("Light", .light),
        ("Regular", .regular),
        ("Medium", .medium),
        ("Semibold", .semibold),
        ("Bold", .bold),
        ("Heavy", .heavy),
        ("Black", .black),
    ]

    private static let customFontName = "AvenirNext-DemiBold"

    @State private var size = 28.0
    @State private var weightIndex = 3
    @State private var design = TypographyDesign.standard
    @State private var isItalic = false
    @State private var isBold = false

    private var specimenFont: PlatformFont {
        .typographyFont(
            ofSize: size,
            weight: Self.weights[weightIndex].weight,
            design: design,
            italic: isItalic,
            bold: isBold,
        )
    }

    var body: some View {
        CatalogPageScaffold(.fonts, code: Self.code) {
            VStack(alignment: .leading, spacing: 16) {
                TextLabel(attributedString: Self.specimen(font: specimenFont))
                    .accessibilityIdentifier("demo.fonts.specimen")
                Divider()
                TextLabel(attributedString: Self.reference())
                    .accessibilityIdentifier("demo.fonts.reference")
            }
        } controls: {
            CatalogSlider("Size", value: $size, in: 9 ... 64, step: 1) { "\(Int($0)) pt" }
            TypographyMenuPicker("Weight", selection: $weightIndex, options: Array(Self.weights.indices)) {
                Self.weights[$0].name
            }
            .accessibilityIdentifier("demo.fonts.weight")
            CatalogPicker("Design", selection: $design, options: TypographyDesign.allCases) { $0.title }
            Toggle("Italic trait", isOn: $isItalic)
            Toggle("Bold trait", isOn: $isBold)
            CatalogReadout("Resolved font", value: specimenFont.fontName, identifier: "state.fonts.fontName")
            CatalogReadout(
                "Line height",
                value: TypographyMeasure.points(specimenFont.typographyLineHeight),
                identifier: "state.fonts.lineHeight",
            )
            CatalogNote(
                "A trait or design the font has no face for falls back to the closest one: the resolved name shows what CoreText picked.",
            )
        }
    }

    private static func specimen(font: PlatformFont) -> NSAttributedString {
        NSAttributedString(
            string: "The quick brown fox jumps over the lazy dog. 0123456789",
            attributes: [.font: font, .foregroundColor: PlatformColor.label],
        )
    }

    /// Every weight, the traits, monospaced faces, a custom font and the text styles,
    /// each line set in the font it names.
    private static func reference() -> NSAttributedString {
        let text = NSMutableAttributedString()
        let caption: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: PlatformColor.secondaryLabel,
        ]
        func section(_ title: String) {
            if text.length > 0 {
                text.append(NSAttributedString(string: "\n\n", attributes: [.font: PlatformFont.systemFont(ofSize: 10)]))
            }
            text.append(NSAttributedString(string: title.uppercased() + "\n", attributes: caption))
        }
        func line(_ string: String, _ font: PlatformFont, last: Bool = false) {
            text.append(NSAttributedString(
                string: last ? string : string + "\n",
                attributes: [.font: font, .foregroundColor: PlatformColor.label],
            ))
        }

        section("Weights")
        for (offset, entry) in weights.enumerated() {
            text.append(NSAttributedString(
                string: offset == weights.count - 1 ? entry.name : entry.name + "  ",
                attributes: [.font: PlatformFont.systemFont(ofSize: 17, weight: entry.weight), .foregroundColor: PlatformColor.label],
            ))
        }

        section("Symbolic traits")
        text.append(NSAttributedString(string: "Italic  ", attributes: [.font: PlatformFont.typographyFont(ofSize: 17, italic: true), .foregroundColor: PlatformColor.label]))
        text.append(NSAttributedString(string: "Bold  ", attributes: [.font: PlatformFont.typographyFont(ofSize: 17, bold: true), .foregroundColor: PlatformColor.label]))
        line("Bold italic", .typographyFont(ofSize: 17, italic: true, bold: true), last: true)

        section("Monospaced")
        line("let answer = 42", .monospacedSystemFont(ofSize: 15, weight: .regular))
        let proportional = PlatformFont.systemFont(ofSize: 17)
        let monospacedDigits = PlatformFont.monospacedDigitSystemFont(ofSize: 17, weight: .regular)
        line("1,111.11  proportional digits", proportional)
        line("8,888.88  proportional digits", proportional)
        line("1,111.11  monospaced digits", monospacedDigits)
        line("8,888.88  monospaced digits", monospacedDigits, last: true)

        section("Custom font by name")
        if let custom = PlatformFont(name: customFontName, size: 19) {
            line("\(customFontName) is installed", custom, last: true)
        } else {
            line("\(customFontName) is missing: the system font stands in", .systemFont(ofSize: 19, weight: .semibold), last: true)
        }

        section("Text styles")
        let styles: [(String, PlatformFont.TextStyle)] = [
            ("Title 1", .title1),
            ("Headline", .headline),
            ("Body", .body),
            ("Callout", .callout),
            ("Footnote", .footnote),
            ("Caption 1", .caption1),
        ]
        for (offset, style) in styles.enumerated() {
            line(style.0, .preferredFont(forTextStyle: style.1), last: offset == styles.count - 1)
        }
        return text
    }
}
