//
//  BaselineOffsetPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  .baselineOffset raises or lowers a run off the line's baseline: the way to
//  set superscripts, subscripts, footnote marks and raised badges.
//

import CoreText
import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct BaselineOffsetPage: View {
    private static let code = """
    // A smaller font, raised: a superscript.
    text.addAttributes([
        .font: PlatformFont.systemFont(ofSize: 17 * 0.6),
        .baselineOffset: 7,
    ], range: exponentRange)

    // A negative offset lowers the run: a subscript.
    text.addAttributes([
        .font: PlatformFont.systemFont(ofSize: 17 * 0.6),
        .baselineOffset: -3,
    ], range: indexRange)
    """

    @State private var offset = 6.0
    @State private var scale = 0.6
    @State private var showsBaselines = true

    private var specimen: NSAttributedString {
        Self.specimen(offset: offset, scale: scale, showsBaselines: showsBaselines)
    }

    var body: some View {
        CatalogPageScaffold(.baselineOffset, code: Self.code) {
            VStack(alignment: .leading, spacing: 16) {
                TextLabel(attributedString: specimen)
                    .accessibilityIdentifier("demo.baselineOffset.specimen")
                Divider()
                TextLabel(attributedString: Self.examples(showsBaselines: showsBaselines))
                    .accessibilityIdentifier("demo.baselineOffset.examples")
            }
        } controls: {
            CatalogSlider("Offset", value: $offset, in: -10 ... 10, step: 0.5, format: TypographyMeasure.points)
            CatalogSlider("Font scale of the shifted run", value: $scale, in: 0.4 ... 1, step: 0.05) {
                "× " + $0.formatted(.number.precision(.fractionLength(2)))
            }
            Toggle("Show baselines", isOn: $showsBaselines)
            CatalogReadout(
                "Specimen height",
                value: TypographyMeasure.points(TypographyMeasure.size(of: specimen).height),
                identifier: "state.baselineOffset.height",
            )
            CatalogReadout(
                "Height without offset",
                value: TypographyMeasure.points(TypographyMeasure.size(
                    of: Self.specimen(offset: 0, scale: scale, showsBaselines: false),
                ).height),
                identifier: "state.baselineOffset.baseHeight",
            )
            CatalogNote(
                "A raised run that reaches above the line's ascent, or a lowered one that reaches below its descent, makes that line taller by the overshoot and pushes its neighbours apart. A small run that stays inside changes nothing: compare the two heights.",
            )
        }
    }

    private static func specimen(offset: Double, scale: Double, showsBaselines: Bool) -> NSAttributedString {
        let size: CGFloat = 28
        let text = NSMutableAttributedString(string: "Baseline ", attributes: [
            .font: PlatformFont.systemFont(ofSize: size),
            .foregroundColor: PlatformColor.label,
        ])
        text.append(NSAttributedString(string: "shifted", attributes: [
            .font: PlatformFont.systemFont(ofSize: size * scale, weight: .semibold),
            .foregroundColor: PlatformColor.systemBlue,
            .baselineOffset: offset,
        ]))
        text.append(NSAttributedString(string: " baseline\nand the line below it.", attributes: [
            .font: PlatformFont.systemFont(ofSize: size),
            .foregroundColor: PlatformColor.label,
        ]))
        if showsBaselines {
            addBaselines(to: text)
        }
        return text
    }

    /// Superscripts, subscripts, footnote marks and a raised badge.
    private static func examples(showsBaselines: Bool) -> NSAttributedString {
        let size: CGFloat = 19
        let body: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: size),
            .foregroundColor: PlatformColor.label,
        ]
        let small = PlatformFont.systemFont(ofSize: size * 0.6)
        let text = NSMutableAttributedString()
        func append(_ string: String, _ attributes: [NSAttributedString.Key: Any] = [:]) {
            text.append(NSAttributedString(string: string, attributes: body.merging(attributes) { $1 }))
        }

        append("E = mc")
        append("2", [.font: small, .baselineOffset: size * 0.4])
        append("   H")
        append("2", [.font: small, .baselineOffset: -size * 0.15])
        append("O   x")
        append("n+1", [.font: small, .baselineOffset: size * 0.4])
        append("\nAs the footnote says")
        append("1", [.font: small, .baselineOffset: size * 0.4, .foregroundColor: PlatformColor.systemBlue])
        append(", every claim needs a source")
        append("2", [.font: small, .baselineOffset: size * 0.4, .foregroundColor: PlatformColor.systemBlue])
        append(".\nLitext ")
        append(" NEW ", [
            .font: PlatformFont.systemFont(ofSize: size * 0.55, weight: .bold),
            .foregroundColor: PlatformColor.white,
            .backgroundColor: PlatformColor.systemPink,
            .baselineOffset: size * 0.35,
            .kern: 0.5,
        ])
        append(" with a raised badge.")
        if showsBaselines {
            addBaselines(to: text)
        }
        return text
    }

    /// Draws each line's baseline as a thin rule, so offsets can be read against it.
    private static func addBaselines(to text: NSMutableAttributedString) {
        let rule = CGColor(red: 1, green: 0.23, blue: 0.19, alpha: 0.6)
        let action = TextLabel.LineDrawingAction { context, line, origin in
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            context.setStrokeColor(rule)
            context.setLineWidth(0.5)
            context.setLineDash(phase: 0, lengths: [3, 2])
            context.move(to: CGPoint(x: origin.x, y: origin.y))
            context.addLine(to: CGPoint(x: origin.x + width, y: origin.y))
            context.strokePath()
        }
        text.addAttribute(.litextLineDrawingAction, value: action, range: NSRange(location: 0, length: text.length))
    }
}
