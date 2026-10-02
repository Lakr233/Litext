//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation

#if os(watchOS)
    import SwiftUI
#endif

extension TextLabel {
    /// An inline object that takes up `size` in the text: a platform view on
    /// iOS, macOS, tvOS and visionOS, or a SwiftUI view on watchOS.
    ///
    /// Insert one with `attributedString(attributes:)`. The label places the view
    /// over the space CoreText reserves for it after each layout pass. One
    /// attachment, and so one view, can be shown by only one label at a time.
    @MainActor
    open class Attachment {
        /// The object replacement character an attachment occupies in the string.
        public static let replacementText = "\u{FFFC}"

        /// The size CoreText reserves for this attachment.
        ///
        /// CoreText reads the size when it typesets, and a hosting label caches that layout.
        /// After changing the size of an attachment that is already displayed, call
        /// `reloadTextLayout()` on the hosting label so the new size takes effect.
        ///
        /// A subclass may override this property with a computed getter. `TextLabel.Layout`
        /// reads it again whenever it builds or rebuilds its framesetter.
        open var size: CGSize {
            didSet { runMetrics.size = size }
        }

        /// How far the attachment reaches below the baseline, in points; `nil`, the
        /// default, uses a tenth of `size.height`. The rest of the height sits
        /// above the baseline.
        ///
        /// Pass `0` to sit the attachment on the baseline, or the font's descent
        /// to line its bottom up with the descenders. Values are clamped to
        /// `0 ... size.height`, and a value that is not finite counts as `nil`.
        /// As with `size`, call `reloadTextLayout()` on the hosting label after
        /// changing it for an attachment that is already displayed.
        open var descent: CGFloat? {
            didSet { runMetrics.descent = descent }
        }

        /// Holds the metrics CoreText reads. The run delegate retains this box instead of the
        /// attachment, so the attachment and its view are released when the caller drops them.
        private let runMetrics = RunMetrics()
        private var cachedRunDelegate: CTRunDelegate?

        #if !os(watchOS)
            /// The platform view to embed as an inline attachment (iOS/macOS/tvOS/visionOS).
            ///
            /// The label adds it as a subview and sets its frame to the attachment's
            /// rect after each layout pass. Touches on it go to the view, not to the
            /// label's selection.
            open var view: PlatformView?
        #else
            /// The SwiftUI view to embed as an inline attachment (watchOS), framed to
            /// the attachment's rect.
            open var swiftUIView: AnyView?
        #endif

        /// Creates an empty attachment. Set `size` before laying out text with it.
        public init() {
            size = .zero
        }

        #if !os(watchOS)
            /// Creates an attachment with a size and an optional platform view.
            public convenience init(size: CGSize, view: PlatformView? = nil) {
                self.init()
                self.size = size
                self.view = view
            }
        #else
            /// Creates an attachment with a size and an optional SwiftUI view.
            public convenience init(size: CGSize, swiftUIView: AnyView? = nil) {
                self.init()
                self.size = size
                self.swiftUIView = swiftUIView
            }
        #endif

        /// A one-character string that shows this attachment, carrying
        /// `attributes` as well. Add `.link` to make the attachment a link too;
        /// a tap on it still reports the attachment region.
        ///
        /// Overrides must keep `.litextAttachment` set to `self` and the run
        /// delegate from `runDelegate` on the character, or nothing is reserved
        /// for the view.
        open func attributedString(
            attributes: [NSAttributedString.Key: Any] = [:],
        ) -> NSAttributedString {
            let result = NSMutableAttributedString(
                string: Self.replacementText,
                attributes: attributes,
            )
            let range = NSRange(location: 0, length: result.length)
            result.addAttribute(.litextAttachment, value: self, range: range)
            result.addAttribute(
                kCTRunDelegateAttributeName as NSAttributedString.Key,
                value: runDelegate,
                range: range,
            )
            return result
        }

        /// The text that stands for the attachment when the selection is copied:
        /// the view's `AttachmentRepresentable` representation, or a space.
        ///
        /// Called for each selected attachment whenever the selected text is read:
        /// on every copy, and in the SwiftUI `TextLabel` on every selection change.
        /// Keep it cheap.
        open func attributedStringRepresentation() -> NSAttributedString {
            #if !os(watchOS)
                if let view = view as? AttachmentRepresentable {
                    return view.attributedStringRepresentation()
                }
            #endif
            return NSAttributedString(string: " ")
        }

        /// A CoreText run delegate that reports this attachment's size.
        ///
        /// The delegate retains a small metrics box rather than the attachment, so CoreText can
        /// keep measuring after the attachment is gone without keeping the attachment alive.
        /// The delegate is cached so repeated reads do not allocate additional delegates.
        ///
        /// - Important: Performance-sensitive. CoreText calls its callbacks while it
        ///   typesets; they read a small box that `size` and `descent` keep current,
        ///   and never call back into the attachment.
        open var runDelegate: CTRunDelegate {
            syncRunMetrics()
            if let cachedRunDelegate {
                return cachedRunDelegate
            }

            var callbacks = CTRunDelegateCallbacks(
                version: kCTRunDelegateVersion1,
                dealloc: { refCon in
                    Unmanaged<RunMetrics>.fromOpaque(refCon).release()
                },
                getAscent: { refCon in
                    let metrics = Unmanaged<RunMetrics>.fromOpaque(refCon).takeUnretainedValue()
                    return metrics.size.height - metrics.resolvedDescent
                },
                getDescent: { refCon in
                    let metrics = Unmanaged<RunMetrics>.fromOpaque(refCon).takeUnretainedValue()
                    return metrics.resolvedDescent
                },
                getWidth: { refCon in
                    let metrics = Unmanaged<RunMetrics>.fromOpaque(refCon).takeUnretainedValue()
                    return metrics.size.width
                },
            )

            let unmanagedMetrics = Unmanaged.passRetained(runMetrics)
            guard let delegate = CTRunDelegateCreate(&callbacks, unmanagedMetrics.toOpaque()) else {
                unmanagedMetrics.release()
                fatalError("Unable to create CTRunDelegate for TextLabel.Attachment")
            }
            cachedRunDelegate = delegate
            return delegate
        }

        /// Copies `size` into the box the run delegate reads. Going through dynamic dispatch
        /// honours a subclass that computes `size` without calling `super`.
        func syncRunMetrics() {
            runMetrics.size = size
            runMetrics.descent = descent
        }
    }
}

extension TextLabel.Attachment {
    /// The metrics a run delegate reports, read by CoreText at typesetting time.
    ///
    /// Writes happen on the main actor through `Attachment.size`, and CoreText reads happen
    /// while the main-actor layout typesets, which is why unchecked sendability is sound here.
    final class RunMetrics: @unchecked Sendable {
        static let descentFraction: CGFloat = 0.1

        var size: CGSize = .zero
        var descent: CGFloat?

        /// `descent` clamped into the height, or the default fraction of it.
        var resolvedDescent: CGFloat {
            let height = size.height
            guard let descent, descent.isFinite else { return height * Self.descentFraction }
            return min(max(descent, 0), max(height, 0))
        }
    }
}
