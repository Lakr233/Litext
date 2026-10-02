//
//  LTXAnimatableLabel+Layout.swift
//  LitextAnimation
//
//  Created by Litext Team.
//

import CoreGraphics
import CoreText
import Foundation
import Litext

#if !os(watchOS)

    /// The layout an animatable label shows its text with.
    ///
    /// It draws exactly like `TextLabel.Layout` with three differences:
    ///
    /// - It draws only the lines the context's clip box reaches, not every line the view's
    ///   dirty rect reaches.
    /// - While the label animates, the label's own drawing leaves out the animation region,
    ///   which the animation layer draws through `drawAnimation(in:visibleRect:)`.
    /// - In the animation layer, a line that touches the animator's `animatingRange` goes to
    ///   the animator, and the animator adds its own content after the lines. Every other
    ///   line is drawn by `CTLineDraw` without a protocol call.
    @MainActor
    final class LTXAnimatableTextLayout: TextLabel.Layout {
        /// The label the layout draws for, which owns the animator.
        weak var label: LTXAnimatableLabel?

        private var cachedLineIndex: LTXLineIndex?

        /// The animator drawing the current pass, with what it animates and the frame time.
        /// Set only while `drawAnimation(in:visibleRect:)` runs.
        private var drawingAnimator: (any LTXTextAnimator)?
        private var drawingRange = NSRange(location: NSNotFound, length: 0)
        private var drawingTime: CFTimeInterval = 0

        /// The laid-out lines keyed by their characters, or `nil` before the first layout
        /// pass. Built on first use after each pass, so a pass costs at most one build.
        var lineIndex: LTXLineIndex? {
            if let cachedLineIndex {
                return cachedLineIndex
            }
            let lines = layoutLines
            guard !lines.isEmpty else { return nil }
            let index = LTXLineIndex(lines: lines)
            cachedLineIndex = index
            return index
        }

        override var containerSize: CGSize {
            didSet {
                if containerSize != oldValue {
                    cachedLineIndex = nil
                }
            }
        }

        override func invalidateLayout() {
            super.invalidateLayout()
            cachedLineIndex = nil
        }

        // MARK: - Drawing

        /// Draws the label's own backing store: everything outside the animation region.
        ///
        /// - Important: Performance-sensitive: this runs on every display pass of the label,
        ///   which an animation causes only when the text changes or the region moves.
        override func draw(in context: CGContext, visibleRect: CGRect?) {
            guard let rect = visibleRect else {
                super.draw(in: context, visibleRect: nil)
                return
            }
            // UIKit hands `draw(_:)` the whole bounds for any dirty rect; the clip box is
            // what reaches the screen, and it is smaller on AppKit.
            let clipBox = context.boundingBoxOfClipPath
            let visible = rect.intersection(clipBox)
            guard !visible.isNull, !visible.isEmpty else { return }

            let region = label?.animationRegion ?? .null
            let excluded = region.intersection(clipBox)
            guard !excluded.isNull, !excluded.isEmpty else {
                super.draw(in: context, visibleRect: visible)
                return
            }
            // The animation layer owns the region; drawing it here as well would show text
            // in flight at full strength under the layer.
            guard !excluded.contains(visible) else { return }
            context.saveGState()
            context.addRect(clipBox)
            context.addRect(excluded)
            context.clip(using: .evenOdd)
            super.draw(in: context, visibleRect: visible)
            context.restoreGState()
        }

        /// Draws the animation region for the animation layer: lines in flight through the
        /// animator, other lines as usual, then the animator's own content.
        ///
        /// - Important: Performance-sensitive: this runs on every animation frame that
        ///   invalidates anything.
        func drawAnimation(in context: CGContext, visibleRect: CGRect) {
            guard !visibleRect.isNull, !visibleRect.isEmpty,
                  let label, let animator = label.drawingAnimator
            else { return }
            let time = label.currentTime
            drawingAnimator = animator
            drawingRange = animator.animatingRange ?? NSRange(location: NSNotFound, length: 0)
            drawingTime = time
            super.draw(in: context, visibleRect: visibleRect)
            drawingAnimator = nil

            // Layout space, as `TextLabel.Layout.draw(in:visibleRect:)` sets it up.
            let flipHeight = viewRect(fromLayoutRect: .zero).minY
            guard flipHeight.isFinite else { return }
            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: 0, y: flipHeight)
            context.scaleBy(x: 1, y: -1)
            animator.drawAdditionalContent(in: context, at: time)
            context.restoreGState()
        }

        /// - Important: Performance-sensitive: this runs for every visible line on every
        ///   display pass.
        override func draw(line: CTLine, at index: Int, in context: CGContext) {
            guard let animator = drawingAnimator, drawingRange.location != NSNotFound else {
                super.draw(line: line, at: index, in: context)
                return
            }
            let cfRange = CTLineGetStringRange(line)
            let lineStart = cfRange.location
            let lineEnd = cfRange.location + cfRange.length
            let isInFlight = drawingRange.location < lineEnd && lineStart < NSMaxRange(drawingRange)
            guard isInFlight else {
                super.draw(line: line, at: index, in: context)
                return
            }

            let rect: CGRect = if let lineIndex, index < lineIndex.count {
                lineIndex.rects[index]
            } else {
                .null
            }
            let animatedLine = LTXAnimatedLine(
                line: line,
                index: index,
                stringRange: NSRange(location: lineStart, length: cfRange.length),
                baselineOrigin: context.textPosition,
                rect: rect,
            )
            let textPosition = context.textPosition
            context.saveGState()
            let didDraw = animator.draw(animatedLine, in: context, at: drawingTime)
            context.restoreGState()
            // The text matrix and position are not part of the graphics state.
            context.textMatrix = .identity
            context.textPosition = textPosition
            if !didDraw {
                super.draw(line: line, at: index, in: context)
            }
        }
    }

#endif
