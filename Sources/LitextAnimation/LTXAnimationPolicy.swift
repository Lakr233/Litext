//
//  LTXAnimationPolicy.swift
//  LitextAnimation
//
//  Created by Litext Team.
//

import Foundation
import Litext

#if !os(watchOS)

    /// Everything an animation policy and an animator know about one text change of a label.
    ///
    /// The label builds one for every assignment that changes its text, asks its policy
    /// whether to animate, and passes the same value to the animator when it does.
    @MainActor
    public struct LTXAnimationContext {
        /// The difference between the previous and the new text.
        public let change: LTXTextChange

        /// The label's `animationIdentity` when it showed the previous text.
        public let previousIdentity: AnyHashable?

        /// The label's `animationIdentity` for the new text.
        public let identity: AnyHashable?

        /// The layout that showed the previous text. It keeps its laid-out lines, so an
        /// animator can read where the previous glyphs were, or keep the layout to draw them
        /// on their way out.
        public let previousLayout: TextLabel.Layout

        /// The layout that shows the new text. The label typesets it on its next layout pass,
        /// so its geometry is ready by the first frame and the first draw, not yet here.
        public let layout: TextLabel.Layout

        /// Whether the label is in a window, where the change can be seen.
        public let isInWindow: Bool

        /// Whether the platform allows animations right now: `false` inside
        /// `UIView.performWithoutAnimation`, for example. Always `true` on AppKit, which has
        /// no such switch.
        public let areAnimationsEnabled: Bool

        /// Whether the person using the device asked for reduced motion, read when the change
        /// happened. The default policy still animates; an animator reads this to tone its
        /// effect down, to a plain fade for example.
        public let prefersReducedMotion: Bool

        /// Whether the label was still animating earlier text when this change arrived.
        public let wasAnimating: Bool

        public init(
            change: LTXTextChange,
            previousIdentity: AnyHashable?,
            identity: AnyHashable?,
            previousLayout: TextLabel.Layout,
            layout: TextLabel.Layout,
            isInWindow: Bool,
            areAnimationsEnabled: Bool,
            prefersReducedMotion: Bool,
            wasAnimating: Bool,
        ) {
            self.change = change
            self.previousIdentity = previousIdentity
            self.identity = identity
            self.previousLayout = previousLayout
            self.layout = layout
            self.isInWindow = isInWindow
            self.areAnimationsEnabled = areAnimationsEnabled
            self.prefersReducedMotion = prefersReducedMotion
            self.wasAnimating = wasAnimating
        }

        /// Whether the label now shows different content than before, as when a reused
        /// table or collection view cell displays another item.
        public var isIdentityChange: Bool {
            previousIdentity != identity
        }
    }

    /// Decides whether a label animates a text change.
    ///
    /// Hosts that reuse labels, such as table and collection view cells, use the policy to
    /// tell streaming into the same content from showing new content. A change the policy
    /// declines appears in its final state at once.
    @MainActor
    public protocol LTXAnimationPolicy {
        /// Whether the change described by `context` animates.
        ///
        /// - Important: Performance-sensitive. Called for every text change of the label.
        func shouldAnimate(_ context: LTXAnimationContext) -> Bool
    }

    /// The policy an animatable label uses unless told otherwise.
    ///
    /// A change animates only when all of these hold:
    ///
    /// - The label is in a window.
    /// - Animations are enabled.
    /// - The identity is unchanged, so a reused cell does not replay its text.
    /// - The change is not a replacement of the whole text.
    /// - The change inserts text, or the label is still animating earlier text. A streaming
    ///   renderer that restyles or trims text it already showed then does not cut the
    ///   animation of the text in flight short.
    ///
    /// A replacement of the whole text, such as a title or a counter showing a new value,
    /// animates under a custom policy, for example `LTXClosureAnimationPolicy { _ in true }`.
    ///
    /// Reduced motion does not stop the animation: the context carries it to the animator,
    /// which decides how to tone its effect down.
    public struct LTXDefaultAnimationPolicy: LTXAnimationPolicy, Sendable {
        public init() {}

        public func shouldAnimate(_ context: LTXAnimationContext) -> Bool {
            context.isInWindow
                && context.areAnimationsEnabled
                && !context.isIdentityChange
                && !context.change.isReplacement
                && (context.change.hasInsertion || context.wasAnimating)
        }
    }

    /// A policy that asks a closure.
    public struct LTXClosureAnimationPolicy: LTXAnimationPolicy {
        private let body: @MainActor (LTXAnimationContext) -> Bool

        /// Creates a policy that animates a change when `body` returns `true`.
        public init(_ body: @escaping @MainActor (LTXAnimationContext) -> Bool) {
            self.body = body
        }

        public func shouldAnimate(_ context: LTXAnimationContext) -> Bool {
            body(context)
        }
    }

#endif
