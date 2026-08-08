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
            guard canDrawTextLayout else { return }
            guard let context = UIGraphicsGetCurrentContext() else { return }
            UIGraphicsPushContext(context)
            textLayout.draw(in: context, visibleRect: rect)
            UIGraphicsPopContext()
        }
    }

#elseif canImport(AppKit)
    import AppKit

    public extension TextLabelView {
        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard canDrawTextLayout else { return }
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            textLayout.draw(in: context, visibleRect: dirtyRect)
        }

        override var isFlipped: Bool {
            true
        }
    }
#endif

#if !os(watchOS)
    extension TextLabelView {
        /// Whether the text layout describes the geometry being painted.
        ///
        /// Lines are positioned against `TextLabel.Layout.containerSize`, so painting while
        /// it disagrees with `bounds` offsets every line by the difference — and a shorter
        /// container may not even hold the same lines. A layout pass is always pending when
        /// they disagree, and it marks the view for display once it has caught up, so
        /// skipping here costs at most one frame and never paints the wrong thing.
        ///
        /// Repairing the layout from `draw(_:)` is not an option: the host is inside its
        /// display phase, and laying out there would reenter the phase it just left.
        var canDrawTextLayout: Bool {
            textLayout.containerSize == bounds.size
        }
    }
#endif
