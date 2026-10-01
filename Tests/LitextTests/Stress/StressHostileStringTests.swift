//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//
//  Stress: hostile strings. See StressSupport.swift for the quick and
//  LITEXT_STRESS=full modes; the full mode repeats the long clusters more.
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

struct HostileString: CustomTestStringConvertible, Sendable {
    let name: String
    let units: [UInt16]

    var testDescription: String {
        name
    }

    init(_ name: String, units: [UInt16]) {
        self.name = name
        self.units = units
    }

    init(_ name: String, _ string: String) {
        self.init(name, units: Array(string.utf16))
    }

    var nsString: NSString {
        NSString(characters: units, length: units.count)
    }

    static var all: [HostileString] {
        let repeats = StressMode.pick(1, full: 5)
        let combining = (0 ..< 3000 * repeats).map { UInt16(0x0300 + $0 % 0x70) }
        let zwjFamily = Array(repeating: "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}", count: 300 * repeats)
            .joined()
        let separators: [UInt16] = [0x0A, 0x0D, 0x0D, 0x0A, 0x0B, 0x0C, 0x85, 0x2028, 0x2029, 0x1C, 0x1D, 0x1E]
        return [
            HostileString("lone high surrogate", units: Array("start ".utf16) + [0xD83D] + Array(" end".utf16)),
            HostileString("lone low surrogate", units: Array("start ".utf16) + [0xDE00] + Array(" end".utf16)),
            HostileString("reversed surrogate pair", units: [0xDE00, 0xD83D, 0x41, 0xDBFF, 0xDBFF, 0xDFFF, 0xDC00]),
            HostileString("only lone surrogates", units: (0 ..< 200).map { $0 % 2 == 0 ? 0xD800 : 0xDFFF }),
            HostileString(
                "unpaired bidi controls",
                "abc \u{202E}RLO without PDF \u{2067}RLI \u{2066}LRI \u{202C}\u{202C}\u{2069}\u{2069} \u{202B}\u{202A} שלום عربي end",
            ),
            HostileString(
                "200 nested embeddings",
                String(repeating: "\u{202B}a\u{202A}b", count: 100) + "x" + String(repeating: "\u{202C}", count: 50),
            ),
            HostileString("combining marks on one base", units: [0x61] + combining + Array(" next word".utf16)),
            HostileString("combining marks with no base", units: combining),
            HostileString("chained zero-width joiners", "x" + String(repeating: "\u{200D}", count: 2000) + "y"),
            HostileString("long ZWJ family sequence", zwjFamily + " tail"),
            // CoreText's cost on a run of regional indicators grows with its cube
            // (see `regionalIndicatorRunCostMatchesCoreText`), so this stays short.
            HostileString("long flag run", String(repeating: "\u{1F1EF}\u{1F1F5}\u{1F1FA}", count: 100 * repeats)),
            HostileString("variation selectors", String(repeating: "a\u{FE0F}\u{FE0E}\u{E0100}", count: 500)),
            HostileString("U+FFFC without an attachment", "before \u{FFFC}\u{FFFC} middle \u{FFFC}"),
            HostileString("NUL characters", units: [0x00, 0x41, 0x00, 0x00, 0x20, 0x42, 0x00]),
            HostileString("only NULs", units: Array(repeating: 0, count: 500)),
            HostileString("every separator", units: (0 ..< 30).flatMap { [UInt16(0x61 + $0 % 26)] + separators }),
            HostileString("only separators", units: Array((0 ..< 40).map { _ in separators }.joined())),
            HostileString("CRLF and lone CR", String(repeating: "line\r\nline\rline\n", count: 100)),
            HostileString("tabs and soft hyphens", String(repeating: "\t\u{00AD}a\u{00AD}\t", count: 300)),
            HostileString(
                "noncharacters and private use",
                units: [0xFFFE, 0xFFFF, 0xDBFF, 0xDFFF, 0xE000, 0xF8FF, 0xFDD0, 0xFDEF, 0x20, 0x41],
            ),
            HostileString(
                "Zalgo",
                String(repeating: "Z\u{0351}\u{0352}\u{0357}\u{035B}\u{0346}a\u{0344}\u{0310}\u{0352}l\u{0350}g\u{0363}o", count: 200),
            ),
            HostileString("Thai and Devanagari clusters", String(repeating: "क्षत्रिय ฟ้้้้้้ ", count: 200)),
            HostileString("empty", ""),
            HostileString("single space", " "),
            HostileString("single newline", "\n"),
        ]
    }
}

