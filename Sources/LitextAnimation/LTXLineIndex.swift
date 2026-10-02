//
//  LTXLineIndex.swift
//  LitextAnimation
//
//  Created by Litext Team.
//

import CoreGraphics
import Foundation
import Litext

#if !os(watchOS)

    /// The laid-out lines of one layout, keyed by their characters, for turning a character
    /// range into the lines that show it.
    ///
    /// Built once per layout pass from `TextLabel.Layout.layoutLines`. Lines show the text in
    /// order, so a lookup is two binary searches over their start and end offsets.
    struct LTXLineIndex {
        /// The UTF-16 offset each line starts at, ascending.
        private(set) var starts: [Int] = []
        /// The UTF-16 offset each line ends at, line break included, ascending.
        private(set) var ends: [Int] = []
        /// Each line's typographic box, in layout space.
        private(set) var rects: [CGRect] = []

        @MainActor
        init(lines: [TextLabel.LayoutLine]) {
            starts.reserveCapacity(lines.count)
            ends.reserveCapacity(lines.count)
            rects.reserveCapacity(lines.count)
            for line in lines {
                starts.append(line.stringRange.location)
                ends.append(NSMaxRange(line.stringRange))
                rects.append(line.rect)
            }
        }

        var count: Int {
            starts.count
        }

        /// The lines that show any character of `range`. An empty range counts as the
        /// character at its location, so it finds the line an insertion point sits on.
        ///
        /// - Important: Performance-sensitive. O(log n) in the number of lines, no
        ///   allocation.
        func lines(touching range: NSRange) -> Range<Int> {
            guard range.location != NSNotFound, range.location >= 0, !starts.isEmpty else { return 0 ..< 0 }
            let lowerBound = range.location
            let upperBound = range.length > 0 ? NSMaxRange(range) : lowerBound + 1
            // The first line that ends after the range starts, and the first that starts at
            // or after the range ends.
            let first = Self.partitionPoint(ends.count) { ends[$0] > lowerBound }
            let last = Self.partitionPoint(starts.count) { starts[$0] >= upperBound }
            return first < last ? first ..< last : 0 ..< 0
        }

        /// The strip of the label that `lines` own, in view space (top-left origin).
        ///
        /// A strip spans the container's width and reaches halfway into the gap to the
        /// neighbouring lines, so it covers the line spacing and most glyph ink that leaves
        /// the typographic boxes: italic overhangs, marks above capitals, deep descenders.
        /// The first and last lines of the text reach half a line height past their boxes.
        /// Strips of adjacent line ranges leave no gap between them, and overlap only where
        /// the lines' own boxes do.
        ///
        /// - Important: Performance-sensitive. O(1): reads at most four line boxes.
        @MainActor
        func strip(of lines: Range<Int>, in layout: TextLabel.Layout) -> CGRect {
            guard !lines.isEmpty, lines.lowerBound >= 0, lines.upperBound <= count else { return .null }
            let first = layout.viewRect(fromLayoutRect: rects[lines.lowerBound])
            let last = layout.viewRect(fromLayoutRect: rects[lines.upperBound - 1])
            var top = min(first.minY, last.minY)
            var bottom = max(first.maxY, last.maxY)
            if lines.lowerBound > 0 {
                let above = layout.viewRect(fromLayoutRect: rects[lines.lowerBound - 1])
                top = min(top, (above.maxY + first.minY) / 2)
            } else {
                top -= first.height / 2
            }
            if lines.upperBound < count {
                let below = layout.viewRect(fromLayoutRect: rects[lines.upperBound])
                bottom = max(bottom, (last.maxY + below.minY) / 2)
            } else {
                bottom += last.height / 2
            }
            let minX = min(0, first.minX, last.minX)
            let maxX = max(layout.containerSize.width, first.maxX, last.maxX)
            return CGRect(x: minX, y: top, width: maxX - minX, height: bottom - top)
        }

        /// The first index in `0 ..< count` where `predicate` holds, or `count`.
        /// `predicate` must hold for every index after one where it holds.
        private static func partitionPoint(_ count: Int, where predicate: (Int) -> Bool) -> Int {
            var low = 0
            var high = count
            while low < high {
                let mid = (low + high) / 2
                if predicate(mid) {
                    high = mid
                } else {
                    low = mid + 1
                }
            }
            return low
        }
    }

#endif
