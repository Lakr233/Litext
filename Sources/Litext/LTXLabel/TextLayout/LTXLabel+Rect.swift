//
//  LTXLabel+Rect.swift
//  Litext
//
//  Created by 秋星桥 on 3/27/25.
//

import Foundation
import QuartzCore

#if !os(watchOS)

    extension LTXLabel {
        func convertRectFromTextLayout(_ rect: CGRect, insetForInteraction useInset: Bool) -> CGRect {
            var result = rect
            result.origin.y = bounds.height - result.origin.y - result.size.height
            if useInset { result = result.insetBy(dx: -4, dy: -4) }
            return result
        }

        var ltxBackingLayer: CALayer? {
            #if canImport(UIKit)
                return layer
            #elseif canImport(AppKit)
                wantsLayer = true
                return layer
            #endif
        }

        func cgPath(from path: LTXPlatformBezierPath) -> CGPath {
            #if canImport(UIKit)
                return path.cgPath
            #elseif canImport(AppKit)
                if #available(macOS 14.0, *) {
                    return path.cgPath
                }
                return path.quartzPath
            #endif
        }
    }

#endif // !os(watchOS)