@MainActor
@Suite("Stress: hostile strings", .tags(.stress), StressMode.enabled)
struct StressHostileStringTests {
    private static let font = PlatformFont.systemFont(ofSize: 15)

    /// Lays out `text` at several widths and checks every invariant.
    private func audit(_ text: NSAttributedString, name: String) {
        let length = text.length
        let context = makeStressContext()
        for width: CGFloat in [1, 37, 320, 4000] {
            let layout = TextLabel.Layout(attributedString: text)
            let fit = layout.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            let size = CGSize(width: width, height: max(fit.height, 10))
            var audit = LayoutAudit()
            audit.audit(
                layout,
                containerSize: size,
                samplePoints: samplePoints(in: size, count: 36),
                ranges: [
                    NSRange(location: 0, length: min(1, length)),
                    NSRange(location: length / 2, length: 3),
                    NSRange(location: max(0, length - 2), length: 2),
                ],
                context: context,
                visibleRect: CGRect(x: 0, y: size.height / 3, width: width, height: 40),
            )
            audit.record("\(name) at width \(width)")
            // Every character index has a caret rect when there are lines.
            if length > 0, layout.visibleLineCount(in: nil) > 0 {
                for index in stride(from: 0, to: length, by: max(1, length / 50)) {
                    if let caret = layout.caretRect(at: index, onLineOf: index) {
                        #expect(caret.isFiniteRect, "\(name): caret at \(index)")
                    }
                }
            }
        }

        #if !os(watchOS)
            let label = TextLabelView(attributedText: text)
            label.isSelectable = true
            label.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
            forceLayout(label)
            label.selectAll()
            if length > 0 {
                #expect(label.selectionRange == NSRange(location: 0, length: length), "\(name)")
            }
            // Word and line selection at a spread of indices, including both ends.
            let indices = Set([0, 1, length / 3, length / 2, length - 2, length - 1, length, length + 5])
            for index in indices.sorted() where index >= 0 {
                label.selectWordAtIndex(index)
                checkSelection(label, name: name)
                label.selectLineAtIndex(index)
                checkSelection(label, name: name)
            }
            _ = label.selectedAttributedText()
            for point in samplePoints(in: label.bounds.size, count: 16) {
                if let index = label.characterIndexAtPoint(point) {
                    #expect(index >= 0 && index <= length, "\(name)")
                }
                _ = label.hitTarget(at: point)
                _ = label.highlightRegionForTap(at: point)
            }
            drawView(label, rect: label.bounds)
        #endif
    }

    #if !os(watchOS)
        private func checkSelection(_ label: TextLabelView, name: String) {
            guard let range = label.selectionRange else { return }
            #expect(range.location >= 0 && range.length > 0, "\(name): \(range)")
            #expect(NSMaxRange(range) <= label.attributedText.length, "\(name): \(range)")
        }
    #endif

    /// At most 0.25 s per string on an M4 Max in the quick mode; the full mode's longer
    /// clusters take up to 3 s (the flag run).
    @Test(arguments: HostileString.all)
    func `hostile strings lay out safely`(_ hostile: HostileString) {
        let text = NSAttributedString(string: hostile.nsString as String, attributes: [.font: Self.font])
        #expect(text.length == hostile.units.count, "lone surrogates must survive bridging")
        withinBudget("hostile: \(hostile.name)", seconds: StressMode.pick(2, full: 20)) {
            audit(text, name: hostile.name)
        }
    }

    /// The same strings with attributes changing at every UTF-16 unit, so runs
    /// split inside surrogate pairs and grapheme clusters.
    @Test func `attributes splitting clusters`() {
        // About 0.5 s on an M4 Max.
        withinBudget("attributes splitting clusters", seconds: 4) {
            for hostile in HostileString.all where hostile.units.count < 2000 {
                let text = NSMutableAttributedString(string: hostile.nsString as String)
                for index in 0 ..< text.length {
                    text.addAttributes([
                        .font: PlatformFont.systemFont(ofSize: CGFloat(10 + index % 13)),
                        .link: URL(string: "https://example.com/\(index % 3)")!,
                    ], range: NSRange(location: index, length: 1))
                }
                audit(text, name: "\(hostile.name), split")
            }
        }
    }

