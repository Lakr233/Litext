//
//  TextLabelView+Rect.swift
//  Litext
//
//  Created by 秋星桥 on 3/27/25.
//

import Foundation
import QuartzCore

#if !os(watchOS)

    extension TextLabelView {
        /// Text is drawn anchored to the top of the layout container, so view-space
        /// conversions must flip against the layout's container height. Using
        /// `bounds.height` here would desynchronize attachments, selection, and
        /// hit testing from the drawn text whenever the view is resized before the
        /// next layout pass runs.
        func convertRectFromTextLayout(_ rect: CGRect, insetForInteraction useInset: Bool) -> CGRect {
            var result = rect
            result.origin.y = textLayout.containerSize.height - result.origin.y - result.size.height
            if useInset { result = result.insetBy(dx: -4, dy: -4) }
            return result
        }

        var displayScale: CGFloat {
            #if os(visionOS)
                let scale = traitCollection.displayScale
                return scale > 0 ? scale : 1
            #elseif canImport(UIKit)
                let scale = window?.screen.scale ?? traitCollection.displayScale
                return scale > 0 ? scale : 1
            #elseif canImport(AppKit)
                let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
                return scale > 0 ? scale : 1
            #endif
        }

        /// Rounds a length up to the device pixel grid. Text metrics are fractional
        /// (e.g. 30.2999…) and reporting them raw makes the host layout round the
        /// view to a slightly different size than the text layout was measured for.
        func pixelCeil(_ value: CGFloat) -> CGFloat {
            let scale = displayScale
            return ceil(value * scale) / scale
        }

        /// Snaps a rect's origin to the device pixel grid without changing its size.
        func pixelAlign(_ rect: CGRect) -> CGRect {
            let scale = displayScale
            var result = rect
            result.origin.x = (rect.origin.x * scale).rounded() / scale
            result.origin.y = (rect.origin.y * scale).rounded() / scale
            return result
        }

        var backingLayer: CALayer? {
            #if canImport(UIKit)
                return layer
            #elseif canImport(AppKit)
                wantsLayer = true
                return layer
            #endif
        }

        func cgPath(from path: PlatformBezierPath) -> CGPath {
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
