//
//  ParagraphStylePage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): NSParagraphStyle knobs on a multi-paragraph sample: alignment (left/center/right/justified/natural),
// lineSpacing, lineHeightMultiple, minimumLineHeight/maximumLineHeight,
// firstLineHeadIndent/headIndent/tailIndent, paragraphSpacing/paragraphSpacingBefore,
// baseWritingDirection. One control per knob; mention the CleanLayout note that glyph ink can exceed
// typographic bounds with tight line heights.
struct ParagraphStylePage: View {
    var body: some View {
        CatalogPlaceholderView(page: .paragraphStyle)
    }
}
