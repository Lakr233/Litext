//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//
//  Stress: seeded, reproducible fuzzing. See StressSupport.swift for the
//  default and LITEXT_STRESS=1 modes.
//
//  2,000 iterations by default, 20,000 with LITEXT_STRESS=1, or any count with
//  LITEXT_FUZZ_ITERATIONS. Iteration i uses seed LITEXT_FUZZ_SEED + i (base
//  0x5EED1A7E). A failure is shrunk to a minimal input and reported with its
//  seed; re-run just that case with
//  `LITEXT_FUZZ_SEED=<seed> LITEXT_FUZZ_ITERATIONS=1 swift test --filter StressFuzz`.
//

import CoreGraphics
import CoreText
import Foundation
@testable import Litext
import Testing

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

extension NSAttributedString.Key {
    /// Applied to every fuzzed string so its laid-out runs reveal line coverage.
    static let stressCoverage = NSAttributedString.Key("LitextStressCoverage")
}

/// One fuzzed input, kept structured so a failure can be shrunk.
struct FuzzCase: CustomStringConvertible {
    enum Link {
        case url
        case string
        case invalidString
        case number
    }

    enum Paragraph {
        case left
        case center
        case right
        case justified
        case rightToLeft
        case indented(head: CGFloat, tail: CGFloat)
        case spaced(line: CGFloat, paragraph: CGFloat)
        case heights(min: CGFloat, max: CGFloat)
    }

    struct Segment {
        var units: [UInt16]
        var fontSize: CGFloat
        var bold: Bool
        var colorIndex: Int?
        var link: Link?
        var linkGroup: Int
        var attachment: CGSize?
        var paragraph: Paragraph?
        var kern: CGFloat?
        var baselineOffset: CGFloat?
    }

    var seed: UInt64
    var segments: [Segment]
    var widths: [CGFloat]
    var height: CGFloat
    var ranges: [NSRange]
    var points: [CGPoint]

    var description: String {
        var lines = ["seed \(seed), widths \(widths), height \(height)"]
        for (index, segment) in segments.enumerated() {
            let text = escapedDescription(NSString(characters: segment.units, length: segment.units.count), limit: 120)
            var attributes = ["size \(segment.fontSize)"]
            if segment.bold {
                attributes.append("bold")
            }
            if let colorIndex = segment.colorIndex {
                attributes.append("color \(colorIndex)")
            }
            if let link = segment.link {
                attributes.append("link \(link) #\(segment.linkGroup)")
            }
            if let attachment = segment.attachment {
                attributes.append("attachment \(attachment)")
            }
            if let paragraph = segment.paragraph {
                attributes.append("paragraph \(paragraph)")
            }
            if let kern = segment.kern {
                attributes.append("kern \(kern)")
            }
            if let offset = segment.baselineOffset {
                attributes.append("baseline \(offset)")
            }
            lines.append("  [\(index)] \"\(text)\" \(attributes.joined(separator: ", "))")
        }
        lines.append("  ranges \(ranges)")
        return lines.joined(separator: "\n")
    }

    // MARK: Generation

    /// Pieces drawn from many scripts and from the awkward corners of Unicode.
    static let pieces: [[UInt16]] = [
        "Hello", "world", "Litext", " ", "  ", "\t", "\n", "\r\n", "\u{2028}", "\u{2029}",
        "Ελληνικά", "кириллица", "中文字符", "日本語のテキスト", "한국어", "ไทยภาษา", "हिन्दी",
        "שלום", "مرحبا بالعالم", "\u{202E}", "\u{202C}", "\u{2067}", "\u{2069}", "\u{200F}", "\u{200E}",
        "👨‍👩‍👧‍👦", "🇯🇵", "🏳️‍🌈", "e\u{0301}", "\u{0301}\u{0302}", "\u{200D}", "\u{FE0F}", "\u{00AD}",
        "\u{FFFC}", "\u{0000}", "-", "—", "https://example.com/path?q=1", "supercalifragilistic",
        "0123456789", ".", ",", "!", "(", ")", "\"", "'",
    ].map { Array($0.utf16) } + [[0xD800], [0xDC00], [0xFFFF]]

