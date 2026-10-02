//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//
//  The stress helpers of `LitextTests/Stress/StressSupport.swift`, cut down to what the
//  animation stress suite needs, since test targets cannot share sources: the `.stress`
//  tag, the `LITEXT_STRESS` switch, time budgets and a text stream. `StressSupport.swift`
//  explains how the quick and full modes are meant to be run. `SeededGenerator` lives in
//  LTXTextChangeTests.swift.
//

#if !os(watchOS)

    import CoreText
    import DisplayLink
    import Foundation
    @testable import Litext
    @testable import LitextAnimation
    import QuartzCore
    import Testing

    #if canImport(UIKit)
        import UIKit
    #elseif canImport(AppKit)
        import AppKit
    #endif

    extension Tag {
        @Tag static var stress: Self
    }

    enum StressMode {
        static let environment = ProcessInfo.processInfo.environment

        /// `true` when `LITEXT_STRESS` is set to anything but `0`.
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

        /// `LITEXT_FUZZ_ITERATIONS`, or `standard` / `full` by mode.
        static func fuzzIterations(_ standard: Int, full: Int) -> Int {
            if let value = environment["LITEXT_FUZZ_ITERATIONS"].flatMap(Int.init), value > 0 {
                return value
            }
            return pick(standard, full: full)
        }

        static let fuzzSeed: UInt64 = environment["LITEXT_FUZZ_SEED"].flatMap(UInt64.init) ?? 0x5EED_1A7E
    }

    /// Runs `body`, prints how long it took and records an issue when it took longer than
    /// `budget` seconds.
    @MainActor
    @discardableResult
    func withinBudget<T>(
        _ label: String,
        seconds budget: Double,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ body: () throws -> T,
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
            sourceLocation: sourceLocation,
        )
        return result
    }

    /// Text streamed onto a label the way a chat or markdown renderer does: growing,
    /// restyled, with links and attachments, cut back and restarted now and then.
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

    /// A copy of `text` whose attachments carry no views, for a reference label that must
    /// not take the attachment views away from the label under test. Attachments draw
    /// nothing themselves, so both render the same pixels.
    @MainActor
    func withoutAttachmentViews(_ text: NSAttributedString) -> NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: text)
        text.enumerateAttribute(
            .litextAttachment,
            in: NSRange(location: 0, length: text.length),
        ) { value, range, _ in
            guard let attachment = value as? TextLabel.Attachment, attachment.view != nil else { return }
            copy.addAttribute(.litextAttachment, value: TextLabel.Attachment(size: attachment.size), range: range)
        }
        return copy
    }

    // MARK: - Animation

    /// A clock the test moves by hand, read by a label for the time of a change.
    final class SyntheticClock {
        var now: CFTimeInterval

        init(_ now: CFTimeInterval) {
            self.now = now
        }
    }

    /// A fade-in effect shaped like a real one: every arrival fades in over `duration`,
    /// several arrivals are in flight at once, and each frame invalidates only the
    /// characters still fading. It also counts what the label asked of it.
    @MainActor
    final class FadeAnimator: LTXTextAnimator {
        struct Arrival {
            var range: NSRange
            let start: CFTimeInterval
        }

        let duration: CFTimeInterval
        private(set) var arrivals: [Arrival] = []
        /// The most arrivals in flight at once.
        private(set) var peakArrivalCount = 0
        private(set) var drawnLineCount = 0
        private(set) var finishCount = 0

        init(duration: CFTimeInterval = 0.35) {
            self.duration = duration
        }

        func animateChange(_ context: LTXAnimationContext, at time: CFTimeInterval) {
            let change = context.change
            let editStart = change.commonPrefixLength
            let editEnd = change.previousLength - change.commonSuffixLength
            let delta = change.length - change.previousLength
            // Arrivals before the edit stay, those after it move with the text, and the
            // characters it removed stop animating.
            var moved: [Arrival] = []
            for arrival in arrivals {
                let start = arrival.range.location
                let end = NSMaxRange(arrival.range)
                if end <= editStart {
                    moved.append(arrival)
                } else if start >= editEnd {
                    moved.append(Arrival(range: NSRange(location: start + delta, length: end - start), start: arrival.start))
                } else if start < editStart {
                    moved.append(Arrival(range: NSRange(location: start, length: editStart - start), start: arrival.start))
                }
            }
            arrivals = moved
            if change.hasInsertion {
                arrivals.append(Arrival(range: change.insertedRange, start: time))
            }
            peakArrivalCount = max(peakArrivalCount, arrivals.count)
        }

        func advance(to time: CFTimeInterval, invalidation: LTXInvalidationContext) -> Bool {
            // Characters that just finished are redrawn once more at full strength.
            for arrival in arrivals {
                invalidation.invalidateCharacters(in: arrival.range)
            }
            arrivals.removeAll { time >= $0.start + duration }
            return !arrivals.isEmpty
        }

        var animatingRange: NSRange? {
            guard var lower = arrivals.first?.range.location else { return nil }
            var upper = lower
            for arrival in arrivals {
                lower = min(lower, arrival.range.location)
                upper = max(upper, NSMaxRange(arrival.range))
            }
            return NSRange(location: lower, length: upper - lower)
        }

        func draw(_ line: LTXAnimatedLine, in context: CGContext, at time: CFTimeInterval) -> Bool {
            drawnLineCount += 1
            var alpha: CGFloat = 1
            for arrival in arrivals where NSIntersectionRange(arrival.range, line.stringRange).length > 0 {
                alpha = min(alpha, CGFloat(max(0, min(1, (time - arrival.start) / duration))))
            }
            context.setAlpha(alpha)
            CTLineDraw(line.line, context)
            return true
        }

        func finish() {
            finishCount += 1
            arrivals.removeAll()
        }
    }

    /// Runs the layout pass the run loop would run, if one is pending, without asking for
    /// one.
    @MainActor
    func layoutIfNeeded(_ view: PlatformView) {
        #if canImport(UIKit)
            view.layoutIfNeeded()
        #elseif canImport(AppKit)
            view.layoutSubtreeIfNeeded()
        #endif
    }

    /// Resizes `label` to the height its text needs at `width`, as a self-sizing cell does,
    /// and lays it out.
    @MainActor
    func sizeToFit(_ label: TextLabelView, width: CGFloat) {
        let size = label.textLayout.sizeThatFits(CGSize(width: width, height: 0))
        label.frame = CGRect(x: 0, y: 0, width: width, height: max(1, size.height.rounded(.up)))
        performLayoutPass(label)
    }

    /// The number of laid-out lines whose box centre lies in `rect`, a view-space rect.
    @MainActor
    func lineCount(in rect: CGRect, of label: TextLabelView) -> Int {
        guard !rect.isNull, let index = (label.textLayout as? LTXAnimatableTextLayout)?.lineIndex else { return 0 }
        var count = 0
        for box in index.rects where rect.contains(CGPoint(x: rect.midX, y: label.viewRect(fromLayoutRect: box).midY)) {
            count += 1
        }
        return count
    }

    /// The subviews that are neither attachment views nor the selection handles a UIKit
    /// label always has: the display link's anchor while the label animates, nothing
    /// otherwise.
    @MainActor
    func extraSubviewCount(_ label: TextLabelView) -> Int {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS)
            let handles: [PlatformView] = [label.selectionHandleStart, label.selectionHandleEnd]
        #else
            let handles: [PlatformView] = []
        #endif
        return label.subviews.count(where: { view in
            !label.attachmentViews.contains(view) && !handles.contains { $0 === view }
        })
    }

#endif
