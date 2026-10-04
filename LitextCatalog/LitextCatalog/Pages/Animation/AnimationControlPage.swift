//
//  AnimationControlPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  The knobs LTXAnimatableLabel offers its host: assigning text with or
//  without animation, finishing the animations in flight, observing
//  isAnimating, changing animationIdentity, and the frame rate range its
//  display link asks for. The readout counts the frames the animator
//  actually got.
//

import DisplayLink
import Litext
import LitextAnimation
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct AnimationControlPage: View {
    private static let code = """
    let label = LTXAnimatableLabel()
    label.animator = LTXFadeUpAnimator()

    // Animate, if the policy agrees, or show the text at once.
    label.setAttributedText(text, animated: animateToggle.isOn)

    // Jump to the final text, for example before taking a snapshot.
    label.finishAnimations()

    // isAnimating is key-value observable.
    observation = label.observe(\\.isAnimating, options: [.new]) { _, change in
        spinner.isHidden = change.newValue != true
    }

    // Another item: its first text appears at once.
    label.animationIdentity = item.id

    // import DisplayLink for the range type.
    label.preferredFrameRateRange = DisplayLinkFrameRateRange(
        minimum: 30,
        maximum: 60,
        preferred: 30,
    )
    """

    var body: some View {
        #if os(tvOS)
            CatalogUnavailableView(page: .animationControl, reason: "The animation pages need sliders and toggles, which tvOS does not have.")
        #else
            AnimationControlDemoView(code: Self.code)
        #endif
    }
}