    @MainActor
    static func generate(seed: UInt64) -> FuzzCase {
        var random = SeededGenerator(seed: seed)
        let segmentCount = Int.random(in: 0 ... 24, using: &random)
        var segments = [Segment]()
        for _ in 0 ..< segmentCount {
            var units = [UInt16]()
            for _ in 0 ..< Int.random(in: 1 ... 6, using: &random) {
                units += pieces.randomElement(using: &random)!
            }
            let roll = Int.random(in: 0 ..< 100, using: &random)
            segments.append(Segment(
                units: units,
                fontSize: [0.5, 8, 12, 15, 17, 24, 48, 120].randomElement(using: &random)!,
                bold: Bool.random(using: &random),
                colorIndex: roll < 50 ? Int.random(in: 0 ..< 4, using: &random) : nil,
                link: roll < 25 ? [.url, .string, .invalidString, .number].randomElement(using: &random)! : nil,
                linkGroup: Int.random(in: 0 ..< 3, using: &random),
                attachment: (30 ..< 40).contains(roll)
                    ? CGSize(
                        width: [0, 1, 20, 300, 5000].randomElement(using: &random)!,
                        height: [0, 1, 20, 300].randomElement(using: &random)!
                    )
                    : nil,
                paragraph: (40 ..< 60).contains(roll) ? randomParagraph(using: &random) : nil,
                kern: roll % 7 == 0 ? CGFloat.random(in: -20 ... 20, using: &random) : nil,
                baselineOffset: roll % 11 == 0 ? CGFloat.random(in: -50 ... 50, using: &random) : nil
            ))
        }
        let widthChoices: [CGFloat] = [0.5, 1, 7, 33, 100, 200, 320, 375, 1000, 100_000]
        let widths = (0 ..< 2).map { _ in
            Bool.random(using: &random)
                ? widthChoices.randomElement(using: &random)!
                : CGFloat.random(in: 1 ... 800, using: &random)
        }
        let height = [0, 10, 100, 500, 5000].randomElement(using: &random)! as CGFloat

        var fuzzCase = FuzzCase(seed: seed, segments: segments, widths: widths, height: height, ranges: [], points: [])
        let length = fuzzCase.build().length
        var ranges: [NSRange] = [
            NSRange(location: NSNotFound, length: 0),
            NSRange(location: NSNotFound, length: 5),
            NSRange(location: -3, length: 10),
            NSRange(location: 0, length: Int.max),
            NSRange(location: Int.max - 1, length: 1),
            NSRange(location: length, length: 1),
            NSRange(location: length + 10, length: 3),
            NSRange(location: 0, length: 0),
            NSRange(location: 0, length: length),
        ]
        for _ in 0 ..< 6 {
            let location = Int.random(in: -2 ... max(0, length + 2), using: &random)
            ranges.append(NSRange(location: location, length: Int.random(in: -1 ... max(0, length + 3), using: &random)))
        }
        fuzzCase.ranges = ranges
        fuzzCase.points = (0 ..< 12).map { _ in
            CGPoint(
                x: CGFloat.random(in: -50 ... 900, using: &random),
                y: CGFloat.random(in: -50 ... 900, using: &random)
            )
        } + [
            CGPoint(x: CGFloat.nan, y: 10),
            CGPoint(x: 10, y: CGFloat.nan),
            CGPoint(x: CGFloat.infinity, y: -CGFloat.infinity),
            CGPoint(x: -1e12, y: 1e12),
        ]
        return fuzzCase
    }

    private static func randomParagraph(using random: inout SeededGenerator) -> Paragraph {
        switch Int.random(in: 0 ..< 8, using: &random) {
        case 0: .left
        case 1: .center
        case 2: .right
        case 3: .justified
        case 4: .rightToLeft
        case 5: .indented(
                head: CGFloat.random(in: -200 ... 400, using: &random),
                tail: CGFloat.random(in: -400 ... 400, using: &random)
            )
        case 6: .spaced(
                line: CGFloat.random(in: 0 ... 100, using: &random),
                paragraph: CGFloat.random(in: 0 ... 100, using: &random)
            )
        default: .heights(
                min: CGFloat.random(in: 0 ... 80, using: &random),
                max: CGFloat.random(in: 0 ... 80, using: &random)
            )
        }
    }

    // MARK: Building

