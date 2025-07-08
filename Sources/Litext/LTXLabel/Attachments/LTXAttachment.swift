//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation

//
// LTXAttachment can not be reused
//
// please use LTXAttachmentViewProvider to implement a reusable view provider
//

open class LTXAttachment {
    open var viewProvider: any LTXAttachmentViewProvider
    open var data: Any?

    open func attributedStringRepresentation() -> NSAttributedString {
        .init(string: viewProvider.textRepresentation())
    }

    public init(viewProvider: any LTXAttachmentViewProvider, data: Any? = nil) {
        self.viewProvider = viewProvider
        self.data = data
    }

    deinit {
        self.runDelegateReferenceObject = nil
        self.runDelegate = nil
    }

    private var runDelegateReferenceObject: RunDelegateReferenceObject?
    private var runDelegate: CTRunDelegate?
    func updateRunDelegate(maxWidth: CGFloat) -> CTRunDelegate? {
        runDelegateReferenceObject = nil
        runDelegate = nil
        let (referenceObject, delegate) = Self.createDefaultRunDelegate(attachment: self, labelWidth: maxWidth)
        runDelegateReferenceObject = referenceObject
        runDelegate = delegate
        return delegate
    }
}

extension LTXAttachment {
    static func createDefaultRunDelegate(attachment: LTXAttachment, labelWidth: CGFloat) -> (RunDelegateReferenceObject, CTRunDelegate?) {
        let boundingSize = attachment.viewProvider.boundingSize(for: attachment)
        let referenceObject = RunDelegateReferenceObject(
            width: min(labelWidth, boundingSize.width),
            height: boundingSize.height,
        )

        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { _ in },
            getAscent: { refCon in
                let size = Unmanaged<RunDelegateReferenceObject>.fromOpaque(refCon).takeUnretainedValue()
                return size.height * 0.85
            },
            getDescent: { refCon in
                let size = Unmanaged<RunDelegateReferenceObject>.fromOpaque(refCon).takeUnretainedValue()
                return size.height * 0.15
            },
            getWidth: { refCon in
                let size = Unmanaged<RunDelegateReferenceObject>.fromOpaque(refCon).takeUnretainedValue()
                return size.width
            }
        )

        let delegate = CTRunDelegateCreate(&callbacks, Unmanaged.passUnretained(referenceObject).toOpaque())
        return (referenceObject, delegate)
    }
}
