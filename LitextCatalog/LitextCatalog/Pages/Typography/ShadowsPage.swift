//
//  ShadowsPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): NSShadow via .shadow attribute (offset, blurRadius, shadowColor) on a headline and on a run inside
// body text. Controls: x/y offset sliders, blur slider, color picker. If CoreText does not draw
// .shadow, say so and draw it with a LineDrawingAction instead.
struct ShadowsPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .shadows)
    }
}
