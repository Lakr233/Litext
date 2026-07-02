//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation

public extension TextLabel {
    @MainActor
    class LineDrawingAction: NSObject {
        public var action: (CGContext, CTLine, CGPoint) -> Void

        public init(action: @escaping (CGContext, CTLine, CGPoint) -> Void) {
            self.action = action
            super.init()
        }
    }
}
