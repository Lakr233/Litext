//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import Foundation

#if !os(watchOS)

    extension TextLabelView {
        func isLocationAboveAttachmentView(location: CGPoint) -> Bool {
            attachmentViews.contains { $0.frame.contains(location) }
        }

        func updateAttachmentViews() {
            var newAttachmentViews: Set<PlatformView> = []

            for highlightRegion in highlightRegions {
                guard highlightRegion.kind == .attachment,
                      let attachment = highlightRegion.attributes[.litextAttachment] as? TextLabel.Attachment,
                      let view = attachment.view,
                      let firstRect = highlightRegion.rects.first
                else { continue }

                if view.superview != self {
                    addSubview(view)
                }
                newAttachmentViews.insert(view)

                let convertedRect = convertRectFromTextLayout(firstRect, insetForInteraction: false)
                view.frame = pixelAlign(convertedRect)
            }

            // A view has one superview. When another label showing the same attachment laid
            // out later, the view now belongs to that label and must stay there.
            for view in attachmentViews.subtracting(newAttachmentViews) where view.superview === self {
                view.removeFromSuperview()
            }
            attachmentViews = newAttachmentViews
        }
    }

#endif // !os(watchOS)
