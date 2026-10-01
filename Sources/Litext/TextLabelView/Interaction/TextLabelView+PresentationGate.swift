//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

#if canImport(UIKit) && !os(tvOS) && !os(watchOS)

    import UIKit

    /// Whether the label may show selection UI, such as the edit menu or the share
    /// sheet, without it landing over a controller that covers the label.
    extension TextLabelView {
        /// Checks that the label's screen is the one on top at `rect`, in the label's
        /// coordinates.
        ///
        /// The screen is the view of the label's view controller, or the window when
        /// there is none. Selection UI stays hidden when:
        /// - the label is outside a window, or the window is hidden;
        /// - the controller, or one of its ancestors, has presented another
        ///   controller, such as a form sheet, or is being dismissed or removed;
        /// - with `hitTests`, something off the label's screen, such as a bar or a
        ///   view the host laid over the window, takes touches all over the part of
        ///   `rect` inside the window, or none of `rect` is inside it. A selection
        ///   taller than the screen, or partly under a bar, still passes where it shows.
        func canPresentSelectionUI(from rect: CGRect, hitTests: Bool = true) -> Bool {
            guard let window, !window.isHidden else { return false }
            let controller = parentViewController
            if let controller {
                // The property also reports what an ancestor presented.
                if controller.presentedViewController != nil {
                    return false
                }
                var current: UIViewController? = controller
                while let candidate = current {
                    if candidate.isBeingDismissed || candidate.isMovingFromParent {
                        return false
                    }
                    current = candidate.parent
                }
            }
            guard hitTests else { return true }
            let visible = convert(rect, to: window).intersection(window.bounds)
            guard !visible.isNull else { return false }
            // The middle, then the top and bottom of the visible part, for a selection
            // whose middle is under a bar.
            let probes = [visible.midY, visible.minY + 1, visible.maxY - 1].map {
                CGPoint(x: visible.midX, y: min(max($0, visible.minY), visible.maxY))
            }
            return probes.contains { isOnOwnScreen(atWindowPoint: $0) }
        }

        /// Whether the view that takes touches at `point`, in window coordinates,
        /// belongs to the label's screen: the view of its view controller, or the
        /// window when there is none.
        func isOnOwnScreen(atWindowPoint point: CGPoint) -> Bool {
            guard let window, let hitView = window.hitTest(point, with: nil) else { return false }
            return hitView.isDescendant(of: parentViewController?.view ?? window)
        }
    }

#elseif canImport(AppKit) && !targetEnvironment(macCatalyst)

    import AppKit

    extension TextLabelView {
        /// Checks that the label is on top at `rect`, in the label's coordinates, in a
        /// visible window with no sheet attached, so a popover such as Translate never
        /// opens over a sheet or a view the host laid over the label. Where `rect` is
        /// scrolled out of view, the visible part of the label is checked instead.
        func canPresentSelectionUI(from rect: CGRect) -> Bool {
            guard let window, window.isVisible, window.attachedSheet == nil,
                  let contentView = window.contentView, !visibleRect.isEmpty
            else { return false }
            var probe = rect.intersection(visibleRect)
            if probe.isNull {
                probe = visibleRect
            }
            let windowPoint = convert(CGPoint(x: probe.midX, y: probe.midY), to: nil)
            let point = contentView.superview?.convert(windowPoint, from: nil) ?? windowPoint
            guard let hitView = contentView.hitTest(point) else { return false }
            return hitView === self || hitView.isDescendant(of: self)
        }
    }

#endif
