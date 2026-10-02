//
//  VerticalMetricsPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): Scripts with tall ascenders/deep descenders (Thai, Tibetan, Burmese, Arabic marks) and mixed font
// sizes on one line; overlay the line rects from layoutLines so the line box is visible; explain that
// sizes come from typographic bounds and ink outside them can clip (AGENTS 'Typographic bounds' rule).
struct VerticalMetricsPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .verticalMetrics)
    }
}
