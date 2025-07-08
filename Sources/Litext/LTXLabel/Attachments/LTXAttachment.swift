//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation

open class LTXAttachment {
    open var viewProvider: any LTXAttachmentViewProvider
    open var data: Any?
    private var _runDelegate: CTRunDelegate?

    public init(viewProvider: any LTXAttachmentViewProvider, data: Any? = nil, _runDelegate: CTRunDelegate? = nil) {
        self.viewProvider = viewProvider
        self.data = data
        self._runDelegate = _runDelegate
    }

    open func attributedStringRepresentation() -> NSAttributedString {
        if let viewProvider = viewProvider as? LTXAttributeStringRepresentable {
            return viewProvider.attributedStringRepresentation()
        }
        return NSAttributedString(string: " ")
    }

    open var runDelegate: CTRunDelegate {
        if _runDelegate == nil {
            _runDelegate = Self.createDefaultRunDelegate(attachment: self)
        }
        return _runDelegate!
    }
}

private extension LTXAttachment {
    static func createDefaultRunDelegate(attachment: LTXAttachment) -> CTRunDelegate? {
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { _ in },
            getAscent: { refCon in
                let attachment = Unmanaged<LTXAttachment>.fromOpaque(refCon).takeUnretainedValue()
                let boundingSize = attachment.viewProvider.boundingSize(for: attachment)
                return boundingSize.height * 0.9
            },
            getDescent: { refCon in
                let attachment = Unmanaged<LTXAttachment>.fromOpaque(refCon).takeUnretainedValue()
                let boundingSize = attachment.viewProvider.boundingSize(for: attachment)
                return boundingSize.height * 0.1
            },
            getWidth: { refCon in
                let attachment = Unmanaged<LTXAttachment>.fromOpaque(refCon).takeUnretainedValue()
                let boundingSize = attachment.viewProvider.boundingSize(for: attachment)
                return boundingSize.width
            }
        )

        let unmanagedSelf = Unmanaged.passUnretained(attachment)
        return CTRunDelegateCreate(&callbacks, unmanagedSelf.toOpaque())
    }
}
