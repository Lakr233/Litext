//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

#if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)

    import UIKit

    /// A long press selects the word under the finger, and a drag that follows extends
    /// the selection, as in the system text views. The menu shows when the finger lifts.
    extension TextLabelView {
        final class LongPressSelectionRecognizer: UILongPressGestureRecognizer {}

        func installLongPressSelection() {
            let recognizer = LongPressSelectionRecognizer(
                target: self,
                action: #selector(handleLongPressSelection(_:)),
            )
            // A pointer selects by dragging, and a right click shows the menu.
            recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            addGestureRecognizer(recognizer)
        }

        /// Begins only over a word in a selectable label, so a long press elsewhere, such
        /// as on a link in a label that is not selectable, keeps reaching the label's
        /// touch handling. A nested label over an attachment selects its own text.
        override open func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer is LongPressSelectionRecognizer else {
                return super.gestureRecognizerShouldBegin(gestureRecognizer)
            }
            return longPressWord(at: gestureRecognizer.location(in: self)) != nil
        }

        /// The word a long press at `location` selects, if any.
        func longPressWord(at location: CGPoint) -> NSRange? {
            guard isSelectable, !isLocationAboveAttachmentView(location: location),
                  let index = characterIndexAtPoint(location)
            else { return nil }
            let word = (textLayout.attributedString.string as NSString).rangeOfWord(at: index)
            guard word.location != NSNotFound, word.length > 0 else { return nil }
            return word
        }

        @objc private func handleLongPressSelection(_ recognizer: UILongPressGestureRecognizer) {
            longPressSelection(recognizer.state, at: recognizer.location(in: self))
        }

        /// Moves the selection for a long press in `state` at `location`, in the label's
        /// coordinates.
        func longPressSelection(_ state: UIGestureRecognizer.State, at location: CGPoint) {
            switch state {
            case .began:
                guard let word = longPressWord(at: location) else { return }
                // The recognizer cancels the label's touches; the press owns the
                // interaction until it ends.
                interactionState.longPressWordRange = word
                isInteractionInProgress = true
                hideSelectionMenuController()
                setSelectionRange(word, presentsMenu: false)
            case .changed:
                guard let word = interactionState.longPressWordRange,
                      let index = nearestTextIndexAtPoint(location)
                else { return }
                let lower = min(word.location, index)
                let upper = max(NSMaxRange(word), index)
                setSelectionRange(NSRange(location: lower, length: upper - lower), presentsMenu: false)
                reportSelectionDrag(at: location)
            case .ended, .cancelled, .failed:
                guard interactionState.longPressWordRange != nil else { return }
                interactionState.longPressWordRange = nil
                isInteractionInProgress = false
                // Presents the menu once and tells sibling labels to drop their selections.
                if let selectionGroup {
                    selectionGroup.presentSelection()
                } else {
                    updateSelectionLayer()
                }
            default:
                break
            }
        }
    }

#endif
