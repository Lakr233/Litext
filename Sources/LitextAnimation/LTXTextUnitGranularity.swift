//
//  LTXTextUnitGranularity.swift
//  LitextAnimation
//
//  Created by Litext Team.
//

import Foundation

#if !os(watchOS)

    /// How an effect splits arriving text into units that start one after another.
    public enum LTXTextUnitGranularity: Sendable, Hashable {
        /// Every character the reader sees as one, emoji sequences included.
        case cluster
        /// Every word, as the system's word breaker finds them; works for CJK too.
        case word
    }

    enum TextUnits {
        /// The UTF-16 offsets where the units of `range` start, ascending, beginning with
        /// `range.location`. Never more than `maxCount`: longer runs are thinned evenly, so
        /// a unit then spans several clusters or words.
        static func starts(
            in string: NSString,
            range: NSRange,
            granularity: LTXTextUnitGranularity,
            maxCount: Int,
        ) -> [Int] {
            guard range.length > 0, NSMaxRange(range) <= string.length else { return [range.location] }
            var starts = [range.location]
            let options: NSString.EnumerationOptions = switch granularity {
            case .cluster: [.byComposedCharacterSequences, .substringNotRequired]
            case .word: [.byWords, .substringNotRequired]
            }
            string.enumerateSubstrings(in: range, options: options) { _, unitRange, _, _ in
                if unitRange.location > starts[starts.count - 1] {
                    starts.append(unitRange.location)
                }
            }
            let limit = max(maxCount, 1)
            guard starts.count > limit else { return starts }
            return (0 ..< limit).map { starts[$0 * starts.count / limit] }
        }
    }

#endif
