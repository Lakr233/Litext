//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreGraphics
import CoreText
import Foundation
import QuartzCore

#if !os(watchOS)

    public extension LTXLabel {
        @objc func selectAllText() {
            guard let range = selectAllRange() else { return }
            selectionRange = range
        }
    }

    extension LTXLabel {
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
