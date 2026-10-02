//
//  ViewAttachmentsPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): TextLabel.Attachment(size:view:) with views of several sizes (small icon, tall image-like block,
// wide banner) inline in a paragraph; attributedString(attributes:) to give them a font/link;
// attachments wrap with the text. Controls: attachment size slider, width slider for the container.
struct ViewAttachmentsPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .viewAttachments)
    }
}
