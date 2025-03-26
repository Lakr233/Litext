//
//  LTXLabel+Interaction@AppKit.swift
//  Litext
//
//  Created by 秋星桥 on 3/26/25.
//

import Foundation

#if canImport(UIKit)

#elseif canImport(AppKit)
    public extension LTXLabel {
        override var acceptsFirstResponder: Bool {
            isSelectable
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard event.modifierFlags.contains(.command) else {
                return super.performKeyEquivalent(with: event)
            }
            let key = event.charactersIgnoringModifiers

            if key == "c", let range = selectionRange, range.length > 0 {
                copySelectedText()
                return true
            }

            if key == "a", isSelectable {
                selectAllText()
                return true
            }
            return false
        }

        override func rightMouseDown(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            setInteractionStateToBegin(initialLocation: location)
            if handleRightClick(with: event) { return }
            super.rightMouseDown(with: event)
        }

        override func mouseDown(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            setInteractionStateToBegin(initialLocation: location)

            if isLocationAboveAttachmentView(location: location) {
                super.mouseDown(with: event)
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

        override func mouseDragged(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)

            guard isTouchReallyMoved(location) else { return }

            deactivateHighlightRegion()

            if interactionState.isFirstMove {
                interactionState.isFirstMove = false
                selectionRange = nil
            }

            if isSelectable { updateSelectinoRange(withLocation: location) }
        }

        override func mouseUp(with event: NSEvent) {
            defer { deactivateHighlightRegion() }
            let location = convert(event.locationInWindow, from: nil)

            for region in highlightRegions {
                let rects = region.rects.map {
                    convertRectFromTextLayout($0.rectValue, insetForInteraction: true)
                }
                for rect in rects where rect.contains(location) {
                    self.tapHandler?(region, location)
                    break
                }
            }
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

        private func handleRightClick(with event: NSEvent) -> Bool {
            let point = convert(event.locationInWindow, from: nil)

            if isSelectable, let selectionRange, selectionRange.length > 0 {
                showContextMenu()
                return true
            }

            if let hitRegion = highlightRegionAtPoint(point),
               let linkURL = hitRegion.attributes[.link] as? URL
            {
                selectedLinkForMenuAction = linkURL
                showLinkContextMenu()
                return true
            }

            return false
        }

        private func showContextMenu() {
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

        private func showLinkContextMenu() {
            let menu = NSMenu()

            menu.addItem(
                withTitle: LocalizedText.openLink,
                action: #selector(openLink(_:)),
                keyEquivalent: ""
            )

            menu.addItem(
                withTitle: LocalizedText.copyLink,
                action: #selector(copyLink(_:)),
                keyEquivalent: ""
            )

            if let event = NSApp.currentEvent {
                NSMenu.popUpContextMenu(menu, with: event, for: self)
            }
        }

        private func updateCursorForPoint(_ point: CGPoint) {
            if !isSelectable {
                NSCursor.arrow.set()
                return
            }

            if highlightRegionAtPoint(point) != nil {
                NSCursor.pointingHand.set()
                return
            }
            
            if let index = textIndexAtPoint(point) {
                let range = NSRange(location: index, length: 1)
                let rect = textLayout?.rects(for: range).first
                if let rect {
                    let realRect = convertRectFromTextLayout(rect, insetForInteraction: true)
                    if realRect.contains(point) {
                        NSCursor.iBeam.set()
                        return
                    }
                }
            }
            
            resetCursor()
        }

        private func resetCursor() {
            NSCursor.arrow.set()
        }

        @objc private func copyLink(_: Any) {
            guard let linkURL = selectedLinkForMenuAction else { return }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(linkURL.absoluteString, forType: .string)
        }

        @objc private func openLink(_: Any) {
            guard let url = selectedLinkForMenuAction else { return }
            NSWorkspace.shared.open(url)
        }

        @objc func copyAction(_: Any?) {
            copySelectedText()
        }
    }
#endif
