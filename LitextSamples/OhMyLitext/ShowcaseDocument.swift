//
//  ShowcaseDocument.swift
//  OhMyLitext
//
//  Created by Litext Team.
//
//  Builds the single rich-text document rendered by the demo. Every Litext
//  feature — styled runs, links, inline attachments, bidirectional text,
//  custom line drawing, and selection — lives in one attributed string
//  displayed by one LTXLabel.
//

import CoreText
import Litext
import SwiftUI

// MARK: - Theme

struct ColorOption: Equatable {
    let name: String
    let color: PlatformColor?

    static func == (lhs: ColorOption, rhs: ColorOption) -> Bool {
        lhs.name == rhs.name
    }
}

struct DocumentTheme: Equatable {
    var fontSize: Double = 16
    var lineSpacing: Double = 5
    var isSelectable = true
    var textColorIndex = 0
    var selectionColorIndex = 0

    static let textColors: [ColorOption] = [
        ColorOption(name: "Default", color: PlatformColor.label),
        ColorOption(name: "Blue", color: PlatformColor.systemBlue),
        ColorOption(name: "Green", color: PlatformColor.systemGreen),
        ColorOption(name: "Orange", color: PlatformColor.systemOrange),
        ColorOption(name: "Purple", color: PlatformColor.systemPurple),
    ]

    static let selectionColors: [ColorOption] = [
        ColorOption(name: "Default", color: nil),
        ColorOption(name: "Blue", color: PlatformColor.systemBlue.withAlphaComponent(0.2)),
        ColorOption(name: "Green", color: PlatformColor.systemGreen.withAlphaComponent(0.2)),
        ColorOption(name: "Yellow", color: PlatformColor.systemYellow.withAlphaComponent(0.3)),
        ColorOption(name: "Pink", color: PlatformColor.systemPink.withAlphaComponent(0.2)),
    ]

    var textColor: PlatformColor {
        Self.textColors[textColorIndex].color ?? PlatformColor.label
    }

    var selectionColor: PlatformColor? {
        Self.selectionColors[selectionColorIndex].color
    }

    mutating func reset() {
        self = DocumentTheme()
    }
}

// MARK: - Document Builder

@MainActor
enum ShowcaseDocument {
    static let repoURL = URL(string: "https://github.com/Lakr233/Litext")!
    static let githubURL = URL(string: "https://github.com")!
    static let appleURL = URL(string: "https://developer.apple.com")!
    static let linkedAttachmentURL = URL(string: "https://example.com/linked-attachment")!

    static func make(theme: DocumentTheme) -> NSAttributedString {
        let text = NSMutableAttributedString()
        let style = Stylist(theme: theme)

        // Title block. The repository link is a full standalone line right below
        // the title so UI tests can tap it at a predictable offset.
        text.append(style.title("Litext\n"))
        text.append(style.link("github.com/Lakr233/Litext ↗\n", url: repoURL))
        text.append(style.subtitle("High-performance rich text, drawn with CoreText on every Apple platform.\n"))

        text.append(style.heading("RICH STYLES\n"))
        text.append(style.body("Mix "))
        text.append(style.bold("bold"))
        text.append(style.body(", "))
        text.append(style.italic("italic"))
        text.append(style.body(", "))
        text.append(style.colored("colored", color: .systemRed))
        text.append(style.body(", "))
        text.append(style.underlined("underlined"))
        text.append(style.body(", and "))
        text.append(style.struckThrough("struck-through"))
        text.append(style.body(" runs freely, or drop into "))
        text.append(style.code("monospaced code"))
        text.append(style.body(" inline.\n"))

        text.append(style.heading("LINKS\n"))
        text.append(style.body("Tap "))
        text.append(style.link("GitHub", url: githubURL))
        text.append(style.body(" or the "))
        // One URL spanning two differently-styled runs: verifies a single
        // highlight region covers multi-style links.
        text.append(style.boldLink("Apple ", url: appleURL))
        text.append(style.italicUnderlinedLink("Developer", url: appleURL))
        text.append(style.body(" link. On macOS, hovering shows a pointing hand and right-click offers Open / Copy.\n"))

        text.append(style.heading("INLINE ATTACHMENTS\n"))
        text.append(style.body("Native views flow with the text: "))
        text.append(attachmentString(
            title: "INLINE VIEW",
            width: 96,
            identifier: "demo.attachment.inline.view",
            linkURL: nil
        ))
        text.append(style.body(" sits on the baseline, while "))
        text.append(attachmentString(
            title: "LINKED VIEW",
            width: 120,
            identifier: "demo.attachment.linked.view",
            linkURL: linkedAttachmentURL
        ))
        text.append(style.body(" opens a link when activated.\n"))

        text.append(style.heading("BIDIRECTIONAL TEXT\n"))
        text.append(style.body("English שלום عربى 123 mixed-direction text lays out, hit-tests, and selects correctly.\n"))

        text.append(style.heading("CUSTOM DRAWING\n"))
        text.append(style.lineDrawn("A line-drawing callback paints this green underline straight into the CoreText context.\n"))

        text.append(style.heading("SELECTION\n"))
        text.append(style.body(
            "Try selecting this paragraph. On iOS, drag the selection handles; on macOS, click and drag, " +
                "double-click for a word, triple-click for a line, then copy with ⌘C or select everything with ⌘A.\n"
        ))
        text.append(style.body(
            "Litext is built for text-heavy interfaces — chat transcripts, articles, and documentation — " +
                "where CoreText keeps scrolling smooth no matter how much rich content is on screen.\n"
        ))

        text.append(style.caption("Rendered by a single LTXLabel — no TextKit involved."))
        return text
    }

