//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//
//  The text diff behind animated changes: UTF-16 prefix and suffix, aligned to
//  grapheme clusters in both strings. A fuzz test holds the optimized diff to a
//  naive one built from Swift's `Character` segmentation.
//
//  Reproduce a fuzz failure with the seed it prints:
//  `LITEXT_FUZZ_SEED=<seed> LITEXT_FUZZ_ITERATIONS=1 swift test --filter LTXTextChange`.
//

#if !os(watchOS)

    import Foundation
    import LitextAnimation
    import Testing

    @Suite("Text change")
    struct LTXTextChangeTests {
        private static func range(_ location: Int, _ length: Int) -> NSRange {
            NSRange(location: location, length: length)
        }

        // MARK: - Edits

        @Test
        func `appending text inserts at the end`() {
            let change = LTXTextChange(from: "Hello", to: "Hello, world")
            #expect(change.insertedRange == Self.range(5, 7))
            #expect(change.removedRange == Self.range(5, 0))
            #expect(change.commonPrefixLength == 5)
            #expect(change.commonSuffixLength == 0)
            #expect(change.isAppend)
            #expect(!change.isReplacement)
            #expect(change.hasInsertion)
            #expect(!change.hasRemoval)
        }

        @Test
        func `the first text is an append and not a replacement`() {
            let change = LTXTextChange(from: "", to: "Hi")
            #expect(change.insertedRange == Self.range(0, 2))
            #expect(change.isAppend)
            #expect(!change.isReplacement)
        }

        @Test
        func `inserting in the middle keeps both ends`() {
            let change = LTXTextChange(from: "Hello world", to: "Hello brave world")
            #expect(change.insertedRange == Self.range(6, 6))
            #expect(change.removedRange == Self.range(6, 0))
            #expect(change.commonSuffixLength == 5)
            #expect(!change.isAppend)
        }

        @Test
        func `deleting text inserts nothing`() {
            let change = LTXTextChange(from: "Hello brave world", to: "Hello world")
            #expect(change.insertedRange == Self.range(6, 0))
            #expect(change.removedRange == Self.range(6, 6))
            #expect(!change.hasInsertion)
            #expect(change.hasRemoval)
            #expect(!change.isAppend)
        }

        @Test
        func `shortening the end removes the tail`() {
            let change = LTXTextChange(from: "Hello world", to: "Hello")
            #expect(change.removedRange == Self.range(5, 6))
            #expect(!change.hasInsertion)
        }

        @Test
        func `text with nothing in common is a replacement`() {
            let change = LTXTextChange(from: "abc", to: "xyz")
            #expect(change.isReplacement)
            #expect(change.insertedRange == Self.range(0, 3))
            #expect(change.removedRange == Self.range(0, 3))
        }

        @Test
        func `sharing only the end is not a replacement`() {
            let change = LTXTextChange(from: "abc!", to: "xyz!")
            #expect(!change.isReplacement)
            #expect(change.insertedRange == Self.range(0, 3))
        }

        @Test
        func `clearing the text is not a replacement`() {
            let change = LTXTextChange(from: "abc", to: "")
            #expect(!change.isReplacement)
            #expect(change.removedRange == Self.range(0, 3))
        }

        @Test
        func `equal strings change nothing`() {
            let change = LTXTextChange(from: "Same", to: "Same")
            #expect(change.isTextUnchanged)
            #expect(!change.isAppend)
            #expect(!change.isReplacement)
            #expect(!change.isAttributeOnly)
            #expect(change.commonPrefixLength == 4)
            #expect(change.commonSuffixLength == 0)
        }

        // MARK: - Attributes

        @Test
        func `a change of attributes alone is attribute only`() {
            let previous = NSAttributedString(string: "Bold", attributes: [.testStyle: 1])
            let current = NSAttributedString(string: "Bold", attributes: [.testStyle: 2])
            let change = LTXTextChange(from: previous, to: current)
            #expect(change.isAttributeOnly)
            #expect(change.isTextUnchanged)
            #expect(!change.hasInsertion)
        }

        @Test
        func `identical attributed strings are not attribute only`() {
            let text = NSAttributedString(string: "Bold", attributes: [.testStyle: 1])
            let change = LTXTextChange(from: text, to: NSAttributedString(attributedString: text))
            #expect(!change.isAttributeOnly)
            #expect(change.isTextUnchanged)
        }

        @Test
        func `restyled text that also grows is not attribute only`() {
            let previous = NSAttributedString(string: "Bold", attributes: [.testStyle: 1])
            let current = NSAttributedString(string: "Bolder", attributes: [.testStyle: 2])
            let change = LTXTextChange(from: previous, to: current)
            #expect(!change.isAttributeOnly)
            #expect(change.insertedRange == Self.range(4, 2))
        }

        // MARK: - Newlines

        @Test
        func `a trailing newline is ordinary text`() {
            let added = LTXTextChange(from: "Line", to: "Line\n")
            #expect(added.insertedRange == Self.range(4, 1))
            #expect(added.isAppend)

            let continued = LTXTextChange(from: "Line\n", to: "Line\nNext")
            #expect(continued.insertedRange == Self.range(5, 4))
            #expect(continued.isAppend)

            let removed = LTXTextChange(from: "Line\n", to: "Line")
            #expect(removed.removedRange == Self.range(4, 1))
        }

        @Test
        func `a line feed after a carriage return joins its cluster`() {
            let change = LTXTextChange(from: "Line\r", to: "Line\r\n")
            #expect(change.insertedRange == Self.range(4, 2))
            #expect(change.removedRange == Self.range(4, 1))
            #expect(change.isAppend)
        }

        // MARK: - Clusters

        @Test
        func `a ZWJ sequence arriving in parts covers the whole emoji`() {
            // 👩 is two code units, the joiner one, 💻 two.
            let first = LTXTextChange(from: "Hi 👩", to: "Hi 👩\u{200D}")
            #expect(first.insertedRange == Self.range(3, 3))
            #expect(first.removedRange == Self.range(3, 2))
            #expect(first.isAppend)
            #expect(!first.isReplacement)

            let second = LTXTextChange(from: "Hi 👩\u{200D}", to: "Hi 👩\u{200D}💻")
            #expect(second.insertedRange == Self.range(3, 5))
            #expect(second.removedRange == Self.range(3, 3))
        }

        @Test
        func `a whole ZWJ sequence appends after the text`() {
            let change = LTXTextChange(from: "Hi ", to: "Hi 👩\u{200D}👩\u{200D}👧\u{200D}👦")
            #expect(change.insertedRange == Self.range(3, 11))
            #expect(change.removedRange == Self.range(3, 0))
        }

        @Test
        func `a skin tone modifier joins the emoji before it`() {
            let change = LTXTextChange(from: "👍", to: "👍🏽")
            #expect(change.insertedRange == Self.range(0, 4))
            #expect(change.removedRange == Self.range(0, 2))
            #expect(change.isAppend)
            #expect(!change.isReplacement)
        }

        @Test
        func `the second regional indicator completes the flag`() {
            let change = LTXTextChange(from: "Go 🇺", to: "Go 🇺🇸")
            #expect(change.insertedRange == Self.range(3, 4))
            #expect(change.removedRange == Self.range(3, 2))
        }

        @Test
        func `a third regional indicator starts a new flag`() {
            let change = LTXTextChange(from: "🇺🇸", to: "🇺🇸🇫")
            #expect(change.insertedRange == Self.range(4, 2))
            #expect(change.removedRange == Self.range(4, 0))
        }

        @Test
        func `removing one indicator re-pairs the flags after it`() {
            // 🇺🇸🇫🇷 becomes 🇸🇫 🇷: every cluster after the edit moved.
            let change = LTXTextChange(from: "🇺🇸🇫🇷", to: "🇸🇫🇷")
            #expect(change.commonPrefixLength == 0)
            #expect(change.commonSuffixLength == 0)
        }

        @Test
        func `a combining mark joins the letter before it`() {
            let change = LTXTextChange(from: "Cafe", to: "Cafe\u{301}")
            #expect(change.insertedRange == Self.range(3, 2))
            #expect(change.removedRange == Self.range(3, 1))
            #expect(change.isAppend)
        }

        @Test
        func `removing a combining mark replaces its cluster`() {
            let change = LTXTextChange(from: "Cafe\u{301}!", to: "Cafe!")
            #expect(change.insertedRange == Self.range(3, 1))
            #expect(change.removedRange == Self.range(3, 2))
            #expect(change.commonSuffixLength == 1)
        }

        @Test
        func `a combining mark inserted mid text covers its letter`() {
            let change = LTXTextChange(from: "resume", to: "re\u{301}sume")
            #expect(change.insertedRange == Self.range(1, 2))
            #expect(change.removedRange == Self.range(1, 1))
            #expect(change.commonSuffixLength == 4)
        }

        @Test
        func `right to left text diffs in logical order`() {
            let previous = "مرحبا"
            let current = "مرحبا بالعالم"
            let change = LTXTextChange(from: previous, to: current)
            #expect(change.insertedRange == Self.range(5, 8))
            #expect(change.isAppend)

            let vowelled = LTXTextChange(from: "سلام", to: "سَلام")
            #expect(vowelled.insertedRange == Self.range(0, 2))
            #expect(vowelled.removedRange == Self.range(0, 1))
            #expect(vowelled.commonSuffixLength == 3)
        }

        @Test
        func `a Hangul syllable built from jamo grows its cluster`() {
            let change = LTXTextChange(from: "\u{1100}\u{1161}", to: "\u{1100}\u{1161}\u{11A8}")
            #expect(change.insertedRange == Self.range(0, 3))
            #expect(change.removedRange == Self.range(0, 2))
        }

        // MARK: - Long text

        @Test
        func `long streams compare across chunk boundaries`() {
            // Long enough to take the chunked path, which differs at an offset that is
            // not a multiple of the chunk length.
            let base = String(repeating: "Lorem ipsum é 👩‍💻 ", count: 300)
            let units = Array(base.utf16)
            let previous = base
            let current = String(decoding: units[..<1001] + Array("XYZ".utf16) + units[1001...], as: UTF16.self)
            let reference = Self.referenceChange(from: previous, to: current)
            // Native Swift strings have no UTF-16 buffer to borrow and take the chunked
            // comparison; attributed strings usually lend theirs.
            let plain = LTXTextChange(from: previous, to: current)
            let attributed = LTXTextChange(
                from: NSAttributedString(string: previous),
                to: NSAttributedString(string: current),
            )
            for change in [plain, attributed] {
                #expect(change.commonPrefixLength == reference.prefix)
                #expect(change.commonSuffixLength == reference.suffix)
                #expect(change.insertedRange.length >= 3)
            }
        }

        // MARK: - Fuzz

        private static let pieces: [String] = [
            "a", "b", " ", "\n", "\r", "\r\n", "e", "\u{301}", "\u{302}",
            "🇺", "🇸", "🇫", "👩", "💻", "👍", "🏽", "\u{200D}", "\u{FE0F}",
            "ا", "\u{64B}", "ب", "\u{1100}", "\u{1161}", "\u{11A8}",
            "क", "\u{94D}", "ष", "中", "😀",
        ]

        private static func randomText(length: Int, random: inout SeededGenerator) -> String {
            var text = ""
            for _ in 0 ..< length {
                text += pieces.randomElement(using: &random)!
            }
            return text
        }

        /// An edit of `text`: an append, an insertion, a deletion or a replacement of a
        /// random span, cut at arbitrary UTF-16 offsets, inside clusters too.
        private static func randomEdit(of text: String, random: inout SeededGenerator) -> String {
            let units = Array(text.utf16)
            let start = Int.random(in: 0 ... units.count, using: &random)
            let end = Int.random(in: start ... units.count, using: &random)
            let removesSpan = Bool.random(using: &random)
            let inserted = Array(randomText(length: Int.random(in: 0 ... 4, using: &random), random: &random).utf16)
            let kept = removesSpan ? units[..<start] + inserted + units[end...] : units[..<start] + inserted + units[start...]
            return String(decoding: kept, as: UTF16.self)
        }

        /// The common prefix and suffix computed the slow way: whole clusters, compared
        /// by their code units, the prefix first.
        private static func referenceChange(from previous: String, to current: String) -> (prefix: Int, suffix: Int) {
            let old = previous.map { Array($0.utf16) }
            let new = current.map { Array($0.utf16) }
            var prefixCount = 0
            var prefix = 0
            while prefixCount < min(old.count, new.count), old[prefixCount] == new[prefixCount] {
                prefix += old[prefixCount].count
                prefixCount += 1
            }
            var suffixCount = 0
            var suffix = 0
            while suffixCount < min(old.count, new.count) - prefixCount,
                  old[old.count - 1 - suffixCount] == new[new.count - 1 - suffixCount]
            {
                suffix += old[old.count - 1 - suffixCount].count
                suffixCount += 1
            }
            return (prefix, suffix)
        }

        @Test
        func `the diff matches whole-cluster comparison on random edits`() {
            let environment = ProcessInfo.processInfo.environment
            let iterations = environment["LITEXT_FUZZ_ITERATIONS"].flatMap(Int.init) ?? 2000
            let baseSeed = environment["LITEXT_FUZZ_SEED"].flatMap(UInt64.init) ?? 0x5EED_1A7E
            var mismatches = 0
            for iteration in 0 ..< iterations {
                let seed = baseSeed &+ UInt64(iteration)
                var random = SeededGenerator(seed: seed)
                let previous = Self.randomText(length: Int.random(in: 0 ... 12, using: &random), random: &random)
                let current = Self.randomEdit(of: previous, random: &random)
                let change = LTXTextChange(from: previous, to: current)
                let reference = Self.referenceChange(from: previous, to: current)
                if change.commonPrefixLength != reference.prefix || change.commonSuffixLength != reference.suffix {
                    mismatches += 1
                    Issue.record("""
                    seed \(seed): \(previous.debugDescription) -> \(current.debugDescription): \
                    prefix \(change.commonPrefixLength), suffix \(change.commonSuffixLength); \
                    expected \(reference.prefix), \(reference.suffix)
                    """)
                    if mismatches > 20 {
                        break
                    }
                }
                let previousLength = previous.utf16.count
                let currentLength = current.utf16.count
                #expect(change.previousLength == previousLength)
                #expect(change.length == currentLength)
                #expect(change.isAppend == (current.utf16.starts(with: previous.utf16) && currentLength > previousLength))
            }
        }
    }

    // MARK: - Seeded randomness

    /// SplitMix64: small, fast and identical on every platform, so a seed
    /// reproduces the same input everywhere.
    struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

#endif

#if !os(watchOS)

    extension NSAttributedString.Key {
        /// An attribute only the tests read, so restyling needs no platform font types.
        static let testStyle = NSAttributedString.Key("LTXTestStyle")
    }

#endif
