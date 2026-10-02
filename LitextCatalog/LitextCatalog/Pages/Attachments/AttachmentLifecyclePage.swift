//
//  AttachmentLifecyclePage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): Replace the text repeatedly (button + auto toggle) and show how many attachment views are alive
// (weak references / deinit counter), that views are reused when the same attachment stays, and
// released when the text drops them. Readouts: live attachment count, total created. Note the
// evictCoreTextLastTypesetAttributes caveat from AGENTS (CoreText keeps the last typeset attributes
// per thread).
struct AttachmentLifecyclePage: View {
    var body: some View {
        CatalogPlaceholderView(page: .attachmentLifecycle)
    }
}