    /// CoreText's line breaking is about cubic in the length of a run of
    /// regional indicators (flag emoji halves). On an M4 Max, raw
    /// `CTFramesetterSuggestFrameSizeWithConstraints` at width 37 takes 0.66,
    /// 4.9 and 38 s for 600, 1,200 and 2,400 indicators: a few kilobytes of
    /// flags can stall any CoreText label. Litext cannot avoid that cost, but
    /// must not add to it.
    @Test func `regional indicator run cost matches core text`() {
        let count = StressMode.pick(100, full: 200)
        let text = NSAttributedString(
            string: String(repeating: "\u{1F1EF}\u{1F1F5}\u{1F1FA}", count: count),
            attributes: [.font: Self.font],
        )
        let constraint = CGSize(width: 37, height: CGFloat.greatestFiniteMagnitude)
        let clock = ContinuousClock()

        let coreTextStart = clock.now
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        _ = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(), nil, constraint, nil)
        let coreText = seconds(of: clock.now - coreTextStart)

        let litextStart = clock.now
        let layout = TextLabel.Layout(attributedString: text)
        let fit = layout.sizeThatFits(constraint)
        layout.containerSize = CGSize(width: 37, height: fit.height)
        let litext = seconds(of: clock.now - litextStart)

        print("[stress] \(count * 3) regional indicators: CoreText \(coreText) s, Litext \(litext) s")
        #expect(litext <= coreText * 1.5 + 0.05)
        #expect(layout.visibleLineCount(in: nil) > 0)
    }

    /// `.link` holds whatever the caller put there.
    @Test func `odd link values`() throws {
        let values: [(String, Any)] = try [
            ("NSNumber", NSNumber(value: 42)),
            ("empty string", ""),
            ("invalid URL string", "ht tp://exa mple .com/%%%"),
            ("whitespace", "   "),
            ("NSNull", NSNull()),
            ("date", Date(timeIntervalSince1970: 0)),
            ("relative URL", #require(URL(string: "relative/path"))),
            ("file URL", URL(fileURLWithPath: "/tmp/x")),
            ("data", Data([0xFF, 0x00])),
            ("attributed string", NSAttributedString(string: "nested")),
        ]
        for (name, value) in values {
            let text = NSMutableAttributedString(string: "Tap ", attributes: [.font: Self.font])
            text.append(NSAttributedString(string: "this odd link", attributes: [.font: Self.font, .link: value]))
            text.append(NSAttributedString(string: " please", attributes: [.font: Self.font]))
            audit(text, name: "link \(name)")

            let layout = TextLabel.Layout(attributedString: text)
            layout.containerSize = CGSize(width: 300, height: 50)
            layout.updateHighlightRegions()
            let region = try #require(layout.highlightRegions.first { $0.kind == .link }, "link \(name)")
            #expect(region.stringRange == NSRange(location: 4, length: 13))
            // A value that is neither a URL nor a URL string has no URL.
            _ = region.linkURL

            #if canImport(AppKit) && !targetEnvironment(macCatalyst)
                try clickFirstLink(in: text, name: name)
            #endif
        }
    }

    /// Attachment attributes spanning more than the U+FFFC they belong to.
    @Test func `attachment attribute on longer ranges`() {
        let attachment = TextLabel.Attachment(size: CGSize(width: 24, height: 18))
        #if !os(watchOS)
            attachment.view = PlatformView(frame: .zero)
        #endif
        let cases: [(String, NSAttributedString)] = [
            ("attribute over three letters", {
                let text = NSMutableAttributedString(string: "ab cde fg", attributes: [.font: Self.font])
                text.addAttribute(.litextAttachment, value: attachment, range: NSRange(location: 3, length: 3))
                return text
            }()),
            ("attribute and run delegate over three letters", {
                let text = NSMutableAttributedString(string: "ab cde fg", attributes: [.font: Self.font])
                let range = NSRange(location: 3, length: 3)
                text.addAttribute(.litextAttachment, value: attachment, range: range)
                text.addAttribute(kCTRunDelegateAttributeName as NSAttributedString.Key, value: attachment.runDelegate, range: range)
                return text
            }()),
            ("attribute over the whole string with newlines", {
                let text = NSMutableAttributedString(string: "line one\nline two\n\u{FFFC}", attributes: [.font: Self.font])
                text.addAttribute(.litextAttachment, value: attachment, range: NSRange(location: 0, length: text.length))
                return text
            }()),
            ("run delegate without attachment", {
                let text = NSMutableAttributedString(string: "x\u{FFFC}y", attributes: [.font: Self.font])
                text.addAttribute(
                    kCTRunDelegateAttributeName as NSAttributedString.Key,
                    value: attachment.runDelegate,
                    range: NSRange(location: 0, length: 3),
                )
                return text
            }()),
            ("attachment attribute holding a string", {
                let text = NSMutableAttributedString(string: "x\u{FFFC}y", attributes: [.font: Self.font])
                text.addAttribute(.litextAttachment, value: "not an attachment", range: NSRange(location: 1, length: 1))
                return text
            }()),
            ("same attachment twice", {
                let text = NSMutableAttributedString(attributedString: attachment.attributedString(attributes: [.font: Self.font]))
                text.append(NSAttributedString(string: " and ", attributes: [.font: Self.font]))
                text.append(attachment.attributedString(attributes: [.font: Self.font]))
                return text
            }()),
        ]
        for (name, text) in cases {
            audit(text, name: name)
            #if !os(watchOS)
                let label = TextLabelView(attributedText: text)
                label.frame = CGRect(x: 0, y: 0, width: 300, height: 100)
                forceLayout(label)
                // One view is placed once, however many regions refer to it.
                #expect(label.attachmentViews.count <= 1, "\(name)")
                if let view = attachment.view, label.attachmentViews.contains(view) {
                    #expect(view.frame.isFiniteRect, "\(name)")
                    #expect(view.superview === label, "\(name)")
                }
                label.attributedText = NSAttributedString(string: "plain")
                forceLayout(label)
                #expect(label.attachmentViews.isEmpty, "\(name)")
            #endif
        }
    }

    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        @MainActor
        private final class TapRecorder: TextLabelViewDelegate {
            var regions: [TextLabel.HighlightRegion] = []

            func textLabelView(_: TextLabelView, didTapHighlightRegion region: TextLabel.HighlightRegion, at _: CGPoint) {
                regions.append(region)
                _ = region.linkURL
            }
        }

        /// Clicks the first link with synthesized events, through the delegate and
        /// the SwiftUI coordinator, which must ignore a link without a URL.
        private func clickFirstLink(in text: NSAttributedString, name: String) throws {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 300, height: 100),
                styleMask: [.titled],
                backing: .buffered,
                defer: false,
            )
            let label = TextLabelView(attributedText: text)
            label.frame = CGRect(x: 0, y: 0, width: 300, height: 100)
            window.contentView?.addSubview(label)
            label.layoutSubtreeIfNeeded()
            let recorder = TapRecorder()
            label.delegate = recorder

            let run = try #require(label.layoutRuns(matching: .link).first, "link \(name)")
            let rect = label.viewRect(fromLayoutRect: run.rect)
            let point = label.convert(CGPoint(x: rect.midX, y: rect.midY), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(
                    with: type,
                    location: point,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: 1,
                ))
                if type == .leftMouseDown {
                    label.mouseDown(with: event)
                } else {
                    label.mouseUp(with: event)
                }
            }
            #expect(recorder.regions.count == 1, "link \(name)")
            #expect(!label.isInteractionInProgress)

            var opened = [URL]()
            let coordinator = TextLabel.Coordinator(onTapLink: { opened.append($0) }, onSelectionChange: nil)
            for region in recorder.regions {
                coordinator.textLabelView(label, didTapHighlightRegion: region, at: .zero)
            }
            #expect(opened.count == recorder.regions.compactMap(\.linkURL).count, "link \(name)")
        }
    #endif
}
