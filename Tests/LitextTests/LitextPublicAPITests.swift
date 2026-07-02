//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Litext
import Testing

@MainActor
private final class OpenLayoutOverride: TextLabel.Layout {
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        super.sizeThatFits(size)
    }
}

@MainActor
private final class OpenAttachmentOverride: TextLabel.Attachment {
    override func attributedString(
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        super.attributedString(attributes: attributes)
    }
}

#if !os(watchOS)
    @MainActor
    private final class OpenTextLabelViewOverride: TextLabelView {
        override var isSelectable: Bool {
            get { super.isSelectable }
            set { super.isSelectable = newValue }
        }
    }
#endif

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

@MainActor
@Test func openClassAPISupportsExternalSubclassing() {
    let attachment = OpenAttachmentOverride()
    attachment.size = CGSize(width: 12, height: 8)
    #expect(attachment.attributedString(attributes: [:]).length == 1)

    let layout = OpenLayoutOverride(attributedString: NSAttributedString(string: "Subclassable"))
    #expect(layout.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)).width > 0)

    #if !os(watchOS)
        let label = OpenTextLabelViewOverride()
        label.isSelectable = true
        #expect(label.isSelectable)
    #endif
}
