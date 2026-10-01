//
//  TextLabelView+SelectionHandleDelegate.swift
//  Litext
//
//  Created by 秋星桥 on 7/8/25.
//

#if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)

    import UIKit

    /// A selection handle drag, driven by `SelectionHandleGrabGesture`.
    extension TextLabelView {
        func selectionHandleDidBeginDrag(_: SelectionHandle.Kind) {
            interactionState.isDraggingSelectionHandle = true
            isInteractionInProgress = true
            // Like the system text views, keep the menu out of the way while a handle moves
            // and bring it back once when the drag ends.
            if let selectionGroup {
                selectionGroup.hideMenu()
            } else {
                hideSelectionMenuController()
            }
        }

        func selectionHandleDidMove(_ kind: SelectionHandle.Kind, toLocationInSuperView point: CGPoint) {
            // In a group the handle can move into another member. The drag stays with
            // this label, which keeps its recognizer until the drag ends.
            if let selectionGroup {
                selectionGroup.moveEnd(isStart: kind == .start, toWindowPoint: convert(point, to: nil))
                reportSelectionDrag(at: point)
                return
            }
            guard let selectionRange, let textLocation = nearestTextIndexAtPoint(point) else { return }
            let newRange: NSRange
            switch kind {
            case .start:
                let startLocation = min(textLocation, selectionRange.location + selectionRange.length - 1)
                let length = selectionRange.location + selectionRange.length - startLocation
                newRange = .init(location: startLocation, length: length)
            case .end:
                let startLocation = selectionRange.location
                let endingLocation = max(textLocation, startLocation + 1)
                newRange = .init(location: startLocation, length: endingLocation - startLocation)
            }
            setSelectionRange(newRange, presentsMenu: false)
            if self.selectionRange != nil {
                delegate?.textLabelView(self, didDragSelectionAt: point)
            }
        }

        func selectionHandleDidEndDrag(_: SelectionHandle.Kind) {
            interactionState.isDraggingSelectionHandle = false
            isInteractionInProgress = false
            if let selectionGroup {
                // The handle may have moved to another member; drop the recognizer here
                // if this label no longer shows one.
                updateSelectionHandleGrabGesture()
                selectionGroup.presentSelection()
                return
            }
            guard selectionRange != nil else { return }
            // Presents the menu once and tells sibling labels to drop their selections.
            updateSelectionLayer()
        }
    }

#endif
