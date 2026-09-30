//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

#if canImport(UIKit) && !os(watchOS)

    import CoreText
    import Foundation
    import UIKit

    /// Subclasses that override a touch, press or hit-testing hook below must call
    /// `super` for the events they do not consume, or selection and link taps stop working.
    extension TextLabelView {
        fileprivate static var menuOwnerIdentifier: UUID = .init()

        override open func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            guard isSelectable else {
                super.pressesBegan(presses, with: event)
                return
            }
            var didHandleEvent = false
            for press in presses {
                guard let key = press.key else { continue }
                // Use keyCode instead of charactersIgnoringModifiers for keyboard layout independence
                if key.keyCode == .keyboardC, key.modifierFlags.contains(.command) {
                    didHandleEvent = copySelectionOrNestedSelection()
                }
                if key.keyCode == .keyboardA, key.modifierFlags.contains(.command) {
                    selectAll()
                    didHandleEvent = true
                }
            }
            if !didHandleEvent {
                super.pressesBegan(presses, with: event)
            }
        }

        override open var canBecomeFocused: Bool {
            isSelectable
        }

        override open func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            #if !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
                for handler in [selectionHandleStart, selectionHandleEnd] {
                    guard !handler.isHidden else { continue }
                    let rect = handler.frame
                        .insetBy(
                            dx: -SelectionHandle.knobExtraResponsiveArea,
                            dy: -SelectionHandle.knobExtraResponsiveArea
                        )
                    if rect.contains(point) {
                        return true
                    }
                }
            #endif

            switch hitTarget(at: point) {
            case .outside, .passThrough:
                return false
            case .attachment:
                return super.point(inside: point, with: event)
            case .interactiveText:
                return true
            }
        }

        override open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard touches.count == 1,
                  let firstTouch = touches.first
            else {
                super.touchesBegan(touches, with: event)
                return
            }

            if isSelectable, !isFirstResponder {
                // Become first responder so the label receives keyboard shortcuts such as Copy.
                _ = becomeFirstResponder()
            }

            let location = firstTouch.location(in: self)
            setInteractionStateToBegin(initialLocation: location)

            if isLocationAboveAttachmentView(location: location) {
                interactionState.isForwardingToSuper = true
                super.touchesBegan(touches, with: event)
                return
            }

            if activateLinkRegion(at: location) {
                return
            }

            bumpClickCountIfWithinTimeGap()
            interactionState.clickCountAtBegin = interactionState.clickCount
            if !isSelectable {
                return
            }

            if interactionState.clickCount <= 1 {
                // A pointer click inside the selection keeps it so touchesEnded can show the
                // menu; a drag rebuilds the range from the initial location either way.
                if isPointerDevice(touch: firstTouch), !selectionContains(location) {
                    if let index = textIndexAtPoint(location) {
                        selectionRange = NSRange(location: index, length: 0)
                    }
                }
            } else if let index = characterIndexAtPoint(location) {
                let selectsLine = interactionState.clickCount > 2
                selectWordOrLine(at: index, selectsLine: selectsLine)
                // Apply the selection again on the next run-loop turn, in case UIKit
                // reverts it while it finishes delivering this touch. Skip it if the text
                // has been replaced since, as the index would then point into other text.
                let text = attributedText
                DispatchQueue.main.async { [weak self] in
                    guard let self, attributedText.isEqual(to: text) else { return }
                    selectWordOrLine(at: index, selectsLine: selectsLine)
                }
            }
        }

        private func selectWordOrLine(at index: Int, selectsLine: Bool) {
            if selectsLine {
                selectLineAtIndex(index)
            } else {
                selectWordAtIndex(index)
            }
        }

        override open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard !interactionState.isForwardingToSuper, touches.count == 1,
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

        override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            endInteractionUnlessDraggingSelectionHandle()
            if interactionState.isForwardingToSuper {
                interactionState.isForwardingToSuper = false
                deactivateHighlightRegion()
                super.touchesEnded(touches, with: event)
                return
            }
            guard touches.count == 1,
                  let firstTouch = touches.first
            else {
                super.touchesEnded(touches, with: event)
                return
            }
            let location = firstTouch.location(in: self)
            defer { deactivateHighlightRegion() }

            if !isTouchReallyMoved(location),
               interactionState.clickCountAtBegin <= 1
            {
                if selectionContains(location) {
                    #if !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
                        showSelectionMenuController()
                    #endif
                } else {
                    clearSelection()
                }
            }

            guard selectionRange == nil,
                  !isTouchReallyMoved(location),
                  !interactionState.isTapCancelled
            else { return }
            if let region = highlightRegionForTap(at: location) {
                delegate?.textLabelView(self, didTapHighlightRegion: region, at: location)
            }
        }

        override open func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            endInteractionUnlessDraggingSelectionHandle()
            if interactionState.isForwardingToSuper {
                interactionState.isForwardingToSuper = false
                deactivateHighlightRegion()
                super.touchesCancelled(touches, with: event)
                return
            }
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

        /// A selection handle drag owns the interaction until the handle reports its end,
        /// even if touches the label receives meanwhile end or are cancelled.
        private func endInteractionUnlessDraggingSelectionHandle() {
            if !interactionState.isDraggingSelectionHandle {
                isInteractionInProgress = false
            }
        }

        #if !os(tvOS) && !os(watchOS)
            /// for handling right click on iOS
            public func installContextMenuInteraction() {
                let interaction = UIContextMenuInteraction(delegate: self)
                addInteraction(interaction)
            }

            public func installTextPointerInteraction() {
                if #available(iOS 13.4, macCatalyst 13.4, *) {
                    let pointerInteraction = UIPointerInteraction(delegate: self)
                    addInteraction(pointerInteraction)
                }
            }
        #endif
    }

    #if !os(tvOS) && !os(watchOS)
        extension TextLabelView {
            /// Shows the selection menu over the selection. Pass `selectionRects`, the
            /// selection's rects in layout space, when they are already at hand so they
            /// need not be computed again.
            func showSelectionMenuController(selectionRects: [CGRect]? = nil) {
                guard let range = selectionRange, range.length > 0 else { return }

                // Don't show the menu if another view controller is presented above ours
                // (e.g. UIActivityViewController from shareMenuItemTapped)
                if parentViewController?.presentedViewController != nil {
                    return
                }

                let rects: [CGRect] = (selectionRects ?? textLayout.rects(for: range)).map {
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

                menuController.menuItems = availableItems.map { item in
                    UIMenuItem(title: item.title, action: item.action)
                }

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
                copySelectionOrNestedSelection()
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

            func availableTextSelectionMenuItems() -> [TextLabelMenuItem] {
                TextLabelMenuItem.allCases.filter { item in
                    canPerformAction(item.action, withSender: nil)
                }
            }

            /// The available selection menu items as actions, for the edit menu and
            /// the Mac Catalyst context menu.
            func makeSelectionMenuActions() -> [UIAction] {
                availableTextSelectionMenuItems().map { item in
                    let selector = item.action
                    return UIAction(title: item.title, image: item.image) { [weak self] _ in
                        self?.perform(selector)
                    }
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
                let actions = makeSelectionMenuActions()
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