    // MARK: Attachments

    private static func attachmentString(
        title: String,
        width: CGFloat,
        identifier: String,
        linkURL: URL?
    ) -> NSAttributedString {
        let attachment = LTXAttachment()
        attachment.size = CGSize(width: width, height: 28)
        attachment.view = makeBadgeView(title: title, width: width, identifier: identifier)

        let string = NSMutableAttributedString(string: LTXReplacementText)
        let range = NSRange(location: 0, length: string.length)
        string.addAttribute(.ltxAttachment, value: attachment, range: range)
        string.addAttribute(
            kCTRunDelegateAttributeName as NSAttributedString.Key,
            value: attachment.runDelegate,
            range: range
        )
        if let linkURL {
            string.addAttributes(
                [.link: linkURL, .foregroundColor: PlatformColor.link],
                range: range
            )
        }
        return string
    }

    private static func makeBadgeView(title: String, width: CGFloat, identifier: String) -> LTXPlatformView {
        #if canImport(UIKit)
            let label = UILabel()
            label.text = title
            label.textAlignment = .center
            label.font = .boldSystemFont(ofSize: 11)
            label.textColor = .white
            label.backgroundColor = .systemBlue
            label.layer.cornerRadius = 8
            label.clipsToBounds = true
            label.isAccessibilityElement = true
            label.accessibilityIdentifier = identifier
            return label
        #elseif canImport(AppKit)
            // NSTextField does not center its text vertically, so wrap it in a
            // container and keep it centered with autoresizing margins.
            let container = NSView(frame: CGRect(x: 0, y: 0, width: width, height: 28))
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor.systemBlue.cgColor
            container.layer?.cornerRadius = 8
            container.setAccessibilityIdentifier(identifier)

            let label = NSTextField(labelWithString: title)
            label.alignment = .center
            label.font = .boldSystemFont(ofSize: 11)
            label.textColor = .white
            label.sizeToFit()
            label.frame.origin = CGPoint(
                x: (container.bounds.width - label.frame.width) / 2,
                y: (container.bounds.height - label.frame.height) / 2
            )
            label.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
            container.addSubview(label)
            return container
        #endif
    }
}

// MARK: - Stylist

@MainActor
private struct Stylist {
    let theme: DocumentTheme

    private var bodyFont: PlatformFont {
        .systemFont(ofSize: theme.fontSize)
    }

    private var boldFont: PlatformFont {
        .boldSystemFont(ofSize: theme.fontSize)
    }

