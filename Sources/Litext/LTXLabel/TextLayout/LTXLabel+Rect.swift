//
//  LTXLabel+Rect.swift
//  Litext
//
//  Created by 秋星桥 on 3/27/25.
//

import Foundation
import QuartzCore

#if !os(watchOS)

    private let visibleTextDrawingOverscan: CGFloat = 96

    extension LTXLabel {
        func visibleTextDrawingRect(for dirtyRect: CGRect) -> CGRect? {
            let labelBounds = bounds.standardized
            guard !labelBounds.isEmpty else { return nil }

            let dirtyBounds = dirtyRect.isEmpty ? labelBounds : dirtyRect.standardized
            guard drawsOnlyVisibleText else {
                let dirtyVisibleRect = dirtyBounds.intersection(labelBounds)
                guard !dirtyVisibleRect.isNull, !dirtyVisibleRect.isEmpty else { return nil }
                return dirtyVisibleRect
            }

            var visibleRect = labelBounds
            #if canImport(UIKit)
                guard let window else { return visibleRect }
                guard !isHidden, alpha > 0.01 else { return nil }

                var visibleInWindow = convert(labelBounds, to: window)
                visibleInWindow = visibleInWindow.intersection(window.bounds)

                var ancestor = superview
                while let view = ancestor {
                    guard !view.isHidden, view.alpha > 0.01 else { return nil }
                    if view.clipsToBounds || view is UIScrollView || view === window {
                        visibleInWindow = visibleInWindow.intersection(view.convert(view.bounds, to: window))
                    }
                    ancestor = view.superview
                }

                guard !visibleInWindow.isNull, !visibleInWindow.isEmpty else { return nil }
                visibleRect = visibleRect.intersection(convert(visibleInWindow, from: window))
            #elseif canImport(AppKit)
                guard !isHidden else { return nil }
                visibleRect = visibleRect.intersection(visibleRectInOwnCoordinates)
            #endif

            guard !visibleRect.isNull, !visibleRect.isEmpty else { return nil }
            return visibleRect.insetBy(
                dx: -1,
                dy: -visibleTextDrawingOverscan
            ).intersection(labelBounds)
        }

        #if canImport(UIKit) && !os(watchOS)
            func updateVisibleRenderingObservation() {
                guard drawsOnlyVisibleText else {
                    visibleRenderingScrollView = nil
                    visibleRenderingBoundsObservation = nil
                    visibleRenderingContentOffsetObservation = nil
                    return
                }

                let scrollView = nearestScrollingAncestor()
                guard scrollView !== visibleRenderingScrollView else { return }

                visibleRenderingScrollView = scrollView
                visibleRenderingBoundsObservation = scrollView?.observe(
                    \.bounds,
                    options: [.new]
                ) { [weak self] _, _ in
                    Task { @MainActor [weak self] in
                        self?.setNeedsTextDisplay()
                    }
                }
                visibleRenderingContentOffsetObservation = scrollView?.observe(
                    \.contentOffset,
                    options: [.new]
                ) { [weak self] _, _ in
                    Task { @MainActor [weak self] in
                        self?.setNeedsTextDisplay()
                    }
                }
            }

            private func nearestScrollingAncestor() -> UIScrollView? {
                var ancestor = superview
                while let view = ancestor {
                    if let scrollView = view as? UIScrollView {
                        return scrollView
                    }
                    ancestor = view.superview
                }
                return nil
            }
        #endif

        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
            func updateVisibleRenderingObservation() {
                guard drawsOnlyVisibleText else {
                    visibleRenderingClipView = nil
                    if let visibleRenderingBoundsObserver {
                        NotificationCenter.default.removeObserver(visibleRenderingBoundsObserver)
                    }
                    visibleRenderingBoundsObserver = nil
                    return
                }

                let clipView = nearestClipViewAncestor()
                guard clipView !== visibleRenderingClipView else { return }

                if let visibleRenderingBoundsObserver {
                    NotificationCenter.default.removeObserver(visibleRenderingBoundsObserver)
                }
                visibleRenderingClipView = clipView
                visibleRenderingBoundsObserver = nil

                guard let clipView else { return }
                clipView.postsBoundsChangedNotifications = true
                visibleRenderingBoundsObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: clipView,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.setNeedsTextDisplay()
                    }
                }
            }

            private func nearestClipViewAncestor() -> NSClipView? {
                var ancestor = superview
                while let view = ancestor {
                    if let clipView = view as? NSClipView {
                        return clipView
                    }
                    ancestor = view.superview
                }
                return enclosingScrollView?.contentView
            }

            private var visibleRectInOwnCoordinates: CGRect {
                visibleRect.intersection(bounds)
            }
        #endif

        func convertRectFromTextLayout(_ rect: CGRect, insetForInteraction useInset: Bool) -> CGRect {
            var result = rect
            result.origin.y = bounds.height - result.origin.y - result.size.height
            if useInset { result = result.insetBy(dx: -4, dy: -4) }
            return result
        }

        var ltxBackingLayer: CALayer? {
            #if canImport(UIKit)
                return layer
            #elseif canImport(AppKit)
                wantsLayer = true
                return layer
            #endif
        }

        func cgPath(from path: LTXPlatformBezierPath) -> CGPath {
            #if canImport(UIKit)
                return path.cgPath
            #elseif canImport(AppKit)
                if #available(macOS 14.0, *) {
                    return path.cgPath
                }
                return path.quartzPath
            #endif
        }
    }

#endif // !os(watchOS)
