//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//
//  Stress: the animatable label under a long stream, one huge arrival, random edits and
//  fast cell reuse. Frames are synthetic, 120 per second, and delivered by hand, so the
//  tests measure the label's own work and not the display. See AnimationStressSupport.swift
//  for the quick and full modes.
//

#if !os(watchOS)

    import DisplayLink
    import Foundation
    @testable import Litext
    @testable import LitextAnimation
    import Testing

    #if canImport(UIKit)
        import UIKit
    #elseif canImport(AppKit)
        import AppKit
    #endif

    @MainActor
    @Suite("Stress: animatable label", .tags(.stress), StressMode.enabled, .serialized)
    struct LTXAnimationStressTests {
        private static let frameInterval: CFTimeInterval = 1.0 / 120
        private static let width: CGFloat = 320
        private static let font = PlatformFont.systemFont(ofSize: 15)

        // MARK: - Streaming

        /// Streams a reply in 20-character chunks, one every 50 ms, with six 120 Hz frames
        /// between chunks: 16 KB in the quick mode, 32 KB with LITEXT_STRESS=full. Every frame
        /// must touch a bounded number of lines however long the text grows, lay nothing out,
        /// and leave the label's own backing store alone unless lines start or finish
        /// animating. Most of the time, about 5 s for 16 KB on an Apple silicon Mac, is the
        /// host typesetting the whole reply again for every chunk; the frames themselves get
        /// their own, much smaller budget.
        @Test
        func `a streamed reply redraws only the lines in flight on each frame`() throws {
            let length = StressMode.pick(16 * 1024, full: 32 * 1024)
            let chunkLength = 20
            let framesPerChunk = 6
            let reply = Self.reply(length: length)
            let clock = SyntheticClock(100)
            let animator = FadeAnimator(duration: 0.35)
            let window = makeWindow()
            let label = makeStressLabel(animator: animator, clock: clock)
            addToWindow(label, window)

            // Arrivals live for `duration` and come every `framesPerChunk` frames.
            let arrivalBound = Int((animator.duration / (Double(framesPerChunk) * Self.frameInterval)).rounded(.up)) + 1
            // Eight arrivals of 20 characters span at most five lines of about 40 characters,
            // plus the lines a paragraph break or a cut cluster adds.
            let lineBound = 12
            var frameCount = 0
            var labelRedrawFrames = 0
            var peakInvalidatedLines = 0
            var peakLinesInFlight = 0
            let timer = ContinuousClock()
            var frameTime = Duration.zero

            withinBudget("stream \(length / 1024) KB at 120 Hz", seconds: StressMode.pick(25, full: 100)) {
                var shown = 0
                while shown < reply.length {
                    autoreleasepool {
                        // A stream delivers whole characters, never half a surrogate pair.
                        let end = min(reply.length, shown + chunkLength)
                        shown = end < reply.length ? NSMaxRange(reply.rangeOfComposedCharacterSequence(at: end - 1)) : end
                        label.attributedText = Self.attributed(reply.substring(to: shown))
                        sizeToFit(label, width: Self.width)
                        #expect(label.isAnimating, "chunk ending at \(shown) did not animate")

                        for _ in 0 ..< framesPerChunk {
                            clock.now += Self.frameInterval
                            frameCount += 1
                            let layout = label.textLayout
                            let generation = layout.generation
                            let region = label.animationRegion
                            let labelRequests = label.labelDisplayRequestCount
                            let layerRequests = label.animationLayerDisplayRequestCount

                            let frameStart = timer.now
                            label.displayLinkDidUpdate(frame(at: clock.now))
                            layoutIfNeeded(label)
                            frameTime += timer.now - frameStart

                            #expect(label.textLayout === layout && layout.generation == generation, "frame \(frameCount) laid the text out")
                            let regionMoved = label.animationRegion != region || !label.isAnimating
                            if label.labelDisplayRequestCount != labelRequests {
                                labelRedrawFrames += 1
                                #expect(regionMoved, "frame \(frameCount) redrew the label while the region stayed put")
                            }
                            #expect(label.animationLayerDisplayRequestCount - layerRequests <= 1)

                            let invalidated = lineCount(in: label.invalidation.dirtyRect, of: label)
                            peakInvalidatedLines = max(peakInvalidatedLines, invalidated)
                            if let range = animator.animatingRange,
                               let index = (label.textLayout as? LTXAnimatableTextLayout)?.lineIndex
                            {
                                peakLinesInFlight = max(peakLinesInFlight, index.lines(touching: range).count)
                            }
                            if frameCount % 12 == 0 {
                                drawAnimationLayer(of: label, scale: 1)
                            }
                        }
                    }
                }
            }

            let frameSeconds = Double(frameTime.components.seconds) + Double(frameTime.components.attoseconds) / 1e18
            // About 20-50 µs a frame on an Apple silicon Mac.
            let frameBudget = Double(frameCount) * 0.0002
            print("[stress] \(frameCount) frames took \(String(format: "%.3f", frameSeconds)) s (budget \(String(format: "%.2f", frameBudget)) s)")
            #expect(frameSeconds <= frameBudget, "frames took \(frameSeconds) s, over their \(frameBudget) s budget")
            print("[stress] \(frameCount) frames, \(labelRedrawFrames) redrew the label, peak \(peakInvalidatedLines) invalidated lines, \(peakLinesInFlight) lines and \(animator.peakArrivalCount) arrivals in flight")
            #expect(peakInvalidatedLines <= lineBound)
            #expect(peakLinesInFlight <= lineBound)
            #expect(animator.peakArrivalCount <= arrivalBound)
            #expect(animator.drawnLineCount > 0)
            // The label redraws when an arrival starts or finishes moving the region, at most
            // twice a chunk, and never on the frames in between.
            #expect(labelRedrawFrames <= 2 * frameCount / framesPerChunk)

            label.displayLinkDidUpdate(frame(at: clock.now + 1))
            try expectIdleAndPlain(label)
            #expect(animator.finishCount == 0)
        }

        /// One change brings 10,000 characters at once: every line is in flight, and every
        /// frame redraws all of them in the animation layer without laying anything out.
        @Test
        func `ten thousand characters arriving at once animate without relayout`() throws {
            let clock = SyntheticClock(100)
            let animator = FadeAnimator(duration: 0.35)
            let window = makeWindow()
            let label = makeStressLabel(animator: animator, clock: clock)
            label.attributedText = Self.attributed("Reply:")
            sizeToFit(label, width: Self.width)
            addToWindow(label, window)

            let arrival = Self.attributed("Reply:" + (Self.reply(length: 10000) as String))
            withinBudget("10,000-character arrival", seconds: 2) {
                label.attributedText = arrival
                sizeToFit(label, width: Self.width)
            }
            #expect(label.isAnimating)
            let lines = label.layoutLines.count
            #expect(lineCount(in: label.animationRegion, of: label) >= lines - 1)

            let frames = Int((animator.duration / Self.frameInterval).rounded(.up)) + 2
            var drawn = 0
            withinBudget("\(frames) frames over \(lines) lines", seconds: 4) {
                for step in 0 ..< frames {
                    clock.now += Self.frameInterval
                    let layout = label.textLayout
                    let generation = layout.generation
                    label.displayLinkDidUpdate(frame(at: clock.now))
                    layoutIfNeeded(label)
                    #expect(label.textLayout === layout && layout.generation == generation, "frame \(step) laid the text out")
                    if step % 10 == 0, label.isAnimating {
                        drawAnimationLayer(of: label, scale: 1)
                        drawn += 1
                    }
                }
            }
            #expect(drawn > 0)
            #expect(animator.drawnLineCount >= drawn * (lines - 1))
            try expectIdleAndPlain(label)
        }

        // MARK: - Random edits

        /// Random grow, restyle, shrink, restart, frames, window moves, identity and animator
        /// changes, finishing and unanimated assignments, checking the label's animation
        /// state after every step and its pixels against `TextLabelView` now and then while
        /// idle. 1,000 steps in the quick mode, 10,000 with LITEXT_STRESS=full;
        /// LITEXT_FUZZ_ITERATIONS overrides the count and LITEXT_FUZZ_SEED the seed.
        @Test
        func `random edits keep the animation state consistent`() {
            let steps = StressMode.fuzzIterations(1000, full: 10000)
            let runs = 4
            print("[stress] animation fuzz: \(steps) steps from seed \(StressMode.fuzzSeed)")
            withinBudget("\(steps) random edits", seconds: max(4, Double(steps) * 0.004)) {
                for run in 0 ..< runs {
                    fuzz(seed: StressMode.fuzzSeed &+ UInt64(run), steps: max(1, steps / runs))
                }
            }
        }

        private func fuzz(seed: UInt64, steps: Int) {
            var random = SeededGenerator(seed: seed)
            var stream = TextStream(seed: seed)
            let clock = SyntheticClock(100)
            let window = makeWindow()
            let label = makeStressLabel(animator: FadeAnimator(), clock: clock)
            label.frame = CGRect(x: 0, y: 0, width: Self.width, height: 300)
            label.attributedText = stream.grow()
            addToWindow(label, window)
            performLayoutPass(label)
            var renderChecks = 0
            var animatingSteps = 0

            for step in 0 ..< steps {
                autoreleasepool {
                    let operation: String
                    switch Int.random(in: 0 ..< 20, using: &random) {
                    case 0 ... 5:
                        operation = "grow"
                        label.attributedText = stream.grow()
                    case 6:
                        operation = "restyle"
                        label.attributedText = stream.restyle()
                    case 7:
                        operation = "shrink"
                        label.attributedText = stream.shrink()
                    case 8:
                        operation = "restart"
                        label.attributedText = stream.restart()
                    case 9 ... 12:
                        operation = "frames"
                        for _ in 0 ..< Int.random(in: 1 ... 12, using: &random) {
                            clock.now += Self.frameInterval
                            label.displayLinkDidUpdate(frame(at: clock.now))
                        }
                    case 13:
                        if label.window == nil {
                            operation = "attach"
                            addToWindow(label, window)
                        } else {
                            operation = "detach"
                            label.removeFromSuperview()
                        }
                    case 14:
                        operation = "identity"
                        label.animationIdentity = Int.random(in: 0 ..< 3, using: &random)
                    case 15:
                        operation = "animator"
                        label.animator = Int.random(in: 0 ..< 4, using: &random) == 0
                            ? nil
                            : FadeAnimator(duration: Double.random(in: 0.05 ... 0.6, using: &random))
                    case 16:
                        operation = "finish"
                        label.finishAnimations()
                    case 17:
                        operation = "unanimated"
                        label.setAttributedText(stream.grow(), animated: false)
                    case 18:
                        operation = "resize"
                        label.frame = CGRect(
                            x: 0,
                            y: 0,
                            width: CGFloat.random(in: 120 ... 400, using: &random),
                            height: CGFloat.random(in: 100 ... 400, using: &random),
                        )
                    default:
                        operation = "stall"
                        clock.now += Double.random(in: 0.2 ... 2, using: &random)
                        label.displayLinkDidUpdate(frame(at: clock.now))
                    }
                    layoutIfNeeded(label)
                    let name = "seed \(seed) step \(step) \(operation)"
                    expectAnimationStateConsistent(label, name)
                    if label.isAnimating {
                        animatingSteps += 1
                    }
                    if step % 25 == 0, !label.isAnimating {
                        expectRendersLikePlainLabel(label, name)
                        renderChecks += 1
                    }
                }
            }
            print("[stress] seed \(seed): animating after \(animatingSteps) of \(steps) steps, \(renderChecks) render checks")
            #expect(renderChecks > 0, "seed \(seed): never idle at a render check")
            #expect(animatingSteps > 0, "seed \(seed): never animated")

            clock.now += 10
            label.displayLinkDidUpdate(frame(at: clock.now))
            #expect(!label.isAnimating, "seed \(seed): still animating after the last arrival ended")
            expectAnimationStateConsistent(label, "seed \(seed) end")
        }

        // MARK: - Cell reuse

        /// Scrolls 100 messages through eight visible cells, reusing the cells that leave
        /// the window, while the newest message and a random visible one keep streaming.
        /// Only cells in the window may hold a display link, cells leave without one, and
        /// every cell and animator is released afterwards. 3 passes in the quick mode, 30
        /// with LITEXT_STRESS=full.
        @Test
        func `reused cells hold display links only while visible and release everything`() {
            let passes = StressMode.pick(3, full: 30)
            let itemCount = 100
            let visibleCount = 8
            let clock = SyntheticClock(100)
            let window = makeWindow()
            var random = SeededGenerator(seed: StressMode.fuzzSeed)
            var labelBoxes: [WeakBox<LTXAnimatableLabel>] = []
            var animatorBoxes: [WeakBox<FadeAnimator>] = []
            var peakLinks = 0

            withinBudget("\(passes) passes over \(itemCount) reused cells", seconds: StressMode.pick(4, full: 40)) {
                for _ in 0 ..< passes {
                    autoreleasepool {
                        var items = (0 ..< itemCount).map { "Message \($0):" }
                        var visible: [(label: LTXAnimatableLabel, item: Int)] = []
                        var spare: [LTXAnimatableLabel] = []
                        var created: [LTXAnimatableLabel] = []

                        for item in 0 ..< itemCount {
                            // Scroll by one row: the top cell leaves and is queued for reuse.
                            if visible.count == visibleCount {
                                let top = visible.removeFirst().label
                                top.removeFromSuperview()
                                #expect(!top.isAnimating && top.displayLink == nil, "a cell left the window animating")
                                #expect(extraSubviewCount(top) == 0)
                                spare.append(top)
                            }
                            let cell: LTXAnimatableLabel
                            if let reused = spare.popLast() {
                                cell = reused
                            } else {
                                let animator = FadeAnimator(duration: 0.2)
                                cell = makeStressLabel(animator: animator, clock: clock)
                                created.append(cell)
                                animatorBoxes.append(WeakBox(animator))
                            }
                            cell.animationIdentity = item
                            cell.attributedText = Self.attributed(items[item])
                            cell.frame = CGRect(x: 0, y: CGFloat(visible.count) * 44, width: Self.width, height: 44)
                            addToWindow(cell, window)
                            performLayoutPass(cell)
                            #expect(!cell.isAnimating, "a reused cell animated its new item")
                            visible.append((cell, item))

                            // The newest message streams, and so does a random visible one.
                            let streaming = [visible.count - 1, Int.random(in: 0 ..< visible.count, using: &random)]
                            for slot in Set(streaming) {
                                let entry = visible[slot]
                                items[entry.item] += " more"
                                entry.label.attributedText = Self.attributed(items[entry.item])
                                performLayoutPass(entry.label)
                            }

                            let cells = visible.map(\.label) + spare
                            for _ in 0 ..< 3 {
                                clock.now += Self.frameInterval
                                for cell in cells where cell.displayLink != nil {
                                    cell.displayLinkDidUpdate(frame(at: clock.now))
                                }
                            }
                            let linked = cells.filter { $0.displayLink != nil }
                            peakLinks = max(peakLinks, linked.count)
                            #expect(linked.count <= visible.count)
                            #expect(linked.allSatisfy { $0.window != nil }, "a cell out of the window holds a link")
                            for cell in cells {
                                #expect(extraSubviewCount(cell) == (cell.isAnimating ? 1 : 0))
                            }
                        }

                        for entry in visible {
                            entry.label.removeFromSuperview()
                        }
                        for cell in created {
                            #expect(cell.displayLink == nil && !cell.isAnimating)
                            #expect(cell.animationLayer == nil)
                            labelBoxes.append(WeakBox(cell))
                        }
                    }
                }
            }

            evictCoreTextLastTypesetAttributes()
            print("[stress] \(labelBoxes.count) cells, at most \(peakLinks) display links at once")
            #expect(peakLinks >= 1)
            #expect(labelBoxes.count(where: { $0.value != nil }) == 0, "cells outlived their table")
            #expect(animatorBoxes.count(where: { $0.value != nil }) == 0, "animators outlived their cells")
        }

        // MARK: - Helpers

        private func makeStressLabel(animator: FadeAnimator, clock: SyntheticClock) -> LTXAnimatableLabel {
            let label = LTXAnimatableLabel(frame: CGRect(x: 0, y: 0, width: Self.width, height: 40))
            label.clock = { clock.now }
            label.reducedMotionOverride = false
            label.animator = animator
            return label
        }

        /// The state the label must keep however it got there.
        private func expectAnimationStateConsistent(
            _ label: LTXAnimatableLabel,
            _ step: String,
            sourceLocation: SourceLocation = #_sourceLocation,
        ) {
            #expect(label.isAnimating == (label.displayLink != nil), "\(step): link and isAnimating disagree", sourceLocation: sourceLocation)
            if label.isAnimating {
                #expect(label.animator != nil, "\(step): animating without an animator", sourceLocation: sourceLocation)
                #expect(label.window != nil, "\(step): animating out of a window", sourceLocation: sourceLocation)
                #expect(extraSubviewCount(label) == 1, "\(step): not exactly one link anchor", sourceLocation: sourceLocation)
            } else {
                #expect(label.animationLayer == nil, "\(step): animation layer while idle", sourceLocation: sourceLocation)
                #expect(label.animationRegion.isNull, "\(step): animation region while idle", sourceLocation: sourceLocation)
                #expect(extraSubviewCount(label) == 0, "\(step): extra subviews while idle", sourceLocation: sourceLocation)
            }
            if let layer = label.animationLayer {
                #expect(layer.superlayer === hostLayer(label), "\(step): layer detached", sourceLocation: sourceLocation)
                #expect(
                    layer.isHidden || layer.region == label.animationRegion,
                    "\(step): layer region \(layer.region) is not \(label.animationRegion)",
                    sourceLocation: sourceLocation,
                )
            }
            #expect(
                label.textLayout.attributedString.isEqual(to: label.attributedText),
                "\(step): layout text differs from attributedText",
                sourceLocation: sourceLocation,
            )
            if let fade = label.animator as? FadeAnimator {
                let length = label.attributedText.length
                #expect(
                    fade.arrivals.allSatisfy { $0.range.location >= 0 && NSMaxRange($0.range) <= length },
                    "\(step): an arrival reaches past length \(length)",
                    sourceLocation: sourceLocation,
                )
            }
        }

        /// Compares an idle label's pixels with a `TextLabelView` showing the same text.
        private func expectRendersLikePlainLabel(
            _ label: LTXAnimatableLabel,
            _ step: String,
            sourceLocation: SourceLocation = #_sourceLocation,
        ) {
            guard label.bounds.width >= 1, label.bounds.height >= 1 else { return }
            let plain = TextLabelView(attributedText: withoutAttachmentViews(label.attributedText))
            plain.frame = label.bounds
            performLayoutPass(plain)
            #expect(
                renderedBytes(label, scale: 1) == renderedBytes(plain, scale: 1),
                "\(step): idle label draws unlike TextLabelView",
                sourceLocation: sourceLocation,
            )
        }

        /// An animation that ran to its end leaves the label as a plain `TextLabelView`.
        private func expectIdleAndPlain(_ label: LTXAnimatableLabel, sourceLocation: SourceLocation = #_sourceLocation) throws {
            #expect(!label.isAnimating, sourceLocation: sourceLocation)
            #expect(label.displayLink == nil, sourceLocation: sourceLocation)
            #expect(label.animationLayer == nil, sourceLocation: sourceLocation)
            #expect(extraSubviewCount(label) == 0, sourceLocation: sourceLocation)
            expectRendersLikePlainLabel(label, "after the animation", sourceLocation: sourceLocation)
        }

        /// A reply of `length` UTF-16 units: sentences of mixed scripts in paragraphs of a
        /// few hundred characters, the way a chat answer arrives.
        private static func reply(length: Int) -> NSString {
            let sentences = [
                "Litext lays the reply out as it streams in. ",
                "Each chunk fades in while the rest stays still. ",
                "中文的句子也会逐字出现。",
                "مرحبا بالعالم، هذا نص عربي. ",
                "Emoji like 👩‍💻 and 🇯🇵 arrive whole. ",
                "Combining marks such as e\u{301} stay attached. ",
            ]
            var random = SeededGenerator(seed: 0xA11CE)
            let text = NSMutableString()
            var paragraph = 0
            while text.length < length {
                text.append(sentences.randomElement(using: &random)!)
                paragraph += 1
                if paragraph == 8 {
                    text.append("\n")
                    paragraph = 0
                }
            }
            return text
        }

        private static func attributed(_ string: String) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [.font: font])
        }
    }

#endif
