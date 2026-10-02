//
//  CustomAnimatorPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  A complete LTXTextAnimator in one small class: a typewriter that types
//  inserted text out one character at a time behind a caret. It shows each
//  part of the protocol: animateChange(_:at:) starts a timeline,
//  advance(to:invalidation:) moves it and names the lines to redraw,
//  animatingRange picks the lines the animator draws, draw(_:in:at:) draws
//  them, overdrawInsets makes room for the caret, and finish() ends it all.
//

import CoreText
import Litext
import LitextAnimation
import QuartzCore
import SwiftUI

struct CustomAnimatorPage: View {
    /// The animator below, without the page's readout hooks and slow motion.
    private static let code = """
    final class TypewriterAnimator: LTXTextAnimator {
        var charactersPerSecond = 30.0
        var caretColor = PlatformColor.systemBlue.cgColor

        private var string: NSString = ""
        private var start = 0          // where the typed text begins
        private var typed = 0          // the first character not shown yet
        private var end = 0            // the end of the text to type
        private var origin: (time: CFTimeInterval, offset: Int) = (0, 0)
        private static let overhang: CGFloat = 2

        func animateChange(_ context: LTXAnimationContext, at time: CFTimeInterval) {
            let change = context.change
            string = context.layout.attributedString.string as NSString
            // Reduced motion: show the text at once.
            guard !context.prefersReducedMotion, change.hasInsertion else {
                return finish()
            }
            if typed < end, change.isAppend {
                end = change.length        // keep typing, now further
            } else {
                start = change.insertedRange.location
                typed = start
                end = NSMaxRange(change.insertedRange)
                origin = (time, typed)
            }
        }

        func advance(to time: CFTimeInterval, invalidation: LTXInvalidationContext) -> Bool {
            guard typed < end else { return false }
            let next = typedOffset(at: time)
            if next != typed {
                // The lines from the old caret to the new one.
                invalidation.invalidateCharacters(in: NSRange(location: typed, length: next - typed))
                invalidation.invalidateCharacters(in: NSRange(location: next, length: 0))
                typed = next
            }
            return typed < end
        }

        // Every line of the typed text, not only the caret's: a range that
        // stays put keeps the animation region still while typing.
        var animatingRange: NSRange? {
            typed < end ? NSRange(location: start, length: end - start) : nil
        }

        // The caret reaches a little above and below the line's box.
        var overdrawInsets: LTXInsets {
            LTXInsets(top: Self.overhang, left: 1, bottom: Self.overhang, right: 2)
        }

        func draw(_ line: LTXAnimatedLine, in context: CGContext, at _: CFTimeInterval) -> Bool {
            let lineStart = line.stringRange.location
            let lineEnd = NSMaxRange(line.stringRange)
            let hiddenStart = max(typed, lineStart)
            let hiddenEnd = min(end, lineEnd)
            let hasCaret = typed >= lineStart && (typed < lineEnd || typed == string.length)
            guard hiddenStart < hiddenEnd || hasCaret else { return false }

            let x = line.baselineOrigin.x
            let hideFrom = x + CTLineGetOffsetForStringIndex(line.line, hiddenStart, nil)
            if hasCaret {
                context.setFillColor(caretColor)
                context.fill(CGRect(
                    x: hideFrom - 1,
                    y: line.rect.minY - Self.overhang,
                    width: 2,
                    height: line.rect.height + Self.overhang * 2,
                ))
            }
            // Draw the line clipped to what is typed, before and after the gap.
            let band = line.rect.insetBy(dx: 0, dy: -line.rect.height)
            var visible = [CGRect(x: band.minX - 1000, y: band.minY, width: hideFrom - band.minX + 1000, height: band.height)]
            if hiddenEnd < lineEnd {
                let showFrom = x + CTLineGetOffsetForStringIndex(line.line, hiddenEnd, nil)
                visible.append(CGRect(x: showFrom, y: band.minY, width: 100_000, height: band.height))
            }
            context.clip(to: visible)
            CTLineDraw(line.line, context)
            return true
        }

        func finish() {
            typed = end
        }

        private func typedOffset(at time: CFTimeInterval) -> Int {
            let count = Int((time - origin.time) * charactersPerSecond)
            let offset = origin.offset + max(count, 0)
            guard offset < end else { return end }
            // Never stop inside a character the reader sees as one.
            return string.rangeOfComposedCharacterSequence(at: offset).location
        }
    }

    label.animator = TypewriterAnimator()
    label.attributedText = text   // the new text types out
    """

    var body: some View {
        #if os(tvOS)
            CatalogUnavailableView(page: .customAnimator, reason: "The animation pages need sliders and toggles, which tvOS does not have.")
        #else
            CustomAnimatorDemoView(code: Self.code)
        #endif
    }
}

