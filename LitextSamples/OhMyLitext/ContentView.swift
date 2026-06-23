//
//  ContentView.swift
//  OhMyLitext
//
//  Created by Litext Team.
//

import CoreText
import Litext
import SwiftUI

struct ContentView: View {
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var linkTapped: URL?
    @State private var lastTappedURL = ""
    @State private var lastSelectedText = ""
    @State private var showAlert = false
    @State private var showSettings = false

    // Appearance settings
    @State private var fontSize: Double = 16
    @State private var lineSpacing: Double = 4
    @State private var isSelectable: Bool = true
    @State private var textColorIndex: Int = 0
    @State private var selectionColorIndex: Int = 0

    private let textColors: [(name: String, color: PlatformColor)] = [
        ("Default", PlatformColor.label),
        ("Blue", PlatformColor.systemBlue),
        ("Green", PlatformColor.systemGreen),
        ("Orange", PlatformColor.systemOrange),
        ("Purple", PlatformColor.systemPurple),
    ]

    private let selectionColors: [(name: String, color: PlatformColor?)] = [
        ("Default", nil),
        ("Blue", PlatformColor.systemBlue.withAlphaComponent(0.2)),
        ("Green", PlatformColor.systemGreen.withAlphaComponent(0.2)),
        ("Yellow", PlatformColor.systemYellow.withAlphaComponent(0.3)),
        ("Orange", PlatformColor.systemOrange.withAlphaComponent(0.2)),
        ("Pink", PlatformColor.systemPink.withAlphaComponent(0.2)),
    ]

    var body: some View {
        #if os(tvOS)
            tvOSContent
        #else
            mainContent
        #endif
    }

