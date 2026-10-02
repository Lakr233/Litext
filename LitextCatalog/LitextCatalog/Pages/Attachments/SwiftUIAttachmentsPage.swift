//
//  SwiftUIAttachmentsPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): SwiftUI views hosted inline through CatalogAttachmentViews.hosting(_:size:) (TextLabel.Attachment.swiftUIView exists only on watchOS; elsewhere the attachment takes a UIView/NSView), e.g. (a capsule tag, an SF Symbol, a small
// chart-like view) inline; TextLabel.onTapAttachment with a readout of which attachment was tapped;
// attributedStringRepresentation() for copy.
struct SwiftUIAttachmentsPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .swiftUIAttachments)
    }
}
