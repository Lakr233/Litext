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

    /// Subclasses that override a mouse, key or hit-testing hook below must call
    /// `super` for the events they do not consume, or selection and link clicks stop working.
    extension TextLabelView {
        /// The cursor most recently applied by any label. Re-setting the same
        /// cursor on every mouse event makes AppKit flicker, and nested labels
        /// share the cursor, so deduplication must be global — a per-view cache
        /// goes stale as soon as another label sets a different cursor.
        fileprivate static var appliedCursor: NSCursor?

        override open var acceptsFirstResponder: Bool {
            isSelectable
        }

        override open func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else {
                return super.performKeyEquivalent(with: event)
            }
            guard event.modifierFlags.contains(.command) else {
                return super.performKeyEquivalent(with: event)
            }
            let key = event.charactersIgnoringModifiers

            // The Edit menu reaches `copy(_:)` and `selectAll(_:)` too; these keep the
            // shortcuts working in a host without one.
            if key == "c", hasCommandSelection {
                copy(nil)
                return true
            }

            if key == "a", isSelectable {
                selectAll()
                return true
            }
            return false
        }

        /// AppKit's own handling asks `menu(for:)` for the context menu.
        override open func rightMouseDown(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            setInteractionStateToBegin(initialLocation: location)
            defer { isInteractionInProgress = false }
            super.rightMouseDown(with: event)
        }

        override open func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) {
                // A control-click is a right click: AppKit shows `menu(for:)`.
                super.mouseDown(with: event)
                return
            }
            let location = convert(event.locationInWindow, from: nil)
            setInteractionStateToBegin(initialLocation: location)

            if isSelectable || linkRegion(at: location) != nil {
                window?.makeFirstResponder(self)
            }

            if isLocationAboveAttachmentView(location: location) {
                interactionState.isForwardingToSuper = true
                super.mouseDown(with: event)
                return
            }

            if activateLinkRegion(at: location) {
                return
            }

            interactionState.clickCount = event.clickCount
            if !isSelectable {
                // Hit-testing normally routes these clicks past the label. When one arrives
                // anyway, hand the whole sequence to the next responder so it gets a
                // matching mouseDragged and mouseUp.
                interactionState.isForwardingToSuper = true
                super.mouseDown(with: event)
                return
            }

            if interactionState.clickCount <= 1 {
                // A click clears the selection, inside it too, as in the system text views.
                clearSelection()
            } else if interactionState.clickCount == 2 {
                if let index = characterIndexAtPoint(location) {
                    selectWordAtIndex(index)
                }
            } else {
                if let index = characterIndexAtPoint(location) {
                    selectLineAtIndex(index)
                }
            }
        }

        override open func mouseDragged(with event: NSEvent) {
            if interactionState.isForwardingToSuper {
                super.mouseDragged(with: event)
                return
            }
            let location = convert(event.locationInWindow, from: nil)

            guard isTouchReallyMoved(location) else { return }

            deactivateHighlightRegion()

            if interactionState.isFirstMove {
                interactionState.isFirstMove = false
                selectionRange = nil
            }

            if isSelectable {
                updateSelectionRange(withLocation: location)
                reportSelectionDrag(at: location)
            }
        }

        override open func mouseUp(with event: NSEvent) {
            isInteractionInProgress = false
            defer { deactivateHighlightRegion() }
            if interactionState.isForwardingToSuper {
                interactionState.isForwardingToSuper = false
                super.mouseUp(with: event)
                return
            }
            let location = convert(event.locationInWindow, from: nil)

            guard !isTouchReallyMoved(location), !interactionState.isTapCancelled else { return }

            if let region = highlightRegionForTap(at: location) {
                delegate?.textLabelView(self, didTapHighlightRegion: region, at: location)
            }
        }

        override open func hitTest(_ point: NSPoint) -> NSView? {
            // AppKit hands hitTest the point in the superview's coordinate
            // space; local geometry (bounds, attachment frames, highlight
            // regions) can only be tested after converting. Skipping the
            // conversion makes a label nested at a non-zero origin — e.g.
            // inside another label's attachment view — mouse-transparent.
            let localPoint = superview.map { convert(point, from: $0) } ?? point
            switch hitTarget(at: localPoint) {
            case .outside:
                return nil
            case .attachment:
                // `super` expects the original, superview-space point.
                return super.hitTest(point)
            case .interactiveText:
                return self
            case .passThrough:
                // Like `point(inside:with:)` on UIKit, a non-selectable label lets clicks
                // away from its links reach the view behind it. A subview that claims the
                // point still receives it.
                let hit = super.hitTest(point)
                return hit === self ? nil : hit
            }
        }

        override open func updateTrackingAreas() {
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

        override open func cursorUpdate(with event: NSEvent) {
            // Intentionally not calling super: it would reset to the arrow cursor.
            let point = convert(event.locationInWindow, from: nil)
            applyCursor(desiredCursor(at: point))
        }

        override open func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            let point = convert(event.locationInWindow, from: nil)
            applyCursor(desiredCursor(at: point))
        }

        override open func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            applyCursor(.arrow)
            Self.appliedCursor = nil
        }

        override open func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            let point = convert(event.locationInWindow, from: nil)
            applyCursor(desiredCursor(at: point))
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
                if nestedTextLabelView(at: point) != nil {
                    return nil
                }
                return .arrow
            }
            if linkRegion(at: point) != nil {
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
                    if let label = current as? TextLabelView {
                        return label
                    }
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

        @available(*, deprecated, renamed: "copy(_:)")
        @objc public func copyAction(_ sender: Any?) {
            copy(sender)
        }
    }
#endif
