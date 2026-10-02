//
//  LTXAnimationPolicy.swift
//  LitextAnimation
//
//  Created by Litext Team.
//

import Foundation

#if !os(watchOS)

    /// Everything an animation policy knows about one text change of a label.
    ///
    /// The label builds one for every assignment that changes its text, and passes the same
    /// value on to the animator when the policy lets the change animate.
    public struct LTXAnimationContext: Hashable {
        /// The difference between the previous and the new text.
        public let change: LTXTextChange

        /// The label's `animationIdentity` when it showed the previous text.
        public let previousIdentity: AnyHashable?

        /// The label's `animationIdentity` for the new text.
        public let identity: AnyHashable?

        /// Whether the label is in a window, where the change can be seen.
        public let isInWindow: Bool

        /// Whether the platform allows animations right now. `false` inside
        /// `UIView.performWithoutAnimation`, for example.
        public let areAnimationsEnabled: Bool

        /// Whether the person using the device asked for reduced motion. The default policy
        /// still animates; an animator reads this to tone its effect down.
        public let prefersReducedMotion: Bool

        public init(
            change: LTXTextChange,
            previousIdentity: AnyHashable?,
            identity: AnyHashable?,
            isInWindow: Bool,
            areAnimationsEnabled: Bool,
            prefersReducedMotion: Bool,
        ) {
            self.change = change
            self.previousIdentity = previousIdentity
            self.identity = identity
            self.isInWindow = isInWindow
            self.areAnimationsEnabled = areAnimationsEnabled
            self.prefersReducedMotion = prefersReducedMotion
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
    /// - The change inserts text.
    /// - The change is not a replacement of the whole text.
    ///
    /// Reduced motion does not stop the animation: the context carries it to the animator,
    /// which decides how to tone its effect down.
    public struct LTXDefaultAnimationPolicy: LTXAnimationPolicy, Sendable {
        public init() {}

        public func shouldAnimate(_ context: LTXAnimationContext) -> Bool {
            context.isInWindow
                && context.areAnimationsEnabled
                && !context.isIdentityChange
                && context.change.hasInsertion
                && !context.change.isReplacement
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
