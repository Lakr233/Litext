//
//  AnimationPolicyPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): LTXDefaultAnimationPolicy vs LTXClosureAnimationPolicy (e.g. animate only appends, or only when the
// text grows by >N chars), listing LTXAnimationContext fields in a readout for the last change
// (change.isAppend/isReplacement/isAttributeOnly, identity change, isInWindow, areAnimationsEnabled,
// prefersReducedMotion, wasAnimating); reduced-motion note (Settings > Accessibility > Reduce Motion /
// NSWorkspace accessibilityDisplayShouldReduceMotion). Must work on iOS and native macOS (use
// AnimatableText or PlatformViewHost.label with LTXAnimatableLabel); on tvOS show
// CatalogUnavailableView like StreamingPage.
struct AnimationPolicyPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .animationPolicy)
    }
}
