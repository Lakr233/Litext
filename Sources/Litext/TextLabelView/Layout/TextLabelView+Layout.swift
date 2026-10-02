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
        ///
        /// - Important: Performance-sensitive: this typesets the whole text again.
        public func reloadTextLayout() {
            textLayout.invalidateLayout()
            invalidateTextLayout()
        }

        /// Marks the text layout dirty, so the next layout pass lays the text out
        /// again and redraws it. Cheap: the work happens in that pass, once.
        public func invalidateTextLayout() {
            invalidateTextLayout(invalidatesIntrinsicSize: true)
        }

        /// The size the text needs when wrapped at `preferredMaxLayoutWidth`, or
        /// else at the width the label was last laid out at.
        ///
        /// - Important: Performance-sensitive: Auto Layout reads it often. It is
        ///   answered from the layout's measurement cache whenever the width is
        ///   unchanged.
        override open var intrinsicContentSize: CGSize {
            var width = CGFloat.greatestFiniteMagnitude
            // An invalid width (NaN, negative or infinite) constrains nothing.
            if preferredMaxLayoutWidth.isValidLayoutDimension, preferredMaxLayoutWidth > 0 {
                width = preferredMaxLayoutWidth
            } else if lastContainerSize.width.isValidLayoutDimension, lastContainerSize.width > 0 {
                width = lastContainerSize.width
            }
            return textSize(wrappingAt: width)
        }

        #if canImport(UIKit)
            /// The size the text needs when wrapped at `size.width`, like
            /// `UILabel.sizeThatFits(_:)`: the height is never limited, and a zero
            /// or invalid width leaves the text unwrapped. Both dimensions are
            /// rounded up to the pixel grid.
            ///
            /// - Important: Performance-sensitive. The layout caches the last few
            ///   widths; each new width measures the whole text with CoreText.
            override open func sizeThatFits(_ size: CGSize) -> CGSize {
                textSize(wrappingAt: Self.wrappingWidth(for: size))
            }

        #elseif canImport(AppKit)
            /// The size the text needs when wrapped at `size.width`, like
            /// `NSControl.sizeThatFits(_:)`: the height is never limited, and a zero
            /// or invalid width leaves the text unwrapped. Both dimensions are
            /// rounded up to the pixel grid.
            ///
            /// - Important: Performance-sensitive. The layout caches the last few
            ///   widths; each new width measures the whole text with CoreText.
            @objc open func sizeThatFits(_ size: CGSize) -> CGSize {
                textSize(wrappingAt: Self.wrappingWidth(for: size))
            }
        #endif

        /// The laid-out lines of the text, top to bottom, in layout space. Empty
        /// until the label has been laid out. See `TextLabel.Layout.layoutLines`.
        public var layoutLines: [TextLabel.LayoutLine] {
            textLayout.layoutLines
        }

        private static func wrappingWidth(for size: CGSize) -> CGFloat {
            size.width.isValidLayoutDimension && size.width > 0 ? size.width : .greatestFiniteMagnitude
        }

        private func textSize(wrappingAt wrappingWidth: CGFloat) -> CGSize {
            let constraintSize = CGSize(width: wrappingWidth, height: CGFloat.greatestFiniteMagnitude)
            let suggested = textLayout.sizeThatFits(
                constraintSize,
            )
            // Round up to the pixel grid so the host layout system never sizes the
            // view fractionally smaller than the measured text. The width stops at the
            // constraint, though: a frame wider than the width the text was measured
            // at lets lines take more glyphs, so the text would wrap into fewer lines
            // than the height was measured for (57.06 rounds to 58 at 1x for a 57.3
            // constraint). Text too wide for the constraint keeps its full width.
            var width = pixelCeil(suggested.width)
            if suggested.width <= constraintSize.width, width > constraintSize.width {
                width = constraintSize.width
            }
            return CGSize(width: width, height: pixelCeil(suggested.height))
        }

        /// Returns laid-out glyph runs that carry `key`.
        ///
        /// Rects are in CoreText layout space (lower-left origin), exactly as
        /// `TextLabel.Layout.layoutRuns(matching:)` returns them. Convert them with
        /// `viewRect(fromLayoutRect:)` before using them as view coordinates.
        ///
        /// - Important: Performance-sensitive: each call walks every glyph run.
        public func layoutRuns(matching key: NSAttributedString.Key) -> [TextLabel.LayoutRun] {
            textLayout.layoutRuns(matching: key)
        }

        #if canImport(UIKit)
            /// Lays the text out for the current bounds when it is dirty, then places
            /// attachment views and the selection. Overrides must call `super`.
            ///
            /// - Important: Performance-sensitive: a size change typesets the text.
            override open func layoutSubviews() {
                super.layoutSubviews()
                performLayout()
            }

            #if !os(visionOS)
                /// Lays the text out again, since dynamic colors and the display scale may
                /// have changed. Overrides must call `super`.
                override open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
                    super.traitCollectionDidChange(previousTraitCollection)
                    invalidateTextLayout()
                }
            #endif

        #elseif canImport(AppKit)
            /// Lays the text out for the current bounds when it is dirty, then places
            /// attachment views and the selection. Overrides must call `super`.
            ///
            /// - Important: Performance-sensitive: a size change typesets the text.
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

            /// Invalidates the text layout when the size changes. Overrides must call
            /// `super`.
            override open func setBoundsSize(_ newSize: NSSize) {
                let oldSize = bounds.size
                super.setBoundsSize(newSize)
                guard oldSize != newSize else { return }
                invalidateTextLayout(invalidatesIntrinsicSize: oldSize.width != newSize.width)
            }

            /// Lays the text out again once a live resize ends. Overrides must call
            /// `super`.
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

        /// Redraws the text without laying it out again, for example after state a
        /// line-drawing action reads has changed.
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
