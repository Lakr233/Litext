//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Litext
import Testing

@MainActor
@Test func renamedPublicAPIIsUsableWithoutTestableImport() throws {
    let attachment = TextLabel.Attachment()
    attachment.size = CGSize(width: 24, height: 16)

    let url = try #require(URL(string: "https://example.com/public-api"))
    let attachmentText = attachment.attributedString(attributes: [
        .link: url,
    ])

    #expect(attachmentText.string == TextLabel.Attachment.replacementText)
    #expect(attachmentText.attribute(.litextAttachment, at: 0, effectiveRange: nil) is TextLabel.Attachment)
    #expect(attachmentText.attribute(
        kCTRunDelegateAttributeName as NSAttributedString.Key,
        at: 0,
        effectiveRange: nil
    ) != nil)

    let layout = TextLabel.Layout(attributedString: attachmentText)
    let suggestedSize = layout.sizeThatFits(CGSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
    #expect(suggestedSize.width > 0)

    #if !os(watchOS)
        let label = TextLabelView(attributedText: attachmentText)
        label.isSelectable = true
        label.selectAll()
        _ = label.copySelection()
        label.clearSelection()
        #expect(label.attributedText.length == attachmentText.length)
    #endif
}
