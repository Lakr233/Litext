//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//
//  Stress tests: robustness under load and adversarial input.
//
//  Every stress test is tagged `.stress` and is skipped unless `LITEXT_STRESS`
//  asks for it, so a plain `swift test` stays fast:
//
//  - Quick (`LITEXT_STRESS=1 swift test --filter Stress`): reduced inputs and
//    2,000 fuzz iterations, about 25 s on an M4 Max.
//  - Full (`LITEXT_STRESS=full swift test --filter Stress`): the full-size
//    inputs (100k lines, a 1 MB paragraph, 10k links, 10,000 view updates, ...)
//    and 20,000 fuzz iterations. Expect several minutes, most of it CoreText
//    typesetting the 1 MB paragraph, which is quadratic in paragraph length
//    inside CoreText.
//
//  On a simulator, pass the variable to the test runner with
//  `TEST_RUNNER_LITEXT_STRESS=1 xcodebuild test ...`. Other knobs:
//
//  - `LITEXT_FUZZ_ITERATIONS=<n>` overrides the fuzz iteration count.
//  - `LITEXT_FUZZ_SEED=<n>` sets the base seed. A failing fuzz case prints its
//    seed and a shrunk input, and re-running with that seed reproduces it.
//
//  Each measured step has a time budget, roughly 5-10x the time it takes on an
//  M4 Max, so a slip into quadratic behaviour fails loudly while ordinary
//  machine noise does not. Steps that take milliseconds get a floor of 1-2 s
//  instead, where scheduler noise would dominate a multiple. Budgets for the
//  full sizes apply when LITEXT_STRESS=full.
//

import CoreGraphics
import CoreText
import Foundation
@testable import Litext
import Testing

extension Tag {
    @Tag static var stress: Self
}

enum StressMode {
    static let environment = ProcessInfo.processInfo.environment

    /// `true` when `LITEXT_STRESS` is set to anything but `0`, which runs the
    /// stress suites at all.
    static let isEnabled: Bool = environment["LITEXT_STRESS"].map { !$0.isEmpty && $0 != "0" } ?? false

    /// `true` when `LITEXT_STRESS=full` asks for the full-size runs.
    static let isFull: Bool = environment["LITEXT_STRESS"] == "full"

    /// The trait that skips a stress suite unless `LITEXT_STRESS` is set.
    static var enabled: ConditionTrait {
        .enabled(if: isEnabled, "Set LITEXT_STRESS=1 (quick) or LITEXT_STRESS=full to run the stress tests")
    }

    /// Picks the quick or the full-size value.
    static func pick<T>(_ standard: T, full: T) -> T {
        isFull ? full : standard
    }

    static let fuzzIterations: Int = {
        if let value = environment["LITEXT_FUZZ_ITERATIONS"].flatMap(Int.init), value > 0 {
            return value
        }
        return pick(2000, full: 20000)
    }()

    static let fuzzSeed: UInt64 = environment["LITEXT_FUZZ_SEED"].flatMap(UInt64.init) ?? 0x5EED_1A7E
}

// MARK: - Time budgets

/// Runs `body`, prints how long it took and records an issue when it took
/// longer than `budget` seconds.
@MainActor
@discardableResult
func withinBudget<T>(
    _ label: String,
    seconds budget: Double,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: () throws -> T
) rethrows -> T {
    let clock = ContinuousClock()
    let start = clock.now
    let result = try body()
    let elapsed = clock.now - start
    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    print("[stress] \(label): \(String(format: "%.3f", seconds)) s (budget \(budget) s)")
    #expect(
        seconds <= budget,
        "\(label) took \(seconds) s, over its \(budget) s budget",
        sourceLocation: sourceLocation
    )
    return result
}

func seconds(of duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}

// MARK: - Seeded randomness

/// SplitMix64: small, fast and identical on every platform, so a seed
/// reproduces the same input everywhere.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Geometry checks

extension CGRect {
    var isFiniteRect: Bool {
        origin.x.isFinite && origin.y.isFinite && size.width.isFinite && size.height.isFinite
    }
}

extension CGSize {
    var isFiniteSize: Bool {
        width.isFinite && height.isFinite
    }
}

extension CGPoint {
    var isFinitePoint: Bool {
        x.isFinite && y.isFinite
    }
}

/// A bitmap context to draw layouts into.
func makeStressContext(width: Int = 64, height: Int = 64) -> CGContext {
    CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
    )!
}

/// Collects violations of the invariants every layout must keep, whatever its input.
@MainActor
struct LayoutAudit {
    private(set) var problems: [String] = []

