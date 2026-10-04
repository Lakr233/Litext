//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Litext
import Testing

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Records the order of its calls and the text position each one saw.
@MainActor
private final class RecordingRenderer: TextLabel.LineRenderer {
    enum Step: Equatable {
        case background(Int)
        case glyphs(Int)
    }

    var steps: [Step] = []
    var glyphPositions: [CGPoint] = []
    var drawsGlyphs = true
    /// Moves the text position while drawing the background, as careless code would.
    var movesTextPosition = false

    override func drawBackground(of _: CTLine, at index: Int, in context: CGContext, layout _: TextLabel.Layout) {
        steps.append(.background(index))
        if movesTextPosition {
            context.textPosition = CGPoint(x: -500, y: -500)
        }
    }

    override func drawGlyphs(of line: CTLine, at index: Int, in context: CGContext, layout: TextLabel.Layout) {
        steps.append(.glyphs(index))
        glyphPositions.append(context.textPosition)
        if drawsGlyphs {
            super.drawGlyphs(of: line, at: index, in: context, layout: layout)
        }
    }
}

@MainActor
private final class OwnLayoutLabel: TextLabelView {
    final class OwnLayout: TextLabel.Layout {}

    override func makeTextLayout(_ attributedText: NSAttributedString) -> TextLabel.Layout {
        OwnLayout(attributedString: attributedText)
    }
}

@MainActor
private func laidOutLayout(_ string: String, width: CGFloat = 200) -> TextLabel.Layout {
    let layout = TextLabel.Layout(attributedString: NSAttributedString(
        string: string,
        attributes: [.font: PlatformFont.systemFont(ofSize: 16)],
    ))
    layout.containerSize = CGSize(width: width, height: 1000)
    return layout
}

@MainActor
private func render(_ layout: TextLabel.Layout) -> [UInt8] {
    let width = 200
    let height = 200
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    bytes.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return }
        layout.draw(in: context)
    }
    return bytes
}

@Suite("Line renderer")
@MainActor
struct LitextLineRendererTests {
    @Test
    func `each line is drawn background first, then glyphs, at its baseline origin`() {
        let layout = laidOutLayout("first line\nsecond line")
        let renderer = RecordingRenderer()
        renderer.movesTextPosition = true
        layout.lineRenderer = renderer
        _ = render(layout)
        #expect(renderer.steps == [.background(0), .glyphs(0), .background(1), .glyphs(1)])
        #expect(renderer.glyphPositions == layout.layoutLines.map(\.baselineOrigin))
    }

    @Test
    func `the default renderer draws what no renderer draws`() {
        let layout = laidOutLayout("Hello, world")
        let expected = render(layout)
        #expect(expected.contains { $0 != 0 })
        layout.lineRenderer = TextLabel.LineRenderer()
        #expect(render(layout) == expected)
    }

    @Test
    func `the glyphs go through the renderer`() {
        let layout = laidOutLayout("Hello, world")
        let renderer = RecordingRenderer()
        renderer.drawsGlyphs = false
        layout.lineRenderer = renderer
        #expect(!render(layout).contains { $0 != 0 })
    }

    #if !os(watchOS)
        @Test
        func `a label hands its renderer to the layout it shows and to every later one`() {
            let label = TextLabelView(attributedText: NSAttributedString(string: "One"))
            let renderer = TextLabel.LineRenderer()
            label.lineRenderer = renderer
            #expect(label.textLayout.lineRenderer === renderer)

            label.attributedText = NSAttributedString(string: "Two")
            #expect(label.textLayout.lineRenderer === renderer)

            label.lineRenderer = nil
            #expect(label.textLayout.lineRenderer == nil)
        }

        @Test
        func `a subclass's own layout gets the renderer too`() {
            let label = OwnLayoutLabel(attributedText: NSAttributedString(string: "One"))
            let renderer = TextLabel.LineRenderer()
            label.lineRenderer = renderer
            label.attributedText = NSAttributedString(string: "Two")
            #expect(label.textLayout is OwnLayoutLabel.OwnLayout)
            #expect(label.textLayout.lineRenderer === renderer)
        }
    #endif
}
