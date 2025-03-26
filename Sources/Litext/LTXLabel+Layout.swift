//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation
import QuartzCore

public extension LTXLabel {
    // MARK: - Layout & Auto Layout Support

    override var intrinsicContentSize: CGSize {
        guard let textLayout else { return .zero }

        var constraintSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        if preferredMaxLayoutWidth > 0 {
            constraintSize.width = preferredMaxLayoutWidth
        } else if lastContainerSize.width > 0 {
            constraintSize.width = lastContainerSize.width
        }

        return textLayout.suggestContainerSize(withSize: constraintSize)
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
    #else
        #error("unsupported platform")
    #endif

    // MARK: - Rendering

    #if canImport(UIKit)
        override func draw(_: CGRect) {
            guard let context = UIGraphicsGetCurrentContext() else { return }

            if flags.needsUpdateHighlightRegions {
                textLayout?.updateHighlightRegions(with: context)
                highlightRegions = textLayout?.highlightRegions ?? []
                updateAttachmentViews()
                flags.needsUpdateHighlightRegions = false
            }

            textLayout?.draw(in: context)
        }

    #elseif canImport(AppKit)
        override func draw(_: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }

            if flags.needsUpdateHighlightRegions {
                textLayout?.updateHighlightRegions(with: context)
                highlightRegions = textLayout?.highlightRegions ?? []
                updateAttachmentViews()
                flags.needsUpdateHighlightRegions = false
            }

            textLayout?.draw(in: context)
        }
    #else
        #error("unsupported platform")
    #endif
}
