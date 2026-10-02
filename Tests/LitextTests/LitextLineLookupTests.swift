//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//
//  Line lookups binary-search when the line boxes descend in order and scan
//  otherwise. These tests hold the bisection to the scan it replaced, answer for
//  answer, on layouts built to break it, and check that it really is faster.
//
//  Reproduce a fuzz failure with the seed it prints:
//  `LITEXT_FUZZ_SEED=<seed> LITEXT_FUZZ_ITERATIONS=1 swift test --filter LineLookup`.
//

import CoreText
@testable import Litext
import Testing

@MainActor
@Suite("Line lookup")
struct LitextLineLookupTests {
    // MARK: - Reference

    /// `nearestLineIndex(toLayoutY:)` as it was before bisection: the first and
    /// last-line cases, then the scan.
    private static func referenceNearestLineIndex(_ layout: TextLabel.Layout, _ y: CGFloat) -> Int? {
        let lines = layout.layoutLines
        guard let first = lines.first, let last = lines.last else { return nil }
        if y > first.baselineOrigin.y {
            return 0
        }
        if y < last.baselineOrigin.y {
            return lines.count - 1
        }
        return layout.linearNearestLineIndex(toLayoutY: y)
    }

    /// Holds every lookup to its scan at each probe. Returns the number of
    /// mismatches, each recorded with `context`.
    @discardableResult
    private static func expectBisectionMatchesScan(
        _ layout: TextLabel.Layout,
        probes: [CGFloat],
        context: String,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) -> Int {
        var mismatches = 0
        for y in probes {
            let containing = layout.lineIndex(containingLayoutY: y)
            let containingReference = layout.linearLineIndex(containingLayoutY: y)
            if containing != containingReference {
                mismatches += 1
                Issue.record(
                    "line containing \(y): \(String(describing: containing)), scan \(String(describing: containingReference)) — \(context)",
                    sourceLocation: sourceLocation,
                )
            }
            let nearest = layout.nearestLineIndex(toLayoutY: y)
            let nearestReference = referenceNearestLineIndex(layout, y)
            if nearest != nearestReference {
                mismatches += 1
                Issue.record(
                    "line nearest \(y): \(String(describing: nearest)), scan \(String(describing: nearestReference)) — \(context)",
                    sourceLocation: sourceLocation,
                )
            }
        }
        // Every pair of probes as a rect, in both orders, so empty, inverted,
        // degenerate, NaN and infinite extents are all covered.
        let rectProbes = Array(probes.prefix(24))
        for top in rectProbes {
            for bottom in rectProbes {
                let rect = CGRect(x: 0, y: bottom, width: 10, height: top - bottom)
                let range = layout.lineIndices(intersectingLayoutRect: rect)
                let reference = layout.linearLineIndices(intersectingLayoutRect: rect)
                if range != reference {
                    mismatches += 1
                    Issue.record(
                        "lines in \(rect): \(range), scan \(reference) — \(context)",
                        sourceLocation: sourceLocation,
                    )
                }
            }
        }
        return mismatches
    }

    /// Every box edge, middle and baseline, a hair either side of each, values
    /// between and beyond the lines, and the non-finite values.
    private static func probes(for layout: TextLabel.Layout, random: inout SeededGenerator) -> [CGFloat] {
        var probes: [CGFloat] = [.nan, .infinity, -.infinity, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, 0]
        let lineCount = layout.layoutLines.count
        var low = CGFloat.greatestFiniteMagnitude
        var high = -CGFloat.greatestFiniteMagnitude
        for index in 0 ..< lineCount {
            let box = layout.lineBox(at: index)
            let baseline = layout.layoutLines[index].baselineOrigin.y
            for value in [box.minY, box.midY, box.maxY, baseline] where value.isFinite {
                probes += [value, value.nextUp, value.nextDown, value + 0.25, value - 0.25]
                low = min(low, value)
                high = max(high, value)
            }
        }
        if low <= high {
            for _ in 0 ..< 60 {
                probes.append(CGFloat.random(in: (low - 50) ... (high + 50), using: &random))
            }
        }
        // The non-finite values stay first, so the rect pairs always include them.
        var edges = Array(probes.dropFirst(6))
        edges.shuffle(using: &random)
        return Array(probes.prefix(6)) + edges.prefix(400)
    }

    // MARK: - Fuzzing

    private static let words = ["word", "a", "longerword", "  ", "\t", "mixed", "中文", "😀", "x"]

