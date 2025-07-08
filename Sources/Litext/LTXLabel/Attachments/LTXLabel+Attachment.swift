//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import Foundation
import OrderedCollections

extension LTXLabel {
    func isLocationAboveAttachmentView(location: CGPoint) -> Bool {
        for view in attachmentViews {
            if view.frame.contains(location) {
                return true
            }
        }
        return false
    }

    func generateRunDelegatesForAttachments() {
        let attributeText = attributedText.mutableCopy() as! NSMutableAttributedString
        let maxWidth = preferredMaxLayoutWidth > 0 ? preferredMaxLayoutWidth : bounds.width
        Self.rebuildAttachmentRunDelegate(attributeText: attributeText, maxWidth: maxWidth)
        attributedText = attributeText
    }

    func updateAttachmentViews(reconfigureViews: Bool) {
        var previousViewMap: [String: OrderedSet<LTXPlatformView>] = attachmentViewMap
        attachmentViewMap.removeAll()

        // layout has been generated, now we need to update according to the layout
        for highlightRegion in highlightRegions {
            guard let attachment = highlightRegion.attributes[LTXAttachmentAttributeName] as? LTXAttachment else {
                continue
            }
            let typeIdentifier = attachment.viewProvider.reuseIdentifier()

            #if canImport(UIKit)
                let rect = highlightRegion.rects.first!.cgRectValue
            #elseif canImport(AppKit)
                let rect = highlightRegion.rects.first!.rectValue
            #endif

            let convertedRect = convertRectFromTextLayout(rect, insetForInteraction: false)

            // grab an existing view if available and delete it from current view map
            if var existingViews = previousViewMap[typeIdentifier], !existingViews.isEmpty {
                defer { previousViewMap[typeIdentifier] = existingViews }
                let view = existingViews.removeFirst()
                assert(view.superview == self)
                assert(view.translatesAutoresizingMaskIntoConstraints == false)
                assert(view.autoresizingMask == [])
                if view.frame != convertedRect { view.frame = convertedRect }
                if reconfigureViews { attachment.viewProvider.configureView(view, for: attachment) }
                attachmentViewMap[typeIdentifier, default: OrderedSet<LTXPlatformView>()].append(view)
            } else {
                let view = attachment.viewProvider.createView()
                view.translatesAutoresizingMaskIntoConstraints = false
                view.autoresizingMask = []
                if view.superview != self { addSubview(view) }
                view.frame = convertedRect
                attachment.viewProvider.configureView(view, for: attachment)
                attachmentViewMap[typeIdentifier, default: OrderedSet<LTXPlatformView>()].append(view)
            }
        }

        for views in previousViewMap.values {
            for view in views {
                view.removeFromSuperview()
            }
        }
    }
}

extension LTXLabel {
    static func rebuildAttachmentRunDelegate(attributeText: NSMutableAttributedString, maxWidth: CGFloat) {
        attributeText.removeAttribute(
            kCTRunDelegateAttributeName as NSAttributedString.Key,
            range: .init(location: 0, length: attributeText.length)
        )
        // enumerate through all the attachments and generate run delegates
        attributeText.enumerateAttribute(LTXAttachmentAttributeName, in: NSRange(location: 0, length: attributeText.length), options: []) { value, range, _ in
            guard let attachment = value as? LTXAttachment else { return }
            let delegate = attachment.updateRunDelegate(maxWidth: maxWidth)
            attributeText.addAttribute(
                kCTRunDelegateAttributeName as NSAttributedString.Key,
                value: delegate as Any,
                range: range
            )
        }
    }
}
