//
//  Ext+NSString.swift
//  Litext
//
//  Created by 秋星桥 on 3/26/25.
//

import Foundation

extension NSString {
    /// The word containing `index`, or `NSNotFound` when `index` sits on
    /// whitespace or punctuation.
    ///
    /// Words arrive in order, so the walk stops at the first word that starts
    /// after `index` instead of tokenizing the rest of the string. The walk still
    /// covers the whole string so word breaking keeps the language it would infer
    /// from the full text.
    func rangeOfWord(at index: Int) -> NSRange {
        let options: NSString.EnumerationOptions = [.byWords, .substringNotRequired]
        var resultRange = NSRange(location: NSNotFound, length: 0)

        enumerateSubstrings(in: NSRange(location: 0, length: length), options: options) { _, substringRange, _, stop in
            if substringRange.location > index {
                stop.pointee = true
            } else if substringRange.contains(index) {
                resultRange = substringRange
                stop.pointee = true
            }
        }

        return resultRange
    }

    /// The paragraph containing `index`, without its terminator.
    ///
    /// Paragraph boundaries follow Foundation: LF, CR, CRLF and U+2029, the same
    /// separators CoreText starts a new paragraph at. A U+2028 line separator
    /// breaks the line but stays inside the paragraph, as in native text views.
    func rangeOfLine(at index: Int) -> NSRange {
        let paragraph = paragraphRange(for: NSRange(location: index, length: 0))
        var end = paragraph.location + paragraph.length
        while end > paragraph.location,
              let scalar = Unicode.Scalar(character(at: end - 1)),
              CharacterSet.newlines.contains(scalar)
        {
            end -= 1
        }
        return NSRange(location: paragraph.location, length: end - paragraph.location)
    }
}
