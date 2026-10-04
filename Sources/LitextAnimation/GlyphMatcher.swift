//
//  GlyphMatcher.swift
//  LitextAnimation
//
//  Created by Litext Team.
//

import Foundation

#if !os(watchOS)

    /// Pairs the glyphs of two texts so a transition can tell which glyphs stay, which
    /// leave and which arrive.
    enum GlyphMatcher {
        /// For each element of `new`, the index of the element of `old` it continues, or
        /// `nil` when it is new.
        ///
        /// Pairs form a longest common subsequence, so matched glyphs keep their reading
        /// order and never cross while they slide: `1234` to `1235` keeps `123` and swaps
        /// the last digit, and `New Chat` to `Chat` keeps `Chat`. The common prefix and suffix
        /// are paired first; only the middle goes through the quadratic table, and a middle
        /// longer than `limit` on both sides pairs greedily, each new glyph taking the first
        /// unused equal old glyph after the previous pair.
        static func match<Key: Equatable>(old: [Key], new: [Key], limit: Int = 192) -> [Int?] {
            var result = [Int?](repeating: nil, count: new.count)
            var prefix = 0
            while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] {
                result[prefix] = prefix
                prefix += 1
            }
            var suffix = 0
            while suffix < old.count - prefix, suffix < new.count - prefix,
                  old[old.count - 1 - suffix] == new[new.count - 1 - suffix]
            {
                result[new.count - 1 - suffix] = old.count - 1 - suffix
                suffix += 1
            }
            let oldMiddle = prefix ..< old.count - suffix
            let newMiddle = prefix ..< new.count - suffix
            guard !oldMiddle.isEmpty, !newMiddle.isEmpty else { return result }

            if oldMiddle.count > limit, newMiddle.count > limit {
                var next = oldMiddle.lowerBound
                for index in newMiddle {
                    guard let found = old[next ..< oldMiddle.upperBound].firstIndex(of: new[index]) else { continue }
                    result[index] = found
                    next = found + 1
                }
                return result
            }

            // lengths[i][j]: the longest common subsequence of old[i...] and new[j...] in the middle.
            let rows = oldMiddle.count + 1
            let columns = newMiddle.count + 1
            var lengths = [Int32](repeating: 0, count: rows * columns)
            for i in stride(from: oldMiddle.count - 1, through: 0, by: -1) {
                for j in stride(from: newMiddle.count - 1, through: 0, by: -1) {
                    lengths[i * columns + j] = if old[oldMiddle.lowerBound + i] == new[newMiddle.lowerBound + j] {
                        lengths[(i + 1) * columns + j + 1] + 1
                    } else {
                        max(lengths[(i + 1) * columns + j], lengths[i * columns + j + 1])
                    }
                }
            }
            var i = 0
            var j = 0
            while i < oldMiddle.count, j < newMiddle.count {
                if old[oldMiddle.lowerBound + i] == new[newMiddle.lowerBound + j] {
                    result[newMiddle.lowerBound + j] = oldMiddle.lowerBound + i
                    i += 1
                    j += 1
                } else if lengths[(i + 1) * columns + j] >= lengths[i * columns + j + 1] {
                    i += 1
                } else {
                    j += 1
                }
            }
            return result
        }

        /// The number a string shows, ignoring everything but digits, one decimal point and
        /// a leading minus sign, or `nil` when it shows none. `"1,024 tokens"` is 1024.
        static func numericValue(of string: String) -> Double? {
            var digits = ""
            var sawDigit = false
            var sawPoint = false
            for character in string {
                if character.isASCII, character.isNumber {
                    digits.append(character)
                    sawDigit = true
                } else if character == ".", sawDigit, !sawPoint {
                    digits.append(character)
                    sawPoint = true
                } else if character == "-" || character == "\u{2212}", !sawDigit, digits.isEmpty {
                    digits.append("-")
                }
            }
            guard sawDigit else { return nil }
            return Double(digits)
        }
    }

#endif
