//
//  LTXCubicBezierCurve.swift
//  LitextAnimation
//
//  Created by Litext Team.
//

import Foundation

#if !os(watchOS)

    /// A timing curve shaped like CSS `cubic-bezier(x1, y1, x2, y2)`, from (0, 0) to (1, 1).
    ///
    /// SwiftUI's `UnitCurve` needs iOS 17, and LitextAnimation runs from iOS 15, so the
    /// effects bring their own. The value is a pure function of progress, so an effect looks
    /// the same however often the display asks for a frame.
    public struct LTXCubicBezierCurve: Sendable, Hashable {
        /// The first control point's x value, clamped to 0...1.
        public let x1: Double
        /// The first control point's y value.
        public let y1: Double
        /// The second control point's x value, clamped to 0...1.
        public let x2: Double
        /// The second control point's y value.
        public let y2: Double

        /// A curve with the given control points. Their x values are clamped to 0...1,
        /// which keeps the curve a function of time; their y values may overshoot.
        public init(x1: Double, y1: Double, x2: Double, y2: Double) {
            self.x1 = min(max(x1, 0), 1)
            self.y1 = y1
            self.x2 = min(max(x2, 0), 1)
            self.y2 = y2
        }

        /// Starts fast and settles gently, like text that lands rather than slides.
        public static let easeOut = LTXCubicBezierCurve(x1: 0.22, y1: 1, x2: 0.36, y2: 1)

        /// Starts and ends gently.
        public static let easeInOut = LTXCubicBezierCurve(x1: 0.42, y1: 0, x2: 0.58, y2: 1)

        /// Progress proportional to time.
        public static let linear = LTXCubicBezierCurve(x1: 0, y1: 0, x2: 1, y2: 1)

        /// The curve's value at `progress`, clamped to 0 before the start and 1 after the end.
        ///
        /// - Important: Performance-sensitive. Called per glyph group on every frame: a few
        ///   Newton steps, no allocation.
        public func value(at progress: Double) -> Double {
            guard progress > 0 else { return 0 }
            guard progress < 1 else { return 1 }
            return Self.bezier(parameter(forX: progress), y1, y2)
        }

        /// The curve parameter whose x value is `x`: Newton's method, which converges in
        /// two or three steps for usual curves, with bisection where the slope is flat.
        private func parameter(forX x: Double) -> Double {
            var t = x
            for _ in 0 ..< 8 {
                let error = Self.bezier(t, x1, x2) - x
                if abs(error) < 1e-7 {
                    return t
                }
                let slope = Self.derivative(t, x1, x2)
                guard abs(slope) > 1e-6 else { break }
                t = min(max(t - error / slope, 0), 1)
            }
            var low = 0.0
            var high = 1.0
            t = x
            for _ in 0 ..< 40 {
                let value = Self.bezier(t, x1, x2)
                if abs(value - x) < 1e-7 {
                    break
                }
                if value < x {
                    low = t
                } else {
                    high = t
                }
                t = (low + high) / 2
            }
            return t
        }

        /// One coordinate of the curve with end points 0 and 1.
        private static func bezier(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
        }

        private static func derivative(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * p1 + 6 * u * t * (p2 - p1) + 3 * t * t * (1 - p2)
        }
    }

#endif
