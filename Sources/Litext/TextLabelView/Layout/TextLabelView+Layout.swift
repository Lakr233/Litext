//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation
import QuartzCore

#if !os(watchOS)

    public extension TextLabelView {
        func invalidateTextLayout() {
            if selectionRange != NSRange.sanitized(selectionRange, within: attributedText.length) {
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

            let suggested = textLayout.sizeThatFits(
                constraintSize
            )
            // Round up to the pixel grid so the host layout system never sizes the
            // view fractionally smaller than the measured text.
            return CGSize(
                width: pixelCeil(suggested.width),
                height: pixelCeil(suggested.height)
            )
        }

        func layoutRuns(matching key: NSAttributedString.Key) -> [TextLabel.LayoutRun] {
            textLayout.layoutRuns(matching: key)
        }

        #if canImport(UIKit)
            override func layoutSubviews() {
                super.layoutSubviews()
                performLayout()
            }

            #if !os(visionOS)
                override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
                    super.traitCollectionDidChange(previousTraitCollection)
                    invalidateTextLayout()
                }
            #endif

        #elseif canImport(AppKit)
            override func layout() {
                super.layout()
                performLayout()
            }

            override func setFrameSize(_ newSize: NSSize) {
                let oldSize = frame.size
                super.setFrameSize(newSize)
                guard oldSize != newSize else { return }
                invalidateTextLayout()
                setNeedsTextDisplay()
            }

            override func setBoundsSize(_ newSize: NSSize) {
                let oldSize = bounds.size
                super.setBoundsSize(newSize)
                guard oldSize != newSize else { return }
                invalidateTextLayout()
                setNeedsTextDisplay()
            }

            override func viewDidEndLiveResize() {
                super.viewDidEndLiveResize()
                invalidateTextLayout()
                setNeedsTextDisplay()
            }
        #endif

        private func performLayout() {
            let containerSize = bounds.size

            var layoutUpdateWasMade = false
            if flags.layoutIsDirty || lastContainerSize != containerSize {
                invalidateIntrinsicContentSize()
                lastContainerSize = containerSize
                textLayout.containerSize = containerSize
                textLayout.updateHighlightRegions()
                updateAttachmentViews()
                flags.layoutIsDirty = false
                layoutUpdateWasMade = true
            }

            if layoutUpdateWasMade {
                updateSelectionLayer()
                setNeedsTextDisplay()
            }
        }

        func setNeedsTextDisplay() {
            #if canImport(UIKit)
                setNeedsDisplay()
            #elseif canImport(AppKit)
                needsDisplay = true
            #endif
        }
    }

#endif // !os(watchOS)
