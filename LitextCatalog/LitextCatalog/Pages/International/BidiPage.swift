//
//  BidiPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): Arabic and Hebrew paragraphs with natural/right alignment and baseWritingDirection .rightToLeft, a
// mixed line (English + Hebrew + Arabic + numbers, like the unit test 'LTR שלום عربى 123'), selection
// across direction changes. Controls: writing direction picker (natural/LTR/RTL), alignment picker;
// readout of selection range and selected text.
struct BidiPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .bidi)
    }
}
