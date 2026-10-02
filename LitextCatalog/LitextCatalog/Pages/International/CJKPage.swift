//
//  CJKPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): Chinese (simplified/traditional), Japanese (kana + kanji, with punctuation that must not start a
// line) and Korean paragraphs, plus mixed CJK-Latin text. Selectable; readout of the selected text.
// Controls: width slider so the kinsoku line breaking is visible, font size slider.
struct CJKPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .cjk)
    }
}