    mutating func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition {
            problems.append(message())
        }
    }

    /// Measures, lays out, draws and queries `layout` at `containerSize`.
    ///
    /// - `samplePoints`: points, in layout space, for the index queries.
    /// - `ranges`: ranges for `rects(for:)`, in addition to the full range.
    mutating func audit(
        _ layout: TextLabel.Layout,
        containerSize: CGSize,
        samplePoints: [CGPoint],
        ranges: [NSRange] = [],
        context: CGContext? = nil,
        visibleRect: CGRect? = nil,
        drawsEverything: Bool = true
    ) {
        let length = layout.attributedString.length
        for constraint in [
            containerSize,
            CGSize(width: containerSize.width, height: .greatestFiniteMagnitude),
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
        ] {
            let fit = layout.sizeThatFits(constraint)
            check(fit.isFiniteSize && fit.width >= 0 && fit.height >= 0, "sizeThatFits(\(constraint)) = \(fit)")
        }

        layout.containerSize = containerSize
        layout.updateHighlightRegions()

        if let context {
            layout.draw(in: context, visibleRect: visibleRect)
            if drawsEverything {
                layout.draw(in: context, visibleRect: nil)
            }
        }

        let fullRange = NSRange(location: 0, length: length)
        for range in [fullRange] + ranges {
            for rect in layout.rects(for: range) {
                check(rect.isFiniteRect, "rects(for: \(range)) has \(rect)")
            }
        }

        for point in samplePoints {
            for (name, index) in [
                ("textIndex", layout.textIndex(at: point)),
                ("nearestTextIndex", layout.nearestTextIndex(at: point)),
                ("characterIndex", layout.characterIndex(at: point)),
            ] {
                if let index {
                    check(index >= 0 && index <= length, "\(name)(at: \(point)) = \(index), length \(length)")
                }
            }
        }

        for region in layout.highlightRegions {
            check(
                region.stringRange.location >= 0 && NSMaxRange(region.stringRange) <= length,
                "highlight region \(region.stringRange) beyond length \(length)"
            )
            for rect in region.rects {
                check(rect.isFiniteRect, "highlight region rect \(rect)")
            }
        }
    }

    /// Checks that the laid-out runs carrying `key`, which the caller applied to
    /// the whole string, cover every character exactly once with lines in order.
    mutating func checkLinesCoverString(_ layout: TextLabel.Layout, key: NSAttributedString.Key) {
        let length = layout.attributedString.length
        let runs = layout.layoutRuns(matching: key)
        var lineRanges = [Int: (start: Int, end: Int, covered: Int)]()
        var previousLine = -1
        for run in runs {
            check(run.rect.isFiniteRect, "run rect \(run.rect)")
            check(run.lineRect.isFiniteRect, "line rect \(run.lineRect)")
            check(run.lineIndex >= previousLine, "line \(run.lineIndex) enumerated after line \(previousLine)")
            previousLine = run.lineIndex
            let range = run.stringRange
            var entry = lineRanges[run.lineIndex] ?? (start: Int.max, end: Int.min, covered: 0)
            entry.start = min(entry.start, range.location)
            entry.end = max(entry.end, NSMaxRange(range))
            entry.covered += range.length
            lineRanges[run.lineIndex] = entry
        }
        var expectedStart = 0
        for lineIndex in lineRanges.keys.sorted() {
            let entry = lineRanges[lineIndex]!
            check(entry.start == expectedStart, "line \(lineIndex) starts at \(entry.start), expected \(expectedStart)")
            check(
                entry.covered == entry.end - entry.start,
                "line \(lineIndex) runs cover \(entry.covered) of \(entry.start)..<\(entry.end)"
            )
            expectedStart = entry.end
        }
        check(expectedStart == length, "lines end at \(expectedStart), length \(length)")
    }

    func record(_ context: @autoclosure () -> String, sourceLocation: SourceLocation = #_sourceLocation) {
        for problem in problems {
            Issue.record("\(context()): \(problem)", sourceLocation: sourceLocation)
        }
    }
}

/// Evenly spread points across `size`, plus points outside it on every side.
func samplePoints(in size: CGSize, count: Int) -> [CGPoint] {
    let width = size.width.isFinite ? size.width : 1000
    let height = size.height.isFinite ? size.height : 1000
    var points = [CGPoint]()
    let side = max(1, Int(Double(count).squareRoot()))
    for row in 0 ..< side {
        for column in 0 ..< side {
            points.append(CGPoint(
                x: width * CGFloat(column) / CGFloat(side),
                y: height * CGFloat(row) / CGFloat(side)
            ))
        }
    }
    points += [
        CGPoint(x: -100, y: -100),
        CGPoint(x: width + 100, y: height + 100),
        CGPoint(x: width / 2, y: -1e6),
        CGPoint(x: width / 2, y: height + 1e6),
        CGPoint(x: -1e9, y: height / 2),
        CGPoint(x: 1e9, y: height / 2),
    ]
    return points
}

/// A short, readable description of a string, escaping everything outside
/// printable ASCII so control characters and lone surrogates show up.
func escapedDescription(_ string: NSString, limit: Int = 400) -> String {
    var result = ""
    let count = min(string.length, limit)
    for index in 0 ..< count {
        let unit = string.character(at: index)
        if unit >= 0x20, unit < 0x7F {
            result.append(Character(Unicode.Scalar(UInt8(unit))))
        } else {
            result += String(format: "\\u{%04X}", unit)
        }
    }
    if string.length > limit {
        result += "... (\(string.length) UTF-16 units)"
    }
    return result
}
