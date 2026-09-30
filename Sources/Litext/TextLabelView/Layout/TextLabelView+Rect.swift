//
//  TextLabelView+Rect.swift
//  Litext
//
//  Created by 秋星桥 on 3/27/25.
//

import Foundation
import QuartzCore

#if !os(watchOS)

    // Layout geometry (`layoutRuns(matching:)`, `HighlightRegion.rects`,
    // `TextLabel.Layout.rects(for:)`) uses CoreText's lower-left origin. The view,
    // its subviews and every delegate location use a top-left origin: natively on
    // UIKit, and on AppKit because `isFlipped` is `true`.
    public extension TextLabelView {
        /// Converts a rect from CoreText layout space to this view's coordinates.
        ///
        /// The flip uses the height the text was last laid out at, which lags `bounds`
        /// between a resize and the next layout pass, so the result always lines up
        /// with the drawn text.
        func viewRect(fromLayoutRect rect: CGRect) -> CGRect {
            textLayout.viewRect(fromLayoutRect: rect)
        }

        /// Converts a rect from this view's coordinates to CoreText layout space.
        func layoutRect(fromViewRect rect: CGRect) -> CGRect {
            textLayout.layoutRect(fromViewRect: rect)
        }

        /// Converts a point from this view's coordinates, such as a delegate's tap
        /// location, to CoreText layout space.
        func layoutPoint(fromViewPoint point: CGPoint) -> CGPoint {
            textLayout.layoutPoint(fromViewPoint: point)
        }
    }

    extension TextLabelView {
        /// Text is drawn anchored to the top of the layout container, so view-space
        /// conversions must flip against the layout's container height. Using
        /// `bounds.height` here would desynchronize attachments, selection, and
        /// hit testing from the drawn text whenever the view is resized before the
        /// next layout pass runs.
        func convertRectFromTextLayout(_ rect: CGRect, insetForInteraction useInset: Bool) -> CGRect {
            let result = textLayout.viewRect(fromLayoutRect: rect)
            return useInset ? result.insetBy(dx: -4, dy: -4) : result
        }

        func convertPointForTextLayout(_ point: CGPoint) -> CGPoint {
            textLayout.layoutPoint(fromViewPoint: point)
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
                return path.quartzPath
            #endif
        }
    }

#endif // !os(watchOS)
