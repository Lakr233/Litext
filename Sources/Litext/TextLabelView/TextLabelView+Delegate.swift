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
        func textLabelView(
            _ textLabelView: TextLabelView,
            didTapHighlightRegion region: TextLabel.HighlightRegion,
            at location: CGPoint
        )

        func textLabelView(
            _ textLabelView: TextLabelView,
            didChangeSelection selection: NSRange?
        )

        /// useful for moving scrollview accordingly to handle selection
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
