//
//  OffscreenRenderingPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  TextLabel.Layout without a view: measured, laid out and drawn into a
//  bitmap context, restricted to a visible rect, and shown as an image.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct OffscreenRenderingPage: View {
    private static let code = """
    let layout = TextLabel.Layout(attributedString: text)
    let size = layout.sizeThatFits(CGSize(width: 280, height: .greatestFiniteMagnitude))
    layout.containerSize = CGSize(width: 280, height: ceil(size.height))

    let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                            bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // draw(in:) expects a top-left origin, like a view's context.
    context.translateBy(x: 0, y: CGFloat(pixelHeight))
    context.scaleBy(x: scale, y: -scale)

    // Only the lines that intersect the rect are drawn (top-left origin).
    let visible = CGRect(x: 0, y: 0, width: 280, height: 120)
    layout.draw(in: context, visibleRect: visible)
    let drawn = layout.visibleLineCount(in: visible)
    let image = context.makeImage()
    """

    @State private var width = 280.0
    @State private var visibleFraction = 1.0
    @State private var scaleIndex = 1
    @State private var showsCulledArea = true

    private static let scales: [CGFloat] = [1, 2, 3]

    var body: some View {
        let render = OffscreenRender(
            width: width,
            visibleFraction: visibleFraction,
            scale: Self.scales[scaleIndex],
        )
        CatalogPageScaffold(.offscreenRendering, code: Self.code) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal) {
                    if let image = render.image {
                        Image(decorative: image, scale: render.scale)
                            .overlay(alignment: .top) {
                                if showsCulledArea, render.visibleRect.height < render.size.height {
                                    Rectangle()
                                        .fill(Color.red.opacity(0.08))
                                        .overlay(alignment: .top) {
                                            Rectangle().fill(Color.red.opacity(0.6)).frame(height: 1)
                                        }
                                        .frame(height: render.size.height - render.visibleRect.height)
                                        .offset(y: OffscreenRender.margin + render.visibleRect.height)
                                }
                            }
                            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                            .padding(4)
                            .accessibilityIdentifier("demo.offscreen.image")
                    }
                }
                Text("A CGImage drawn by TextLabel.Layout, shown with SwiftUI's Image. No TextLabelView is involved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } controls: {
            CatalogSlider("Width", value: $width, in: 120 ... 520, step: 10) { "\(Int($0)) pt" }
            CatalogSlider("Visible rect height", value: $visibleFraction, in: 0.1 ... 1, step: 0.05) {
                $0.formatted(.percent.precision(.fractionLength(0)))
            }
            CatalogPicker("Scale", selection: $scaleIndex, options: Array(Self.scales.indices)) {
                "\(Int(Self.scales[$0]))×"
            }
            Toggle("Shade the culled area", isOn: $showsCulledArea)
            CatalogReadout("Layout size", value: Self.describe(render.size), identifier: "state.offscreen.size")
            CatalogReadout("Bitmap", value: "\(render.pixelWidth) × \(render.pixelHeight) px", identifier: "state.offscreen.pixels")
            CatalogReadout(
                "Lines drawn",
                value: "\(render.drawnLines) of \(render.totalLines)",
                identifier: "state.offscreen.lines",
            )
            CatalogReadout(
                "Render time",
                value: Self.milliseconds(render.duration),
                identifier: "state.offscreen.time",
            )
        }
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let milliseconds = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        return milliseconds.formatted(.number.precision(.fractionLength(2))) + " ms"
    }

    private static func describe(_ size: CGSize) -> String {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0 ... 1))
        return "\(Double(size.width).formatted(format)) × \(Double(size.height).formatted(format)) pt"
    }
}

/// One offscreen render: measure, lay out, draw into a bitmap, and time it.
@MainActor
private struct OffscreenRender {
    private(set) var image: CGImage?
    let scale: CGFloat
    private(set) var size: CGSize = .zero
    private(set) var visibleRect: CGRect = .zero
    private(set) var pixelWidth = 0
    private(set) var pixelHeight = 0
    private(set) var drawnLines = 0
    private(set) var totalLines = 0
    private(set) var duration: Duration = .zero

    /// Paper around the text, in points.
    static let margin: CGFloat = 12

    init(width: Double, visibleFraction: Double, scale: CGFloat) {
        self.scale = scale
        let clock = ContinuousClock()
        let start = clock.now

        let layout = TextLabel.Layout(attributedString: Self.text)
        let fitting = layout.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        size = CGSize(width: width, height: fitting.height.rounded(.up))
        layout.containerSize = size
        visibleRect = CGRect(x: 0, y: 0, width: size.width, height: (size.height * visibleFraction).rounded(.up))

        pixelWidth = Int(((size.width + Self.margin * 2) * scale).rounded(.up))
        pixelHeight = Int(((size.height + Self.margin * 2) * scale).rounded(.up))
        guard pixelWidth > 0, pixelHeight > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
              )
        else { return }

        // Paper background, then flip to the top-left origin draw(in:) expects.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 0.98, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: Self.margin, y: Self.margin)

        layout.draw(in: context, visibleRect: visibleRect)
        drawnLines = layout.visibleLineCount(in: visibleRect)
        totalLines = layout.visibleLineCount(in: nil)
        image = context.makeImage()
        duration = clock.now - start
    }

    /// Fixed colors: the image is paper-white in light and dark mode alike.
    static let text: NSAttributedString = {
        let ink = PlatformColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)
        let accent = PlatformColor(red: 0.75, green: 0.2, blue: 0.1, alpha: 1)
        let text = NSMutableAttributedString(
            string: "Offscreen\n",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: accent,
            ],
        )
        text.append(NSAttributedString(
            string: "A layout measures and draws on its own, for thumbnails, PDF pages, share images or snapshot tests. Give it a container size, then draw it into any CGContext. Pass a visible rect and only the lines that intersect it are drawn, found by binary search, so a long document costs about what its visible part costs. 小さな画像にも、長い文書にも。",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 15),
                .foregroundColor: ink,
            ],
        ))
        return text
    }()
}
