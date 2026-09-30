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

    /// Overrides the drawing, sizing and layout hooks from outside the module,
    /// which only compiles while they are `open`.
    @MainActor
    private final class CustomizedTextLabelView: TextLabelView {
        var drawCount = 0
        var layoutCount = 0

        override var intrinsicContentSize: CGSize {
            let size = super.intrinsicContentSize
            return CGSize(width: size.width + 10, height: size.height)
        }

        #if canImport(UIKit)
            override func draw(_ rect: CGRect) {
                drawCount += 1
                super.draw(rect)
            }

            override func layoutSubviews() {
                layoutCount += 1
                super.layoutSubviews()
            }

            func runLayoutPass() {
                layoutIfNeeded()
            }
        #elseif canImport(AppKit)
            override func draw(_ dirtyRect: NSRect) {
                drawCount += 1
                super.draw(dirtyRect)
            }

            override func layout() {
                layoutCount += 1
                super.layout()
            }

            func runLayoutPass() {
                layoutSubtreeIfNeeded()
            }
        #endif
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

    layout.containerSize = CGSize(width: 100, height: suggestedSize.height)
    #expect(layout.visibleLineCount(in: nil) > 0)
    if let context = CGContext(
        data: nil,
        width: 100,
        height: max(1, Int(suggestedSize.height.rounded(.up))),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) {
        layout.draw(in: context, visibleRect: CGRect(x: 0, y: 0, width: 100, height: 10))
    }

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

#if !os(watchOS)
    @MainActor
    @Test func drawingSizingAndLayoutHooksAreOpen() {
        let text = NSAttributedString(string: "Open hooks")
        let plain = TextLabelView(attributedText: text)
        let label = CustomizedTextLabelView(attributedText: text)
        #expect(label.intrinsicContentSize.width == plain.intrinsicContentSize.width + 10)

        label.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
        label.runLayoutPass()
        #expect(label.layoutCount > 0)
    }

    @MainActor
    @Test func viewSpaceConvertersFlipAgainstTheLaidOutHeight() throws {
        let url = try #require(URL(string: "https://example.com"))
        let text = NSMutableAttributedString(string: "Tap here")
        text.addAttribute(.link, value: url, range: NSRange(location: 4, length: 4))
        let label = TextLabelView(attributedText: text)
        label.frame = CGRect(x: 0, y: 0, width: 200, height: 60)
        #if canImport(UIKit)
            label.layoutIfNeeded()
        #elseif canImport(AppKit)
            label.layoutSubtreeIfNeeded()
        #endif

        let run = try #require(label.layoutRuns(matching: .link).first)
        let viewRect = label.viewRect(fromLayoutRect: run.rect)
        #expect(viewRect.size == run.rect.size)
        #expect(viewRect.minY == 60 - run.rect.maxY)
        #expect(label.layoutRect(fromViewRect: viewRect) == run.rect)

        let tap = CGPoint(x: viewRect.midX, y: viewRect.midY)
        let layoutTap = label.layoutPoint(fromViewPoint: tap)
        #expect(run.rect.contains(layoutTap))
    }
#endif
