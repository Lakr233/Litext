//
//  LineBreakingPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): NSParagraphStyle.lineBreakMode .byWordWrapping vs .byCharWrapping on a narrow container,
// hyphenationFactor (and .usesDefaultHyphenation on newer systems, #available-gated), a long URL /
// long unbreakable word, and a note that Litext has no numberOfLines/truncation API (show how to cap
// height with a frame instead, or how a Layout subclass could stop drawing). Controls: width slider,
// mode picker, hyphenation slider.
struct LineBreakingPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .lineBreaking)
    }
}
