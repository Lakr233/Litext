//
//  CustomLayoutPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): Subclass TextLabelView overriding makeTextLayout(_:) to return a TextLabel.Layout subclass that
// overrides draw(line:at:in:) (call super) to paint alternating line backgrounds / highlight the line
// under the pointer; also reloadTextLayout()/invalidateTextLayout()/setNeedsTextDisplay(). Controls:
// highlight color, toggle the custom layout on/off.
struct CustomLayoutPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .customLayout)
    }
}
