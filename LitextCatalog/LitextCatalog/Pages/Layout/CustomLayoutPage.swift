//
//  CustomLayoutPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  A TextLabelView subclass that hands its text to a TextLabel.Layout
//  subclass through makeTextLayout(_:). The layout overrides
//  draw(line:at:in:) to paint stripes and a highlighted line behind the
//  glyphs, while measurement, hit testing and selection stay Litext's own.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct CustomLayoutPage: View {
    private static let code = """
    final class StripedLayout: TextLabel.Layout {
        var highlightedLine: Int?
        var stripeColor: CGColor = …

        override func draw(line: CTLine, at index: Int, in context: CGContext) {
            // The context is in CoreText space; textPosition is the baseline origin.
            let origin = context.textPosition
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            if index == highlightedLine || index % 2 == 1 {
                context.setFillColor(stripeColor)
                context.fill(CGRect(x: 0, y: origin.y - descent - leading,
                                    width: containerSize.width, height: ascent + descent + leading))
            }
            super.draw(line: line, at: index, in: context)   // the glyphs
        }
    }

    final class StripedLabelView: TextLabelView {
        override func makeTextLayout(_ text: NSAttributedString) -> TextLabel.Layout {
            StripedLayout(attributedString: text)   // once per new string
        }
    }

    // State draw(line:) reads changed: redraw without re-typesetting.
    (label.textLayout as? StripedLayout)?.highlightedLine = 2
    label.setNeedsTextDisplay()
    """

    private static let colors: [(name: String, color: PlatformColor)] = [
        ("Blue", .systemBlue),
        ("Green", .systemGreen),
        ("Orange", .systemOrange),
        ("Pink", .systemPink),
    ]

    @State private var model = CustomLayoutModel()
    @State private var usesCustomLayout = true
    @State private var stripes = true
    @State private var colorIndex = 0
    @State private var highlightedLine = 0.0
    @State private var lineSpacing = 4.0

    var body: some View {
        CatalogPageScaffold(.customLayout, code: Self.code) {
            PlatformViewHost<StripedLabelView>.label {
                let label = StripedLabelView()
                label.usesCustomLayout = usesCustomLayout
                label.isSelectable = true
                let recorder = model
                label.onMakeTextLayout = { [weak recorder] in recorder?.recordMakeTextLayout() }
                recorder.label = label
                return label
            } update: { label in
                let text = Self.text(lineSpacing: lineSpacing)
                if !label.attributedText.isEqual(to: text) {
                    label.attributedText = text
                }
                if let layout = label.textLayout as? StripedTextLayout {
                    let color = Self.colors[colorIndex].color
                    layout.stripeColor = color.withAlphaComponent(0.1).cgColor
                    layout.highlightColor = color.withAlphaComponent(0.3).cgColor
                    layout.showsStripes = stripes
                    layout.highlightedLine = model.hoveredLine ?? (highlightedLine > 0 ? Int(highlightedLine) - 1 : nil)
                }
                label.setNeedsTextDisplay()
            }
            // makeTextLayout(_:) runs only for a new string, so switching the
            // subclass on and off builds a new label.
            .id(usesCustomLayout)
            #if !os(tvOS)
                .onContinuousHover { phase in
                    switch phase {
                    case let .active(location): model.hover(at: location)
                    case .ended: model.hover(at: nil)
                    }
                }
            #endif
                .accessibilityIdentifier("demo.customLayout.label")
        } controls: {
            Toggle("Use StripedLayout (makeTextLayout)", isOn: $usesCustomLayout)
            Toggle("Alternate line stripes", isOn: $stripes)
                .disabled(!usesCustomLayout)
            CatalogPicker("Color", selection: $colorIndex, options: Array(Self.colors.indices)) {
                Self.colors[$0].name
            }
            .disabled(!usesCustomLayout)
            CatalogSlider("Highlighted line", value: $highlightedLine, in: 0 ... 12, step: 1) {
                $0 == 0 ? "none" : "\(Int($0))"
            }
            .disabled(!usesCustomLayout)
            CatalogSlider("Line spacing", value: $lineSpacing, in: 0 ... 16, step: 1) { "\(Int($0)) pt" }
            CatalogReadout(
                "textLayout",
                value: usesCustomLayout ? "StripedTextLayout" : "TextLabel.Layout",
                identifier: "state.customLayout.class",
            )
            CatalogReadout("makeTextLayout calls", value: "\(model.makeTextLayoutCalls)", identifier: "state.customLayout.calls")
            CatalogReadout(
                "Line under the pointer",
                value: model.hoveredLine.map { "\($0 + 1)" } ?? "none",
                identifier: "state.customLayout.hovered",
            )
            CatalogNote("Changing the line spacing builds a new string, so makeTextLayout runs again; the color and the highlight only redraw.")
        }
    }

    private static func text(lineSpacing: Double) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        return NSAttributedString(
            string: "A layout subclass sees every line as it is drawn. This one paints a stripe behind every other line and a stronger band behind the line you point at, then calls super to draw the glyphs on top. Measurement, hit testing and selection are untouched: select some text to see the selection drawn over the stripes. Hover over a line on a Mac or an iPad with a pointer, or pick one with the slider.",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 17),
                .foregroundColor: PlatformColor.label,
                .paragraphStyle: paragraph,
            ],
        )
    }
}

