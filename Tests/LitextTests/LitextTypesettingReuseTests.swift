//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//
//  A layout that reuses the lines of the previous string must lay the text out
//  exactly as one that typesets the whole string. These tests stream rich text
//  through both and compare them line by line.
//
//  Reproduce a fuzz failure with the seed it prints:
//  `LITEXT_FUZZ_SEED=<seed> LITEXT_FUZZ_ITERATIONS=1 swift test --filter TypesettingReuse`.
//

import CoreText
import Foundation
@testable import Litext
import Testing

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

@MainActor
@Suite("Typesetting reuse")
struct LitextTypesettingReuseTests {
    // MARK: - Text

    private struct Generator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 33
        }

        mutating func next(_ bound: Int) -> Int {
            Int(next() % UInt64(bound))
        }
    }

    private static let words = [
        "streaming", "text", "layout", "CoreText", "paragraph", "line", "glyph",
        "中文混排", "日本語の文章", "emoji 🎉", "👩‍👩‍👧", "a", "fine-grained", "tab\there",
    ]

    /// A paragraph of a random kind: body, heading, quote-like indented text,
    /// tight or loose line heights, an inline attachment or a link.
    private static func paragraph(_ generator: inout Generator, attachments: [TextLabel.Attachment]) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        var font = PlatformFont.systemFont(ofSize: 15)
        switch generator.next(6) {
        case 0:
            font = PlatformFont.boldSystemFont(ofSize: 24)
            style.paragraphSpacingBefore = 12
            style.paragraphSpacing = 6
        case 1:
            style.headIndent = 18
            style.firstLineHeadIndent = 18
            style.paragraphSpacing = 4
        case 2:
            style.lineHeightMultiple = 1.4
            style.paragraphSpacing = 10
        case 3:
            style.minimumLineHeight = 22
            style.maximumLineHeight = 22
        case 4:
            style.firstLineHeadIndent = 24
            style.lineSpacing = 3
        default:
            style.paragraphSpacing = 8
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style]
        let text = NSMutableAttributedString()
        for _ in 0 ..< 3 + generator.next(30) {
            let word = words[generator.next(words.count)] + " "
            switch generator.next(12) {
            case 0:
                var linked = attributes
                linked[.link] = URL(string: "https://example.com")!
                text.append(NSAttributedString(string: word, attributes: linked))
            case 1:
                var code = attributes
                code[.font] = PlatformFont.monospacedSystemFont(ofSize: 14, weight: .regular)
                text.append(NSAttributedString(string: word, attributes: code))
            case 2 where !attachments.isEmpty:
                let attachment = attachments[generator.next(attachments.count)]
                text.append(attachment.attributedString(attributes: attributes))
            default:
                text.append(NSAttributedString(string: word, attributes: attributes))
            }
        }
        let separators = ["\n", "\n", "\n", "\r\n", "\u{2029}"]
        text.append(NSAttributedString(string: separators[generator.next(separators.count)], attributes: attributes))
        return text
    }

    // MARK: - Comparison

    /// Measures and lays out `layout` the way `TextLabelView` does.
    private static func layOut(_ layout: TextLabel.Layout, width: CGFloat) {
        let size = layout.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        layout.containerSize = CGSize(width: width, height: ceil(size.height))
        layout.updateHighlightRegions()
    }

    /// Records every difference between two layouts of the same string.
    @discardableResult
    private static func expectSameLayout(
        _ reused: TextLabel.Layout,
        _ fresh: TextLabel.Layout,
        width: CGFloat,
        context: String,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) -> Bool {
        let probe = CGSize(width: width, height: .greatestFiniteMagnitude)
        let reusedSize = reused.sizeThatFits(probe)
        let freshSize = fresh.sizeThatFits(probe)
        guard reusedSize == freshSize else {
            Issue.record("size \(reusedSize) vs \(freshSize) — \(context)", sourceLocation: sourceLocation)
            return false
        }
        let reusedLines = reused.layoutLines
        let freshLines = fresh.layoutLines
        guard reusedLines.count == freshLines.count else {
            Issue.record("\(reusedLines.count) lines vs \(freshLines.count) — \(context)", sourceLocation: sourceLocation)
            return false
        }
        for (lhs, rhs) in zip(reusedLines, freshLines) {
            let originMatches = abs(lhs.baselineOrigin.x - rhs.baselineOrigin.x) < 1e-6
                && abs(lhs.baselineOrigin.y - rhs.baselineOrigin.y) < 1e-6
            let rectMatches = abs(lhs.rect.minY - rhs.rect.minY) < 1e-6
                && abs(lhs.rect.height - rhs.rect.height) < 1e-6
                && abs(lhs.rect.width - rhs.rect.width) < 1e-6
            guard lhs.stringRange == rhs.stringRange, originMatches, rectMatches else {
                Issue.record(
                    "line \(lhs.index): \(lhs.stringRange) at \(lhs.baselineOrigin) \(lhs.rect) vs \(rhs.stringRange) at \(rhs.baselineOrigin) \(rhs.rect) — \(context)",
                    sourceLocation: sourceLocation,
                )
                return false
            }
        }
        let reusedRegions = reused.highlightRegions.map(\.stringRange).sorted { $0.location < $1.location }
        let freshRegions = fresh.highlightRegions.map(\.stringRange).sorted { $0.location < $1.location }
        guard reusedRegions == freshRegions else {
            Issue.record("highlight regions differ — \(context)", sourceLocation: sourceLocation)
            return false
        }
        return true
    }

    private static func environmentInt(_ key: String) -> Int? {
        ProcessInfo.processInfo.environment[key].flatMap(Int.init)
    }

    // MARK: - Streaming

    @Test
    func `streamed text lays out like text typeset whole`() {
        let seeds = Self.environmentInt("LITEXT_FUZZ_SEED").map { [UInt64($0)] } ?? (1 ... 6).map(UInt64.init)
        let iterations = Self.environmentInt("LITEXT_FUZZ_ITERATIONS") ?? 1
        var reusedLines = 0
        for seed in seeds {
            for iteration in 0 ..< iterations {
                var generator = Generator(state: seed &+ UInt64(iteration) &* 7919)
                let attachments = [
                    TextLabel.Attachment(size: CGSize(width: 18, height: 18), view: nil),
                    TextLabel.Attachment(size: CGSize(width: 240, height: 64), view: nil),
                ]
                let document = NSMutableAttributedString()
                for _ in 0 ..< 24 {
                    document.append(Self.paragraph(&generator, attachments: attachments))
                }
                let width = CGFloat([180, 320, 375.5, 600][generator.next(4)])
                var previous: TextLabel.Layout?
                var cut = 0
                while cut < document.length {
                    cut = min(document.length, cut + 1 + generator.next(60))
                    let prefix = document.attributedSubstring(from: NSRange(location: 0, length: cut))
                    let reused = TextLabel.Layout(attributedString: prefix)
                    if let previous {
                        reused.reuseTypesetting(from: previous)
                    }
                    Self.layOut(reused, width: width)
                    reusedLines += reused.reusedLineCount
                    let fresh = TextLabel.Layout(attributedString: prefix)
                    Self.layOut(fresh, width: width)
                    let context = "seed \(seed) iteration \(iteration) width \(width) length \(cut)"
                    guard Self.expectSameLayout(reused, fresh, width: width, context: context) else { return }
                    previous = reused
                }
            }
        }
        // Without this the comparison could pass by never reusing anything.
        #expect(reusedLines > 0)
    }

    @Test
    func `a label streaming text reuses the lines before the change`() {
        let label = TextLabelView()
        label.frame = CGRect(x: 0, y: 0, width: 320, height: 2000)
        var text = ""
        var updatesReusingLines = 0
        for index in 0 ..< 40 {
            text += "Paragraph \(index) streams onto the end of the label, one piece after another.\n"
            label.attributedText = NSAttributedString(string: text, attributes: [.font: PlatformFont.systemFont(ofSize: 15)])
            _ = label.intrinsicContentSize
            label.layoutNow()
            if label.textLayout.reusedLineCount > 0 {
                updatesReusingLines += 1
            }
        }
        // Every few updates typeset the whole string again, to let go of earlier strings.
        #expect(updatesReusingLines > 20)
        let fresh = TextLabel.Layout(attributedString: label.attributedText)
        fresh.containerSize = label.textLayout.containerSize
        #expect(fresh.layoutLines.map(\.stringRange) == label.textLayout.layoutLines.map(\.stringRange))
    }

    // MARK: - When the lines cannot be reused

    @Test
    func `an edit before the end typesets again from the paragraph before it`() {
        let attributes: [NSAttributedString.Key: Any] = [.font: PlatformFont.systemFont(ofSize: 15)]
        let paragraphs = (0 ..< 12).map { "Paragraph \($0) with enough words to wrap at a narrow width.\n" }
        let original = NSAttributedString(string: paragraphs.joined(), attributes: attributes)
        var edited = paragraphs
        edited[6] = "An edited paragraph in the middle.\n"
        let editedString = NSAttributedString(string: edited.joined(), attributes: attributes)

        let previous = TextLabel.Layout(attributedString: original)
        Self.layOut(previous, width: 200)
        let reused = TextLabel.Layout(attributedString: editedString)
        reused.reuseTypesetting(from: previous)
        Self.layOut(reused, width: 200)
        let fresh = TextLabel.Layout(attributedString: editedString)
        Self.layOut(fresh, width: 200)
        #expect(reused.reusedLineCount > 0)
        Self.expectSameLayout(reused, fresh, width: 200, context: "middle edit")
    }

    @Test
    func `restyled text before the change is typeset again`() {
        let text = (0 ..< 8).map { "Paragraph \($0) with some words.\n" }.joined()
        let plain = NSAttributedString(string: text, attributes: [.font: PlatformFont.systemFont(ofSize: 15)])
        let restyled = NSMutableAttributedString(attributedString: plain)
        restyled.addAttribute(.font, value: PlatformFont.boldSystemFont(ofSize: 20), range: NSRange(location: 0, length: 9))
        restyled.append(NSAttributedString(string: "More.", attributes: [.font: PlatformFont.systemFont(ofSize: 15)]))

        let previous = TextLabel.Layout(attributedString: plain)
        Self.layOut(previous, width: 200)
        let reused = TextLabel.Layout(attributedString: restyled)
        reused.reuseTypesetting(from: previous)
        Self.layOut(reused, width: 200)
        let fresh = TextLabel.Layout(attributedString: restyled)
        Self.layOut(fresh, width: 200)
        #expect(reused.reusedLineCount == 0)
        Self.expectSameLayout(reused, fresh, width: 200, context: "restyled prefix")
    }

    @Test
    func `an attachment that changed size before the change is typeset again`() {
        let attachment = TextLabel.Attachment(size: CGSize(width: 40, height: 20), view: nil)
        let attributes: [NSAttributedString.Key: Any] = [.font: PlatformFont.systemFont(ofSize: 15)]
        let text = NSMutableAttributedString(string: "Before.\n", attributes: attributes)
        text.append(attachment.attributedString(attributes: attributes))
        text.append(NSAttributedString(string: "\nAfter the attachment.\nTail paragraph.\n", attributes: attributes))

        let previous = TextLabel.Layout(attributedString: text)
        Self.layOut(previous, width: 200)
        attachment.size = CGSize(width: 40, height: 80)
        let longer = NSMutableAttributedString(attributedString: text)
        longer.append(NSAttributedString(string: "More.", attributes: attributes))
        let reused = TextLabel.Layout(attributedString: longer)
        reused.reuseTypesetting(from: previous)
        Self.layOut(reused, width: 200)
        let fresh = TextLabel.Layout(attributedString: longer)
        Self.layOut(fresh, width: 200)
        Self.expectSameLayout(reused, fresh, width: 200, context: "resized attachment")
    }

    @Test
    func `a layout at another width typesets the whole string`() {
        let attributes: [NSAttributedString.Key: Any] = [.font: PlatformFont.systemFont(ofSize: 15)]
        let text = (0 ..< 8).map { "Paragraph \($0) with some words to wrap.\n" }.joined()
        let previous = TextLabel.Layout(attributedString: NSAttributedString(string: text, attributes: attributes))
        Self.layOut(previous, width: 200)
        let longer = NSAttributedString(string: text + "More.", attributes: attributes)
        let reused = TextLabel.Layout(attributedString: longer)
        reused.reuseTypesetting(from: previous)
        Self.layOut(reused, width: 260)
        #expect(reused.reusedLineCount == 0)
        let fresh = TextLabel.Layout(attributedString: longer)
        Self.layOut(fresh, width: 260)
        Self.expectSameLayout(reused, fresh, width: 260, context: "other width")
    }

    // MARK: - Memory

    @Test
    func `the lines never keep much more text alive than they show`() {
        let attributes: [NSAttributedString.Key: Any] = [.font: PlatformFont.systemFont(ofSize: 15)]
        var text = ""
        var previous: TextLabel.Layout?
        for index in 0 ..< 300 {
            text += "Paragraph \(index) streams in.\n"
            let layout = TextLabel.Layout(attributedString: NSAttributedString(string: text, attributes: attributes))
            if let previous {
                layout.reuseTypesetting(from: previous)
            }
            Self.layOut(layout, width: 300)
            let length = (text as NSString).length
            #expect(layout.retainedTextLength <= 4 * length)
            previous = layout
        }
    }
}

private extension TextLabelView {
    func layoutNow() {
        #if canImport(UIKit)
            setNeedsLayout()
            layoutIfNeeded()
        #elseif canImport(AppKit)
            needsLayout = true
            layoutSubtreeIfNeeded()
        #endif
    }
}
