//
//  Created by Litext Team.
//  Copyright (c) 2026 Litext Team. All rights reserved.
//
//  An animatable label narrows what it draws to the context's clip. A tile's clip is
//  the tile, and a line just outside it can still leave ink in it, so the label has to
//  reach past the clip by as much as a tile draws past its edges.
//

#if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)

    import CoreText
    @testable import Litext
    @testable import LitextAnimation
    import Testing
    import UIKit

    @MainActor
    @Suite("Tiled drawing of an animatable label", .serialized)
    struct LTXTiledDrawingTests {
        /// Draws well past the line's own box, above and below it.
        private final class OverflowingRenderer: TextLabel.LineRenderer {
            override func drawBackground(of line: CTLine, at index: Int, in context: CGContext, layout _: TextLabel.Layout) {
                guard index.isMultiple(of: 2) else { return }
                let origin = context.textPosition
                let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                context.setFillColor(UIColor.systemTeal.withAlphaComponent(0.35).cgColor)
                context.fill(CGRect(x: origin.x, y: origin.y - 40, width: width / 2, height: 90))
            }
        }

        private static let width: CGFloat = 260
        private static var windows: [UIWindow] = []

        private static func string(paragraphs: Int) -> NSAttributedString {
            let result = NSMutableAttributedString()
            for index in 0 ..< paragraphs {
                let font: UIFont = index.isMultiple(of: 3) ? .boldSystemFont(ofSize: 19) : .systemFont(ofSize: 15)
                let words = "Paragraph \(index) of a long reply, with gÿpq descenders and 中文, wrapping onto another line. \n"
                result.append(NSAttributedString(string: words, attributes: [.font: font, .foregroundColor: UIColor.label]))
            }
            return result
        }

        /// A label of `text` in a window as tall as the label, so every tile exists.
        private static func makeLabel(_ text: NSAttributedString, tiled: Bool) -> LTXAnimatableLabel {
            let label = LTXAnimatableLabel(frame: .zero)
            label.clock = { 100 }
            label.reducedMotionOverride = false
            label.animator = LTXFadeInAnimator()
            label.lineRenderer = OverflowingRenderer()
            label.tiledDrawing = tiled ? .init(threshold: 300) : nil
            label.attributedText = text
            let height = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
            label.frame = CGRect(x: 0, y: 0, width: width, height: height)
            let window = UIWindow(frame: label.frame)
            window.isHidden = false
            // Views can outlive a window released at the end of a test.
            windows.append(window)
            window.addSubview(label)
            window.layoutIfNeeded()
            label.layoutIfNeeded()
            return label
        }

        private static func bitmap(size: CGSize, _ draw: (CGContext) -> Void) throws -> Data {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            format.opaque = false
            let image = UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
            return try #require(image.cgImage?.dataProvider?.data as Data?)
        }

        private static func tiles(of label: TextLabelView) -> [TextLabelTileLayer] {
            (label.layer.sublayers ?? []).compactMap { $0 as? TextLabelTileLayer }.sorted { $0.index < $1.index }
        }

        /// What the label's tiles show, put together.
        private static func tiledBitmap(_ label: TextLabelView) throws -> Data {
            try bitmap(size: label.bounds.size) { context in
                for tile in tiles(of: label) {
                    tile.contentsScale = 2
                    tile.setNeedsDisplay()
                    context.saveGState()
                    context.translateBy(x: tile.frame.minX, y: tile.frame.minY)
                    context.clip(to: tile.bounds)
                    tile.render(in: context)
                    context.restoreGState()
                }
            }
        }

        /// What one backing store holds: the label's own drawing, without the layers
        /// it puts over it.
        private static func wholeBitmap(_ label: LTXAnimatableLabel) throws -> Data {
            label.contentScaleFactor = 2
            label.setNeedsDisplay()
            let over = (label.layer.sublayers ?? []).filter { !$0.isHidden }
            for layer in over {
                layer.isHidden = true
            }
            defer {
                for layer in over {
                    layer.isHidden = false
                }
            }
            return try bitmap(size: label.bounds.size) { label.layer.render(in: $0) }
        }

        private static func differingBytes(_ lhs: Data, _ rhs: Data) -> Int {
            guard lhs.count == rhs.count else { return max(lhs.count, rhs.count) }
            return zip(lhs, rhs).count(where: { $0 != $1 })
        }

        @Test
        func `tiles of an animatable label show what its one backing store does`() throws {
            let text = Self.string(paragraphs: 70)
            let whole = Self.makeLabel(text, tiled: false)
            let tiled = Self.makeLabel(text, tiled: true)
            #expect(tiled.isDrawingInTiles)
            #expect(!whole.isDrawingInTiles)
            #expect(tiled.bounds.size == whole.bounds.size)
            #expect(Self.tiles(of: tiled).count > 3)

            let reference = try Self.wholeBitmap(whole)
            #expect(reference.contains { $0 != 0 })
            #expect(try Self.differingBytes(Self.tiledBitmap(tiled), reference) == 0)
        }

        @Test
        func `tiles leave out the text an animation is still bringing in`() throws {
            let text = Self.string(paragraphs: 70)
            let more = Self.string(paragraphs: 78)
            let whole = Self.makeLabel(text, tiled: false)
            let tiled = Self.makeLabel(text, tiled: true)

            // The same streamed change in both: the new paragraphs start to fade in.
            for label in [whole, tiled] {
                label.attributedText = more
                label.frame.size.height = label.sizeThatFits(CGSize(width: Self.width, height: .greatestFiniteMagnitude)).height
                label.window?.frame.size.height = label.frame.height
                label.window?.layoutIfNeeded()
                label.layoutIfNeeded()
            }
            #expect(tiled.isAnimating == whole.isAnimating)
            #expect(tiled.animationRegion == whole.animationRegion)
            #expect(tiled.bounds.size == whole.bounds.size)
            // In flight or not, the label's own drawing is the same either way: tiles
            // skip exactly what one backing store skips.
            #expect(try Self.differingBytes(Self.tiledBitmap(tiled), Self.wholeBitmap(whole)) == 0)
        }
    }

#endif
