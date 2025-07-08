//
//  Created by Lakr233 & Helixform on 2025/7/8.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import Foundation

public protocol LTXAttachmentViewProvider: Hashable, Equatable {
    func reuseIdentifier() -> String
    func createView() -> LTXPlatformView
    func configureView(_ view: LTXPlatformView, for attachment: LTXAttachment)
    func boundingSize(for attachment: LTXAttachment) -> CGSize
    func textRepresentation() -> String
}

public extension LTXAttachmentViewProvider {
    func hash(into hasher: inout Hasher) {
        hasher.combine(reuseIdentifier())
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
}

open class LTXBaseAttachmentViewProvider: LTXAttachmentViewProvider {
    open func reuseIdentifier() -> String {
        #fileID
    }

    open func createView() -> LTXPlatformView {
        .init()
    }

    open func configureView(_: LTXPlatformView, for _: LTXAttachment) {
        // pass
    }

    open func boundingSize(for _: LTXAttachment) -> CGSize {
        .zero
    }

    public func textRepresentation() -> String {
        ""
    }
}
