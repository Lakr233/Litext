//
//  LineDrawingActionPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  TextLabel.LineDrawingAction, attached with .litextLineDrawingAction: a
//  closure called once for every line its range touches, after the text is
//  drawn, to add a marker, a wavy underline, a box or a quote bar.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct LineDrawingActionPage: View {
    private static let code = """
    // Called once per visible line the range touches, however many runs
    // CoreText splits it into, after the line's glyphs are drawn. The context
    // is in CoreText space (lower-left origin); origin is the baseline start.
    let marker = TextLabel.LineDrawingAction { context, line, origin in
        // The action gets the whole line: find the marked part in it.
        let start = CTLineGetOffsetForStringIndex(line, max(range.location, lineStart), nil)
        let end = CTLineGetOffsetForStringIndex(line, min(NSMaxRange(range), lineEnd), nil)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        context.setFillColor(color)
        context.fill(CGRect(x: origin.x + start, y: origin.y - descent,
                            width: end - start, height: ascent + descent))
    }
    text.addAttribute(.litextLineDrawingAction, value: marker, range: range)
    """

    enum Style: String, CaseIterable {
        case marker = "Marker"
        case wavy = "Wavy"
        case box = "Box"
    }

    private static let colors: [(name: String, color: PlatformColor)] = [
        ("Yellow", .systemYellow),
        ("Pink", .systemPink),
        ("Green", .systemGreen),
        ("Blue", .systemBlue),
    ]

    @State private var style = Style.marker
    @State private var colorIndex = 0
    @State private var showsQuoteBar = true

    var body: some View {
        CatalogPageScaffold(.lineDrawingAction, code: Self.code) {
            TextLabel(attributedString: Self.text(
                style: style,
                color: Self.colors[colorIndex].color,
                showsQuoteBar: showsQuoteBar,
            ))
            .selectable(true)
            .accessibilityIdentifier("demo.lineDrawing.label")
        } controls: {
            CatalogPicker("Style", selection: $style, options: Style.allCases) { $0.rawValue }
            CatalogPicker("Color", selection: $colorIndex, options: Array(Self.colors.indices)) {
                Self.colors[$0].name
            }
            Toggle("Quote bar", isOn: $showsQuoteBar)
            CatalogNote("Actions draw after the glyphs, so a fill behind text should be translucent. Keep them cheap: they run for every visible line on every display pass.")
        }
    }

    private static func text(style: Style, color: PlatformColor, showsQuoteBar: Bool) -> NSAttributedString {
        let body: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 17),
            .foregroundColor: PlatformColor.label,
        ]
        let text = NSMutableAttributedString(
            string: "A line drawing action decorates the lines its range touches. This sentence marks ",
            attributes: body,
        )
        var marked: [NSRange] = []
        func appendMarked(_ string: String) {
            marked.append(NSRange(location: text.length, length: (string as NSString).length))
            text.append(NSAttributedString(string: string, attributes: body))
        }
        appendMarked("a short phrase")
        text.append(NSAttributedString(string: " and then ", attributes: body))
        appendMarked("a longer one that runs on long enough to wrap across a line break")
        text.append(NSAttributedString(string: ", so one action draws on two lines.\n", attributes: body))
        for range in marked {
            text.addAttribute(
                .litextLineDrawingAction,
                value: LineDecorations.mark(range: range, style: style, color: color),
                range: range,
            )
        }

        let quote = NSMutableParagraphStyle()
        quote.firstLineHeadIndent = 16
        quote.headIndent = 16
        quote.paragraphSpacingBefore = 10
        var quoteAttributes = body
        quoteAttributes[.paragraphStyle] = quote
        quoteAttributes[.foregroundColor] = PlatformColor.secondaryLabel
        quoteAttributes[.font] = PlatformFont.catalogFont(ofSize: 17, italic: true)
        if showsQuoteBar {
            quoteAttributes[.litextLineDrawingAction] = LineDecorations.quoteBar(color: color)
        }
        text.append(NSAttributedString(
            string: "A quote carries one action across the whole paragraph: the bar is drawn line by line, so it follows the paragraph however it wraps.",
            attributes: quoteAttributes,
        ))
        return text
    }
}

/// The drawing behind each style. Each closure works in CoreText space: y grows upward
/// and `origin` is where the line's baseline starts.
private enum LineDecorations {
    static func mark(range: NSRange, style: LineDrawingActionPage.Style, color: PlatformColor) -> TextLabel.LineDrawingAction {
        let cgColor = color.cgColor
        return TextLabel.LineDrawingAction { context, line, origin in
            guard let span = span(of: range, in: line) else { return }
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            let x = origin.x + span.lowerBound
            let width = span.upperBound - span.lowerBound
            switch style {
            case .marker:
                context.setFillColor(cgColor.copy(alpha: 0.35) ?? cgColor)
                context.fill(CGRect(x: x - 1, y: origin.y - descent, width: width + 2, height: ascent * 0.8 + descent))
            case .wavy:
                drawWave(in: context, from: x, to: x + width, y: origin.y - descent * 0.7, color: cgColor)
            case .box:
                context.setStrokeColor(cgColor)
                context.setLineWidth(1.5)
                let box = CGRect(x: x - 2, y: origin.y - descent - 1, width: width + 4, height: ascent + descent + 2)
                context.addPath(CGPath(roundedRect: box, cornerWidth: 4, cornerHeight: 4, transform: nil))
                context.strokePath()
            }
        }
    }

    static func quoteBar(color: PlatformColor) -> TextLabel.LineDrawingAction {
        let cgColor = color.cgColor
        return TextLabel.LineDrawingAction { context, line, origin in
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            // The line origin includes the head indent; the bar sits in the indent.
            context.setFillColor(cgColor)
            context.fill(CGRect(x: 2, y: origin.y - descent - leading, width: 3, height: ascent + descent + leading))
        }
    }

    /// The horizontal extent of `range` within `line`, in the line's own coordinates.
    private static func span(of range: NSRange, in line: CTLine) -> ClosedRange<CGFloat>? {
        let lineRange = CTLineGetStringRange(line)
        let start = max(range.location, lineRange.location)
        let end = min(NSMaxRange(range), lineRange.location + lineRange.length)
        guard start < end else { return nil }
        let startOffset = CTLineGetOffsetForStringIndex(line, start, nil)
        let endOffset = CTLineGetOffsetForStringIndex(line, end, nil)
        return min(startOffset, endOffset) ... max(startOffset, endOffset)
    }

    private static func drawWave(in context: CGContext, from startX: CGFloat, to endX: CGFloat, y: CGFloat, color: CGColor) {
        let wavelength: CGFloat = 6
        let amplitude: CGFloat = 1.5
        context.setStrokeColor(color)
        context.setLineWidth(1.5)
        context.move(to: CGPoint(x: startX, y: y))
        var x = startX
        var up = true
        while x < endX {
            let next = min(x + wavelength / 2, endX)
            context.addQuadCurve(
                to: CGPoint(x: next, y: y),
                control: CGPoint(x: (x + next) / 2, y: y + (up ? amplitude : -amplitude) * 2),
            )
            x = next
            up.toggle()
        }
        context.strokePath()
    }
}
