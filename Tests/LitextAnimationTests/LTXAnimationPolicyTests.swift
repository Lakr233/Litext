//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//
//  The default animation policy checks each of its conditions on its own, and
//  the closure policy forwards the context it gets.
//

#if !os(watchOS)

    import Foundation
    import LitextAnimation
    import Testing

    @MainActor
    @Suite("Animation policy")
    struct LTXAnimationPolicyTests {
        private static let streamed = LTXTextChange(from: "Hello", to: "Hello, world")

        private static func context(
            change: LTXTextChange = streamed,
            previousIdentity: AnyHashable? = "message",
            identity: AnyHashable? = "message",
            isInWindow: Bool = true,
            areAnimationsEnabled: Bool = true,
            prefersReducedMotion: Bool = false,
        ) -> LTXAnimationContext {
            LTXAnimationContext(
                change: change,
                previousIdentity: previousIdentity,
                identity: identity,
                isInWindow: isInWindow,
                areAnimationsEnabled: areAnimationsEnabled,
                prefersReducedMotion: prefersReducedMotion,
            )
        }

        private let policy = LTXDefaultAnimationPolicy()

        @Test
        func `streaming into the same content animates`() {
            #expect(policy.shouldAnimate(Self.context()))
        }

        @Test
        func `content without an identity still animates`() {
            #expect(policy.shouldAnimate(Self.context(previousIdentity: nil, identity: nil)))
        }

        @Test
        func `a new identity does not animate`() {
            let context = Self.context(identity: "another message")
            #expect(context.isIdentityChange)
            #expect(!policy.shouldAnimate(context))
        }

        @Test
        func `gaining or losing an identity counts as a new identity`() {
            #expect(!policy.shouldAnimate(Self.context(previousIdentity: nil)))
            #expect(!policy.shouldAnimate(Self.context(identity: nil)))
        }

        @Test
        func `a label outside a window does not animate`() {
            #expect(!policy.shouldAnimate(Self.context(isInWindow: false)))
        }

        @Test
        func `disabled animations do not animate`() {
            #expect(!policy.shouldAnimate(Self.context(areAnimationsEnabled: false)))
        }

        @Test
        func `a change without new text does not animate`() {
            let deletion = LTXTextChange(from: "Hello, world", to: "Hello")
            #expect(!policy.shouldAnimate(Self.context(change: deletion)))

            let restyled = LTXTextChange(
                from: NSAttributedString(string: "Hello", attributes: [.testStyle: 1]),
                to: NSAttributedString(string: "Hello", attributes: [.testStyle: 2]),
            )
            #expect(restyled.isAttributeOnly)
            #expect(!policy.shouldAnimate(Self.context(change: restyled)))
        }

        @Test
        func `replacing the whole text does not animate`() {
            let replacement = LTXTextChange(from: "Hello", to: "Goodbye")
            #expect(replacement.isReplacement)
            #expect(!policy.shouldAnimate(Self.context(change: replacement)))
        }

        @Test
        func `the first text animates`() {
            #expect(policy.shouldAnimate(Self.context(change: LTXTextChange(from: "", to: "Hi"))))
        }

        @Test
        func `reduced motion is left to the animator`() {
            let context = Self.context(prefersReducedMotion: true)
            #expect(context.prefersReducedMotion)
            #expect(policy.shouldAnimate(context))
        }

        @Test
        func `the closure policy answers with its closure`() {
            var seen: [LTXAnimationContext] = []
            let policy = LTXClosureAnimationPolicy { context in
                seen.append(context)
                return context.prefersReducedMotion
            }
            let calm = Self.context(prefersReducedMotion: true)
            let lively = Self.context(isInWindow: false)
            #expect(policy.shouldAnimate(calm))
            #expect(!policy.shouldAnimate(lively))
            #expect(seen == [calm, lively])
        }
    }

#endif
