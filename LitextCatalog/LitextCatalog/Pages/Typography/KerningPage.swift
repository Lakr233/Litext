//
//  KerningPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): The .kern attribute on a whole string and on a single run (tight headline, loose all-caps label),
// plus .tracking if CoreText honours it on the deployment floors. Controls: kern slider (-2…10 pt) and
// a readout of the measured width from TextLabel.Layout.sizeThatFits.
struct KerningPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .kerning)
    }
}
