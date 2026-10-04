//
//  AlphaQuantizer.swift
//  LitextAnimation
//
//  Created by Litext Team.
//

import CoreGraphics
import Foundation

#if !os(watchOS)

    /// Rounds opacity to a fixed number of steps.
    ///
    /// An effect redraws text only when its quantized opacity changes. With 32 steps the
    /// fade still looks continuous, and the slow tail of an ease-out, where opacity changes
    /// by less than a step per frame, costs no redraws at all.
    struct AlphaQuantizer: Sendable, Hashable {
        /// The number of steps from transparent to opaque.
        let levels: Int

        init(levels: Int = 32) {
            self.levels = max(levels, 1)
        }

        /// The step for `alpha`: 0 is transparent and `levels` opaque.
        func level(for alpha: Double) -> Int {
            guard alpha > 0 else { return 0 }
            guard alpha < 1 else { return levels }
            return Int((alpha * Double(levels)).rounded())
        }

        /// The opacity a step stands for.
        func alpha(forLevel level: Int) -> CGFloat {
            CGFloat(min(max(level, 0), levels)) / CGFloat(levels)
        }
    }

#endif
