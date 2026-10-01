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
    /// recognizers, scroll views' included, wait for it to fail.
    ///
    /// The label owns this object and keeps the recognizer on its current window only
    /// while its handles show. The object holds the label weakly, so a window that
    /// retains the recognizer and its target never keeps the label alive.
    @MainActor
    final class SelectionHandleGrabGesture: NSObject {
        private weak var label: TextLabelView?
        let recognizer = UILongPressGestureRecognizer()
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
            recognizer.minimumPressDuration = 0
            recognizer.allowableMovement = .greatestFiniteMagnitude
            // Keep the touch from the views under it, so grabbing a knob that lies
            // over a link or a cell neither taps nor highlights it.
            recognizer.delaysTouchesBegan = true
            recognizer.delegate = self
            recognizer.addTarget(self, action: #selector(handleRecognizer(_:)))
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

        @objc private func handleRecognizer(_ recognizer: UILongPressGestureRecognizer) {
            guard let label else { return }
            switch recognizer.state {
            case .began:
                let location = recognizer.location(in: label)
                guard let kind = handleKind(atWindowPoint: recognizer.location(in: nil)) else { return }
                let handle = label.selectionHandle(kind)
                let anchor = handle.lineAnchor
                drag = Drag(
                    kind: kind,
                    anchor: CGPoint(x: handle.frame.minX + anchor.x, y: handle.frame.minY + anchor.y),
                    touchLocation: location,
                )
                label.selectionHandleDidBeginDrag(kind)
            case .changed:
                guard let drag else { return }
                let location = recognizer.location(in: label)
                let point = CGPoint(
                    x: drag.anchor.x + location.x - drag.touchLocation.x,
                    y: drag.anchor.y + location.y - drag.touchLocation.y,
                )
                label.selectionHandleDidMove(drag.kind, toLocationInSuperView: point)
            case .ended, .cancelled, .failed:
                endDrag()
            default:
                break
            }
        }

        private func endDrag() {
            guard let drag else { return }
            // Cleared first: ending the drag rebuilds the selection, which can detach
            // the recognizer and come back here.
            self.drag = nil
            label?.selectionHandleDidEndDrag(drag.kind)
        }
    }

    extension SelectionHandleGrabGesture: UIGestureRecognizerDelegate {
        func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            handleKind(atWindowPoint: touch.location(in: nil)) != nil
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer,
        ) -> Bool {
            // Another label's recognizer must not wait on this one, or two labels whose
            // handles both cover a touch would each wait for the other.
            !(other.delegate is SelectionHandleGrabGesture)
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
            let showsHandles = !selectionHandleStart.isHidden || !selectionHandleEnd.isHidden
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