    #if os(tvOS)
        var tvOSContent: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 48) {
                        sectionBasicText
                        sectionStyledText
                        sectionLinks
                        sectionAuditFixtures
                        sectionLongText
                        observableState
                    }
                    .padding(64)
                }
                .navigationTitle("Litext Demo")
            }
            .alert("Link Tapped", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(linkTapped?.absoluteString ?? "")
            }
        }
    #else
        var mainContent: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        sectionSimpleAPI
                        sectionBasicText
                        sectionStyledText
                        sectionLinks
                        sectionMixedContent
                        sectionAuditFixtures
                        sectionLongText
                        observableState
                    }
                    .padding()
                }
                #if os(iOS)
                .navigationTitle("Litext Demo")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "textformat.size")
                        }
                        .popover(isPresented: Binding(
                            get: { showSettings && horizontalSizeClass != .compact },
                            set: { showSettings = $0 }
                        )) {
                            settingsPopover
                        }
                    }
                }
                .sheet(isPresented: Binding(
                    get: { showSettings && horizontalSizeClass == .compact },
                    set: { showSettings = $0 }
                )) {
                    settingsPopover
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
                }
                #elseif os(visionOS) || targetEnvironment(macCatalyst)
                .navigationTitle("Litext Demo")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "textformat.size")
                        }
                        .popover(isPresented: $showSettings) {
                            settingsPopover
                        }
                    }
                }
                #elseif os(macOS)
                .navigationTitle("Litext Demo")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showSettings.toggle()
                        } label: {
                            Image(systemName: "textformat.size")
                        }
                        .popover(isPresented: $showSettings) {
                            settingsPopover
                        }
                    }
                }
                #endif
            }
            .alert("Link Tapped", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(linkTapped?.absoluteString ?? "")
            }
        }

        var settingsPopover: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Text Appearance")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Font Size: \(Int(fontSize))pt")
                        .font(.subheadline)
                    Slider(value: $fontSize, in: 10 ... 32, step: 1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Line Spacing: \(Int(lineSpacing))pt")
                        .font(.subheadline)
                    Slider(value: $lineSpacing, in: 0 ... 16, step: 1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Text Color")
                        .font(.subheadline)
                    Picker("Color", selection: $textColorIndex) {
                        ForEach(0 ..< textColors.count, id: \.self) { index in
                            Text(textColors[index].name).tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Selection Color")
                        .font(.subheadline)
                    Picker("Selection", selection: $selectionColorIndex) {
                        ForEach(0 ..< selectionColors.count, id: \.self) { index in
                            Text(selectionColors[index].name).tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Toggle("Selectable", isOn: $isSelectable)

                Button("Reset to Defaults") {
                    fontSize = 16
                    lineSpacing = 4
                    isSelectable = true
                    textColorIndex = 0
                    selectionColorIndex = 0
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(width: 400)
        }

        var sectionMixedContent: some View {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Mixed Content")

                LitextLabel(attributedString: mixedAttributedText())
                    .selectable(isSelectable)
                    .selectionBackgroundColor(currentSelectionColor)
                    .onTapLink { url in
                        recordLinkTap(url)
                    }
            }
        }
    #endif

    // MARK: - Shared Section Views

    var sectionSimpleAPI: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Simple API")

            // Simple string init (most concise)
            LitextLabel("Hello, Litext!")
                .selectable(isSelectable)
                .selectionBackgroundColor(currentSelectionColor)

            // String with custom attributes
            LitextLabel("Custom styled text", attributes: [
                .font: PlatformFont.boldSystemFont(ofSize: 18),
                .foregroundColor: PlatformColor.systemBlue,
            ])
            .selectable(isSelectable)
            .selectionBackgroundColor(currentSelectionColor)
        }
    }

    var sectionBasicText: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Basic Text")

            LitextLabel(attributedString: simpleAttributedText())
                .selectable(isSelectable)
                .selectionBackgroundColor(currentSelectionColor)
        }
    }

    var sectionStyledText: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Styled Text")

            LitextLabel(attributedString: styledAttributedText())
                .selectable(isSelectable)
                .selectionBackgroundColor(currentSelectionColor)
        }
    }

    var sectionLinks: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Links")

            LitextLabel(attributedString: linkAttributedText())
                .selectable(isSelectable)
                .selectionBackgroundColor(currentSelectionColor)
                .onTapLink { url in
                    recordLinkTap(url)
                }
        }
    }

    var sectionAuditFixtures: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Audit Fixtures")

            LitextLabel(attributedString: multiStyleLinkAttributedText())
                .selectable(isSelectable)
                .selectionBackgroundColor(currentSelectionColor)
                .onSelectionChange(recordSelection)
                .onTapLink { url in
                    recordLinkTap(url)
                }
                .accessibilityIdentifier("fixture.link.multistyle")

            LitextLabel(attributedString: inlineAttachmentText(linked: false))
                .selectable(isSelectable)
                .selectionBackgroundColor(currentSelectionColor)
                .onSelectionChange(recordSelection)
                .accessibilityIdentifier("fixture.attachment.inline")

            LitextLabel(attributedString: inlineAttachmentText(linked: true))
                .selectable(isSelectable)
                .selectionBackgroundColor(currentSelectionColor)
                .onSelectionChange(recordSelection)
                .onTapLink { url in
                    recordLinkTap(url)
                }
                .accessibilityIdentifier("fixture.attachment.linked")

            LitextLabel(attributedString: rtlBidiAttributedText())
                .selectable(isSelectable)
                .selectionBackgroundColor(currentSelectionColor)
                .onSelectionChange(recordSelection)
                .accessibilityIdentifier("fixture.rtl")

            LitextLabel(attributedString: lineDrawingAttributedText())
                .selectable(isSelectable)
                .selectionBackgroundColor(currentSelectionColor)
                .onSelectionChange(recordSelection)
                .accessibilityIdentifier("fixture.line-drawing")

            LitextLabel(attributedString: truncationAttributedText())
                .selectable(isSelectable)
                .selectionBackgroundColor(currentSelectionColor)
                .onSelectionChange(recordSelection)
                .frame(maxWidth: 240, alignment: .leading)
                .clipped()
                .accessibilityIdentifier("fixture.truncation")

            LitextLabel(attributedString: emptyAttributedText())
                .selectable(isSelectable)
                .selectionBackgroundColor(currentSelectionColor)
                .onSelectionChange(recordSelection)
                .accessibilityIdentifier("fixture.empty")
        }
    }

    var sectionLongText: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Long Selectable Text")

            LitextLabel(attributedString: longAttributedText())
                .selectable(isSelectable)
                .selectionBackgroundColor(currentSelectionColor)
                .onSelectionChange(recordSelection)
                .accessibilityIdentifier("fixture.long-text")
        }
    }

    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
    }

    var observableState: some View {
        VStack {
            Text(lastTappedURL.isEmpty ? "none" : lastTappedURL)
                .accessibilityIdentifier("state.lastTappedURL")
            Text(lastSelectedText.isEmpty ? "none" : lastSelectedText)
                .accessibilityIdentifier("state.selectedText")
        }
        .font(.caption2)
        .foregroundStyle(.clear)
        .frame(width: 1, height: 1)
        .accessibilityHidden(false)
    }

    func recordLinkTap(_ url: URL) {
        linkTapped = url
        lastTappedURL = url.absoluteString
        showAlert = true
    }

    func recordSelection(_ text: String?) {
        lastSelectedText = text ?? ""
    }
}

