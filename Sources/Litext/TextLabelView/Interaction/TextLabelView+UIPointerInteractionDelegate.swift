//
//  TextLabelView+UIPointerInteractionDelegate.swift
//  Litext
//
//  Created by 秋星桥 on 7/8/25.
//

#if canImport(UIKit) && !os(tvOS) && !os(watchOS)

    import UIKit

    @available(iOS 13.4, macCatalyst 13.4, *)
    extension TextLabelView: UIPointerInteractionDelegate {
        public func pointerInteraction(
            _: UIPointerInteraction,
            regionFor request: UIPointerRegionRequest,
            defaultRegion: UIPointerRegion
        ) -> UIPointerRegion? {
            guard isSelectable else { return nil }
            // Attachment views own the pointer over their surface — a nested
            // TextLabelView installs its own interaction, and non-text
            // attachments deserve the system default instead of a text beam.
            guard !isLocationAboveAttachmentView(location: request.location) else { return nil }
            return defaultRegion
        }

        public func pointerInteraction(_: UIPointerInteraction, styleFor _: UIPointerRegion) -> UIPointerStyle? {
            guard isSelectable else { return nil }
            guard parentViewController?.presentedViewController == nil else { return nil }
            return UIPointerStyle(shape: .verticalBeam(length: 1), constrainedAxes: [])
        }
    }

#endif
