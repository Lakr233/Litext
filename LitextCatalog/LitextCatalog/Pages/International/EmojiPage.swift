//
//  EmojiPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): ZWJ families, flags, skin-tone modifiers, keycaps, emoji presentation selectors, mixed with text at
// several sizes. Selection and characterIndex(at:) treat each grapheme cluster as one; show a readout
// of the hit character and its UTF-16 range. Note that emoji bitmaps may draw outside typographic
// bounds (known limitation).
struct EmojiPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .emoji)
    }
}
