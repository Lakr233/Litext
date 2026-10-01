//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//
//  Stress: huge inputs. See StressSupport.swift for the quick and
//  LITEXT_STRESS=full sizes and for how the time budgets were chosen.
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

struct HugeInput: CustomTestStringConvertible, Sendable {
    let name: String
    /// Builds the string at the quick or the full size.
    let make: @MainActor @Sendable (_ full: Bool) -> NSAttributedString
    /// Budget for each typesetting step (measure, lay out), quick and full.
    let typesetBudget: (standard: Double, full: Double)
    /// Budget for each query step (draw, rects, index lookups, selection).
    let queryBudget: (standard: Double, full: Double)

    var testDescription: String {
        name
    }

    @MainActor
    static var font: PlatformFont {
        PlatformFont.systemFont(ofSize: 14)
    }

    static let all: [HugeInput] = [
        // 100k lines: about 1.8e6 points tall, past the old 1e6 layout cap.
        // M4 Max, full: measure 0.4 s, lay out 0.6 s, 210 index lookups 2.7 s
        // (each scans the lines linearly).
        HugeInput(
            name: "100k lines",
            make: { full in
                let count = full ? 100_000 : 20000
                let string = (0 ..< count).map { "Line \($0) of the document" }.joined(separator: "\n")
                return NSAttributedString(string: string, attributes: [.font: font])
            },
            typesetBudget: (2, 5),
            queryBudget: (3, 15)
        ),
        // One paragraph with no newline: 1 MB full, 50 KB default. CoreText's
        // line breaking is quadratic in paragraph length (see
        // `longParagraphCostMatchesCoreText`): the full size takes about 90 s to
        // measure on an M4 Max, all of it inside CTFramesetter. Default: 0.25 s.
        HugeInput(
            name: "1 MB paragraph",
            make: { full in
                let target = full ? 1_000_000 : 50000
                let words = ["lorem", "ipsum", "dolor", "sit", "amet,", "consectetur", "adipiscing", "elit"]
                var string = ""
                string.reserveCapacity(target + 16)
                var index = 0
                while string.utf16.count < target {
                    string += words[index % words.count]
                    string += " "
                    index += 1
                }
                return NSAttributedString(string: string, attributes: [.font: font])
            },
            typesetBudget: (3, 600),
            queryBudget: (2, 5)
        ),
        // A token CoreText can only break character by character. Full: 0.2 s.
        HugeInput(
            name: "50k-character token",
            make: { full in
                let string = String(repeating: "x", count: full ? 50000 : 10000)
                return NSAttributedString(string: string, attributes: [.font: font])
            },
            typesetBudget: (2, 3),
            queryBudget: (2, 3)
        ),
        // Separate links, each its own highlight region.
        HugeInput(
            name: "10k links",
            make: { full in
                let result = NSMutableAttributedString()
                for index in 0 ..< (full ? 10000 : 2000) {
                    result.append(NSAttributedString(string: "see ", attributes: [.font: font]))
                    result.append(NSAttributedString(string: "link \(index)", attributes: [
                        .font: font,
                        .link: URL(string: "https://example.com/\(index)")!,
                    ]))
                    result.append(NSAttributedString(string: index % 7 == 0 ? "\n" : " ", attributes: [.font: font]))
                }
                return result
            },
            typesetBudget: (2, 4),
            queryBudget: (2, 4)
        ),
        // Attachments, every tenth one with a view.
        HugeInput(
            name: "2k attachments",
            make: { full in
                let result = NSMutableAttributedString()
                for index in 0 ..< (full ? 2000 : 500) {
                    let attachment = TextLabel.Attachment(
                        size: CGSize(width: CGFloat(8 + index % 20), height: CGFloat(8 + index % 30))
                    )
                    #if !os(watchOS)
                        if index % 10 == 0 {
                            attachment.view = PlatformView(frame: .zero)
                        }
                    #endif
                    result.append(attachment.attributedString(attributes: [.font: font]))
                    result.append(NSAttributedString(string: " a ", attributes: [.font: font]))
                }
                return result
            },
            typesetBudget: (2, 4),
            queryBudget: (2, 4)
        ),
        // A new font and colour on every character.
        HugeInput(
            name: "per-character attributes",
            make: { full in
                mixedAttributeString(length: full ? 50000 : 10000, link: nil)
            },
            typesetBudget: (2, 4),
            queryBudget: (2, 4)
        ),
        // The same, all inside one link: one CoreText run, and once one highlight
        // lookup, per character. This was quadratic (15 s at 20k characters).
        HugeInput(
            name: "per-character attributes inside one link",
            make: { full in
                mixedAttributeString(length: full ? 50000 : 10000, link: URL(string: "https://example.com")!)
            },
            typesetBudget: (2, 4),
            queryBudget: (2, 4)
        ),
    ]

