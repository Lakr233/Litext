//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation

public extension LTXLabel {
    #if canImport(UIKit)
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            if !bounds.contains(point) {
                return false
            }
            if highlightRegionAtPoint(point) == nil {
                return super.point(inside: point, with: event)
            }
            return true
        }

        override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let firstTouch = touches.first else { return }
            let touchLocation = firstTouch.location(in: self)

            initialTouchLocation = touchLocation

            if let hitHighlightRegion = highlightRegionAtPoint(touchLocation) {
                addActiveHighlightRegion(hitHighlightRegion)
            }

            isTouchSequenceActive = true
        }

        override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard activeHighlightRegion != nil, let firstTouch = touches.first else { return }

            let currentLocation = firstTouch.location(in: self)
            let distance = hypot(currentLocation.x - initialTouchLocation.x, currentLocation.y - initialTouchLocation.y)

            if distance > 2 {
                removeActiveHighlightRegion()
                isTouchSequenceActive = false
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let activeHighlightRegion else {
                isTouchSequenceActive = false
                return
            }

            // FIXME: currently a single touch is supported
            guard let firstTouch = touches.first else { return }
            let touchLocation = firstTouch.location(in: self)

            if isHighlightRegion(activeHighlightRegion, containsPoint: touchLocation) {
                tapHandler?(activeHighlightRegion, touchLocation)
            }

            removeActiveHighlightRegion()
            isTouchSequenceActive = false
        }

        override func touchesCancelled(_: Set<UITouch>, with _: UIEvent?) {
            removeActiveHighlightRegion()
            isTouchSequenceActive = false
        }

    #elseif canImport(AppKit)
        override func mouseDown(with event: NSEvent) {
            let touchLocation = convert(event.locationInWindow, from: nil)
            initialTouchLocation = touchLocation

            if let hitHighlightRegion = highlightRegionAtPoint(touchLocation) {
                addActiveHighlightRegion(hitHighlightRegion)
            }

            isTouchSequenceActive = true
        }

        override func mouseDragged(with event: NSEvent) {
            guard activeHighlightRegion != nil else { return }

            let currentLocation = convert(event.locationInWindow, from: nil)
            let distance = hypot(currentLocation.x - initialTouchLocation.x, currentLocation.y - initialTouchLocation.y)

            if distance > 4.0 {
                removeActiveHighlightRegion()
                isTouchSequenceActive = false
            }
        }

        override func mouseUp(with event: NSEvent) {
            guard let activeHighlightRegion else {
                isTouchSequenceActive = false
                return
            }

            let touchLocation = convert(event.locationInWindow, from: nil)

            if isHighlightRegion(activeHighlightRegion, containsPoint: touchLocation) {
                tapHandler?(activeHighlightRegion, touchLocation)
            }

            removeActiveHighlightRegion()
            isTouchSequenceActive = false
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            if !bounds.contains(point) { return nil }
            if highlightRegionAtPoint(point) == nil {
                return super.hitTest(point)
            }
            return self
        }

    #else
        #error("unsupported platform")
    #endif
}
