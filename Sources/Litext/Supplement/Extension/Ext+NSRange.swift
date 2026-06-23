//
//  Ext+NSRange.swift
//  Litext
//
//  Created by 秋星桥 on 3/26/25.
//

import Foundation

extension NSRange {
    func contains(_ index: Int) -> Bool {
        index >= location && index < (location + length)
    }

    static func sanitized(_ range: NSRange?, within length: Int) -> NSRange? {
        guard let range,
              range.location != NSNotFound,
              range.location >= 0,
              range.length > 0,
              range.location < length
        else {
            return nil
        }

        let clampedLength = min(range.length, length - range.location)
        return NSRange(location: range.location, length: clampedLength)
    }
}
