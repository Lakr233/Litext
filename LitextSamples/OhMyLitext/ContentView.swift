//
//  ContentView.swift
//  OhMyLitext
//
//  Created by Litext Team.
//

import Litext
import SwiftUI

struct ContentView: View {
    @State private var linkTapped: URL?
    @State private var showAlert = false
    @State private var showSettings = false

    // Appearance settings
    @State private var fontSize: Double = 16
    @State private var lineSpacing: Double = 4
    @State private var isSelectable: Bool = true
    @State private var textColorIndex: Int = 0

    private let textColors: [(name: String, color: PlatformColor)] = [
        ("Default", PlatformColor.label),
        ("Blue", PlatformColor.systemBlue),
        ("Green", PlatformColor.systemGreen),
        ("Orange", PlatformColor.systemOrange),
        ("Purple", PlatformColor.systemPurple),
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
                        sectionLongText
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
                        sectionBasicText
                        sectionStyledText
                        sectionLinks
                        sectionMixedContent
                        sectionLongText
                    }
                    .padding()
                }
                #if os(iOS) || os(visionOS) || targetEnvironment(macCatalyst)
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
                    .pickerStyle(.segmented)
                }

                Toggle("Selectable", isOn: $isSelectable)

                Button("Reset to Defaults") {
                    fontSize = 16
                    lineSpacing = 4
                    isSelectable = true
                    textColorIndex = 0
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(width: 400)
        }

        var sectionMixedContent: some View {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Mixed Content")

                LTXLabelView(
                    attributedText: mixedAttributedText(),
                    isSelectable: isSelectable
                ) { url in
                    linkTapped = url
                    showAlert = true
                }
            }
        }
    #endif

    // MARK: - Shared Section Views

    var sectionBasicText: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Basic Text")

            LTXLabelView(
                attributedText: simpleAttributedText(),
                isSelectable: isSelectable
            )
        }
    }

    var sectionStyledText: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Styled Text")

            LTXLabelView(
                attributedText: styledAttributedText(),
                isSelectable: isSelectable
            )
        }
    }

    var sectionLinks: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Links")

            LTXLabelView(
                attributedText: linkAttributedText(),
                isSelectable: isSelectable
            ) { url in
                linkTapped = url
                showAlert = true
            }
        }
    }

    var sectionLongText: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Long Selectable Text")

            LTXLabelView(
                attributedText: longAttributedText(),
                isSelectable: isSelectable
            )
        }
    }

    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Sample Attributed Strings

extension ContentView {
    private var currentTextColor: PlatformColor {
        textColors[textColorIndex].color
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
}

// MARK: - Platform Extensions

#if canImport(AppKit) && !canImport(UIKit)
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
