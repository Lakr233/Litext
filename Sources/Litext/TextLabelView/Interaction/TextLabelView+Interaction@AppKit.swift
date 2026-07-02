//
//  TextLabelView+Interaction@AppKit.swift
//  Litext
//
//  Created by 秋星桥 on 3/26/25.
//

import Foundation

#if canImport(UIKit)
// UIKit interaction is handled in TextLabelView+Touches.swift
#elseif canImport(AppKit)
    import AppKit

    public extension TextLabelView {
        /// The cursor most recently applied by any label. Re-setting the same
        /// cursor on every mouse event makes AppKit flicker, and nested labels
        /// share the cursor, so deduplication must be global — a per-view cache
        /// goes stale as soon as another label sets a different cursor.
        fileprivate static var appliedCursor: NSCursor?

        override var acceptsFirstResponder: Bool {
            isSelectable
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard event.modifierFlags.contains(.command) else {
                return super.performKeyEquivalent(with: event)
            }
            let key = event.charactersIgnoringModifiers

            if key == "c", let range = selectionRange, range.length > 0 {
                let copiedText = copySelection()
                if copiedText.length <= 0 {
                    _ = copyFromSubviewsRecursively()
                }
                return true
            }

            if key == "a", isSelectable {
                selectAll()
                return true
            }
            return false
        }

        override func rightMouseDown(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            setInteractionStateToBegin(initialLocation: location)
            defer { isInteractionInProgress = false }
            if handleRightClick(with: event) { return }
            super.rightMouseDown(with: event)
        }

        override func mouseDown(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            setInteractionStateToBegin(initialLocation: location)

            if isSelectable || highlightRegionAtPoint(location) != nil {
                window?.makeFirstResponder(self)
            }

            if isLocationAboveAttachmentView(location: location) {
                super.mouseDown(with: event)
                return
            }

            if activateHighlightRegionAtPoint(location) {
                return
            }

            interactionState.clickCount = event.clickCount
            if !isSelectable { return }

            if interactionState.clickCount <= 1 {
                if !selectionContains(location) {
                    clearSelection()
                }
            } else if interactionState.clickCount == 2 {
                if let index = nearestTextIndexAtPoint(location) {
                    selectWordAtIndex(index)
                }
            } else {
                if let index = nearestTextIndexAtPoint(location) {
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

            if isSelectable {
                updateSelectionRange(withLocation: location)
                if selectionRange != nil {
                    delegate?.textLabelView(self, didDragSelectionAt: location)
                }
            }
        }

        override func mouseUp(with event: NSEvent) {
            isInteractionInProgress = false
            defer { deactivateHighlightRegion() }
            let location = convert(event.locationInWindow, from: nil)

            guard !isTouchReallyMoved(location) else { return }

            if let region = highlightRegionForTap(at: location) {
                delegate?.textLabelView(self, didTapHighlightRegion: region, at: location)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // AppKit hands hitTest the point in the superview's coordinate
            // space; local geometry (bounds, attachment frames, highlight
            // regions) can only be tested after converting. Skipping the
            // conversion makes a label nested at a non-zero origin — e.g.
            // inside another label's attachment view — mouse-transparent.
            let localPoint = superview.map { convert(point, from: $0) } ?? point
            if !bounds.contains(localPoint) { return nil }

            for view in attachmentViews {
                if view.frame.contains(localPoint) {
                    return super.hitTest(point)
                }
            }

            if isSelectable || highlightRegionAtPoint(localPoint) != nil {
                return self
            }
            return super.hitTest(point)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            for trackingArea in trackingAreas {
                removeTrackingArea(trackingArea)
            }

            // .cursorUpdate lets this view own cursor changes; without it AppKit
            // resets the cursor to arrow between our mouseMoved updates, which
            // reads as flickering between the arrow and the I-beam.
            let options: NSTrackingArea.Options = [
                .mouseEnteredAndExited,
                .mouseMoved,
                .cursorUpdate,
                .activeInKeyWindow,
            ]
            let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(trackingArea)
        }

        override func cursorUpdate(with event: NSEvent) {
            // Intentionally not calling super: it would reset to the arrow cursor.
            let point = convert(event.locationInWindow, from: nil)
            applyCursor(desiredCursor(at: point))
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            let point = convert(event.locationInWindow, from: nil)
            applyCursor(desiredCursor(at: point))
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            applyCursor(.arrow)
            Self.appliedCursor = nil
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            let point = convert(event.locationInWindow, from: nil)
            applyCursor(desiredCursor(at: point))
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

        /// Resolves which cursor the point deserves, or `nil` when another view
        /// owns the cursor at that location. The whole label surface is
        /// treated as text (like NSTextView) instead of hit-testing individual
        /// glyph rects — per-glyph tests alternate between hit and miss while the
        /// pointer moves, which flickered between the arrow and the I-beam.
        private func desiredCursor(at point: CGPoint) -> NSCursor? {
            if isLocationAboveAttachmentView(location: point) {
                // A nested TextLabelView runs this same tracking-area logic for
                // its own surface; applying .arrow from here would fight it.
                if nestedTextLabelView(at: point) != nil { return nil }
                return .arrow
            }
            if highlightRegionAtPoint(point) != nil {
                return .pointingHand
            }
            if isSelectable {
                return .iBeam
            }
            return .arrow
        }

        /// The label (if any) that would receive mouse events inside an
        /// attachment view under the given point in local coordinates.
        private func nestedTextLabelView(at point: CGPoint) -> TextLabelView? {
            for view in attachmentViews where view.frame.contains(point) {
                // NSView.hitTest expects the point in the receiver's superview
                // coordinates — attachment views are direct subviews, so the
                // local point is already in the right space.
                var hit = view.hitTest(point)
                while let current = hit {
                    if let label = current as? TextLabelView { return label }
                    hit = current.superview
                }
            }
            return nil
        }

        private func applyCursor(_ cursor: NSCursor?) {
            guard let cursor else { return }
            guard Self.appliedCursor !== cursor else { return }
            Self.appliedCursor = cursor
            cursor.set()
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
            let copiedText = copySelection()
            if copiedText.length <= 0 {
                _ = copyFromSubviewsRecursively()
            }
        }
    }
#endif
