//
//  CatalogRootView.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  The sidebar of pages, grouped as CatalogGroup lists them, and the page
//  picked from it. On iPhone the split view collapses to a list that pushes
//  each page.
//

import SwiftUI

struct CatalogRootView: View {
    @State private var selection: CatalogPageID? = CatalogLaunchOptions.current.page
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            CatalogSidebar(selection: $selection)
        } detail: {
            NavigationStack {
                if let selection {
                    selection.content
                        .id(selection)
                } else {
                    CatalogWelcomeView()
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 480)
        #endif
    }
}

/// The list of pages.
struct CatalogSidebar: View {
    @Binding var selection: CatalogPageID?

    var body: some View {
        List(selection: $selection) {
            ForEach(CatalogGroup.allCases) { group in
                Section(group.title) {
                    ForEach(group.pages) { page in
                        NavigationLink(value: page) {
                            Label(page.title, systemImage: page.systemImage)
                        }
                        .accessibilityHint(page.summary)
                        .accessibilityIdentifier("catalog.page.\(page.rawValue)")
                    }
                }
            }
        }
        .navigationTitle("Litext")
        #if os(macOS)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        #endif
    }
}

/// What the detail column shows before a page is picked.
struct CatalogWelcomeView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Litext Catalog", systemImage: "textformat")
        } description: {
            Text("Pick a page to see one part of Litext at work: its explanation, a live demo, the controls that matter, and the code behind it.")
        }
    }
}

#Preview {
    CatalogRootView()
}
