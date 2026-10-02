//
//  LTXTextChange.swift
//  LitextAnimation
//
//  Created by Litext Team.
//

import CoreFoundation
import Foundation

#if !os(watchOS)

    /// What changed between two strings a label showed, in UTF-16 offsets.
    ///
    /// The change is the common prefix and the common suffix the two strings share, and the
    /// span between them: `removedRange` in the previous string was replaced by
    /// `insertedRange` in the new one. Both ends of that span sit on grapheme-cluster
    /// boundaries in both strings, so an inserted range never starts or ends inside a
    /// character the reader sees as one: a combining mark, a skin-tone modifier or the second
    /// half of an emoji ZWJ sequence that arrives after its base widens the inserted range back
    /// to the start of the cluster it joins.
    ///
    /// Litext lays out exactly the string it is given and adds no trailing newline of its own,
    /// so a newline at the end of either string is ordinary text here. A `"\r"` followed later
    /// by `"\n"` is one cluster, and the inserted range covers both.
    ///
    /// Clusters are Swift's `Character` boundaries. The value has no isolation, so it can be
    /// computed on any thread.
    public struct LTXTextChange: Sendable, Hashable {
        /// The length of the previous string, in UTF-16 code units.
        public let previousLength: Int

        /// The length of the new string, in UTF-16 code units.
        public let length: Int

        /// The UTF-16 length of the text both strings start with, cut back to a cluster
        /// boundary in both.
        public let commonPrefixLength: Int

        /// The UTF-16 length of the text both strings end with, cut back to a cluster boundary
        /// in both. It never overlaps the common prefix in either string.
        public let commonSuffixLength: Int

        /// Whether the previous string is a UTF-16 prefix of the new one, which is longer: the
        /// text only grew at its end. Holds even when the first new code unit joins the last
        /// cluster of the previous string, in which case `insertedRange` starts before
        /// `previousLength`.
        public let isAppend: Bool

        /// Whether the two strings share no text at either end, compared code unit by code
        /// unit before cluster alignment, and neither is empty. The new string replaces the
        /// previous one rather than editing it.
        public let isReplacement: Bool

        /// Whether the two strings have the same characters and differ only in attributes.
        public let isAttributeOnly: Bool

        /// The changed span in the new string, between the common prefix and suffix.
        public var insertedRange: NSRange {
            NSRange(location: commonPrefixLength, length: length - commonPrefixLength - commonSuffixLength)
        }

        /// The changed span in the previous string, between the common prefix and suffix.
        public var removedRange: NSRange {
            NSRange(
                location: commonPrefixLength,
                length: previousLength - commonPrefixLength - commonSuffixLength,
            )
        }

        /// Whether the new string has any text the previous one did not have in its place.
        public var hasInsertion: Bool {
            insertedRange.length > 0
        }

        /// Whether any text of the previous string is gone or was replaced.
        public var hasRemoval: Bool {
            removedRange.length > 0
        }

        /// Whether the characters of the two strings are identical.
        public var isTextUnchanged: Bool {
            !hasInsertion && !hasRemoval
        }

        /// Compares two attributed strings, both their characters and, when the characters
        /// match, their attributes.
        ///
        /// - Important: Performance-sensitive. Runs on every text change of an animatable
        ///   label. The characters are compared in UTF-16 chunks, O(n) in the shared text;
        ///   graphemes are segmented only at the two ends of the changed span, and attributes
        ///   are compared only when the characters are identical.
        public init(from previous: NSAttributedString, to current: NSAttributedString) {
            let previousText = previous.string
            let currentText = current.string
            self.init(
                previous: previousText as NSString,
                previousText: previousText,
                current: currentText as NSString,
                currentText: currentText,
                attributesDiffer: { !previous.isEqual(to: current) },
            )
        }

        /// Compares two plain strings. `isAttributeOnly` is always `false`.
        public init(from previous: String, to current: String) {
            self.init(
                previous: previous as NSString,
                previousText: previous,
                current: current as NSString,
                currentText: current,
                attributesDiffer: { false },
            )
        }

        private init(
            previous: NSString,
            previousText: String,
            current: NSString,
            currentText: String,
            attributesDiffer: () -> Bool,
        ) {
            let oldLength = previous.length
            let newLength = current.length
            let rawPrefix = Self.commonPrefixLength(previous, current, limit: min(oldLength, newLength))
            // Every cluster lookup below walks only the cluster at one offset.
            let prefix = min(
                Self.clusterStart(in: previousText, containing: rawPrefix, length: oldLength),
                Self.clusterStart(in: currentText, containing: rawPrefix, length: newLength),
            )
            // The suffix may reach into code units the aligned prefix gave back, which keeps
            // the changed span as short as the clusters allow.
            let rawSuffix = Self.commonSuffixLength(
                previous,
                current,
                limit: min(oldLength, newLength) - prefix,
            )
            var suffix = rawSuffix
            // The suffix must start on a boundary in both strings. Boundaries inside it can
            // differ between the two, since a cluster rule such as regional-indicator pairing
            // looks back into the changed span, so step forward until both agree.
            while suffix > 0 {
                let newStart = newLength - suffix
                let newEnd = Self.clusterEnd(in: currentText, containing: newStart, length: newLength)
                if newEnd != newStart {
                    suffix = newLength - newEnd
                    continue
                }
                let oldStart = oldLength - suffix
                let oldEnd = Self.clusterEnd(in: previousText, containing: oldStart, length: oldLength)
                if oldEnd != oldStart {
                    suffix = oldLength - oldEnd
                    continue
                }
                break
            }

            previousLength = oldLength
            length = newLength
            commonPrefixLength = prefix
            commonSuffixLength = suffix
            isAppend = rawPrefix == oldLength && newLength > oldLength
            isReplacement = oldLength > 0 && newLength > 0 && rawPrefix == 0 && rawSuffix == 0
            isAttributeOnly = rawPrefix == oldLength && oldLength == newLength && attributesDiffer()
        }

        // MARK: - Clusters

        /// The UTF-16 offset of the start of the grapheme cluster that contains `offset`, or
        /// `offset` itself when it is a cluster boundary or an end of the string.
        private static func clusterStart(in string: String, containing offset: Int, length: Int) -> Int {
            guard offset > 0, offset < length else { return offset }
            let index = String.Index(utf16Offset: offset, in: string)
            guard index.samePosition(in: string) == nil else { return offset }
            // Character-wise index operations round an index inside a cluster down to the
            // cluster's start, so stepping forward and back lands there.
            return string.index(before: string.index(after: index)).utf16Offset(in: string)
        }

        /// The UTF-16 offset of the end of the grapheme cluster that contains `offset`, or
        /// `offset` itself when it is a cluster boundary or an end of the string.
        private static func clusterEnd(in string: String, containing offset: Int, length: Int) -> Int {
            guard offset > 0, offset < length else { return offset }
            let index = String.Index(utf16Offset: offset, in: string)
            guard index.samePosition(in: string) == nil else { return offset }
            return string.index(after: index).utf16Offset(in: string)
        }

        // MARK: - UTF-16 comparison

        private static let chunkLength = 256

        /// The number of leading UTF-16 code units the two strings share, at most `limit`.
        private static func commonPrefixLength(_ lhs: NSString, _ rhs: NSString, limit: Int) -> Int {
            guard limit > 0 else { return 0 }
            if let left = CFStringGetCharactersPtr(lhs as CFString),
               let right = CFStringGetCharactersPtr(rhs as CFString)
            {
                var index = 0
                while index < limit, left[index] == right[index] {
                    index += 1
                }
                return index
            }
            return withChunkBuffers { left, right in
                var start = 0
                while start < limit {
                    let count = min(chunkLength, limit - start)
                    let range = NSRange(location: start, length: count)
                    lhs.getCharacters(left.baseAddress!, range: range)
                    rhs.getCharacters(right.baseAddress!, range: range)
                    if memcmp(left.baseAddress!, right.baseAddress!, count * MemoryLayout<unichar>.stride) != 0 {
                        var offset = 0
                        while left[offset] == right[offset] {
                            offset += 1
                        }
                        return start + offset
                    }
                    start += count
                }
                return limit
            }
        }

        /// The number of trailing UTF-16 code units the two strings share, at most `limit`.
        private static func commonSuffixLength(_ lhs: NSString, _ rhs: NSString, limit: Int) -> Int {
            guard limit > 0 else { return 0 }
            let lhsLength = lhs.length
            let rhsLength = rhs.length
            if let left = CFStringGetCharactersPtr(lhs as CFString),
               let right = CFStringGetCharactersPtr(rhs as CFString)
            {
                var count = 0
                while count < limit, left[lhsLength - 1 - count] == right[rhsLength - 1 - count] {
                    count += 1
                }
                return count
            }
            return withChunkBuffers { left, right in
                var matched = 0
                while matched < limit {
                    let count = min(chunkLength, limit - matched)
                    lhs.getCharacters(left.baseAddress!, range: NSRange(location: lhsLength - matched - count, length: count))
                    rhs.getCharacters(right.baseAddress!, range: NSRange(location: rhsLength - matched - count, length: count))
                    if memcmp(left.baseAddress!, right.baseAddress!, count * MemoryLayout<unichar>.stride) != 0 {
                        var offset = 0
                        while left[count - 1 - offset] == right[count - 1 - offset] {
                            offset += 1
                        }
                        return matched + offset
                    }
                    matched += count
                }
                return limit
            }
        }

        private static func withChunkBuffers<T>(
            _ body: (UnsafeMutableBufferPointer<unichar>, UnsafeMutableBufferPointer<unichar>) -> T,
        ) -> T {
            withUnsafeTemporaryAllocation(of: unichar.self, capacity: chunkLength) { left in
                withUnsafeTemporaryAllocation(of: unichar.self, capacity: chunkLength) { right in
                    body(left, right)
                }
            }
        }
    }

#endif
