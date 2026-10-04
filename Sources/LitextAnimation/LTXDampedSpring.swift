//
//  LTXDampedSpring.swift
//  LitextAnimation
//
//  Created by Litext Team.
//

import Foundation

#if !os(watchOS)

    /// A spring released from rest, in closed form, described the way SwiftUI describes one.
    ///
    /// ``displacement(at:)`` is how much of the distance is still to go: 1 at the start, then
    /// heading to 0, overshooting below it when the spring is bouncy. Because it is a formula
    /// of time and not a step-by-step simulation, a frame that arrives late lands where it
    /// should, and an effect can evaluate any moment without keeping per-frame state.
    public struct LTXDampedSpring: Sendable, Hashable {
        /// The period of the undamped spring, in seconds: SwiftUI's `response`. At least
        /// 0.01.
        public let response: Double

        /// 1 settles as fast as possible without overshooting; less bounces, more creeps.
        /// At least 0.01.
        public let dampingRatio: Double

        /// - Parameters:
        ///   - response: The period of the undamped spring, in seconds.
        ///   - dampingRatio: 1 for no overshoot, less to bounce, more to creep.
        public init(response: Double, dampingRatio: Double) {
            self.response = max(response, 0.01)
            self.dampingRatio = max(dampingRatio, 0.01)
        }

        /// A bouncy spring, for glyphs rolling into place.
        public static let bouncy = LTXDampedSpring(response: 0.4, dampingRatio: 0.54)

        /// A spring that settles without overshooting.
        public static let smooth = LTXDampedSpring(response: 0.42, dampingRatio: 1)

        /// The fraction of the distance still to go `time` seconds after release.
        ///
        /// - Important: Performance-sensitive. Called per glyph on every frame; no
        ///   allocation.
        public func displacement(at time: Double) -> Double {
            guard time > 0 else { return 1 }
            let omega = 2 * Double.pi / response
            let zeta = dampingRatio
            if zeta < 1 {
                let dampedOmega = omega * (1 - zeta * zeta).squareRoot()
                let decay = exp(-zeta * omega * time)
                return decay * (cos(dampedOmega * time) + zeta * omega / dampedOmega * sin(dampedOmega * time))
            }
            if zeta == 1 {
                return exp(-omega * time) * (1 + omega * time)
            }
            // Overdamped: two real roots, slow and fast.
            let root = (zeta * zeta - 1).squareRoot()
            let slow = -omega * (zeta - root)
            let fast = -omega * (zeta + root)
            return (fast * exp(slow * time) - slow * exp(fast * time)) / (fast - slow)
        }

        /// The fraction of the distance covered `time` seconds after release.
        public func progress(at time: Double) -> Double {
            1 - displacement(at: time)
        }

        /// How long until the spring stays within `tolerance` of its target, in seconds.
        public func settlingDuration(tolerance: Double = 0.001) -> Double {
            let omega = 2 * Double.pi / response
            let zeta = dampingRatio
            if zeta < 1 {
                // The oscillation stays under its envelope, e^(-ζωt) / √(1 - ζ²).
                let amplitude = 1 / (1 - zeta * zeta).squareRoot()
                return max(log(amplitude / tolerance) / (zeta * omega), 0)
            }
            // Without overshoot the displacement only shrinks, so bisect for the crossing.
            var high = response
            while displacement(at: high) > tolerance, high < 60 {
                high *= 2
            }
            var low = 0.0
            for _ in 0 ..< 40 {
                let mid = (low + high) / 2
                if displacement(at: mid) > tolerance {
                    low = mid
                } else {
                    high = mid
                }
            }
            return high
        }
    }

#endif
