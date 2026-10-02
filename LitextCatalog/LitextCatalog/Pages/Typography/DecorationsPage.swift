//
//  DecorationsPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Underlines and strikethroughs are drawn by CoreText from the attributed
//  string: style, pattern and color, with the flags CoreText ignores called
//  out rather than faked.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct DecorationsPage: View {
    private static let code = """
    // Style and pattern combine into one NSUnderlineStyle value.
    let style: NSUnderlineStyle = [.double, .patternDash]
    text.addAttributes([
        .underlineStyle: style.rawValue,
        .underlineColor: PlatformColor.systemRed,   // optional: else the text color
    ], range: range)

    text.addAttributes([
        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
        .strikethroughColor: PlatformColor.systemBlue,
    ], range: otherRange)
    """

    enum Line: String, CaseIterable, Identifiable {
        case underline
        case strikethrough
        case both

        var id: Self {
            self
        }

        var title: String {
            rawValue.capitalized
        }
    }

    private static let styles: [(name: String, style: NSUnderlineStyle)] = [
        ("Single", .single),
        ("Thick", .thick),
        ("Double", .double),
    ]

    private static let patterns: [(name: String, pattern: NSUnderlineStyle)] = [
        ("Solid", []),
        ("Dot", .patternDot),
        ("Dash", .patternDash),
        ("Dash dot", .patternDashDot),
        ("Dash dot dot", .patternDashDotDot),
    ]

    @State private var line = Line.underline
    @State private var styleIndex = 0
    @State private var patternIndex = 0
    @State private var isByWord = false
    @State private var color = TypographySwatch.label

    private var decoration: NSUnderlineStyle {
        var style = Self.styles[styleIndex].style.union(Self.patterns[patternIndex].pattern)
        if isByWord {
            style.insert(.byWord)
        }
        return style
    }

    var body: some View {
        CatalogPageScaffold(.decorations, code: Self.code) {
            VStack(alignment: .leading, spacing: 16) {
                TextLabel(attributedString: Self.sample(line: line, style: decoration, color: color))
                    .accessibilityIdentifier("demo.decorations.sample")
                Divider()
                TextLabel(attributedString: Self.reference())
                    .accessibilityIdentifier("demo.decorations.reference")
            }
        } controls: {
            CatalogPicker("Line", selection: $line, options: Line.allCases) { $0.title }
            CatalogPicker("Style", selection: $styleIndex, options: Array(Self.styles.indices)) { Self.styles[$0].name }
            TypographyMenuPicker("Pattern", selection: $patternIndex, options: Array(Self.patterns.indices)) {
                Self.patterns[$0].name
            }
            .accessibilityIdentifier("demo.decorations.pattern")
            TypographyMenuPicker("Color", selection: $color, options: TypographySwatch.allCases) {
                $0 == .label ? "Text color" : $0.title
            }
            .accessibilityIdentifier("demo.decorations.color")
            Toggle("By word", isOn: $isByWord)
            CatalogReadout("Style raw value", value: "0x" + String(decoration.rawValue, radix: 16), identifier: "state.decorations.rawValue")
            CatalogNote(
                "CoreText ignores the byWord flag: the line still runs under the spaces between words. To skip spaces, put the attribute on each word instead.",
                systemImage: "info.circle",
            )
        }
    }

    private static func sample(line: Line, style: NSUnderlineStyle, color: TypographySwatch) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 24),
            .foregroundColor: PlatformColor.label,
        ]
        if line != .strikethrough {
            attributes[.underlineStyle] = style.rawValue
            if color != .label {
                attributes[.underlineColor] = color.color
            }
        }
        if line != .underline {
            attributes[.strikethroughStyle] = style.rawValue
            if color != .label {
                attributes[.strikethroughColor] = color.color
            }
        }
        return NSAttributedString(
            string: "Decorations follow the text across line breaks: this sentence is long enough to wrap onto a second line.",
            attributes: attributes,
        )
    }

    /// Every style and pattern once, so they can be compared side by side.
    private static func reference() -> NSAttributedString {
        let spacing = NSMutableParagraphStyle()
        spacing.lineSpacing = 6
        let body: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 17),
            .foregroundColor: PlatformColor.label,
            .paragraphStyle: spacing,
        ]
        let text = NSMutableAttributedString()
        func row(_ name: String, _ attributes: [NSAttributedString.Key: Any]) {
            if text.length > 0 {
                text.append(NSAttributedString(string: "\n", attributes: body))
            }
            text.append(NSAttributedString(string: name, attributes: body.merging(attributes) { $1 }))
        }
        for style in styles {
            row("\(style.name) underline", [.underlineStyle: style.style.rawValue])
        }
        for pattern in patterns.dropFirst() {
            row("\(pattern.name) underline", [.underlineStyle: NSUnderlineStyle.single.union(pattern.pattern).rawValue])
        }
        row("Colored underline", [
            .underlineStyle: NSUnderlineStyle.thick.rawValue,
            .underlineColor: PlatformColor.systemPink,
        ])
        for style in styles {
            row("\(style.name) strikethrough", [.strikethroughStyle: style.style.rawValue])
        }
        row("Colored strikethrough", [
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .strikethroughColor: PlatformColor.systemRed,
        ])
        return text
    }
}
