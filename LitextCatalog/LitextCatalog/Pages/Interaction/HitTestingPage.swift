//
//  HitTestingPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): As the pointer moves (macOS .onContinuousHover / iOS pointer + tap / drag gesture), show
// TextLabelView.characterIndex(at:), Layout.textIndex(at:), nearestTextIndex(at:),
// highlightRegion(at:) kind and range, and draw the hit character rect from rects(for:) converted with
// viewRect(fromLayoutRect:). Readouts for each value; layoutPoint(fromViewPoint:) shown too.
struct HitTestingPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .hitTesting)
    }
}
