//
//  FontsPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): System fonts at several sizes and every weight (ultraLight…black), italic and bold symbolic traits,
// a monospaced font, monospaced digits, a custom font by name with a fallback, and Dynamic Type text
// styles (preferredFont(forTextStyle:)). Controls: size slider, weight picker, italic toggle, design
// picker (default/serif/rounded/monospaced via font descriptors). Use TextLabel(attributedString:).
struct FontsPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .fonts)
    }
}
