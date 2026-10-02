//
//  AnimationEffectsTests.swift
//  OhMyLitextTests
//
//  Created by Litext Team.
//
//  The pure parts of the sample animators: curves, springs, quantization,
//  text units, glyph matching, and the hand-over from the numeric transition's
//  sprites to the label's own drawing.
//

import CoreGraphics
import CoreText
import Foundation
import Litext
import LitextAnimation
import Testing

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

// MARK: - Curves and springs

struct AnimationCurveTests {
    @Test
    func `a Bézier curve runs from zero to one and clamps outside`() {
        for curve in [CubicBezierCurve.easeOut, .easeInOut, .linear] {
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
            #expect(abs(CubicBezierCurve.linear.value(at: progress) - progress) < 1e-5)
            #expect(CubicBezierCurve.easeOut.value(at: progress) > progress)
        }
        #expect(abs(CubicBezierCurve.easeInOut.value(at: 0.5) - 0.5) < 1e-5)
    }

    @Test
    func `a spring starts at full displacement and settles within its tolerance`() {
        for spring in [DampedSpring.bouncy, .smooth, DampedSpring(response: 0.3, dampingRatio: 1.6)] {
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
        let bouncyMinimum = times.map { DampedSpring.bouncy.displacement(at: $0) }.min() ?? 0
        let smoothMinimum = times.map { DampedSpring.smooth.displacement(at: $0) }.min() ?? 0
        #expect(bouncyMinimum < -0.1)
        #expect(smoothMinimum >= 0)
        // A response of 0.4 s and a damping ratio of 0.54 crosses the target first
        // after about 0.15 s.
        #expect(DampedSpring.bouncy.displacement(at: 0.12) > 0)
        #expect(DampedSpring.bouncy.displacement(at: 0.2) < 0)
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
        let schedule = StaggerSchedule(interval: 0.02, maxTotalDelay: 0.2)
        #expect(schedule.interval(forUnitCount: 1) == 0)
        #expect(schedule.interval(forUnitCount: 5) == 0.02)
        #expect(abs(schedule.interval(forUnitCount: 101) * 100 - 0.2) < 1e-12)
    }
}

// MARK: - Text units

struct TextUnitTests {
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

// MARK: - Glyph matching

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
        #expect(NumericTransitionAnimator.countsDown(from: "1,024", to: "644"))
        #expect(!NumericTransitionAnimator.countsDown(from: "9", to: "10"))
        #expect(!NumericTransitionAnimator.countsDown(from: "Hello", to: "World"))
    }
}

// MARK: - Animators

@MainActor
struct AnimatorTests {
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

    private func context(from old: TextLabel.Layout, to new: TextLabel.Layout) -> LTXAnimationContext {
        LTXAnimationContext(
            change: LTXTextChange(from: old.attributedString, to: new.attributedString),
            previousIdentity: nil,
            identity: nil,
            previousLayout: old,
            layout: new,
            isInWindow: true,
            areAnimationsEnabled: true,
            prefersReducedMotion: false,
            wasAnimating: false,
        )
    }

    @Test
    func `fade-in staggers units and finishes each at full opacity`() throws {
        let size = CGSize(width: 400, height: 100)
        let old = layout(text("Hello"), size: size)
        let new = layout(text("Hello world"), size: size)
        let animator = FadeInAnimator()
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
        let animator = FadeInAnimator()
        animator.animateChange(context(from: first, to: second), at: 0)
        animator.animateChange(context(from: second, to: third), at: 0.05)

        let ranges = animator.batches.map(\.range)
        #expect(ranges == [NSRange(location: 0, length: 3), NSRange(location: 8, length: 6)])
        let moved = try #require(animator.batches.last)
        #expect(moved.unitStarts.first == 8)

        animator.finish()
        #expect(animator.animatingRange == nil)
    }

    @Test(arguments: [1.0, 0.1])
    func `a fast stream keeps its chunks in order with a bounded lag`(speed: Double) {
        let size = CGSize(width: 2000, height: 200)
        let animator = FadeInAnimator()
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
    func `fade-up reports its rise as overdraw below the line`() {
        let animator = FadeUpAnimator(rise: 6)
        #expect(animator.overdrawInsets == LTXInsets(top: 0, left: 0, bottom: 6, right: 0))
        #expect(FadeInAnimator().overdrawInsets == .zero)
    }

    @Test
    func `numeric sprites at rest draw exactly what the label draws`() throws {
        let size = CGSize(width: 240, height: 60)
        let old = layout(text("1,024", centered: true), size: size)
        let new = layout(text("1,030", centered: true), size: size)
        _ = old.layoutLines
        _ = new.layoutLines
        let animator = NumericTransitionAnimator()
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
        let animator = NumericTransitionAnimator()
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