    private var italicFont: PlatformFont {
        #if canImport(UIKit)
            return .italicSystemFont(ofSize: theme.fontSize)
        #elseif canImport(AppKit)
            let base = NSFont.systemFont(ofSize: theme.fontSize)
            let descriptor = base.fontDescriptor.withSymbolicTraits(.italic)
            return NSFont(descriptor: descriptor, size: theme.fontSize) ?? base
        #endif
    }

    private var monoFont: PlatformFont {
        .monospacedSystemFont(ofSize: theme.fontSize - 1, weight: .regular)
    }

    private func paragraph(
        spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat = 6
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = theme.lineSpacing
        style.paragraphSpacing = spacingAfter
        style.paragraphSpacingBefore = spacingBefore
        return style
    }

    private func attributes(
        font: PlatformFont,
        color: PlatformColor,
        spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat = 6
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph(spacingBefore: spacingBefore, spacingAfter: spacingAfter),
        ]
    }

    func title(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: attributes(
            font: .boldSystemFont(ofSize: theme.fontSize * 2.2),
            color: theme.textColor,
            spacingAfter: 2
        ))
    }

    func subtitle(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: attributes(
            font: bodyFont,
            color: .secondaryLabel,
            spacingAfter: 10
        ))
    }

    func heading(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: attributes(
            font: .boldSystemFont(ofSize: max(11, theme.fontSize - 3)),
            color: .secondaryLabel,
            spacingBefore: 18,
            spacingAfter: 4
        ))
    }

    func body(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: attributes(
            font: bodyFont,
            color: theme.textColor
        ))
    }

    func caption(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: attributes(
            font: .systemFont(ofSize: max(10, theme.fontSize - 4)),
            color: .secondaryLabel,
            spacingBefore: 20
        ))
    }

    func bold(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: attributes(font: boldFont, color: theme.textColor))
    }

    func italic(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: attributes(font: italicFont, color: theme.textColor))
    }

    func colored(_ string: String, color: PlatformColor) -> NSAttributedString {
        NSAttributedString(string: string, attributes: attributes(font: bodyFont, color: color))
    }

    func underlined(_ string: String) -> NSAttributedString {
        var attrs = attributes(font: bodyFont, color: theme.textColor)
        attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        return NSAttributedString(string: string, attributes: attrs)
    }

    func struckThrough(_ string: String) -> NSAttributedString {
        var attrs = attributes(font: bodyFont, color: theme.textColor)
        attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        attrs[.strikethroughColor] = theme.textColor
        return NSAttributedString(string: string, attributes: attrs)
    }

    func code(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: attributes(font: monoFont, color: .systemPink))
    }

    func link(_ string: String, url: URL) -> NSAttributedString {
        var attrs = attributes(font: bodyFont, color: .link)
        attrs[.link] = url
        return NSAttributedString(string: string, attributes: attrs)
    }

    func boldLink(_ string: String, url: URL) -> NSAttributedString {
        var attrs = attributes(font: boldFont, color: .systemBlue)
        attrs[.link] = url
        return NSAttributedString(string: string, attributes: attrs)
    }

    func italicUnderlinedLink(_ string: String, url: URL) -> NSAttributedString {
        var attrs = attributes(font: italicFont, color: .systemPurple)
        attrs[.link] = url
        attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        return NSAttributedString(string: string, attributes: attrs)
    }

    func lineDrawn(_ string: String) -> NSAttributedString {
        let action = LTXLineDrawingAction { context, line, origin in
            var descent: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, &descent, nil))
            let underlineY = origin.y - descent - 2
            context.setStrokeColor(PlatformColor.systemGreen.cgColor)
            context.setLineWidth(1)
            context.move(to: CGPoint(x: origin.x, y: underlineY))
            context.addLine(to: CGPoint(x: origin.x + width, y: underlineY))
            context.strokePath()
        }
        var attrs = attributes(font: bodyFont, color: theme.textColor)
        attrs[.ltxLineDrawingCallback] = action
        return NSAttributedString(string: string, attributes: attrs)
    }
}

// MARK: - Platform Shims

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
    extension NSColor {
        static var label: NSColor {
            .labelColor
        }

        static var link: NSColor {
            .linkColor
        }

        static var secondaryLabel: NSColor {
            .secondaryLabelColor
        }
    }
#endif
