//
//  StreamingDemoView.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Streams a canned model reply into one animatable label, token by token,
//  at an adjustable rate, with a choice of effect.
//

import Litext
import LitextAnimation
import SwiftUI

#if !os(tvOS)

    struct StreamingDemoView: View {
        enum Effect: String, CaseIterable, Identifiable {
            case none = "None"
            case fade = "Fade"
            case fadeUp = "Fade Up"

            var id: Self {
                self
            }

            /// The effect `-effect none|fade|fadeUp` names on the command line.
            static var launchEffect: Effect? {
                switch UserDefaults.standard.string(forKey: "effect") {
                case "none": Effect.none
                case "fade": .fade
                case "fadeUp": .fadeUp
                default: nil
                }
            }
        }

        private static let bottomID = "bottom"

        @State private var script = StreamingScript.make()
        @State private var effect = Effect.launchEffect ?? .fadeUp
        @State private var tokensPerSecond = 30.0
        @State private var isSlowMotion = AnimationDemo.launchesInSlowMotion
        @State private var tokenCount = 0
        @State private var runID = 0
        // The animators live as long as the page, so switching back keeps no state.
        @State private var fade = FadeInAnimator()
        @State private var fadeUp = FadeUpAnimator()

        private var animator: (any LTXTextAnimator)? {
            switch effect {
            case .none: nil
            case .fade: fade
            case .fadeUp: fadeUp
            }
        }

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    AnimatableText(text: script.prefix(tokens: tokenCount), animator: animator)
                        .accessibilityIdentifier("demo.streaming.label")
                        .padding(16)
                        .frame(maxWidth: 720, alignment: .leading)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                        .frame(maxWidth: .infinity)
                        .padding(16)
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                }
                // Follow the stream once it outgrows the screen, as a chat does.
                .onChange(of: tokenCount) {
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                controls
            }
            .navigationTitle("Streaming Text")
            .task(id: runID) {
                await stream()
            }
            .onChange(of: isSlowMotion, initial: true) { _, isSlow in
                let speed = isSlow ? AnimationDemo.slowMotionSpeed : 1
                fade.speed = speed
                fadeUp.speed = speed
            }
        }

        private var controls: some View {
            VStack(spacing: 12) {
                Picker("Effect", selection: $effect) {
                    ForEach(Effect.allCases) { effect in
                        Text(effect.rawValue).tag(effect)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("demo.streaming.effect")

                HStack(spacing: 12) {
                    Image(systemName: "tortoise")
                        .foregroundStyle(.secondary)
                    Slider(value: $tokensPerSecond, in: 5 ... 200)
                        .accessibilityLabel("Tokens per second")
                    Image(systemName: "hare")
                        .foregroundStyle(.secondary)
                    Text("\(Int(tokensPerSecond)) tok/s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }

                HStack {
                    Toggle("Slow Motion", isOn: $isSlowMotion)
                        .fixedSize()
                    Spacer()
                    Text("\(tokenCount) / \(script.tokenEnds.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button {
                        runID += 1
                    } label: {
                        Label("Restart", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("demo.streaming.restart")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }

        /// Reveals tokens at the chosen rate, one display frame at a time. Slow motion
        /// slows the stream as much as the effect, so the two stay in proportion.
        private func stream() async {
            tokenCount = 0
            var due = 0.0
            let frame = Duration.milliseconds(16)
            while tokenCount < script.tokenEnds.count {
                do {
                    try await Task.sleep(for: frame)
                } catch {
                    return
                }
                let speed = isSlowMotion ? AnimationDemo.slowMotionSpeed : 1
                due += tokensPerSecond * speed * 0.016
                let ready = Int(due)
                guard ready > 0 else { continue }
                due -= Double(ready)
                tokenCount = min(tokenCount + ready, script.tokenEnds.count)
            }
        }
    }

#endif
