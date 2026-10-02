//
//  VerticalMetricsPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Scripts with tall ascenders and deep descenders, and mixed sizes on one
//  line, with each line's box and baseline drawn from `layoutLines`.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct VerticalMetricsPage: View {
    private static let code = """
    // Each line's box comes from the typographic bounds of its runs (ascent,
    // descent, leading), the way UILabel measures; the tallest run sets it.
    for line in label.layoutLines {
        let box = label.viewRect(fromLayoutRect: line.rect)
        let baseline = label.viewRect(
            fromLayoutRect: CGRect(origin: line.baselineOrigin, size: .zero),
        ).minY
        print(line.index, line.stringRange, box, baseline)
    }

    // Ink outside those bounds (deep marks, stacked vowels, emoji bitmaps)
    // can be clipped at the label's top and bottom edges.
    """

    @State private var fontSize = 20.0
    @State private var showsBoxes = true
    @State private var showsBaselines = true
    @State private var metrics = LineMetricsModel()

    var body: some View {
        let text = Self.makeText(fontSize: fontSize)
        CatalogPageScaffold(.verticalMetrics, code: Self.code) {
            VStack(alignment: .leading, spacing: 10) {
                PlatformViewHost<LineBoxLabel>.label {
                    LineBoxLabel()
                } update: { label in
                    let metrics = metrics
                    label.onLinesChange = { summary in
                        if metrics.summary != summary {
                            metrics.summary = summary
                        }
                    }
                    label.showsBoxes = showsBoxes
                    label.showsBaselines = showsBaselines
                    label.attributedText = text
                }
                .accessibilityIdentifier("demo.verticalMetrics.label")
                CatalogNote(
                    "Line sizes come from typographic bounds, the way UILabel computes them. Glyph ink that "
                        + "reaches outside them, such as Tibetan stacks or Arabic marks, can be clipped at the "
                        + "label's top and bottom. This is a known, accepted limitation.",
                    systemImage: "exclamationmark.triangle",
                )
            }
        } controls: {
            Toggle("Line boxes (layoutLines[i].rect)", isOn: $showsBoxes)
            Toggle("Baselines (baselineOrigin)", isOn: $showsBaselines)
            CatalogSlider("Font size", value: $fontSize, in: 12 ... 36, step: 1) { "\(Int($0)) pt" }
            CatalogReadout("Lines", value: "\(metrics.summary.count)", identifier: "state.verticalMetrics.lines")
            CatalogReadout(
                "Tallest line",
                value: metrics.summary.tallest,
                identifier: "state.verticalMetrics.tallest",
            )
            CatalogReadout(
                "Shortest line",
                value: metrics.summary.shortest,
                identifier: "state.verticalMetrics.shortest",
            )
            CatalogReadout(
                "Label height",
                value: "\(Int(metrics.summary.totalHeight.rounded(.up))) pt",
                identifier: "state.verticalMetrics.height",
            )
        }
    }

    private static func makeText(fontSize: CGFloat) -> NSAttributedString {
        let body: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: fontSize),
            .foregroundColor: PlatformColor.label,
        ]
        let lines = [
            "Latin: Ag Éÿ Ŝ ĝ jpqy",
            "Thai: ปฏิ ฎฐ ญู ฤๅ ผู้ใหญ่",
            "Tibetan: བོད་ཡིག་ སྐྱེས་ བསྒྲུབས་",
            "Burmese: မြန်မာဘာသာ ကြွေ",
            "Arabic: بِسْمِ ٱللَّٰهِ ٱلرَّحْمَٰنِ",
            "Vietnamese: Ỗ Ặ Ừ ỹ ặ",
        ]
        let text = NSMutableAttributedString(string: lines.joined(separator: "\n") + "\n", attributes: body)
        let mixed: [(CGFloat, String)] = [(0.6, "small "), (1.7, "BIG "), (1, "body "), (0.8, "x²")]
        for (scale, fragment) in mixed {
            var attributes = body
            attributes[.font] = PlatformFont.systemFont(ofSize: (fontSize * scale).rounded())
            text.append(NSAttributedString(string: fragment, attributes: attributes))
        }
        return text
    }
}

/// The line geometry the label reported, for the readouts.
struct LineMetricsSummary: Equatable {
    var count = 0
    var tallest = "none"
    var shortest = "none"
    var totalHeight: CGFloat = 0
}

@Observable
final class LineMetricsModel {
    var summary = LineMetricsSummary()
}

/// A label that draws each laid-out line's box and baseline over its text.
final class LineBoxLabel: TextLabelView {
    var onLinesChange: ((LineMetricsSummary) -> Void)?
    var showsBoxes = true {
        didSet { updateOverlay() }
    }

    var showsBaselines = true {
        didSet { updateOverlay() }
    }

    private let boxLayer = CAShapeLayer()
    private let baselineLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        boxLayer.fillColor = PlatformColor.systemBlue.withAlphaComponent(0.06).cgColor
        boxLayer.strokeColor = PlatformColor.systemBlue.withAlphaComponent(0.7).cgColor
        boxLayer.lineWidth = 0.5
        baselineLayer.fillColor = nil
        baselineLayer.strokeColor = PlatformColor.systemRed.withAlphaComponent(0.8).cgColor
        baselineLayer.lineWidth = 0.5
        baselineLayer.lineDashPattern = [3, 2]
        #if canImport(UIKit)
            let host = layer
        #else
            wantsLayer = true
            guard let host = layer else { return }
        #endif
        for overlay in [boxLayer, baselineLayer] {
            overlay.zPosition = 10
            host.addSublayer(overlay)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    #if canImport(UIKit)
        override func layoutSubviews() {
            super.layoutSubviews()
            updateOverlay()
        }
    #else
        override func layout() {
            super.layout()
            updateOverlay()
        }
    #endif

    private func updateOverlay() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let lines = layoutLines
        let boxes = CGMutablePath()
        let baselines = CGMutablePath()
        for line in lines {
            let box = viewRect(fromLayoutRect: line.rect)
            boxes.addRect(box)
            let baseline = viewRect(fromLayoutRect: CGRect(origin: line.baselineOrigin, size: .zero)).minY
            baselines.move(to: CGPoint(x: box.minX, y: baseline))
            baselines.addLine(to: CGPoint(x: max(box.maxX, bounds.width), y: baseline))
        }
        boxLayer.path = showsBoxes ? boxes : nil
        baselineLayer.path = showsBaselines ? baselines : nil

        var summary = LineMetricsSummary(count: lines.count)
        if let tallest = lines.max(by: { $0.rect.height < $1.rect.height }),
           let shortest = lines.min(by: { $0.rect.height < $1.rect.height })
        {
            summary.tallest = Self.describe(tallest, in: attributedText)
            summary.shortest = Self.describe(shortest, in: attributedText)
        }
        summary.totalHeight = lines.map { viewRect(fromLayoutRect: $0.rect).maxY }.max() ?? 0
        let onLinesChange = onLinesChange
        // Layout can run inside a SwiftUI update; report one hop later.
        DispatchQueue.main.async { onLinesChange?(summary) }
    }

    private static func describe(_ line: TextLabel.LayoutLine, in text: NSAttributedString) -> String {
        let string = (text.string as NSString).substring(with: line.stringRange)
        let script = string.split(separator: ":").first.map(String.init) ?? string
        let name = script.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(name.prefix(14)) \(String(format: "%.1f", line.rect.height)) pt"
    }
}
