//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation
import QuartzCore

public extension LTXLabel {
    func invalidateTextLayout() {
        if let selectionRange,
           attributedText.length >= selectionRange.location + selectionRange.length
        { /* pass */ } else {
            clearSelection()
        }

        flags.layoutIsDirty = true
        #if canImport(UIKit)
            setNeedsLayout()
        #elseif canImport(AppKit)
            needsLayout = true
        #endif
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        var constraintSize = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        if preferredMaxLayoutWidth > 0 {
            constraintSize.width = preferredMaxLayoutWidth
        } else if lastContainerSize.width > 0 {
            constraintSize.width = lastContainerSize.width
        }

        return textLayout.suggestContainerSize(
            withSize: constraintSize
        )
    }

    #if canImport(UIKit)
        override func layoutSubviews() {
            super.layoutSubviews()
            performLayout()
        }

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            invalidateTextLayout()
        }

    #elseif canImport(AppKit)
        override func layout() {
            super.layout()
            performLayout()
        }

        override func viewDidEndLiveResize() {
            super.viewDidEndLiveResize()
            invalidateTextLayout()
        }
    #endif

    private func performLayout() {
        let containerSize = bounds.size

        var layoutUpdateWasMade = false
        if flags.layoutIsDirty || lastContainerSize != containerSize {
            invalidateIntrinsicContentSize()
            lastContainerSize = containerSize
            textLayout.containerSize = containerSize
            flags.needsUpdateHighlightRegions = true
            flags.layoutIsDirty = false
            layoutUpdateWasMade = true
        }

        if flags.needsUpdateHighlightRegions {
            textLayout.updateHighlightRegions()
            updateAttachmentViews()
            flags.needsUpdateHighlightRegions = false
            layoutUpdateWasMade = true
        }

        if layoutUpdateWasMade {
            updateSelectionLayer()
            #if canImport(UIKit)
                setNeedsDisplay()
            #elseif canImport(AppKit)
                needsDisplay = true
            #endif
        }
    }
}
