//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation
import QuartzCore

#if !os(watchOS)

    public extension LTXLabel {
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

            return textLayout.suggestContainerSize(
                withSize: constraintSize
            )
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

            override func viewDidMoveToSuperview() {
                super.viewDidMoveToSuperview()
                updateVisibleRenderingObservation()
                setNeedsTextDisplay()
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
                setNeedsTextDisplay()
            }

            #if (canImport(UIKit) && !os(watchOS)) || (canImport(AppKit) && !targetEnvironment(macCatalyst))
                updateVisibleRenderingObservation()
            #endif
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
