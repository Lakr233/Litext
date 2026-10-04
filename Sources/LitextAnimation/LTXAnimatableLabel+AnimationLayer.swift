//
//  LTXAnimatableLabel+AnimationLayer.swift
//  LitextAnimation
//
//  Created by Litext Team.
//

import CoreGraphics
import Foundation
import Litext
import QuartzCore

#if canImport(UIKit) && !os(watchOS)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

#if !os(watchOS)

    /// The layer an animatable label draws its animation into.
    ///
    /// UIKit repaints a view's whole backing store for any `setNeedsDisplay(_:)`, however
    /// small the rect, so redrawing the label for each frame would cost as much as drawing all
    /// of its text. While it animates, the label instead splits itself into two areas:
    ///
    /// - The animation region: the strips of the lines touching the animator's
    ///   `animatingRange`, plus its `additionalContentBounds`, widened by its
    ///   `overdrawInsets`. This layer covers exactly that region and draws everything in it,
    ///   routing lines in flight to the animator. It is the only thing redrawn per frame.
    /// - Everything else, which the label's own backing store draws as `TextLabelView` does,
    ///   with the region clipped out, so nothing is drawn twice. It is redrawn only when the
    ///   text changes or the region moves.
    ///
    /// The region may reach outside the label's bounds, which is how an effect draws past
    /// them. The layer sits behind every other sublayer, so the selection, link highlights and
    /// attachment views stay on top, and it is removed as soon as the animation ends.
    ///
    /// Core Animation calls the layer on the main thread, the only thread the label touches
    /// it from; the layer never draws asynchronously.
    final class LTXAnimationLayer: CALayer {
        nonisolated(unsafe) weak var label: LTXAnimatableLabel?

        /// The region the layer covers, in the label's coordinates (top-left origin).
        nonisolated(unsafe) var region: CGRect = .null

        /// The frame last assigned. Reading `frame` back goes through the position and the
        /// anchor point and need not return exactly what was set.
        nonisolated(unsafe) var assignedFrame: CGRect = .null

        override init() {
            super.init()
        }

        override init(layer: Any) {
            super.init(layer: layer)
            if let other = layer as? LTXAnimationLayer {
                label = other.label
                region = other.region
                assignedFrame = other.assignedFrame
            }
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        /// Frame, contents and visibility changes appear at once, in the same transaction as
        /// the label's own redraw, so the two never show the text twice or not at all.
        override func action(forKey _: String) -> (any CAAction)? {
            nil
        }

        override func draw(in context: CGContext) {
            // Neither value leaves the main thread this runs on.
            nonisolated(unsafe) let context = context
            nonisolated(unsafe) let layer = self
            MainActor.assumeIsolated {
                layer.label?.drawAnimation(in: context, layer: layer)
            }
        }

        /// Converts a rect from the label's coordinates to the layer's.
        func layerRect(fromViewRect rect: CGRect) -> CGRect {
            let local = rect.offsetBy(dx: -region.minX, dy: -region.minY)
            guard !contentsAreFlipped() else { return local }
            return CGRect(x: local.minX, y: bounds.height - local.maxY, width: local.width, height: local.height)
        }
    }

    extension LTXAnimatableLabel {
        // MARK: - Region

        /// The animation region for the animator's current state, pixel-aligned, or `.null`.
        ///
        /// - Important: Performance-sensitive. Runs on every frame: two binary searches and
        ///   a few rect operations.
        func currentAnimationRegion() -> CGRect {
            guard isAnimating, let animator else { return .null }
            var region = CGRect.null
            if let range = animator.animatingRange,
               let layout = textLayout as? LTXAnimatableTextLayout,
               let lineIndex = layout.lineIndex
            {
                let lines = lineIndex.lines(touching: range)
                if !lines.isEmpty {
                    region = lineIndex.strip(of: lines, in: layout)
                }
            }
            let additional = animator.additionalContentBounds
            if !additional.isNull, !additional.isEmpty,
               additional.minX.isFinite, additional.minY.isFinite,
               additional.maxX.isFinite, additional.maxY.isFinite
            {
                region = region.union(additional)
            }
            guard !region.isNull, !region.isEmpty else { return .null }
            region = animator.overdrawInsets.sanitized.outset(region)
            // Whole device pixels, so the layer's pixels line up with the label's.
            let scale = backingScale
            let minX = (region.minX * scale).rounded(.down) / scale
            let minY = (region.minY * scale).rounded(.down) / scale
            let maxX = (region.maxX * scale).rounded(.up) / scale
            let maxY = (region.maxY * scale).rounded(.up) / scale
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        /// Moves the animation layer onto the current region. When the region changed, the
        /// layer redraws all of it and the label redraws the area it gave up or took over, in
        /// the same transaction.
        ///
        /// - Returns: Whether the region changed.
        @discardableResult
        func updateAnimationRegion() -> Bool {
            let region = currentAnimationRegion()
            guard region != animationRegion else { return false }
            let previous = animationRegion
            animationRegion = region
            if !region.isNull {
                let layer = animationLayer ?? makeAnimationLayer()
                layer.region = region
                layer.isHidden = false
                layoutAnimationLayer()
                setNeedsAnimationLayerDisplay()
            } else {
                animationLayer?.isHidden = true
            }
            setNeedsLabelDisplay(in: previous.union(region))
            return true
        }

        /// Removes the animation layer and gives its region back to the label.
        func removeAnimationLayer() {
            let previous = animationRegion
            animationRegion = .null
            animationLayer?.removeFromSuperlayer()
            animationLayer = nil
            setNeedsLabelDisplay(in: previous)
        }

        private func makeAnimationLayer() -> LTXAnimationLayer {
            let layer = LTXAnimationLayer()
            layer.label = self
            layer.isOpaque = false
            layer.contentsScale = backingScale
            // Behind the selection, link highlight and attachment layers, which are at zero.
            // A layer's own contents stay behind all of its sublayers.
            layer.zPosition = -1
            #if canImport(UIKit)
                self.layer.insertSublayer(layer, at: 0)
                observeDisplayScale()
            #else
                wantsLayer = true
                self.layer?.insertSublayer(layer, at: 0)
            #endif
            animationLayer = layer
            return layer
        }

        /// Places the animation layer over its region.
        func layoutAnimationLayer() {
            guard let layer = animationLayer, let hostLayer = layer.superlayer, !layer.region.isNull else { return }
            var frame = layer.region
            if !hostLayer.contentsAreFlipped() {
                frame.origin.y = hostLayer.bounds.height - layer.region.maxY
            }
            if layer.assignedFrame != frame {
                layer.assignedFrame = frame
                layer.frame = frame
            }
        }

        // MARK: - Display requests

        /// Redraws all of the animation layer.
        func setNeedsAnimationLayerDisplay() {
            guard let animationLayer, !animationLayer.isHidden else { return }
            animationLayerDisplayRequestCount += 1
            animationLayer.setNeedsDisplay()
        }

        /// Redraws `rect` of the animation layer, in the label's coordinates.
        func setNeedsAnimationLayerDisplay(in rect: CGRect) {
            guard let animationLayer, !animationLayer.isHidden else { return }
            let clipped = rect.intersection(animationLayer.region)
            guard !clipped.isNull, !clipped.isEmpty else { return }
            animationLayerDisplayRequestCount += 1
            animationLayer.setNeedsDisplay(animationLayer.layerRect(fromViewRect: clipped))
        }

        /// Redraws `rect` of the label's own backing store, in its coordinates.
        func setNeedsLabelDisplay(in rect: CGRect) {
            let clipped = rect.intersection(bounds)
            guard !clipped.isNull, !clipped.isEmpty else { return }
            labelDisplayRequestCount += 1
            setNeedsDisplayWithoutAnimationLayer(clipped)
        }

        // MARK: - Drawing

        /// Draws the animation region into the animation layer.
        func drawAnimation(in context: CGContext, layer: LTXAnimationLayer) {
            let size = bounds.size
            let region = layer.region
            guard size.width.isFinite, size.height.isFinite, size.width >= 0, size.height >= 0,
                  textLayout.containerSize == size, !region.isNull,
                  let textLayout = textLayout as? LTXAnimatableTextLayout
            else { return }
            context.saveGState()
            defer { context.restoreGState() }
            if !layer.contentsAreFlipped() {
                context.translateBy(x: 0, y: layer.bounds.height)
                context.scaleBy(x: 1, y: -1)
            }
            context.translateBy(x: -region.minX, y: -region.minY)
            let visibleRect = context.boundingBoxOfClipPath.intersection(region)
            // A layer of its own draws outside the view's drawing pass, which is what makes
            // the view's appearance current, so dynamic colours would resolve against the
            // app's appearance instead: dark text in a dark-mode label.
            #if canImport(UIKit)
                traitCollection.performAsCurrent {
                    UIGraphicsPushContext(context)
                    textLayout.drawAnimation(in: context, visibleRect: visibleRect)
                    UIGraphicsPopContext()
                }
            #else
                effectiveAppearance.performAsCurrentDrawingAppearance {
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
                    textLayout.drawAnimation(in: context, visibleRect: visibleRect)
                    NSGraphicsContext.restoreGraphicsState()
                }
            #endif
        }
    }

#endif
