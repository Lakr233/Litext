//
//  ShadowsPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  NSShadow on a headline and on a run inside body text, drawn by CoreText
//  from the .shadow attribute.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct ShadowsPage: View {
    private static let code = """
    let shadow = NSShadow()
    shadow.shadowOffset = CGSize(width: 2, height: 3)
    shadow.shadowBlurRadius = 4
    shadow.shadowColor = PlatformColor.black.withAlphaComponent(0.4)

    text.addAttribute(.shadow, value: shadow, range: range)
    """

    @State private var offsetX = 3.0
    @State private var offsetY = 4.0
    @State private var blur = 2.0
    @State private var swatch = ShadowSwatch.pink
    @State private var opacity = 0.7

    private var shadow: NSShadow {
        let shadow = NSShadow()
        shadow.shadowOffset = CGSize(width: offsetX, height: offsetY)
        shadow.shadowBlurRadius = blur
        shadow.shadowColor = swatch.color.withAlphaComponent(opacity)
        return shadow
    }

    var body: some View {
        CatalogPageScaffold(.shadows, code: Self.code) {
            TextLabel(attributedString: Self.makeText(shadow: shadow))
                .accessibilityIdentifier("demo.shadows.label")
        } controls: {
            CatalogSlider("Offset x", value: $offsetX, in: -10 ... 10, step: 0.5, format: TypographyMeasure.points)
            CatalogSlider("Offset y", value: $offsetY, in: -10 ... 10, step: 0.5, format: TypographyMeasure.points)
            CatalogSlider("Blur radius", value: $blur, in: 0 ... 12, step: 0.5, format: TypographyMeasure.points)
            CatalogPicker("Color", selection: $swatch, options: ShadowSwatch.allCases) { $0.title }
            CatalogSlider("Opacity", value: $opacity, in: 0.1 ... 1, step: 0.05) { "\(Int(($0 * 100).rounded())) %" }
            CatalogNote(Self.directionNote, systemImage: "info.circle")
            CatalogNote(
                "The shadow does not change the measured size, so a large offset or blur near the edge of the label can be clipped.",
                systemImage: "exclamationmark.triangle",
            )
        }
    }

    private static var directionNote: String {
        #if canImport(UIKit)
            "A positive y offset moves the shadow down, as NSShadow does in UIKit."
        #else
            "A positive y offset moves the shadow up, as NSShadow does in AppKit."
        #endif
    }

    private static func makeText(shadow: NSShadow) -> NSAttributedString {
        let text = NSMutableAttributedString(string: "Long Shadows\n", attributes: [
            .font: PlatformFont.systemFont(ofSize: 40, weight: .black),
            .foregroundColor: PlatformColor.label,
            .shadow: shadow,
        ])
        let body: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 17),
            .foregroundColor: PlatformColor.label,
        ]
        text.append(NSAttributedString(string: "A shadow can also sit on ", attributes: body))
        var lifted = body
        lifted[.font] = PlatformFont.systemFont(ofSize: 17, weight: .semibold)
        lifted[.foregroundColor] = PlatformColor.systemBlue
        lifted[.shadow] = shadow
        text.append(NSAttributedString(string: "a single run", attributes: lifted))
        text.append(NSAttributedString(string: " inside body text, while the words around it stay flat.", attributes: body))
        return text
    }
}

enum ShadowSwatch: String, CaseIterable, Identifiable {
    case black
    case blue
    case pink
    case orange

    var id: Self {
        self
    }

    var title: String {
        rawValue.capitalized
    }

    var color: PlatformColor {
        switch self {
        case .black: .black
        case .blue: .systemBlue
        case .pink: .systemPink
        case .orange: .systemOrange
        }
    }
}
