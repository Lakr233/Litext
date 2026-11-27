//
//  Created by Litext Team.
//  Copyright (c) 2026 Litext Team. All rights reserved.
//

#if canImport(UIKit) && !os(watchOS)

    import QuartzCore
    import UIKit

    // A view that implements `draw(_:)` gets one backing store the size of its
    // bounds. For a label that holds a long document that is a bitmap of hundreds of
    // megabytes, drawn whole whenever the text changes, although only a screenful of
    // it is ever seen. A label whose host set `tiledDrawing`, once it is taller than
    // the threshold given there, keeps no backing store of its own. It draws into
    // tiles, sublayers a fixed height each, and keeps tiles only around the part of
    // it that is on screen.
    //
    // Nothing else about the label changes: the tiles sit behind the selection, the
    // link highlight and the attachment views, each draws through the label's own
    // `draw(_:)`, and together they show the pixels the single backing store would.
    //
    // What a tiled label has to do that another does not is know where it is on
    // screen, and nothing tells a view that: a scroll changes its scroll view's
    // bounds, a row above it changes height, a window resizes. It looks for itself,
    // a walk up its ancestors that changes nothing when the label has not moved.
    //
    // - When a scroll view above it scrolls. The label observes the bounds of every
    //   scroll view it is in, so it looks in the very call that scrolled and the
    //   tiles are there before the frame is committed, however far the scroll went.
    //   It also asks Core Animation to display a layer it keeps for that, which
    //   Core Animation does in the commit once layout is over, and looks again
    //   there, at where the layout of that frame left it.
    // - In its own layout pass.
    // - As every turn of the main run loop ends, for whatever else moved it: an
    //   ancestor's frame, a view hidden or shown. Those tiles are made after the
    //   turn's changes may have been committed, so they can come a commit late,
    //   which `TiledDrawing.reach` covers unless the label moved further than that
    //   in one step.
    //
    // Nothing here asks for a commit by itself. A layer left asking to be displayed
    // on every turn has UIKit schedule an update for it, which is another turn, and
    // an idle app would wake for every frame of the display.

    /// The layer of a `TextLabelView`: an ordinary layer until the label draws in
    /// tiles, and from then on one with no contents of its own.
    final class TextLabelBackingLayer: CALayer {
        /// Whether the label draws in tiles. Written on the main thread only.
        nonisolated(unsafe) var isTiled = false

        private var tiles: [TextLabelTileLayer] {
            sublayers?.compactMap { $0 as? TextLabelTileLayer } ?? []
        }

        /// A tiled label has nothing to display itself; its tiles do.
        override func display() {
            guard !isTiled else { return }
            super.display()
        }

        // Text that changed is the tiles' to draw again.

        override func setNeedsDisplay() {
            guard isTiled else {
                super.setNeedsDisplay()
                return
            }
            for tile in tiles {
                tile.setNeedsDisplay()
            }
        }

        override func setNeedsDisplay(_ rect: CGRect) {
            guard isTiled else {
                super.setNeedsDisplay(rect)
                return
            }
            guard !rect.isInfinite, !rect.isNull else {
                setNeedsDisplay()
                return
            }
            for tile in tiles {
                let dirty = rect.intersection(tile.frame)
                guard !dirty.isNull, !dirty.isEmpty else { continue }
                tile.setNeedsDisplay(dirty.offsetBy(dx: -tile.frame.minX, dy: -tile.frame.minY))
            }
        }

        /// Renders the whole text for a snapshot. The tiles hold only what is near
        /// the screen, so for as long as the rendering takes the layer is an ordinary
        /// one again, with one backing store, and renders exactly what a label that
        /// is not tiled does.
        override func render(in context: CGContext) {
            guard isTiled else {
                super.render(in: context)
                return
            }
            let tiles = tiles
            let wasHidden = tiles.map(\.isHidden)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for tile in tiles {
                tile.isHidden = true
            }
            isTiled = false
            super.setNeedsDisplay()
            super.render(in: context)
            contents = nil
            isTiled = true
            for (tile, hidden) in zip(tiles, wasHidden) {
                tile.isHidden = hidden
            }
            CATransaction.commit()
        }
    }

    /// One tile of a tiled label: a strip of its text, drawn by the label.
    final class TextLabelTileLayer: CALayer {
        nonisolated(unsafe) weak var label: TextLabelView?

        /// The tile's place in the label, counted from the top.
        nonisolated(unsafe) var index = 0

        override init() {
            super.init()
        }

        override init(layer: Any) {
            super.init(layer: layer)
            if let other = layer as? TextLabelTileLayer {
                label = other.label
                index = other.index
            }
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        /// A tile appears, moves and goes at once, in the transaction that changed the
        /// label.
        override func action(forKey _: String) -> (any CAAction)? {
            nil
        }

        /// A tile the label let go of while it waited to be drawn stays empty.
        override func display() {
            guard superlayer != nil else { return }
            super.display()
        }

        override func draw(in context: CGContext) {
            // Core Animation draws layers on the main thread, the only thread the label
            // is used from; neither value leaves it.
            nonisolated(unsafe) let context = context
            nonisolated(unsafe) let tile = self
            MainActor.assumeIsolated {
                tile.label?.drawTile(tile, in: context)
            }
        }
    }

    /// A layer with nothing to show, kept by a tiled label so that Core Animation
    /// calls the label in a commit: asked to display, it is drawn once that commit's
    /// layout is over, and its drawing is the label's look at where the frame puts it.
    final class TextLabelTileLookLayer: CALayer {
        nonisolated(unsafe) weak var label: TextLabelView?

        override init() {
            super.init()
        }

        override init(layer: Any) {
            super.init(layer: layer)
            label = (layer as? TextLabelTileLookLayer)?.label
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        override func action(forKey _: String) -> (any CAAction)? {
            nil
        }

        override func draw(in _: CGContext) {
            // Core Animation draws layers on the main thread, the only thread the label
            // is used from.
            nonisolated(unsafe) let look = self
            MainActor.assumeIsolated {
                look.label?.displayTiles()
            }
        }
    }

    extension TextLabelView {
        /// The height of a tile, in points.
        static let tileHeight: CGFloat = 512

        // MARK: - Mode

        /// Puts the label into or out of tiled drawing for its current height, and
        /// brings the tiles up to date. Called after every layout pass and window move.
        func updateTiledDrawing() {
            guard let backing = layer as? TextLabelBackingLayer else { return }
            let height = bounds.height
            let shouldTile = tiledDrawing.map { height.isFinite && height > $0.threshold } ?? false
            if shouldTile != backing.isTiled {
                backing.isTiled = shouldTile
                if shouldTile {
                    // The tiles take over; the bitmap of the whole label goes.
                    backing.contents = nil
                } else {
                    removeTiles()
                    backing.setNeedsDisplay()
                }
            }
            guard shouldTile, window != nil else {
                TextLabelTileTracker.shared.remove(self)
                tileScrollObservations.removeAll()
                tileLookLayer?.removeFromSuperlayer()
                tileLookLayer = nil
                if shouldTile {
                    // Out of a window nothing is on screen, and nothing is kept.
                    removeTiles()
                }
                return
            }
            TextLabelTileTracker.shared.add(self)
            observeScrollAncestors()
            if tileLookLayer == nil {
                let look = TextLabelTileLookLayer()
                look.label = self
                // A point of nothing: it only has to be a layer Core Animation displays.
                look.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
                layer.addSublayer(look)
                tileLookLayer = look
            }
            layoutTiles()
            updateTiles()
        }

        /// Whether the label draws in tiles.
        var isDrawingInTiles: Bool {
            (layer as? TextLabelBackingLayer)?.isTiled ?? false
        }

        // MARK: - Tiles

        /// The frame of the tile at `index`, in the label's coordinates. The last tile
        /// ends with the label, and one past the label's end is empty.
        private func tileFrame(at index: Int) -> CGRect {
            let top = CGFloat(index) * Self.tileHeight
            // Never negative: a rect reports a negative height as its size, and a tile
            // that began below the end of a label that got shorter would stay, a
            // strip as tall as the difference laid over the tile above it.
            let height = max(0, min(Self.tileHeight, bounds.height - top))
            return CGRect(x: 0, y: top, width: bounds.width, height: height)
        }

        /// Moves the tiles the label has onto its current bounds. A tile whose strip
        /// changed size is drawn again; one past the end of the label goes.
        private func layoutTiles() {
            for (index, tile) in tileLayers {
                let frame = tileFrame(at: index)
                guard frame.height > 0, frame.width > 0 else {
                    tile.removeFromSuperlayer()
                    tileLayers[index] = nil
                    tileIndices = nil
                    continue
                }
                let scale = displayScale
                if tile.contentsScale != scale {
                    tile.contentsScale = scale
                    tile.setNeedsDisplay()
                }
                if tile.frame != frame {
                    tile.frame = frame
                    tile.setNeedsDisplay()
                }
            }
        }

        /// Makes the tiles around what is on screen and lets go of the ones far from
        /// it.
        ///
        /// - Important: Performance-sensitive. Runs on every scroll step of every
        ///   scroll view the label is in, again in the commit that follows, and as
        ///   every turn of the main run loop ends, for as long as the label is tiled
        ///   in a window. It walks the label's ancestors once, twice while one of
        ///   them animates, and makes or removes a tile only when what is on screen
        ///   crossed a tile's edge.
        func updateTiles() {
            guard isDrawingInTiles else { return }
            let region = tiledRegion()
            var wanted = tileIndices(in: region.settled)
            if let shown = region.shown {
                // An ancestor is animating: the label is still shown where it was, and
                // on its way it shows what lies between there and where it will rest.
                let moving = tileIndices(in: shown)
                if let last = wanted.last, let first = moving.first, first > last, first - last <= Self.tileGapFilled {
                    wanted.insert(integersIn: last ... first)
                } else if let last = moving.last, let first = wanted.first, first > last, first - last <= Self.tileGapFilled {
                    wanted.insert(integersIn: last ... first)
                }
                wanted.formUnion(moving)
            }
            guard !wanted.isEmpty else {
                removeTiles()
                return
            }
            guard wanted != tileIndices else { return }
            tileIndices = wanted

            // A tile just outside stays, so an edge wobbling on a boundary costs nothing.
            for (index, tile) in tileLayers
                where !wanted.contains(index) && !wanted.contains(index - 1) && !wanted.contains(index + 1)
            {
                tile.removeFromSuperlayer()
                tileLayers[index] = nil
            }
            for index in wanted where tileLayers[index] == nil {
                let frame = tileFrame(at: index)
                guard frame.height > 0, frame.width > 0 else { continue }
                let tile = TextLabelTileLayer()
                tile.label = self
                tile.index = index
                tile.isOpaque = false
                tile.contentsScale = displayScale
                // Behind everything else the label layers over its text, and behind a
                // layer a subclass keeps under those at -1.
                tile.zPosition = -2
                tile.frame = frame
                layer.insertSublayer(tile, at: 0)
                tile.setNeedsDisplay()
                tileLayers[index] = tile
            }
        }

        /// The most tiles made between where an animating label is shown and where it
        /// will rest. A label carried further than this passes too fast to read.
        private static let tileGapFilled = 8

        /// The tiles that `rect` touches.
        private func tileIndices(in rect: CGRect) -> IndexSet {
            guard !rect.isNull, rect.height > 0, rect.width > 0 else { return IndexSet() }
            let tileHeight = Self.tileHeight
            let last = max(0, Int((bounds.height / tileHeight).rounded(.up)) - 1)
            let first = min(last, max(0, Int((rect.minY / tileHeight).rounded(.down))))
            let end = min(last, max(first, Int((rect.maxY / tileHeight).rounded(.up)) - 1))
            return IndexSet(integersIn: first ... end)
        }

        private func removeTiles() {
            tileIndices = nil
            guard !tileLayers.isEmpty else { return }
            for tile in tileLayers.values {
                tile.removeFromSuperlayer()
            }
            tileLayers.removeAll()
        }

        /// How far above and below what is on screen tiles are kept; see
        /// `TiledDrawing.reach`.
        private func tileReach(in window: UIWindow) -> CGFloat {
            if let reach = tiledDrawing?.reach, reach.isFinite {
                return max(0, reach)
            }
            return max(Self.tileHeight, window.bounds.height / 2)
        }

        /// The part of the label to keep drawn, in its own coordinates: its bounds cut
        /// down by its window and by every ancestor that clips, each taken as reaching
        /// `tileReach(in:)` further up and down than it does. `.null` when no part of
        /// the label is that near the screen, or the label is in no window.
        ///
        /// `settled` is for where the label will rest. While an ancestor animates,
        /// `shown` is for where it is drawn at the moment, which is where the
        /// animation started when asked in the turn that started it.
        func tiledRegion() -> (settled: CGRect, shown: CGRect?) {
            guard let window else { return (.null, nil) }
            let reach = tileReach(in: window)
            var isAnimating = false
            let settled = tiledRegion(in: window, reach: reach, presented: false, isAnimating: &isAnimating)
            guard isAnimating else { return (settled, nil) }
            return (settled, tiledRegion(in: window, reach: reach, presented: true, isAnimating: &isAnimating))
        }

        private func tiledRegion(
            in window: UIWindow,
            reach: CGFloat,
            presented: Bool,
            isAnimating: inout Bool,
        ) -> CGRect {
            func shown(_ layer: CALayer) -> CALayer {
                presented ? layer.presentation() ?? layer : layer
            }
            let root = window.layer
            var current = layer
            var rect = bounds
            while current !== root {
                guard let parent = current.superlayer, !current.isHidden else { return .null }
                if current.animationKeys()?.isEmpty == false {
                    isAnimating = true
                }
                rect = shown(current).convert(rect, to: shown(parent))
                if parent.masksToBounds || parent === root {
                    rect = rect.intersection(shown(parent).bounds.insetBy(dx: 0, dy: -reach))
                    guard !rect.isNull, !rect.isEmpty else { return .null }
                }
                current = parent
            }
            guard !root.isHidden else { return .null }
            return shown(layer).convert(rect, from: shown(root)).intersection(bounds)
        }

        // MARK: - Following the display

        /// One scroll view above a tiled label, and the observation of its bounds.
        struct ScrollObservation {
            weak var scrollView: UIScrollView?
            let observation: NSKeyValueObservation
        }

        /// Observes the bounds of every scroll view the label is in, which change
        /// with each scroll whoever makes it. Does nothing while they are the ones
        /// already observed.
        func observeScrollAncestors() {
            var scrollViews: [UIScrollView] = []
            var ancestor = superview
            while let view = ancestor {
                if let scrollView = view as? UIScrollView {
                    scrollViews.append(scrollView)
                }
                ancestor = view.superview
            }
            let isCurrent = scrollViews.count == tileScrollObservations.count
                && zip(scrollViews, tileScrollObservations).allSatisfy { $0 === $1.scrollView }
            guard !isCurrent else { return }
            tileScrollObservations = scrollViews.map { scrollView in
                let observation = scrollView.observe(\.bounds) { [weak self] _, _ in
                    // A view's bounds change on the main thread. Should a host change
                    // them elsewhere, the end of the turn finds the label instead.
                    guard Thread.isMainThread else { return }
                    MainActor.assumeIsolated {
                        self?.scrollAncestorDidScroll()
                    }
                }
                return ScrollObservation(scrollView: scrollView, observation: observation)
            }
        }

        /// Looks now, so the tiles are made in the call that scrolled, and asks to
        /// look again in the commit, where the frame's layout has run.
        private func scrollAncestorDidScroll() {
            guard isDrawingInTiles, window != nil else { return }
            updateTiles()
            // Asking makes a commit, so only what moved the label asks.
            tileLookLayer?.setNeedsDisplay()
        }

        /// Brings the tiles up to date with wherever the label now is.
        func trackTiles() {
            guard isDrawingInTiles else { return }
            guard window != nil else {
                TextLabelTileTracker.shared.remove(self)
                return
            }
            updateTiles()
        }

        /// The look a commit makes: brings the tiles up to date and draws the ones
        /// that need it now, since the display pass that would have drawn them is
        /// already under way and may have gone past them.
        func displayTiles() {
            trackTiles()
            for tile in tileLayers.values where tile.needsDisplay() {
                tile.displayIfNeeded()
            }
        }

        // MARK: - Drawing

        /// How far past a tile's edges lines are still drawn into it, in points: ink a
        /// line leaves outside its own box, such as a tall glyph or what a line drawing
        /// action adds, belongs in the tile next to it as well.
        static let tileDrawingMargin: CGFloat = 96

        /// Draws one tile through `draw(_:)`, as the label's own backing store is.
        func drawTile(_ tile: TextLabelTileLayer, in context: CGContext) {
            let frame = tileFrame(at: tile.index)
            guard frame.height > 0 else { return }
            context.saveGState()
            defer { context.restoreGState() }
            if !tile.contentsAreFlipped() {
                context.translateBy(x: 0, y: tile.bounds.height)
                context.scaleBy(x: 1, y: -1)
            }
            context.translateBy(x: -frame.minX, y: -frame.minY)
            // A layer of its own draws outside the view's drawing pass, which is what
            // makes the view's appearance current for dynamic colors.
            let layout = textLayout
            layout.drawingReach = Self.tileDrawingMargin
            traitCollection.performAsCurrent {
                UIGraphicsPushContext(context)
                draw(frame.insetBy(dx: 0, dy: -Self.tileDrawingMargin))
                UIGraphicsPopContext()
            }
            layout.drawingReach = 0
        }
    }

    /// Has every tiled label in a window look at where it is as each turn of the main
    /// run loop ends, for the moves nothing reports; the top of this file lists the
    /// rest. A label that has not moved changes nothing, and the run loop sleeps.
    ///
    /// Only labels that draw in tiles are here, and with none there is no observer.
    @MainActor
    final class TextLabelTileTracker {
        static let shared = TextLabelTileTracker()

        private let labels = NSHashTable<TextLabelView>.weakObjects()
        private var observer: CFRunLoopObserver?

        /// Ahead of Core Animation's own observer, which commits at 2,000,000 as a
        /// turn ends, so that tiles made here are in that commit.
        private static let observerOrder: CFIndex = 1_999_000

        func add(_ label: TextLabelView) {
            guard !labels.contains(label) else { return }
            labels.add(label)
            guard observer == nil else { return }
            let observer = CFRunLoopObserverCreateWithHandler(
                nil,
                CFRunLoopActivity.beforeWaiting.rawValue,
                true,
                Self.observerOrder,
            ) { _, _ in
                MainActor.assumeIsolated {
                    TextLabelTileTracker.shared.trackLabels()
                }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            self.observer = observer
        }

        func remove(_ label: TextLabelView) {
            labels.remove(label)
        }

        func contains(_ label: TextLabelView) -> Bool {
            labels.contains(label)
        }

        private func trackLabels() {
            let tracked = labels.allObjects
            guard !tracked.isEmpty else {
                if let observer {
                    CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
                    self.observer = nil
                }
                return
            }
            for label in tracked {
                // A label can be moved under another scroll view without being told.
                label.observeScrollAncestors()
                label.trackTiles()
            }
        }
    }

#endif
