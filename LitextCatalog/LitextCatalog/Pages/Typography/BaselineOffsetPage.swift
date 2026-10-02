//
//  BaselineOffsetPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): The .baselineOffset attribute for superscripts (E = mc², footnote marks¹), subscripts (H₂O-style
// with a smaller font) and a raised badge. Controls: offset slider (-10…10), font scale slider for the
// shifted run. Mention how offset runs affect line height.
struct BaselineOffsetPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .baselineOffset)
    }
}
