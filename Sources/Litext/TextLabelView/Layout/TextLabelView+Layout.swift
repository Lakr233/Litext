//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation
import QuartzCore

#if !os(watchOS)

    /// Subclasses that override a layout or geometry hook below must call `super`:
    /// the base implementations run the text layout pass or invalidate it.
    extension TextLabelView {
        /// Discards the cached CoreText layout and re-runs it on the next layout pass.
        ///
        /// Assigning `attributedText` skips the rebuild when the new string equals the old
        /// one. Use this when the string is unchanged but external state read by a run
        /// delegate or a custom line-drawing callback has changed.
        public func reloadTextLayout() {
            textLayout.invalidateLayout()
            invalidateTextLayout()
        }

        public func invalidateTextLayout() {
            invalidateTextLayout(invalidatesIntrinsicSize: true)
        }

        override open var intrinsicContentSize: CGSize {
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

        /// Returns laid-out glyph runs that carry `key`.
        ///
        /// Rects are in CoreText layout space (lower-left origin), exactly as
        /// `TextLabel.Layout.layoutRuns(matching:)` returns them. Convert them with
        /// `viewRect(fromLayoutRect:)` before using them as view coordinates.
        public func layoutRuns(matching key: NSAttributedString.Key) -> [TextLabel.LayoutRun] {
            textLayout.layoutRuns(matching: key)
        }

        #if canImport(UIKit)
            override open func layoutSubviews() {
                super.layoutSubviews()
                performLayout()
            }

            #if !os(visionOS)
                override open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
                    super.traitCollectionDidChange(previousTraitCollection)
                    invalidateTextLayout()
                }
            #endif

        #elseif canImport(AppKit)
            override open func layout() {
                super.layout()
                performLayout()
            }

            /// Geometry hooks only invalidate; they must not mark the view for display.
            /// Marking it here lets a display pass paint before the layout pass has moved
            /// the text layout onto the new size, and `draw(_:)` would then position every
            /// line against a stale container height. `performLayout()` asks for the redraw
            /// once the layout actually matches the bounds.
            override open func setFrameSize(_ newSize: NSSize) {
                let oldSize = frame.size
                super.setFrameSize(newSize)
                guard oldSize != newSize else { return }
                invalidateTextLayout(invalidatesIntrinsicSize: oldSize.width != newSize.width)
            }

            override open func setBoundsSize(_ newSize: NSSize) {
                let oldSize = bounds.size
                super.setBoundsSize(newSize)
                guard oldSize != newSize else { return }
                invalidateTextLayout(invalidatesIntrinsicSize: oldSize.width != newSize.width)
            }

            override open func viewDidEndLiveResize() {
                super.viewDidEndLiveResize()
                invalidateTextLayout()
            }
        #endif

        private func performLayout() {
            let containerSize = bounds.size
            guard flags.layoutIsDirty || lastContainerSize != containerSize else { return }

            // Only the width can change how text wraps, so a height-only change must
            // not dirty the intrinsic size — doing so from inside a layout pass sends
            // the host back through constraint solving for a value that cannot differ.
            if lastContainerSize.width != containerSize.width {
                invalidateIntrinsicContentSize()
            }
            lastContainerSize = containerSize
            textLayout.containerSize = containerSize
            // Highlight regions depend only on the laid-out lines. Window moves and
            // trait changes invalidate without changing them, so extraction is skipped
            // then. Attachment frames are still re-placed: they snap to the display
            // scale, which a window move can change.
            if highlightRegionsGeneration != textLayout.generation {
                textLayout.updateHighlightRegions()
                highlightRegionsGeneration = textLayout.generation
            }
            updateAttachmentViews()
            flags.layoutIsDirty = false

            // Presenting or dismissing the selection menu belongs to a selection
            // change, not to a layout pass: it presents UI and notifies sibling labels,
            // both of which would mutate the view tree while the host is still laying
            // it out.
            updateSelectionLayer(presentsMenu: false)
            setNeedsTextDisplay()
        }

        public func setNeedsTextDisplay() {
            #if canImport(UIKit)
                setNeedsDisplay()
            #elseif canImport(AppKit)
                needsDisplay = true
            #endif
        }
    }

    extension TextLabelView {
        /// Marks the text layout dirty. Pass `invalidatesIntrinsicSize: false` only when
        /// nothing `intrinsicContentSize` reads can have changed: it depends on the
        /// width, `preferredMaxLayoutWidth`, the text and the display scale, never on
        /// the height or on colors.
        func invalidateTextLayout(invalidatesIntrinsicSize: Bool) {
            if selectionRange != NSRange.sanitized(selectionRange, within: attributedText.length) {
                clearSelection()
            }

            flags.layoutIsDirty = true
            #if canImport(UIKit)
                setNeedsLayout()
            #elseif canImport(AppKit)
                needsLayout = true
            #endif
            if invalidatesIntrinsicSize {
                invalidateIntrinsicContentSize()
            }
        }
    }

#endif // !os(watchOS)
