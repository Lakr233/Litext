//
//  LTXFadeInAnimator.swift
//  LitextAnimation
//
//  Created by Litext Team.
//

import CoreFoundation
import CoreGraphics
import CoreText
import Foundation
import Litext

#if !os(watchOS)

    /// Fades in text as it arrives, staggered by character or word.
    ///
    /// ```swift
    /// label.animator = LTXFadeInAnimator()
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
    /// - Lines with an underline, a strikethrough or a line renderer fall back to drawing
    ///   the whole line through ``LTXAnimatedLine/draw(in:)`` once per stretch, clipped to
    ///   that stretch, so decorations and backgrounds fade with their text instead of being
    ///   drawn twice where stretches meet.
    ///
    /// Reduced motion keeps a short, plain fade: no stagger and no rise.
    ///
    /// Subclasses may override the ``LTXTextAnimator`` members to observe or adjust the
    /// effect, calling `super`. The per-glyph work stays final, so overriding adds no
    /// dynamic dispatch inside a line.
    @MainActor
    open class LTXFadeInAnimator: LTXTextAnimator {
        /// How the effect looks. Changes apply to text that arrives afterwards.
        public struct Configuration: Sendable, Hashable {
            /// How long one unit takes to fade in, in seconds.
            public var duration: Double
            /// The units that start one after another.
            public var granularity: LTXTextUnitGranularity
            /// The delay between units, capped for the whole chunk.
            public var stagger: LTXStaggerSchedule
            /// The opacity curve over `duration`.
            public var curve: LTXCubicBezierCurve
            /// How far below its place a unit starts, in points. Zero for a plain fade.
            public var rise: CGFloat
            /// The opacity steps from transparent to opaque. A frame redraws a unit only
            /// when its opacity moves to another step, so fewer steps mean fewer redraws.
            public var alphaLevels: Int
            /// The most changes animating at once.
            public var maxBatches: Int
            /// The most stagger steps in one change; longer changes group their units.
            public var maxUnitsPerBatch: Int

            public init(
                duration: Double = 0.32,
                granularity: LTXTextUnitGranularity = .cluster,
                stagger: LTXStaggerSchedule = LTXStaggerSchedule(interval: 0.014, maxTotalDelay: 0.16),
                curve: LTXCubicBezierCurve = .easeOut,
                rise: CGFloat = 0,
                alphaLevels: Int = 32,
                maxBatches: Int = 24,
                maxUnitsPerBatch: Int = 48,
            ) {
                self.duration = duration
                self.granularity = granularity
                self.stagger = stagger
                self.curve = curve
                self.rise = rise
                self.alphaLevels = alphaLevels
                self.maxBatches = maxBatches
                self.maxUnitsPerBatch = maxUnitsPerBatch
            }
        }

        /// How the effect looks. Changes apply to text that arrives afterwards.
        public final var configuration: Configuration {
            didSet { quantizer = AlphaQuantizer(levels: configuration.alphaLevels) }
        }

        /// Plays the effect slower (below 1) or faster (above 1), for inspecting it.
        public final var speed: Double = 1

        /// - Parameter configuration: How the effect looks.
        public init(configuration: Configuration = Configuration()) {
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

        private final var quantizer: AlphaQuantizer

        /// The batches in flight, sorted by location; their ranges never overlap.
        private(set) final var batches: [Batch] = []
        private final var cachedAnimatingRange: NSRange?

        /// The last batch a glyph was found in. Glyphs are looked up in text order, so the
        /// next glyph is almost always in the same batch.
        private final var lookupHint = 0

        // Buffers reused for runs whose glyph data CoreText cannot hand out directly.
        private final var indexBuffer: [CFIndex] = []
        private final var positionBuffer: [CGPoint] = []
        private final var advanceBuffer: [CGSize] = []
        private final var bandBuffer: [Band] = []

        // MARK: - LTXTextAnimator

        open func animateChange(_ context: LTXAnimationContext, at time: CFTimeInterval) {
            let change = context.change
            // Text the change rewrote, such as markup that became a link, was already on
            // screen: it keeps the fade it had, and only what follows it is new.
            let restyle = change.hasInsertion && change.hasRemoval
                ? RestyleMatch(
                    change,
                    previous: context.previousLayout.attributedString.string as NSString,
                    current: context.layout.attributedString.string as NSString,
                )
                : nil
            remapBatches(through: change, restyle: restyle)
            let inserted = change.insertedRange
            let freshStart = restyle?.freshStart ?? inserted.location
            if NSMaxRange(inserted) > freshStart {
                addBatch(for: NSRange(location: freshStart, length: NSMaxRange(inserted) - freshStart), in: context, at: time)
            }
            updateAnimatingRange()
        }

        open func advance(to time: CFTimeInterval, invalidation: LTXInvalidationContext) -> Bool {
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

        open var animatingRange: NSRange? {
            cachedAnimatingRange
        }

        open var overdrawInsets: LTXInsets {
            // A rising unit starts below its line.
            LTXInsets(top: 0, left: 0, bottom: configuration.rise.rounded(.up), right: 0)
        }

        open func finish() {
            batches.removeAll()
            cachedAnimatingRange = nil
        }

        open func draw(_ line: LTXAnimatedLine, in context: CGContext, at time: CFTimeInterval) -> Bool {
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

        private final func addBatch(for range: NSRange, in context: LTXAnimationContext, at time: CFTimeInterval) {
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
        /// suffix, and where the change replaced their characters, carried to the characters
        /// `restyle` matched them to, or cut.
        private final func remapBatches(through change: LTXTextChange, restyle: RestyleMatch?) {
            guard !batches.isEmpty, !change.isTextUnchanged else { return }
            let prefix = change.commonPrefixLength
            let suffixStart = change.previousLength - change.commonSuffixLength
            let delta = change.length - change.previousLength
            var remapped: [Batch] = []
            remapped.reserveCapacity(batches.count)
            for batch in batches {
                let end = NSMaxRange(batch.range)
                if end <= prefix {
                    remapped.append(batch)
                    continue
                }
                if batch.range.location >= suffixStart {
                    var moved = batch
                    moved.range.location += delta
                    moved.unitStarts = batch.unitStarts.map { $0 + delta }
                    remapped.append(moved)
                    continue
                }
                if batch.range.location < prefix {
                    // Keep the part before the change.
                    var head = batch
                    head.range.length = prefix - batch.range.location
                    head.unitStarts = batch.unitStarts.filter { $0 < prefix }
                    head.levelSum = -1
                    remapped.append(head)
                }
                if let restyle, let tail = carry(batch, from: prefix, through: restyle) {
                    remapped.append(tail)
                }
            }
            batches = remapped
        }

        /// The part of `batch` from `start` on, moved to the characters `restyle` matched
        /// it to, with each unit keeping its place in the batch's timeline.
        private final func carry(_ batch: Batch, from start: Int, through restyle: RestyleMatch) -> Batch? {
            let end = NSMaxRange(batch.range)
            let from = max(start, batch.range.location)
            guard let location = restyle.newOffset(atOrAfter: from, before: end),
                  let newEnd = restyle.newEnd(before: end), newEnd > location
            else { return nil }
            var firstUnit: Int?
            var starts: [Int] = []
            for (unit, unitStart) in batch.unitStarts.enumerated() {
                let unitEnd = unit + 1 < batch.unitStarts.count ? batch.unitStarts[unit + 1] : end
                guard unitEnd > from,
                      let mapped = restyle.newOffset(atOrAfter: max(unitStart, from), before: unitEnd)
                else { continue }
                if firstUnit == nil {
                    firstUnit = unit
                }
                guard (starts.last ?? -1) < mapped else { continue }
                starts.append(mapped)
            }
            guard let firstUnit, !starts.isEmpty else { return nil }
            starts[0] = location
            // Unit `firstUnit` becomes unit 0, so the batch starts that much later.
            return Batch(
                range: NSRange(location: location, length: newEnd - location),
                unitStarts: starts,
                startTime: batch.startTime + Double(firstUnit) * batch.interval / max(speed, .ulpOfOne),
                interval: batch.interval,
                duration: batch.duration,
                rise: batch.rise,
            )
        }

        private final func updateAnimatingRange() {
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
        final func level(ofUnit unit: Int, in batch: Batch, at time: CFTimeInterval) -> Int {
            let elapsed = (time - batch.startTime) * speed - Double(unit) * batch.interval
            guard elapsed > 0 else { return 0 }
            guard elapsed < batch.duration else { return quantizer.levels }
            return quantizer.level(for: configuration.curve.value(at: elapsed / batch.duration))
        }

        private final func levelSum(of batch: Batch, at time: CFTimeInterval) -> Int {
            var sum = 0
            for unit in batch.unitStarts.indices {
                sum += level(ofUnit: unit, in: batch, at: time)
            }
            return sum
        }

        /// How the glyph for the character at `offset` looks: its opacity step and how far
        /// below its place it is. Characters outside every batch are opaque and in place.
        private final func appearance(ofCharacterAt offset: Int, at time: CFTimeInterval) -> Appearance {
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

        private final func batchIndex(containing offset: Int) -> Int? {
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
        private final func drawRun(_ run: CTRun, origin: CGPoint, in context: CGContext, at time: CFTimeInterval) {
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

        /// A horizontal stretch of a banded line and how it looks.
        private struct Band {
            var minX: CGFloat
            var maxX: CGFloat
            var appearance: Appearance
        }

        /// Draws a line with an underline, a strikethrough or a renderer: the whole line once
        /// per band of glyphs that share an appearance, clipped to that band. Neighbouring
        /// bands with the same appearance merge, so finished text is drawn in one piece.
        private final func drawBanded(
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
        private final func withStringIndices(of run: CTRun, count: Int, _ body: (UnsafePointer<CFIndex>) -> Void) {
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

        private final func withGlyphGeometry(
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

    /// ``LTXFadeInAnimator`` with a small rise: each unit starts a few points below its place
    /// and settles as it becomes opaque.
    ///
    /// The rise draws below the line's own strip, so the animator reports it through
    /// ``LTXTextAnimator/overdrawInsets`` and the label widens the area it redraws by that
    /// much.
    @MainActor
    public final class LTXFadeUpAnimator: LTXFadeInAnimator {
        /// - Parameter rise: How far below its place a unit starts, in points.
        public init(rise: CGFloat = 6) {
            super.init(configuration: Configuration(duration: 0.4, rise: rise))
        }
    }

#endif
