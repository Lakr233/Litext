//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import Foundation
import QuartzCore

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
            if isHighlightRegion(region, containsPoint: point) {
                if region.attributes[.link] == nil {
                    continue
                }
                return region
            }
        }
        return nil
    }

    func isHighlightRegion(_ highlightRegion: LTXHighlightRegion, containsPoint point: CGPoint) -> Bool {
        for boxedRect in highlightRegion.rects {
            #if canImport(UIKit)
                let rect = boxedRect.cgRectValue
            #elseif canImport(AppKit)
                let rect = boxedRect.rectValue
            #endif
            let convertedRect = convertRectFromTextLayout(rect, insetForInteraction: true)
            if convertedRect.contains(point) {
                return true
            }
        }
        return false
    }

    func addActiveHighlightRegion(_ highlightRegion: LTXHighlightRegion) {
        removeActiveHighlightRegion()

        activeHighlightRegion = highlightRegion

        let highlightPath = LTXPlatformBezierPath()
        for boxedRect in highlightRegion.rects {
            #if canImport(UIKit)
                let rect = boxedRect.cgRectValue
            #elseif canImport(AppKit)
                let rect = boxedRect.rectValue
            #endif
            let convertedRect = convertRectFromTextLayout(rect, insetForInteraction: true)
            #if canImport(UIKit)
                let subpath = LTXPlatformBezierPath(roundedRect: convertedRect, cornerRadius: 4)
                highlightPath.append(subpath)
            #elseif canImport(AppKit)
                let subpath = LTXPlatformBezierPath(roundedRect: convertedRect, xRadius: 4, yRadius: 4)
                highlightPath.append(subpath)
            #endif
        }

        let highlightColor: PlatformColor = if let color = highlightRegion.attributes[.foregroundColor] as? PlatformColor {
            color
        } else {
            .systemBlue
        }

        let highlightLayer = CAShapeLayer()
        #if canImport(UIKit)
            highlightLayer.path = highlightPath.cgPath
        #elseif canImport(AppKit)
            if #available(macOS 14.0, *) {
                highlightLayer.path = highlightPath.cgPath
            } else {
                highlightLayer.path = highlightPath.quartzPath
            }
        #endif
        highlightLayer.fillColor = highlightColor.withAlphaComponent(0.1).cgColor
        #if canImport(UIKit)
            layer.addSublayer(highlightLayer)
        #elseif canImport(AppKit)
            layer?.addSublayer(highlightLayer)
        #endif

        highlightRegion.associatedObject = highlightLayer
    }

    private func removeActiveHighlightRegion() {
        guard let activeHighlightRegion else { return }

        if let highlightLayer = activeHighlightRegion.associatedObject as? CALayer {
            highlightLayer.opacity = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                highlightLayer.removeFromSuperlayer()
            }
        }

        activeHighlightRegion.associatedObject = nil
        self.activeHighlightRegion = nil
    }
}
