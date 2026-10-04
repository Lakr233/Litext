//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

#if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)

    import UIKit

    /// Drags a label's selection handles from a recognizer on the label's window.
    ///
    /// A handle's knob sits outside the label, above the first selected line or below
    /// the last. UIKit asks a view about a touch only when every ancestor contains it,
    /// and a later sibling such as the next table cell takes the touch first, so a
    /// handle view cannot be grabbed there. A recognizer on the window sees every touch.
    /// This one takes only touches in a visible handle's grab area and begins as soon as
    /// such a touch lands, so the views under the touch never receive it and the other
    /// recognizers yield while the handle is being dragged.
    ///
    /// The drag follows the recognizer's touches rather than its action messages. On
    /// iOS 18, and most often on iPad, a context menu interaction on a view under the
    /// touch, such as a host's chat row, holds back the action messages until the
    /// finger lifts, while the touches still arrive as the finger moves.
    ///
    /// The label owns this object and keeps the recognizer on its current window only
    /// while its handles show. The object holds the label weakly, so a window that
    /// retains the recognizer and its target never keeps the label alive.
    @MainActor
    final class SelectionHandleGrabGesture: NSObject {
        private weak var label: TextLabelView?
        let recognizer = Recognizer()
        private var drag: Drag?

        private struct Drag {
            let kind: SelectionHandle.Kind
            /// Where the drag reports the handle, in the label's coordinates, when the
            /// touch began.
            let anchor: CGPoint
            /// Where the touch began, in the label's coordinates.
            let touchLocation: CGPoint
        }

        init(label: TextLabelView) {
            self.label = label
            super.init()
            // Keep the touch from the views under it, so grabbing a knob that lies
            // over a link or a cell neither taps nor highlights it.
            recognizer.delaysTouchesBegan = true
            recognizer.delegate = self
            recognizer.grab = self
        }

        /// The window the recognizer is on, if any.
        var window: UIWindow? {
            recognizer.view as? UIWindow
        }

        /// Moves the recognizer to `window`, or removes it when `window` is nil.
        func attach(to window: UIWindow?) {
            guard recognizer.view !== window else { return }
            detach()
            window?.addGestureRecognizer(recognizer)
        }

        /// Removes the recognizer from its window, ending a drag in progress.
        func detach() {
            guard let view = recognizer.view else { return }
            view.removeGestureRecognizer(recognizer)
            endDrag()
        }

        /// Removes the recognizer when its label deallocates. A view deallocates on the
        /// main thread; the hop covers a label released elsewhere.
        nonisolated func detachWhenLabelDeallocates() {
            if Thread.isMainThread {
                MainActor.assumeIsolated { detach() }
            } else {
                DispatchQueue.main.async { self.detach() }
            }
        }

        /// The handle whose grab area contains `point`, in the window's coordinates, or
        /// nil when the touch there belongs to something else.
        func handleKind(atWindowPoint point: CGPoint) -> SelectionHandle.Kind? {
            guard let label,
                  let window,
                  label.window === window,
                  label.isVisibleForHandleGrab
            else { return nil }

            let labelPoint = window.convert(point, to: label)
            guard let kind = label.selectionHandleKind(at: labelPoint) else { return nil }

            // Leave the touch alone when something outside the label's own screen lies
            // over the handle, such as a navigation bar, a presented sheet or the menu.
            if window.hitTest(point, with: nil) != nil, !label.isOnOwnScreen(atWindowPoint: point) {
                return nil
            }
            return kind
        }

        fileprivate func touchDidBegin(_ touch: UITouch) {
            guard drag == nil,
                  let label,
                  let kind = handleKind(atWindowPoint: touch.location(in: nil))
            else { return }
            let anchor: CGPoint
            #if !os(visionOS)
                guard let point = label.selectionHandleAnchor(kind) else { return }
                anchor = point
            #else
                let handle = label.selectionHandle(kind)
                anchor = handle.convert(handle.lineAnchor, to: label)
            #endif
            drag = Drag(
                kind: kind,
                anchor: anchor,
                touchLocation: touch.location(in: label),
            )
            label.selectionHandleDidBeginDrag(kind)
            #if !os(visionOS)
                label.beginSelectionLoupe(at: touch.location(in: label), kind: kind, fromHandle: true)
            #endif
        }

        fileprivate func touchDidMove(_ touch: UITouch) {
            guard let drag, let label else { return }
            let location = touch.location(in: label)
            let point = CGPoint(
                x: drag.anchor.x + location.x - drag.touchLocation.x,
                y: drag.anchor.y + location.y - drag.touchLocation.y,
            )
            label.selectionHandleDidMove(drag.kind, toLocationInSuperView: point)
            #if !os(visionOS)
                label.moveSelectionLoupe(at: location, kind: drag.kind)
            #endif
        }

        fileprivate func endDrag() {
            guard let drag else { return }
            // Cleared first: ending the drag rebuilds the selection, which can detach
            // the recognizer and come back here.
            self.drag = nil
            #if !os(visionOS)
                label?.endSelectionLoupe()
            #endif
            label?.selectionHandleDidEndDrag(drag.kind)
        }
    }

    extension SelectionHandleGrabGesture {
        /// Reports its touches to the drag as they arrive. It takes one touch at a time:
        /// the delegate admits only touches on a handle, and the label is exclusive touch.
        final class Recognizer: UIGestureRecognizer {
            fileprivate weak var grab: SelectionHandleGrabGesture?

            override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
                super.touchesBegan(touches, with: event)
                guard let touch = touches.first,
                      let grab,
                      grab.handleKind(atWindowPoint: touch.location(in: nil)) != nil
                else {
                    state = .failed
                    return
                }
                grab.touchDidBegin(touch)
                state = .began
            }

            override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
                super.touchesMoved(touches, with: event)
                if let touch = touches.first {
                    grab?.touchDidMove(touch)
                    state = .changed
                }
            }

            override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
                super.touchesEnded(touches, with: event)
                grab?.endDrag()
                state = .ended
            }

            override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
                super.touchesCancelled(touches, with: event)
                grab?.endDrag()
                state = .cancelled
            }

            override func canPrevent(_ other: UIGestureRecognizer) -> Bool {
                grab?.label?.interactionState.isDraggingSelectionHandle == true &&
                    !(other.delegate is SelectionHandleGrabGesture)
            }

            override func canBePrevented(by other: UIGestureRecognizer) -> Bool {
                guard grab?.label?.interactionState.isDraggingSelectionHandle != true else { return false }
                return super.canBePrevented(by: other)
            }

            /// Also ends the drag when UIKit cancels the recognizer without sending it
            /// the touches' end.
            override func reset() {
                super.reset()
                grab?.endDrag()
            }
        }
    }

    extension SelectionHandleGrabGesture: UIGestureRecognizerDelegate {
        func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            handleKind(atWindowPoint: touch.location(in: nil)) != nil
        }
    }

    extension TextLabelView {
        func selectionHandle(_ kind: SelectionHandle.Kind) -> SelectionHandle {
            switch kind {
            case .start: selectionHandleStart
            case .end: selectionHandleEnd
            }
        }

        /// The visible handle whose grab area contains `point`, in the label's
        /// coordinates. Where both grab areas contain it, the nearer knob wins.
        func selectionHandleKind(at point: CGPoint) -> SelectionHandle.Kind? {
            #if !os(visionOS)
                if #available(iOS 17.0, *), usesSystemSelectionDisplay {
                    let candidates = [SelectionHandle.Kind.start, .end].compactMap { kind -> (SelectionHandle.Kind, CGRect)? in
                        guard let handle = displayedSelectionHandle(kind) else { return nil }
                        let rect = handle.convert(handle.bounds, to: self)
                        guard rect.insetBy(dx: -22, dy: -22).contains(point) else { return nil }
                        return (kind, rect)
                    }
                    return candidates.min { lhs, rhs in
                        let lhsY = lhs.0 == .start ? lhs.1.minY : lhs.1.maxY
                        let rhsY = rhs.0 == .start ? rhs.1.minY : rhs.1.maxY
                        return hypot(point.x - lhs.1.midX, point.y - lhsY) < hypot(point.x - rhs.1.midX, point.y - rhsY)
                    }?.0
                }
            #endif
            let candidates = [SelectionHandle.Kind.start, .end].filter { kind in
                let handle = selectionHandle(kind)
                return !handle.isHidden && handle.grabArea.contains(point)
            }
            return candidates.min { lhs, rhs in
                selectionHandle(lhs).knobDistance(to: point) < selectionHandle(rhs).knobDistance(to: point)
            }
        }

        /// Whether the label shows on screen and takes touches, along with every view
        /// up to its window.
        var isVisibleForHandleGrab: Bool {
            var view: UIView? = self
            while let current = view, !(current is UIWindow) {
                if current.isHidden || current.alpha < 0.01 || !current.isUserInteractionEnabled {
                    return false
                }
                view = current.superview
            }
            return view != nil
        }

        /// Keeps the grab recognizer on the label's window while its handles show, and
        /// off every window otherwise.
        func updateSelectionHandleGrabGesture() {
            // A group's handle can move to another member during a drag; the recognizer
            // that began the drag stays until it ends.
            var showsHandles = !selectionHandleStart.isHidden || !selectionHandleEnd.isHidden
            #if !os(visionOS)
                if usesSystemSelectionDisplay {
                    showsHandles = displayedSelectionHandle(.start) != nil || displayedSelectionHandle(.end) != nil
                }
            #endif
            showsHandles = showsHandles || interactionState.isDraggingSelectionHandle
            guard showsHandles, !isHidden, let window else {
                selectionHandleGrabGesture?.detach()
                return
            }
            let gesture = selectionHandleGrabGesture ?? SelectionHandleGrabGesture(label: self)
            selectionHandleGrabGesture = gesture
            gesture.attach(to: window)
        }
    }

#endif
