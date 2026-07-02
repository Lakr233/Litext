//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreGraphics
import CoreText
import Foundation
import QuartzCore

#if !os(watchOS)

    private let kDeduplicateSelectionNotification = Notification.Name(
        rawValue: "TextLabelViewDeduplicateSelectionNotification"
    )

    extension TextLabelView {
        func updateSelectionLayer() {
            #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
                selectionHandleStart.isHidden = true
                selectionHandleEnd.isHidden = true
            #endif

            guard let range = selectionRange,
                  range.location != NSNotFound,
                  range.length > 0
            else {
                #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
                    hideSelectionMenuController()
                #endif
                clearSelectionLayer()
                return
            }

            let selectionPath = PlatformBezierPath()
            let selectionRects = textLayout.rects(for: range)
            guard !selectionRects.isEmpty else {
                #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
                    hideSelectionMenuController()
                #endif
                clearSelectionLayer()
                return
            }

            createSelectionPath(selectionPath, fromRects: selectionRects)
            updateSelectionLayer(withPath: selectionPath)

            #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
                showSelectionMenuController()

                selectionHandleStart.isHidden = false
                selectionHandleEnd.isHidden = false

                // Update handle colors to match selection color
                let handleColor = selectionBackgroundColor?.withAlphaComponent(1.0)
                selectionHandleStart.updateHandleColor(handleColor)
                selectionHandleEnd.updateHandleColor(handleColor)

                var beginRect = textLayout.rects(
                    for: NSRange(location: range.location, length: 1)
                ).first ?? .zero
                beginRect = convertRectFromTextLayout(beginRect, insetForInteraction: false)
                selectionHandleStart.frame = .init(
                    x: beginRect.minX - SelectionHandle.knobRadius - 1,
                    y: beginRect.minY - SelectionHandle.knobRadius,
                    width: SelectionHandle.knobRadius * 2,
                    height: beginRect.height + SelectionHandle.knobRadius
                )
                var endRect = textLayout.rects(
                    for: NSRange(location: range.location + range.length - 1, length: 1)
                ).first ?? .zero
                endRect = convertRectFromTextLayout(endRect, insetForInteraction: false)
                selectionHandleEnd.frame = .init(
                    x: endRect.maxX - SelectionHandle.knobRadius + 1,
                    y: endRect.minY,
                    width: SelectionHandle.knobRadius * 2,
                    height: endRect.height + SelectionHandle.knobRadius
                )
            #endif

            NotificationCenter.default.post(name: kDeduplicateSelectionNotification, object: self)
        }

        func registerNotificationCenterForSelectionDeduplicate() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(deduplicateSelection),
                name: kDeduplicateSelectionNotification,
                object: nil
            )
        }

        @objc private func deduplicateSelection(_ notification: Notification) {
            guard let object = notification.object as? TextLabelView, object != self else { return }
            clearSelection()
        }

        private func createSelectionPath(_ selectionPath: PlatformBezierPath, fromRects rects: [CGRect]) {
            for rect in rects {
                let convertedRect = convertRectFromTextLayout(rect, insetForInteraction: false)
                let subpath = PlatformBezierPath(rect: convertedRect)
                selectionPath.append(subpath)
            }
        }

        private func updateSelectionLayer(withPath path: PlatformBezierPath) {
            let fillColor = (selectionBackgroundColor ?? defaultSelectionTint).cgColor

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }

            if let selectionLayer {
                selectionLayer.path = cgPath(from: path)
                selectionLayer.fillColor = fillColor
                return
            }

            let selLayer = CAShapeLayer()
            selLayer.path = cgPath(from: path)
            selLayer.fillColor = fillColor
            backingLayer?.insertSublayer(selLayer, at: 0)
            selectionLayer = selLayer
        }

        private func clearSelectionLayer() {
            selectionLayer?.removeFromSuperlayer()
            selectionLayer = nil
        }
    }

#endif // !os(watchOS)
