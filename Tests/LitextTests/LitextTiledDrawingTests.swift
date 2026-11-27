//
//  Created by Litext Team.
//  Copyright (c) 2026 Litext Team. All rights reserved.
//
//  A label whose host set `tiledDrawing` draws in tiles around what is on screen
//  once it is tall enough. The tiles have to show the pixels one backing store
//  would, wherever they are cut, there have to be tiles wherever the label can be
//  seen, and a label whose host did not ask has to be left exactly as it was.
//

#if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)

    import CoreText
    @testable import Litext
    import Testing
    import UIKit

    @MainActor
    @Suite("Tiled drawing", .serialized)
    struct LitextTiledDrawingTests {
        // MARK: - Text

        /// Draws past the line's own box, above and below it, the way a tall glyph or
        /// a decoration can.
        private final class OverflowingRenderer: TextLabel.LineRenderer {
            override func drawBackground(of line: CTLine, at index: Int, in context: CGContext, layout _: TextLabel.Layout) {
                guard index.isMultiple(of: 3) else { return }
                let origin = context.textPosition
                let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                context.setFillColor(UIColor.systemYellow.withAlphaComponent(0.4).cgColor)
                context.fill(CGRect(x: origin.x, y: origin.y - 30, width: width / 2, height: 70))
            }
        }

        private static func text(paragraphs: Int, attachment: TextLabel.Attachment? = nil) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let fonts: [UIFont] = [
                .systemFont(ofSize: 15),
                .boldSystemFont(ofSize: 22),
                .monospacedSystemFont(ofSize: 13, weight: .regular),
                .italicSystemFont(ofSize: 17),
            ]
            let colors: [UIColor] = [.label, .systemBlue, .systemRed, .secondaryLabel]
            for index in 0 ..< paragraphs {
                let style = NSMutableParagraphStyle()
                style.paragraphSpacing = CGFloat(4 + index % 5 * 3)
                style.lineSpacing = CGFloat(index % 3)
                if index % 4 == 1 {
                    style.headIndent = 18
                    style.firstLineHeadIndent = 18
                }
                let words = "Paragraph \(index) 中文混排 with emoji 🎉👩‍👩‍👧 and gÿpq descenders, long enough to wrap onto a second line. "
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: fonts[index % fonts.count],
                    .foregroundColor: colors[index % colors.count],
                    .paragraphStyle: style,
                ]
                if index % 7 == 3 {
                    attributes[.link] = URL(string: "https://example.com/\(index)")!
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                if let attachment, index % 9 == 4 {
                    result.append(attachment.attributedString(attributes: attributes))
                }
                result.append(NSAttributedString(string: words + "\n", attributes: attributes))
            }
            return result
        }

        private struct Generator {
            var state: UInt64

            mutating func next() -> UInt64 {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return state >> 33
            }

            mutating func next(_ bound: Int) -> Int {
                Int(next() % UInt64(bound))
            }
        }

        private static func environmentInt(_ key: String) -> Int? {
            ProcessInfo.processInfo.environment[key].flatMap(Int.init)
        }

        // MARK: - Labels

        private static let width: CGFloat = 240
        private static let tileHeight = TextLabelView.tileHeight

        private static func fittingHeight(_ label: TextLabelView, width: CGFloat = width) -> CGFloat {
            label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        }

        /// A label of `text` at its own height, in a scroll view in a window. With a
        /// `threshold` its host asked for tiles; without one it did not.
        private static func makeLabel(
            _ text: NSAttributedString,
            threshold: CGFloat?,
            reach: CGFloat? = nil,
            viewport: CGSize = CGSize(width: width, height: 600),
        ) -> (label: TextLabelView, scrollView: UIScrollView, window: UIWindow) {
            let window = UIWindow(frame: CGRect(origin: .zero, size: viewport))
            // A hidden window shows nothing, and a label in one keeps no tiles.
            window.isHidden = false
            TestWindows.keepAlive(window)
            let scrollView = UIScrollView(frame: window.bounds)
            window.addSubview(scrollView)
            let label = TextLabelView(frame: .zero)
            label.lineRenderer = OverflowingRenderer()
            label.tiledDrawing = threshold.map { TextLabelView.TiledDrawing(threshold: $0, reach: reach) }
            label.attributedText = text
            label.frame = CGRect(x: 0, y: 0, width: width, height: fittingHeight(label))
            scrollView.contentSize = label.frame.size
            scrollView.addSubview(label)
            window.layoutIfNeeded()
            label.layoutIfNeeded()
            return (label, scrollView, window)
        }

        /// Trait changes wait for the next update; a test has none coming.
        private static func updateTraits(_ window: UIWindow) {
            if #available(iOS 17.0, *) {
                window.updateTraitsIfNeeded()
            }
        }

        /// What a scroll asks for: a look in the next commit.
        private static func setNeedsTileUpdate(_ label: TextLabelView) {
            label.tileLookLayer?.setNeedsDisplay()
        }

        /// A scroll view whose offset Swift callers set without a message send, the
        /// way a final override in a host's own subclass is called.
        private final class DirectScrollView: UIScrollView {
            override var contentOffset: CGPoint {
                get { super.contentOffset }
                set { super.contentOffset = newValue }
            }
        }

        private static func tiles(of label: TextLabelView) -> [TextLabelTileLayer] {
            (label.layer.sublayers ?? []).compactMap { $0 as? TextLabelTileLayer }.sorted { $0.index < $1.index }
        }

        /// The rows of the label its tiles cover, top to bottom. Records an issue when
        /// the tiles are off the grid, repeat, leave a gap or pass the label's end.
        private static func coveredRows(
            of label: TextLabelView,
            sourceLocation: SourceLocation = #_sourceLocation,
        ) -> ClosedRange<CGFloat>? {
            let tiles = tiles(of: label)
            guard let first = tiles.first, let last = tiles.last else { return nil }
            #expect(Set(tiles.map(\.index)).count == tiles.count, "a tile is repeated", sourceLocation: sourceLocation)
            #expect(tiles.count == last.index - first.index + 1, "the tiles leave a gap", sourceLocation: sourceLocation)
            for tile in tiles {
                let top = CGFloat(tile.index) * tileHeight
                // A tile that begins at or below the label's end is not one it should have.
                #expect(top < label.bounds.height, "tile \(tile.index) is past the end", sourceLocation: sourceLocation)
                let expected = CGRect(x: 0, y: top, width: label.bounds.width, height: min(tileHeight, label.bounds.height - top))
                #expect(tile.frame == expected, "tile \(tile.index) is off the grid", sourceLocation: sourceLocation)
                #expect(tile.superlayer === label.layer, sourceLocation: sourceLocation)
            }
            return first.frame.minY ... last.frame.maxY
        }

        /// Checks that the tiles cover the rows of the label within `reach` of the
        /// `viewport` rows of its scroll view, and little more than those.
        private static func expectCoverage(
            of label: TextLabelView,
            offset: CGFloat,
            viewportHeight: CGFloat,
            reach: CGFloat,
            sourceLocation: SourceLocation = #_sourceLocation,
        ) {
            let top = max(0, offset - reach)
            let bottom = min(label.bounds.height, offset + viewportHeight + reach)
            let covered = coveredRows(of: label, sourceLocation: sourceLocation)
            guard bottom > top else {
                #expect(covered == nil, "tiles far from the screen at \(offset)", sourceLocation: sourceLocation)
                return
            }
            guard let covered else {
                Issue.record("no tiles at \(offset)", sourceLocation: sourceLocation)
                return
            }
            #expect(covered.lowerBound <= top, "uncovered above at \(offset)", sourceLocation: sourceLocation)
            #expect(covered.upperBound >= bottom, "uncovered below at \(offset)", sourceLocation: sourceLocation)
            // A tile outside what is wanted may stay; a second one may not.
            #expect(covered.lowerBound > top - 2 * tileHeight, "too many tiles above at \(offset)", sourceLocation: sourceLocation)
            #expect(covered.upperBound < bottom + 2 * tileHeight, "too many tiles below at \(offset)", sourceLocation: sourceLocation)
        }

        // MARK: - Pixels

        private struct Bitmap {
            var data: Data
            var bytesPerRow: Int
            var scale: CGFloat

            /// The bytes of the rows from `top` down to `bottom`, in points.
            func rows(_ top: CGFloat, _ bottom: CGFloat) -> Data {
                let first = Int((top * scale).rounded(.up)) * bytesPerRow
                let end = min(data.count, Int((bottom * scale).rounded(.down)) * bytesPerRow)
                guard end > first else { return Data() }
                return data.subdata(in: first ..< end)
            }
        }

        private static func bitmap(size: CGSize, scale: CGFloat, _ draw: (CGContext) -> Void) throws -> Bitmap {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = false
            let image = UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
            let cgImage = try #require(image.cgImage)
            let data = try #require(cgImage.dataProvider?.data as Data?)
            return Bitmap(data: data, bytesPerRow: cgImage.bytesPerRow, scale: scale)
        }

        /// What the label's tiles show, put together. The tiles draw at `scale`, as
        /// they would on a display of that scale.
        private static func tiledBitmap(_ label: TextLabelView, scale: CGFloat) throws -> Bitmap {
            try bitmap(size: label.bounds.size, scale: scale) { context in
                for tile in tiles(of: label) {
                    tile.contentsScale = scale
                    tile.setNeedsDisplay()
                    context.saveGState()
                    context.translateBy(x: tile.frame.minX, y: tile.frame.minY)
                    context.clip(to: tile.bounds)
                    tile.render(in: context)
                    context.restoreGState()
                }
            }
        }

        /// What the label's layer renders: one backing store's worth for a label that
        /// is not tiled, and the snapshot of one that is.
        private static func renderedBitmap(_ label: TextLabelView, scale: CGFloat) throws -> Bitmap {
            label.contentScaleFactor = scale
            label.setNeedsDisplay()
            return try bitmap(size: label.bounds.size, scale: scale) { label.layer.render(in: $0) }
        }

        private static func differingBytes(_ lhs: Data, _ rhs: Data) -> Int {
            guard lhs.count == rhs.count else { return max(lhs.count, rhs.count) }
            return zip(lhs, rhs).count(where: { $0 != $1 })
        }

        /// Checks that every tile the label has shows the rows of `reference` it lies
        /// over.
        private static func expectTilesMatch(
            _ label: TextLabelView,
            _ reference: Bitmap,
            _ context: String = "",
            sourceLocation: SourceLocation = #_sourceLocation,
        ) throws {
            let composed = try tiledBitmap(label, scale: reference.scale)
            #expect(composed.bytesPerRow == reference.bytesPerRow, sourceLocation: sourceLocation)
            for tile in tiles(of: label) {
                let shown = composed.rows(tile.frame.minY, tile.frame.maxY)
                let expected = reference.rows(tile.frame.minY, tile.frame.maxY)
                #expect(!shown.isEmpty, sourceLocation: sourceLocation)
                let differing = differingBytes(shown, expected)
                #expect(differing == 0, "tile \(tile.index) differs in \(differing) bytes \(context)", sourceLocation: sourceLocation)
            }
        }

        // MARK: - Asked for or not

        @Test
        func `a label draws into one backing store until its host asks for tiles`() {
            let (label, scrollView, _) = Self.makeLabel(Self.text(paragraphs: 400), threshold: nil)
            #expect(label.tiledDrawing == nil)
            #expect(label.bounds.height > 12000)
            #expect(!label.isDrawingInTiles)
            #expect(Self.tiles(of: label).isEmpty)
            #expect(!TextLabelTileTracker.shared.contains(label))
            #expect(label.layer.needsDisplay())

            // Nothing a tiled label does on the way happens to it.
            scrollView.contentOffset = CGPoint(x: 0, y: 8000)
            label.trackTiles()
            Self.setNeedsTileUpdate(label)
            label.setNeedsDisplay(CGRect(x: 0, y: 600, width: 10, height: 10))
            #expect(label.tileScrollObservations.isEmpty)
            #expect(label.tileLookLayer == nil)
            #expect(Self.tiles(of: label).isEmpty)
            #expect((label.layer.sublayers ?? []).allSatisfy { !($0 is TextLabelTileLayer) })
        }

        @Test
        func `asking for tiles and taking that back take effect at once`() throws {
            let text = Self.text(paragraphs: 60)
            let (label, _, _) = Self.makeLabel(text, threshold: nil)
            let reference = try Self.renderedBitmap(label, scale: 2)
            label.layer.displayIfNeeded()
            #expect(label.layer.contents != nil)

            label.tiledDrawing = .init(threshold: 300)
            #expect(label.isDrawingInTiles)
            #expect(label.layer.contents == nil)
            #expect(!Self.tiles(of: label).isEmpty)
            #expect(TextLabelTileTracker.shared.contains(label))
            try Self.expectTilesMatch(label, reference)

            label.tiledDrawing = nil
            #expect(!label.isDrawingInTiles)
            #expect(Self.tiles(of: label).isEmpty)
            #expect(!TextLabelTileTracker.shared.contains(label))
            #expect(label.layer.needsDisplay())
            let restored = try Self.renderedBitmap(label, scale: 2)
            #expect(Self.differingBytes(restored.data, reference.data) == 0)
        }

        @Test
        func `the threshold is the tallest label that keeps one backing store`() {
            let (label, _, _) = Self.makeLabel(Self.text(paragraphs: 30), threshold: nil)
            let height = label.bounds.height
            label.tiledDrawing = .init(threshold: height)
            #expect(!label.isDrawingInTiles)
            label.tiledDrawing = .init(threshold: height - 1)
            #expect(label.isDrawingInTiles)
            label.tiledDrawing = .init(threshold: .greatestFiniteMagnitude)
            #expect(!label.isDrawingInTiles)
            #expect(TextLabelView.TiledDrawing().threshold == 4096)
            #expect(TextLabelView.TiledDrawing().reach == nil)
        }

        @Test
        func `a short label keeps its own backing store`() {
            let label = Self.makeLabel(Self.text(paragraphs: 4), threshold: 4096).label
            #expect(!label.isDrawingInTiles)
            #expect(Self.tiles(of: label).isEmpty)
            #expect(!TextLabelTileTracker.shared.contains(label))
        }

        // MARK: - The same pixels

        @Test(arguments: [1.0, 2.0, 3.0] as [CGFloat])
        func `tiles show the pixels of one backing store`(scale: CGFloat) throws {
            let text = Self.text(paragraphs: 60)
            let whole = Self.makeLabel(text, threshold: nil)
            #expect(!whole.label.isDrawingInTiles)
            let reference = try Self.renderedBitmap(whole.label, scale: scale)
            #expect(reference.data.contains { $0 != 0 })

            // Tall enough a window that every tile is wanted at once.
            let viewport = CGSize(width: Self.width, height: whole.label.bounds.height)
            let tiled = Self.makeLabel(text, threshold: 300, viewport: viewport)
            #expect(tiled.label.isDrawingInTiles)
            #expect(tiled.label.bounds.size == whole.label.bounds.size)
            let expectedTiles = Int((tiled.label.bounds.height / Self.tileHeight).rounded(.up))
            #expect(Self.tiles(of: tiled.label).count == expectedTiles)
            #expect(expectedTiles > 3)

            let composed = try Self.tiledBitmap(tiled.label, scale: scale)
            #expect(Self.differingBytes(composed.data, reference.data) == 0)
        }

        @Test
        func `tiles show the same pixels wherever the label is scrolled to`() throws {
            let text = Self.text(paragraphs: 120)
            let whole = Self.makeLabel(text, threshold: nil)
            let reference = try Self.renderedBitmap(whole.label, scale: 2)
            let (label, scrollView, _) = Self.makeLabel(text, threshold: 300)
            let limit = Int(label.bounds.height - 600)

            var generator = Generator(state: UInt64(Self.environmentInt("LITEXT_FUZZ_SEED") ?? 11))
            for _ in 0 ..< 12 {
                let offset = CGFloat(generator.next(limit))
                scrollView.contentOffset = CGPoint(x: 0, y: offset)
                label.trackTiles()
                Self.expectCoverage(of: label, offset: offset, viewportHeight: 600, reach: Self.tileHeight)
                try Self.expectTilesMatch(label, reference, "at \(offset)")
            }
        }

        @Test
        func `tiles show the pixels of one backing store in dark mode`() throws {
            let text = Self.text(paragraphs: 60)
            let whole = Self.makeLabel(text, threshold: nil)
            let light = try Self.renderedBitmap(whole.label, scale: 2)
            whole.window.overrideUserInterfaceStyle = .dark
            Self.updateTraits(whole.window)
            whole.window.layoutIfNeeded()
            whole.label.layoutIfNeeded()
            let dark = try Self.renderedBitmap(whole.label, scale: 2)
            #expect(Self.differingBytes(dark.data, light.data) > 0)

            let viewport = CGSize(width: Self.width, height: whole.label.bounds.height)
            let tiled = Self.makeLabel(text, threshold: 300, viewport: viewport)
            try Self.expectTilesMatch(tiled.label, light, "in light mode")
            // The tiles were drawn in light mode. The change has to reach every one.
            for tile in Self.tiles(of: tiled.label) {
                tile.displayIfNeeded()
            }
            tiled.window.overrideUserInterfaceStyle = .dark
            Self.updateTraits(tiled.window)
            tiled.window.layoutIfNeeded()
            tiled.label.layoutIfNeeded()
            #expect(Self.tiles(of: tiled.label).allSatisfy { $0.needsDisplay() })
            try Self.expectTilesMatch(tiled.label, dark, "in dark mode")
        }

        @Test
        func `tiles show the new text and the new width after a change`() throws {
            let (label, scrollView, _) = Self.makeLabel(Self.text(paragraphs: 80), threshold: 300)
            scrollView.contentOffset = CGPoint(x: 0, y: 900)
            label.trackTiles()
            for tile in Self.tiles(of: label) {
                tile.displayIfNeeded()
            }

            // New text at the same width.
            let changed = Self.text(paragraphs: 97)
            label.attributedText = changed
            label.frame.size.height = Self.fittingHeight(label)
            label.layoutIfNeeded()
            #expect(Self.tiles(of: label).allSatisfy { $0.needsDisplay() })
            var whole = Self.makeLabel(changed, threshold: nil)
            #expect(whole.label.bounds.size == label.bounds.size)
            try Self.expectTilesMatch(label, Self.renderedBitmap(whole.label, scale: 2), "after a text change")

            // The same text, wider: every line breaks elsewhere.
            let wider: CGFloat = 331
            scrollView.frame.size.width = wider
            label.frame.size = CGSize(width: wider, height: Self.fittingHeight(label, width: wider))
            label.layoutIfNeeded()
            whole = Self.makeLabel(changed, threshold: nil, viewport: CGSize(width: wider, height: 600))
            whole.label.frame.size = label.frame.size
            whole.label.layoutIfNeeded()
            #expect(Self.tiles(of: label).allSatisfy { $0.frame.width == wider })
            _ = Self.coveredRows(of: label)
            try Self.expectTilesMatch(label, Self.renderedBitmap(whole.label, scale: 2), "after a width change")
        }

        @Test
        func `a snapshot of a tiled label renders the whole text`() throws {
            let text = Self.text(paragraphs: 60)
            let whole = Self.makeLabel(text, threshold: nil)
            let reference = try Self.renderedBitmap(whole.label, scale: 2)

            // Only the tiles near the top exist; the snapshot has everything anyway.
            let tiled = Self.makeLabel(text, threshold: 300)
            #expect(tiled.label.isDrawingInTiles)
            #expect(Self.tiles(of: tiled.label).count < Int(tiled.label.bounds.height / Self.tileHeight))
            let before = Self.tiles(of: tiled.label).map(ObjectIdentifier.init)
            for _ in 0 ..< 2 {
                let snapshot = try Self.renderedBitmap(tiled.label, scale: 2)
                #expect(Self.differingBytes(snapshot.data, reference.data) == 0)
                // Rendering put everything back as it was.
                #expect(Self.tiles(of: tiled.label).map(ObjectIdentifier.init) == before)
                #expect(Self.tiles(of: tiled.label).allSatisfy { !$0.isHidden })
                #expect(tiled.label.isDrawingInTiles)
                #expect(tiled.label.layer.contents == nil)
            }
        }

        // MARK: - Which tiles exist

        @Test
        func `tiles cover what is on screen and follow a scroll`() {
            let (label, scrollView, _) = Self.makeLabel(Self.text(paragraphs: 400), threshold: 1024)
            #expect(label.bounds.height > 12000)
            Self.expectCoverage(of: label, offset: 0, viewportHeight: 600, reach: Self.tileHeight)
            #expect(Self.tiles(of: label).count <= 5)
            #expect(TextLabelTileTracker.shared.contains(label))

            scrollView.contentOffset = CGPoint(x: 0, y: 8000)
            label.trackTiles()
            Self.expectCoverage(of: label, offset: 8000, viewportHeight: 600, reach: Self.tileHeight)
            #expect(Self.tiles(of: label).count <= 6)

            // A step shorter than a tile keeps every tile it has.
            let before = Set(Self.tiles(of: label).map(ObjectIdentifier.init))
            scrollView.contentOffset = CGPoint(x: 0, y: 8040)
            label.trackTiles()
            #expect(Set(Self.tiles(of: label).map(ObjectIdentifier.init)).isSuperset(of: before))

            // The end of the label ends the last tile.
            let end = label.bounds.height - 600
            scrollView.contentOffset = CGPoint(x: 0, y: end)
            label.trackTiles()
            Self.expectCoverage(of: label, offset: end, viewportHeight: 600, reach: Self.tileHeight)
            #expect(Self.coveredRows(of: label)?.upperBound == label.bounds.height)
        }

        @Test
        func `tiles reach as far past the screen as the host asked`() {
            let text = Self.text(paragraphs: 400)
            for reach in [0, 200, 1500, 4000] as [CGFloat] {
                let (label, scrollView, _) = Self.makeLabel(text, threshold: 1024, reach: reach)
                for offset in [0, 3000, 7777, label.bounds.height - 600] as [CGFloat] {
                    scrollView.contentOffset = CGPoint(x: 0, y: offset)
                    label.trackTiles()
                    Self.expectCoverage(of: label, offset: offset, viewportHeight: 600, reach: reach)
                }
            }
            // Left to the label, it is half the window and at least a tile.
            let tall = Self.makeLabel(text, threshold: 1024, viewport: CGSize(width: Self.width, height: 1600))
            tall.scrollView.contentOffset = CGPoint(x: 0, y: 5000)
            tall.label.trackTiles()
            Self.expectCoverage(of: tall.label, offset: 5000, viewportHeight: 1600, reach: 800)
        }

        @Test
        func `a label out of sight within reach has its near end drawn`() {
            let (label, scrollView, _) = Self.makeLabel(Self.text(paragraphs: 400), threshold: 1024, reach: 700)
            // Rows before the label, the way a list lays one out ahead of a scroll.
            label.frame.origin.y = 5000
            scrollView.contentSize.height = 5000 + label.bounds.height + 5000

            // Its top is 900 points below the screen: nothing yet.
            scrollView.contentOffset = CGPoint(x: 0, y: 3500)
            label.trackTiles()
            #expect(Self.tiles(of: label).isEmpty)

            // 400 points below: the top is drawn before it is scrolled to.
            scrollView.contentOffset = CGPoint(x: 0, y: 4000)
            label.trackTiles()
            #expect(Self.tiles(of: label).first?.index == 0)
            #expect(Self.tiles(of: label).count <= 2)

            // And the same from below, for its last rows.
            let bottom = 5000 + label.bounds.height
            scrollView.contentOffset = CGPoint(x: 0, y: bottom + 400)
            label.trackTiles()
            #expect(Self.coveredRows(of: label)?.upperBound == label.bounds.height)
            #expect(Self.tiles(of: label).count <= 2)
            scrollView.contentOffset = CGPoint(x: 0, y: bottom + 900)
            label.trackTiles()
            #expect(Self.tiles(of: label).isEmpty)
        }

        @Test
        func `a label out of its window keeps no tiles`() {
            let (label, scrollView, _) = Self.makeLabel(Self.text(paragraphs: 400), threshold: 1024)
            #expect(!Self.tiles(of: label).isEmpty)
            label.removeFromSuperview()
            #expect(label.isDrawingInTiles)
            #expect(Self.tiles(of: label).isEmpty)
            #expect(label.layer.contents == nil)
            #expect(!TextLabelTileTracker.shared.contains(label))

            scrollView.addSubview(label)
            #expect(!Self.tiles(of: label).isEmpty)
            #expect(TextLabelTileTracker.shared.contains(label))
        }

        @Test
        func `a label laid out before it has a window gets its tiles on entering one`() {
            let label = TextLabelView(frame: .zero)
            label.tiledDrawing = .init(threshold: 1024)
            label.attributedText = Self.text(paragraphs: 200)
            label.frame = CGRect(x: 0, y: 0, width: Self.width, height: Self.fittingHeight(label))
            label.layoutIfNeeded()
            #expect(label.isDrawingInTiles)
            #expect(Self.tiles(of: label).isEmpty)
            #expect(!TextLabelTileTracker.shared.contains(label))

            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: Self.width, height: 600))
            window.isHidden = false
            TestWindows.keepAlive(window)
            window.addSubview(label)
            Self.expectCoverage(of: label, offset: 0, viewportHeight: 600, reach: Self.tileHeight)
        }

        @Test
        func `a label scrolled out of sight keeps no tiles`() {
            let (label, scrollView, _) = Self.makeLabel(Self.text(paragraphs: 400), threshold: 1024)
            // Content after the label, so the label can leave the viewport.
            scrollView.contentSize.height = label.bounds.height + 5000
            scrollView.contentOffset = CGPoint(x: 0, y: label.bounds.height + 2000)
            label.trackTiles()
            #expect(Self.tiles(of: label).isEmpty)
            scrollView.contentOffset = CGPoint(x: 0, y: label.bounds.height - 100)
            label.trackTiles()
            #expect(!Self.tiles(of: label).isEmpty)
        }

        @Test
        func `a label to the side of the screen or under a hidden view keeps no tiles`() {
            let (label, scrollView, _) = Self.makeLabel(Self.text(paragraphs: 400), threshold: 1024)
            let holder = UIView(frame: label.frame)
            scrollView.addSubview(holder)
            holder.addSubview(label)
            label.trackTiles()
            #expect(!Self.tiles(of: label).isEmpty)

            holder.frame.origin.x = Self.width + 40
            label.trackTiles()
            #expect(Self.tiles(of: label).isEmpty)
            holder.frame.origin.x = 0
            label.trackTiles()
            #expect(!Self.tiles(of: label).isEmpty)

            holder.isHidden = true
            label.trackTiles()
            #expect(Self.tiles(of: label).isEmpty)
            holder.isHidden = false
            label.trackTiles()
            #expect(!Self.tiles(of: label).isEmpty)
        }

        @Test
        func `a clipping view between the label and its window bounds the tiles`() {
            let (label, scrollView, _) = Self.makeLabel(Self.text(paragraphs: 400), threshold: 1024, reach: 0)
            // A pane 150 points tall, 3000 points into the label.
            let pane = UIView(frame: CGRect(x: 0, y: 200, width: Self.width, height: 150))
            pane.clipsToBounds = true
            scrollView.addSubview(pane)
            pane.addSubview(label)
            label.frame.origin.y = -3000
            label.trackTiles()
            Self.expectCoverage(of: label, offset: 3000, viewportHeight: 150, reach: 0)
            #expect(Self.tiles(of: label).count <= 2)

            // Without the clip the window is what bounds it.
            pane.clipsToBounds = false
            label.trackTiles()
            Self.expectCoverage(of: label, offset: 3000 - 200, viewportHeight: 600, reach: 0)
        }

        @Test
        func `the label finds itself after its ancestors moved it`() {
            let (label, scrollView, window) = Self.makeLabel(Self.text(paragraphs: 400), threshold: 1024)
            let holder = UIView(frame: label.frame)
            scrollView.addSubview(holder)
            holder.addSubview(label)
            label.trackTiles()
            #expect(Self.tiles(of: label).first?.index == 0)

            // Nothing tells the label that its holder moved; it looks before a commit.
            holder.frame.origin.y = -6000
            #expect(Self.tiles(of: label).first?.index == 0)
            label.trackTiles()
            Self.expectCoverage(of: label, offset: 6000, viewportHeight: 600, reach: Self.tileHeight)
            _ = window
        }

        @Test
        func `a label carried by an animation keeps tiles where it is still shown`() {
            let (label, scrollView, _) = Self.makeLabel(Self.text(paragraphs: 400), threshold: 1024)
            let holder = UIView(frame: label.frame)
            scrollView.addSubview(holder)
            holder.addSubview(label)
            label.trackTiles()
            func indices() -> Set<Int> {
                Set(Self.tiles(of: label).map(\.index))
            }
            #expect(indices().contains(0))
            let resting = Int(2000 / Self.tileHeight) + 1
            #expect(!indices().contains(resting))

            UIView.animate(withDuration: 0.3) {
                holder.frame.origin.y = -2000
            }
            // The turn that starts the animation: still shown at the top, about to
            // travel to its new place, and showing everything between on the way.
            label.trackTiles()
            #expect(indices().contains(resting))
            // Where the label is still shown is read from its presentation layers, and
            // a test runner without a window scene never commits any.
            if holder.layer.presentation() != nil {
                #expect(indices().isSuperset(of: Set(0 ... resting)))
            }

            holder.layer.removeAllAnimations()
            label.trackTiles()
            #expect(!indices().contains(0))
            #expect(indices().contains(resting))
        }

        @Test
        func `growing past the threshold starts tiling and shrinking back ends it`() {
            let (label, _, _) = Self.makeLabel(Self.text(paragraphs: 12), threshold: 2000)
            #expect(!label.isDrawingInTiles)

            label.attributedText = Self.text(paragraphs: 200)
            label.frame.size.height = Self.fittingHeight(label)
            label.layoutIfNeeded()
            #expect(label.isDrawingInTiles)
            #expect(!Self.tiles(of: label).isEmpty)
            #expect(label.layer.contents == nil)

            label.attributedText = Self.text(paragraphs: 12)
            label.frame.size.height = Self.fittingHeight(label)
            label.layoutIfNeeded()
            #expect(!label.isDrawingInTiles)
            #expect(Self.tiles(of: label).isEmpty)
            #expect(label.layer.needsDisplay())
        }

        @Test
        func `a streamed label keeps tiles up to its growing end`() throws {
            let (label, scrollView, _) = Self.makeLabel(Self.text(paragraphs: 100), threshold: 1024)
            for paragraphs in stride(from: 104, through: 160, by: 4) {
                label.attributedText = Self.text(paragraphs: paragraphs)
                let height = Self.fittingHeight(label)
                label.frame.size.height = height
                scrollView.contentSize.height = height
                scrollView.contentOffset.y = height - 600
                label.layoutIfNeeded()
                Self.expectCoverage(of: label, offset: height - 600, viewportHeight: 600, reach: Self.tileHeight)
                #expect(Self.coveredRows(of: label)?.upperBound == height)
            }
            let whole = Self.makeLabel(Self.text(paragraphs: 160), threshold: nil)
            try Self.expectTilesMatch(label, Self.renderedBitmap(whole.label, scale: 2), "after streaming")
        }

        @Test
        func `the last tile ends with the label and none is empty`() {
            let text = Self.text(paragraphs: 80)
            let fitting = Self.makeLabel(text, threshold: 300).label.bounds.height
            // One height that ends on a tile's edge, and ones a point to either side.
            let tiles = (fitting / Self.tileHeight).rounded(.down)
            for height in [tiles * Self.tileHeight, tiles * Self.tileHeight + 1, tiles * Self.tileHeight - 1, fitting] {
                let viewport = CGSize(width: Self.width, height: height)
                let (label, scrollView, _) = Self.makeLabel(text, threshold: 300, viewport: viewport)
                label.frame.size.height = height
                scrollView.contentSize.height = height
                label.layoutIfNeeded()
                label.trackTiles()
                #expect(Self.coveredRows(of: label) == 0 ... height)
                #expect(Self.tiles(of: label).count == Int((height / Self.tileHeight).rounded(.up)))
            }
        }

        @Test
        func `the number of tiles follows the screen and not the text`() {
            var counts: [Int] = []
            for paragraphs in [200, 400, 1600] {
                let (label, scrollView, _) = Self.makeLabel(Self.text(paragraphs: paragraphs), threshold: 1024)
                var most = 0
                var generator = Generator(state: 5)
                let limit = Int(label.bounds.height - 600)
                for step in 0 ..< 400 {
                    // Long jumps and short steps.
                    let offset = step.isMultiple(of: 5)
                        ? CGFloat(generator.next(limit))
                        : min(CGFloat(limit), scrollView.contentOffset.y + CGFloat(generator.next(300)))
                    scrollView.contentOffset = CGPoint(x: 0, y: offset)
                    label.trackTiles()
                    most = max(most, Self.tiles(of: label).count)
                }
                counts.append(most)
            }
            // 600 points of screen and a tile of reach each way touch five tiles at
            // most, and one may stay beyond each end.
            #expect(counts.allSatisfy { $0 <= 7 })
            #expect(counts.max() == counts.min())
        }

        // MARK: - Looking

        @Test
        func `a scroll brings the tiles along in the call that scrolls`() {
            let (label, scrollView, _) = Self.makeLabel(Self.text(paragraphs: 400), threshold: 1024)
            #expect(label.tileScrollObservations.count == 1)
            for offset in [9000, 40, 4321, label.bounds.height - 600] as [CGFloat] {
                scrollView.contentOffset = CGPoint(x: 0, y: offset)
                Self.expectCoverage(of: label, offset: offset, viewportHeight: 600, reach: Self.tileHeight)
                // And the commit that follows looks again, after its layout.
                #expect(label.tileLookLayer?.needsDisplay() == true)
                label.tileLookLayer?.displayIfNeeded()
            }
            scrollView.setContentOffset(CGPoint(x: 0, y: 7000), animated: false)
            Self.expectCoverage(of: label, offset: 7000, viewportHeight: 600, reach: Self.tileHeight)
            scrollView.bounds.origin.y = 2500
            Self.expectCoverage(of: label, offset: 2500, viewportHeight: 600, reach: Self.tileHeight)
        }

        @Test
        func `a scroll set without a message send brings the tiles along too`() {
            let (label, scrollView, _) = Self.makeLabel(Self.text(paragraphs: 400), threshold: 1024)
            let direct = DirectScrollView(frame: scrollView.frame)
            direct.contentSize = scrollView.contentSize
            scrollView.superview?.addSubview(direct)
            direct.addSubview(label)
            label.trackTiles()
            // Moved under another scroll view without being told: the end of the turn
            // finds that out.
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            #expect(label.tileScrollObservations.count == 1)
            #expect(label.tileScrollObservations.first?.scrollView === direct)

            direct.contentOffset = CGPoint(x: 0, y: 9000)
            Self.expectCoverage(of: label, offset: 9000, viewportHeight: 600, reach: Self.tileHeight)
        }

        @Test
        func `every scroll view above the label is followed`() {
            let (label, scrollView, _) = Self.makeLabel(Self.text(paragraphs: 400), threshold: 1024)
            // The label in a pane that scrolls inside the outer scroll view.
            let pane = UIScrollView(frame: CGRect(x: 0, y: 0, width: Self.width, height: 600))
            pane.contentSize = label.bounds.size
            scrollView.addSubview(pane)
            pane.addSubview(label)
            scrollView.contentSize = CGSize(width: Self.width, height: 3000)
            label.trackTiles()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            #expect(label.tileScrollObservations.count == 2)

            pane.contentOffset = CGPoint(x: 0, y: 5000)
            Self.expectCoverage(of: label, offset: 5000, viewportHeight: 600, reach: Self.tileHeight)
            // The outer one carries the pane half off the screen.
            scrollView.contentOffset = CGPoint(x: 0, y: 300)
            Self.expectCoverage(of: label, offset: 5300, viewportHeight: 300, reach: Self.tileHeight)

            label.removeFromSuperview()
            #expect(label.tileScrollObservations.isEmpty)
            #expect(label.tileLookLayer == nil)
        }

        @Test
        func `the look a commit makes brings the tiles along and draws them`() {
            let (label, scrollView, _) = Self.makeLabel(Self.text(paragraphs: 400), threshold: 1024)
            let holder = UIView(frame: label.frame)
            scrollView.addSubview(holder)
            holder.addSubview(label)
            label.trackTiles()
            for tile in Self.tiles(of: label) {
                tile.displayIfNeeded()
            }
            // Nothing reports this move.
            holder.frame.origin.y = -9000
            #expect(Self.tiles(of: label).first?.index == 0)

            // What a scroll asks for, and what Core Animation then does in the commit.
            Self.setNeedsTileUpdate(label)
            #expect(label.tileLookLayer?.needsDisplay() == true)
            label.tileLookLayer?.displayIfNeeded()
            #expect(label.tileLookLayer?.needsDisplay() == false)
            Self.expectCoverage(of: label, offset: 9000, viewportHeight: 600, reach: Self.tileHeight)
            // The new tiles are drawn, not left for a display pass that has gone by.
            #expect(Self.tiles(of: label).allSatisfy { !$0.needsDisplay() && $0.contents != nil })
            // The label itself was given nothing to hold.
            #expect(label.layer.contents == nil)
        }

        @Test
        func `a look at a label that has not moved draws nothing`() {
            let (label, _, _) = Self.makeLabel(Self.text(paragraphs: 400), threshold: 1024)
            let tiles = Self.tiles(of: label)
            for tile in tiles {
                tile.displayIfNeeded()
            }
            let contents = tiles.map { $0.contents as AnyObject }
            for _ in 0 ..< 3 {
                // Asking for a look asks the label's own layer, and leaves what the
                // tiles hold alone.
                Self.setNeedsTileUpdate(label)
                #expect(label.tileLookLayer?.needsDisplay() == true)
                #expect(tiles.allSatisfy { !$0.needsDisplay() })
                label.tileLookLayer?.displayIfNeeded()
                #expect(label.tileLookLayer?.needsDisplay() == false)
                label.trackTiles()
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            let after = Self.tiles(of: label)
            #expect(after.map(ObjectIdentifier.init) == tiles.map(ObjectIdentifier.init))
            #expect(after.allSatisfy { !$0.needsDisplay() })
            #expect(zip(after, contents).allSatisfy { $0.contents as AnyObject === $1 })
            // An idle label asks for nothing: asking would make a commit of its own.
            #expect(label.tileLookLayer?.needsDisplay() == false)
        }

        @Test
        func `the main run loop brings the tiles along after a move nothing reports`() {
            let (label, scrollView, _) = Self.makeLabel(Self.text(paragraphs: 400), threshold: 1024)
            let holder = UIView(frame: label.frame)
            scrollView.addSubview(holder)
            holder.addSubview(label)
            label.trackTiles()
            holder.frame.origin.y = -9000
            #expect(Self.tiles(of: label).first?.index == 0)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            Self.expectCoverage(of: label, offset: 9000, viewportHeight: 600, reach: Self.tileHeight)
        }

        @Test
        func `a label that is gone is no longer looked after`() {
            weak var gone: TextLabelView?
            autoreleasepool {
                let (label, _, _) = Self.makeLabel(Self.text(paragraphs: 200), threshold: 1024)
                #expect(TextLabelTileTracker.shared.contains(label))
                gone = label
                label.removeFromSuperview()
                #expect(!TextLabelTileTracker.shared.contains(label))
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            #expect(gone == nil)

            // One let go of while still in its window is not kept alive either.
            autoreleasepool {
                let (label, scrollView, _) = Self.makeLabel(Self.text(paragraphs: 200), threshold: 1024)
                gone = label
                scrollView.removeFromSuperview()
                label.removeFromSuperview()
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            #expect(gone == nil)
        }

        // MARK: - Redrawing

        @Test
        func `a dirty rect redraws only the tiles it touches`() {
            let (label, _, _) = Self.makeLabel(Self.text(paragraphs: 400), threshold: 1024)
            let tiles = Self.tiles(of: label)
            #expect(tiles.count >= 3)
            for tile in tiles {
                tile.displayIfNeeded()
                #expect(!tile.needsDisplay())
            }

            label.setNeedsDisplay(CGRect(x: 0, y: Self.tileHeight + 10, width: 50, height: 20))
            #expect(tiles.map { $0.needsDisplay() } == tiles.map { $0.index == 1 })

            // A rect across an edge reaches the tiles on both sides of it.
            tiles[1].displayIfNeeded()
            label.setNeedsDisplay(CGRect(x: 0, y: Self.tileHeight - 5, width: 50, height: 10))
            #expect(tiles.map { $0.needsDisplay() } == tiles.map { $0.index <= 1 })

            for tile in tiles {
                tile.displayIfNeeded()
            }
            label.setNeedsDisplay()
            #expect(tiles.allSatisfy { $0.needsDisplay() })
            // The label itself never asks for a backing store.
            #expect(label.layer.contents == nil)
        }

        // MARK: - What lies over the text

        @Test
        func `the selection and attachment views stay over the tiles`() throws {
            let attachmentView = UIView()
            let attachment = TextLabel.Attachment(size: CGSize(width: 40, height: 24), view: attachmentView)
            let text = Self.text(paragraphs: 60, attachment: attachment)
            let (label, _, _) = Self.makeLabel(text, threshold: 300)
            #expect(label.isDrawingInTiles)
            #expect(attachmentView.superview === label)

            label.isSelectable = true
            label.selectionRange = NSRange(location: 0, length: 600)
            label.layoutIfNeeded()

            // Core Animation draws sublayers by z position, then in order. Whatever
            // the label lays over its text, the selection among it, is over the tiles.
            let sublayers = label.layer.sublayers ?? []
            func depth(_ layer: CALayer) throws -> (CGFloat, Int) {
                try (layer.zPosition, #require(sublayers.firstIndex { $0 === layer }))
            }
            let tiles = Self.tiles(of: label)
            let others = sublayers.filter { !($0 is TextLabelTileLayer) }
            #expect(!tiles.isEmpty)
            #expect(others.contains { $0 === attachmentView.layer })
            for other in try others.map(depth) {
                for tile in try tiles.map(depth) {
                    let isBehind = tile < other
                    #expect(isBehind)
                }
            }
            // And no part of the text is drawn twice: the label's layer holds nothing.
            #expect(label.layer.contents == nil)
        }

        // MARK: - Anything, in any order

        /// Scrolls, resizes, restreams, hides, moves and switches tiling on and off
        /// at random, and after every step checks which tiles exist; every so often
        /// it checks their pixels too.
        @Test
        func `tiles stay right through any sequence of changes`() throws {
            let seeds = Self.environmentInt("LITEXT_FUZZ_SEED").map { [UInt64($0)] } ?? (1 ... 4).map(UInt64.init)
            let steps = Self.environmentInt("LITEXT_FUZZ_ITERATIONS").map { $0 * 60 } ?? 60
            for seed in seeds {
                var generator = Generator(state: seed &* 2_654_435_761)
                var paragraphs = 40 + generator.next(80)
                var width: CGFloat = Self.width
                var reach: CGFloat?
                let viewportHeight: CGFloat = 600
                let (label, scrollView, window) = Self.makeLabel(Self.text(paragraphs: paragraphs), threshold: 700)

                func settle() {
                    let height = Self.fittingHeight(label, width: width)
                    label.frame.size = CGSize(width: width, height: height)
                    scrollView.frame.size.width = width
                    scrollView.contentSize = CGSize(width: width, height: height + 1500)
                    scrollView.contentOffset.y = min(scrollView.contentOffset.y, height + 900)
                    window.layoutIfNeeded()
                    label.layoutIfNeeded()
                    label.trackTiles()
                }

                for step in 0 ..< steps {
                    switch generator.next(10) {
                    case 0, 1, 2:
                        scrollView.contentOffset.y = CGFloat(generator.next(Int(label.bounds.height) + 900))
                    case 3:
                        scrollView.contentOffset.y = max(0, scrollView.contentOffset.y + CGFloat(generator.next(700)) - 350)
                    case 4:
                        paragraphs = max(4, paragraphs + generator.next(40) - 15)
                        label.attributedText = Self.text(paragraphs: paragraphs)
                    case 5:
                        width = [180, 240, 331, 402.5][generator.next(4)]
                    case 6:
                        reach = [nil, 0, 300, 2000][generator.next(4)]
                        label.tiledDrawing = label.tiledDrawing.map {
                            TextLabelView.TiledDrawing(threshold: $0.threshold, reach: reach)
                        }
                    case 7:
                        label.tiledDrawing = label.tiledDrawing == nil
                            ? TextLabelView.TiledDrawing(threshold: 700, reach: reach)
                            : nil
                    case 8:
                        if label.superview == nil {
                            scrollView.addSubview(label)
                        } else {
                            label.removeFromSuperview()
                        }
                    default:
                        scrollView.isHidden.toggle()
                    }
                    settle()

                    let context = "seed \(seed) step \(step)"
                    let isTiled = label.tiledDrawing != nil && label.bounds.height > 700
                    #expect(label.isDrawingInTiles == isTiled, "\(context)")
                    let isShown = isTiled && label.window != nil && !scrollView.isHidden
                    #expect(TextLabelTileTracker.shared.contains(label) == (isTiled && label.window != nil), "\(context)")
                    guard isShown else {
                        #expect(Self.tiles(of: label).isEmpty, "\(context)")
                        continue
                    }
                    Self.expectCoverage(
                        of: label,
                        offset: scrollView.contentOffset.y,
                        viewportHeight: viewportHeight,
                        reach: reach ?? Self.tileHeight,
                    )
                    #expect(label.layer.contents == nil, "\(context)")
                    if step.isMultiple(of: 10) {
                        let whole = Self.makeLabel(
                            Self.text(paragraphs: paragraphs),
                            threshold: nil,
                            viewport: CGSize(width: width, height: viewportHeight),
                        )
                        whole.label.frame.size = label.frame.size
                        whole.label.layoutIfNeeded()
                        try Self.expectTilesMatch(label, Self.renderedBitmap(whole.label, scale: 2), context)
                    }
                }
            }
        }
    }

#endif
