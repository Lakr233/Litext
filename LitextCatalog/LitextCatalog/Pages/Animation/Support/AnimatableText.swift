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
    struct AnimatableText: View {
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

        var body: some View {
            PlatformViewHost.label {
                LTXAnimatableLabel()
            } update: { label in
                update(label)
            }
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
    }

#endif
