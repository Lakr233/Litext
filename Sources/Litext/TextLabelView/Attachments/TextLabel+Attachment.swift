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
    @MainActor
    open class Attachment {
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

        /// Holds the metrics CoreText reads. The run delegate retains this box instead of the
        /// attachment, so the attachment and its view are released when the caller drops them.
        private let runMetrics = RunMetrics()
        private var cachedRunDelegate: CTRunDelegate?

        #if !os(watchOS)
            /// The platform view to embed as an inline attachment (iOS/macOS/tvOS/visionOS).
            open var view: PlatformView?
        #else
            /// The SwiftUI view to embed as an inline attachment (watchOS).
            open var swiftUIView: AnyView?
        #endif

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
                    return metrics.size.height * (1 - RunMetrics.descentFraction)
                },
                getDescent: { refCon in
                    let metrics = Unmanaged<RunMetrics>.fromOpaque(refCon).takeUnretainedValue()
                    return metrics.size.height * RunMetrics.descentFraction
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
    }
}
