//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreGraphics
import CoreText
import Foundation
import QuartzCore

#if !os(watchOS)

    private let kDeduplicateSelectionNotification = Notification.Name(
        rawValue: "TextLabelViewDeduplicateSelectionNotification",
    )

    extension TextLabelView {
        /// Rebuilds the selection highlight, handles, and — unless `presentsMenu` is false —
        /// the selection menu.
        ///
        /// A layout pass passes `false`. Presenting the menu attaches an interaction and
        /// shows UI, and the deduplication notification makes every other label clear its
        /// selection; neither may happen while the host is still laying this view out.
        func updateSelectionLayer(presentsMenu: Bool = true) {
            #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
                selectionHandleStart.isHidden = true
                selectionHandleEnd.isHidden = true
                defer { updateSelectionHandleGrabGesture() }
            #endif

            guard let range = selectionRange,
                  range.location != NSNotFound,
                  range.length > 0
            else {
                #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
                    if presentsMenu {
                        hideSelectionMenuController()
                    }
                #endif
                clearSelectionLayer()
                return
            }

            let selectionRects = textLayout.rects(for: range)
            guard !selectionRects.isEmpty else {
                #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
                    if presentsMenu {
                        hideSelectionMenuController()
                    }
                #endif
                clearSelectionLayer()
                return
            }

            updateSelectionLayer(withPath: selectionPath(fromRects: selectionRects))

            #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
                if presentsMenu {
                    showSelectionMenuController(selectionRects: selectionRects)
                }

                // In a group, the first member shows the start handle and the last one
                // the end handle.
                selectionHandleStart.isHidden = !(selectionGroup?.showsHandle(true, in: self) ?? true)
                selectionHandleEnd.isHidden = !(selectionGroup?.showsHandle(false, in: self) ?? true)

                // Update handle colors to match selection color
                let handleColor = selectionBackgroundColor?.withAlphaComponent(1.0)
                selectionHandleStart.updateHandleColor(handleColor)
                selectionHandleEnd.updateHandleColor(handleColor)

                // A character drawn by another glyph can have no rect of its own; the
                // caret at its edge keeps the handle on the text instead of at `.zero`.
                let lastCharacter = range.location + range.length - 1
                var beginRect = textLayout.rects(
                    for: NSRange(location: range.location, length: 1),
                ).first
                    ?? textLayout.caretRect(at: range.location, onLineOf: range.location)
                    ?? .zero
                beginRect = convertRectFromTextLayout(beginRect, insetForInteraction: false)
                selectionHandleStart.frame = selectionHandleStart.frame(forLineRect: beginRect)
                var endRect = textLayout.rects(
                    for: NSRange(location: lastCharacter, length: 1),
                ).first
                    ?? textLayout.caretRect(at: lastCharacter + 1, onLineOf: lastCharacter)
                    ?? .zero
                endRect = convertRectFromTextLayout(endRect, insetForInteraction: false)
                selectionHandleEnd.frame = selectionHandleEnd.frame(forLineRect: endRect)
            #endif

            if presentsMenu {
                broadcastSelection()
            }
        }

        /// Tells every other label to drop its selection, except the members of this
        /// label's group, which share it.
        func broadcastSelection() {
            NotificationCenter.default.post(name: kDeduplicateSelectionNotification, object: self)
        }

        func registerNotificationCenterForSelectionDeduplicate() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(deduplicateSelection),
                name: kDeduplicateSelectionNotification,
                object: nil,
            )
        }

        @objc private func deduplicateSelection(_ notification: Notification) {
            guard let object = notification.object as? TextLabelView, object != self else { return }
            if let selectionGroup {
                // The group keeps its members' selection layers in step, so only a group
                // with a selection has anything to clear. Every member hears the
                // broadcast; the first one clears the group.
                if object.selectionGroup !== selectionGroup, selectionGroup.hasSelection {
                    selectionGroup.clearSelection()
                }
                return
            }
            clearSelection()
        }

        /// One rect per selected line segment. A Core Graphics path takes them in
        /// linear time; appending to a bezier path copies it each time, which made
        /// selecting all of a 20,000-line label take seconds.
        private func selectionPath(fromRects rects: [CGRect]) -> CGPath {
            let path = CGMutablePath()
            for rect in rects {
                path.addRect(convertRectFromTextLayout(rect, insetForInteraction: false))
            }
            return path
        }

        private func updateSelectionLayer(withPath path: CGPath) {
            let fillColor = (selectionBackgroundColor ?? defaultSelectionTint).cgColor

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }

            if let selectionLayer {
                selectionLayer.path = path
                selectionLayer.fillColor = fillColor
                return
            }

            let selLayer = CAShapeLayer()
            selLayer.path = path
            selLayer.fillColor = fillColor
            backingLayer?.insertSublayer(selLayer, at: 0)
            selectionLayer = selLayer
        }

        private func clearSelectionLayer() {
            selectionLayer?.removeFromSuperlayer()
            selectionLayer = nil
        }
    }

#endif // !os(watchOS)
