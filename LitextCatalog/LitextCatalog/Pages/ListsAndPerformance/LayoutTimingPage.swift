//
//  LayoutTimingPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): Live timing readouts for a document of N paragraphs (slider 10…5000): time for Layout creation,
// sizeThatFits, first layout, draw(in:) of the whole text and of a visible rect, measured with
// ContinuousClock; table of results; note the performance baseline in Documents/Research/Performance-
// Baseline.md.
struct LayoutTimingPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .layoutTiming)
    }
}
