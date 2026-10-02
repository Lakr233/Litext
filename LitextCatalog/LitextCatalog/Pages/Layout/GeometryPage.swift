//
//  GeometryPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  The geometry a layout reports — line boxes, baselines, glyph runs and the
//  rects of a range — drawn over the text it describes.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct GeometryPage: View {
    private static let code = """
    // Geometry is in CoreText layout space (lower-left origin);
    // convert it before drawing in the view.
    for line in label.layoutLines {
        let box = label.viewRect(fromLayoutRect: line.rect)
        let baselineY = label.viewRect(fromLayoutRect: CGRect(
            origin: line.baselineOrigin, size: .zero,
        )).minY
        print(line.index, line.stringRange, box, baselineY)
    }

    // Glyph runs carrying an attribute: links, or a key of your own.
    for run in label.layoutRuns(matching: .link) {
        print(run.lineIndex, run.stringRange, label.viewRect(fromLayoutRect: run.rect))
    }

    // The rects covering a range: one per line, more on a bidi line.
    let rects = label.textLayout.rects(for: NSRange(location: 40, length: 90))
    label.textLayout.enumerateTextRects(in: range) { rect in /* … */ }
    """

    @State private var showsLines = true
    @State private var showsBaselines = true
    @State private var showsLinkRuns = true
    @State private var showsTagRuns = false
    @State private var showsRange = false
    @State private var rangeStart = 40.0
    @State private var rangeLength = 90.0
    @State private var stats = GeometryStats()

    var body: some View {
        CatalogPageScaffold(.geometry, code: Self.code) {
            VStack(alignment: .leading, spacing: 12) {
                PlatformViewHost<OverlayLabelView>.label {
                    let label = OverlayLabelView()
                    label.attributedText = Self.text
                    label.isSelectable = true
                    return label
                } update: { label in
                    let options = GeometryOverlayOptions(
                        showsLines: showsLines,
                        showsBaselines: showsBaselines,
                        showsLinkRuns: showsLinkRuns,
                        showsTagRuns: showsTagRuns,
                        range: showsRange ? NSRange(location: Int(rangeStart), length: Int(rangeLength)) : nil,
                    )
                    let stats = stats
                    label.overlay = { label, context in
                        let measured = GeometryOverlay.draw(options, over: label, in: context)
                        // Report counts after the draw pass, outside of the SwiftUI update.
                        Task { @MainActor in
                            if stats.lines != measured.lines || stats.linkRuns != measured.linkRuns
                                || stats.tagRuns != measured.tagRuns || stats.rangeRects != measured.rangeRects
                            {
                                stats.update(from: measured)
                            }
                        }
                    }
                    label.setNeedsTextDisplay()
                }
                .accessibilityIdentifier("demo.geometry.label")

                GeometryLegend()
            }
        } controls: {
            Toggle("Line boxes (LayoutLine.rect)", isOn: $showsLines)
            Toggle("Baselines (baselineOrigin)", isOn: $showsBaselines)
            Toggle("Link runs (layoutRuns(matching: .link))", isOn: $showsLinkRuns)
            Toggle("Tagged runs (custom key)", isOn: $showsTagRuns)
            Toggle("rects(for:) of a range", isOn: $showsRange)
            if showsRange {
                CatalogSlider("Range start", value: $rangeStart, in: 0 ... Double(Self.text.length - 1), step: 1) {
                    "\(Int($0))"
                }
                CatalogSlider("Range length", value: $rangeLength, in: 0 ... 200, step: 1) { "\(Int($0))" }
            }
            CatalogReadout("Lines", value: "\(stats.lines)", identifier: "state.geometry.lines")
            CatalogReadout("Link runs", value: "\(stats.linkRuns)", identifier: "state.geometry.linkRuns")
            CatalogReadout("Tagged runs", value: "\(stats.tagRuns)", identifier: "state.geometry.tagRuns")
            CatalogReadout(
                "Range rects",
                value: showsRange ? "\(stats.rangeRects)" : "off",
                identifier: "state.geometry.rangeRects",
            )
            CatalogNote("A run ends wherever attributes or the font change, so one styled word can be several runs.")
        }
    }

    static let tagKey = NSAttributedString.Key("catalog.geometry.tag")

    static let text: NSAttributedString = {
        let body: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 17),
            .foregroundColor: PlatformColor.label,
        ]
        let text = NSMutableAttributedString()
        func append(_ string: String, _ extra: [NSAttributedString.Key: Any] = [:]) {
            text.append(NSAttributedString(string: string, attributes: body.merging(extra) { $1 }))
        }
        append("Every laid-out line has a box from its descent to its ascent and a ")
        append("baseline", [.font: PlatformFont.systemFont(ofSize: 26, weight: .bold), tagKey: true])
        append(" the glyphs sit on. A larger run raises the line it lives on. ")
        append("Links", [.link: URL(string: "https://github.com/Lakr233/Litext")!, .foregroundColor: PlatformColor.systemBlue])
        append(" are runs too, and a link that ")
        append(
            "wraps onto the next line comes back as one run per line",
            [.link: URL(string: "https://developer.apple.com/documentation/coretext")!, .foregroundColor: PlatformColor.systemBlue],
        )
        append(". Runs can carry ")
        append("any key of your own", [tagKey: true, .font: PlatformFont.catalogFont(ofSize: 17, italic: true)])
        append(", and ")
        append("small print", [.font: PlatformFont.systemFont(ofSize: 12), tagKey: true])
        append(" keeps its own metrics inside the line.")
        return text
    }()
}

