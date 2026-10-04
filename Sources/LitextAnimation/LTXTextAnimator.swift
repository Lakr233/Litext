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
import Litext

#if !os(watchOS)

    /// An effect for text an animatable label receives.
    ///
    /// LitextAnimation ships two effects: ``LTXFadeInAnimator`` (and ``LTXFadeUpAnimator``)
    /// for streamed text, and ``LTXNumericTransitionAnimator`` for a counter or title that
    /// changes as a whole. Anything else conforms to this protocol. An animator decides what changed text looks
    /// like while it animates, and the label drives it:
    ///
    /// 1. ``animateChange(_:at:)`` reports each text change the animation policy lets
    ///    through, and the label starts its display link.
    /// 2. ``advance(to:invalidation:)`` runs once per display frame. The animator moves its
    ///    timeline and names what to redraw; the label redraws only that.
    /// 3. While the label draws, every line that touches ``animatingRange`` goes to
    ///    ``draw(_:in:at:)``, and ``drawAdditionalContent(in:at:)`` adds anything that is not
    ///    part of the new text, such as glyphs on their way out. Other lines are drawn by the
    ///    label exactly as `TextLabelView` draws them.
    /// 4. ``finish()`` ends everything at once.
    ///
    /// While animating, the label draws the animation region into a layer of its own: the
    /// strips of the lines that touch ``animatingRange``, across the label's width and halfway
    /// to the neighbouring lines, plus ``additionalContentBounds``, all widened by
    /// ``overdrawInsets``. Only that layer is redrawn per frame, so a frame costs the lines in
    /// flight, however long the text. The rest of the label is redrawn only when the text
    /// changes or the region moves. Anything the animator draws outside the region is not
    /// shown.
    ///
    /// Time always comes from the label: the change's time, then the target timestamp of each
    /// frame, on the clock `CACurrentMediaTime()` reads. An effect is a pure function of that
    /// time and its own timeline, so tests can drive it with synthetic times.
    ///
    /// A minimal animator implements ``animateChange(_:at:)``, ``advance(to:invalidation:)``,
    /// ``animatingRange``, ``draw(_:in:at:)`` and ``finish()``. The label holds its animator
    /// strongly; an animator shared between labels must keep one timeline per label.
    @MainActor
    public protocol LTXTextAnimator: AnyObject {
        /// The label's text changed and its animation policy chose to animate the change.
        ///
        /// `context.change.insertedRange` is the new text, in UTF-16 offsets of the new string
        /// and aligned to grapheme clusters. Text an earlier change was still animating keeps
        /// its offsets inside the common prefix and moves by the length difference inside the
        /// common suffix; the animator maps its own timeline.
        ///
        /// `context.previousLayout` is still laid out, so read the old geometry here, or
        /// keep the layout for later. `context.layout` is typeset on the label's next layout
        /// pass: read its geometry from ``advance(to:invalidation:)`` or while drawing.
        ///
        /// - Parameters:
        ///   - context: The change and everything the policy saw, including
        ///     `prefersReducedMotion`, which the animator honours by toning its effect down.
        ///   - time: When the change happened, on the same clock as frame times.
        func animateChange(_ context: LTXAnimationContext, at time: CFTimeInterval)

        /// Moves the animation to `time` and names what to redraw.
        ///
        /// Called once per display frame while the label is animating. Invalidate only what
        /// looks different from the previous frame: the label redraws that and nothing else,
        /// and a frame that invalidates nothing draws nothing.
        ///
        /// - Important: Performance-sensitive. Runs on the main thread every frame. The
        ///   invalidation context is reused, and invalidating a range costs a binary search.
        ///
        /// - Parameters:
        ///   - time: The target timestamp of the frame being prepared.
        ///   - invalidation: Collects the characters and rects to redraw.
        /// - Returns: Whether anything is still in flight. Returning `false` stops the display
        ///   link until the next animated change; what was invalidated is still redrawn.
        func advance(to time: CFTimeInterval, invalidation: LTXInvalidationContext) -> Bool

        /// The characters in flight, in UTF-16 offsets of the label's text, or `nil` when
        /// none are. Lines that touch it are drawn by ``draw(_:in:at:)``, and their strips
        /// make up the animation region.
        ///
        /// Read once per frame and once per draw pass, so it may be computed, but keep it
        /// cheap. A range that moves to other lines moves the region, which redraws the label
        /// where the region was and where it is now; let it change with the text and as lines
        /// finish, not on every frame.
        var animatingRange: NSRange? { get }

        /// Where ``drawAdditionalContent(in:at:)`` draws, in the label's coordinates (top-left
        /// origin), or `.null`, the default, when it draws nothing. Part of the animation
        /// region, so it may reach outside the label's bounds.
        ///
        /// Read once per frame. Report the whole area the content covers during the
        /// animation rather than its tight bounds on each frame: a change moves the region
        /// and redraws the label around it.
        var additionalContentBounds: CGRect { get }

        /// Draws one line that touches ``animatingRange``.
        ///
        /// The context is flipped to CoreText coordinates of the label's current layout, its
        /// text matrix is the identity and its text position is the line's
        /// `baselineOrigin`, so `line.draw(in: context)` draws the line where and as the
        /// label would, background included; `CTLineDraw(line.line, context)` draws its
        /// glyphs alone. The context is clipped to the area being redrawn, and its graphics state is
        /// restored after the call.
        ///
        /// - Important: Performance-sensitive. Runs during drawing for every line in flight.
        ///   Avoid allocating or measuring text here.
        ///
        /// - Parameters:
        ///   - line: The line, with its index, characters and geometry.
        ///   - context: The context to draw into.
        ///   - time: The time of the frame being drawn.
        /// - Returns: Whether the animator drew the line. Return `false` to have the label draw
        ///   it as at rest, as ``LTXAnimatedLine/draw(in:)`` does.
        func draw(_ line: LTXAnimatedLine, in context: CGContext, at time: CFTimeInterval) -> Bool

        /// Draws content that is not part of the label's text, such as glyphs of the previous
        /// text on their way out.
        ///
        /// Called once per draw of the animation region, after the lines and even when the
        /// text is empty, in the same space as ``draw(_:in:at:)``: CoreText
        /// coordinates of the current layout, origin at its bottom left and y pointing up.
        /// Geometry from `context.previousLayout` uses that layout's own space; when the
        /// container height changed, convert through view space with
        /// `previousLayout.viewRect(fromLayoutRect:)` and `layout.layoutRect(fromViewRect:)`.
        /// Only what falls inside ``additionalContentBounds``, or the strips of the lines in
        /// flight, is shown. Invalidate the rects this draws into from
        /// ``advance(to:invalidation:)``.
        ///
        /// The default draws nothing.
        ///
        /// - Important: Performance-sensitive. Runs on every draw pass while animating.
        func drawAdditionalContent(in context: CGContext, at time: CFTimeInterval)

        /// How far the effect draws outside the strips of its lines, in points. The label
        /// widens the animation region and every invalidated range by this much. Effects that
        /// move, scale or blur glyphs return their reach.
        ///
        /// The region may extend past the label's bounds, where the animation layer still
        /// draws, as long as nothing clips the label: keep `clipsToBounds` `false` on UIKit,
        /// and `layer?.masksToBounds` `false` on AppKit, and leave room for it around the label.
        ///
        /// Defaults to `.zero`. Read once per frame.
        var overdrawInsets: LTXInsets { get }

        /// Ends every animation at once, so the next draw shows the final text.
        ///
        /// The label calls this when it finishes its animations, leaves its window, changes
        /// identity or animator, lets a change through without animating it, or when reduced
        /// motion turns on. The label redraws everything afterwards.
        func finish()
    }

    public extension LTXTextAnimator {
        var additionalContentBounds: CGRect {
            .null
        }

        func drawAdditionalContent(in _: CGContext, at _: CFTimeInterval) {}

        var overdrawInsets: LTXInsets {
            .zero
        }
    }

    /// A laid-out line an animator draws, with the geometry an effect usually needs.
    ///
    /// Geometry is in CoreText layout space: lower-left origin, y pointing up, the space the
    /// drawing context is in.
    public struct LTXAnimatedLine {
        /// The CoreText line.
        public let line: CTLine

        /// The line's position among the laid-out lines, starting at zero.
        public let index: Int

        /// The characters the line shows, in UTF-16 offsets of the label's text, including
        /// any trailing whitespace and line break.
        public let stringRange: NSRange

        /// Where the line's baseline starts: the text position already set on the context.
        public let baselineOrigin: CGPoint

        /// The line's typographic box, from the bottom of its descent to the top of its
        /// ascent, like `TextLabel.LayoutLine.rect`.
        public let rect: CGRect

        /// The layout the line belongs to, whose `lineRenderer` draws it at rest.
        let layout: TextLabel.Layout?

        /// The renderer the label draws the line with at rest, or `nil` when it draws the
        /// glyphs alone. An effect that draws glyph runs one by one can check it, and
        /// draw a line that has one through ``draw(in:)`` instead, so the background
        /// takes part in the effect.
        @MainActor
        public var lineRenderer: TextLabel.LineRenderer? {
            layout?.lineRenderer
        }

        /// - Parameter layout: The layout the line belongs to. Without one,
        ///   ``draw(in:)`` draws the glyphs alone.
        public init(
            line: CTLine,
            index: Int,
            stringRange: NSRange,
            baselineOrigin: CGPoint,
            rect: CGRect,
            layout: TextLabel.Layout? = nil,
        ) {
            self.line = line
            self.index = index
            self.stringRange = stringRange
            self.baselineOrigin = baselineOrigin
            self.rect = rect
            self.layout = layout
        }

        /// Draws the line as the label draws it at rest: its `lineRenderer`'s background,
        /// then its glyphs, at the context's text position. Without a renderer it is
        /// `CTLineDraw`.
        ///
        /// An effect that fades or moves whole lines calls this instead of `CTLineDraw`,
        /// so backgrounds a renderer draws, such as the pill behind inline code, take
        /// part in the effect rather than vanishing from the line while it animates.
        /// The text position is put back afterwards.
        @MainActor
        public func draw(in context: CGContext) {
            guard let layout, let renderer = layout.lineRenderer else {
                CTLineDraw(line, context)
                return
            }
            let textPosition = context.textPosition
            renderer.drawBackground(of: line, at: index, in: context, layout: layout)
            context.textPosition = textPosition
            renderer.drawGlyphs(of: line, at: index, in: context, layout: layout)
            context.textPosition = textPosition
        }

        /// Draws only what the label's `lineRenderer` puts behind the glyphs, at the
        /// context's text position, for an effect that draws the glyphs itself. Draws
        /// nothing without a renderer. The text position is put back afterwards.
        @MainActor
        public func drawBackground(in context: CGContext) {
            guard let layout, let renderer = layout.lineRenderer else { return }
            let textPosition = context.textPosition
            renderer.drawBackground(of: line, at: index, in: context, layout: layout)
            context.textPosition = textPosition
        }
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

    extension LTXInsets {
        /// The insets with every invalid or negative distance replaced by zero.
        var sanitized: LTXInsets {
            func clean(_ value: CGFloat) -> CGFloat {
                value.isFinite && value > 0 ? value : 0
            }
            return LTXInsets(top: clean(top), left: clean(left), bottom: clean(bottom), right: clean(right))
        }

        /// `rect` grown by the insets, in top-left view space.
        func outset(_ rect: CGRect) -> CGRect {
            CGRect(
                x: rect.minX - left,
                y: rect.minY - top,
                width: rect.width + left + right,
                height: rect.height + top + bottom,
            )
        }
    }

#endif
