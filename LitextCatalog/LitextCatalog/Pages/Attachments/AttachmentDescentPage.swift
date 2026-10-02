//
//  AttachmentDescentPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): TextLabel.Attachment.descent: nil (default) vs explicit values, showing how far the view hangs below
// the baseline; draw the baseline from layoutLines.baselineOrigin. Control: descent slider
// (0…size.height), 'use default' toggle.
struct AttachmentDescentPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .attachmentDescent)
    }
}