    @MainActor
    func build() -> NSAttributedString {
        let colors: [PlatformColor] = [.red, .blue, .green, .gray]
        let result = NSMutableAttributedString()
        for segment in segments {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: segment.bold
                    ? PlatformFont.boldSystemFont(ofSize: segment.fontSize)
                    : PlatformFont.systemFont(ofSize: segment.fontSize),
            ]
            if let colorIndex = segment.colorIndex {
                attributes[.foregroundColor] = colors[colorIndex]
            }
            switch segment.link {
            case .url: attributes[.link] = URL(string: "https://example.com/\(segment.linkGroup)")!
            case .string: attributes[.link] = "https://example.org/\(segment.linkGroup)"
            case .invalidString: attributes[.link] = "not a url \(segment.linkGroup) %%"
            case .number: attributes[.link] = NSNumber(value: segment.linkGroup)
            case nil: break
            }
            if let paragraph = segment.paragraph {
                attributes[.paragraphStyle] = Self.style(paragraph)
            }
            if let kern = segment.kern {
                attributes[.kern] = kern
            }
            if let offset = segment.baselineOffset {
                attributes[.baselineOffset] = offset
            }
            if let size = segment.attachment {
                result.append(TextLabel.Attachment(size: size).attributedString(attributes: attributes))
            }
            let string = NSString(characters: segment.units, length: segment.units.count) as String
            result.append(NSAttributedString(string: string, attributes: attributes))
        }
        if result.length > 0 {
            result.addAttribute(.stressCoverage, value: true, range: NSRange(location: 0, length: result.length))
        }
        return result
    }

    private static func style(_ paragraph: Paragraph) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        switch paragraph {
        case .left: style.alignment = .left
        case .center: style.alignment = .center
        case .right: style.alignment = .right
        case .justified: style.alignment = .justified
        case .rightToLeft: style.baseWritingDirection = .rightToLeft
        case let .indented(head, tail):
            style.headIndent = head
            style.firstLineHeadIndent = head / 2
            style.tailIndent = tail
        case let .spaced(line, paragraph):
            style.lineSpacing = line
            style.paragraphSpacing = paragraph
            style.paragraphSpacingBefore = paragraph / 2
        case let .heights(min, max):
            style.minimumLineHeight = min
            style.maximumLineHeight = max
        }
        return style
    }

    // MARK: Checking

    /// Runs every check on this input and returns what went wrong.
    @MainActor
    func problems() -> [String] {
        let text = build()
        let length = text.length
        var audit = LayoutAudit()
        let layout = TextLabel.Layout(attributedString: text)
        let context = makeStressContext(width: 16, height: 16)

        for width in widths {
            let fit = layout.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            audit.check(fit.isFiniteSize && fit.width >= 0 && fit.height >= 0, "sizeThatFits at width \(width) = \(fit)")
            let size = CGSize(width: width, height: height)
            audit.audit(
                layout,
                containerSize: size,
                samplePoints: points,
                ranges: ranges,
                context: context,
                visibleRect: CGRect(x: 0, y: 20, width: width, height: 50),
                drawsEverything: width == widths[0]
            )
            // Some text may lie outside a short container, but none is dropped.
            if length > 0 {
                audit.checkLinesCoverString(layout, key: .stressCoverage)
            }
            for range in ranges {
                for rect in layout.rects(for: range) {
                    audit.check(rect.isFiniteRect, "rects(for: \(range)) at width \(width) has \(rect)")
                }
            }
        }

        #if !os(watchOS)
            let label = TextLabelView(attributedText: text)
            label.isSelectable = true
            label.frame = CGRect(x: 0, y: 0, width: widths[0], height: max(height, 1))
            forceLayout(label)
            for range in ranges {
                label.selectionRange = range
                audit.checkSelection(label)
                _ = label.selectedAttributedText()
                for point in points.prefix(2) {
                    _ = label.selectionContains(point)
                }
            }
            for (pointIndex, point) in points.enumerated() {
                guard let index = label.characterIndexAtPoint(point) else { continue }
                audit.check(index >= 0 && index <= length, "characterIndexAtPoint(\(point)) = \(index)")
                // Word and line selection at every third point keeps an iteration near 5 ms.
                if pointIndex % 3 == 0 {
                    label.selectWordAtIndex(index)
                    audit.checkSelection(label)
                    label.selectLineAtIndex(index)
                    audit.checkSelection(label)
                }
            }
            for point in points {
                _ = label.hitTarget(at: point)
            }
            label.frame = CGRect(x: 0, y: 0, width: widths[1], height: max(height, 1))
            forceLayout(label)
            audit.checkSelection(label)
            label.clearSelection()
            audit.check(label.selectionLayer == nil, "selection layer left after clearSelection()")
        #endif
        return audit.problems
    }

    // MARK: Shrinking

    /// Removes everything that is not needed to keep `stillFails` true.
    @MainActor
    func shrunk(while stillFails: (FuzzCase) -> Bool) -> FuzzCase {
        var current = self
        var improved = true
        while improved {
            improved = false
            // Drop whole segments.
            var index = 0
            while index < current.segments.count {
                var candidate = current
                candidate.segments.remove(at: index)
                if stillFails(candidate) {
                    current = candidate
                    improved = true
                } else {
                    index += 1
                }
            }
            // Shorten each segment, then strip its attributes one by one.
            for index in current.segments.indices {
                while current.segments[index].units.count > 1 {
                    var candidate = current
                    candidate.segments[index].units.removeLast((candidate.segments[index].units.count + 1) / 2)
                    guard stillFails(candidate) else { break }
                    current = candidate
                    improved = true
                }
                let simplifications: [(inout Segment) -> Void] = [
                    { $0.link = nil },
                    { $0.attachment = nil },
                    { $0.paragraph = nil },
                    { $0.kern = nil },
                    { $0.baselineOffset = nil },
                    { $0.colorIndex = nil },
                    { $0.bold = false },
                ]
                for simplify in simplifications {
                    var candidate = current
                    simplify(&candidate.segments[index])
                    // Only a change that shows in the description counts, so the loop ends.
                    if candidate.description != current.description, stillFails(candidate) {
                        current = candidate
                        improved = true
                    }
                }
            }
            // Fewer ranges.
            var rangeIndex = 0
            while rangeIndex < current.ranges.count {
                var candidate = current
                candidate.ranges.remove(at: rangeIndex)
                if stillFails(candidate) {
                    current = candidate
                    improved = true
                } else {
                    rangeIndex += 1
                }
            }
        }
        return current
    }
}

