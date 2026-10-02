//
//  LineBreakingPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Where lines break is up to CoreText and the paragraph style: by word, by
//  character, or one truncated line per paragraph. Litext has no numberOfLines
//  of its own; this page shows what the paragraph style does, that CoreText
//  does not hyphenate, and how to cap the height instead.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct LineBreakingPage: View {
    private static let code = """
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byWordWrapping     // or .byCharWrapping
    // .byTruncatingTail and friends set each paragraph on one line,
    // ending it with an ellipsis.

    // CoreText ignores these: Litext's layout never hyphenates.
    style.hyphenationFactor = 0.8
    style.usesDefaultHyphenation = true

    TextLabel(attributedString: NSAttributedString(string: text, attributes: [
        .font: PlatformFont.systemFont(ofSize: 17),
        .paragraphStyle: style,
    ]))
    .frame(width: 180)

    // There is no numberOfLines. To show only the first lines, give the
    // label a shorter frame: only the lines that fit whole are drawn.
    let layout = TextLabel.Layout(attributedString: text)
    layout.containerSize = layout.sizeThatFits(CGSize(width: 180, height: .greatestFiniteMagnitude))
    let threeLines = layout.viewRect(fromLayoutRect: layout.layoutLines[2].rect).maxY
    TextLabel(attributedString: text)
        .frame(width: 180, height: threeLines, alignment: .top)
    """

    private static let modes: [(name: String, mode: NSLineBreakMode)] = [
        ("Word wrap", .byWordWrapping),
        ("Char wrap", .byCharWrapping),
        ("Clip", .byClipping),
        ("Truncate head", .byTruncatingHead),
        ("Truncate tail", .byTruncatingTail),
        ("Truncate middle", .byTruncatingMiddle),
    ]

    @State private var width = 220.0
    @State private var modeIndex = 0
    @State private var hyphenation = 0.0
    @State private var usesDefaultHyphenation = false
    @State private var capsLines = false
    @State private var lineCap = 3.0
    @State private var availableWidth: CGFloat = 0

    private var text: NSAttributedString {
        Self.makeText(
            mode: Self.modes[modeIndex].mode,
            hyphenation: hyphenation,
            usesDefaultHyphenation: usesDefaultHyphenation,
        )
    }

    /// The width the label actually gets: the slider's, unless the demo card is narrower.
    private var labelWidth: CGFloat {
        guard availableWidth > 0 else { return width }
        return min(width, availableWidth)
    }

    var body: some View {
        let text = text
        let lineCount = TypographyMeasure.lineCount(of: text, width: labelWidth)
        let cappedHeight = capsLines ? Self.height(of: text, width: labelWidth, lines: Int(lineCap)) : nil

        CatalogPageScaffold(.lineBreaking, code: Self.code) {
            VStack(alignment: .leading, spacing: 0) {
                TextLabel(attributedString: text)
                    .frame(width: labelWidth, height: cappedHeight, alignment: .top)
                    .clipped()
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.6))
                            .frame(width: 1)
                    }
                    .accessibilityIdentifier("demo.lineBreaking.label")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { availableWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, newWidth in availableWidth = newWidth }
                }
            }
        } controls: {
            CatalogSlider("Width", value: $width, in: 60 ... 700, step: 1) { "\(Int($0)) pt" }
            TypographyMenuPicker("Line break mode", selection: $modeIndex, options: Array(Self.modes.indices)) {
                Self.modes[$0].name
            }
            .accessibilityIdentifier("demo.lineBreaking.mode")
            CatalogSlider("Hyphenation factor", value: $hyphenation, in: 0 ... 1, step: 0.05) {
                $0.formatted(.number.precision(.fractionLength(2)))
            }
            Toggle("Uses default hyphenation", isOn: $usesDefaultHyphenation)
            Toggle("Cap the height", isOn: $capsLines)
            if capsLines {
                CatalogSlider("Lines to show", value: $lineCap, in: 1 ... 8, step: 1) { "\(Int($0))" }
            }
            CatalogReadout("Label width", value: "\(Int(labelWidth)) pt", identifier: "state.lineBreaking.width")
            CatalogReadout("Lines laid out", value: "\(lineCount)", identifier: "state.lineBreaking.lines")
            CatalogNote(Self.modeNote(Self.modes[modeIndex].mode), systemImage: "info.circle")
            CatalogNote(
                "CoreText, which Litext lays out with, does not hyphenate: the hyphenation factor and the default hyphenation switch leave the lines as they are. Soft hyphens (U+00AD) in the string do allow a break, but no hyphen is drawn there.",
                systemImage: "exclamationmark.triangle",
            )
            CatalogNote(
                "Litext has no numberOfLines. Cap the height with a frame instead: only the lines that fit whole are laid out and drawn, with no ellipsis on the last one. For an ellipsis there, shorten the string yourself or draw that line in a TextLabel.Layout subclass.",
                systemImage: "exclamationmark.triangle",
            )
        }
    }

    private static func modeNote(_ mode: NSLineBreakMode) -> String {
        switch mode {
        case .byWordWrapping:
            "Lines break between words and after punctuation such as the slashes in the URL. A word longer than the whole line is split wherever it reaches the edge."
        case .byCharWrapping:
            "Lines break after whichever character reaches the edge, in the middle of words."
        case .byClipping:
            "Clipping does not wrap: each paragraph is set on one line that runs past the edge. The demo clips the label to its frame."
        default:
            "Truncating modes do not wrap: CoreText sets each paragraph on one line and replaces what does not fit with an ellipsis at the head, the middle or the tail."
        }
    }

    /// The height of the first `lines` lines of `text` at `width`.
    private static func height(of text: NSAttributedString, width: CGFloat, lines: Int) -> CGFloat {
        let layout = TextLabel.Layout(attributedString: text)
        layout.containerSize = layout.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let laidOut = layout.layoutLines
        guard !laidOut.isEmpty else { return 0 }
        let last = laidOut[min(lines, laidOut.count) - 1]
        return layout.viewRect(fromLayoutRect: last.rect).maxY.rounded(.up)
    }

    private static func makeText(
        mode: NSLineBreakMode,
        hyphenation: Double,
        usesDefaultHyphenation: Bool,
    ) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = mode
        style.hyphenationFactor = Float(hyphenation)
        style.usesDefaultHyphenation = usesDefaultHyphenation
        style.paragraphSpacing = 8
        let string = [
            "Hyphenation helps narrow columns with internationalization, incomprehensibilities and characteristically long words.",
            "A long URL has nowhere to break but its punctuation: https://example.com/a/very/long/path/that/cannot/wrap/at/a/space",
            "Supercalifragilisticexpialidocious is one unbreakable word.",
        ].joined(separator: "\n")
        return NSAttributedString(string: string, attributes: [
            .font: PlatformFont.systemFont(ofSize: 17),
            .foregroundColor: PlatformColor.label,
            .paragraphStyle: style,
        ])
    }
}
