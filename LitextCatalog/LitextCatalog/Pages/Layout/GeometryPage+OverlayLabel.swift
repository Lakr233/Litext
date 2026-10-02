//
//  GeometryPage+OverlayLabel.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  A TextLabelView that draws diagnostic overlays over its own text, used by
//  the geometry and attachment-descent pages to show line boxes, baselines and
//  run rects exactly where the label puts them.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// A label that calls `overlay` after drawing its text, in view coordinates
/// (top-left origin on every platform). Call `setNeedsTextDisplay()` after
/// changing what `overlay` reads.
final class OverlayLabelView: TextLabelView {
    var overlay: ((OverlayLabelView, CGContext) -> Void)?

    #if canImport(UIKit)
        override func draw(_ rect: CGRect) {
            super.draw(rect)
            guard let overlay, let context = UIGraphicsGetCurrentContext() else { return }
            drawOverlay(overlay, in: context)
        }

    #elseif canImport(AppKit)
        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard let overlay, let context = NSGraphicsContext.current?.cgContext else { return }
            drawOverlay(overlay, in: context)
        }
    #endif

    /// The baseline of `line` as a horizontal segment in view coordinates.
    func baselineSegment(of line: TextLabel.LayoutLine) -> (start: CGPoint, end: CGPoint) {
        let layoutSegment = CGRect(
            x: line.rect.minX,
            y: line.baselineOrigin.y,
            width: line.rect.width,
            height: 0,
        )
        let viewSegment = viewRect(fromLayoutRect: layoutSegment)
        return (
            CGPoint(x: viewSegment.minX, y: viewSegment.minY),
            CGPoint(x: viewSegment.maxX, y: viewSegment.minY),
        )
    }

    private func drawOverlay(_ overlay: (OverlayLabelView, CGContext) -> Void, in context: CGContext) {
        // Overlays are drawn only once the layout matches the bounds, like the text.
        guard textLayout.containerSize == bounds.size else { return }
        context.saveGState()
        overlay(self, context)
        context.restoreGState()
    }
}

/// Small drawing helpers for overlays.
enum OverlayPainter {
    static func stroke(
        _ rect: CGRect,
        color: PlatformColor,
        in context: CGContext,
        fillAlpha: CGFloat = 0.12,
        dash: [CGFloat] = [],
    ) {
        context.setFillColor(color.withAlphaComponent(fillAlpha).cgColor)
        context.fill(rect)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: dash)
        context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
    }

    static func line(
        from start: CGPoint,
        to end: CGPoint,
        color: PlatformColor,
        in context: CGContext,
        width: CGFloat = 1,
        dash: [CGFloat] = [],
    ) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineDash(phase: 0, lengths: dash)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
    }
}
