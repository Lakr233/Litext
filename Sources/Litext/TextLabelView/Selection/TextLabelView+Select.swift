//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreGraphics
import CoreText
import Foundation
import QuartzCore

#if !os(watchOS)

    public extension TextLabelView {
        /// Selects the whole text, or in a group the text of every member.
        func selectAll() {
            if let selectionGroup {
                guard isSelectable else { return }
                selectionGroup.selectAll()
                return
            }
            guard let range = selectAllRange() else { return }
            selectionRange = range
        }

        /// Selects the word containing the character at `index`, as a double-click
        /// does. Does nothing when the label is not selectable, the character is
        /// whitespace or punctuation, or `index` is past the end of the text.
        func selectWord(at index: Int) {
            selectWordAtIndex(index)
        }

        /// Selects the paragraph containing the character at `index`, without its
        /// line break, as a triple-click does. Does nothing when the label is not
        /// selectable, the paragraph is empty, or `index` is past the end of the text.
        func selectLine(at index: Int) {
            selectLineAtIndex(index)
        }
    }

    extension TextLabelView {
        func selectWordAtIndex(_ index: Int) {
            guard isSelectable else { return }
            let attributedString = textLayout.attributedString
            guard attributedString.length > 0, index < attributedString.length else { return }
            let nsString = attributedString.string as NSString
            let range = nsString.rangeOfWord(at: index)
            guard range.location != NSNotFound, range.length > 0 else { return }
            selectionRange = range
        }

        func selectLineAtIndex(_ index: Int) {
            guard isSelectable else { return }
            let attributedString = textLayout.attributedString
            guard attributedString.length > 0,
                  index < attributedString.length
            else { return }

            let nsString = attributedString.string as NSString
            let lineRange = nsString.rangeOfLine(at: index)

            guard lineRange.location != NSNotFound, lineRange.length > 0 else { return }
            selectionRange = lineRange
        }

        func selectAllRange() -> NSRange? {
            guard isSelectable else { return nil }
            let attributedString = textLayout.attributedString
            guard attributedString.length > 0 else { return nil }
            return NSRange(location: 0, length: attributedString.length)
        }
    }

#endif // !os(watchOS)
