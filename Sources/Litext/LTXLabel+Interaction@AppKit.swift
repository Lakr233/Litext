//
//  LTXLabel+Interaction@AppKit.swift
//  Litext
//
//  Created by 秋星桥 on 3/26/25.
//

#if canImport(UIKit)

#elseif canImport(AppKit)
    public extension LTXLabel {
        override func rightMouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)

            if isSelectable, selectionRange != nil, selectionRange!.length > 0 {
                showContextMenu(at: point)
                return
            }

            super.rightMouseDown(with: event)
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            let point = convert(event.locationInWindow, from: nil)
            updateCursorForPoint(point)
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            resetCursor()
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            let point = convert(event.locationInWindow, from: nil)
            updateCursorForPoint(point)
        }

        override func mouseDown(with event: NSEvent) {
            let touchLocation = convert(event.locationInWindow, from: nil)
            initialTouchLocation = touchLocation

            let hitHighlightRegion = highlightRegionAtPoint(touchLocation)
            
            let currentTime = Date().timeIntervalSince1970
            if currentTime - interactionState.lastClickTime <= interactionState.multiClickTimeThreshold {
                interactionState.clickCount += 1
                if interactionState.clickCount > 3 {
                    interactionState.clickCount = 1
                }
            } else {
                interactionState.clickCount = 1
            }
            interactionState.lastClickTime = currentTime
            
            if isSelectable {
                if interactionState.clickCount == 2 {
                    if let index = textIndexAtPoint(touchLocation) {
                        selectWordAtIndex(index)
                        return
                    }
                } else if interactionState.clickCount == 3 {
                    if let index = textIndexAtPoint(touchLocation) {
                        selectLineAtIndex(index)
                        return
                    }
                } else if hitHighlightRegion == nil {
                    clearSelection()
                    selectionStartPoint = touchLocation
                    flags.isSelectingText = true
                    return
                }
            }

            if let hitHighlightRegion {
                addActiveHighlightRegion(hitHighlightRegion)
            }

            isTouchSequenceActive = true
        }

        override func mouseDragged(with event: NSEvent) {
            let currentLocation = convert(event.locationInWindow, from: nil)

            if isSelectable, flags.isSelectingText {
                selectionEndPoint = currentLocation

                let distance = hypot(currentLocation.x - initialTouchLocation.x, currentLocation.y - initialTouchLocation.y)
                if distance < 3.0 {
                    return
                }

                guard let startPoint = selectionStartPoint,
                      let startIndex = textIndexAtPoint(startPoint),
                      let endIndex = textIndexAtPoint(currentLocation)
                else { return }

                let range = NSRange(
                    location: min(startIndex, endIndex),
                    length: abs(endIndex - startIndex)
                )

                if range.length > 0 {
                    updateSelectionWithRange(range)
                }
                return
            }

            guard activeHighlightRegion != nil else { return }

            let distance = hypot(currentLocation.x - initialTouchLocation.x, currentLocation.y - initialTouchLocation.y)

            if distance > 4.0 {
                removeActiveHighlightRegion()
                isTouchSequenceActive = false
            }
        }

        override func mouseUp(with event: NSEvent) {
            let touchLocation = convert(event.locationInWindow, from: nil)

            if isSelectable, flags.isSelectingText {
                flags.isSelectingText = false

                if selectionRange == nil || selectionRange?.length == 0 {
                    clearSelection()
                }

                updateCursorForPoint(touchLocation)
                return
            }

            guard let activeHighlightRegion else {
                isTouchSequenceActive = false
                return
            }

            if isHighlightRegion(activeHighlightRegion, containsPoint: touchLocation) {
                tapHandler?(activeHighlightRegion, touchLocation)
            }

            removeActiveHighlightRegion()
            isTouchSequenceActive = false
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            if !bounds.contains(point) { return nil }
            
            for view in attachmentViews {
                if view.frame.contains(point) {
                    return super.hitTest(point)
                }
            }

            if isSelectable || highlightRegionAtPoint(point) != nil {
                window?.makeFirstResponder(self)
                return self
            }
            return super.hitTest(point)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            for trackingArea in trackingAreas {
                removeTrackingArea(trackingArea)
            }

            let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow]
            let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(trackingArea)
        }

        private func handleRightClick(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)

            if isSelectable, selectionRange != nil, selectionRange!.length > 0 {
                showContextMenu(at: point)
                return
            }
        }

        private func showContextMenu(at _: NSPoint) {
            let menu = NSMenu()
            menu.addItem(
                withTitle: LocalizedText.copy,
                action: #selector(copyAction(_:)),
                keyEquivalent: "c"
            )

            if let event = NSApp.currentEvent {
                NSMenu.popUpContextMenu(menu, with: event, for: self)
            }
        }

        @objc private func copyLink(_: Any) {
            guard let linkURL = currentLinkURL else { return }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(linkURL, forType: .string)
        }

        @objc private func openLink(_: Any) {
            guard let linkURL = currentLinkURL, let url = URL(string: linkURL) else { return }
            NSWorkspace.shared.open(url)
        }

        @objc func copyAction(_: Any?) {
            copySelectedText()
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if event.modifierFlags.contains(.command) {
                let key = event.charactersIgnoringModifiers

                if key == "c" {
                    if selectionRange != nil, selectionRange!.length > 0 {
                        copySelectedText()
                        return true
                    }
                }

                if key == "a" {
                    if isSelectable {
                        selectAllText()
                        return true
                    }
                }
            }
            return super.performKeyEquivalent(with: event)
        }

        func selectAllText() {
            guard isSelectable, let textLayout else { return }
            let attributedString = textLayout.attributedString
            guard attributedString.length > 0 else { return }

            let range = NSRange(location: 0, length: attributedString.length)
            updateSelectionWithRange(range)
        }

        override var acceptsFirstResponder: Bool {
            isSelectable
        }

        override func keyDown(with event: NSEvent) {
            super.keyDown(with: event)
        }
    }

#endif
