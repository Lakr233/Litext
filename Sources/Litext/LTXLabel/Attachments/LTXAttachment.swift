//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation

#if os(watchOS)
    import SwiftUI
#endif

@MainActor
open class LTXAttachment {
    static let descentFraction: CGFloat = 0.1

    open var size: CGSize
    private var cachedRunDelegate: CTRunDelegate?

    #if !os(watchOS)
        /// The platform view to embed as an inline attachment (iOS/macOS/tvOS/visionOS).
        open var view: LTXPlatformView?
    #else
        /// The SwiftUI view to embed as an inline attachment (watchOS).
        open var swiftUIView: AnyView?
    #endif

    public init() {
        size = .zero
    }

    open func attributedStringRepresentation() -> NSAttributedString {
        #if !os(watchOS)
            if let view = view as? LTXAttributeStringRepresentable {
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
                Unmanaged<LTXAttachment>.fromOpaque(refCon).release()
            },
            getAscent: { refCon in
                let attachment = Unmanaged<LTXAttachment>.fromOpaque(refCon).takeUnretainedValue()
                return attachment.size.height * (1 - LTXAttachment.descentFraction)
            },
            getDescent: { refCon in
                let attachment = Unmanaged<LTXAttachment>.fromOpaque(refCon).takeUnretainedValue()
                return attachment.size.height * LTXAttachment.descentFraction
            },
            getWidth: { refCon in
                let attachment = Unmanaged<LTXAttachment>.fromOpaque(refCon).takeUnretainedValue()
                return attachment.size.width
            }
        )

        let unmanagedSelf = Unmanaged.passRetained(self)
        guard let delegate = CTRunDelegateCreate(&callbacks, unmanagedSelf.toOpaque()) else {
            unmanagedSelf.release()
            fatalError("Unable to create CTRunDelegate for LTXAttachment")
        }
        cachedRunDelegate = delegate
        return delegate
    }
}