    /// A layout of random paragraphs whose fonts, spacing, line heights and
    /// attachments vary from paragraph to paragraph, in a random container.
    private static func makeRandomLayout(random: inout SeededGenerator) -> (TextLabel.Layout, String) {
        let text = NSMutableAttributedString()
        let paragraphCount = Int.random(in: 0 ... 40, using: &random)
        var summary: [String] = []
        for paragraph in 0 ..< paragraphCount {
            let fontSize = [1, 6, 12, 17, 30, 60].randomElement(using: &random)!
            let style = NSMutableParagraphStyle()
            style.lineSpacing = [0, 0, 3, 20].randomElement(using: &random)!
            style.paragraphSpacing = [0, 0, 8].randomElement(using: &random)!
            style.paragraphSpacingBefore = [0, 0, 5].randomElement(using: &random)!
            style.minimumLineHeight = [0, 0, 40].randomElement(using: &random)!
            // Line heights below the font's give lines a negative descent and
            // make boxes overlap; mixed with other font sizes, out of order.
            style.maximumLineHeight = [0, 0, 2, 5, 14].randomElement(using: &random)!
            // A tiny multiple over mixed font sizes overlaps boxes out of order.
            style.lineHeightMultiple = [0, 0, 0.1, 0.5, 2].randomElement(using: &random)!
            let attributes: [NSAttributedString.Key: Any] = [
                .font: PlatformFont.systemFont(ofSize: CGFloat(fontSize)),
                .paragraphStyle: style,
            ]
            let wordCount = Int.random(in: 0 ... 25, using: &random)
            var string = ""
            for _ in 0 ..< wordCount {
                string += words.randomElement(using: &random)! + " "
            }
            text.append(NSAttributedString(string: string, attributes: attributes))
            if Bool.random(using: &random), Int.random(in: 0 ... 3, using: &random) == 0 {
                let attachment = TextLabel.Attachment(size: CGSize(
                    width: CGFloat.random(in: 1 ... 80, using: &random),
                    height: [0.5, 10, 40, 120].randomElement(using: &random)!,
                ))
                attachment.descent = [nil, 0, 5, 500].randomElement(using: &random)!
                text.append(attachment.attributedString(attributes: attributes))
            }
            if paragraph < paragraphCount - 1 {
                text.append(NSAttributedString(string: "\n", attributes: attributes))
            }
            summary.append("\(fontSize)pt/max\(style.maximumLineHeight)")
        }

        let layout = TextLabel.Layout(attributedString: text)
        let width: CGFloat = [0, 40, 120, 320].randomElement(using: &random)!
        let measured = layout.sizeThatFits(CGSize(width: width, height: 0))
        let height = [measured.height, measured.height / 2, 0, 1e7, 1e9].randomElement(using: &random)!
        layout.containerSize = CGSize(width: width, height: height)
        return (layout, "width \(width), height \(height), paragraphs \(summary)")
    }

    @Test
    func `bisection matches the scan on random layouts`() {
        let iterations = StressMode.environment["LITEXT_FUZZ_ITERATIONS"].flatMap(Int.init)
            ?? (StressMode.isEnabled ? StressMode.fuzzIterations : 80)
        var orderedLayouts = 0
        var unorderedLayouts = 0
        var mismatches = 0
        for iteration in 0 ..< iterations {
            let seed = StressMode.fuzzSeed &+ UInt64(iteration)
            var random = SeededGenerator(seed: seed)
            let (layout, description) = Self.makeRandomLayout(random: &random)
            if layout.lineBoxesAreOrdered {
                orderedLayouts += 1
            } else {
                unorderedLayouts += 1
            }
            mismatches += Self.expectBisectionMatchesScan(
                layout,
                probes: Self.probes(for: layout, random: &random),
                context: "seed \(seed): \(description)",
            )
            if mismatches > 20 {
                break
            }
        }
        print("[line lookup] fuzz: \(orderedLayouts) ordered layouts, \(unorderedLayouts) out of order")
        // Both paths must have run, or the fuzz proves nothing about one of them.
        #expect(orderedLayouts > iterations / 4)
        #expect(unorderedLayouts > 0 || iterations < 50)
    }

    // MARK: - Hostile layouts

