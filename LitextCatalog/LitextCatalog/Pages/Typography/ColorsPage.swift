//
//  ColorsPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): Per-run .foregroundColor, dynamic system colors (label, secondaryLabel, systemBlue…) that follow
// light/dark mode, an alpha color, and .backgroundColor if CoreText draws it (check: Litext draws with
// CoreText only, so state plainly whether NSAttributedString .backgroundColor is drawn; if not, show a
// LineDrawingAction-based highlight as the workaround). Controls: color picker for the text, alpha
// slider.
struct ColorsPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .colors)
    }
}
