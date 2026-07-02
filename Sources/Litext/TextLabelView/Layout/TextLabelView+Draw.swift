//
//  TextLabelView+Draw.swift
//  Litext
//
//  Created by 秋星桥 on 3/27/25.
//

import Foundation

#if canImport(UIKit) && !os(watchOS)
    import UIKit

    public extension TextLabelView {
        override func draw(_ rect: CGRect) {
            guard let context = UIGraphicsGetCurrentContext() else { return }
            UIGraphicsPushContext(context)
            textLayout.draw(in: context, visibleRect: visibleRectForDrawing(dirtyRect: rect))
            UIGraphicsPopContext()
        }
    }

#elseif canImport(AppKit)
    import AppKit

    public extension TextLabelView {
        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            textLayout.draw(in: context, visibleRect: visibleRectForDrawing(dirtyRect: dirtyRect))
        }

        override var isFlipped: Bool {
            true
        }
    }
#endif

#if !os(watchOS)
    extension TextLabelView {
        /// Dirty-rect culling is only meaningful while the layout matches the view's
        /// current geometry; during transitions draw everything to stay correct.
        func visibleRectForDrawing(dirtyRect: CGRect) -> CGRect? {
            guard textLayout.containerSize == bounds.size else { return nil }
            return dirtyRect
        }
    }
#endif
