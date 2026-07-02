//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation

extension TextLabel {
    @MainActor
    open class LineDrawingAction: NSObject {
        open var action: (CGContext, CTLine, CGPoint) -> Void

        public init(action: @escaping (CGContext, CTLine, CGPoint) -> Void) {
            self.action = action
            super.init()
        }
    }
}
