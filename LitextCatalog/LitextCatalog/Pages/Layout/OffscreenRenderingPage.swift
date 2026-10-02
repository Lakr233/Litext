//
//  OffscreenRenderingPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): TextLabel.Layout(attributedString:) without a view: set containerSize, sizeThatFits, draw(in:) /
// draw(in:visibleRect:) into a CGContext (bitmap), visibleLineCount(in:), show the resulting CGImage
// in SwiftUI Image; controls for width and visible rect; readout of render time.
struct OffscreenRenderingPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .offscreenRendering)
    }
}