#if !os(tvOS)

    /// The frame rate ranges the page offers.
    enum FrameRateChoice: String, CaseIterable, Hashable {
        case standard
        case thirty
        case sixty
        case max

        var title: String {
            switch self {
            case .standard: "Default"
            case .thirty: "30"
            case .sixty: "60"
            case .max: "120"
            }
        }

        var range: DisplayLinkFrameRateRange {
            switch self {
            case .standard: DisplayLinkFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
            case .thirty: DisplayLinkFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
            case .sixty: DisplayLinkFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
            case .max: DisplayLinkFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
            }
        }

        var description: String {
            let range = range
            return "\(Int(range.minimum))–\(Int(range.maximum)), prefers \(Int(range.preferred))"
        }
    }

    /// A fade that counts the frames it is advanced, to show the rate the display link
    /// delivers.
    final class FrameCountingAnimator: LTXFadeInAnimator {
        /// Called when the animation ends, with the frames it got and how long it ran.
        var onFinish: ((_ frames: Int, _ duration: CFTimeInterval) -> Void)?

        private var frames = 0
        private var firstFrame: CFTimeInterval?
        private var lastFrame: CFTimeInterval = 0

        init() {
            var configuration = Configuration()
            configuration.rise = 6
            configuration.duration = 0.6
            configuration.stagger = LTXStaggerSchedule(interval: 0.02, maxTotalDelay: 0.5)
            super.init(configuration: configuration)
        }

        override func advance(to time: CFTimeInterval, invalidation: LTXInvalidationContext) -> Bool {
            frames += 1
            if firstFrame == nil {
                firstFrame = time
            }
            lastFrame = time
            let isActive = super.advance(to: time, invalidation: invalidation)
            if !isActive {
                report()
            }
            return isActive
        }

        override func finish() {
            super.finish()
            report()
        }

        private func report() {
            if let firstFrame, frames > 1 {
                onFinish?(frames, lastFrame - firstFrame)
            }
            frames = 0
            firstFrame = nil
        }
    }

    @MainActor
    @Observable
    final class AnimationControlModel {
        static let sentences = [
            "Each sentence fades up as it arrives.",
            "Turn off Animated and the next one appears at once.",
            "Finish jumps to the final text.",
            "A new identity shows its first text without animating.",
            "The frame rate range sets how often the animator runs.",
        ]

        let driver = AnimatableLabelDriver()
        let animator = FrameCountingAnimator()
        var isAnimated = true
        var frameRate = FrameRateChoice.standard {
            didSet { driver.update { $0.preferredFrameRateRange = frameRate.range } }
        }

        private(set) var identity = 1
        private(set) var lastRun: String?
        private var count = 1

        init() {
            animator.onFinish = { [weak self] frames, duration in
                self?.recordRun(frames: frames, duration: duration)
            }
        }

        var text: NSAttributedString {
            let sentences = (0 ..< count).map { Self.sentences[$0 % Self.sentences.count] }
            return AnimationPageText.render(sentences.joined(separator: " "))
        }

        func makeLabel() -> LTXAnimatableLabel {
            let label = LTXAnimatableLabel()
            label.animator = animator
            label.animationIdentity = identity
            label.preferredFrameRateRange = frameRate.range
            label.attributedText = text
            return label
        }

        func addSentence() {
            count += 1
            driver.setText(text, animated: isAnimated)
        }

        func finishAnimations() {
            driver.update { $0.finishAnimations() }
        }

        func newIdentity() {
            identity += 1
            count = 1
            driver.update { $0.animationIdentity = identity }
            // The default policy shows the first text of a new identity at once.
            driver.setText(text)
        }

        private func recordRun(frames: Int, duration: CFTimeInterval) {
            guard duration > 0 else { return }
            let rate = Double(frames - 1) / duration
            lastRun = "≈ \(Int(rate.rounded())) fps (\(frames) frames)"
        }
    }

    struct AnimationControlDemoView: View {
        let code: String
        @State private var model = AnimationControlModel()
        @State private var isSlowMotion = CatalogLaunchOptions.current.isSlowMotion

        var body: some View {
            CatalogPageScaffold(.animationControl, code: code) {
                VStack(alignment: .leading, spacing: 16) {
                    DrivenAnimatableLabel(driver: model.driver) {
                        model.makeLabel()
                    }
                    .frame(minHeight: 60, alignment: .topLeading)
                    .accessibilityIdentifier("demo.control.label")

                    HStack(spacing: 8) {
                        Button("Add Sentence") { model.addSentence() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("demo.control.add")
                        Button("Finish") { model.finishAnimations() }
                            .accessibilityIdentifier("demo.control.finish")
                        Button("New Identity") { model.newIdentity() }
                            .accessibilityIdentifier("demo.control.identity")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } controls: {
                Toggle("Animated", isOn: $model.isAnimated)
                    .accessibilityIdentifier("demo.control.animated")
                Toggle("Slow Motion", isOn: $isSlowMotion)
                CatalogPicker("Frame rate", selection: $model.frameRate, options: FrameRateChoice.allCases) { $0.title }
                    .accessibilityIdentifier("demo.control.frameRate")
                CatalogReadout("Frame rate range", value: model.frameRate.description, identifier: "state.control.range")
                CatalogReadout("Display", value: Self.displayRate, identifier: "state.control.display")
                CatalogReadout("Last animation", value: model.lastRun ?? "none yet", identifier: "state.control.lastRun")
                CatalogReadout("isAnimating", value: model.driver.isAnimating ? "true" : "false", identifier: "state.control.isAnimating")
                CatalogReadout("Animations started", value: "\(model.driver.animationStarts)", identifier: "state.control.starts")
                CatalogReadout("animationIdentity", value: "\(model.identity)", identifier: "state.control.identity")
                CatalogReadout(
                    "Reduced motion",
                    value: AnimationPageText.prefersReducedMotion ? "on" : "off",
                    identifier: "state.control.reducedMotion",
                )
                CatalogNote(
                    "The display link exists only while text is in flight, and asks for the range above; the display rounds it to a rate it can show, so 120 needs a ProMotion display. Turning on reduced motion (\(AnimationPageText.reducedMotionSetting)) finishes the animations in flight, and the fade then drops its stagger and rise.",
                    systemImage: "info.circle",
                )
            }
            .onChange(of: isSlowMotion, initial: true) { _, isSlow in
                model.animator.speed = isSlow ? CatalogLaunchOptions.slowMotionSpeed : 1
            }
        }

        /// The highest refresh rate of the main display.
        private static var displayRate: String {
            #if os(visionOS)
                "set by the system"
            #elseif canImport(UIKit)
                "up to \(UIScreen.main.maximumFramesPerSecond) Hz"
            #else
                (NSScreen.main?.maximumFramesPerSecond).map { "up to \($0) Hz" } ?? "unknown"
            #endif
        }
    }

#endif
