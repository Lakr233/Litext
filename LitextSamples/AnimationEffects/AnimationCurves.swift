//
//  AnimationCurves.swift
//  OhMyLitext
//
//  Created by Litext Team.
//
//  The timing math the sample animators share. Every value here is a pure
//  function of elapsed time, so an effect looks the same however often the
//  display asks for a frame, and the tests can check it without a display.
//

import CoreGraphics
import Foundation

// MARK: - Cubic Bézier curve

/// A timing curve shaped like CSS `cubic-bezier(x1, y1, x2, y2)`, from (0, 0) to (1, 1).
///
/// SwiftUI's `UnitCurve` needs iOS 17, and LitextAnimation runs from iOS 15, so the
/// sample effects bring their own. The control points' x values are clamped to 0...1,
/// which keeps the curve a function of time.
nonisolated struct CubicBezierCurve: Sendable, Hashable {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double

    init(x1: Double, y1: Double, x2: Double, y2: Double) {
        self.x1 = min(max(x1, 0), 1)
        self.y1 = y1
        self.x2 = min(max(x2, 0), 1)
        self.y2 = y2
    }

    /// Starts fast and settles gently, like text that lands rather than slides.
    static let easeOut = CubicBezierCurve(x1: 0.22, y1: 1, x2: 0.36, y2: 1)

    /// Starts and ends gently.
    static let easeInOut = CubicBezierCurve(x1: 0.42, y1: 0, x2: 0.58, y2: 1)

    /// Progress proportional to time.
    static let linear = CubicBezierCurve(x1: 0, y1: 0, x2: 1, y2: 1)

    /// The curve's value at `progress`, clamped to 0 before the start and 1 after the end.
    ///
    /// - Important: Performance-sensitive. Called per glyph group on every frame: a few
    ///   Newton steps, no allocation.
    func value(at progress: Double) -> Double {
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

// MARK: - Damped spring

/// A spring released from rest, in closed form, described the way SwiftUI describes one.
///
/// `displacement(at:)` is how much of the distance is still to go: 1 at the start, then
/// heading to 0, overshooting below it when the spring is bouncy. Because it is a formula
/// of time and not a step-by-step simulation, a frame that arrives late lands where it
/// should, and an effect can evaluate any moment without keeping per-frame state.
nonisolated struct DampedSpring: Sendable, Hashable {
    /// The period of the undamped spring, in seconds: SwiftUI's `response`.
    let response: Double

    /// 1 settles as fast as possible without overshooting; less bounces, more creeps.
    let dampingRatio: Double

    init(response: Double, dampingRatio: Double) {
        self.response = max(response, 0.01)
        self.dampingRatio = max(dampingRatio, 0.01)
    }

    /// The bouncy spring FlowDown's title uses for glyphs rolling in.
    static let bouncy = DampedSpring(response: 0.4, dampingRatio: 0.54)

    /// A spring that settles without overshooting.
    static let smooth = DampedSpring(response: 0.42, dampingRatio: 1)

    /// The fraction of the distance still to go `time` seconds after release.
    func displacement(at time: Double) -> Double {
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
    func progress(at time: Double) -> Double {
        1 - displacement(at: time)
    }

    /// How long until the spring stays within `tolerance` of its target.
    func settlingDuration(tolerance: Double = 0.001) -> Double {
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

// MARK: - Alpha quantization

/// Rounds opacity to a fixed number of steps.
///
/// An effect redraws text only when its quantized opacity changes. With 32 steps the
/// fade still looks continuous, and the slow tail of an ease-out, where opacity changes
/// by less than a step per frame, costs no redraws at all.
nonisolated struct AlphaQuantizer: Sendable, Hashable {
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

// MARK: - Stagger

/// Delays for text units that appear one after another, with the whole run capped.
///
/// A short chunk staggers at `interval` per unit; a long one shrinks the interval so
/// the last unit never starts more than `maxTotalDelay` after the first. A paragraph
/// that arrives at once therefore sweeps in quickly instead of trickling for seconds.
nonisolated struct StaggerSchedule: Sendable, Hashable {
    /// The delay between neighbouring units, in seconds.
    let interval: Double

    /// The longest delay any unit gets, in seconds.
    let maxTotalDelay: Double

    /// The delay between neighbouring units when `count` of them arrive together.
    func interval(forUnitCount count: Int) -> Double {
        guard count > 1 else { return 0 }
        return max(min(interval, maxTotalDelay / Double(count - 1)), 0)
    }
}

// MARK: - Text units

/// How an effect splits arriving text into units that start one after another.
nonisolated enum TextUnitGranularity: Sendable, Hashable {
    /// Every character the reader sees as one, emoji sequences included.
    case cluster
    /// Every word, as the system's word breaker finds them; works for CJK too.
    case word
}

nonisolated enum TextUnits {
    /// The UTF-16 offsets where the units of `range` start, ascending, beginning with
    /// `range.location`. Never more than `maxCount`: longer runs are thinned evenly, so
    /// a unit then spans several clusters or words.
    static func starts(
        in string: NSString,
        range: NSRange,
        granularity: TextUnitGranularity,
        maxCount: Int,
    ) -> [Int] {
        guard range.length > 0, NSMaxRange(range) <= string.length else { return [range.location] }
        var starts = [range.location]
        let options: NSString.EnumerationOptions = switch granularity {
        case .cluster: [.byComposedCharacterSequences, .substringNotRequired]
        case .word: [.byWords, .substringNotRequired]
        }
        string.enumerateSubstrings(in: range, options: options) { _, unitRange, _, _ in
            if unitRange.location > starts[starts.count - 1] {
                starts.append(unitRange.location)
            }
        }
        let limit = max(maxCount, 1)
        guard starts.count > limit else { return starts }
        return (0 ..< limit).map { starts[$0 * starts.count / limit] }
    }
}
