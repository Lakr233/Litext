//
//  SizingPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  The three ways to ask how big text is — TextLabelView.sizeThatFits,
//  intrinsicContentSize with preferredMaxLayoutWidth, and
//  TextLabel.Layout.sizeThatFits — side by side for the same text.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct SizingPage: View {
    private static let code = """
    // Like UILabel: wrap at the width, height unlimited. Zero or an invalid
    // width leaves the text unwrapped. Rounded up to the pixel grid.
    let fitting = label.sizeThatFits(CGSize(width: 240, height: 0))

    // Auto Layout: wraps at preferredMaxLayoutWidth, or at the width the
    // label was last laid out at when it is 0.
    label.preferredMaxLayoutWidth = 240
    let intrinsic = label.intrinsicContentSize

    // Without a view. Zero or .greatestFiniteMagnitude is unconstrained;
    // a NaN, negative or infinite size is invalid and measures as .zero.
    let layout = TextLabel.Layout(attributedString: text)
    let measured = layout.sizeThatFits(CGSize(width: 240, height: .greatestFiniteMagnitude))
    """

    @State private var model = SizingModel()
    @State private var width = 240.0
    @State private var preferredWidth = 0.0

    var body: some View {
        let fitting = model.label.sizeThatFits(CGSize(width: width, height: 0))
        CatalogPageScaffold(.sizing, code: Self.code) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal) {
                    PlatformViewHost<TextLabelView> {
                        let label = TextLabelView()
                        label.attributedText = SizingModel.text
                        return label
                    } fittingSize: { label, _ in
                        label.sizeThatFits(CGSize(width: width, height: 0))
                    }
                    .overlay {
                        Rectangle()
                            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                    .padding(1)
                }
                .accessibilityIdentifier("demo.sizing.label")
                Text("The dashed box is the size sizeThatFits returned for a width of \(Self.widthLabel(width)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } controls: {
            CatalogSlider("Width", value: $width, in: 0 ... 600, step: 1) { Self.widthLabel($0) }
            CatalogSlider("preferredMaxLayoutWidth", value: $preferredWidth, in: 0 ... 600, step: 1) {
                $0 == 0 ? "0 (unset)" : "\(Int($0)) pt"
            }
            CatalogReadout(
                "label.sizeThatFits",
                value: Self.describe(fitting),
                identifier: "state.sizing.labelFits",
            )
            CatalogReadout(
                "layout.sizeThatFits",
                value: Self.describe(model.layout.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))),
                identifier: "state.sizing.layoutFits",
            )
            CatalogReadout(
                "intrinsicContentSize",
                value: Self.describe(model.intrinsicSize(preferredMaxLayoutWidth: preferredWidth)),
                identifier: "state.sizing.intrinsic",
            )
            CatalogReadout(
                "Layout, NaN width",
                value: Self.describe(model.layout.sizeThatFits(CGSize(width: CGFloat.nan, height: 100))),
                identifier: "state.sizing.invalid",
            )
            CatalogReadout(
                "Label, width −20",
                value: Self.describe(model.label.sizeThatFits(CGSize(width: -20, height: 0))),
                identifier: "state.sizing.negative",
            )
            CatalogNote(
                "The label rounds up to the pixel grid; the layout reports CoreText's fractional size. A zero width is unconstrained for both, and an invalid size is skipped rather than measured.",
            )
        }
    }

    private static func widthLabel(_ width: Double) -> String {
        width == 0 ? "0 (unconstrained)" : "\(Int(width)) pt"
    }

    private static func describe(_ size: CGSize) -> String {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0 ... 2))
        return "\(Double(size.width).formatted(format)) × \(Double(size.height).formatted(format))"
    }
}

/// The label and layout the readouts measure. The label here is never laid out,
/// so with preferredMaxLayoutWidth at 0 its intrinsic size is the unwrapped text.
@MainActor
private final class SizingModel {
    static let text: NSAttributedString = {
        let text = NSMutableAttributedString(
            string: "Sizes come from typographic bounds, the way UILabel computes them. ",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 17),
                .foregroundColor: PlatformColor.label,
            ],
        )
        text.append(NSAttributedString(
            string: "Narrow the width and the text wraps into more lines.",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 17, weight: .semibold),
                .foregroundColor: PlatformColor.label,
            ],
        ))
        return text
    }()

    let label = TextLabelView(attributedText: SizingModel.text)
    let layout = TextLabel.Layout(attributedString: SizingModel.text)

    func intrinsicSize(preferredMaxLayoutWidth: Double) -> CGSize {
        label.preferredMaxLayoutWidth = preferredMaxLayoutWidth
        return label.intrinsicContentSize
    }
}