    @MainActor
    static func mixedAttributeString(length: Int, link: URL?) -> NSAttributedString {
        let alphabet = Array("abcdefghij klmnopqrstuvwxyz ABCDEFGHIJ 0123456789")
        let colors: [PlatformColor] = [.red, .green, .blue, .orange, .purple, .brown, .gray]
        let result = NSMutableAttributedString()
        result.beginEditing()
        for index in 0 ..< length {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: index % 2 == 0
                    ? PlatformFont.systemFont(ofSize: CGFloat(10 + index % 9))
                    : PlatformFont.boldSystemFont(ofSize: CGFloat(10 + index % 11)),
                .foregroundColor: colors[index % colors.count],
            ]
            if let link {
                attributes[.link] = link
            }
            result.append(NSAttributedString(string: String(alphabet[index % alphabet.count]), attributes: attributes))
        }
        result.endEditing()
        return result
    }
}

@MainActor
@Suite("Stress: huge inputs", .tags(.stress), StressMode.enabled, .serialized)
struct StressHugeInputTests {
    @Test(arguments: HugeInput.all)
    func hugeInputStaysBounded(_ input: HugeInput) {
        let full = StressMode.isFull
        let typesetBudget = full ? input.typesetBudget.full : input.typesetBudget.standard
        let queryBudget = full ? input.queryBudget.full : input.queryBudget.standard
        let name = input.name

        let string = input.make(full)
        let length = string.length
        let width: CGFloat = 320

        let layout = withinBudget("\(name): init", seconds: typesetBudget) {
            TextLabel.Layout(attributedString: string)
        }
        let fit = withinBudget("\(name): sizeThatFits", seconds: typesetBudget) {
            layout.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        }
        #expect(fit.isFiniteSize && fit.height > 0)

        let containerSize = CGSize(width: width, height: fit.height)
        withinBudget("\(name): lay out", seconds: typesetBudget) {
            layout.containerSize = containerSize
        }
        withinBudget("\(name): highlight regions", seconds: queryBudget) {
            layout.updateHighlightRegions()
        }

        // Every character is laid out: the last one has a rect.
        let lastRects = layout.rects(for: NSRange(location: length - 1, length: 1))
        #expect(!lastRects.isEmpty, "\(name): the last character was not laid out")

        let context = makeStressContext(width: Int(width), height: 400)
        withinBudget("\(name): draw visible rects", seconds: queryBudget) {
            for fraction in [0.0, 0.5, 0.97] {
                let visibleRect = CGRect(x: 0, y: fit.height * fraction, width: width, height: 400)
                layout.draw(in: context, visibleRect: visibleRect)
            }
        }

        let rects = withinBudget("\(name): rects(for: full range)", seconds: queryBudget) {
            layout.rects(for: NSRange(location: 0, length: length))
        }
        #expect(!rects.isEmpty)
        let rectsAreFinite = rects.allSatisfy(\.isFiniteRect)
        #expect(rectsAreFinite)

        let points = samplePoints(in: containerSize, count: 64)
        withinBudget("\(name): index lookups at \(points.count) points", seconds: queryBudget) {
            for point in points {
                for index in [
                    layout.textIndex(at: point),
                    layout.nearestTextIndex(at: point),
                    layout.characterIndex(at: point),
                ] {
                    if let index {
                        #expect(index >= 0 && index <= length)
                    }
                }
            }
        }

        if input.name.contains("link") {
            #expect(!layout.highlightRegions.isEmpty)
        }
        #expect(layout.highlightRegions.allSatisfy { NSMaxRange($0.stringRange) <= length })

        #if !os(watchOS)
            let label = TextLabelView(attributedText: string)
            label.isSelectable = true
            withinBudget("\(name): view layout", seconds: typesetBudget) {
                label.frame = CGRect(origin: .zero, size: CGSize(width: width, height: fit.height))
                forceLayout(label)
            }
            withinBudget("\(name): select all", seconds: queryBudget) {
                label.selectAll()
            }
            #expect(label.selectionRange == NSRange(location: 0, length: length))
            withinBudget("\(name): select word and line", seconds: queryBudget) {
                for fraction in [0.0, 0.5, 0.99] {
                    let index = min(length - 1, Int(Double(length) * fraction))
                    label.selectWordAtIndex(index)
                    label.selectLineAtIndex(index)
                }
            }
            label.clearSelection()
            #expect(label.selectionLayer == nil)
            if let region = label.highlightRegions.first(where: { $0.kind == .link }) {
                // A link styled per character has a rect per character.
                withinBudget("\(name): press a link", seconds: queryBudget) {
                    label.addActiveHighlightRegion(region)
                }
                label.deactivateHighlightRegion()
            }
        #endif
    }

    /// CoreText's line breaking is quadratic in the length of a paragraph:
    /// on an M4 Max, raw `CTTypesetterSuggestLineBreak` over 62.5k, 125k and
    /// 250k characters takes 0.37, 1.45 and 5.8 s. Litext cannot change that,
    /// but it must not add to it: its measurement stays within 1.5x of
    /// CoreText's own `CTFramesetterSuggestFrameSizeWithConstraints`.
    @Test func longParagraphCostMatchesCoreText() {
        let font = PlatformFont.systemFont(ofSize: 14)
        let length = StressMode.pick(30000, full: 120_000)
        var string = ""
        while string.utf16.count < length {
            string += "lorem ipsum dolor sit amet "
        }
        let attributed = NSAttributedString(string: string, attributes: [.font: font])
        let constraint = CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        let clock = ContinuousClock()

        let coreTextStart = clock.now
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(), nil, constraint, nil)
        let coreText = seconds(of: clock.now - coreTextStart)