#if !os(tvOS)

    // MARK: - The animator

    /// Types inserted text out one character at a time, behind a caret.
    ///
    /// Left-to-right text only: the clip between typed and untyped text is a horizontal
    /// cut, which a line that mixes directions would place wrongly.
    @MainActor
    final class TypewriterAnimator: LTXTextAnimator {
        var charactersPerSecond = 30.0 {
            didSet { rebaseTiming() }
        }

        var caretColor = PlatformColor.systemBlue.cgColor
        /// Plays the effect slower (below 1) or faster (above 1), for inspecting it.
        var speed = 1.0 {
            didSet { rebaseTiming() }
        }

        /// Reports each change the animator receives, for the page's readout.
        var onChange: ((LTXTextChange) -> Void)?
        /// Reports each frame: whether it moved the caret, and the range in flight.
        var onFrame: ((_ movedCaret: Bool, _ animatingRange: NSRange?) -> Void)?

        private var string: NSString = ""
        /// Where the typed text begins.
        private var start = 0
        /// The first character not shown yet.
        private var typed = 0
        /// The end of the text to type.
        private var end = 0
        /// The time and offset the typing speed counts from.
        private var origin: (time: CFTimeInterval, offset: Int) = (0, 0)
        private static let overhang: CGFloat = 2

        func animateChange(_ context: LTXAnimationContext, at time: CFTimeInterval) {
            let change = context.change
            onChange?(change)
            string = context.layout.attributedString.string as NSString
            // Reduced motion: show the text at once.
            guard !context.prefersReducedMotion, change.hasInsertion else {
                finish()
                return
            }
            if typed < end, change.isAppend {
                // More text while typing: keep the caret where it is and type further.
                end = change.length
            } else {
                start = change.insertedRange.location
                typed = start
                end = NSMaxRange(change.insertedRange)
                origin = (time, typed)
            }
        }

        func advance(to time: CFTimeInterval, invalidation: LTXInvalidationContext) -> Bool {
            guard typed < end else {
                onFrame?(false, nil)
                return false
            }
            let next = typedOffset(at: time)
            let moved = next != typed
            if moved {
                // The lines from the old caret to the new one: an empty range redraws the
                // line its location sits on.
                invalidation.invalidateCharacters(in: NSRange(location: typed, length: next - typed))
                invalidation.invalidateCharacters(in: NSRange(location: next, length: 0))
                typed = next
            }
            onFrame?(moved, animatingRange)
            return typed < end
        }

        /// Every line of the typed text, not only the caret's: a range that stays put keeps
        /// the animation region still while typing, so only the invalidated lines redraw.
        var animatingRange: NSRange? {
            typed < end ? NSRange(location: start, length: end - start) : nil
        }

        /// The caret reaches a little above and below the line's box.
        var overdrawInsets: LTXInsets {
            LTXInsets(top: Self.overhang, left: 1, bottom: Self.overhang, right: 2)
        }

        // additionalContentBounds keeps its default, .null: everything this animator
        // draws lies on the lines in flight.

        func draw(_ line: LTXAnimatedLine, in context: CGContext, at _: CFTimeInterval) -> Bool {
            let lineStart = line.stringRange.location
            let lineEnd = NSMaxRange(line.stringRange)
            let hiddenStart = max(typed, lineStart)
            let hiddenEnd = min(end, lineEnd)
            let hasCaret = typed >= lineStart && (typed < lineEnd || typed == string.length)
            guard hiddenStart < hiddenEnd || hasCaret else { return false }

            let x = line.baselineOrigin.x
            let hideFrom = x + CTLineGetOffsetForStringIndex(line.line, hiddenStart, nil)
            if hasCaret {
                context.setFillColor(caretColor)
                context.fill(CGRect(
                    x: hideFrom - 1,
                    y: line.rect.minY - Self.overhang,
                    width: 2,
                    height: line.rect.height + Self.overhang * 2,
                ))
            }
            // Draw the line clipped to what is typed, before and after the gap.
            let band = line.rect.insetBy(dx: 0, dy: -line.rect.height)
            var visible = [CGRect(
                x: band.minX - 1000,
                y: band.minY,
                width: hideFrom - band.minX + 1000,
                height: band.height,
            )]
            if hiddenEnd < lineEnd {
                let showFrom = x + CTLineGetOffsetForStringIndex(line.line, hiddenEnd, nil)
                visible.append(CGRect(x: showFrom, y: band.minY, width: 100_000, height: band.height))
            }
            context.clip(to: visible)
            CTLineDraw(line.line, context)
            return true
        }

        func finish() {
            typed = end
        }

        /// Counts the new speed from the caret's current place, so it does not jump.
        private func rebaseTiming() {
            origin = (CACurrentMediaTime(), typed)
        }

        private func typedOffset(at time: CFTimeInterval) -> Int {
            let count = Int((time - origin.time) * charactersPerSecond * speed)
            let offset = origin.offset + max(count, 0)
            guard offset < end else { return end }
            // Never stop inside a character the reader sees as one.
            return string.rangeOfComposedCharacterSequence(at: offset).location
        }
    }

    // MARK: - Page

    @MainActor
    @Observable
    final class CustomAnimatorModel {
        static let lines = [
            "A typewriter is a complete LTXTextAnimator in about a hundred lines.",
            "Each frame moves the caret and redraws only the lines it crossed.",
            "Text added while it types joins the queue; the caret keeps going.",
        ]

        let driver = AnimatableLabelDriver()
        let animator = TypewriterAnimator()
        var charactersPerSecond = 30.0 {
            didSet { animator.charactersPerSecond = charactersPerSecond }
        }

        var showsCaret = true {
            didSet { animator.caretColor = Self.caretColor(showsCaret) }
        }

        private(set) var lastChange: LTXTextChange?
        private(set) var animatingRange: NSRange?
        private(set) var frames = 0
        private(set) var caretMoves = 0
        private var count = 1
        private var hasAside = false

        init() {
            animator.onChange = { [weak self] change in
                self?.lastChange = change
                self?.frames = 0
                self?.caretMoves = 0
            }
            animator.onFrame = { [weak self] moved, range in
                guard let self else { return }
                frames += 1
                if moved {
                    caretMoves += 1
                }
                if range != animatingRange {
                    animatingRange = range
                }
            }
        }

        var text: NSAttributedString {
            var lines = (0 ..< count).map { Self.lines[$0 % Self.lines.count] }
            if hasAside {
                lines[0] = lines[0].replacingOccurrences(of: "is a complete", with: "is, as you can see, a complete")
            }
            return AnimationPageText.render(lines.joined(separator: "\n"))
        }

        func makeLabel() -> LTXAnimatableLabel {
            let label = LTXAnimatableLabel()
            label.animator = animator
            label.attributedText = text
            return label
        }

        func typeNextLine() {
            count += 1
            driver.setText(text)
        }

        func insertAside() {
            hasAside.toggle()
            driver.setText(text)
        }

        func finish() {
            driver.update { $0.finishAnimations() }
            animatingRange = nil
        }

        func reset() {
            count = 1
            hasAside = false
            driver.setText(text, animated: false)
            animatingRange = nil
        }

        private static func caretColor(_ isShown: Bool) -> CGColor {
            isShown ? PlatformColor.systemBlue.cgColor : PlatformColor.clear.cgColor
        }
    }

    struct CustomAnimatorDemoView: View {
        let code: String
        @State private var model = CustomAnimatorModel()
        @State private var isSlowMotion = CatalogLaunchOptions.current.isSlowMotion

        var body: some View {
            CatalogPageScaffold(.customAnimator, code: code) {
                VStack(alignment: .leading, spacing: 16) {
                    DrivenAnimatableLabel(driver: model.driver) {
                        model.makeLabel()
                    }
                    .frame(minHeight: 80, alignment: .topLeading)
                    .accessibilityIdentifier("demo.customAnimator.label")

                    HStack(spacing: 8) {
                        Button("Type a Line") { model.typeNextLine() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("demo.customAnimator.type")
                        Button("Insert") { model.insertAside() }
                            .accessibilityIdentifier("demo.customAnimator.insert")
                        Button("Finish") { model.finish() }
                            .accessibilityIdentifier("demo.customAnimator.finish")
                        Button("Reset") { model.reset() }
                            .accessibilityIdentifier("demo.customAnimator.reset")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } controls: {
                CatalogSlider("Typing speed", value: $model.charactersPerSecond, in: 5 ... 120, step: 5) {
                    "\(Int($0)) chars/s"
                }
                Toggle("Caret", isOn: $model.showsCaret)
                Toggle("Slow Motion", isOn: $isSlowMotion)
                CatalogReadout(
                    "animatingRange",
                    value: model.animatingRange.map(NSStringFromRange) ?? "nil",
                    identifier: "state.customAnimator.range",
                )
                CatalogReadout(
                    "Frames / caret moves",
                    value: "\(model.frames) / \(model.caretMoves)",
                    identifier: "state.customAnimator.frames",
                )
                CatalogReadout("isAnimating", value: model.driver.isAnimating ? "true" : "false", identifier: "state.customAnimator.isAnimating")
                if let change = model.lastChange {
                    CatalogReadout("Last change", value: "\(change.previousLength) → \(change.length)")
                    CatalogReadout(
                        "Inserted / removed",
                        value: "\(NSStringFromRange(change.insertedRange)) / \(NSStringFromRange(change.removedRange))",
                        identifier: "state.customAnimator.change",
                    )
                    FlagGrid(flags: [
                        ("isAppend", change.isAppend),
                        ("isReplacement", change.isReplacement),
                        ("hasInsertion", change.hasInsertion),
                        ("hasRemoval", change.hasRemoval),
                    ])
                }
                CatalogNote(
                    "A frame where the caret does not move invalidates nothing, so nothing is drawn. Insert adds words in the middle of the first line: only those type out, and the text after them stays visible on both sides of the gap. The clip is a horizontal cut, so this animator suits left-to-right text.",
                    systemImage: "info.circle",
                )
            }
            .onChange(of: isSlowMotion, initial: true) { _, isSlow in
                model.animator.speed = isSlow ? CatalogLaunchOptions.slowMotionSpeed : 1
            }
        }
    }

#endif
