//
//  SelectionPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): TextLabelView.isSelectable, selectionBackgroundColor, selectionRange (readout + set from code),
// selectAll(), selectWord(at:), selectLine(at:), clearSelection(),
// selectedPlainText()/selectedAttributedText(), copySelection(), selectionContains(_:), delegate
// didChangeSelection/didDragSelectionAt; buttons for each call. Note macOS mouse drag, double/triple
// click, Cmd-A/Cmd-C and iOS long-press + handles. Also SwiftUI
// .selectable/.onSelectionChange/.selectionBackgroundColor.
struct SelectionPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .selection)
    }
}
