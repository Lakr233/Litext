//
//  LTXInvalidationContext.swift
//  LitextAnimation
//
//  Created by Litext Team.
//

import CoreGraphics
import Foundation
import Litext

#if !os(watchOS)

    /// Collects what an animator wants redrawn for one frame.
    ///
    /// The label hands the same context to every call of
    /// `LTXTextAnimator.advance(to:invalidation:)`, emptied, and redraws the union of what was
    /// invalidated once the call returns. Like `UICollectionViewLayoutInvalidationContext`, it
    /// is only meaningful during that call.
    ///
    /// - Important: Performance-sensitive. Invalidating characters costs two binary searches
    ///   over the laid-out lines, however many lines the range touches; nothing allocates.
    @MainActor
    public final class LTXInvalidationContext {
        /// The union of everything invalidated, in the label's coordinates (top-left origin).
        /// `.null` when nothing was.
        private(set) var dirtyRect: CGRect = .null

        /// Whether `invalidateAll()` was called.
        private(set) var invalidatesAll = false

        /// The lines of the layout being animated, or `nil` while it has not been laid out.
        private var lineIndex: LTXLineIndex?
        /// Converts layout space to view space for the layout being animated.
        private var layout: TextLabel.Layout?
        /// Whether the layout can map characters to lines at all. A label whose
        /// `makeTextLayout(_:)` returns a layout of its own cannot.
        private var canMapCharacters = false
        private var insets: LTXInsets = .zero

        init() {}

        /// Empties the context for a new frame of `layout`.
        func reset(layout: TextLabel.Layout, lineIndex: LTXLineIndex?, canMapCharacters: Bool, insets: LTXInsets) {
            dirtyRect = .null
            invalidatesAll = false
            self.layout = layout
            self.lineIndex = lineIndex
            self.canMapCharacters = canMapCharacters
            self.insets = insets
        }

        /// Drops the references the context holds between frames.
        func clear() {
            dirtyRect = .null
            invalidatesAll = false
            layout = nil
            lineIndex = nil
        }

        /// Redraws the lines that show any character of `range`: the strip of the label they
        /// own, across its width and halfway to the neighbouring lines, widened by the
        /// animator's `overdrawInsets`.
        ///
        /// `range` is in UTF-16 offsets of the label's text. An empty range redraws the line
        /// its location sits on, which suits a deletion point. Lines are found in the layout
        /// that is on screen; before a new text's first layout pass there are none, and the
        /// label redraws everything after that pass anyway.
        public func invalidateCharacters(in range: NSRange) {
            guard !invalidatesAll else { return }
            guard canMapCharacters else {
                invalidatesAll = true
                return
            }
            guard let lineIndex, let layout else { return }
            let lines = lineIndex.lines(touching: range)
            guard !lines.isEmpty else { return }
            dirtyRect = dirtyRect.union(insets.outset(lineIndex.strip(of: lines, in: layout)))
        }

        /// Redraws `rect`, in the label's coordinates (top-left origin). Only the part inside
        /// the animation region is redrawn: the lines touching the animator's
        /// `animatingRange` and its `additionalContentBounds`, widened by its
        /// `overdrawInsets`.
        public func invalidate(_ rect: CGRect) {
            guard !invalidatesAll, !rect.isNull, !rect.isEmpty,
                  rect.minX.isFinite, rect.minY.isFinite, rect.maxX.isFinite, rect.maxY.isFinite
            else { return }
            dirtyRect = dirtyRect.union(rect)
        }

        /// Redraws everything the animator draws: the whole animation region.
        public func invalidateAll() {
            invalidatesAll = true
        }
    }

#endif
