//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//
//  The fade-in animator and the timing math under it: curves, quantization,
//  stagger and text units, then the animator's batches, its order under a
//  fast stream, and what it draws once a unit is opaque.
//

#if !os(watchOS)

    import CoreGraphics
    import CoreText
    import Foundation
    import Litext
    @testable import LitextAnimation
    import Testing

    // MARK: - Timing

    @Suite("Fade timing")
    struct LTXFadeTimingTests {
        @Test
        func `a Bézier curve runs from zero to one and clamps outside`() {
            for curve in [LTXCubicBezierCurve.easeOut, .easeInOut, .linear] {
                #expect(curve.value(at: -1) == 0)
                #expect(curve.value(at: 0) == 0)
                #expect(curve.value(at: 1) == 1)
                #expect(curve.value(at: 2) == 1)
                var previous = 0.0
                for step in 1 ..< 100 {
                    let value = curve.value(at: Double(step) / 100)
                    #expect(value >= previous - 1e-9)
                    previous = value
                }
            }
        }

        @Test
        func `the linear curve is the identity and ease-out leads it`() {
            for progress in stride(from: 0.05, to: 1, by: 0.05) {
                #expect(abs(LTXCubicBezierCurve.linear.value(at: progress) - progress) < 1e-5)
                #expect(LTXCubicBezierCurve.easeOut.value(at: progress) > progress)
            }
            #expect(abs(LTXCubicBezierCurve.easeInOut.value(at: 0.5) - 0.5) < 1e-5)
        }

        @Test
        func `control points keep the curve a function of time`() {
            let curve = LTXCubicBezierCurve(x1: -1, y1: 0, x2: 2, y2: 1)
            #expect(curve.x1 == 0)
            #expect(curve.x2 == 1)
        }

        @Test
        func `the alpha quantizer rounds to thirty-two steps`() {
            let quantizer = AlphaQuantizer(levels: 32)
            #expect(quantizer.level(for: -0.5) == 0)
            #expect(quantizer.level(for: 0) == 0)
            #expect(quantizer.level(for: 0.01) == 0)
            #expect(quantizer.level(for: 0.02) == 1)
            #expect(quantizer.level(for: 0.5) == 16)
            #expect(quantizer.level(for: 0.99) == 32)
            #expect(quantizer.level(for: 1.5) == 32)
            #expect(quantizer.alpha(forLevel: 16) == 0.5)
            #expect(quantizer.alpha(forLevel: 40) == 1)
            #expect(quantizer.alpha(forLevel: -1) == 0)
        }

        @Test
        func `a stagger caps the delay of a long chunk`() {
            let schedule = LTXStaggerSchedule(interval: 0.02, maxTotalDelay: 0.2)
            #expect(schedule.interval(forUnitCount: 1) == 0)
            #expect(schedule.interval(forUnitCount: 5) == 0.02)
            #expect(abs(schedule.interval(forUnitCount: 101) * 100 - 0.2) < 1e-12)
        }

        @Test
        func `clusters keep emoji sequences and flags whole`() {
            let string = "a👩‍💻🇯🇵é" as NSString
            let starts = TextUnits.starts(
                in: string,
                range: NSRange(location: 0, length: string.length),
                granularity: .cluster,
                maxCount: 48,
            )
            #expect(starts == [0, 1, 6, 10])
        }

        @Test
        func `words start at each word and the range start`() {
            let string = "Hello brave new world" as NSString
            let starts = TextUnits.starts(
                in: string,
                range: NSRange(location: 5, length: string.length - 5),
                granularity: .word,
                maxCount: 48,
            )
            #expect(starts == [5, 6, 12, 16])
        }

        @Test
        func `a long range is thinned to the maximum count`() {
            let string = String(repeating: "x", count: 1000) as NSString
            let starts = TextUnits.starts(
                in: string,
                range: NSRange(location: 0, length: 1000),
                granularity: .cluster,
                maxCount: 48,
            )
            #expect(starts.count == 48)
            #expect(starts.first == 0)
            #expect(starts == starts.sorted())
        }
    }

    // MARK: - Animator

    @MainActor
    @Suite("Fade-in animator")
    struct LTXFadeInAnimatorTests {
        private static let font = PlatformFont.boldSystemFont(ofSize: 24)

        private func text(_ string: String) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [
                .font: Self.font,
                .foregroundColor: CGColor(gray: 0, alpha: 1),
            ])
        }

        private func layout(_ text: NSAttributedString, size: CGSize) -> TextLabel.Layout {
            let layout = TextLabel.Layout(attributedString: text)
            layout.containerSize = size
            return layout
        }

        private func context(
            from old: TextLabel.Layout,
            to new: TextLabel.Layout,
            prefersReducedMotion: Bool = false,
        ) -> LTXAnimationContext {
            LTXAnimationContext(
                change: LTXTextChange(from: old.attributedString, to: new.attributedString),
                previousIdentity: nil,
                identity: nil,
                previousLayout: old,
                layout: new,
                isInWindow: true,
                areAnimationsEnabled: true,
                prefersReducedMotion: prefersReducedMotion,
                wasAnimating: false,
            )
        }

        @Test
        func `fade-in staggers units and finishes each at full opacity`() throws {
            let size = CGSize(width: 400, height: 100)
            let old = layout(text("Hello"), size: size)
            let new = layout(text("Hello world"), size: size)
            let animator = LTXFadeInAnimator()
            animator.animateChange(context(from: old, to: new), at: 10)

            #expect(animator.animatingRange == NSRange(location: 5, length: 6))
            let batch = try #require(animator.batches.first)
            #expect(batch.unitStarts == Array(5 ..< 11))
            // The first unit leads the last one.
            let first = animator.level(ofUnit: 0, in: batch, at: 10.1)
            let last = animator.level(ofUnit: 5, in: batch, at: 10.1)
            #expect(first > last)
            #expect(animator.level(ofUnit: 0, in: batch, at: 10) == 0)
            #expect(animator.level(ofUnit: 5, in: batch, at: 11) == 32)
        }

        @Test
        func `fade-in moves its batches with the text`() throws {
            let size = CGSize(width: 400, height: 100)
            let first = layout(text("Hello"), size: size)
            let second = layout(text("Hello world"), size: size)
            let third = layout(text(">> Hello world"), size: size)
            let animator = LTXFadeInAnimator()
            animator.animateChange(context(from: first, to: second), at: 0)
            animator.animateChange(context(from: second, to: third), at: 0.05)

            let ranges = animator.batches.map(\.range)
            #expect(ranges == [NSRange(location: 0, length: 3), NSRange(location: 8, length: 6)])
            let moved = try #require(animator.batches.last)
            #expect(moved.unitStarts.first == 8)

            animator.finish()
            #expect(animator.animatingRange == nil)
        }

        @Test
        func `rewritten text that was on screen does not fade in again`() {
            let size = CGSize(width: 800, height: 100)
            let old = layout(text("An [inline][ref] and"), size: size)
            let new = layout(text("An inline and more text"), size: size)
            let animator = LTXFadeInAnimator()
            animator.animateChange(context(from: old, to: new), at: 0)

            // Only " more text" is new; "inline and" was already shown.
            #expect(animator.batches.map(\.range) == [NSRange(location: 13, length: 10)])
        }

        @Test
        func `rewritten text in flight keeps fading where it was`() throws {
            let size = CGSize(width: 800, height: 100)
            let first = layout(text("Hello "), size: size)
            let second = layout(text("Hello **wor"), size: size)
            let third = layout(text("Hello world"), size: size)
            let animator = LTXFadeInAnimator()
            animator.animateChange(context(from: first, to: second), at: 0)
            let original = try #require(animator.batches.first)
            animator.animateChange(context(from: second, to: third), at: 0.05)

            #expect(animator.batches.map(\.range) == [
                NSRange(location: 6, length: 3),
                NSRange(location: 9, length: 2),
            ])
            let carried = try #require(animator.batches.first)
            #expect(carried.unitStarts == [6, 7, 8])
            // "w" was the third unit, so it keeps the opacity it had.
            for time in [0.06, 0.1, 0.2] {
                #expect(animator.level(ofUnit: 0, in: carried, at: time) == animator.level(ofUnit: 2, in: original, at: time))
            }
        }

        @Test
        func `a rewrite that shares no text fades in whole`() {
            let size = CGSize(width: 800, height: 100)
            let old = layout(text("Total: 12"), size: size)
            let new = layout(text("Total: 345"), size: size)
            let animator = LTXFadeInAnimator()
            animator.animateChange(context(from: old, to: new), at: 0)
            #expect(animator.batches.map(\.range) == [NSRange(location: 7, length: 3)])
        }

        @Test(arguments: [1.0, 0.1])
        func `a fast stream keeps its chunks in order with a bounded lag`(speed: Double) {
            let size = CGSize(width: 2000, height: 200)
            let animator = LTXFadeInAnimator()
            animator.speed = speed
            var previous = layout(text(""), size: size)
            var string = ""
            let words = ["CTRunDraw", " draws", " each", " stretch", " of", " glyphs", " at", " its", " own", " opacity."]
            var arrivals: [Double] = []
            // Twenty chunks: fewer than the most changes the animator keeps in flight.
            for round in 0 ..< 2 {
                for (index, word) in words.enumerated() {
                    string += word
                    let next = layout(text(string), size: size)
                    let time = Double(round * words.count + index) * 0.033 / speed
                    arrivals.append(time)
                    animator.animateChange(context(from: previous, to: next), at: time)
                    previous = next
                }
            }

            let batches = animator.batches
            #expect(batches.count == arrivals.count)
            let maxLag = animator.configuration.stagger.maxTotalDelay / speed
            for (index, batch) in batches.enumerated() {
                let lastStart = batch.startTime + Double(batch.unitStarts.count - 1) * batch.interval / speed
                // The last unit starts within the lag bound, plus one step.
                #expect(lastStart - arrivals[index] <= maxLag + 0.02 / speed)
                guard index > 0 else { continue }
                let earlier = batches[index - 1]
                let earlierLast = earlier.startTime + Double(earlier.unitStarts.count - 1) * earlier.interval / speed
                #expect(batch.startTime >= earlierLast)
            }
        }

        @Test
        func `reduced motion fades a change as one unit without a rise`() throws {
            let size = CGSize(width: 400, height: 100)
            let old = layout(text("Hello"), size: size)
            let new = layout(text("Hello world"), size: size)
            let animator = LTXFadeUpAnimator()
            animator.animateChange(context(from: old, to: new, prefersReducedMotion: true), at: 0)

            let batch = try #require(animator.batches.first)
            #expect(batch.unitStarts == [5])
            #expect(batch.rise == 0)
            #expect(batch.duration <= 0.2)
        }

        @Test
        func `advancing invalidates until every unit is opaque`() {
            let size = CGSize(width: 400, height: 100)
            let old = layout(text("Hello"), size: size)
            let new = layout(text("Hello world"), size: size)
            let animator = LTXFadeInAnimator()
            animator.animateChange(context(from: old, to: new), at: 0)

            let invalidation = LTXInvalidationContext()
            #expect(animator.advance(to: 0.1, invalidation: invalidation))
            #expect(!animator.advance(to: 5, invalidation: invalidation))
            #expect(animator.batches.isEmpty)
            #expect(animator.animatingRange == nil)
        }

        @Test
        func `fade-up reports its rise as overdraw below the line`() {
            let animator = LTXFadeUpAnimator(rise: 6)
            #expect(animator.overdrawInsets == LTXInsets(top: 0, left: 0, bottom: 6, right: 0))
            #expect(animator.configuration.duration == 0.4)
            #expect(LTXFadeInAnimator().overdrawInsets == .zero)
        }

        @Test
        func `a configuration change applies its opacity steps`() throws {
            let size = CGSize(width: 400, height: 100)
            let old = layout(text("Hello"), size: size)
            let new = layout(text("Hello world"), size: size)
            let animator = LTXFadeInAnimator(configuration: .init(alphaLevels: 4))
            animator.animateChange(context(from: old, to: new), at: 0)
            let batch = try #require(animator.batches.first)
            #expect(animator.level(ofUnit: 0, in: batch, at: 10) == 4)

            animator.configuration.alphaLevels = 8
            #expect(animator.level(ofUnit: 0, in: batch, at: 10) == 8)
        }

        @Test
        func `a subclass observes the frames and the finish`() {
            let size = CGSize(width: 400, height: 100)
            let old = layout(text("Hello"), size: size)
            let new = layout(text("Hello world"), size: size)
            let animator = CountingFadeAnimator()
            animator.animateChange(context(from: old, to: new), at: 0)
            let invalidation = LTXInvalidationContext()
            _ = animator.advance(to: 0.05, invalidation: invalidation)
            _ = animator.advance(to: 0.1, invalidation: invalidation)
            animator.finish()

            #expect(animator.frames == 2)
            #expect(animator.finishes == 1)
            #expect(animator.animatingRange == nil)
        }

        @Test
        func `an opaque line draws what the label draws`() throws {
            let size = CGSize(width: 240, height: 60)
            let old = layout(text("Hello"), size: size)
            let new = layout(text("Hello world"), size: size)
            let animator = LTXFadeInAnimator()
            animator.animateChange(context(from: old, to: new), at: 0)
            let routed = AnimatorLayout(attributedString: new.attributedString)
            routed.containerSize = size
            routed.animator = animator
            routed.time = 30

            let expected = try render(size: size) { context in
                new.draw(in: context)
            }
            let actual = try render(size: size) { context in
                routed.draw(in: context)
            }
            #expect(routed.drawnLines == 1)
            #expect(expected.contains { $0 != 0 })
            #expect(expected == actual)

            // At the start, the new word is not drawn yet.
            routed.time = 0
            let starting = try render(size: size) { context in
                routed.draw(in: context)
            }
            #expect(starting != expected)
        }

        /// Draws into an RGBA bitmap with a top-left origin, like a view, and returns its bytes.
        private func render(size: CGSize, _ body: (CGContext) -> Void) throws -> [UInt8] {
            let width = Int(size.width)
            let height = Int(size.height)
            let context = try #require(CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ))
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            body(context)
            let data = try #require(context.data)
            return Array(UnsafeRawBufferPointer(start: data, count: width * height * 4))
        }
    }

    /// Hands every line to an animator, the way the animatable label hands it the lines in
    /// flight.
    @MainActor
    private final class AnimatorLayout: TextLabel.Layout {
        var animator: LTXFadeInAnimator?
        var time: CFTimeInterval = 0
        private(set) var drawnLines = 0

        override func draw(line: CTLine, at index: Int, in context: CGContext) {
            let range = CTLineGetStringRange(line)
            let animatedLine = LTXAnimatedLine(
                line: line,
                index: index,
                stringRange: NSRange(location: range.location, length: range.length),
                baselineOrigin: context.textPosition,
                rect: .null,
                layout: self,
            )
            if animator?.draw(animatedLine, in: context, at: time) == true {
                drawnLines += 1
            } else {
                super.draw(line: line, at: index, in: context)
            }
        }
    }

    /// Counts the frames and finishes the fade-in animator gets.
    @MainActor
    private final class CountingFadeAnimator: LTXFadeInAnimator {
        private(set) var frames = 0
        private(set) var finishes = 0

        override func advance(to time: CFTimeInterval, invalidation: LTXInvalidationContext) -> Bool {
            frames += 1
            return super.advance(to: time, invalidation: invalidation)
        }

        override func finish() {
            finishes += 1
            super.finish()
        }
    }

#endif
