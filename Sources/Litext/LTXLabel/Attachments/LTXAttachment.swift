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
    open var size: CGSize

    #if !os(watchOS)
        /// The platform view to embed as an inline attachment (iOS/macOS/tvOS/visionOS).
        open var view: LTXPlatformView?
    #else
        /// The SwiftUI view to embed as an inline attachment (watchOS).
        open var swiftUIView: AnyView?
    #endif

    private var _runDelegate: CTRunDelegate?

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

    open var runDelegate: CTRunDelegate {
        if _runDelegate == nil {
            var callbacks = CTRunDelegateCallbacks(
                version: kCTRunDelegateVersion1,
                dealloc: { refCon in
                    Unmanaged<LTXAttachment>.fromOpaque(refCon).release()
                },
                getAscent: { refCon in
                    let attachment = Unmanaged<LTXAttachment>.fromOpaque(refCon).takeUnretainedValue()
                    return attachment.size.height * 0.9
                },
                getDescent: { refCon in
                    let attachment = Unmanaged<LTXAttachment>.fromOpaque(refCon).takeUnretainedValue()
                    return attachment.size.height * 0.1
                },
                getWidth: { refCon in
                    let attachment = Unmanaged<LTXAttachment>.fromOpaque(refCon).takeUnretainedValue()
                    return attachment.size.width
                }
            )

            let unmanagedSelf = Unmanaged.passRetained(self)
            _runDelegate = CTRunDelegateCreate(&callbacks, unmanagedSelf.toOpaque())
        }

        return _runDelegate!
    }
}
