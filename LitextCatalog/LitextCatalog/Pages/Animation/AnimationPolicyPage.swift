//
//  AnimationPolicyPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  One animatable label, a choice of animation policy, and buttons that make
//  each kind of text change. The readout shows the LTXAnimationContext the
//  policy saw for the last change, and what it decided.
//

import Litext
import LitextAnimation
import SwiftUI

struct AnimationPolicyPage: View {
    private static let code = """
    // The default: animate in a window, with animations enabled, for the
    // same identity, when the change inserts text (or text is in flight)
    // and is not a replacement of the whole text.
    label.animationPolicy = LTXDefaultAnimationPolicy()

    // Your own rule, from everything the label knows about the change.
    label.animationPolicy = LTXClosureAnimationPolicy { context in
        context.isInWindow
            && context.areAnimationsEnabled
            && !context.isIdentityChange
            && context.change.isAppend
    }

    // The context of a change:
    //   change.isAppend, .isReplacement, .isAttributeOnly,
    //   .insertedRange, .removedRange, .commonPrefixLength, ...
    //   isIdentityChange, isInWindow, areAnimationsEnabled,
    //   prefersReducedMotion, wasAnimating
    """

    var body: some View {
        #if os(tvOS)
            CatalogUnavailableView(page: .animationPolicy, reason: "The animation pages need sliders and toggles, which tvOS does not have.")
        #else
            PolicyDemoView(code: Self.code)
        #endif
    }
}

