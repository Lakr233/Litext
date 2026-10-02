//
//  SizingPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): TextLabelView.sizeThatFits(_:), intrinsicContentSize, preferredMaxLayoutWidth (0 = unconstrained)
// and TextLabel.Layout.sizeThatFits, side by side for the same text with a width slider; readouts of
// each size; note zero/negative width means unconstrained and invalid sizes are skipped (AGENTS layout
// rules).
struct SizingPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .sizing)
    }
}
