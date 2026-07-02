//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import Foundation

public extension TextLabel {
    @MainActor
    protocol AttachmentRepresentable {
        func attributedStringRepresentation() -> NSAttributedString
    }
}
