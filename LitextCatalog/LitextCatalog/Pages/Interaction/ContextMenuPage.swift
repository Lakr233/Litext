//
//  ContextMenuPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): The selection menu: UIKit textLabelView(_:editMenuForSelection:suggestedActions:) (iOS 16+,
// #available) adding a custom 'Copy as Markdown'-style action; AppKit
// textLabelView(_:menu:forSelection:event:) appending an item; macOS startSpeaking/stopSpeaking. Show
// what happens on tvOS (no menu: CatalogUnavailableView or a note).
struct ContextMenuPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .contextMenu)
    }
}
