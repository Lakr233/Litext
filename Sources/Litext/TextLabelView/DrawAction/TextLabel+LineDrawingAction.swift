//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation

extension TextLabel {
    /// Custom drawing for the lines a range touches, attached with
    /// `.litextLineDrawingAction`.
    ///
    /// After the visible lines are drawn, `action` is called once for every visible
    /// line the attributed range touches, however many runs CoreText splits it into.
    @MainActor
    open class LineDrawingAction: NSObject {
        /// Draws extra content for one line: a background bar, a quote rule, an
        /// underline of your own.
        ///
        /// It receives the context in CoreText's flipped space (lower-left origin,
        /// identity text matrix), the line, and the line's baseline origin in
        /// layout space. The graphics state is saved before the call and restored
        /// after it.
        ///
        /// - Important: Performance-sensitive: this runs for every visible line
        ///   carrying the action on every display pass. Avoid allocating or
        ///   measuring text here.
        open var action: (CGContext, CTLine, CGPoint) -> Void

        /// Creates an action that runs `action` for each line it touches.
        public init(action: @escaping (CGContext, CTLine, CGPoint) -> Void) {
            self.action = action
            super.init()
        }
    }
}