#if !os(tvOS)

    /// The policies the page offers.
    enum PolicyChoice: String, CaseIterable, Hashable {
        case standard
        case appendsOnly
        case everyChange
        case never

        var title: String {
            switch self {
            case .standard: "Default"
            case .appendsOnly: "Appends"
            case .everyChange: "Every"
            case .never: "Never"
            }
        }

        var explanation: String {
            switch self {
            case .standard:
                "LTXDefaultAnimationPolicy: in a window, animations enabled, same identity, not a replacement, and the change inserts text or text is still in flight."
            case .appendsOnly:
                "A closure policy that animates only text added at the end, as a chat stream adds it."
            case .everyChange:
                "A closure policy that animates every change in the window for the same identity, replacements included. The animator fades in whatever the change inserted."
            case .never:
                "A closure policy that returns false: every change appears at once, and text in flight finishes."
            }
        }

        var policy: any LTXAnimationPolicy {
            switch self {
            case .standard:
                LTXDefaultAnimationPolicy()
            case .appendsOnly:
                LTXClosureAnimationPolicy { context in
                    context.isInWindow
                        && context.areAnimationsEnabled
                        && !context.isIdentityChange
                        && context.change.isAppend
                }
            case .everyChange:
                LTXClosureAnimationPolicy { context in
                    context.isInWindow && !context.isIdentityChange
                }
            case .never:
                LTXClosureAnimationPolicy { _ in false }
            }
        }
    }

    /// What the policy saw and decided for one change.
    struct PolicyDecision {
        var change: LTXTextChange
        var isIdentityChange: Bool
        var isInWindow: Bool
        var areAnimationsEnabled: Bool
        var prefersReducedMotion: Bool
        var wasAnimating: Bool
        var animates: Bool
        var defaultAnimates: Bool
        var number: Int
    }

    /// The page's text and the decisions the policy made about it.
    @MainActor
    @Observable
    final class PolicyDemoModel {
        static let items = [
            ["Streaming text", "arrives", "a few words", "at a time,", "and only", "the new words", "fade in."],
            ["A reused cell", "shows another", "message:", "its identity", "changed, so", "nothing replays."],
            ["Replies", "can be", "restyled", "while they stream", "without cutting", "the fade short."],
        ]

        let driver = AnimatableLabelDriver()
        let animator = LTXFadeInAnimator()
        var choice = PolicyChoice.standard {
            didSet { installPolicy() }
        }

        private(set) var lastDecision: PolicyDecision?
        private(set) var identity = 0
        private var words: [String] = []
        private var isHighlighted = false
        private var decisionCount = 0

        init() {
            animator.configuration.duration = 0.9
            animator.configuration.stagger = LTXStaggerSchedule(interval: 0.06, maxTotalDelay: 0.6)
            words = Array(Self.items[0].prefix(2))
        }

        var text: NSAttributedString {
            AnimationPageText.render(
                words.joined(separator: " "),
                color: isHighlighted ? .systemOrange : .label,
            )
        }

        private var phrases: [String] {
            Self.items[identity % Self.items.count]
        }

        func makeLabel() -> LTXAnimatableLabel {
            let label = LTXAnimatableLabel()
            label.animator = animator
            label.animationIdentity = identity
            label.attributedText = text
            // Installed after the first text, so the readout starts with a change you make.
            label.animationPolicy = makePolicy()
            return label
        }

        private func installPolicy() {
            driver.label?.animationPolicy = makePolicy()
        }

        /// The chosen policy, wrapped so the page sees every decision it makes.
        private func makePolicy() -> any LTXAnimationPolicy {
            let policy = choice.policy
            return LTXClosureAnimationPolicy { [weak self] context in
                let animates = policy.shouldAnimate(context)
                self?.record(context, animates: animates)
                return animates
            }
        }

        // MARK: Changes

        func append() {
            let next = phrases.first { !words.contains($0) } ?? "and more"
            words.append(next)
            apply()
        }

        func insertInMiddle() {
            words.insert("really", at: max(words.count / 2, 1))
            apply()
        }

        func trim() {
            guard words.count > 1 else { return }
            words.removeLast()
            apply()
        }

        func restyle() {
            isHighlighted.toggle()
            apply()
        }

        func replace() {
            // Nothing in common with the items or each other at either end, so the change
            // is a replacement.
            let replacement = ["Quite", "different", "now!"]
            words = words == replacement ? ["Brand", "new", "text?"] : replacement
            apply()
        }

        /// Shows the next item, as a reused cell does: identity first, then its text.
        func nextItem() {
            identity += 1
            words = Array(phrases.prefix(2))
            driver.update { $0.animationIdentity = identity }
            apply()
        }

        func reset() {
            words = Array(phrases.prefix(2))
            isHighlighted = false
            driver.setText(text, animated: false)
            lastDecision = nil
        }

        private func apply() {
            driver.setText(text)
        }

        private func record(_ context: LTXAnimationContext, animates: Bool) {
            decisionCount += 1
            lastDecision = PolicyDecision(
                change: context.change,
                isIdentityChange: context.isIdentityChange,
                isInWindow: context.isInWindow,
                areAnimationsEnabled: context.areAnimationsEnabled,
                prefersReducedMotion: context.prefersReducedMotion,
                wasAnimating: context.wasAnimating,
                animates: animates,
                defaultAnimates: LTXDefaultAnimationPolicy().shouldAnimate(context),
                number: decisionCount,
            )
        }
    }

    struct PolicyDemoView: View {
        let code: String
        @State private var model = PolicyDemoModel()
        @State private var isSlowMotion = CatalogLaunchOptions.current.isSlowMotion

        var body: some View {
            CatalogPageScaffold(.animationPolicy, code: code) {
                VStack(alignment: .leading, spacing: 16) {
                    DrivenAnimatableLabel(driver: model.driver) {
                        model.makeLabel()
                    }
                    .accessibilityIdentifier("demo.policy.label")

                    changeButtons
                }
            } controls: {
                CatalogPicker("Policy", selection: $model.choice, options: PolicyChoice.allCases) { $0.title }
                    .accessibilityIdentifier("demo.policy.choice")
                CatalogNote(model.choice.explanation, systemImage: "info.circle")
                Toggle("Slow Motion", isOn: $isSlowMotion)
                PolicyDecisionView(decision: model.lastDecision, isAnimating: model.driver.isAnimating)
                CatalogNote(
                    "Reduced motion does not stop an animation: the context carries prefersReducedMotion to the animator, which tones its effect down. The fade on this page then drops its stagger. Turning reduced motion on finishes the animations in flight. Try it in \(AnimationPageText.reducedMotionSetting).",
                    systemImage: "figure.walk.motion",
                )
            }
            .onChange(of: isSlowMotion, initial: true) { _, isSlow in
                model.animator.speed = isSlow ? CatalogLaunchOptions.slowMotionSpeed : 1
            }
        }

        private var changeButtons: some View {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
                    buttons
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }

        @ViewBuilder private var buttons: some View {
            Button("Append") { model.append() }
                .accessibilityIdentifier("demo.policy.append")
            Button("Insert") { model.insertInMiddle() }
                .accessibilityIdentifier("demo.policy.insert")
            Button("Trim") { model.trim() }
                .accessibilityIdentifier("demo.policy.trim")
            Button("Restyle") { model.restyle() }
                .accessibilityIdentifier("demo.policy.restyle")
            Button("Replace") { model.replace() }
                .accessibilityIdentifier("demo.policy.replace")
            Button("Next Item") { model.nextItem() }
                .accessibilityIdentifier("demo.policy.nextItem")
            Button("Reset") { model.reset() }
                .accessibilityIdentifier("demo.policy.reset")
        }
    }

    /// The readout of the last decision: the verdict, the change and the context flags.
    private struct PolicyDecisionView: View {
        let decision: PolicyDecision?
        let isAnimating: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                CatalogReadout("isAnimating", value: isAnimating ? "true" : "false", identifier: "state.policy.isAnimating")
                if let decision {
                    CatalogReadout(
                        "Change #\(decision.number)",
                        value: decision.animates ? "animated" : "shown at once",
                        identifier: "state.policy.decision",
                    )
                    CatalogReadout(
                        "Default policy",
                        value: decision.defaultAnimates ? "would animate" : "would not animate",
                        identifier: "state.policy.default",
                    )
                    let change = decision.change
                    CatalogReadout("Length", value: "\(change.previousLength) → \(change.length)")
                    CatalogReadout("Common prefix / suffix", value: "\(change.commonPrefixLength) / \(change.commonSuffixLength)")
                    CatalogReadout(
                        "Inserted / removed",
                        value: "\(NSStringFromRange(change.insertedRange)) / \(NSStringFromRange(change.removedRange))",
                        identifier: "state.policy.ranges",
                    )
                    FlagGrid(flags: [
                        ("isAppend", change.isAppend),
                        ("isReplacement", change.isReplacement),
                        ("isAttributeOnly", change.isAttributeOnly),
                        ("hasInsertion", change.hasInsertion),
                        ("hasRemoval", change.hasRemoval),
                        ("isIdentityChange", decision.isIdentityChange),
                        ("isInWindow", decision.isInWindow),
                        ("areAnimationsEnabled", decision.areAnimationsEnabled),
                        ("prefersReducedMotion", decision.prefersReducedMotion),
                        ("wasAnimating", decision.wasAnimating),
                    ])
                    .accessibilityIdentifier("state.policy.flags")
                } else {
                    Text("Make a change to see what the policy saw.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Boolean fields as a grid of checkmarks.
    struct FlagGrid: View {
        let flags: [(name: String, value: Bool)]

        var body: some View {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(flags, id: \.name) { flag in
                    Label {
                        Text(flag.name)
                            .font(.callout.monospaced())
                            .foregroundStyle(flag.value ? .primary : .secondary)
                    } icon: {
                        Image(systemName: flag.value ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(flag.value ? Color.green : Color.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(flag.value ? "true" : "false")
                }
            }
        }
    }

#endif
