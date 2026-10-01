//
//  TextLabelView+Delegate.swift
//  Litext
//
//  Created by 秋星桥 on 7/5/25.
//

import Foundation

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

#if !os(watchOS)

    @MainActor
    public protocol TextLabelViewDelegate: AnyObject {
        /// Called when a link or attachment is tapped. `location` is in the label's
        /// view coordinates (top-left origin); `region.rects` are in layout space,
        /// so convert them with `TextLabelView.viewRect(fromLayoutRect:)` first.
        func textLabelView(
            _ textLabelView: TextLabelView,
            didTapHighlightRegion region: TextLabel.HighlightRegion,
            at location: CGPoint,
        )

        func textLabelView(
            _ textLabelView: TextLabelView,
            didChangeSelection selection: NSRange?,
        )

        /// Called while a drag extends the selection, with `location` in the label's
        /// view coordinates. Useful for scrolling a containing scroll view.
        func textLabelView(
            _ textLabelView: TextLabelView,
            didDragSelectionAt location: CGPoint,
        )

        #if canImport(UIKit) && !os(tvOS)
            /// Returns the menu to show for the selection, or nil for the system's menu.
            ///
            /// `suggestedActions` are the system's commands for the selection, such as
            /// Copy, Look Up, Translate and Share, without the editing ones. Called on
            /// iOS 16 and Mac Catalyst 16 or later; earlier systems show a fixed menu.
            @available(iOS 16.0, macCatalyst 16.0, visionOS 1.0, *)
            func textLabelView(
                _ textLabelView: TextLabelView,
                editMenuForSelection selection: NSRange,
                suggestedActions: [UIMenuElement],
            ) -> UIMenu?
        #elseif canImport(AppKit)
            /// Returns the menu to show for a right click on the selection, or nil for
            /// `menu`, the menu the label built. AppKit appends the Services menu to
            /// either one.
            func textLabelView(
                _ textLabelView: TextLabelView,
                menu: NSMenu,
                forSelection selection: NSRange,
                event: NSEvent,
            ) -> NSMenu?
        #endif
    }

    public extension TextLabelViewDelegate {
        func textLabelView(
            _: TextLabelView,
            didTapHighlightRegion _: TextLabel.HighlightRegion,
            at _: CGPoint,
        ) {}

        func textLabelView(
            _: TextLabelView,
            didChangeSelection _: NSRange?,
        ) {}

        func textLabelView(
            _: TextLabelView,
            didDragSelectionAt _: CGPoint,
        ) {}

        #if canImport(UIKit) && !os(tvOS)
            @available(iOS 16.0, macCatalyst 16.0, visionOS 1.0, *)
            func textLabelView(
                _: TextLabelView,
                editMenuForSelection _: NSRange,
                suggestedActions _: [UIMenuElement],
            ) -> UIMenu? {
                nil
            }
        #elseif canImport(AppKit)
            func textLabelView(
                _: TextLabelView,
                menu _: NSMenu,
                forSelection _: NSRange,
                event _: NSEvent,
            ) -> NSMenu? {
                nil
            }
        #endif
    }

#endif // !os(watchOS)
