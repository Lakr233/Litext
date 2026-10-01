//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//
//  Stress: rapid updates, synthesized input, many labels and SwiftUI. See
//  StressSupport.swift for the default and LITEXT_STRESS=1 modes.
//
//  Mouse sequences use synthesized NSEvents and run on AppKit only; UIKit runs
//  the same update loop and drives selection handles instead, since UITouch
//  cannot be synthesized.
//

import CoreGraphics
import CoreText
import Foundation
@testable import Litext
import SwiftUI
import Testing

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

#if !os(watchOS)

    /// Text streamed onto a label the way a chat or markdown renderer does:
    /// growing, restyled, with links and attachments, restarting now and then.
    @MainActor
    struct TextStream {
        private(set) var text = NSMutableAttributedString()
        private var random: SeededGenerator
        private let font = PlatformFont.systemFont(ofSize: 15)
        private let words = [
            "stream", "of", "text", "Litext", "renders", "quickly", "שלום", "مرحبا", "中文", "👩‍💻", "e\u{301}",
        ]

        init(seed: UInt64) {
            random = SeededGenerator(seed: seed)
        }

        /// Appends a few words, and sometimes a link, an attachment or a newline.
        mutating func grow() -> NSAttributedString {
            for _ in 0 ..< Int.random(in: 1 ... 4, using: &random) {
                var attributes: [NSAttributedString.Key: Any] = [.font: font]
                let roll = Int.random(in: 0 ..< 20, using: &random)
                if roll == 0 {
                    attributes[.link] = URL(string: "https://example.com/\(text.length)")!
                }
                if roll == 1 {
                    let attachment = TextLabel.Attachment(size: CGSize(width: 16, height: 16))
                    if Bool.random(using: &random) {
                        attachment.view = PlatformView(frame: .zero)
                    }
                    text.append(attachment.attributedString(attributes: attributes))
                }
                let separator = roll == 2 ? "\n" : " "
                text.append(NSAttributedString(string: words.randomElement(using: &random)! + separator, attributes: attributes))
            }
            return snapshot()
        }

        /// Restyles a stretch already shown, as a markdown renderer does.
        mutating func restyle() -> NSAttributedString {
            guard text.length > 4 else { return snapshot() }
            let location = Int.random(in: 0 ..< text.length - 2, using: &random)
            let range = NSRange(location: location, length: min(10, text.length - location))
            text.addAttribute(.font, value: PlatformFont.boldSystemFont(ofSize: 15), range: range)
            return snapshot()
        }

        /// Cuts the text back, as a retried answer does.
        mutating func shrink() -> NSAttributedString {
            guard text.length > 0 else { return snapshot() }
            let length = Int.random(in: 0 ..< text.length, using: &random)
            text.deleteCharacters(in: NSRange(location: length, length: text.length - length))
            return snapshot()
        }

        mutating func restart() -> NSAttributedString {
            text = NSMutableAttributedString()
            return grow()
        }

        private func snapshot() -> NSAttributedString {
            text.copy() as! NSAttributedString
        }
    }

    /// Checks the state a label must keep however it got there.
    @MainActor
    func expectConsistent(_ label: TextLabelView, _ step: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let length = label.attributedText.length
        if let range = label.selectionRange {
            #expect(
                range.location >= 0 && range.length > 0 && range.location + range.length <= length,
                "\(step): selection \(range) beyond length \(length)",
                sourceLocation: sourceLocation
            )
        } else {
            #expect(label.selectionLayer == nil, "\(step): selection layer without a selection", sourceLocation: sourceLocation)
        }
        #expect(
            label.textLayout.attributedString.isEqual(to: label.attributedText),
            "\(step): layout text differs from attributedText",
            sourceLocation: sourceLocation
        )
        for region in label.highlightRegions {
            #expect(
                region.stringRange.location + region.stringRange.length <= length,
                "\(step): stale highlight region \(region.stringRange), length \(length)",
                sourceLocation: sourceLocation
            )
        }
        if let active = label.activeHighlightRegion {
            #expect(
                active.stringRange.location + active.stringRange.length <= length,
                "\(step): stale active highlight \(active.stringRange), length \(length)",
                sourceLocation: sourceLocation
            )
        }
        for view in label.attachmentViews {
            #expect(view.superview === label, "\(step): attachment view not in the label", sourceLocation: sourceLocation)
            #expect(view.frame.isFiniteRect, "\(step): attachment frame \(view.frame)", sourceLocation: sourceLocation)
        }
    }

    @MainActor
    @Suite("Stress: views", .tags(.stress), .serialized)
    struct StressViewTests {
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
            private func makeWindow(size: CGSize = CGSize(width: 800, height: 600)) -> NSWindow {
                let window = NSWindow(
                    contentRect: CGRect(origin: .zero, size: size),
                    styleMask: [.titled, .resizable],
                    backing: .buffered,
                    defer: false
                )
                window.isReleasedWhenClosed = false
                return window
            }
        #elseif canImport(UIKit)
            private func makeWindow(size: CGSize = CGSize(width: 800, height: 600)) -> UIWindow {
                UIWindow(frame: CGRect(origin: .zero, size: size))
            }
        #endif

        private func host(_ label: TextLabelView, in window: some AnyObject) {
            #if canImport(AppKit) && !targetEnvironment(macCatalyst)
                (window as! NSWindow).contentView?.addSubview(label)
            #elseif canImport(UIKit)
                (window as! UIWindow).addSubview(label)
            #endif
        }

        // MARK: - Rapid updates

        /// Streams text onto a label while resizing, laying out, drawing, selecting
        /// and invalidating it. 1,000 steps by default (about 0.2 s on an M4 Max),
        /// 10,000 with LITEXT_STRESS=1 (about 2 s). The stream restarts every few
        /// hundred steps, so total work stays linear in the step count.
        @Test func rapidUpdatesKeepStateConsistent() {
            let steps = StressMode.pick(1000, full: 10000)
            var random = SeededGenerator(seed: 0xFEED)
            var stream = TextStream(seed: 7)
            let window = makeWindow()
            let label = TextLabelView(attributedText: stream.grow())
            label.isSelectable = true
            label.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
            host(label, in: window)

            withinBudget("\(steps) rapid updates", seconds: max(2, Double(steps) * 0.002)) {
                for step in 0 ..< steps {
                    autoreleasepool {
                        let name: String
                        switch Int.random(in: 0 ..< 16, using: &random) {
                        case 0 ... 4:
                            name = "grow"
                            label.attributedText = step % 300 == 299 ? stream.restart() : stream.grow()
                        case 5:
                            name = "restyle"
                            label.attributedText = stream.restyle()
                        case 6:
                            name = "shrink"
                            label.attributedText = stream.shrink()
                        case 7:
                            name = "resize"
                            label.frame = CGRect(
                                x: CGFloat.random(in: 0 ... 50, using: &random),
                                y: 0,
                                width: CGFloat.random(in: 1 ... 700, using: &random),
                                height: CGFloat.random(in: 0 ... 600, using: &random)
                            )
                        case 8:
                            name = "layout"
                            forceLayout(label)
                        case 9:
                            name = "draw"
                            forceLayout(label)
                            drawView(label, rect: label.bounds)
                        case 10:
                            name = "select"
                            let length = label.attributedText.length
                            label.selectionRange = NSRange(
                                location: Int.random(in: -1 ... length + 1, using: &random),
                                length: Int.random(in: -1 ... length + 2, using: &random)
                            )
                        case 11:
                            name = "select all"
                            label.selectAll()
                        case 12:
                            name = "clear"
                            label.clearSelection()
                        case 13:
                            name = "invalidate"
                            label.invalidateTextLayout()
                        case 14:
                            name = "reload"
                            label.reloadTextLayout()
                        default:
                            name = "press link"
                            forceLayout(label)
                            if let region = label.highlightRegions.first(where: { $0.kind == .link }) {
                                label.addActiveHighlightRegion(region)
                            }
                        }
                        expectConsistent(label, "step \(step) (\(name))")
                    }
                }
                forceLayout(label)
                expectConsistent(label, "final layout")
            }
        }

        /// A selection made on streamed text survives while the text only grows past
        /// it, and is dropped, never left out of bounds, as the text is cut back.
        @Test func selectionWhileTextShrinks() {
            let font = PlatformFont.systemFont(ofSize: 15)
            let full = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 40)
            let label = TextLabelView(attributedText: NSAttributedString(string: full, attributes: [.font: font]))
            label.isSelectable = true
            label.frame = CGRect(x: 0, y: 0, width: 300, height: 400)
            forceLayout(label)

            let selection = NSRange(location: 100, length: 50)
            label.selectionRange = selection
            let expected = (full as NSString).substring(with: selection)
            var length = full.utf16.count
            withinBudget("selection while text shrinks", seconds: 2) {
                while length > 0 {
                    length = max(0, length - 7)
                    let prefix = (full as NSString).substring(to: length)
                    label.attributedText = NSAttributedString(string: prefix, attributes: [.font: font])
                    if length % 3 == 0 {
                        forceLayout(label)
                    }
                    expectConsistent(label, "length \(length)")
                    if length >= NSMaxRange(selection) {
                        #expect(label.selectionRange == selection)
                        #expect(label.selectedPlainText() == expected)
                    } else {
                        #expect(label.selectionRange == nil, "length \(length)")
                    }
                }
            }

            // Ranges set while the text is shorter than they are get clamped or dropped.
            for range in [
                NSRange(location: 0, length: 10),
                NSRange(location: 5, length: Int.max),
                NSRange(location: NSNotFound, length: 3),
            ] {
                label.attributedText = NSAttributedString(string: "short", attributes: [.font: font])
                label.selectionRange = range
                expectConsistent(label, "range \(range) on short text")
                label.attributedText = NSAttributedString(string: "", attributes: [.font: font])
                expectConsistent(label, "range \(range) on empty text")
                #expect(label.selectionRange == nil)
            }
        }

        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
            @MainActor
            private final class TapCounter: TextLabelViewDelegate {
                var taps = 0

                func textLabelView(_: TextLabelView, didTapHighlightRegion _: TextLabel.HighlightRegion, at _: CGPoint) {
                    taps += 1
                }
            }

            /// Random click, double-click, triple-click and drag sequences from
            /// synthesized events, with the text replaced in the middle of some of
            /// them. 400 gestures by default (about 0.05 s), 4,000 with LITEXT_STRESS=1
            /// (about 0.5 s).
            @Test func randomMouseSequences() throws {
                let gestures = StressMode.pick(400, full: 4000)
                var random = SeededGenerator(seed: 0xC11C)
                var stream = TextStream(seed: 11)
                let window = makeWindow()
                for _ in 0 ..< 30 {
                    _ = stream.grow()
                }
                let label = TextLabelView(attributedText: stream.grow())
                label.isSelectable = true
                label.frame = CGRect(x: 10, y: 10, width: 400, height: 300)
                host(label, in: window)
                label.layoutSubtreeIfNeeded()
                let counter = TapCounter()
                label.delegate = counter
                var gesturesEndingWithSelection = 0

                func event(_ type: NSEvent.EventType, at point: CGPoint, clicks: Int) throws -> NSEvent {
                    try #require(NSEvent.mouseEvent(
                        with: type,
                        location: label.convert(point, to: nil),
                        modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber,
                        context: nil,
                        eventNumber: 0,
                        clickCount: clicks,
                        pressure: 1
                    ))
                }
                func randomPoint() -> CGPoint {
                    CGPoint(
                        x: CGFloat.random(in: -40 ... 440, using: &random),
                        y: CGFloat.random(in: -40 ... 340, using: &random)
                    )
                }

                try withinBudget("\(gestures) mouse gestures", seconds: max(2, Double(gestures) * 0.001)) {
                    for gesture in 0 ..< gestures {
                        try autoreleasepool {
                            let clicks = [1, 1, 1, 2, 3].randomElement(using: &random)!
                            let start = randomPoint()
                            let tapsBefore = counter.taps
                            var replacedText = false
                            try label.mouseDown(with: event(.leftMouseDown, at: start, clicks: clicks))
                            #expect(label.isInteractionInProgress)
                            var location = start
                            for _ in 0 ..< Int.random(in: 0 ... 6, using: &random) {
                                location = Bool.random(using: &random) ? randomPoint() : location
                                try label.mouseDragged(with: event(.leftMouseDragged, at: location, clicks: clicks))
                                if Int.random(in: 0 ..< 8, using: &random) == 0 {
                                    replacedText = true
                                    label.attributedText = Bool.random(using: &random) ? stream.grow() : stream.shrink()
                                    if Bool.random(using: &random) {
                                        label.layoutSubtreeIfNeeded()
                                    }
                                }
                                expectConsistent(label, "gesture \(gesture) drag")
                            }
                            if Int.random(in: 0 ..< 6, using: &random) == 0 {
                                replacedText = true
                                label.attributedText = stream.grow()
                            }
                            try label.mouseUp(with: event(.leftMouseUp, at: location, clicks: clicks))
                            #expect(!label.isInteractionInProgress, "gesture \(gesture)")
                            #expect(!label.interactionState.isForwardingToSuper, "gesture \(gesture)")
                            #expect(label.activeHighlightRegion == nil, "gesture \(gesture)")
                            if replacedText {
                                #expect(counter.taps == tapsBefore, "gesture \(gesture) tapped a link that replaced the pressed one")
                            }
                            expectConsistent(label, "gesture \(gesture) end")
                            if label.selectionRange != nil {
                                gesturesEndingWithSelection += 1
                            }

                            // Unbalanced: a stray mouseDown is followed by another full gesture.
                            if Int.random(in: 0 ..< 10, using: &random) == 0 {
                                try label.mouseDown(with: event(.leftMouseDown, at: randomPoint(), clicks: 1))
                            }
                            if gesture % 50 == 0 {
                                label.layoutSubtreeIfNeeded()
                                drawView(label, rect: label.bounds)
                            }
                        }
                    }
                    try label.mouseUp(with: event(.leftMouseUp, at: .zero, clicks: 1))
                }
                #expect(!label.isInteractionInProgress)
                expectConsistent(label, "after all gestures")
                // The events really drive selection and links.
                print("[stress] \(gesturesEndingWithSelection) of \(gestures) gestures left a selection, \(counter.taps) tapped a link")
                #expect(gesturesEndingWithSelection > gestures / 10)
            }
        #endif

        #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS)
            /// Drags the selection handles while the text changes underneath.
            @Test func randomHandleDrags() {
                let drags = StressMode.pick(400, full: 4000)
                var random = SeededGenerator(seed: 0x4A4D)
                var stream = TextStream(seed: 13)
                for _ in 0 ..< 30 {
                    _ = stream.grow()
                }
                let label = TextLabelView(attributedText: stream.grow())
                label.isSelectable = true
                label.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
                forceLayout(label)
                withinBudget("\(drags) handle drags", seconds: max(2, Double(drags) * 0.002)) {
                    for drag in 0 ..< drags {
                        label.selectAll()
                        let kind: SelectionHandle.Kind = Bool.random(using: &random) ? .start : .end
                        label.selectionHandleDidBeginDrag(kind)
                        for _ in 0 ..< Int.random(in: 1 ... 5, using: &random) {
                            label.selectionHandleDidMove(kind, toLocationInSuperView: CGPoint(
                                x: CGFloat.random(in: -40 ... 440, using: &random),
                                y: CGFloat.random(in: -40 ... 340, using: &random)
                            ))
                            if Int.random(in: 0 ..< 6, using: &random) == 0 {
                                label.attributedText = Bool.random(using: &random) ? stream.grow() : stream.shrink()
                                forceLayout(label)
                            }
                            expectConsistent(label, "drag \(drag)")
                        }
                        label.selectionHandleDidEndDrag(kind)
                        #expect(!label.isInteractionInProgress)
                        expectConsistent(label, "drag \(drag) end")
                    }
                }
            }
        #endif

        // MARK: - Many labels

        /// 2,000 labels created, laid out and drawn one after another: about
        /// 0.15 s on an M4 Max, in both modes.
        @Test func manyLabelsLayOutAndDraw() {
            let count = 2000
            let font = PlatformFont.systemFont(ofSize: 14)
            withinBudget("\(count) labels laid out and drawn", seconds: 2) {
                for index in 0 ..< count {
                    autoreleasepool {
                        let text = NSMutableAttributedString(
                            string: "Label \(index): some text that wraps across a couple of lines ",
                            attributes: [.font: font]
                        )
                        text.append(NSAttributedString(
                            string: "with a link",
                            attributes: [.font: font, .link: URL(string: "https://example.com/\(index)")!]
                        ))
                        let label = TextLabelView(attributedText: text)
                        let size = label.textLayout.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude))
                        label.frame = CGRect(origin: .zero, size: CGSize(width: 200, height: size.height))
                        forceLayout(label)
                        drawView(label, rect: label.bounds)
                        #expect(!label.highlightRegions.isEmpty)
                    }
                }
            }
        }

        /// 200 labels in one window. Selecting in any one clears the others through
        /// the deduplication notification, whatever order the selections come in.
        @Test func selectionDeduplicatesAcrossManyLabels() {
            let count = 200
            var random = SeededGenerator(seed: 0xD0D0)
            let window = makeWindow(size: CGSize(width: 800, height: 4000))
            let font = PlatformFont.systemFont(ofSize: 13)
            var labels = [TextLabelView]()
            for index in 0 ..< count {
                let label = TextLabelView(attributedText: NSAttributedString(
                    string: "Label number \(index) with selectable text",
                    attributes: [.font: font]
                ))
                label.isSelectable = true
                label.frame = CGRect(x: 0, y: CGFloat(index) * 20, width: 400, height: 20)
                host(label, in: window)
                forceLayout(label)
                labels.append(label)
            }

            func selectedLabels() -> [Int] {
                labels.indices.filter { labels[$0].selectionRange != nil }
            }

            // 1,000 selections reach 200 observers each: about 0.08 s on an M4 Max.
            withinBudget("selection deduplication across \(count) labels", seconds: 1) {
                for round in 0 ..< 1000 {
                    let index = Int.random(in: 0 ..< count, using: &random)
                    switch round % 3 {
                    case 0: labels[index].selectAll()
                    case 1: labels[index].selectionRange = NSRange(location: 0, length: 5)
                    default: labels[index].selectWordAtIndex(3)
                    }
                    #expect(selectedLabels() == [index], "round \(round)")
                    for other in [0, count - 1, (index + 1) % count] where other != index {
                        #expect(labels[other].selectionLayer == nil, "round \(round)")
                    }
                }
            }

            // Clearing the only selection leaves none; a layout pass never clears one.
            if let selected = selectedLabels().first {
                for label in labels {
                    label.invalidateTextLayout()
                    forceLayout(label)
                }
                #expect(selectedLabels() == [selected])
                labels[selected].clearSelection()
            }
            #expect(selectedLabels().isEmpty)
        }

        // MARK: - SwiftUI

        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
            /// A hosted `TextLabel` whose text changes 1,000 times, with layout forced
            /// after each change: about 0.45 s on an M4 Max, in both modes.
            @Test func swiftUILabelUpdatedRepeatedly() throws {
                let updates = 1000
                var stream = TextStream(seed: 21)
                var lastText = stream.grow()
                var selections = [String?]()
                func makeRoot(_ text: NSAttributedString) -> some View {
                    TextLabel(attributedString: text)
                        .selectable()
                        .onSelectionChange { selections.append($0) }
                        .frame(width: 320)
                }
                let hostingView = NSHostingView(rootView: makeRoot(lastText))
                hostingView.frame = CGRect(x: 0, y: 0, width: 320, height: 600)
                let window = makeWindow(size: CGSize(width: 320, height: 600))
                window.contentView?.addSubview(hostingView)
                hostingView.layoutSubtreeIfNeeded()

                func findLabel(in view: NSView) -> TextLabelView? {
                    if let label = view as? TextLabelView {
                        return label
                    }
                    for subview in view.subviews {
                        if let label = findLabel(in: subview) {
                            return label
                        }
                    }
                    return nil
                }
                let label = try #require(findLabel(in: hostingView))

                withinBudget("\(updates) SwiftUI updates", seconds: 4) {
                    for update in 0 ..< updates {
                        autoreleasepool {
                            lastText = update % 250 == 249 ? stream.restart() : (update % 9 == 0 ? stream.shrink() : stream.grow())
                            hostingView.rootView = makeRoot(lastText)
                            hostingView.layoutSubtreeIfNeeded()
                            if update % 10 == 0, label.attributedText.length > 3 {
                                label.selectionRange = NSRange(location: 0, length: 3)
                            }
                            #expect(label.frame.isFiniteRect)
                            expectConsistent(label, "SwiftUI update \(update)")
                        }
                    }
                }
                #expect(findLabel(in: hostingView) === label, "the hosted label was recreated")
                #expect(label.attributedText.string == lastText.string)
                #expect(label.frame.width == 320)
                #expect(label.frame.height >= label.textLayout.sizeThatFits(
                    CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
                ).height - 1)
                for selection in selections {
                    if let selection {
                        #expect(selection.utf16.count <= 3)
                    }
                }
            }
        #endif
    }

#endif