        let litextStart = clock.now
        let layout = TextLabel.Layout(attributedString: attributed)
        let fit = layout.sizeThatFits(constraint)
        layout.containerSize = CGSize(width: 320, height: fit.height)
        let litext = seconds(of: clock.now - litextStart)

        print("[stress] \(length)-character paragraph: CoreText \(coreText) s, Litext measure + lay out \(litext) s")
        #expect(abs(fit.height - suggested.height) <= 1)
        #expect(litext <= coreText * 1.5 + 0.05)
    }

    /// Highlight extraction over a link styled character by character, at n,
    /// 2n and 4n characters. Linear work grows 4x from n to 4n. The quadratic
    /// version measured 0.99, 3.7 and 15.3 s for 5k, 10k and 20k characters
    /// (15x); it now takes about 10, 20 and 38 ms.
    @Test func highlightExtractionScalesLinearly() throws {
        let base = StressMode.pick(5000, full: 20000)
        var timings = [Double]()
        for length in [base, base * 2, base * 4] {
            let string = try HugeInput.mixedAttributeString(length: length, link: #require(URL(string: "https://example.com")))
            let layout = TextLabel.Layout(attributedString: string)
            layout.containerSize = CGSize(width: 320, height: 100)
            let clock = ContinuousClock()
            let start = clock.now
            layout.updateHighlightRegions()
            timings.append(seconds(of: clock.now - start))
            #expect(layout.highlightRegions.count == 1)
            #expect(layout.highlightRegions.first?.stringRange == NSRange(location: 0, length: length))
        }
        print("[stress] highlight extraction at \(base), \(base * 2), \(base * 4) characters: \(timings) s")
        #expect(timings[2] <= timings[0] * 10 + 0.05, "4x the characters took \(timings[2] / timings[0])x as long")
    }

    /// Text more than a million points tall is laid out to the end. The final
    /// layout used to stop at 1e6 points, so 100k lines laid out only 55,555 and
    /// the rest, with its links, was never drawn or hit-testable.
    @Test func textTallerThanAMillionPointsIsLaidOutInFull() throws {
        let font = PlatformFont.systemFont(ofSize: 400)
        let count = 3000
        let text = NSMutableAttributedString(
            string: (0 ..< count).map { "L\($0)" }.joined(separator: "\n"),
            attributes: [.font: font]
        )
        try text.addAttribute(.link, value: #require(URL(string: "https://example.com/last")), range: NSRange(location: text.length - 2, length: 2))
        let layout = withinBudget("layout taller than 1e6 points", seconds: 1) {
            let layout = TextLabel.Layout(attributedString: text)
            let fit = layout.sizeThatFits(CGSize(width: 2000, height: CGFloat.greatestFiniteMagnitude))
            layout.containerSize = CGSize(width: 2000, height: fit.height)
            layout.updateHighlightRegions()
            return layout
        }
        #expect(layout.containerSize.height > 1_000_000)
        #expect(layout.visibleLineCount(in: nil) == count)
        #expect(!layout.rects(for: NSRange(location: text.length - 1, length: 1)).isEmpty)
        #expect(layout.highlightRegions.count == 1)
    }

    /// Laying out n, 2n and 4n lines stays linear.
    @Test func lineCountScalesLinearly() {
        // 4n lines stay under 1e6 points. Past that, the 1e6-point measurement
        // frame comes back incomplete and the text is typeset about three times
        // (25k, 50k, 100k lines: 0.07, 0.14, 0.94 s), a step, not a curve.
        let base = StressMode.pick(5000, full: 12000)
        let font = PlatformFont.systemFont(ofSize: 14)
        var timings = [Double]()
        for count in [base, base * 2, base * 4] {
            let string = NSAttributedString(
                string: (0 ..< count).map { "Line \($0)" }.joined(separator: "\n"),
                attributes: [.font: font]
            )
            let clock = ContinuousClock()
            let start = clock.now
            let layout = TextLabel.Layout(attributedString: string)
            let fit = layout.sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
            layout.containerSize = CGSize(width: 320, height: fit.height)
            _ = layout.rects(for: NSRange(location: 0, length: string.length))
            timings.append(seconds(of: clock.now - start))
            #expect(layout.visibleLineCount(in: nil) == count)
        }
        print("[stress] layout of \(base), \(base * 2), \(base * 4) lines: \(timings) s")
        #expect(timings[2] <= timings[0] * 10 + 0.05, "4x the lines took \(timings[2] / timings[0])x as long")
    }
}

#if !os(watchOS)
    @MainActor
    func forceLayout(_ view: PlatformView) {
        #if canImport(UIKit)
            view.setNeedsLayout()
            view.layoutIfNeeded()
        #elseif canImport(AppKit)
            view.layoutSubtreeIfNeeded()
            view.layout()
        #endif
    }
#endif