/// Paints alternate stripes and one highlighted line behind the glyphs.
final class StripedTextLayout: TextLabel.Layout {
    var showsStripes = true
    var highlightedLine: Int?
    var stripeColor = PlatformColor.systemBlue.withAlphaComponent(0.1).cgColor
    var highlightColor = PlatformColor.systemBlue.withAlphaComponent(0.3).cgColor

    override func draw(line: CTLine, at index: Int, in context: CGContext) {
        let fill: CGColor? = if index == highlightedLine {
            highlightColor
        } else if showsStripes, index % 2 == 1 {
            stripeColor
        } else {
            nil
        }
        if let fill {
            let origin = context.textPosition
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            context.saveGState()
            context.setFillColor(fill)
            context.fill(CGRect(
                x: 0,
                y: origin.y - descent - leading,
                width: containerSize.width,
                height: ascent + descent + leading,
            ))
            context.restoreGState()
            context.textPosition = origin
        }
        super.draw(line: line, at: index, in: context)
    }
}

/// Hands every new string to a `StripedTextLayout` while `usesCustomLayout` is on.
final class StripedLabelView: TextLabelView {
    var usesCustomLayout = true
    var onMakeTextLayout: (() -> Void)?

    override func makeTextLayout(_ attributedText: NSAttributedString) -> TextLabel.Layout {
        onMakeTextLayout?()
        guard usesCustomLayout else { return super.makeTextLayout(attributedText) }
        return StripedTextLayout(attributedString: attributedText)
    }
}

@Observable
private final class CustomLayoutModel {
    var makeTextLayoutCalls = 0
    var hoveredLine: Int?
    @ObservationIgnored weak var label: StripedLabelView?

    func recordMakeTextLayout() {
        // makeTextLayout runs while SwiftUI updates the view; count it afterwards.
        Task { @MainActor in self.makeTextLayoutCalls += 1 }
    }

    func hover(at location: CGPoint?) {
        guard let label, let location else {
            hoveredLine = nil
            return
        }
        let point = label.layoutPoint(fromViewPoint: location)
        // Lines run top to bottom, and layout space grows upward: the first line whose
        // bottom is below the point is the one under it, the spacing above it included.
        let lines = label.layoutLines
        let line = point.y > (lines.first?.rect.maxY ?? 0) ? nil : lines.first { $0.rect.minY <= point.y }
        if hoveredLine != line?.index {
            hoveredLine = line?.index
        }
    }
}
