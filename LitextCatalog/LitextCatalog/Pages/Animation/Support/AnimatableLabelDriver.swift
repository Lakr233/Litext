//
//  AnimatableLabelDriver.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Lets a page drive one LTXAnimatableLabel the way UIKit or AppKit code
//  does: by calling its methods from button actions, not from SwiftUI
//  updates. The policy, control and custom animator pages use it.
//

import Litext
import LitextAnimation
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

#if !os(tvOS) && !os(watchOS)

    /// Owns the connection to one `LTXAnimatableLabel`: its text changes, its `isAnimating`
    /// state observed through key-value observing, and a revision that makes SwiftUI measure
    /// the label again after a change.
    @MainActor
    @Observable
    final class AnimatableLabelDriver {
        /// The label's `isAnimating`, as key-value observing last reported it.
        private(set) var isAnimating = false

        /// How many times the label started animating.
        private(set) var animationStarts = 0

        /// Bumped on every text change, so the host reads the label's new height.
        private(set) var revision = 0

        @ObservationIgnored private(set) weak var label: LTXAnimatableLabel?
        @ObservationIgnored private var observation: NSKeyValueObservation?

        /// Connects the driver to `label` and starts observing `isAnimating`.
        func attach(_ label: LTXAnimatableLabel) {
            self.label = label
            observation = label.observe(\.isAnimating, options: [.new]) { [weak self] _, change in
                let isAnimating = change.newValue ?? false
                MainActor.assumeIsolated {
                    self?.animatingDidChange(isAnimating)
                }
            }
        }

        /// Assigns `text` like `label.attributedText = text`, so the policy decides, or with
        /// `setAttributedText(_:animated:)` when `animated` is given.
        func setText(_ text: NSAttributedString, animated: Bool? = nil) {
            guard let label else { return }
            if let animated {
                label.setAttributedText(text, animated: animated)
            } else {
                label.attributedText = text
            }
            revision += 1
        }

        /// Runs `body` with the label, then measures it again.
        func update(_ body: (LTXAnimatableLabel) -> Void) {
            guard let label else { return }
            body(label)
            revision += 1
        }

        private func animatingDidChange(_ isAnimating: Bool) {
            guard isAnimating != self.isAnimating else { return }
            self.isAnimating = isAnimating
            if isAnimating {
                animationStarts += 1
            }
        }
    }

    /// Hosts the label an ``AnimatableLabelDriver`` drives. `make` builds and configures the
    /// label once, including its first text.
    struct DrivenAnimatableLabel: View {
        let driver: AnimatableLabelDriver
        let make: () -> LTXAnimatableLabel

        var body: some View {
            // Reading the revision here updates the host after every change, and SwiftUI
            // then measures the label again.
            let revision = driver.revision
            PlatformViewHost.label {
                let label = make()
                driver.attach(label)
                return label
            } update: { _ in
                _ = revision
            }
        }
    }

    /// The text the animation pages show: body text in the label color.
    enum AnimationPageText {
        static func render(_ string: String, color: PlatformColor = .label, size: CGFloat = 19) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [
                .font: PlatformFont.systemFont(ofSize: size),
                .foregroundColor: color,
            ])
        }

        /// Whether the system asks for reduced motion right now.
        static var prefersReducedMotion: Bool {
            #if canImport(UIKit)
                UIAccessibility.isReduceMotionEnabled
            #else
                NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            #endif
        }

        /// Where to turn reduced motion on, on this platform.
        static var reducedMotionSetting: String {
            #if os(macOS) || targetEnvironment(macCatalyst)
                "System Settings › Accessibility › Display › Reduce motion"
            #else
                "Settings › Accessibility › Motion › Reduce Motion"
            #endif
        }
    }

#endif
