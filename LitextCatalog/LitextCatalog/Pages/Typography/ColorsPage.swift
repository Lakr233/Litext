//
//  ColorsPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Colors per run: dynamic system colors, alpha, and a background behind a
//  run, drawn either by CoreText from .backgroundColor or by a line drawing
//  action of your own.
//

import CoreText
import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct ColorsPage: View {
    private static let code = """
    // Any color per run. System colors are dynamic: the label resolves them
    // when it draws, so they follow light and dark mode.
    text.addAttribute(.foregroundColor,
                      value: PlatformColor.systemBlue.withAlphaComponent(0.6),
                      range: range)

    // CoreText fills .backgroundColor behind the run's glyphs,
    // as tall as the run's font.
    text.addAttribute(.backgroundColor, value: PlatformColor.systemYellow, range: range)

    // For any other shape, draw it yourself. The action runs after the
    // glyphs, so a translucent fill reads as a highlighter.
    let marker = TextLabel.LineDrawingAction { context, line, origin in
        let start = CTLineGetOffsetForStringIndex(line, range.location, nil)
        let end = CTLineGetOffsetForStringIndex(line, NSMaxRange(range), nil)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        let box = CGRect(x: origin.x + start, y: origin.y - descent,
                         width: end - start, height: ascent + descent)
        context.addPath(CGPath(roundedRect: box, cornerWidth: 4, cornerHeight: 4, transform: nil))
        context.setFillColor(markerColor)
        context.fillPath()
    }
    text.addAttribute(.litextLineDrawingAction, value: marker, range: range)
    """

    enum Appearance: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: Self {
            self
        }

        var title: String {
            rawValue.capitalized
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    enum Background: String, CaseIterable, Identifiable {
        case none
        case attribute
        case marker

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .none: "None"
            case .attribute: "Attribute"
            case .marker: "Line action"
            }
        }
    }

    @State private var swatch = TypographySwatch.blue
    @State private var alpha = 1.0
    @State private var background = Background.attribute
    @State private var appearance = Appearance.system
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        CatalogPageScaffold(.colors, code: Self.code, demoInsets: 0) {
            TextLabel(attributedString: Self.makeText(
                color: swatch.color.withAlphaComponent(alpha),
                background: background,
            ))
            .accessibilityIdentifier("demo.colors.label")
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: CatalogStyle.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: CatalogStyle.cornerRadius)
                    .strokeBorder(.quaternary)
            }
            .environment(\.colorScheme, appearance.colorScheme ?? systemColorScheme)
        } controls: {
            TypographyMenuPicker("Text color", selection: $swatch, options: TypographySwatch.allCases) { $0.title }
                .accessibilityIdentifier("demo.colors.swatch")
            CatalogSlider("Alpha", value: $alpha, in: 0.1 ... 1, step: 0.05) { "\(Int(($0 * 100).rounded())) %" }
            CatalogPicker("Background", selection: $background, options: Background.allCases) { $0.title }
            CatalogPicker("Appearance", selection: $appearance, options: Appearance.allCases) { $0.title }
            CatalogReadout("Foreground", value: "\(swatch.codeName) × \(alpha.formatted(.number.precision(.fractionLength(2))))")
            CatalogNote(
                "CoreText draws .backgroundColor itself: a band exactly as tall as the run's font, behind the glyphs. A LineDrawingAction can draw any other shape, after the glyphs.",
                systemImage: "info.circle",
            )
        }
    }

    private static func makeText(color: PlatformColor, background: Background) -> NSAttributedString {
        let body: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 17),
            .foregroundColor: PlatformColor.label,
        ]
        let text = NSMutableAttributedString()
        func append(_ string: String, _ attributes: [NSAttributedString.Key: Any] = [:]) {
            text.append(NSAttributedString(string: string, attributes: body.merging(attributes) { $1 }))
        }

        append("This sentence uses the color and alpha you pick.\n\n", [
            .font: PlatformFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: color,
        ])

        append("Semantic colors: ")
        append("label", [.foregroundColor: PlatformColor.label])
        append(", ")
        append("secondaryLabel", [.foregroundColor: PlatformColor.secondaryLabel])
        append(", ")
        append("tertiaryLabel", [.foregroundColor: PlatformColor.tertiaryLabel])
        append(" and ")
        append("link", [.foregroundColor: PlatformColor.link])
        append(". Switch the appearance to see them resolve again.\n\n")

        append("System colors: ")
        for (offset, swatch) in TypographySwatch.allCases.dropFirst().enumerated() {
            if offset > 0 {
                append(" ")
            }
            append(swatch.title.lowercased(), [.foregroundColor: swatch.color])
        }
        append("\n\nOne color per character: ")
        let rainbow = "SPECTRUM"
        for (offset, character) in rainbow.enumerated() {
            let hue = CGFloat(offset) / CGFloat(rainbow.count)
            append(String(character), [
                .font: PlatformFont.systemFont(ofSize: 17, weight: .bold),
                .foregroundColor: PlatformColor(hue: hue, saturation: 0.8, brightness: 0.85, alpha: 1),
            ])
        }

        append("\n\nA background ")
        let highlightStart = text.length
        append("behind a run of text that may wrap onto the next line")
        let highlight = NSRange(location: highlightStart, length: text.length - highlightStart)
        append(", next to text without one.")

        switch background {
        case .none:
            break
        case .attribute:
            text.addAttribute(
                .backgroundColor,
                value: PlatformColor.systemYellow.withAlphaComponent(0.45),
                range: highlight,
            )
        case .marker:
            text.addAttribute(.litextLineDrawingAction, value: markerAction(for: highlight), range: highlight)
        }
        return text
    }

    /// Draws a rounded, translucent marker behind the part of `range` on each line.
    private static func markerAction(for range: NSRange) -> TextLabel.LineDrawingAction {
        let fill = CGColor(red: 1, green: 0.8, blue: 0, alpha: 0.4)
        return TextLabel.LineDrawingAction { context, line, origin in
            let lineRange = CTLineGetStringRange(line)
            let lower = max(range.location, lineRange.location)
            let upper = min(NSMaxRange(range), lineRange.location + lineRange.length)
            guard upper > lower else { return }
            let start = CTLineGetOffsetForStringIndex(line, lower, nil)
            let end = CTLineGetOffsetForStringIndex(line, upper, nil)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            let box = CGRect(
                x: origin.x + min(start, end) - 2,
                y: origin.y - descent,
                width: abs(end - start) + 4,
                height: ascent + descent,
            )
            context.addPath(CGPath(roundedRect: box, cornerWidth: 4, cornerHeight: 4, transform: nil))
            context.setFillColor(fill)
            context.fillPath()
        }
    }
}
