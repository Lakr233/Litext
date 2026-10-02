//
//  ResizableContainerPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): A draggable handle / slider that narrows and widens the container from ~40 pt to full width while
// the text reflows; readouts of width, measured height and line count (layoutLines.count). Works with
// TextLabel in SwiftUI.
struct ResizableContainerPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .resizableContainer)
    }
}
