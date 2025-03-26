//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation

#if canImport(UIKit)
    public extension LTXLabel {
        override var keyCommands: [UIKeyCommand]? {
            guard isSelectable else { return nil }

            return [
                UIKeyCommand(
                    title: LocalizedText.copy,
                    image: nil,
                    action: #selector(copySelectedText),
                    input: "c",
                    modifierFlags: .command,
                    propertyList: nil,
                    alternates: [],
                    discoverabilityTitle: LocalizedText.copy,
                    attributes: [],
                    state: .off
                ),
                UIKeyCommand(
                    title: LocalizedText.selectAll,
                    image: nil,
                    action: #selector(selectAllText),
                    input: "a",
                    modifierFlags: .command,
                    propertyList: nil,
                    alternates: [],
                    discoverabilityTitle: LocalizedText.selectAll,
                    attributes: [],
                    state: .off
                ),
            ]
        }

        override var canBecomeFocused: Bool {
            isSelectable
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            if !bounds.contains(point) { return false }

            for view in attachmentViews {
                if view.frame.contains(point) {
                    return super.point(inside: point, with: event)
                }
            }

            if isSelectable || highlightRegionAtPoint(point) != nil {
                return true
            }

            return false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard touches.count == 1,
                  let firstTouch = touches.first
            else {
                super.touchesBegan(touches, with: event)
                return
            }

            // 确保视图可以在交互时成为第一响应者
            if isSelectable, !isFirstResponder {
                _ = becomeFirstResponder()
            }

            let location = firstTouch.location(in: self)
            setInteractionStateToBegin(initialLocation: location)

            if isLocationAboveAttachmentView(location: location) {
                super.touchesBegan(touches, with: event)
                return
            }
            interactionState.isFirstMove = true

            if activateHighlightRegionAtPoint(location) {
                return
            }

            bumpClickCountIfWithinTimeGap()
            if !isSelectable { return }

            if interactionState.clickCount <= 1 {
                if isLocationInSelection(location: location) {
                } else {
                    clearSelection()
                }
            } else if interactionState.clickCount == 2 {
                if let index = textIndexAtPoint(location) {
                    selectWordAtIndex(index)
                }
            } else {
                if let index = textIndexAtPoint(location) {
                    selectLineAtIndex(index)
                }
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard touches.count == 1,
                  let firstTouch = touches.first
            else {
                super.touchesMoved(touches, with: event)
                return
            }
            let location = firstTouch.location(in: self)
            guard isTouchReallyMoved(location) else { return }
            deactivateHighlightRegion()

            #if canImport(UIKit) && !targetEnvironment(macCatalyst)
                // on iOS we block the selection change by touches moved
                // instead user is required to use those handlers
                interactionState.isFirstMove = false
                selectionRange = nil
            #else
                if interactionState.isFirstMove {
                    interactionState.isFirstMove = false
                    selectionRange = nil
                }
                if isSelectable { updateSelectinoRange(withLocation: location) }
            #endif
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard touches.count == 1,
                  let firstTouch = touches.first
            else {
                super.touchesEnded(touches, with: event)
                return
            }
            let location = firstTouch.location(in: self)
            defer { deactivateHighlightRegion() }
            for region in highlightRegions {
                let rects = region.rects.map {
                    convertRectFromTextLayout($0.cgRectValue, insetForInteraction: true)
                }
                for rect in rects where rect.contains(location) {
                    self.tapHandler?(region, location)
                    break
                }
            }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard touches.count == 1,
                  let firstTouch = touches.first
            else {
                super.touchesCancelled(touches, with: event)
                return
            }
            _ = firstTouch
            deactivateHighlightRegion()
        }
    }

#endif

#if canImport(UIKit)

    extension LTXLabel {
        func showSelectionMenuController() {
            guard let range = selectionRange,
                  range.length > 0,
                  let textLayout
            else { return }

            let rects: [CGRect] = textLayout.rects(for: range).map {
                convertRectFromTextLayout($0, insetForInteraction: true)
            }
            guard !rects.isEmpty, var unionRect = rects.first else { return }

            for rect in rects.dropFirst() {
                unionRect = unionRect.union(rect)
            }

            let menuController = UIMenuController.shared

            var menuItems: [UIMenuItem] = []
            menuItems.append(UIMenuItem(
                title: LocalizedText.copy,
                action: #selector(copyMenuItemTapped)
            ))
            menuController.menuItems = menuItems
            menuController.showMenu(
                from: self,
                rect: unionRect
            )
        }

        func hideSelectionMenuController() { UIMenuController.shared.hideMenu()
        }

        @objc private func copyMenuItemTapped() {
            copySelectedText()
            clearSelection()
        }

        override public var canBecomeFirstResponder: Bool {
            isSelectable
        }

        override public func canPerformAction(
            _ action: Selector,
            withSender sender: Any?
        ) -> Bool {
            if action == #selector(copyMenuItemTapped) {
                return selectionRange != nil
                    && selectionRange!.length > 0
            }
            return super.canPerformAction(
                action,
                withSender: sender
            )
        }
    }
#endif