/// What the overlay draws, captured from the page's toggles.
private struct GeometryOverlayOptions {
    var showsLines: Bool
    var showsBaselines: Bool
    var showsLinkRuns: Bool
    var showsTagRuns: Bool
    var range: NSRange?
}

/// Counts the overlay found while drawing, shown in the readouts.
@Observable
private final class GeometryStats {
    var lines = 0
    var linkRuns = 0
    var tagRuns = 0
    var rangeRects = 0

    func update(from measured: GeometryOverlay.Counts) {
        lines = measured.lines
        linkRuns = measured.linkRuns
        tagRuns = measured.tagRuns
        rangeRects = measured.rangeRects
    }
}

private enum GeometryOverlay {
    struct Counts {
        var lines = 0
        var linkRuns = 0
        var tagRuns = 0
        var rangeRects = 0
    }

    static func draw(_ options: GeometryOverlayOptions, over label: OverlayLabelView, in context: CGContext) -> Counts {
        var counts = Counts()
        let lines = label.layoutLines
        counts.lines = lines.count

        if options.showsLines {
            for line in lines {
                OverlayPainter.stroke(label.viewRect(fromLayoutRect: line.rect), color: .systemBlue, in: context, fillAlpha: 0.06)
            }
        }
        if options.showsBaselines {
            for line in lines {
                let segment = label.baselineSegment(of: line)
                OverlayPainter.line(from: segment.start, to: segment.end, color: .systemRed, in: context)
            }
        }

        let linkRuns = label.layoutRuns(matching: .link)
        counts.linkRuns = linkRuns.count
        if options.showsLinkRuns {
            for run in linkRuns {
                OverlayPainter.stroke(label.viewRect(fromLayoutRect: run.rect), color: .systemOrange, in: context, fillAlpha: 0.15)
            }
        }

        let tagRuns = label.layoutRuns(matching: GeometryPage.tagKey)
        counts.tagRuns = tagRuns.count
        if options.showsTagRuns {
            for run in tagRuns {
                OverlayPainter.stroke(label.viewRect(fromLayoutRect: run.rect), color: .systemGreen, in: context, fillAlpha: 0.18)
            }
        }

        if let range = options.range {
            label.textLayout.enumerateTextRects(in: range) { rect in
                counts.rangeRects += 1
                OverlayPainter.stroke(
                    label.viewRect(fromLayoutRect: rect),
                    color: .systemPurple,
                    in: context,
                    fillAlpha: 0.2,
                    dash: [3, 2],
                )
            }
        }
        return counts
    }
}

private struct GeometryLegend: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12, alignment: .leading)], alignment: .leading, spacing: 6) {
            items
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var items: some View {
        swatch("Line box", .blue)
        swatch("Baseline", .red)
        swatch("Link run", .orange)
        swatch("Tagged run", .green)
        swatch("Range rect", .purple)
    }

    private func swatch(_ title: String, _ color: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            RoundedRectangle(cornerRadius: 2)
                .stroke(color, lineWidth: 1.5)
                .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 2))
                .frame(width: 12, height: 12)
        }
    }
}
