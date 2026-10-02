//
//  CustomAnimatorPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): A minimal LTXTextAnimator written in the page file (e.g. a typewriter caret or per-line slide):
// animateChange(_:at:), advance(to:invalidation:) using
// LTXInvalidationContext.invalidateCharacters(in:), animatingRange, draw(_:in:at:) with
// LTXAnimatedLine, finish(); explain each step; show LTXTextChange fields for the last change. tvOS:
// CatalogUnavailableView.
struct CustomAnimatorPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .customAnimator)
    }
}
