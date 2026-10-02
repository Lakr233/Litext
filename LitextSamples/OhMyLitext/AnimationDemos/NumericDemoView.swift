//
//  NumericDemoView.swift
//  OhMyLitext
//
//  Created by Litext Team.
//
//  A title bar like FlowDown's, cycling through conversation titles, and a
//  counter, both rolling from one value to the next with
//  NumericTransitionAnimator.
//

import Litext
import LitextAnimation
import SwiftUI

#if !os(tvOS)

    struct NumericDemoView: View {
        private static let titles = [
            "New Conversation",
            "Swift Concurrency Basics",
            "Trip to Kyoto 🇯🇵",
            "如何优化列表滚动性能",
            "Debugging a Memory Leak",
            "Weekend Recipe Ideas",
            "Chat",
        ]

        @State private var titleIndex = 0
        @State private var count = 1024
        @State private var isAutoPlaying = true
        @State private var isSlowMotion = AnimationDemo.launchesInSlowMotion
        @State private var titleAnimator = NumericTransitionAnimator()
        @State private var counterAnimator = NumericTransitionAnimator()

        var body: some View {
            ScrollView {
                VStack(spacing: 20) {
                    titleBar
                    counter
                    controls
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            .navigationTitle("Numeric Transition")
            .task(id: isAutoPlaying) {
                await autoPlay()
            }
            .onChange(of: isSlowMotion, initial: true) { _, isSlow in
                let speed = isSlow ? AnimationDemo.slowMotionSpeed : 1
                titleAnimator.speed = speed
                counterAnimator.speed = speed
            }
        }

        // MARK: - Labels

        /// A navigation bar with the title centred in bold body text, as FlowDown shows
        /// the conversation title.
        private var titleBar: some View {
            HStack(spacing: 12) {
                Image(systemName: "sidebar.left")
                AnimatableText(
                    text: Self.titleText(Self.titles[titleIndex]),
                    animator: titleAnimator,
                    policy: NumericTransitionAnimator.policy,
                )
                .accessibilityIdentifier("demo.numeric.title")
                Image(systemName: "square.and.pencil")
            }
            .foregroundStyle(.tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        }

        private var counter: some View {
            VStack(spacing: 4) {
                AnimatableText(
                    text: Self.counterText(count),
                    animator: counterAnimator,
                    policy: NumericTransitionAnimator.policy,
                )
                .accessibilityIdentifier("demo.numeric.counter")
                Text("tokens used")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        }

        private var controls: some View {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button("−1") { count -= 1 }
                        .accessibilityIdentifier("demo.numeric.decrement")
                    Button("+1") { count += 1 }
                        .accessibilityIdentifier("demo.numeric.increment")
                    Button("Jump") { jump() }
                        .accessibilityIdentifier("demo.numeric.jump")
                    Button("Next Title") { nextTitle() }
                        .accessibilityIdentifier("demo.numeric.nextTitle")
                }
                .buttonStyle(.bordered)

                Toggle("Auto Play", isOn: $isAutoPlaying)
                Toggle("Slow Motion", isOn: $isSlowMotion)
                Text("Glyphs both texts share slide into place; new ones roll in on a spring, old ones roll away. A number that goes down rolls the other way.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        // MARK: - Content

        private static func titleText(_ title: String) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            return NSAttributedString(string: title, attributes: [
                .font: PlatformFont.boldSystemFont(ofSize: 17),
                .foregroundColor: PlatformColor.label,
                .paragraphStyle: paragraph,
            ])
        }

        private static func counterText(_ count: Int) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            return NSAttributedString(string: count.formatted(), attributes: [
                .font: PlatformFont.monospacedDigitSystemFont(ofSize: 56, weight: .bold),
                .foregroundColor: PlatformColor.label,
                .paragraphStyle: paragraph,
            ])
        }

        private func nextTitle() {
            titleIndex = (titleIndex + 1) % Self.titles.count
        }

        /// Moves the counter by a random amount, up or down, so the transition shows
        /// both directions and changes of length.
        private func jump() {
            let magnitude = [1, 7, 42, 380, 2500].randomElement() ?? 1
            count = max(count + (Bool.random() ? magnitude : -magnitude), 0)
        }

        private func autoPlay() async {
            guard isAutoPlaying else { return }
            while !Task.isCancelled {
                // A transition takes about a second; slow motion stretches it tenfold.
                let pause = isSlowMotion ? 12.0 : 2.2
                do {
                    try await Task.sleep(for: .seconds(pause))
                } catch {
                    return
                }
                nextTitle()
                jump()
            }
        }
    }

#endif
