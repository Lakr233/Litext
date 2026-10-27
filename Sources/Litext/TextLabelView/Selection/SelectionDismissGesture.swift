//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

#if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)

    import UIKit

    /// Clears a label's selection when a tap lands elsewhere on its screen, as the
    /// system text views do.
    ///
    /// A tap on the label is the label's own: it clears or keeps the selection
    /// itself. A tap anywhere else reaches other views, so only a recognizer on the
    /// window sees it. This one never takes a touch from them: it cancels and delays
    /// nothing and recognizes alongside every other recognizer, and the tap still
    /// reaches the view under it. A drag fails it, so scrolling keeps the selection.
    ///
    /// It leaves alone the touches on the selection's labels and its handles, and
    /// those off the label's screen: the view of the outermost controller that
    /// contains the label's, so a child controller beside the label's, such as an
    /// input bar, is on it, and a presented sheet or a view laid over the window is
    /// not. While the selection's menu shows, a tap only dismisses the menu, as a
    /// tap on the selection does, so a tap on one of the menu's commands never clears
    /// the selection it acts on.
    ///
    /// The label owns this object and keeps the recognizer on its current window only
    /// while it holds part of a selection. The object holds the label weakly, so a
    /// window that retains the recognizer and its target never keeps the label alive.
    @MainActor
    final class SelectionDismissGesture: NSObject {
        private weak var label: TextLabelView?
        let recognizer = UITapGestureRecognizer()

        init(label: TextLabelView) {
            self.label = label
            super.init()
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            recognizer.addTarget(self, action: #selector(handleTap))
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

        func detach() {
            recognizer.view?.removeGestureRecognizer(recognizer)
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

        /// Whether a tap that began at `time`, at `point` in the window's coordinates,
        /// on `hitView`, clears the selection.
        func dismissesSelection(atWindowPoint point: CGPoint, on hitView: UIView?, at time: TimeInterval) -> Bool {
            guard let label, let window, label.window === window, let hitView,
                  !label.selectionMenuShowed(atTouchTime: time)
            else { return false }
            let members = label.selectionGroup?.labels ?? [label]
            if members.contains(where: { hitView.isDescendant(of: $0) }) {
                return false
            }
            if members.contains(where: { $0.selectionHandleKind(atWindowPoint: point, in: window) != nil }) {
                return false
            }
            var controller = label.parentViewController
            while let parent = controller?.parent {
                controller = parent
            }
            return hitView.isDescendant(of: controller?.view ?? window)
        }

        /// Clears the selection, with every member of its group.
        func dismiss() {
            label?.clearSelection()
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            dismiss()
        }
    }

    extension SelectionDismissGesture: UIGestureRecognizerDelegate {
        func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            dismissesSelection(atWindowPoint: touch.location(in: nil), on: touch.view, at: touch.timestamp)
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer,
        ) -> Bool {
            true
        }
    }

    extension TextLabelView {
        /// Keeps the dismiss recognizer on the label's window while the label holds part
        /// of a selection, and off every window otherwise.
        func updateSelectionDismissGesture() {
            guard (selectionRange?.length ?? 0) > 0, !isHidden, let window else {
                selectionDismissGesture?.detach()
                return
            }
            let gesture = selectionDismissGesture ?? SelectionDismissGesture(label: self)
            selectionDismissGesture = gesture
            gesture.attach(to: window)
        }
    }

#endif
