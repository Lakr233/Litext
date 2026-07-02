//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreGraphics
import Foundation

@MainActor
public class LTXHighlightRegion {
    public enum Kind {
        case link
        case attachment
    }

    public private(set) var rects: [NSValue] = []

    #if os(watchOS)
        private var _cgRects: [CGRect] = []
    #endif

    public private(set) var attributes: [NSAttributedString.Key: Any]
    public private(set) var stringRange: NSRange
    public let kind: Kind

    nonisolated(unsafe) var associatedObject: AnyObject?

    init(kind: Kind, attributes: [NSAttributedString.Key: Any], stringRange: NSRange) {
        self.kind = kind
        self.attributes = attributes
        self.stringRange = stringRange
    }

    func addRect(_ rect: CGRect) {
        #if canImport(UIKit) && !os(watchOS)
            rects.append(NSValue(cgRect: rect))
        #elseif canImport(AppKit)
            rects.append(NSValue(rect: rect))
        #else
            _cgRects.append(rect)
        #endif
    }

    /// Returns all rects as CGRect values. Prefer this over `rects` for cross-platform code.
    public var cgRects: [CGRect] {
        #if canImport(UIKit) && !os(watchOS)
            return rects.map(\.cgRectValue)
        #elseif canImport(AppKit)
            return rects.map(\.rectValue)
        #else
            return _cgRects
        #endif
    }
}
