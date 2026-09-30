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

        /// The region's `.link` value as a URL. `NSAttributedString.Key.link`
        /// accepts either a `URL` or a `String`, so both are resolved here.
        public var linkURL: URL? {
            Self.linkURL(from: attributes[.link])
        }

        nonisolated(unsafe) var associatedObject: AnyObject?

        init(kind: Kind, attributes: [NSAttributedString.Key: Any], stringRange: NSRange) {
            self.kind = kind
            self.attributes = attributes
            self.stringRange = stringRange
        }

        nonisolated static func linkURL(from value: Any?) -> URL? {
            if let url = value as? URL {
                return url
            }
            if let string = value as? String {
                return URL(string: string)
            }
            return nil
        }

        func addRect(_ rect: CGRect) {
            rects.append(rect)
        }
    }
}

// swiftlint:enable nesting
