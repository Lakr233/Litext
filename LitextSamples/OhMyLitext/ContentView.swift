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

    var body: some View {
        #if os(watchOS)
            watchOSContent
        #else
            mainContent
        #endif
    }

    #if os(watchOS)
        var watchOSContent: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Litext Demo")
                        .font(.headline)

                    LTXLabelView(
                        attributedText: Self.simpleAttributedText(),
                        isSelectable: false
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    LTXLabelView(
                        attributedText: Self.linkAttributedText(),
                        isSelectable: false
                    ) { url in
                        linkTapped = url
                        showAlert = true
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .alert("Link Tapped", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(linkTapped?.absoluteString ?? "")
            }
        }
    #endif

    #if !os(watchOS)
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
                    .frame(maxWidth: 600, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
                #if os(iOS) || os(visionOS) || targetEnvironment(macCatalyst)
                    .navigationTitle("Litext Demo")
                    .navigationBarTitleDisplayMode(.large)
                #elseif os(macOS)
                    .navigationTitle("Litext Demo")
                #elseif os(tvOS)
                    .navigationTitle("Litext Demo")
                #endif
            }
            .alert("Link Tapped", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(linkTapped?.absoluteString ?? "")
            }
        }

        var sectionBasicText: some View {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Basic Text")

                LTXLabelView(
                    attributedText: Self.simpleAttributedText(),
                    isSelectable: true
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        var sectionStyledText: some View {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Styled Text")

                LTXLabelView(
                    attributedText: Self.styledAttributedText(),
                    isSelectable: true
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        var sectionLinks: some View {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Links")

                LTXLabelView(
                    attributedText: Self.linkAttributedText(),
                    isSelectable: true
                ) { url in
                    linkTapped = url
                    showAlert = true
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        var sectionMixedContent: some View {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Mixed Content")

                LTXLabelView(
                    attributedText: Self.mixedAttributedText(),
                    isSelectable: true
                ) { url in
                    linkTapped = url
                    showAlert = true
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        var sectionLongText: some View {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Long Selectable Text")

                LTXLabelView(
                    attributedText: Self.longAttributedText(),
                    isSelectable: true
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        func sectionHeader(_ title: String) -> some View {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    #endif
}

// MARK: - Sample Attributed Strings

extension ContentView {
    static func simpleAttributedText() -> NSAttributedString {
        let text = "Hello, Litext! This is a simple text rendered using LTXLabel with CoreText."
        return NSAttributedString(
            string: text,
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .foregroundColor: PlatformColor.label,
            ]
        )
    }

    static func styledAttributedText() -> NSAttributedString {
        let result = NSMutableAttributedString()

        let normal = NSAttributedString(
            string: "This text has ",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .foregroundColor: PlatformColor.label,
            ]
        )
        result.append(normal)

        let bold = NSAttributedString(
            string: "bold",
            attributes: [
                .font: PlatformFont.boldSystemFont(ofSize: 16),
                .foregroundColor: PlatformColor.label,
            ]
        )
        result.append(bold)

        let normal2 = NSAttributedString(
            string: ", ",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .foregroundColor: PlatformColor.label,
            ]
        )
        result.append(normal2)

        let italic = NSAttributedString(
            string: "italic",
            attributes: [
                .font: PlatformFont.italicSystemFont(ofSize: 16),
                .foregroundColor: PlatformColor.label,
            ]
        )
        result.append(italic)

        let normal3 = NSAttributedString(
            string: ", ",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .foregroundColor: PlatformColor.label,
            ]
        )
        result.append(normal3)

        let colored = NSAttributedString(
            string: "colored",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .foregroundColor: PlatformColor.systemRed,
            ]
        )
        result.append(colored)

        let normal4 = NSAttributedString(
            string: ", and ",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .foregroundColor: PlatformColor.label,
            ]
        )
        result.append(normal4)

        let underlined = NSAttributedString(
            string: "underlined",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .foregroundColor: PlatformColor.label,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
        )
        result.append(underlined)

        let normal5 = NSAttributedString(
            string: " styles.",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .foregroundColor: PlatformColor.label,
            ]
        )
        result.append(normal5)

        return result
    }

    static func linkAttributedText() -> NSAttributedString {
        let result = NSMutableAttributedString()

        let prefix = NSAttributedString(
            string: "Visit ",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .foregroundColor: PlatformColor.label,
            ]
        )
        result.append(prefix)

        let link = NSAttributedString(
            string: "GitHub",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .foregroundColor: PlatformColor.link,
                .link: URL(string: "https://github.com")!,
            ]
        )
        result.append(link)

        let middle = NSAttributedString(
            string: " or ",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .foregroundColor: PlatformColor.label,
            ]
        )
        result.append(middle)

        let link2 = NSAttributedString(
            string: "Apple Developer",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .foregroundColor: PlatformColor.link,
                .link: URL(string: "https://developer.apple.com")!,
            ]
        )
        result.append(link2)

        let suffix = NSAttributedString(
            string: " for more information.",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .foregroundColor: PlatformColor.label,
            ]
        )
        result.append(suffix)

        return result
    }

    static func mixedAttributedText() -> NSAttributedString {
        let result = NSMutableAttributedString()

        let intro = NSAttributedString(
            string: "Litext supports ",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .foregroundColor: PlatformColor.label,
            ]
        )
        result.append(intro)

        let bold = NSAttributedString(
            string: "rich text",
            attributes: [
                .font: PlatformFont.boldSystemFont(ofSize: 16),
                .foregroundColor: PlatformColor.systemBlue,
            ]
        )
        result.append(bold)

        let middle = NSAttributedString(
            string: " with ",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .foregroundColor: PlatformColor.label,
            ]
        )
        result.append(middle)

        let link = NSAttributedString(
            string: "clickable links",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .foregroundColor: PlatformColor.link,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .link: URL(string: "https://example.com")!,
            ]
        )
        result.append(link)

        let ending = NSAttributedString(
            string: ", text selection, and high-performance CoreText rendering!",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .foregroundColor: PlatformColor.label,
            ]
        )
        result.append(ending)

        return result
    }

    static func longAttributedText() -> NSAttributedString {
        let text = """
        Litext is a high-performance text rendering framework built on CoreText. \
        It provides features like text selection, link handling, and custom attachments. \
        The framework is designed to work seamlessly across all Apple platforms including \
        iOS, macOS (both native AppKit and Mac Catalyst), tvOS, watchOS, and visionOS.

        Try selecting this text! On iOS, you can use the selection handles to adjust your \
        selection. On macOS, click and drag to select text. Use Cmd+C to copy selected text \
        or Cmd+A to select all.

        Litext is perfect for displaying rich content like chat messages, articles, \
        documentation, and any other text-heavy interfaces where performance matters.
        """

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4

        return NSAttributedString(
            string: text,
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 15),
                .foregroundColor: PlatformColor.label,
                .paragraphStyle: paragraphStyle,
            ]
        )
    }
}

// MARK: - Platform Extensions

#if canImport(AppKit) && !canImport(UIKit)
    extension NSColor {
        static var label: NSColor { .labelColor }
        static var link: NSColor { .linkColor }
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
