//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import Foundation
import QuartzCore

#if !os(watchOS)

    extension LTXLabel {
        func activateHighlightRegionAtPoint(_ location: CGPoint) -> Bool {
            if let hitHighlightRegion = highlightRegionAtPoint(location) {
                addActiveHighlightRegion(hitHighlightRegion)
                return true
            }
            return false
        }

        func deactivateHighlightRegion() {
            removeActiveHighlightRegion()
        }

        func highlightRegionAtPoint(_ point: CGPoint) -> LTXHighlightRegion? {
            for region in highlightRegions {
                guard region.kind == .link else { continue }
                if isHighlightRegion(region, containsPoint: point) {
                    return region
                }
            }
            return nil
        }

        func highlightRegionForTap(at point: CGPoint) -> LTXHighlightRegion? {
            if let attachmentRegion = highlightRegions.first(where: {
                $0.kind == .attachment && isHighlightRegion($0, containsPoint: point)
            }) {
                return attachmentRegion
            }

            return highlightRegions.first { isHighlightRegion($0, containsPoint: point) }
        }

        func isHighlightRegion(_ highlightRegion: LTXHighlightRegion, containsPoint point: CGPoint) -> Bool {
            for rect in highlightRegion.cgRects {
                let convertedRect = convertRectFromTextLayout(rect, insetForInteraction: true)
                if convertedRect.contains(point) {
                    return true
                }
            }
            return false
        }

        func addActiveHighlightRegion(_ highlightRegion: LTXHighlightRegion) {
            removeActiveHighlightRegion()
            removePendingHighlightLayers()

            activeHighlightRegion = highlightRegion

            let highlightPath = LTXPlatformBezierPath()
            let cornerRadius: CGFloat = 4
            for rect in highlightRegion.cgRects {
                let convertedRect = convertRectFromTextLayout(rect, insetForInteraction: true)
                #if canImport(UIKit)
                    let subpath = LTXPlatformBezierPath(roundedRect: convertedRect, cornerRadius: cornerRadius)
                    highlightPath.append(subpath)
                #elseif canImport(AppKit)
                    let subpath = LTXPlatformBezierPath(roundedRect: convertedRect, xRadius: cornerRadius, yRadius: cornerRadius)
                    highlightPath.append(subpath)
                #endif
            }

            let highlightColor: PlatformColor = if let color = highlightRegion.attributes[.foregroundColor] as? PlatformColor {
                color
            } else {
                LTXDefaultLinkHighlightFallbackColor
            }

            let highlightLayer = CAShapeLayer()
            highlightLayer.path = cgPath(from: highlightPath)
            highlightLayer.fillColor = highlightColor.withAlphaComponent(0.1).cgColor
            ltxBackingLayer?.addSublayer(highlightLayer)

            highlightRegion.associatedObject = highlightLayer
        }

        private func removeActiveHighlightRegion() {
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
