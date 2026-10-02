//
//  KerningPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Character spacing through .kern and .tracking, on a whole string and on a
//  single run, with the width TextLabel.Layout measures for it.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct KerningPage: View {
    private static let code = """
    // Points added after each character, on the whole string or one run.
    let headline = NSAttributedString(string: "Tight Headline", attributes: [
        .font: PlatformFont.systemFont(ofSize: 34, weight: .bold),
        .kern: -1.2,
    ])
    text.addAttribute(.kern, value: 3, range: allCapsRange)

    // .tracking spaces characters too.
    text.addAttribute(.tracking, value: 3, range: range)

    // The width the label will take for it.
    let layout = TextLabel.Layout(attributedString: headline)
    let width = layout.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude,
                                           height: .greatestFiniteMagnitude)).width
    """

    enum Spacing: String, CaseIterable, Identifiable {
        case kern
        case tracking

        var id: Self {
            self
        }

        var key: NSAttributedString.Key {
            switch self {
            case .kern: .kern
            case .tracking: .tracking
            }
        }

        var title: String {
            ".\(rawValue)"
        }
    }

    private static let headlineString = "Litext Typography"

    @State private var spacing = 1.5
    @State private var attribute = Spacing.kern

    private var headline: NSAttributedString {
        Self.headline(spacing: spacing, key: attribute.key)
    }

    var body: some View {
        CatalogPageScaffold(.kerning, code: Self.code) {
            VStack(alignment: .leading, spacing: 16) {
                TextLabel(attributedString: headline)
                    .accessibilityIdentifier("demo.kerning.headline")
                Divider()
                TextLabel(attributedString: Self.samples())
                    .accessibilityIdentifier("demo.kerning.samples")
            }
        } controls: {
            CatalogSlider("Spacing", value: $spacing, in: -2 ... 10, step: 0.1) { TypographyMeasure.points($0) }
            CatalogPicker("Attribute", selection: $attribute, options: Spacing.allCases) { $0.title }
            CatalogReadout(
                "Measured width",
                value: TypographyMeasure.points(TypographyMeasure.size(of: headline).width),
                identifier: "state.kerning.width",
            )
            CatalogReadout(
                "Width without spacing",
                value: TypographyMeasure.points(TypographyMeasure.size(of: Self.headline(spacing: 0, key: .kern)).width),
                identifier: "state.kerning.baseWidth",
            )
            CatalogNote("The measured width comes from TextLabel.Layout.sizeThatFits, the same measurement the label sizes itself with.")
        }
    }

    private static func headline(spacing: Double, key: NSAttributedString.Key) -> NSAttributedString {
        NSAttributedString(string: headlineString, attributes: [
            .font: PlatformFont.systemFont(ofSize: 34, weight: .bold),
            .foregroundColor: PlatformColor.label,
            key: spacing,
        ])
    }

    /// A tight headline, a loose all-caps label and a single spaced-out run in body text.
    private static func samples() -> NSAttributedString {
        let body: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 17),
            .foregroundColor: PlatformColor.label,
        ]
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "NEW ARRIVALS\n", attributes: [
            .font: PlatformFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: PlatformColor.secondaryLabel,
            .kern: 3,
        ]))
        text.append(NSAttributedString(string: "Display headline at −1 pt\n", attributes: [
            .font: PlatformFont.systemFont(ofSize: 28, weight: .heavy),
            .foregroundColor: PlatformColor.label,
            .kern: -1,
        ]))
        text.append(NSAttributedString(string: "Body text with one ", attributes: body))
        var spaced = body
        spaced[.kern] = 4
        spaced[.foregroundColor] = PlatformColor.systemBlue
        text.append(NSAttributedString(string: "spaced-out", attributes: spaced))
        text.append(NSAttributedString(string: " run in the middle of the sentence.", attributes: body))
        return text
    }
}
