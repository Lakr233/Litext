//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreGraphics
import CoreText
import Foundation
import QuartzCore

extension LTXLabel {
    func updateSelectionLayer() {
        selectionLayer?.removeFromSuperlayer()
        selectionLayer = nil

        guard let textLayout,
              let range = selectionRange,
              range.location != NSNotFound,
              range.length > 0
        else {
            #if canImport(UIKit) && !targetEnvironment(macCatalyst)
                hideSelectionMenuController()
            #endif
            return
        }

        let selectionPath = LTXPlatformBezierPath()
        let selectionRects = textLayout.rects(for: range)
        guard !selectionRects.isEmpty else {
            #if canImport(UIKit) && !targetEnvironment(macCatalyst)
                hideSelectionMenuController()
            #endif
            return
        }

        createSelectionPath(selectionPath, fromRects: selectionRects)
        createSelectionLayer(withPath: selectionPath)

        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
            showSelectionMenuController()
        #endif
    }

    private func createSelectionPath(_ selectionPath: LTXPlatformBezierPath, fromRects rects: [CGRect]) {
        for rect in rects {
            let convertedRect = convertRectFromTextLayout(rect, insetForInteraction: false)

            #if canImport(UIKit)
                let subpath = LTXPlatformBezierPath(rect: convertedRect)
                selectionPath.append(subpath)
            #elseif canImport(AppKit)
                let subpath = LTXPlatformBezierPath(rect: convertedRect)
                selectionPath.appendPath(subpath)
            #else
                #error("unsupported platform")
            #endif
        }
    }

    private func createSelectionLayer(withPath path: LTXPlatformBezierPath) {
        let selLayer = CAShapeLayer()

        #if canImport(UIKit)
            selLayer.path = path.cgPath
        #elseif canImport(AppKit)
            selLayer.path = path.quartzPath
        #else
            #error("unsupported platform")
        #endif

        #if canImport(UIKit)
            selLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.1).cgColor
        #elseif canImport(AppKit)
            selLayer.fillColor = NSColor.linkColor.withAlphaComponent(0.1).cgColor
        #else
            #error("unsupported platform")
        #endif

        #if canImport(UIKit)
            layer.insertSublayer(selLayer, at: 0)
        #elseif canImport(AppKit)
            layer?.insertSublayer(selLayer, at: 0)
        #else
            #error("unsupported platform")
        #endif

        selectionLayer = selLayer
    }
}