#if !os(watchOS)
    extension LayoutAudit {
        mutating func checkSelection(_ label: TextLabelView) {
            let length = label.attributedText.length
            if let range = label.selectionRange {
                check(
                    range.location >= 0 && range.length > 0 && range.location + range.length <= length,
                    "selectionRange \(range) outside length \(length)"
                )
            } else {
                check(label.selectionLayer == nil, "selection layer without a selection")
            }
        }
    }
#endif

@MainActor
@Suite("Stress: fuzz", .tags(.stress))
struct StressFuzzTests {
    /// About 7.5 ms per iteration on an M4 Max: 15 s for the default 2,000. The
    /// budget allows 40 ms per iteration, and no single iteration may take 2 s.
    @Test func randomAttributedStrings() {
        let iterations = StressMode.fuzzIterations
        let base = StressMode.fuzzSeed
        var failures = 0
        withinBudget("fuzz, \(iterations) iterations", seconds: Double(iterations) * 0.04) {
            for iteration in 0 ..< iterations {
                let seed = base &+ UInt64(iteration)
                let fuzzCase = FuzzCase.generate(seed: seed)
                // A run loop drains autoreleased labels every turn; this loop has
                // to drain them itself, or every label stays registered for the
                // selection notification and each post reaches all of them.
                let clock = ContinuousClock()
                let start = clock.now
                var problems = autoreleasepool { fuzzCase.problems() }
                // One input is a few hundred characters; anything this slow is a blow-up.
                let elapsed = seconds(of: clock.now - start)
                if elapsed > 2 {
                    problems.append("one iteration took \(elapsed) s")
                }
                guard !problems.isEmpty else { continue }
                failures += 1
                let minimal = fuzzCase.shrunk { candidate in autoreleasepool { !candidate.problems().isEmpty } }
                Issue.record("""
                Fuzz failure with seed \(seed) (reproduce with LITEXT_FUZZ_SEED=\(seed) LITEXT_FUZZ_ITERATIONS=1).
                Problems: \(minimal.problems().prefix(5).joined(separator: "; "))
                Minimal input:
                \(minimal)
                """)
                if failures >= 5 {
                    break
                }
            }
        }
    }

    /// The shrinker keeps only what a failure needs: here, one character with a link.
    @Test func shrinkerFindsAMinimalInput() throws {
        let seed = try #require((0 ..< 500).map { StressMode.fuzzSeed &+ UInt64($0) }.first { seed in
            FuzzCase.generate(seed: seed).segments.filter { $0.link != nil }.count >= 2
        })
        let fuzzCase = FuzzCase.generate(seed: seed)
        let minimal = fuzzCase.shrunk { candidate in
            candidate.segments.contains { $0.link != nil }
        }
        #expect(minimal.segments.count == 1)
        #expect(minimal.segments.first?.units.count == 1)
        #expect(minimal.segments.first?.attachment == nil)
        #expect(minimal.ranges.isEmpty)
    }

    /// The fuzzer itself is deterministic: a seed always builds the same input.
    @Test func seedsReproduce() {
        for seed: UInt64 in [0, 1, 42, StressMode.fuzzSeed] {
            let first = FuzzCase.generate(seed: seed)
            let second = FuzzCase.generate(seed: seed)
            #expect(first.description == second.description)
            #expect(first.build().isEqual(to: second.build()) || first.build().string == second.build().string)
        }
    }
}
