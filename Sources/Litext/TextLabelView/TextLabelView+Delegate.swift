//
//  TextLabelView+Delegate.swift
//  Litext
//
//  Created by 秋星桥 on 7/5/25.
//

import Foundation

#if !os(watchOS)

    @MainActor
    public protocol TextLabelViewDelegate: AnyObject {
        /// Called when a link or attachment is tapped. `location` is in the label's
        /// view coordinates (top-left origin); `region.rects` are in layout space,
        /// so convert them with `TextLabelView.viewRect(fromLayoutRect:)` first.
        func textLabelView(
            _ textLabelView: TextLabelView,
            didTapHighlightRegion region: TextLabel.HighlightRegion,
            at location: CGPoint
        )

        func textLabelView(
            _ textLabelView: TextLabelView,
            didChangeSelection selection: NSRange?
        )

        /// Called while a drag extends the selection, with `location` in the label's
        /// view coordinates. Useful for scrolling a containing scroll view.
        func textLabelView(
            _ textLabelView: TextLabelView,
            didDragSelectionAt location: CGPoint
        )
    }

    public extension TextLabelViewDelegate {
        func textLabelView(
            _: TextLabelView,
            didTapHighlightRegion _: TextLabel.HighlightRegion,
            at _: CGPoint
        ) {}

        func textLabelView(
            _: TextLabelView,
            didChangeSelection _: NSRange?
        ) {}

        func textLabelView(
            _: TextLabelView,
            didDragSelectionAt _: CGPoint
        ) {}
    }

#endif // !os(watchOS)
