//
//  GeometryPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): Overlay on a TextLabelView: every LayoutLine.rect, its baseline (baselineOrigin), and LayoutRun
// rects from layoutRuns(matching:) (e.g. runs carrying .link or a custom key), converted with
// viewRect(fromLayoutRect:); rects(for:) / enumerateTextRects(in:using:) for a chosen range. Toggles
// for each overlay; readout of line count and run count.
struct GeometryPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .geometry)
    }
}
