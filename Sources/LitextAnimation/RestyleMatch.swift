//
//  RestyleMatch.swift
//  LitextAnimation
//
//  Created by Litext Team.
//

import Foundation

#if !os(watchOS)

    /// Where the text a change replaced shows up again in the text that replaced it.
    ///
    /// A streaming renderer that formats as it goes often rewrites text it already showed:
    /// `[link][ref]` becomes `link` once the reference arrives, and `**bold` becomes `bold`
    /// once it closes. The change then runs from the rewritten text to the end of the
    /// string, though most of it is text the reader has already seen. Matching the replaced
    /// characters into the new ones, in order and skipping what one side dropped or added,
    /// tells that text from the text that is really new, which starts at ``freshStart``.
    struct RestyleMatch {
        /// Matched characters as (new offset, previous offset) pairs in UTF-16 offsets of
        /// their strings, ascending in both.
        let pairs: [(new: Int, previous: Int)]

        /// Where the text the previous string did not show starts, in the new string.
        let freshStart: Int

        /// The farthest a match may skip ahead in the replaced text, such as over a link's
        /// URL.
        static let skipLimit = 256
        /// The longest replaced text worth matching; a longer one counts as all new.
        static let lengthLimit = 4096
        /// The shortest run of consecutive matches that counts, so a stray letter of new
        /// text never matches a stray letter the change removed.
        static let minimumRun = 3

        init(_ change: LTXTextChange, previous: NSString, current: NSString) {
            let inserted = change.insertedRange
            let removed = change.removedRange
            guard inserted.length > 0, removed.length > 0, removed.length <= Self.lengthLimit else {
                pairs = []
                freshStart = inserted.location
                return
            }
            var old = [unichar](repeating: 0, count: removed.length)
            previous.getCharacters(&old, range: removed)
            // The walk ends once the replaced text runs out, so only that much of a long
            // insertion is read.
            let newLength = min(inserted.length, removed.length + Self.lengthLimit)
            var new = [unichar](repeating: 0, count: newLength)
            current.getCharacters(&new, range: NSRange(location: inserted.location, length: newLength))

            let minimumRun = min(Self.minimumRun, old.count)
            var accepted: [(new: Int, previous: Int)] = []
            var run: [(new: Int, previous: Int)] = []
            func closeRun() {
                if run.count >= minimumRun {
                    accepted.append(contentsOf: run)
                }
                run.removeAll(keepingCapacity: true)
            }
            var oldIndex = 0
            var newIndex = 0
            while newIndex < new.count, oldIndex < old.count {
                let end = min(oldIndex + Self.skipLimit, old.count)
                var found = oldIndex
                while found < end, old[found] != new[newIndex] {
                    found += 1
                }
                if found < end {
                    if let last = run.last, last.new != newIndex - 1 || last.previous != found - 1 {
                        closeRun()
                    }
                    run.append((newIndex, found))
                    oldIndex = found + 1
                } else {
                    closeRun()
                }
                newIndex += 1
            }
            closeRun()

            pairs = accepted.map { (inserted.location + $0.new, removed.location + $0.previous) }
            guard let last = pairs.last else {
                freshStart = inserted.location
                return
            }
            var start = last.new + 1
            if start < current.length {
                // Never split a character the reader sees as one.
                start = current.rangeOfComposedCharacterSequence(at: start).location
            }
            freshStart = max(start, inserted.location)
        }

        /// The new offset of the first matched character at or after `previousOffset` and
        /// before `previousEnd`, or `nil`.
        func newOffset(atOrAfter previousOffset: Int, before previousEnd: Int) -> Int? {
            var low = 0
            var high = pairs.count
            while low < high {
                let mid = (low + high) / 2
                if pairs[mid].previous < previousOffset {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            guard low < pairs.count, pairs[low].previous < previousEnd else { return nil }
            return pairs[low].new
        }

        /// The new offset just past the last matched character before `previousEnd`, or
        /// `nil`.
        func newEnd(before previousEnd: Int) -> Int? {
            var low = 0
            var high = pairs.count
            while low < high {
                let mid = (low + high) / 2
                if pairs[mid].previous < previousEnd {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            guard low > 0 else { return nil }
            return pairs[low - 1].new + 1
        }
    }

#endif
