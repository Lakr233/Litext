//
//  LTXStaggerSchedule.swift
//  LitextAnimation
//
//  Created by Litext Team.
//

import Foundation

#if !os(watchOS)

    /// Delays for text units that appear one after another, with the whole run capped.
    ///
    /// A short chunk staggers at ``interval`` per unit; a long one shrinks the interval so
    /// the last unit never starts more than ``maxTotalDelay`` after the first. A paragraph
    /// that arrives at once therefore sweeps in quickly instead of trickling for seconds.
    public struct LTXStaggerSchedule: Sendable, Hashable {
        /// The delay between neighbouring units, in seconds.
        public var interval: Double

        /// The longest delay any unit gets, in seconds.
        public var maxTotalDelay: Double

        /// - Parameters:
        ///   - interval: The delay between neighbouring units, in seconds.
        ///   - maxTotalDelay: The longest delay any unit gets, in seconds.
        public init(interval: Double, maxTotalDelay: Double) {
            self.interval = interval
            self.maxTotalDelay = maxTotalDelay
        }

        /// The delay between neighbouring units when `count` of them arrive together.
        public func interval(forUnitCount count: Int) -> Double {
            guard count > 1 else { return 0 }
            return max(min(interval, maxTotalDelay / Double(count - 1)), 0)
        }
    }

#endif
