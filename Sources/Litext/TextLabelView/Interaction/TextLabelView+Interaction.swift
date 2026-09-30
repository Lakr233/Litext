//
//  TextLabelView+Interaction.swift
//  Litext
//
//  Created by 秋星桥 on 3/26/25.
//

import Foundation

#if !os(watchOS)

    private let kMinimalDistanceToMove: CGFloat = 3.0
    private let kMultiClickTimeThreshold: TimeInterval = 0.25

    extension TextLabelView {
        /// What a point in the label's own coordinates lands on, shared by UIKit
        /// `point(inside:with:)` and AppKit `hitTest(_:)` so both platforms decide alike.
        enum HitTarget {
            /// Outside the label's bounds.
            case outside
            /// Over an attachment view, which should receive the event itself.
            case attachment
            /// Over text the label handles: any text when selectable, otherwise a link.
            case interactiveText
            /// Inside the bounds but over nothing the label reacts to.
            case passThrough
        }

        func hitTarget(at localPoint: CGPoint) -> HitTarget {
            if !bounds.contains(localPoint) {
                return .outside
            }
            if isLocationAboveAttachmentView(location: localPoint) {
                return .attachment
            }
            if isSelectable || linkRegion(at: localPoint) != nil {
                return .interactiveText
            }
            return .passThrough
        }

        func setInteractionStateToBegin(initialLocation: CGPoint) {
            interactionState.initialTouchLocation = initialLocation
            interactionState.isFirstMove = true
            interactionState.clickCountAtBegin = 1
            interactionState.isForwardingToSuper = false
            interactionState.isTapCancelled = false
            isInteractionInProgress = true
        }

        func bumpClickCountIfWithinTimeGap() {
            let currentTime = Date().timeIntervalSince1970
            let isContinuousClick = currentTime - interactionState.lastClickTime <= kMultiClickTimeThreshold
            interactionState.lastClickTime = currentTime
            if isContinuousClick {
                interactionState.clickCount += 1
            }
            scheduleContinuousStateReset()
        }

        func scheduleContinuousStateReset() {
            NSObject.cancelPreviousPerformRequests(
                withTarget: self,
                selector: #selector(performContinuousStateReset),
                object: nil
            )
            perform(
                #selector(performContinuousStateReset),
                with: nil,
                afterDelay: kMultiClickTimeThreshold
            )
        }

        @objc func performContinuousStateReset() {
            interactionState.clickCount = 1
            interactionState.lastClickTime = 0
        }

        func isTouchReallyMoved(_ point: CGPoint) -> Bool {
            let distance = hypot(
                point.x - interactionState.initialTouchLocation.x,
                point.y - interactionState.initialTouchLocation.y
            )
            return distance > kMinimalDistanceToMove
        }
    }

#endif // !os(watchOS)
