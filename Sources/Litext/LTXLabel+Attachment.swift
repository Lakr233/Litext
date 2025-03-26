//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import Foundation

extension LTXLabel {
    func updateAttachmentViews() {
        let viewsToRemove = attachmentViews
        var newAttachmentViews: Set<LTXPlatformView> = []

        for highlightRegion in highlightRegions {
            guard let attachment = highlightRegion.attributes[LTXAttachmentAttributeName] as? LTXAttachment,
                  let view = attachment.view else { continue }

            if view.superview == self {
                newAttachmentViews.insert(view)
            } else {
                addSubview(view)
                newAttachmentViews.insert(view)
            }

            #if canImport(UIKit)
                let rect = highlightRegion.rects.first!.cgRectValue
            #elseif canImport(AppKit)
                let rect = highlightRegion.rects.first!.rectValue
            #else
                #error("unsupported platform")
            #endif

            let convertedRect = convertRectFromTextLayout(rect, forInteraction: false)
            view.frame = convertedRect
        }

        for view in viewsToRemove {
            if !newAttachmentViews.contains(view) {
                view.removeFromSuperview()
            }
        }

        attachmentViews = newAttachmentViews
    }
}
