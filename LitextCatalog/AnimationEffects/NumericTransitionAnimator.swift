//
//  NumericTransitionAnimator.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  A reference LTXTextAnimator for short text that changes as a whole: a
//  counter or a title. Modelled on how FlowDown's title bar rolls from one
//  title to the next; reimplemented here from the described behaviour.
//

import CoreGraphics
import CoreText
import Foundation
import Litext
import LitextAnimation
import QuartzCore

#if !os(watchOS)

    /// Rolls a label from one text to the next, glyph by glyph.
    ///
    /// Glyphs the two texts share slide from where they were to where they are now.
    /// New glyphs roll in from below on a bouncy spring while they fade in and grow from
    /// 40 % to full size; glyphs that are gone roll up, shrink and fade out. Arrivals and
    /// departures are staggered across about 0.2 s. When the label shows a number that
    /// went down, everything rolls the other way, like a countdown.
    ///
    /// ```swift
    /// label.animator = NumericTransitionAnimator()
    /// label.animationPolicy = NumericTransitionAnimator.policy  // animates whole replacements
    /// label.attributedText = NSAttributedString(string: "\(count)", attributes: ...)
    /// ```
    ///
    /// The default policy does not animate a replacement of the whole text, which is
    /// what most changes of a counter or title are, so use ``policy``.
    ///
    /// Every glyph is drawn by the animator while the transition runs, from the label's
    /// text and from the previous text it remembers. All motion is a damped spring in
    /// closed form, so each frame is a pure function of time. When the last spring
    /// settles, the label draws the text itself, and the hand-over is pixel-exact because
    /// the glyphs were drawn from the same runs at the same positions.
    ///
    /// Suited to a line or two of text: a change costs one pass over both texts' glyphs
    /// and a match that is quadratic in the length of the part that changed.
    @MainActor
    final class NumericTransitionAnimator: LTXTextAnimator {
        /// Which way glyphs roll.
        enum Direction {
            /// New glyphs come from below, old ones leave upwards.
            case up
            /// New glyphs come from above, old ones leave downwards.
            case down
            /// `down` when both texts show a number and it went down, `up` otherwise.
            case automatic
        }

        /// The springs and distances of the transition.
        struct Timing {
            /// Moves arriving glyphs into place.
            var arrival = DampedSpring.bouncy
            /// Moves departing glyphs away.
            var departure = DampedSpring(response: 0.36, dampingRatio: 1)
            /// Moves glyphs that stay to their new place.
            var slide = DampedSpring(response: 0.42, dampingRatio: 0.82)
            /// Fades glyphs in and out.
            var fade = DampedSpring.smooth
            /// Scales arriving and departing glyphs.
            var scale = DampedSpring(response: 0.3, dampingRatio: 0.82)
            /// The stagger across all arriving, or all departing, glyphs, in seconds.
            var totalStagger = 0.2
            /// How far a glyph rolls, as a fraction of its height.
            var travel: CGFloat = 1.0 / 3.0
            /// The size an arriving glyph starts at and a departing one ends at.
            var minimumScale: CGFloat = 0.4
        }

        /// The policy that animates every change a reader can see, whole replacements
        /// included.
        static let policy = LTXClosureAnimationPolicy { context in
            context.isInWindow && context.areAnimationsEnabled && !context.isIdentityChange
        }

        var direction: Direction = .automatic
        var timing = Timing()

        /// Plays the transition slower (below 1) or faster (above 1), for inspecting it.
        var speed: Double = 1

        init() {}

        // MARK: - Model

        /// A glyph as one layout placed it, converted to the current layout's space.
        struct Glyph {
            let run: CTRun
            let index: CFIndex
            let key: GlyphKey
            /// The line origin to set as text position before drawing the run.
            var textPosition: CGPoint
            /// The glyph's typographic box.
            var box: CGRect
        }

        /// What makes two glyphs the same for matching: the glyph in the same font.
        struct GlyphKey: Equatable {
            let glyph: CGGlyph
            let font: CTFont

            static func == (lhs: GlyphKey, rhs: GlyphKey) -> Bool {
                lhs.glyph == rhs.glyph && (lhs.font === rhs.font || CFEqual(lhs.font, rhs.font))
            }
        }

        /// How a glyph looks at one moment, relative to its place.
        struct Pose {
            var offset: CGVector
            var alpha: CGFloat
            var scale: CGFloat

            static let rest = Pose(offset: .zero, alpha: 1, scale: 1)
        }

        /// One glyph's transition from one pose to another.
        struct Sprite {
            var glyph: Glyph
            let isLeaving: Bool
            /// The time of the change, and this glyph's stagger after it.
            let changeTime: CFTimeInterval
            let delay: Double
            let from: Pose
            let to: Pose
            let motion: DampedSpring
            /// How long after its delay the sprite has settled.
            let duration: Double
        }

        /// A change whose new layout has not been laid out yet.
        private struct Pending {
            let time: CFTimeInterval
            let previousLayout: TextLabel.Layout
            /// The previous layout's flip height: view y = flip − layout y.
            let previousFlip: CGFloat
            /// The glyphs on screen and how they looked when the change came, or `nil`
            /// for the previous layout's glyphs at rest.
            let carried: [(glyph: Glyph, pose: Pose)]?
            /// Departing glyphs of earlier changes, still in flight.
            let leaving: [Sprite]
            let rollsUp: Bool
            let reducedMotion: Bool
        }

        private var layout: TextLabel.Layout?
        private var textLength = 0
        private var pending: Pending?
        private(set) var sprites: [Sprite] = []
        private var contentBounds: CGRect = .null

        // MARK: - LTXTextAnimator

        func animateChange(_ context: LTXAnimationContext, at time: CFTimeInterval) {
            let rollsUp = switch direction {
            case .up: true
            case .down: false
            case .automatic: !Self.countsDown(
                    from: context.previousLayout.attributedString.string,
                    to: context.layout.attributedString.string,
                )
            }
            let next: Pending
            if let pending {
                // Two changes before a frame: the screen still shows what the first one
                // started from.
                next = Pending(
                    time: time,
                    previousLayout: pending.previousLayout,
                    previousFlip: pending.previousFlip,
                    carried: pending.carried,
                    leaving: pending.leaving,
                    rollsUp: rollsUp,
                    reducedMotion: context.prefersReducedMotion,
                )
            } else {
                let isRunning = !sprites.isEmpty
                next = Pending(
                    time: time,
                    previousLayout: context.previousLayout,
                    previousFlip: Self.flipHeight(of: context.previousLayout),
                    carried: isRunning
                        ? sprites.filter { !$0.isLeaving }.map { ($0.glyph, pose(of: $0, at: time)) }
                        : nil,
                    leaving: sprites.filter(\.isLeaving),
                    rollsUp: rollsUp,
                    reducedMotion: context.prefersReducedMotion,
                )
            }
            pending = next
            layout = context.layout
            textLength = context.change.length
            sprites = []
            contentBounds = Self.provisionalBounds(of: next.previousLayout)
        }

        func advance(to time: CFTimeInterval, invalidation: LTXInvalidationContext) -> Bool {
            resolvePendingIfReady()
            invalidation.invalidateAll()
            guard pending == nil else { return true }
            sprites.removeAll { sprite in
                sprite.isLeaving && elapsed(of: sprite, at: time) > 0 && pose(of: sprite, at: time).alpha < 0.01
            }
            return sprites.contains { elapsed(of: $0, at: time) < $0.duration }
        }

        var animatingRange: NSRange? {
            guard pending != nil || !sprites.isEmpty, textLength > 0 else { return nil }
            return NSRange(location: 0, length: textLength)
        }

        var additionalContentBounds: CGRect {
            contentBounds
        }

        func draw(_: LTXAnimatedLine, in _: CGContext, at _: CFTimeInterval) -> Bool {
            resolvePendingIfReady()
            // Every glyph of the text is a sprite, drawn by drawAdditionalContent.
            return pending == nil
        }

        func drawAdditionalContent(in context: CGContext, at time: CFTimeInterval) {
            resolvePendingIfReady()
            guard pending == nil else { return }
            for sprite in sprites {
                let pose = pose(of: sprite, at: time)
                guard pose.alpha > 0.004, pose.scale > 0.01 else { continue }
                let box = sprite.glyph.box
                context.saveGState()
                context.setAlpha(pose.alpha)
                context.translateBy(x: box.midX + pose.offset.dx, y: box.midY + pose.offset.dy)
                context.scaleBy(x: pose.scale, y: pose.scale)
                context.translateBy(x: -box.midX, y: -box.midY)
                context.textPosition = sprite.glyph.textPosition
                CTRunDraw(sprite.glyph.run, context, CFRange(location: sprite.glyph.index, length: 1))
                context.restoreGState()
            }
        }

        func finish() {
            pending = nil
            sprites = []
            layout = nil
            contentBounds = .null
        }

        // MARK: - Poses

        private func elapsed(of sprite: Sprite, at time: CFTimeInterval) -> Double {
            (time - sprite.changeTime) * speed - sprite.delay
        }

        /// The pose of `sprite` at `time`: each channel springs from `from` to `to`.
        func pose(of sprite: Sprite, at time: CFTimeInterval) -> Pose {
            let elapsed = elapsed(of: sprite, at: time)
            guard elapsed > 0 else { return sprite.from }
            guard elapsed < sprite.duration else { return sprite.to }
            let motion = CGFloat(sprite.motion.progress(at: elapsed))
            let fade = CGFloat(timing.fade.progress(at: elapsed))
            let scale = CGFloat(timing.scale.progress(at: elapsed))
            return Pose(
                offset: CGVector(
                    dx: sprite.from.offset.dx + (sprite.to.offset.dx - sprite.from.offset.dx) * motion,
                    dy: sprite.from.offset.dy + (sprite.to.offset.dy - sprite.from.offset.dy) * motion,
                ),
                alpha: min(max(sprite.from.alpha + (sprite.to.alpha - sprite.from.alpha) * fade, 0), 1),
                scale: max(sprite.from.scale + (sprite.to.scale - sprite.from.scale) * scale, 0),
            )
        }

        // MARK: - Building the transition

        /// Pairs the glyphs once the new layout has been laid out, which the label does
        /// before the first frame and the first draw.
        private func resolvePendingIfReady() {
            guard let pending, let layout else { return }
            let lines = layout.layoutLines
            guard textLength == 0 || !lines.isEmpty else { return }
            self.pending = nil

            let shift = Self.flipHeight(of: layout) - pending.previousFlip
            let old: [(glyph: Glyph, pose: Pose)] = if let carried = pending.carried {
                carried.map { (Self.shifted($0.glyph, by: shift), $0.pose) }
            } else {
                Self.glyphs(in: pending.previousLayout.layoutLines, shift: shift)
                    .map { ($0, Pose.rest) }
            }
            let new = Self.glyphs(in: lines, shift: 0)
            let matches = GlyphMatcher.match(old: old.map(\.glyph.key), new: new.map(\.key))

            var matchedOld = [Bool](repeating: false, count: old.count)
            for case let oldIndex? in matches {
                matchedOld[oldIndex] = true
            }
            let leavingIndices = old.indices
                .filter { !matchedOld[$0] }
                .sorted { old[$0].glyph.box.minX < old[$1].glyph.box.minX }
            let arrivingCount = matches.count(where: { $0 == nil })

            let reduced = pending.reducedMotion
            let step = reduced ? 0 : timing.totalStagger / Double(max(arrivingCount, leavingIndices.count, 1))
            // Layout space has y pointing up: rolling up means arriving from below.
            let below: CGFloat = pending.rollsUp ? -1 : 1
            let minimumScale = reduced ? 1 : timing.minimumScale
            let travelFraction = reduced ? 0 : timing.travel

            var result: [Sprite] = []
            result.reserveCapacity(new.count + leavingIndices.count + pending.leaving.count)
            var arrivalRank = 0
            for (index, glyph) in new.enumerated() {
                if let oldIndex = matches[index] {
                    let previous = old[oldIndex]
                    let offset = reduced ? CGVector.zero : CGVector(
                        dx: previous.glyph.box.minX + previous.pose.offset.dx - glyph.box.minX,
                        dy: previous.glyph.box.minY + previous.pose.offset.dy - glyph.box.minY,
                    )
                    let from = Pose(offset: offset, alpha: previous.pose.alpha, scale: previous.pose.scale)
                    result.append(makeSprite(glyph, leaving: false, time: pending.time, delay: 0, from: from, to: .rest, motion: timing.slide))
                } else {
                    let travel = glyph.box.height * travelFraction
                    let from = Pose(offset: CGVector(dx: 0, dy: below * travel), alpha: 0, scale: minimumScale)
                    let delay = Double(arrivalRank) * step
                    arrivalRank += 1
                    result.append(makeSprite(glyph, leaving: false, time: pending.time, delay: delay, from: from, to: .rest, motion: timing.arrival))
                }
            }
            for (rank, oldIndex) in leavingIndices.enumerated() {
                let previous = old[oldIndex]
                let travel = previous.glyph.box.height * travelFraction
                let to = Pose(
                    offset: CGVector(dx: previous.pose.offset.dx, dy: -below * travel),
                    alpha: 0,
                    scale: minimumScale,
                )
                result.append(makeSprite(
                    previous.glyph,
                    leaving: true,
                    time: pending.time,
                    delay: Double(rank) * step,
                    from: previous.pose,
                    to: to,
                    motion: timing.departure,
                ))
            }
            for var sprite in pending.leaving {
                sprite.glyph = Self.shifted(sprite.glyph, by: shift)
                result.append(sprite)
            }
            sprites = result
            contentBounds = bounds(of: result, in: layout)
        }

        private func makeSprite(
            _ glyph: Glyph,
            leaving: Bool,
            time: CFTimeInterval,
            delay: Double,
            from: Pose,
            to: Pose,
            motion: DampedSpring,
        ) -> Sprite {
            let duration = max(
                motion.settlingDuration(tolerance: 0.002),
                timing.fade.settlingDuration(tolerance: 0.002),
                timing.scale.settlingDuration(tolerance: 0.002),
            )
            return Sprite(
                glyph: glyph,
                isLeaving: leaving,
                changeTime: time,
                delay: delay,
                from: from,
                to: to,
                motion: motion,
                duration: duration,
            )
        }

        /// Everywhere the sprites can reach, in view space, with room for the bounce.
        private func bounds(of sprites: [Sprite], in layout: TextLabel.Layout) -> CGRect {
            var union = CGRect.null
            for sprite in sprites {
                var box = sprite.glyph.box
                for pose in [sprite.from, sprite.to] {
                    union = union.union(box.offsetBy(dx: pose.offset.dx, dy: pose.offset.dy))
                }
                box = box.insetBy(dx: -2, dy: -box.height * timing.travel * 0.5)
                union = union.union(box)
            }
            guard !union.isNull else { return .null }
            return layout.viewRect(fromLayoutRect: union).insetBy(dx: -4, dy: -4)
        }

        // MARK: - Glyphs

        /// The glyphs of `lines`, in reading order, moved by `shift` along y.
        ///
        /// Reads the layout's own typeset lines, so a glyph drawn from here lands on the
        /// pixels the label draws it on. Runs once per change, never per frame.
        static func glyphs(in lines: [TextLabel.LayoutLine], shift: CGFloat) -> [Glyph] {
            var result: [Glyph] = []
            for line in lines {
                let origin = CGPoint(x: line.baselineOrigin.x, y: line.baselineOrigin.y + shift)
                for run in CTLineGetGlyphRuns(line.line) as! [CTRun] {
                    let count = CTRunGetGlyphCount(run)
                    guard count > 0 else { continue }
                    let attributes = CTRunGetAttributes(run) as NSDictionary
                    guard let fontValue = attributes[kCTFontAttributeName as String] else { continue }
                    let font = fontValue as! CTFont
                    let ascent = CTFontGetAscent(font)
                    let descent = CTFontGetDescent(font)
                    var glyphs = [CGGlyph](repeating: 0, count: count)
                    var positions = [CGPoint](repeating: .zero, count: count)
                    var advances = [CGSize](repeating: .zero, count: count)
                    let all = CFRange(location: 0, length: count)
                    CTRunGetGlyphs(run, all, &glyphs)
                    CTRunGetPositions(run, all, &positions)
                    CTRunGetAdvances(run, all, &advances)
                    for index in 0 ..< count {
                        result.append(Glyph(
                            run: run,
                            index: index,
                            key: GlyphKey(glyph: glyphs[index], font: font),
                            textPosition: origin,
                            box: CGRect(
                                x: origin.x + positions[index].x,
                                y: origin.y + positions[index].y - descent,
                                width: advances[index].width,
                                height: ascent + descent,
                            ),
                        ))
                    }
                }
            }
            return result
        }

        private static func shifted(_ glyph: Glyph, by shift: CGFloat) -> Glyph {
            guard shift != 0 else { return glyph }
            var glyph = glyph
            glyph.textPosition.y += shift
            glyph.box.origin.y += shift
            return glyph
        }

        /// The height layout space is flipped against: view y = flip − layout y.
        private static func flipHeight(of layout: TextLabel.Layout) -> CGFloat {
            let flip = layout.viewRect(fromLayoutRect: .zero).minY
            return flip.isFinite ? flip : 0
        }

        /// Where the previous text was, widened by a line, in view space: the area to
        /// redraw until the new layout is ready.
        private static func provisionalBounds(of layout: TextLabel.Layout) -> CGRect {
            var union = CGRect.null
            for line in layout.layoutLines {
                union = union.union(layout.viewRect(fromLayoutRect: line.rect))
            }
            guard !union.isNull else { return .null }
            return union.insetBy(dx: -4, dy: -union.height / 2)
        }

        /// Whether the text shows a number that went down.
        nonisolated static func countsDown(from previous: String, to current: String) -> Bool {
            guard let old = GlyphMatcher.numericValue(of: previous),
                  let new = GlyphMatcher.numericValue(of: current)
            else { return false }
            return new < old
        }
    }

#endif
