//
//  LineDrawingActionPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): TextLabel.LineDrawingAction via .litextLineDrawingAction: a wavy underline, a marker highlight
// behind a run, a margin bar for a quote; explain it is called once per line the range touches with
// (CGContext, CTLine, origin). Controls: style picker, color picker.
struct LineDrawingActionPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .lineDrawingAction)
    }
}
