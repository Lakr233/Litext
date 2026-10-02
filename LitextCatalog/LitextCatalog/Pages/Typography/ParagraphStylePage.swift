//
//  ParagraphStylePage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Every NSParagraphStyle knob CoreText honours, one control each, on three
//  paragraphs so spacing between paragraphs shows too.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct ParagraphStylePage: View {
    private static let code = """
    let style = NSMutableParagraphStyle()
    style.alignment = .justified
    style.lineSpacing = 4
    style.lineHeightMultiple = 1.2      // 0 leaves the font's line height
    style.minimumLineHeight = 0         // 0 means no minimum
    style.maximumLineHeight = 0         // 0 means no maximum
    style.firstLineHeadIndent = 24
    style.headIndent = 0
    style.tailIndent = 0                // negative: measured from the trailing edge
    style.paragraphSpacing = 12
    style.paragraphSpacingBefore = 0
    style.baseWritingDirection = .natural

    TextLabel(attributedString: NSAttributedString(string: text, attributes: [
        .font: PlatformFont.systemFont(ofSize: 17),
        .foregroundColor: PlatformColor.label,
        .paragraphStyle: style,
    ]))
    """

    private static let alignments: [(name: String, alignment: NSTextAlignment)] = [
        ("Left", .left),
        ("Center", .center),
        ("Right", .right),
        ("Justify", .justified),
        ("Natural", .natural),
    ]

    private static let directions: [(name: String, direction: NSWritingDirection)] = [
        ("Natural", .natural),
        ("Left to right", .leftToRight),
        ("Right to left", .rightToLeft),
    ]

    @State private var alignmentIndex = 4
    @State private var lineSpacing = 0.0
    @State private var lineHeightMultiple = 0.0
    @State private var minimumLineHeight = 0.0
    @State private var maximumLineHeight = 0.0
    @State private var firstLineHeadIndent = 0.0
    @State private var headIndent = 0.0
    @State private var tailIndent = 0.0
    @State private var paragraphSpacing = 8.0
    @State private var paragraphSpacingBefore = 0.0
    @State private var directionIndex = 0

    private var style: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = Self.alignments[alignmentIndex].alignment
        style.lineSpacing = lineSpacing
        style.lineHeightMultiple = lineHeightMultiple
        style.minimumLineHeight = minimumLineHeight
        style.maximumLineHeight = maximumLineHeight
        style.firstLineHeadIndent = firstLineHeadIndent
        style.headIndent = headIndent
        style.tailIndent = -tailIndent
        style.paragraphSpacing = paragraphSpacing
        style.paragraphSpacingBefore = paragraphSpacingBefore
        style.baseWritingDirection = Self.directions[directionIndex].direction
        return style
    }

    var body: some View {
        CatalogPageScaffold(.paragraphStyle, code: Self.code) {
            TextLabel(attributedString: Self.makeText(style: style))
                .accessibilityIdentifier("demo.paragraphStyle.label")
        } controls: {
            CatalogPicker("Alignment", selection: $alignmentIndex, options: Array(Self.alignments.indices)) {
                Self.alignments[$0].name
            }
            CatalogPicker("Writing direction", selection: $directionIndex, options: Array(Self.directions.indices)) {
                Self.directions[$0].name
            }

            sectionTitle("Line height")
            CatalogSlider("Line spacing", value: $lineSpacing, in: 0 ... 24, step: 1, format: Self.points)
            CatalogSlider("Line height multiple", value: $lineHeightMultiple, in: 0 ... 2.5, step: 0.05) {
                $0 == 0 ? "off" : "× " + $0.formatted(.number.precision(.fractionLength(2)))
            }
            CatalogSlider("Minimum line height", value: $minimumLineHeight, in: 0 ... 48, step: 1, format: Self.pointsOrOff)
            CatalogSlider("Maximum line height", value: $maximumLineHeight, in: 0 ... 48, step: 1, format: Self.pointsOrOff)

            sectionTitle("Indents")
            CatalogSlider("First line head indent", value: $firstLineHeadIndent, in: 0 ... 64, step: 1, format: Self.points)
            CatalogSlider("Head indent", value: $headIndent, in: 0 ... 64, step: 1, format: Self.points)
            CatalogSlider("Tail indent (from the trailing edge)", value: $tailIndent, in: 0 ... 64, step: 1, format: Self.points)

            sectionTitle("Paragraph spacing")
            CatalogSlider("After", value: $paragraphSpacing, in: 0 ... 40, step: 1, format: Self.points)
            CatalogSlider("Before", value: $paragraphSpacingBefore, in: 0 ... 40, step: 1, format: Self.points)

            Button("Reset", action: reset)
                .accessibilityIdentifier("demo.paragraphStyle.reset")
            CatalogNote(
                "Sizes come from typographic bounds, as with UILabel. A maximum line height below the font's own height packs lines closer than their glyphs, so ascenders and descenders can reach outside a line's box and be clipped at the top and bottom of the label.",
                systemImage: "exclamationmark.triangle",
            )
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func reset() {
        alignmentIndex = 4
        lineSpacing = 0
        lineHeightMultiple = 0
        minimumLineHeight = 0
        maximumLineHeight = 0
        firstLineHeadIndent = 0
        headIndent = 0
        tailIndent = 0
        paragraphSpacing = 8
        paragraphSpacingBefore = 0
        directionIndex = 0
    }

    private static func points(_ value: Double) -> String {
        "\(Int(value)) pt"
    }

    private static func pointsOrOff(_ value: Double) -> String {
        value == 0 ? "off" : points(value)
    }

    private static func makeText(style: NSParagraphStyle) -> NSAttributedString {
        let paragraphs = [
            "Paragraph styles apply to whole paragraphs. Each one here is long enough to wrap, so the line spacing, line height and indents all have lines to act on.",
            "The first line head indent moves only the opening line; the head indent moves the rest. A tail indent pulls the trailing edge in.",
            "Paragraph spacing adds room after each paragraph, and spacing before adds room above it, except above the first.",
        ]
        return NSAttributedString(string: paragraphs.joined(separator: "\n"), attributes: [
            .font: PlatformFont.systemFont(ofSize: 17),
            .foregroundColor: PlatformColor.label,
            .paragraphStyle: style,
        ])
    }
}
