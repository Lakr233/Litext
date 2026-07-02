//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

#if canImport(UIKit) && !os(watchOS)

    import CoreText
    import Foundation
    import UIKit

    public extension TextLabelView {
        fileprivate static var menuOwnerIdentifier: UUID = .init()

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            guard isSelectable else {
                super.pressesBegan(presses, with: event)
                return
            }
            var didHandleEvent = false
            for press in presses {
                guard let key = press.key else { continue }
                // Use keyCode instead of charactersIgnoringModifiers for keyboard layout independence
                if key.keyCode == .keyboardC, key.modifierFlags.contains(.command) {
                    let copiedText = copySelection()
                    didHandleEvent = copiedText.length > 0 || copyFromSubviewsRecursively()
                }
                if key.keyCode == .keyboardA, key.modifierFlags.contains(.command) {
                    selectAll()
                    didHandleEvent = true
                }
            }
            if !didHandleEvent { super.pressesBegan(presses, with: event) }
        }

        override var canBecomeFocused: Bool {
            isSelectable
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            #if !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
                for handler in [selectionHandleStart, selectionHandleEnd] {
                    guard !handler.isHidden else { continue }
                    let rect = handler.frame
                        .insetBy(
                            dx: -SelectionHandle.knobExtraResponsiveArea,
                            dy: -SelectionHandle.knobExtraResponsiveArea
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

            if activateHighlightRegionAtPoint(location) {
                return
            }

            bumpClickCountIfWithinTimeGap()
            if !isSelectable { return }

            if interactionState.clickCount <= 1 {
                if isPointerDevice(touch: firstTouch) {
                    if let index = textIndexAtPoint(location) {
                        selectionRange = NSRange(location: index, length: 0)
                    }
                }
            } else if interactionState.clickCount == 2 {
                if let index = nearestTextIndexAtPoint(location) {
                    selectWordAtIndex(index)
                    // prevent touches did end discard the changes
                    DispatchQueue.main.asyncAfter(deadline: .now()) { [weak self] in
                        self?.selectWordAtIndex(index)
                    }
                }
            } else {
                if let index = nearestTextIndexAtPoint(location) {
                    selectLineAtIndex(index)
                    // prevent touches did end discard the changes
                    DispatchQueue.main.asyncAfter(deadline: .now()) { [weak self] in
                        self?.selectLineAtIndex(index)
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

            deactivateHighlightRegion()
            performContinuousStateReset()

            guard isSelectable else { return }

            if isPointerDevice(touch: firstTouch) {
                updateSelectionRange(withLocation: location)
                if selectionRange != nil {
                    delegate?.textLabelView(self, didDragSelectionAt: location)
                }
            }
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
                if selectionContains(location) {
                    #if !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
                        showSelectionMenuController()
                    #endif
                } else {
                    clearSelection()
                }
            }

            guard selectionRange == nil, !isTouchReallyMoved(location) else { return }
            if let region = highlightRegionForTap(at: location) {
                delegate?.textLabelView(self, didTapHighlightRegion: region, at: location)
            }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            isInteractionInProgress = false
            guard touches.count == 1 else {
                super.touchesCancelled(touches, with: event)
                return
            }
            NSObject.cancelPreviousPerformRequests(
                withTarget: self,
                selector: #selector(performContinuousStateReset),
                object: nil
            )
            performContinuousStateReset()
            deactivateHighlightRegion()
        }

        #if !os(tvOS) && !os(watchOS)
            /// for handling right click on iOS
            func installContextMenuInteraction() {
                let interaction = UIContextMenuInteraction(delegate: self)
                addInteraction(interaction)
            }

            func installTextPointerInteraction() {
                if #available(iOS 13.4, macCatalyst 13.4, *) {
                    let pointerInteraction = UIPointerInteraction(delegate: self)
                    addInteraction(pointerInteraction)
                }
            }
        #endif
    }

    #if !os(tvOS) && !os(watchOS)
        extension TextLabelView {
            func showSelectionMenuController() {
                guard let range = selectionRange, range.length > 0 else { return }

                // Don't show the menu if another view controller is presented above ours
                // (e.g. UIActivityViewController from shareMenuItemTapped)
                if parentViewController?.presentedViewController != nil { return }

                let rects: [CGRect] = textLayout.rects(for: range).map {
                    convertRectFromTextLayout($0, insetForInteraction: true)
                }
                guard !rects.isEmpty, var unionRect = rects.first else { return }

                for rect in rects.dropFirst() {
                    unionRect = unionRect.union(rect)
                }

                let availableItems = availableTextSelectionMenuItems()
                guard !availableItems.isEmpty else { return }

                #if !targetEnvironment(macCatalyst)
                    if #available(iOS 16.0, visionOS 1.0, *) {
                        showEditMenuController(from: unionRect)
                        return
                    }
                #endif

                let menuController = UIMenuController.shared

                let items = availableItems
                    .compactMap { item -> UIMenuItem? in
                        guard let selector = item.action else { return nil }
                        return UIMenuItem(title: item.title, action: selector)
                    }
                menuController.menuItems = items

                Self.menuOwnerIdentifier = id
                menuController.showMenu(
                    from: self,
                    rect: unionRect.insetBy(dx: -8, dy: -8)
                )
            }

            func hideSelectionMenuController() {
                guard Self.menuOwnerIdentifier == id else { return }
                #if !targetEnvironment(macCatalyst)
                    if #available(iOS 16.0, visionOS 1.0, *),
                       let editMenuInteraction = editMenuInteractionStorage as? UIEditMenuInteraction
                    {
                        editMenuInteraction.dismissMenu()
                        return
                    }
                #endif
                UIMenuController.shared.hideMenu()
            }

            @objc func copyMenuItemTapped() {
                let copiedText = copySelection()
                if copiedText.length <= 0 {
                    _ = copyFromSubviewsRecursively()
                }
                clearSelection()
            }

            @objc func selectAllTapped() {
                selectAll()
                DispatchQueue.main.async {
                    self.showSelectionMenuController()
                }
            }

            @objc func shareMenuItemTapped() {
                guard let text = selectedPlainText(), !text.isEmpty else { return }
                let activityController = UIActivityViewController(activityItems: [text], applicationActivities: nil)
                activityController.popoverPresentationController?.sourceView = self
                parentViewController?.present(activityController, animated: true)
            }

            override open var canBecomeFirstResponder: Bool {
                isSelectable
            }

            override open func canPerformAction(
                _ action: Selector,
                withSender _: Any?
            ) -> Bool {
                if action == #selector(copyMenuItemTapped) {
                    return selectionRange != nil
                        && selectionRange!.length > 0
                }
                if action == #selector(selectAllTapped) {
                    return selectionRange != selectAllRange()
                }
                if action == #selector(shareMenuItemTapped) {
                    return (selectedPlainText() ?? "").isEmpty == false
                }
                return false
            }

            fileprivate func availableTextSelectionMenuItems() -> [TextLabelMenuItem] {
                TextLabelMenuItem.textSelectionMenu().filter { item in
                    guard let selector = item.action else { return false }
                    return canPerformAction(selector, withSender: nil)
                }
            }

            #if !targetEnvironment(macCatalyst)
                @available(iOS 16.0, visionOS 1.0, *)
                private func ensureEditMenuInteraction() -> UIEditMenuInteraction {
                    if let editMenuInteraction = editMenuInteractionStorage as? UIEditMenuInteraction {
                        return editMenuInteraction
                    }

                    let editMenuInteraction = UIEditMenuInteraction(delegate: self)
                    editMenuInteractionStorage = editMenuInteraction
                    addInteraction(editMenuInteraction)
                    return editMenuInteraction
                }

                @available(iOS 16.0, visionOS 1.0, *)
                private func showEditMenuController(from unionRect: CGRect) {
                    // UIEditMenuInteraction presentation is unsupported on Mac Catalyst.
                    let editMenuInteraction = ensureEditMenuInteraction()
                    editMenuTargetRect = unionRect
                    Self.menuOwnerIdentifier = id

                    if isEditMenuVisible {
                        editMenuInteraction.updateVisibleMenuPosition(animated: false)
                        return
                    }

                    isEditMenuVisible = true
                    let sourcePoint = CGPoint(x: unionRect.midX, y: unionRect.midY)
                    let configuration = UIEditMenuConfiguration(identifier: nil, sourcePoint: sourcePoint)
                    editMenuInteraction.presentEditMenu(with: configuration)
                }
            #endif
        }
    #endif

    #if !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
        @available(iOS 16.0, visionOS 1.0, *)
        extension TextLabelView: @preconcurrency UIEditMenuInteractionDelegate {
            public func editMenuInteraction(
                _: UIEditMenuInteraction,
                menuFor _: UIEditMenuConfiguration,
                suggestedActions _: [UIMenuElement]
            ) -> UIMenu? {
                let actions = availableTextSelectionMenuItems().compactMap { item -> UIAction? in
                    guard let selector = item.action else { return nil }
                    return UIAction(title: item.title, image: item.image) { [weak self] _ in
                        self?.perform(selector)
                    }
                }
                guard !actions.isEmpty else { return nil }
                return UIMenu(children: actions)
            }

            public func editMenuInteraction(
                _: UIEditMenuInteraction,
                targetRectFor _: UIEditMenuConfiguration
            ) -> CGRect {
                editMenuTargetRect
            }

            public func editMenuInteraction(
                _: UIEditMenuInteraction,
                willDismissMenuFor _: UIEditMenuConfiguration,
                animator _: UIEditMenuInteractionAnimating
            ) {
                isEditMenuVisible = false
            }
        }
    #endif

    extension TextLabelView {
        func isPointerDevice(touch: UITouch) -> Bool {
            #if targetEnvironment(macCatalyst)
                return true // Mac Catalyst is always a pointer device
            #else
                switch touch.type {
                case .indirectPointer, .pencil:
                    return true
                default:
                    return false
                }
            #endif
        }
    }

#endif
