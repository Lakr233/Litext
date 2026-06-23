//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
@testable import Litext
import Testing

@MainActor
@Test func invalidRangesDoNotProduceRects() {
    let layout = LTXTextLayout(attributedString: NSAttributedString(string: "Hello Litext"))
    layout.containerSize = CGSize(width: 200, height: 60)

    #expect(layout.rects(for: NSRange(location: NSNotFound, length: 1)).isEmpty)
    #expect(layout.rects(for: NSRange(location: -1, length: 1)).isEmpty)
    #expect(layout.rects(for: NSRange(location: 0, length: 0)).isEmpty)
    #expect(layout.rects(for: NSRange(location: 500, length: 5)).isEmpty)
}

#if !os(watchOS)
    @MainActor
    @Test func publicSelectionRangeIsSanitized() {
        let label = LTXLabel(attributedText: NSAttributedString(string: "Hello"))

        label.selectionRange = NSRange(location: 1, length: 100)
        #expect(label.selectionRange == NSRange(location: 1, length: 4))

        label.selectionRange = NSRange(location: NSNotFound, length: 1)
        #expect(label.selectionRange == nil)

        label.selectionRange = NSRange(location: 0, length: 0)
        #expect(label.selectionRange == nil)
    }
#endif

@MainActor
@Test func highlightRegionsSeparateMultiStyleLinksAndLinkedAttachments() throws {
    let url = try #require(URL(string: "https://example.com/linked"))
    let text = NSMutableAttributedString(string: "Start ")
    text.append(NSAttributedString(
        string: "multi ",
        attributes: [
            .link: url,
            .foregroundColor: PlatformColor.systemBlue,
        ]
    ))
    text.append(NSAttributedString(
        string: "style",
        attributes: [
            .link: url,
            .foregroundColor: PlatformColor.systemPurple,
        ]
    ))
    text.append(NSAttributedString(string: " "))

    let attachment = LTXAttachment()
    attachment.size = CGSize(width: 30, height: 20)
    let attachmentString = NSMutableAttributedString(string: LTXReplacementText)
    let attachmentRange = NSRange(location: 0, length: attachmentString.length)
    attachmentString.addAttributes(
        [
            .ltxAttachment: attachment,
            .link: url,
            kCTRunDelegateAttributeName as NSAttributedString.Key: attachment.runDelegate,
        ],
        range: attachmentRange
    )
    text.append(attachmentString)

    let layout = LTXTextLayout(attributedString: text)
    layout.containerSize = CGSize(width: 240, height: 80)
    layout.updateHighlightRegions()

    let linkRegions = layout.highlightRegions.filter { $0.kind == .link }
    let attachmentRegions = layout.highlightRegions.filter { $0.kind == .attachment }

    #expect(linkRegions.count == 2)
    #expect(attachmentRegions.count == 1)
    #expect(linkRegions.contains { $0.stringRange == NSRange(location: 6, length: 11) })
    #expect(attachmentRegions.first?.cgRects.isEmpty == false)
}

@MainActor
@Test func attachmentRunDelegateDoesNotRetainAfterAttributedStringDrops() {
    weak var weakAttachment: LTXAttachment?

    do {
        let attachment = LTXAttachment()
        attachment.size = CGSize(width: 24, height: 16)
        weakAttachment = attachment

        let string = NSMutableAttributedString(string: LTXReplacementText)
        string.addAttribute(
            kCTRunDelegateAttributeName as NSAttributedString.Key,
            value: attachment.runDelegate,
            range: NSRange(location: 0, length: string.length)
        )
        _ = string
    }

    #expect(weakAttachment == nil)
}