// MARK: - Sample Attributed Strings

extension ContentView {
    private var currentTextColor: PlatformColor {
        textColors[textColorIndex].color
    }

    private var currentSelectionColor: PlatformColor? {
        selectionColors[selectionColorIndex].color
    }

    private var currentFont: PlatformFont {
        PlatformFont.systemFont(ofSize: CGFloat(fontSize))
    }

    private var currentBoldFont: PlatformFont {
        PlatformFont.boldSystemFont(ofSize: CGFloat(fontSize))
    }

    private var currentItalicFont: PlatformFont {
        PlatformFont.italicSystemFont(ofSize: CGFloat(fontSize))
    }

    private var currentParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = CGFloat(lineSpacing)
        return style
    }

    func simpleAttributedText() -> NSAttributedString {
        let text = "Hello, Litext! This is a simple text rendered using LTXLabel with CoreText."
        return NSAttributedString(
            string: text,
            attributes: [
                .font: currentFont,
                .foregroundColor: currentTextColor,
                .paragraphStyle: currentParagraphStyle,
            ]
        )
    }

    func styledAttributedText() -> NSAttributedString {
        let result = NSMutableAttributedString()

        result.append(NSAttributedString(
            string: "This text has ",
            attributes: [
                .font: currentFont,
                .foregroundColor: currentTextColor,
                .paragraphStyle: currentParagraphStyle,
            ]
        ))

        result.append(NSAttributedString(
            string: "bold",
            attributes: [
                .font: currentBoldFont,
                .foregroundColor: currentTextColor,
                .paragraphStyle: currentParagraphStyle,
            ]
        ))

        result.append(NSAttributedString(
            string: ", ",
            attributes: [
                .font: currentFont,
                .foregroundColor: currentTextColor,
                .paragraphStyle: currentParagraphStyle,
            ]
        ))

        result.append(NSAttributedString(
            string: "italic",
            attributes: [
                .font: currentItalicFont,
                .foregroundColor: currentTextColor,
                .paragraphStyle: currentParagraphStyle,
            ]
        ))

        result.append(NSAttributedString(
            string: ", ",
            attributes: [
                .font: currentFont,
                .foregroundColor: currentTextColor,
                .paragraphStyle: currentParagraphStyle,
            ]
        ))

        result.append(NSAttributedString(
            string: "colored",
            attributes: [
                .font: currentFont,
                .foregroundColor: PlatformColor.systemRed,
                .paragraphStyle: currentParagraphStyle,
            ]
        ))

        result.append(NSAttributedString(
            string: ", and ",
            attributes: [
                .font: currentFont,
                .foregroundColor: currentTextColor,
                .paragraphStyle: currentParagraphStyle,
            ]
        ))

        result.append(NSAttributedString(
            string: "underlined",
            attributes: [
                .font: currentFont,
                .foregroundColor: currentTextColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .paragraphStyle: currentParagraphStyle,
            ]
        ))

        result.append(NSAttributedString(
            string: " styles.",
            attributes: [
                .font: currentFont,
                .foregroundColor: currentTextColor,
                .paragraphStyle: currentParagraphStyle,
            ]
        ))

        return result
    }

    func linkAttributedText() -> NSAttributedString {
        let result = NSMutableAttributedString()

        result.append(NSAttributedString(
            string: "Visit ",
            attributes: [
                .font: currentFont,
                .foregroundColor: currentTextColor,
                .paragraphStyle: currentParagraphStyle,
            ]
        ))

        result.append(NSAttributedString(
            string: "GitHub",
            attributes: [
                .font: currentFont,
                .foregroundColor: PlatformColor.link,
                .link: URL(string: "https://github.com")!,
                .paragraphStyle: currentParagraphStyle,
            ]
        ))

        result.append(NSAttributedString(
            string: " or ",
            attributes: [
                .font: currentFont,
                .foregroundColor: currentTextColor,
                .paragraphStyle: currentParagraphStyle,
            ]
        ))

        result.append(NSAttributedString(
            string: "Apple Developer",
            attributes: [
                .font: currentFont,
                .foregroundColor: PlatformColor.link,
                .link: URL(string: "https://developer.apple.com")!,
                .paragraphStyle: currentParagraphStyle,
            ]
        ))

        result.append(NSAttributedString(
            string: " for more information.",
            attributes: [
                .font: currentFont,
                .foregroundColor: currentTextColor,
                .paragraphStyle: currentParagraphStyle,
            ]
        ))

        return result
    }

    func mixedAttributedText() -> NSAttributedString {
        let result = NSMutableAttributedString()

        result.append(NSAttributedString(
            string: "Litext supports ",
            attributes: [
                .font: currentFont,
                .foregroundColor: currentTextColor,
                .paragraphStyle: currentParagraphStyle,
            ]
        ))

        result.append(NSAttributedString(
            string: "rich text",
            attributes: [
                .font: currentBoldFont,
                .foregroundColor: PlatformColor.systemBlue,
                .paragraphStyle: currentParagraphStyle,
            ]
        ))

        result.append(NSAttributedString(
            string: " with ",
            attributes: [
                .font: currentFont,
                .foregroundColor: currentTextColor,
                .paragraphStyle: currentParagraphStyle,
            ]
        ))

        result.append(NSAttributedString(
            string: "clickable links",
            attributes: [
                .font: currentFont,
                .foregroundColor: PlatformColor.link,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .link: URL(string: "https://example.com")!,
                .paragraphStyle: currentParagraphStyle,
            ]
        ))

        result.append(NSAttributedString(
            string: ", text selection, and high-performance CoreText rendering!",
            attributes: [
                .font: currentFont,
                .foregroundColor: currentTextColor,
                .paragraphStyle: currentParagraphStyle,
            ]
        ))

        return result
    }

    func longAttributedText() -> NSAttributedString {
        let text = """
        Litext is a high-performance text rendering framework built on CoreText. \
        It provides features like text selection, link handling, and custom attachments. \
        The framework is designed to work seamlessly across all Apple platforms including \
        iOS, macOS (both native AppKit and Mac Catalyst), tvOS, and visionOS.

        Try selecting this text! On iOS, you can use the selection handles to adjust your \
        selection. On macOS, click and drag to select text. Use Cmd+C to copy selected text \
        or Cmd+A to select all.

        Litext is perfect for displaying rich content like chat messages, articles, \
        documentation, and any other text-heavy interfaces where performance matters.
        """

        return NSAttributedString(
            string: text,
            attributes: [
                .font: currentFont,
                .foregroundColor: currentTextColor,
                .paragraphStyle: currentParagraphStyle,
            ]
        )
    }

    func multiStyleLinkAttributedText() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let url = URL(string: "https://example.com/multi-style")!

        result.append(baseString("Tap the "))
        result.append(NSAttributedString(
            string: "multi-style ",
            attributes: [
                .font: currentBoldFont,
                .foregroundColor: PlatformColor.systemBlue,
                .link: url,
                .paragraphStyle: currentParagraphStyle,
            ]
        ))
        result.append(NSAttributedString(
            string: "link",
            attributes: [
                .font: currentItalicFont,
                .foregroundColor: PlatformColor.systemPurple,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .link: url,
                .paragraphStyle: currentParagraphStyle,
            ]
        ))
        result.append(baseString(" to verify one region spans styled runs."))
        return result
    }

    func inlineAttachmentText(linked: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(baseString(linked ? "Linked attachment: " : "Inline attachment: "))

        let attachment = LTXAttachment()
        attachment.size = CGSize(width: linked ? 120 : 96, height: 28)
        attachment.view = makeAttachmentView(title: linked ? "LINKED VIEW" : "INLINE VIEW")

        let attachmentString = NSMutableAttributedString(string: LTXReplacementText)
        let attachmentRange = NSRange(location: 0, length: attachmentString.length)
        attachmentString.addAttribute(.ltxAttachment, value: attachment, range: attachmentRange)
        attachmentString.addAttribute(
            kCTRunDelegateAttributeName as NSAttributedString.Key,
            value: attachment.runDelegate,
            range: attachmentRange
        )
        if linked {
            attachmentString.addAttributes(
                [
                    .link: URL(string: "https://example.com/linked-attachment")!,
                    .foregroundColor: PlatformColor.link,
                ],
                range: attachmentRange
            )
        }

        result.append(attachmentString)
        result.append(baseString(linked ? " should show and open as a link." : " should align to the baseline."))
        return result
    }

    func rtlBidiAttributedText() -> NSAttributedString {
        NSAttributedString(
            string: "RTL / bidi: English שלום عربى 123 mixed direction hit testing.",
            attributes: [
                .font: currentFont,
                .foregroundColor: currentTextColor,
                .paragraphStyle: currentParagraphStyle,
            ]
        )
    }

    func lineDrawingAttributedText() -> NSAttributedString {
        let action = LTXLineDrawingAction { context, line, origin in
            var descent: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, &descent, nil))
            let underlineY = origin.y - descent - CGFloat(2)
            context.setStrokeColor(PlatformColor.systemGreen.cgColor)
            context.setLineWidth(1)
            context.move(to: CGPoint(x: origin.x, y: underlineY))
            context.addLine(to: CGPoint(x: origin.x + width, y: underlineY))
            context.strokePath()
        }

        return NSAttributedString(
            string: "Line drawing callback underlines this CoreText line.",
            attributes: [
                .font: currentFont,
                .foregroundColor: currentTextColor,
                .ltxLineDrawingCallback: action,
                .paragraphStyle: currentParagraphStyle,
            ]
        )
    }

    func truncationAttributedText() -> NSAttributedString {
        NSAttributedString(
            string: "This intentionally long single-line fixture is clipped by its SwiftUI frame to catch layout regressions.",
            attributes: [
                .font: currentFont,
                .foregroundColor: currentTextColor,
                .paragraphStyle: currentParagraphStyle,
            ]
        )
    }

    func emptyAttributedText() -> NSAttributedString {
        NSAttributedString(string: "", attributes: [
            .font: currentFont,
            .foregroundColor: currentTextColor,
        ])
    }

    private func baseString(_ string: String) -> NSAttributedString {
        NSAttributedString(
            string: string,
            attributes: [
                .font: currentFont,
                .foregroundColor: currentTextColor,
                .paragraphStyle: currentParagraphStyle,
            ]
        )
    }

    private func makeAttachmentView(title: String) -> LTXPlatformView {
        #if canImport(UIKit)
            let label = UILabel()
            label.text = title
            label.textAlignment = .center
            label.font = .boldSystemFont(ofSize: 11)
            label.textColor = .white
            label.backgroundColor = .systemBlue
            label.layer.cornerRadius = 6
            label.clipsToBounds = true
            label.isAccessibilityElement = true
            label.accessibilityIdentifier = title == "LINKED VIEW"
                ? "fixture.attachment.linked.view"
                : "fixture.attachment.inline.view"
            return label
        #elseif canImport(AppKit)
            let label = NSTextField(labelWithString: title)
            label.alignment = .center
            label.font = .boldSystemFont(ofSize: 11)
            label.textColor = .white
            label.wantsLayer = true
            label.layer?.backgroundColor = NSColor.systemBlue.cgColor
            label.layer?.cornerRadius = 6
            label.setAccessibilityIdentifier(title == "LINKED VIEW"
                ? "fixture.attachment.linked.view"
                : "fixture.attachment.inline.view")
            return label
        #endif
    }
}

// MARK: - Platform Extensions

#if canImport(UIKit)
// UIKit uses UIColor which already has .label and .link
#elseif canImport(AppKit)
    extension NSColor {
        static var label: NSColor {
            .labelColor
        }

        static var link: NSColor {
            .linkColor
        }
    }

    extension NSFont {
        static func italicSystemFont(ofSize size: CGFloat) -> NSFont {
            let systemFont = NSFont.systemFont(ofSize: size)
            let descriptor = systemFont.fontDescriptor.withSymbolicTraits(.italic)
            return NSFont(descriptor: descriptor, size: size) ?? systemFont
        }
    }
#endif

#Preview {
    ContentView()
}
