//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation
import QuartzCore

public extension LTXLabel {
    func invalidateTextLayout() {
        clearSelection()
        flags.layoutIsDirty = true
        #if canImport(UIKit)
            setNeedsLayout()
        #elseif canImport(AppKit)
            needsLayout = true
        #endif
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        guard let textLayout else { return .zero }

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

            let containerSize = bounds.size
            if flags.layoutIsDirty || lastContainerSize != containerSize {
                if flags.layoutIsDirty || containerSize.width != lastContainerSize.width {
                    invalidateIntrinsicContentSize()
                }

                lastContainerSize = containerSize
                textLayout?.containerSize = containerSize
                flags.needsUpdateHighlightRegions = true
                flags.layoutIsDirty = false

                setNeedsDisplay()
            }
        }

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            invalidateTextLayout()
        }

    #elseif canImport(AppKit)
        override func layout() {
            super.layout()

            let containerSize = bounds.size
            if flags.layoutIsDirty || lastContainerSize != containerSize {
                if flags.layoutIsDirty || containerSize.width != lastContainerSize.width {
                    invalidateIntrinsicContentSize()
                }

                lastContainerSize = containerSize
                textLayout?.containerSize = containerSize
                flags.needsUpdateHighlightRegions = true
                flags.layoutIsDirty = false

                needsDisplay = true
            }
        }
    #endif
}
