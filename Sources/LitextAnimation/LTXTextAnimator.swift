//
//  LTXTextAnimator.swift
//  LitextAnimation
//
//  Created by Litext Team.
//

import CoreFoundation
import CoreGraphics
import CoreText
import Foundation

#if !os(watchOS)

    /// An appearance effect for text an animatable label receives.
    ///
    /// LitextAnimation ships no effects of its own. An animator decides what new text looks
    /// like while it appears, and the label drives it: it reports each text change the
    /// animation policy lets through, asks for one step per display frame, redraws the lines
    /// the step names and hands the animator every line that intersects text in flight.
    ///
    /// Time always comes from the label, as the target timestamp of the frame being drawn,
    /// so an effect is a pure function of that time and its own timeline. Tests can drive an
    /// animator with synthetic times.
    ///
    /// The label holds its animator strongly.
    @MainActor
    public protocol LTXTextAnimator: AnyObject {
        /// The label's text changed and its animation policy chose to animate the change.
        ///
        /// `change.insertedRange` is the new text, in UTF-16 offsets of the new string and
        /// aligned to grapheme clusters. Text an earlier change was still animating keeps its
        /// offsets inside the common prefix and moves by the length difference inside the
        /// common suffix; the animator maps its own timeline.
        ///
        /// - Parameters:
        ///   - change: The difference between the previous and the new string.
        ///   - context: Everything the policy saw, including `prefersReducedMotion`, which the
        ///     animator honours by toning its effect down.
        ///   - time: The time the change happened, on the same clock as frame times.
        func textDidChange(_ change: LTXTextChange, context: LTXAnimationContext, at time: CFTimeInterval)

        /// Moves the animation to `time` and reports what to redraw.
        ///
        /// Called once per display frame while the animation is active.
        ///
        /// - Important: Performance-sensitive. Runs on the main thread every frame. Report
        ///   only the ranges whose look changed since the last step; the label redraws the
        ///   lines they touch and nothing else.
        func advance(to time: CFTimeInterval) -> LTXAnimationStep

        /// Draws one line that intersects text in flight.
        ///
        /// The context is already flipped to CoreText coordinates and its text position is
        /// set to the line's origin, so `CTLineDraw(line, context)` draws the line where the
        /// label would. Return `false` to have the label draw the line with `CTLineDraw`
        /// itself.
        ///
        /// - Important: Performance-sensitive. Runs during drawing for every line in flight.
        ///
        /// - Parameters:
        ///   - line: The CoreText line.
        ///   - stringRange: The line's characters, in UTF-16 offsets of the label's text.
        ///   - context: The context to draw into.
        ///   - time: The time of the frame being drawn.
        /// - Returns: Whether the animator drew the line.
        func draw(line: CTLine, stringRange: NSRange, in context: CGContext, at time: CFTimeInterval) -> Bool

        /// How far the effect draws outside a line's box, in points, so the label widens the
        /// area it redraws. Effects that move or blur glyphs return their reach. Defaults to
        /// `.zero`.
        var overdrawInsets: LTXInsets { get }

        /// Ends every animation at once, so the next draw shows the final text.
        ///
        /// The label calls this when it finishes its animations, leaves its window, changes
        /// identity, or lets a change through without animating it.
        func finish()
    }

    public extension LTXTextAnimator {
        var overdrawInsets: LTXInsets {
            .zero
        }
    }

    /// The result of advancing an animator to a frame's time.
    public struct LTXAnimationStep: Sendable, Hashable {
        /// The character ranges whose look changed and must be redrawn. The label turns them
        /// into line boxes, widened by the animator's `overdrawInsets`.
        public var dirtyRanges: [NSRange]

        /// Whether any text is still in flight. When `false`, the label stops its display
        /// link until the next animated change.
        public var isActive: Bool

        public init(dirtyRanges: [NSRange], isActive: Bool) {
            self.dirtyRanges = dirtyRanges
            self.isActive = isActive
        }

        /// A step that redraws nothing and ends the animation.
        public static let finished = LTXAnimationStep(dirtyRanges: [], isActive: false)
    }

    /// Distances an effect draws outside a line's box, in points of the label's coordinate
    /// space, where `top` points toward the first line.
    public struct LTXInsets: Sendable, Hashable {
        public var top: CGFloat
        public var left: CGFloat
        public var bottom: CGFloat
        public var right: CGFloat

        public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
            self.top = top
            self.left = left
            self.bottom = bottom
            self.right = right
        }

        /// The same distance on every side.
        public init(all value: CGFloat) {
            self.init(top: value, left: value, bottom: value, right: value)
        }

        /// No overdraw.
        public static let zero = LTXInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

#endif
