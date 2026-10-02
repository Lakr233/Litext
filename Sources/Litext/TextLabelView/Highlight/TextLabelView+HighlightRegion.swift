//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import Foundation
import QuartzCore

#if !os(watchOS)

    public extension TextLabelView {
        /// The link or attachment region a tap at `point`, in the label's
        /// coordinates, would report to the delegate, or `nil`. An attachment wins
        /// over a link that overlaps it. Use it for long-press previews, hover cards
        /// or menus of your own.
        ///
        /// The test uses the same slightly enlarged rects a tap does. It walks the
        /// regions and their rects, so it costs nothing on text without links or
        /// attachments.
        func highlightRegion(at point: CGPoint) -> TextLabel.HighlightRegion? {
            highlightRegionForTap(at: point)
        }
    }

    extension TextLabelView {
        /// Shows the press highlight on the link under `location`, if any.
        func activateLinkRegion(at location: CGPoint) -> Bool {
            if let hitRegion = linkRegion(at: location) {
                addActiveHighlightRegion(hitRegion)
                return true
            }
            return false
        }

        /// The link region under `point`. Attachment regions are ignored.
        func linkRegion(at point: CGPoint) -> TextLabel.HighlightRegion? {
            highlightRegions.first { $0.kind == .link && isHighlightRegion($0, containsPoint: point) }
        }

        /// The region a tap at `point` activates: an attachment wins over a link
        /// that overlaps it, and otherwise any region under the point is returned.
        func highlightRegionForTap(at point: CGPoint) -> TextLabel.HighlightRegion? {
            if let attachmentRegion = highlightRegions.first(where: {
                $0.kind == .attachment && isHighlightRegion($0, containsPoint: point)
            }) {
                return attachmentRegion
            }

            return highlightRegions.first { isHighlightRegion($0, containsPoint: point) }
        }

        func isHighlightRegion(_ highlightRegion: TextLabel.HighlightRegion, containsPoint point: CGPoint) -> Bool {
            for rect in highlightRegion.rects {
                let convertedRect = convertRectFromTextLayout(rect, insetForInteraction: true)
                if convertedRect.contains(point) {
                    return true
                }
            }
            return false
        }

        func addActiveHighlightRegion(_ highlightRegion: TextLabel.HighlightRegion) {
            deactivateHighlightRegion()
            removePendingHighlightLayers()

            activeHighlightRegion = highlightRegion

            // A link styled character by character has a rect per character.
            // Appending to a bezier path copies it each time, which is quadratic,
            // so the rounded rects are collected in a Core Graphics path instead.
            let highlightPath = CGMutablePath()
            let cornerRadius = max(linkHighlightCornerRadius, 0)
            for rect in highlightRegion.rects {
                let convertedRect = convertRectFromTextLayout(rect, insetForInteraction: true)
                #if canImport(UIKit)
                    let subpath = PlatformBezierPath(roundedRect: convertedRect, cornerRadius: cornerRadius)
                #elseif canImport(AppKit)
                    let subpath = PlatformBezierPath(roundedRect: convertedRect, xRadius: cornerRadius, yRadius: cornerRadius)
                #endif
                highlightPath.addPath(cgPath(from: subpath))
            }

            let highlightColor: PlatformColor = if let linkHighlightColor {
                linkHighlightColor
            } else if let color = highlightRegion.attributes[.foregroundColor] as? PlatformColor {
                color.withAlphaComponent(0.1)
            } else {
                defaultLinkHighlightFallbackColor.withAlphaComponent(0.1)
            }

            let highlightLayer = CAShapeLayer()
            highlightLayer.path = highlightPath
            highlightLayer.fillColor = highlightColor.cgColor
            backingLayer?.addSublayer(highlightLayer)

            highlightRegion.associatedObject = highlightLayer
        }

        /// Fades out and removes the press highlight, if one is showing.
        func deactivateHighlightRegion() {
            guard let activeHighlightRegion else { return }

            if let highlightLayer = activeHighlightRegion.associatedObject as? CALayer {
                pendingHighlightRemovalLayers.append(highlightLayer)
                highlightLayer.opacity = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak highlightLayer] in
                    guard let highlightLayer else { return }
                    highlightLayer.removeFromSuperlayer()
                    self?.pendingHighlightRemovalLayers.removeAll { $0 === highlightLayer }
                }
            }

            activeHighlightRegion.associatedObject = nil
            self.activeHighlightRegion = nil
        }

        private func removePendingHighlightLayers() {
            pendingHighlightRemovalLayers.forEach { $0.removeFromSuperlayer() }
            pendingHighlightRemovalLayers.removeAll()
        }
    }

#endif // !os(watchOS)
