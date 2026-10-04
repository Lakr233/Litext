//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//
//  The numeric transition and what it rests on: the damped spring, glyph
//  matching, and the hand-over from its sprites to the label's own drawing.
//

#if !os(watchOS)

    import CoreGraphics
    import CoreText
    import Foundation
    import Litext
    @testable import LitextAnimation
    import Testing

    // MARK: - Springs

    @Suite("Damped spring")
    struct LTXDampedSpringTests {
        @Test
        func `a spring starts at full displacement and settles within its tolerance`() {
            for spring in [LTXDampedSpring.bouncy, .smooth, LTXDampedSpring(response: 0.3, dampingRatio: 1.6)] {
                #expect(spring.displacement(at: 0) == 1)
                #expect(spring.displacement(at: -1) == 1)
                let settle = spring.settlingDuration(tolerance: 0.001)
                #expect(settle > 0 && settle < 5)
                for step in 0 ... 50 {
                    let time = settle + Double(step) * 0.02
                    #expect(abs(spring.displacement(at: time)) <= 0.001 + 1e-9)
                }
            }
        }

        @Test
        func `the bouncy spring overshoots and the smooth one does not`() {
            let times = stride(from: 0.0, through: 2, by: 0.005)
            let bouncyMinimum = times.map { LTXDampedSpring.bouncy.displacement(at: $0) }.min() ?? 0
            let smoothMinimum = times.map { LTXDampedSpring.smooth.displacement(at: $0) }.min() ?? 0
            #expect(bouncyMinimum < -0.1)
            #expect(smoothMinimum >= 0)
            // A response of 0.4 s and a damping ratio of 0.54 crosses the target first
            // after about 0.15 s.
            #expect(LTXDampedSpring.bouncy.displacement(at: 0.12) > 0)
            #expect(LTXDampedSpring.bouncy.displacement(at: 0.2) < 0)
        }
    }

    // MARK: - Glyph matching

    @Suite("Glyph matching")
    struct GlyphMatcherTests {
        private func match(_ old: String, _ new: String) -> [Int?] {
            GlyphMatcher.match(old: Array(old), new: Array(new))
        }

        @Test
        func `a counter keeps the digits it shares`() {
            #expect(match("1234", "1235") == [0, 1, 2, nil])
            #expect(match("99", "100") == [nil, nil, nil])
            #expect(match("129", "130") == [0, nil, nil])
        }

        @Test
        func `matched glyphs never cross`() {
            let pairs = match("101", "110").compactMap(\.self)
            #expect(pairs == pairs.sorted())
            #expect(pairs.count == 2)
        }

        @Test
        func `a title keeps its shared words`() {
            let result = match("New Chat", "Chat")
            #expect(result == [4, 5, 6, 7])
        }

        @Test
        func `a long middle falls back to greedy matching in order`() {
            let base = (0 ..< 300).map { $0 % 7 }
            let old = [9] + base + [9]
            let new = [8] + base + [8]
            let result = GlyphMatcher.match(old: old, new: new, limit: 64)
            let pairs = result.compactMap(\.self)
            #expect(pairs == pairs.sorted())
            #expect(pairs.count == 300)
        }

        @Test
        func `numbers are read through grouping and signs`() {
            #expect(GlyphMatcher.numericValue(of: "1,024 tokens") == 1024)
            #expect(GlyphMatcher.numericValue(of: "-3.5") == -3.5)
            #expect(GlyphMatcher.numericValue(of: "\u{2212}7") == -7)
            #expect(GlyphMatcher.numericValue(of: "New Chat") == nil)
            #expect(LTXNumericTransitionAnimator.countsDown(from: "1,024", to: "644"))
            #expect(!LTXNumericTransitionAnimator.countsDown(from: "9", to: "10"))
            #expect(!LTXNumericTransitionAnimator.countsDown(from: "Hello", to: "World"))
        }
    }

    // MARK: - Animator

    @MainActor
    @Suite("Numeric transition animator")
    struct LTXNumericTransitionAnimatorTests {
        private static let font = PlatformFont.boldSystemFont(ofSize: 24)

        private func text(_ string: String, centered: Bool = false) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = centered ? .center : .natural
            return NSAttributedString(string: string, attributes: [
                .font: Self.font,
                .foregroundColor: CGColor(gray: 0, alpha: 1),
                .paragraphStyle: paragraph,
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
        func `numeric sprites at rest draw exactly what the label draws`() throws {
            let size = CGSize(width: 240, height: 60)
            let old = layout(text("1,024", centered: true), size: size)
            let new = layout(text("1,030", centered: true), size: size)
            _ = old.layoutLines
            _ = new.layoutLines
            let animator = LTXNumericTransitionAnimator()
            animator.animateChange(context(from: old, to: new), at: 0)

            let expected = try render(size: size) { context in
                new.draw(in: context)
            }
            let actual = try render(size: size) { context in
                // Layout space: what the label hands drawAdditionalContent.
                let flip = new.viewRect(fromLayoutRect: .zero).minY
                context.translateBy(x: 0, y: flip)
                context.scaleBy(x: 1, y: -1)
                context.textMatrix = .identity
                animator.drawAdditionalContent(in: context, at: 30)
            }
            #expect(animator.sprites.count(where: { !$0.isLeaving }) == 5)
            #expect(animator.sprites.count(where: \.isLeaving) == 2)
            #expect(expected == actual)
        }

        @Test
        func `a countdown rolls arriving glyphs in from above`() throws {
            let size = CGSize(width: 240, height: 60)
            let old = layout(text("10"), size: size)
            let new = layout(text("9"), size: size)
            _ = old.layoutLines
            _ = new.layoutLines
            let animator = LTXNumericTransitionAnimator()
            animator.animateChange(context(from: old, to: new), at: 0)
            try render(size: size) { context in
                animator.drawAdditionalContent(in: context, at: 0)
            }
            let arriving = try #require(animator.sprites.first { !$0.isLeaving })
            let leaving = try #require(animator.sprites.first { $0.isLeaving })
            // Layout space: y points up, so above is positive.
            #expect(arriving.from.offset.dy > 0)
            #expect(leaving.to.offset.dy < 0)
            #expect(arriving.from.scale == 0.4)
            #expect(arriving.from.alpha == 0)
        }

        @Test
        func `an explicit direction overrides the countdown`() throws {
            let size = CGSize(width: 240, height: 60)
            let old = layout(text("10"), size: size)
            let new = layout(text("9"), size: size)
            _ = old.layoutLines
            _ = new.layoutLines
            let animator = LTXNumericTransitionAnimator(configuration: .init(direction: .up))
            animator.animateChange(context(from: old, to: new), at: 0)
            _ = animator.advance(to: 0, invalidation: LTXInvalidationContext())
            let arriving = try #require(animator.sprites.first { !$0.isLeaving })
            #expect(arriving.from.offset.dy < 0)
        }

        @Test
        func `reduced motion fades glyphs in place`() throws {
            let size = CGSize(width: 240, height: 60)
            let old = layout(text("10"), size: size)
            let new = layout(text("9"), size: size)
            _ = old.layoutLines
            _ = new.layoutLines
            let animator = LTXNumericTransitionAnimator()
            animator.animateChange(context(from: old, to: new, prefersReducedMotion: true), at: 0)
            _ = animator.advance(to: 0, invalidation: LTXInvalidationContext())
            let arriving = try #require(animator.sprites.first { !$0.isLeaving })
            #expect(arriving.from.offset == .zero)
            #expect(arriving.from.scale == 1)
            #expect(arriving.from.alpha == 0)
        }

        @Test
        func `the transition settles and finish clears it`() {
            let size = CGSize(width: 240, height: 60)
            let old = layout(text("New Chat"), size: size)
            let new = layout(text("Chat"), size: size)
            _ = old.layoutLines
            _ = new.layoutLines
            let animator = LTXNumericTransitionAnimator()
            animator.animateChange(context(from: old, to: new), at: 0)
            let invalidation = LTXInvalidationContext()
            #expect(animator.advance(to: 0.05, invalidation: invalidation))
            #expect(animator.animatingRange == NSRange(location: 0, length: 4))
            #expect(!animator.advance(to: 30, invalidation: invalidation))

            animator.finish()
            #expect(animator.animatingRange == nil)
            #expect(animator.additionalContentBounds.isNull)
        }

        @Test
        func `the policy animates a whole replacement the default policy skips`() {
            let context = LTXAnimationContext(
                change: LTXTextChange(from: "99", to: "100"),
                previousIdentity: "counter",
                identity: "counter",
                previousLayout: TextLabel.Layout(attributedString: NSAttributedString(string: "99")),
                layout: TextLabel.Layout(attributedString: NSAttributedString(string: "100")),
                isInWindow: true,
                areAnimationsEnabled: true,
                prefersReducedMotion: false,
                wasAnimating: false,
            )
            #expect(LTXNumericTransitionAnimator.policy.shouldAnimate(context))
            #expect(!LTXDefaultAnimationPolicy().shouldAnimate(context))
        }

        /// Draws into an RGBA bitmap with a top-left origin, like a view, and returns its bytes.
        @discardableResult
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

#endif
