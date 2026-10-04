//
//  TextLabel+LineRenderer.swift
//  Litext
//
//  Created by Litext Team.
//

import CoreGraphics
import CoreText
import Foundation

extension TextLabel {
    /// Draws each laid-out line in two steps: what goes behind its glyphs, then the glyphs.
    ///
    /// A renderer changes how lines look without subclassing `TextLabel.Layout`, so it
    /// combines with any label that makes a layout of its own. `TextLabelView` hands its
    /// `lineRenderer` to every layout it builds, after `makeTextLayout(_:)` returns, so a
    /// subclass's layout gets it too. `LitextAnimation` also hands it to animators, which
    /// draw a line in flight the way the label draws it at rest with
    /// `LTXAnimatedLine.draw(in:)`.
    ///
    /// Without a renderer, a layout draws each line with `CTLineDraw` and nothing else.
    ///
    /// ```swift
    /// final class UnderlayRenderer: TextLabel.LineRenderer {
    ///     override func drawBackground(of line: CTLine, at index: Int, in context: CGContext, layout: TextLabel.Layout) {
    ///         // Fill behind the line; the text position is its baseline origin.
    ///     }
    /// }
    ///
    /// label.lineRenderer = UnderlayRenderer()
    /// ```
    ///
    /// Both steps receive the context in CoreText's space: lower-left origin, identity text
    /// matrix, and the text position at where the line's baseline starts. An animator may
    /// have moved that position or set an alpha or a clip, so draw relative to it. The
    /// layout puts the text position back after `drawBackground(of:at:in:layout:)`.
    ///
    /// A renderer may serve several layouts and several labels, so anything it caches
    /// should be kept per layout.
    ///
    /// - Important: Performance-sensitive: both steps run for every visible line on every
    ///   display pass, and for every line in flight on every animation frame. Avoid
    ///   allocating or measuring text here.
    @MainActor
    open class LineRenderer {
        public init() {}

        /// Draws what goes behind the glyphs of `line`: a background, a highlight, a pill.
        /// The default draws nothing.
        open func drawBackground(
            of _: CTLine,
            at _: Int,
            in _: CGContext,
            layout _: TextLabel.Layout,
        ) {}

        /// Draws the glyphs of `line` at the context's text position. The default calls
        /// `CTLineDraw`.
        open func drawGlyphs(
            of line: CTLine,
            at _: Int,
            in context: CGContext,
            layout _: TextLabel.Layout,
        ) {
            CTLineDraw(line, context)
        }
    }
}
