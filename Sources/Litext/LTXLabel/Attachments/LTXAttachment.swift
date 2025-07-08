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

    open func attributedStringRepresentation() -> NSAttributedString {
        .init(string: viewProvider.textRepresentation())
    }

    public init(viewProvider: any LTXAttachmentViewProvider, data: Any? = nil, _runDelegate: CTRunDelegate? = nil) {
        self.viewProvider = viewProvider
        self.data = data
        self._runDelegate = _runDelegate
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
                return boundingSize.height * 0.85
            },
            getDescent: { refCon in
                let attachment = Unmanaged<LTXAttachment>.fromOpaque(refCon).takeUnretainedValue()
                let boundingSize = attachment.viewProvider.boundingSize(for: attachment)
                return boundingSize.height * 0.15
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
