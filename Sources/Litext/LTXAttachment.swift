//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation

public let LTXReplacementText = "\u{FFFC}"
public let LTXAttachmentAttributeName = NSAttributedString.Key("LTXAttachment")
public let LTXLineDrawingCallbackName = NSAttributedString.Key("LTXLineDrawingCallback")

public class LTXAttachment {
    public var size: CGSize
    public var view: LTXPlatformView?

    private var _runDelegate: CTRunDelegate?

    public init() {
        size = .zero
    }

    // 获取 attachment 的文本表示
    public func attributedStringRepresentation() -> NSAttributedString {
        if let view = view as? LTXAttributeStringRepresentable {
            return view.attributedStringRepresentation()
        }
        // 如果没有实现协议，返回空格
        return NSAttributedString(string: " ")
    }

    public var runDelegate: CTRunDelegate {
        if _runDelegate == nil {
            var callbacks = CTRunDelegateCallbacks(
                version: kCTRunDelegateVersion1,
                dealloc: { _ in },
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

            let unmanagedSelf = Unmanaged.passUnretained(self)
            _runDelegate = CTRunDelegateCreate(&callbacks, unmanagedSelf.toOpaque())
        }

        return _runDelegate!
    }
}
