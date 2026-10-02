//
//  LinksPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): Links via .link (URL and String values), TextLabel.onTapLink /
// TextLabelViewDelegate.textLabelView(_:didTapHighlightRegion:at:) with a readout of the last tapped
// URL, TextLabelView.linkHighlightColor and linkHighlightCornerRadius (controls: color picker, radius
// slider), multi-style links and HighlightRegion.linkURL. Use TextLabelView through
// PlatformViewHost.label for the highlight knobs.
struct LinksPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .links)
    }
}
