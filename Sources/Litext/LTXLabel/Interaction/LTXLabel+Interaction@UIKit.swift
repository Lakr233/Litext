//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation

private var menuOwnerIdentifier: UUID = .init()

#if canImport(UIKit)
    import UIKit

    public extension LTXLabel {
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            guard isSelectable else {
                super.pressesBegan(presses, with: event)
                return
            }
            var didHandleEvent = false
            for press in presses {
                guard let key = press.key else { continue }
                if key.charactersIgnoringModifiers == "c", key.modifierFlags.contains(.command) {
                    let copiedText = copySelectedText()
                    didHandleEvent = copiedText.length > 0
                }
                if key.charactersIgnoringModifiers == "a", key.modifierFlags.contains(.command) {
                    selectAllText()
                    didHandleEvent = true
                }
            }
            if !didHandleEvent { super.pressesBegan(presses, with: event) }
        }

        override var canBecomeFocused: Bool {
            isSelectable
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            #if !targetEnvironment(macCatalyst)
                for handler in [selectionHandleStart, selectionHandleEnd] {
                    let rect = handler.frame
                        .insetBy(
                            dx: -LTXSelectionHandle.knobExtraResponsiveArea,
                            dy: -LTXSelectionHandle.knobExtraResponsiveArea
                        )
                    if rect.contains(point) { return true }
                }
            #endif

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

            if isSelectable, !isFirstResponder {
                // to received keyboard event from there
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
            } else if interactionState.clickCount == 2 {
                if let index = textIndexAtPoint(location) {
                    selectWordAtIndex(index)
                    // prevent touches did end discard the changes
                    DispatchQueue.main.asyncAfter(deadline: .now()) {
                        self.selectWordAtIndex(index)
                    }
                }
            } else {
                if let index = textIndexAtPoint(location) {
                    selectLineAtIndex(index)
                    // prevent touches did end discard the changes
                    DispatchQueue.main.asyncAfter(deadline: .now()) {
                        self.selectLineAtIndex(index)
                    }
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
            defer { self.delegate?.ltxLabelDetectedUserEventMovingAtLocation(self, location: location) }

            deactivateHighlightRegion()
            performContinuousStateReset()

            #if canImport(UIKit) && !targetEnvironment(macCatalyst)
                // check if is a pointer device

                // on iOS we block the selection change by touches moved
                // instead user is required to use those handlers
                interactionState.isFirstMove = false
            #else
                if interactionState.isFirstMove {
                    interactionState.isFirstMove = false
                }
                if isSelectable { updateSelectinoRange(withLocation: location) }
            #endif
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            isInteractionInProgress = false
            guard touches.count == 1,
                  let firstTouch = touches.first
            else {
                super.touchesEnded(touches, with: event)
                return
            }
            let location = firstTouch.location(in: self)
            defer { deactivateHighlightRegion() }

            if !isTouchReallyMoved(location),
               interactionState.clickCount <= 1
            {
                if isLocationInSelection(location: location) {
                    #if !targetEnvironment(macCatalyst)
                        showSelectionMenuController()
                    #endif
                } else {
                    clearSelection()
                }
            }

            guard selectionRange == nil, !isTouchReallyMoved(location) else { return }
            for region in highlightRegions {
                let rects = region.rects.map {
                    convertRectFromTextLayout($0.cgRectValue, insetForInteraction: true)
                }
                for rect in rects where rect.contains(location) {
                    self.delegate?.ltxLabelDidTapOnHighlightContent(self, region: region, location: location)
                    break
                }
            }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            isInteractionInProgress = false
            guard touches.count == 1,
                  let firstTouch = touches.first
            else {
                super.touchesCancelled(touches, with: event)
                return
            }
            _ = firstTouch
            deactivateHighlightRegion()
        }

        // for handling right click on iOS
        func installContextMenuInteraction() {
            let interaction = UIContextMenuInteraction(delegate: self)
            addInteraction(interaction)
        }

        func installTextPointerInteraction() {
            if #available(iOS 13.4, macCatalyst 13.4, *) {
                let pointerInteraction = UIPointerInteraction(delegate: self)
                self.addInteraction(pointerInteraction)
            }
        }
    }

    extension LTXLabel: LTXSelectionHandleDelegate {
        func selectionHandleDidMove(_ type: LTXSelectionHandle.HandleType, toLocationInSuperView point: CGPoint) {
            guard let selectionRange, let textLocation = nearestTextIndexAtPoint(point) else { return }
            switch type {
            case .start:
                let startLocation = min(textLocation, selectionRange.location + selectionRange.length - 1)
                let length = selectionRange.location + selectionRange.length - startLocation
                self.selectionRange = .init(
                    location: startLocation,
                    length: length
                )
            case .end:
                let startLocation = selectionRange.location
                let endingLocation = max(textLocation, startLocation + 1)
                self.selectionRange = .init(
                    location: startLocation,
                    length: endingLocation - startLocation
                )
            }
        }
    }

    extension LTXLabel: UIContextMenuInteractionDelegate {
        public func contextMenuInteraction(
            _: UIContextMenuInteraction,
            configurationForMenuAtLocation location: CGPoint
        ) -> UIContextMenuConfiguration? {
            #if targetEnvironment(macCatalyst)
                guard selectionRange != nil else { return nil }
                var menuItems: [UIMenuElement] = [
                    UIAction(title: LocalizedText.copy, image: nil) { _ in
                        self.copySelectedText()
                    },
                ]
                if selectionRange != selectAllRange() {
                    menuItems.append(
                        UIAction(title: LocalizedText.selectAll, image: nil) { _ in
                            self.selectAllText()
                        }
                    )
                }
                return .init(
                    identifier: nil,
                    previewProvider: nil
                ) { _ in
                    .init(children: menuItems)
                }
            #else
                DispatchQueue.main.async {
                    guard self.isSelectable else { return }
                    guard self.isLocationInSelection(location: location) else { return }
                    self.showSelectionMenuController()
                }
                return nil
            #endif
        }
    }

    @available(iOS 13.4, macCatalyst 13.4, *)
    extension LTXLabel: UIPointerInteractionDelegate {
        public func pointerInteraction(_: UIPointerInteraction, styleFor _: UIPointerRegion) -> UIPointerStyle? {
            guard isSelectable else { return nil }
            guard parentViewController?.presentedViewController == nil else { return nil }
            return UIPointerStyle(shape: .verticalBeam(length: 1), constrainedAxes: [])
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
            if selectionRange != selectAllRange() {
                menuItems.append(UIMenuItem(
                    title: LocalizedText.selectAll,
                    action: #selector(selectAllTapped)
                ))
            }
            menuController.menuItems = menuItems

            menuOwnerIdentifier = id
            menuController.showMenu(
                from: self,
                rect: unionRect.insetBy(dx: -8, dy: -8)
            )
        }

        func hideSelectionMenuController() {
            guard menuOwnerIdentifier == id else { return }
            UIMenuController.shared.hideMenu()
        }

        @objc private func copyMenuItemTapped() {
            let copiedText = copySelectedText()
            if copiedText.length <= 0 {
                _ = copyFromSubviewsRecursively()
            }
            clearSelection()
        }

        @objc private func selectAllTapped() {
            selectAllText()
            DispatchQueue.main.async {
                self.showSelectionMenuController()
            }
        }

        @objc private func copyKeyCommand() {
            let copiedText = copySelectedText()
            if copiedText.length <= 0 {
                _ = copyFromSubviewsRecursively()
            }
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

        private func copyFromSubviewsRecursively() -> Bool {
            copyFromSubviewsRecursively(in: self)
        }

        private func copyFromSubviewsRecursively(in view: UIView) -> Bool {
            for subview in view.subviews {
                if let ltxLabel = subview as? LTXLabel {
                    let copiedText = ltxLabel.copySelectedText()
                    if copiedText.length > 0 {
                        return true
                    }
                } else {
                    if copyFromSubviewsRecursively(in: subview) {
                        return true
                    }
                }
            }
            return false
        }
    }

#endif

#if canImport(UIKit)

    extension UIView {
        var parentViewController: UIViewController? {
            weak var parentResponder: UIResponder? = self
            while parentResponder != nil {
                parentResponder = parentResponder!.next
                if let viewController = parentResponder as? UIViewController {
                    return viewController
                }
            }
            return nil
        }
    }
#endif
