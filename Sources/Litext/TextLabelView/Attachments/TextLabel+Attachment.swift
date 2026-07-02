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
        static let descentFraction: CGFloat = 0.1

        open var size: CGSize
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

        open func attributedString(
            attributes: [NSAttributedString.Key: Any] = [:]
        ) -> NSAttributedString {
            let result = NSMutableAttributedString(
                string: Self.replacementText,
                attributes: attributes
            )
            let range = NSRange(location: 0, length: result.length)
            result.addAttribute(.litextAttachment, value: self, range: range)
            result.addAttribute(
                kCTRunDelegateAttributeName as NSAttributedString.Key,
                value: runDelegate,
                range: range
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

        /// A CoreText run delegate that retains this attachment for as long as CoreText needs metrics.
        ///
        /// The delegate is cached so repeated reads do not allocate additional delegates or retain
        /// the attachment more than once.
        open var runDelegate: CTRunDelegate {
            if let cachedRunDelegate {
                return cachedRunDelegate
            }

            var callbacks = CTRunDelegateCallbacks(
                version: kCTRunDelegateVersion1,
                dealloc: { refCon in
                    Unmanaged<Attachment>.fromOpaque(refCon).release()
                },
                getAscent: { refCon in
                    let attachment = Unmanaged<Attachment>.fromOpaque(refCon).takeUnretainedValue()
                    return attachment.size.height * (1 - Attachment.descentFraction)
                },
                getDescent: { refCon in
                    let attachment = Unmanaged<Attachment>.fromOpaque(refCon).takeUnretainedValue()
                    return attachment.size.height * Attachment.descentFraction
                },
                getWidth: { refCon in
                    let attachment = Unmanaged<Attachment>.fromOpaque(refCon).takeUnretainedValue()
                    return attachment.size.width
                }
            )

            let unmanagedSelf = Unmanaged.passRetained(self)
            guard let delegate = CTRunDelegateCreate(&callbacks, unmanagedSelf.toOpaque()) else {
                unmanagedSelf.release()
                fatalError("Unable to create CTRunDelegate for TextLabel.Attachment")
            }
            cachedRunDelegate = delegate
            return delegate
        }
    }
}
