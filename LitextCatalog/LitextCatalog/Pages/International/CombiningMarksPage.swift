//
//  CombiningMarksPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): Combining accents (e + U+0301, stacked diacritics / Zalgo-light), Vietnamese, Thai and Devanagari
// with marks; selection snaps to grapheme clusters. Readout of the selected text and its UTF-16 length
// vs Character count.
struct CombiningMarksPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .combiningMarks)
    }
}
