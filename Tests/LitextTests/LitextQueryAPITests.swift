//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Litext
import Testing

/// Covers the sizing, hit testing, line and attachment APIs from outside the
/// module, so each test also proves the API it uses is public.
@MainActor
@Suite("Query API")
struct LitextQueryAPITests {
    private static let font = PlatformFont.systemFont(ofSize: 16)

    private static func layoutLine(of layout: TextLabel.Layout, containing index: Int) throws -> TextLabel.LayoutLine {
        try #require(layout.layoutLines.first { NSLocationInRange(index, $0.stringRange) })
    }

    @Test
    func `a layout has no lines before it gets a container`() {
        let layout = TextLabel.Layout(attributedString: NSAttributedString(string: "Text"))
        #expect(layout.layoutLines.isEmpty)
    }

    @Test
    func `layout lines cover the text from top to bottom`() {
        let layout = TextLabel.Layout(attributedString: NSAttributedString(
            string: "One\nTwo\nThree",
            attributes: [.font: Self.font],
        ))
        layout.containerSize = CGSize(width: 300, height: 200)

        let lines = layout.layoutLines
        #expect(lines.map(\.index) == [0, 1, 2])
        #expect(lines.map(\.stringRange) == [
            NSRange(location: 0, length: 4),
            NSRange(location: 4, length: 4),
            NSRange(location: 8, length: 5),
        ])
        #expect(lines.count == layout.visibleLineCount(in: nil))
        for line in lines {
            #expect(line.rect.minY < line.baselineOrigin.y)
            #expect(line.baselineOrigin.y < line.rect.maxY)
        }
        for (upper, lower) in zip(lines, lines.dropFirst()) {
            #expect(upper.baselineOrigin.y > lower.baselineOrigin.y)
            #expect(upper.rect.midY > lower.rect.midY)
        }
    }

    @Test
    func `a layout line hands out the line it typeset`() {
        let layout = TextLabel.Layout(attributedString: NSAttributedString(
            string: "One\nTwo",
            attributes: [.font: Self.font],
        ))
        layout.containerSize = CGSize(width: 300, height: 200)

        let lines = layout.layoutLines
        #expect(lines.count == 2)
        for line in lines {
            let range = CTLineGetStringRange(line.line)
            #expect(NSRange(location: range.location, length: range.length) == line.stringRange)
        }
        // Reading the lines again hands out the same typeset lines, not new ones.
        #expect(zip(lines, layout.layoutLines).allSatisfy { $0.line === $1.line })
    }

    @Test
    func `an attachment's descent places it against the baseline`() throws {
        let attachment = TextLabel.Attachment(size: CGSize(width: 20, height: 20))
        let text = NSMutableAttributedString(string: "A", attributes: [.font: Self.font])
        text.append(attachment.attributedString(attributes: [.font: Self.font]))
        let layout = TextLabel.Layout(attributedString: text)
        layout.containerSize = CGSize(width: 200, height: 100)

        func attachmentDescent() throws -> CGFloat {
            let run = try #require(layout.layoutRuns(matching: .litextAttachment).first)
            #expect(abs(run.rect.height - 20) < 0.001)
            let baseline = try Self.layoutLine(of: layout, containing: 1).baselineOrigin.y
            return baseline - run.rect.minY
        }

        #expect(attachment.descent == nil)
        #expect(try abs(attachmentDescent() - 2) < 0.001)

        attachment.descent = 0
        layout.invalidateLayout()
        #expect(try abs(attachmentDescent()) < 0.001)

        attachment.descent = 5
        layout.invalidateLayout()
        #expect(try abs(attachmentDescent() - 5) < 0.001)

        attachment.descent = 50
        layout.invalidateLayout()
        #expect(try abs(attachmentDescent() - 20) < 0.001)

        attachment.descent = -3
        layout.invalidateLayout()
        #expect(try abs(attachmentDescent()) < 0.001)

        attachment.descent = .nan
        layout.invalidateLayout()
        #expect(try abs(attachmentDescent() - 2) < 0.001)
    }

    @Test
    func `the layout's character index matches its rects`() throws {
        let layout = TextLabel.Layout(attributedString: NSAttributedString(
            string: "Hello world",
            attributes: [.font: Self.font],
        ))
        layout.containerSize = CGSize(width: 300, height: 40)
        let rect = try #require(layout.rects(for: NSRange(location: 7, length: 1)).first)
        #expect(layout.characterIndex(at: CGPoint(x: rect.midX, y: rect.midY)) == 7)
        #expect(TextLabel.Layout(attributedString: NSAttributedString()).characterIndex(at: .zero) == nil)
    }
}

