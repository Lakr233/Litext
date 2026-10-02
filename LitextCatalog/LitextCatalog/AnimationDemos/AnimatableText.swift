//
//  AnimatableText.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  A small SwiftUI wrapper around LTXAnimatableLabel. Litext's own SwiftUI
//  TextLabel always creates a plain TextLabelView, so a view that animates
//  its text wraps the subclass itself, as here.
//

import Litext
import LitextAnimation
import SwiftUI

#if !os(watchOS)

    /// Shows attributed text in an `LTXAnimatableLabel`, animating each change with
    /// `animator`.
    ///
    /// Keep the animator in `@State` (or another owner that outlives body updates): a
    /// different instance replaces the label's animator and finishes its animations.
    ///
    /// ```swift
    /// @State private var animator = FadeInAnimator()
    ///
    /// AnimatableText(text: streamed, animator: animator)
    /// ```
    struct AnimatableText {
        var text: NSAttributedString
        var animator: (any LTXTextAnimator)?
        /// The label's policy; `nil` keeps `LTXDefaultAnimationPolicy`.
        var policy: (any LTXAnimationPolicy)?
        /// What the text belongs to; changing it shows the next text without animating.
        var identity: AnyHashable?

        init(
            text: NSAttributedString,
            animator: (any LTXTextAnimator)?,
            policy: (any LTXAnimationPolicy)? = nil,
            identity: AnyHashable? = nil,
        ) {
            self.text = text
            self.animator = animator
            self.policy = policy
            self.identity = identity
        }

        func makeLabel() -> LTXAnimatableLabel {
            let label = LTXAnimatableLabel()
            update(label)
            return label
        }

        func update(_ label: LTXAnimatableLabel) {
            if label.animator !== animator {
                label.animator = animator
            }
            if let policy {
                label.animationPolicy = policy
            }
            // The identity goes first, so a change of content is not animated.
            label.animationIdentity = identity
            label.attributedText = text
        }

        /// The proposed width, and the height the text needs at that width.
        func size(for proposal: ProposedViewSize, label: LTXAnimatableLabel) -> CGSize? {
            guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
            let fitting = label.textLayout.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            return CGSize(width: width, height: fitting.height.rounded(.up))
        }
    }

    #if canImport(UIKit)
        extension AnimatableText: UIViewRepresentable {
            func makeUIView(context _: Context) -> LTXAnimatableLabel {
                makeLabel()
            }

            func updateUIView(_ uiView: LTXAnimatableLabel, context _: Context) {
                update(uiView)
            }

            func sizeThatFits(_ proposal: ProposedViewSize, uiView: LTXAnimatableLabel, context _: Context) -> CGSize? {
                size(for: proposal, label: uiView)
            }
        }
    #else
        extension AnimatableText: NSViewRepresentable {
            func makeNSView(context _: Context) -> LTXAnimatableLabel {
                makeLabel()
            }

            func updateNSView(_ nsView: LTXAnimatableLabel, context _: Context) {
                update(nsView)
            }

            func sizeThatFits(_ proposal: ProposedViewSize, nsView: LTXAnimatableLabel, context _: Context) -> CGSize? {
                size(for: proposal, label: nsView)
            }
        }
    #endif

#endif