    private static func paragraphs(
        _ fontSizes: [CGFloat],
        maximumLineHeight: CGFloat = 0,
        lineHeightMultiple: CGFloat = 0,
        text: String = "Line",
    ) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.maximumLineHeight = maximumLineHeight
        style.lineHeightMultiple = lineHeightMultiple
        let result = NSMutableAttributedString()
        for (index, size) in fontSizes.enumerated() {
            result.append(NSAttributedString(
                string: index == fontSizes.count - 1 ? text : text + "\n",
                attributes: [.font: PlatformFont.systemFont(ofSize: size), .paragraphStyle: style],
            ))
        }
        return result
    }

    private static func laidOut(_ text: NSAttributedString, width: CGFloat = 300, height: CGFloat? = nil) -> TextLabel.Layout {
        let layout = TextLabel.Layout(attributedString: text)
        let measured = layout.sizeThatFits(CGSize(width: width, height: 0))
        layout.containerSize = CGSize(width: width, height: height ?? measured.height)
        return layout
    }

    @Test
    func `squeezed lines of mixed sizes fall back to the scan`() {
        // A 60 pt line squeezed to a tenth of its height reaches far above the
        // 6 pt line before it.
        let layout = Self.laidOut(Self.paragraphs([6, 60, 6, 60, 6], lineHeightMultiple: 0.1))
        #expect(!layout.lineBoxesAreOrdered)
        var random = SeededGenerator(seed: 1)
        Self.expectBisectionMatchesScan(layout, probes: Self.probes(for: layout, random: &random), context: "squeezed")
    }

    @Test(arguments: [
        ("uniform", [CGFloat](repeating: 16, count: 50), CGFloat(0), CGFloat(0)),
        ("tiny fonts", [CGFloat](repeating: 0.5, count: 50), 0, 0),
        ("squeezed uniform", [CGFloat](repeating: 30, count: 50), 3, 0),
        ("tight multiple", [CGFloat](repeating: 20, count: 50), 0, 0.3),
        ("growing", (1 ... 40).map { CGFloat($0) }, 0, 0),
        ("shrinking", (1 ... 40).reversed().map { CGFloat($0) }, 0, 0),
    ])
    func `bisection matches the scan on hostile ordered layouts`(
        name: String,
        sizes: [CGFloat],
        maximumLineHeight: CGFloat,
        lineHeightMultiple: CGFloat,
    ) {
        let text = Self.paragraphs(sizes, maximumLineHeight: maximumLineHeight, lineHeightMultiple: lineHeightMultiple)
        // Heights that put the lines near zero, far below it, and at the
        // magnitudes where neighbouring middles round to equal distances.
        for height in [nil, 0, 1e7, 1e8, 1e9] as [CGFloat?] {
            let layout = Self.laidOut(text, height: height)
            var random = SeededGenerator(seed: 7)
            Self.expectBisectionMatchesScan(
                layout,
                probes: Self.probes(for: layout, random: &random),
                context: "\(name), height \(String(describing: height)), ordered \(layout.lineBoxesAreOrdered)",
            )
        }
    }

    @Test
    func `empty lines and an empty layout agree with the scan`() {
        let empty = Self.laidOut(NSAttributedString())
        #expect(empty.lineIndex(containingLayoutY: 0) == nil)
        #expect(empty.nearestLineIndex(toLayoutY: 0) == nil)
        #expect(empty.lineIndices(intersectingLayoutRect: CGRect(x: 0, y: -100, width: 10, height: 200)).isEmpty)

        let blank = Self.laidOut(NSAttributedString(
            string: String(repeating: "\n", count: 30),
            attributes: [.font: PlatformFont.systemFont(ofSize: 14)],
        ))
        var random = SeededGenerator(seed: 3)
        Self.expectBisectionMatchesScan(blank, probes: Self.probes(for: blank, random: &random), context: "blank lines")
    }

    @Test
    func `public hit testing is unchanged on a long document`() throws {
        let layout = Self.laidOut(Self.paragraphs([CGFloat](repeating: 14, count: 400), text: "Some words on a line"))
        #expect(layout.lineBoxesAreOrdered)
        let lines = layout.layoutLines
        for index in stride(from: 0, to: lines.count, by: 37) {
            let line = lines[index]
            let point = CGPoint(x: 20, y: line.rect.midY)
            #expect(layout.lineIndex(containingLayoutY: point.y) == index)
            let caret = try #require(layout.nearestTextIndex(at: point))
            #expect(NSLocationInRange(caret, line.stringRange))
            let character = try #require(layout.characterIndex(at: point))
            #expect(NSLocationInRange(character, line.stringRange))
        }
        // Below the last line, the text index is the end of the text.
        let bottom = try #require(lines.last).rect.minY - 50
        #expect(layout.textIndex(at: CGPoint(x: 5, y: bottom)) == layout.attributedString.length)
    }

    // MARK: - Speed

    /// A 10,000-line document, laid out once for the speed tests.
    private static let longDocument = laidOut(paragraphs([CGFloat](repeating: 12, count: 10000)))
    private static let shortDocument = laidOut(paragraphs([CGFloat](repeating: 12, count: 100)))

    /// The fastest of `trials` timings of `body`, in seconds per repetition:
    /// interference only ever slows a run down.
    private static func fastest(trials: Int = 5, repetitions: Int, _ body: () -> Void) -> Double {
        let clock = ContinuousClock()
        var best = Double.infinity
        for _ in 0 ..< trials {
            let start = clock.now
            for _ in 0 ..< repetitions {
                body()
            }
            best = min(best, seconds(of: clock.now - start))
        }
        return best / Double(repetitions)
    }

    /// The time of one lookup, averaged over points in the bottom tenth of the
    /// layout, where the scan has the most lines to pass.
    private static func timePerLookup(
        _ layout: TextLabel.Layout,
        repetitions: Int,
        _ lookup: (CGFloat) -> Int?,
    ) -> Double {
        let lines = layout.layoutLines
        let ys = (0 ..< 50).map { index in
            lines[lines.count - 1 - index * max(lines.count / 500, 1)].rect.midY
        }
        var sink = 0
        let time = fastest(repetitions: repetitions) {
            for y in ys {
                sink &+= lookup(y) ?? 0
            }
        }
        #expect(sink != -1)
        return time / Double(ys.count)
    }

    @Test
    func `bisection is faster and grows logarithmically, as the scan's harness can tell`() {
        let small = Self.shortDocument
        let large = Self.longDocument
        #expect(small.lineBoxesAreOrdered && large.lineBoxesAreOrdered)

        let bisectSmall = Self.timePerLookup(small, repetitions: 200) { small.lineIndex(containingLayoutY: $0) }
        let bisectLarge = Self.timePerLookup(large, repetitions: 200) { large.lineIndex(containingLayoutY: $0) }
        let scanSmall = Self.timePerLookup(small, repetitions: 40) { small.linearLineIndex(containingLayoutY: $0) }
        let scanLarge = Self.timePerLookup(large, repetitions: 1) { large.linearLineIndex(containingLayoutY: $0) }
        print(
            "[line lookup] per lookup — 100 lines: bisect \(bisectSmall) s, scan \(scanSmall) s; "
                + "10,000 lines: bisect \(bisectLarge) s, scan \(scanLarge) s",
        )

        // The harness must see the scan grow with the line count, 100× here, or
        // it could not tell a linear lookup from a logarithmic one.
        #expect(scanLarge / scanSmall > 20)
        // Bisection grows with the logarithm: 14 steps against 7.
        #expect(bisectLarge / bisectSmall < 6)
        // And on the long document it beats the scan by orders of magnitude.
        #expect(scanLarge / bisectLarge > 30)
    }

    @Test
    func `public hit testing on a long document costs what it does on a short one`() {
        let small = Self.shortDocument
        let large = Self.longDocument
        func timeNearest(_ layout: TextLabel.Layout) -> Double {
            Self.timePerLookup(layout, repetitions: 40) { layout.nearestTextIndex(at: CGPoint(x: 20, y: $0)) }
        }
        let nearestSmall = timeNearest(small)
        let nearestLarge = timeNearest(large)
        print("[line lookup] nearestTextIndex per call — 100 lines: \(nearestSmall) s, 10,000 lines: \(nearestLarge) s")
        // A scan would make the long document about 100× slower; finding the
        // caret within the line costs the same on both.
        #expect(nearestLarge / nearestSmall < 4)
    }

    @Test
    func `drawing a window of a long document culls by bisection`() {
        let large = Self.longDocument
        let bottom = CGRect(x: 0, y: large.containerSize.height - 900, width: 300, height: 900)
        let layoutBottom = large.layoutRect(fromViewRect: bottom)
        #expect(
            large.lineIndices(intersectingLayoutRect: layoutBottom)
                == large.linearLineIndices(intersectingLayoutRect: layoutBottom),
        )

        let culled = Self.fastest(repetitions: 500) { _ = large.lineIndices(intersectingLayoutRect: layoutBottom) }
        let scanned = Self.fastest(repetitions: 5) { _ = large.linearLineIndices(intersectingLayoutRect: layoutBottom) }
        print("[line lookup] culling the bottom 900 pt of 10,000 lines: bisect \(culled) s, scan \(scanned) s")
        #expect(scanned / culled > 30)
        #expect(large.visibleLineCount(in: bottom) < 100)
    }
}