#if !os(watchOS)
    @MainActor
    private final class ProbeLayout: TextLabel.Layout {}

    @MainActor
    private final class ProbeLayoutLabel: TextLabelView {
        override func makeTextLayout(_ attributedText: NSAttributedString) -> TextLabel.Layout {
            ProbeLayout(attributedString: attributedText)
        }
    }

    @MainActor
    @Suite("Query API on the view")
    struct LitextViewQueryAPITests {
        private static let font = PlatformFont.systemFont(ofSize: 16)

        private static func layOut(_ label: TextLabelView) {
            #if canImport(UIKit)
                label.layoutIfNeeded()
            #elseif canImport(AppKit)
                label.layoutSubtreeIfNeeded()
            #endif
        }

        private static func makeLinkLabel() throws -> TextLabelView {
            let url = try #require(URL(string: "https://example.com/query"))
            let text = NSMutableAttributedString(string: "Tap here now", attributes: [.font: font])
            text.addAttribute(.link, value: url, range: NSRange(location: 4, length: 4))
            let label = TextLabelView(attributedText: text)
            label.frame = CGRect(x: 0, y: 0, width: 300, height: 40)
            layOut(label)
            return label
        }

        private static func viewCenter(of range: NSRange, in label: TextLabelView) throws -> CGPoint {
            let rect = try #require(label.textLayout.rects(for: range).first)
            let viewRect = label.viewRect(fromLayoutRect: rect)
            return CGPoint(x: viewRect.midX, y: viewRect.midY)
        }

        @Test
        func `size that fits measures the text like the intrinsic size`() {
            let label = TextLabelView(attributedText: NSAttributedString(
                string: "A sentence long enough to wrap onto several lines",
                attributes: [.font: Self.font],
            ))

            let wrapped = label.sizeThatFits(CGSize(width: 80, height: 0))
            let unwrapped = label.sizeThatFits(.zero)
            #expect(wrapped.width <= 80)
            #expect(wrapped.height > unwrapped.height)
            #expect(unwrapped.width > 80)
            // The proposed height never limits the text, as with UILabel.
            #expect(label.sizeThatFits(CGSize(width: 80, height: 1)) == wrapped)
            #expect(label.sizeThatFits(CGSize(width: CGFloat.nan, height: 10)) == unwrapped)
            #expect(label.sizeThatFits(CGSize(width: -5, height: 10)) == unwrapped)

            label.preferredMaxLayoutWidth = 80
            #expect(label.intrinsicContentSize == wrapped)

            #if canImport(UIKit)
                label.frame = CGRect(x: 0, y: 0, width: 80, height: 1)
                label.sizeToFit()
                #expect(label.bounds.size == wrapped)
            #endif
        }

        @Test
        func `the view's layout is readable and comes from make text layout`() {
            let text = NSAttributedString(string: "Probe", attributes: [.font: Self.font])
            let label = ProbeLayoutLabel(attributedText: text)
            label.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
            Self.layOut(label)

            #expect(label.textLayout is ProbeLayout)
            #expect(label.textLayout.attributedString.isEqual(to: text))
            #expect(!label.textLayout.rects(for: NSRange(location: 0, length: 5)).isEmpty)
            #expect(label.layoutLines.count == 1)
            #expect(label.layoutLines.first?.stringRange == NSRange(location: 0, length: 5))
        }

        @Test
        func `highlight region at a point finds the link under it`() throws {
            let label = try Self.makeLinkLabel()

            let region = try #require(label.highlightRegion(at: Self.viewCenter(
                of: NSRange(location: 5, length: 1),
                in: label,
            )))
            #expect(region.kind == .link)
            #expect(region.stringRange == NSRange(location: 4, length: 4))
            #expect(region.linkURL?.absoluteString == "https://example.com/query")

            #expect(try label.highlightRegion(at: Self.viewCenter(
                of: NSRange(location: 0, length: 1),
                in: label,
            )) == nil)
            #expect(label.highlightRegion(at: CGPoint(x: -100, y: -100)) == nil)
        }

        @Test
        func `character index at a point finds the character under it`() throws {
            let label = try Self.makeLinkLabel()
            for index in [0, 5, 9, 11] {
                let point = try Self.viewCenter(of: NSRange(location: index, length: 1), in: label)
                #expect(label.characterIndex(at: point) == index)
            }
        }

        @Test
        func `select word and select line select like multiple clicks`() {
            let label = TextLabelView(attributedText: NSAttributedString(
                string: "Hello brave world\nSecond line",
                attributes: [.font: Self.font],
            ))

            label.selectWord(at: 7)
            #expect(label.selectionRange == nil)

            label.isSelectable = true
            label.selectWord(at: 7)
            #expect(label.selectionRange == NSRange(location: 6, length: 5))

            label.selectLine(at: 2)
            #expect(label.selectionRange == NSRange(location: 0, length: 17))

            label.selectLine(at: 20)
            #expect(label.selectionRange == NSRange(location: 18, length: 11))

            label.selectWord(at: 5)
            #expect(label.selectionRange == NSRange(location: 18, length: 11))

            label.selectWord(at: 1000)
            #expect(label.selectionRange == NSRange(location: 18, length: 11))
        }

        @Test
        func `link highlight settings start at their defaults`() {
            let label = TextLabelView()
            #expect(label.linkHighlightColor == nil)
            #expect(label.linkHighlightCornerRadius == 4)
            label.linkHighlightColor = .red
            label.linkHighlightCornerRadius = 0
            #expect(label.linkHighlightColor == .red)
            #expect(label.linkHighlightCornerRadius == 0)
        }
    }
#endif
