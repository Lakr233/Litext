//
//  FadeInAnimator.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  A reference LTXTextAnimator for streamed text: each chunk fades in, one
//  character or word after another. FadeUpAnimator, at the end of the file,
//  adds a small rise.
//

import CoreGraphics
import CoreText
import Foundation
import Litext
import LitextAnimation
import QuartzCore

#if !os(watchOS)

    /// Fades in text as it arrives, staggered by character or word.
    ///
    /// ```swift
    /// label.animator = FadeInAnimator()
    /// label.attributedText = streamedSoFar   // only the new characters fade in
    /// ```
    ///
    /// How it stays cheap:
    ///
    /// - It keeps one *batch* per animated change: the inserted range, its start time and
    ///   the offsets where its units start. At most `maxBatches` are in flight; the oldest,
    ///   nearly opaque by then, finishes early when a fast stream exceeds that.
    /// - Opacity is quantized to `alphaLevels` steps. A frame invalidates a batch's lines
    ///   only when one of its units moved to another step, so the slow tail of the curve
    ///   costs nothing.
    /// - A line in flight is drawn run by run: each run is cut into stretches of glyphs at
    ///   the same step, and each stretch is drawn with `CTRunDraw` at its own alpha. Text
    ///   that has finished on the same line is drawn opaque, so it never flickers.
    /// - Lines with an underline or strikethrough fall back to drawing the whole line
    ///   once per stretch, clipped to that stretch, so the decoration fades with its text
    ///   instead of being drawn twice where stretches meet.
    ///
    /// Reduced motion keeps a short, plain fade: no stagger and no rise.
    @MainActor
    class FadeInAnimator: LTXTextAnimator {
        /// How the effect looks. Changes apply to text that arrives afterwards.
        struct Configuration {
            /// How long one unit takes to fade in, in seconds.
            var duration: Double = 0.32
            /// The units that start one after another.
            var granularity: TextUnitGranularity = .cluster
            /// The delay between units, capped for the whole chunk.
            var stagger = StaggerSchedule(interval: 0.014, maxTotalDelay: 0.16)
            /// The opacity curve over `duration`.
            var curve: CubicBezierCurve = .easeOut
            /// How far below its place a unit starts, in points. Zero for a plain fade.
            var rise: CGFloat = 0
            /// The opacity steps; see ``AlphaQuantizer``.
            var alphaLevels = 32
            /// The most changes animating at once.
            var maxBatches = 24
            /// The most stagger steps in one change; longer changes group their units.
            var maxUnitsPerBatch = 48
        }

        var configuration: Configuration {
            didSet { quantizer = AlphaQuantizer(levels: configuration.alphaLevels) }
        }

        /// Plays the effect slower (below 1) or faster (above 1), for inspecting it.
        var speed: Double = 1

        init(configuration: Configuration = Configuration()) {
            self.configuration = configuration
            quantizer = AlphaQuantizer(levels: configuration.alphaLevels)
        }

        // MARK: - Timeline

        /// One animated change: the characters it inserted and when each unit starts.
        struct Batch {
            /// The inserted characters, in UTF-16 offsets of the label's text.
            var range: NSRange
            /// Where each unit starts, ascending; the first is `range.location`.
            var unitStarts: [Int]
            /// When the first unit starts.
            let startTime: CFTimeInterval
            /// The delay between neighbouring units.
            let interval: Double
            let duration: Double
            let rise: CGFloat
            /// The sum of the units' opacity steps at the last frame. Steps only grow, so
            /// the sum changes exactly when some unit's step does.
            var levelSum = -1
        }

        private var quantizer: AlphaQuantizer

        /// The batches in flight, sorted by location; their ranges never overlap.
        private(set) var batches: [Batch] = []
        private var cachedAnimatingRange: NSRange?

        /// The last batch a glyph was found in. Glyphs are looked up in text order, so the
        /// next glyph is almost always in the same batch.
        private var lookupHint = 0

        // Buffers reused for runs whose glyph data CoreText cannot hand out directly.
        private var indexBuffer: [CFIndex] = []
        private var positionBuffer: [CGPoint] = []
        private var advanceBuffer: [CGSize] = []
        private var bandBuffer: [Band] = []

        // MARK: - LTXTextAnimator

        func animateChange(_ context: LTXAnimationContext, at time: CFTimeInterval) {
            let change = context.change
            remapBatches(through: change)
            if change.hasInsertion {
                addBatch(for: change.insertedRange, in: context, at: time)
            }
            updateAnimatingRange()
        }

        func advance(to time: CFTimeInterval, invalidation: LTXInvalidationContext) -> Bool {
            let fullSum = quantizer.levels
            var index = 0
            while index < batches.count {
                let sum = levelSum(of: batches[index], at: time)
                if sum != batches[index].levelSum {
                    batches[index].levelSum = sum
                    invalidation.invalidateCharacters(in: batches[index].range)
                }
                if sum == fullSum * batches[index].unitStarts.count {
                    // Every unit is opaque: the label draws these lines from now on.
                    batches.remove(at: index)
                    updateAnimatingRange()
                } else {
                    index += 1
                }
            }
            return !batches.isEmpty
        }

        var animatingRange: NSRange? {
            cachedAnimatingRange
        }

        var overdrawInsets: LTXInsets {
            // A rising unit starts below its line.
            LTXInsets(top: 0, left: 0, bottom: configuration.rise.rounded(.up), right: 0)
        }

        func finish() {
            batches.removeAll()
            cachedAnimatingRange = nil
        }

        func draw(_ line: LTXAnimatedLine, in context: CGContext, at time: CFTimeInterval) -> Bool {
            guard let range = cachedAnimatingRange, NSIntersectionRange(range, line.stringRange).length > 0
                || NSLocationInRange(line.stringRange.location, range)
            else { return false }
            let runs = CTLineGetGlyphRuns(line.line)
            let runCount = CFArrayGetCount(runs)
            // A renderer may draw behind the glyphs, which only whole-line drawing fades.
            if line.lineRenderer != nil || Self.hasDecoration(runs, count: runCount) {
                drawBanded(line, runs: runs, runCount: runCount, in: context, at: time)
                return true
            }
            for runIndex in 0 ..< runCount {
                let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, runIndex), to: CTRun.self)
                drawRun(run, origin: line.baselineOrigin, in: context, at: time)
            }
            return true
        }

        // MARK: - Batches

        private func addBatch(for range: NSRange, in context: LTXAnimationContext, at time: CFTimeInterval) {
            let reduced = context.prefersReducedMotion
            let string = context.layout.attributedString.string as NSString
            let starts = reduced
                ? [range.location]
                : TextUnits.starts(
                    in: string,
                    range: range,
                    granularity: configuration.granularity,
                    maxCount: configuration.maxUnitsPerBatch,
                )
            var interval = configuration.stagger.interval(forUnitCount: starts.count)
            let position = batches.firstIndex { $0.range.location > range.location } ?? batches.count
            var startTime = time
            if !reduced, position > 0, speed > 0 {
                // Carry on the stagger of the text just before, so a chunk never shows
                // ahead of the previous one. A fast stream would pile that delay up, so a
                // chunk that would end more than `maxTotalDelay` after it arrived
                // compresses its own stagger instead; the lag stays bounded and the order
                // is kept.
                let previous = batches[position - 1]
                let previousLast = previous.startTime
                    + Double(previous.unitStarts.count - 1) * previous.interval / speed
                startTime = max(time, previousLast + max(interval, previous.interval) / speed)
                if starts.count > 1 {
                    let latest = time + configuration.stagger.maxTotalDelay / speed
                    let room = max(latest - startTime, 0) * speed
                    interval = min(interval, room / Double(starts.count - 1))
                }
            }
            let batch = Batch(
                range: range,
                unitStarts: starts,
                startTime: startTime,
                interval: interval,
                duration: max(reduced ? min(configuration.duration, 0.2) : configuration.duration, 0.01),
                rise: reduced ? 0 : max(configuration.rise, 0),
            )
            batches.insert(batch, at: position)
            // A fast stream finishes its oldest change early; it is nearly opaque by then.
            while batches.count > max(configuration.maxBatches, 1) {
                guard let oldest = batches.indices.min(by: { batches[$0].startTime < batches[$1].startTime })
                else { break }
                batches.remove(at: oldest)
            }
        }

        /// Moves the batches with the text: kept in the common prefix, shifted in the common
        /// suffix, cut where the change replaced their characters.
        private func remapBatches(through change: LTXTextChange) {
            guard !batches.isEmpty, !change.isTextUnchanged else { return }
            let prefix = change.commonPrefixLength
            let suffixStart = change.previousLength - change.commonSuffixLength
            let delta = change.length - change.previousLength
            batches = batches.compactMap { batch in
                var batch = batch
                let end = NSMaxRange(batch.range)
                if end <= prefix {
                    return batch
                }
                if batch.range.location >= suffixStart {
                    batch.range.location += delta
                    batch.unitStarts = batch.unitStarts.map { $0 + delta }
                    return batch
                }
                guard batch.range.location < prefix else { return nil }
                // Keep the part before the change; the rest of the batch was replaced.
                batch.range.length = prefix - batch.range.location
                batch.unitStarts = batch.unitStarts.filter { $0 < prefix }
                batch.levelSum = -1
                return batch
            }
        }

        private func updateAnimatingRange() {
            lookupHint = 0
            guard let first = batches.first else {
                cachedAnimatingRange = nil
                return
            }
            let end = batches.map { NSMaxRange($0.range) }.max() ?? NSMaxRange(first.range)
            cachedAnimatingRange = NSRange(location: first.range.location, length: end - first.range.location)
        }

        // MARK: - Opacity

        /// The opacity step of unit `unit` of `batch` at `time`.
        ///
        /// - Important: Performance-sensitive. Runs per unit per frame and per stretch of
        ///   glyphs while drawing.
        func level(ofUnit unit: Int, in batch: Batch, at time: CFTimeInterval) -> Int {
            let elapsed = (time - batch.startTime) * speed - Double(unit) * batch.interval
            guard elapsed > 0 else { return 0 }
            guard elapsed < batch.duration else { return quantizer.levels }
            return quantizer.level(for: configuration.curve.value(at: elapsed / batch.duration))
        }

        private func levelSum(of batch: Batch, at time: CFTimeInterval) -> Int {
            var sum = 0
            for unit in batch.unitStarts.indices {
                sum += level(ofUnit: unit, in: batch, at: time)
            }
            return sum
        }

        /// How the glyph for the character at `offset` looks: its opacity step and how far
        /// below its place it is. Characters outside every batch are opaque and in place.
        private func appearance(ofCharacterAt offset: Int, at time: CFTimeInterval) -> Appearance {
            guard let batchIndex = batchIndex(containing: offset) else {
                return Appearance(level: quantizer.levels, drop: 0)
            }
            let batch = batches[batchIndex]
            let unit = Self.lastIndex(in: batch.unitStarts, notAfter: offset)
            let level = level(ofUnit: unit, in: batch, at: time)
            guard batch.rise > 0, level < quantizer.levels else {
                return Appearance(level: level, drop: 0)
            }
            // The rise follows the quantized opacity, so a stretch moves as one piece and
            // settles exactly when it becomes opaque.
            let remaining = 1 - quantizer.alpha(forLevel: level)
            return Appearance(level: level, drop: batch.rise * remaining)
        }

        private func batchIndex(containing offset: Int) -> Int? {
            if lookupHint < batches.count, NSLocationInRange(offset, batches[lookupHint].range) {
                return lookupHint
            }
            var low = 0
            var high = batches.count
            while low < high {
                let mid = (low + high) / 2
                if NSMaxRange(batches[mid].range) <= offset {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            guard low < batches.count, NSLocationInRange(offset, batches[low].range) else { return nil }
            lookupHint = low
            return low
        }

        /// The index of the last element of the ascending `values` that is at most
        /// `value`, or 0.
        private static func lastIndex(in values: [Int], notAfter value: Int) -> Int {
            var low = 0
            var high = values.count
            while low < high {
                let mid = (low + high) / 2
                if values[mid] <= value {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            return max(low - 1, 0)
        }

        // MARK: - Drawing

        private struct Appearance: Equatable {
            var level: Int
            var drop: CGFloat
        }

        /// Draws one run as stretches of glyphs that share an appearance.
        ///
        /// - Important: Performance-sensitive. One lookup per glyph, one `CTRunDraw` per
        ///   stretch; nothing allocates once the buffers have grown.
        private func drawRun(_ run: CTRun, origin: CGPoint, in context: CGContext, at time: CFTimeInterval) {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { return }
            withStringIndices(of: run, count: count) { indices in
                var stretchStart = 0
                var current = appearance(ofCharacterAt: indices[0], at: time)
                for glyph in 1 ... count {
                    let next = glyph < count ? appearance(ofCharacterAt: indices[glyph], at: time) : nil
                    guard next != current else { continue }
                    if current.level > 0 {
                        context.setAlpha(quantizer.alpha(forLevel: current.level))
                        // Layout space has y pointing up, so a drop moves the glyphs down.
                        context.textPosition = CGPoint(x: origin.x, y: origin.y - current.drop)
                        CTRunDraw(run, context, CFRange(location: stretchStart, length: glyph - stretchStart))
                    }
                    if let next {
                        current = next
                        stretchStart = glyph
                    }
                }
            }
            context.textPosition = origin
        }

        /// A horizontal stretch of a decorated line and how it looks.
        private struct Band {
            var minX: CGFloat
            var maxX: CGFloat
            var appearance: Appearance
        }

        /// Draws a line with an underline, a strikethrough or a renderer: the whole line once per band
        /// of glyphs that share an appearance, clipped to that band. Neighbouring bands
        /// with the same appearance merge, so finished text is drawn in one piece.
        private func drawBanded(
            _ line: LTXAnimatedLine,
            runs: CFArray,
            runCount: Int,
            in context: CGContext,
            at time: CFTimeInterval,
        ) {
            bandBuffer.removeAll(keepingCapacity: true)
            for runIndex in 0 ..< runCount {
                let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, runIndex), to: CTRun.self)
                let count = CTRunGetGlyphCount(run)
                guard count > 0 else { continue }
                withGlyphGeometry(of: run, count: count) { indices, positions, advances in
                    for glyph in 0 ..< count {
                        let minX = positions[glyph].x
                        let maxX = minX + advances[glyph].width
                        let appearance = appearance(ofCharacterAt: indices[glyph], at: time)
                        if let last = bandBuffer.last, last.appearance == appearance, abs(last.maxX - minX) < 0.5 {
                            bandBuffer[bandBuffer.count - 1].maxX = max(last.maxX, maxX)
                        } else {
                            bandBuffer.append(Band(minX: min(minX, maxX), maxX: max(minX, maxX), appearance: appearance))
                        }
                    }
                }
            }
            let height = line.rect.height
            for band in bandBuffer where band.appearance.level > 0 {
                context.saveGState()
                // Tall enough for the decoration and for glyphs on their way up.
                context.clip(to: CGRect(
                    x: line.baselineOrigin.x + band.minX,
                    y: line.rect.minY - height - band.appearance.drop,
                    width: band.maxX - band.minX,
                    height: height * 3 + band.appearance.drop,
                ))
                context.setAlpha(quantizer.alpha(forLevel: band.appearance.level))
                context.textPosition = CGPoint(x: line.baselineOrigin.x, y: line.baselineOrigin.y - band.appearance.drop)
                line.draw(in: context)
                context.restoreGState()
            }
            context.textPosition = line.baselineOrigin
        }

        /// Whether any run of the line is underlined or struck through.
        private static func hasDecoration(_ runs: CFArray, count: Int) -> Bool {
            for runIndex in 0 ..< count {
                let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, runIndex), to: CTRun.self)
                let attributes = CTRunGetAttributes(run) as NSDictionary
                if let style = attributes[NSAttributedString.Key.underlineStyle] as? Int, style != 0 {
                    return true
                }
                if let style = attributes[NSAttributedString.Key.strikethroughStyle] as? Int, style != 0 {
                    return true
                }
            }
            return false
        }

        // MARK: - Glyph data

        /// Calls `body` with the run's string indices, straight from CoreText when it can
        /// hand them out, from a reused buffer otherwise.
        private func withStringIndices(of run: CTRun, count: Int, _ body: (UnsafePointer<CFIndex>) -> Void) {
            if let pointer = CTRunGetStringIndicesPtr(run) {
                body(pointer)
                return
            }
            if indexBuffer.count < count {
                indexBuffer = [CFIndex](repeating: 0, count: count)
            }
            indexBuffer.withUnsafeMutableBufferPointer { buffer in
                CTRunGetStringIndices(run, CFRange(location: 0, length: count), buffer.baseAddress!)
                body(UnsafePointer(buffer.baseAddress!))
            }
        }

        private func withGlyphGeometry(
            of run: CTRun,
            count: Int,
            _ body: (UnsafePointer<CFIndex>, UnsafePointer<CGPoint>, UnsafePointer<CGSize>) -> Void,
        ) {
            if positionBuffer.count < count {
                positionBuffer = [CGPoint](repeating: .zero, count: count)
                advanceBuffer = [CGSize](repeating: .zero, count: count)
            }
            positionBuffer.withUnsafeMutableBufferPointer { positions in
                advanceBuffer.withUnsafeMutableBufferPointer { advances in
                    let range = CFRange(location: 0, length: count)
                    CTRunGetPositions(run, range, positions.baseAddress!)
                    CTRunGetAdvances(run, range, advances.baseAddress!)
                    withStringIndices(of: run, count: count) { indices in
                        body(indices, positions.baseAddress!, advances.baseAddress!)
                    }
                }
            }
        }
    }

    // MARK: - Fade up

    /// ``FadeInAnimator`` with a small rise: each unit starts a few points below its place
    /// and settles as it becomes opaque.
    ///
    /// The rise draws below the line's own strip, so the animator reports it through
    /// `overdrawInsets` and the label widens the area it redraws by that much.
    @MainActor
    final class FadeUpAnimator: FadeInAnimator {
        init(rise: CGFloat = 6) {
            var configuration = Configuration()
            configuration.rise = rise
            configuration.duration = 0.4
            super.init(configuration: configuration)
        }
    }

#endif
