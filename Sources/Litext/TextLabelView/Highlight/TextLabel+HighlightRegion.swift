//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

// swiftlint:disable nesting

import CoreGraphics
import Foundation

extension TextLabel {
    @MainActor
    open class HighlightRegion {
        public enum Kind {
            case link
            case attachment
        }

        open private(set) var rects: [CGRect] = []

        open private(set) var attributes: [NSAttributedString.Key: Any]
        open private(set) var stringRange: NSRange
        public let kind: Kind

        nonisolated(unsafe) var associatedObject: AnyObject?

        init(kind: Kind, attributes: [NSAttributedString.Key: Any], stringRange: NSRange) {
            self.kind = kind
            self.attributes = attributes
            self.stringRange = stringRange
        }

        func addRect(_ rect: CGRect) {
            rects.append(rect)
        }
    }
}

// swiftlint:enable nesting
