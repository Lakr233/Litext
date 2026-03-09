//
//  ContentView.swift
//  OhMyLitextWatch Watch App
//

import CoreText
import Litext
import SwiftUI

struct ContentView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Basic Styled Text")
                LitextLabel(attributedString: basicStyledText())

                sectionLabel("Code Block")
                LitextLabel(attributedString: codeBlockText())

                sectionLabel("Mixed Rich Text")
                LitextLabel(attributedString: mixedText())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .navigationTitle("Litext")
    }

    func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Sample Attributed Strings

extension ContentView {
    private var body14: UIFont {
        UIFont.systemFont(ofSize: 14)
    }

    private var bold14: UIFont {
        UIFont.boldSystemFont(ofSize: 14)
    }

    private var mono12: UIFont {
        UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    }

    private var white: UIColor {
        .white
    }

    /// Basic styled text: bold, italic, colored, underline
    func basicStyledText() -> NSAttributedString {
        let s = NSMutableAttributedString()
        s.append(attr("Litext ", font: bold14, color: .white))
        s.append(attr("renders CoreText on Apple Watch.\n", font: body14, color: .white))
        s.append(attr("Bold • ", font: bold14, color: .white))
        s.append(attr("Colored • ", font: body14, color: UIColor(red: 0.2, green: 0.6, blue: 1, alpha: 1)))
        s.append(attr("Underlined", font: body14, color: UIColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1), underline: true))
        return s
    }

    /// Code block using LTXAttachment + AnyView
    func codeBlockText() -> NSAttributedString {
        let s = NSMutableAttributedString()
        let orange = UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 1)
        s.append(attr("Call ", font: body14, color: .white))
        s.append(attr("LitextLabel(", font: mono12, color: orange))
        s.append(attr("attributedString:", font: mono12, color: .white))
        s.append(attr(")\n", font: mono12, color: orange))

        // Inline code block as attachment
        let codeText = "let label = LitextLabel()\nlabel.attributedText = str"
        let blockWidth: CGFloat = WKInterfaceDevice.current().screenBounds.width - 20
        let codeFont = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let lineCount = CGFloat(codeText.components(separatedBy: "\n").count)
        let blockHeight = ceil(codeFont.lineHeight * lineCount + 12 + 6) // 6pt padding top + bottom + 6pt top gap

        let attachment = LTXAttachment()
        attachment.size = CGSize(width: blockWidth, height: blockHeight)
        attachment.swiftUIView = AnyView(
            CodeBlockView(code: codeText)
                .frame(width: blockWidth, height: blockHeight)
        )

        let attachStr = NSMutableAttributedString(string: LTXReplacementText)
        attachStr.addAttribute(.ltxAttachment, value: attachment, range: NSRange(location: 0, length: 1))
        let runDelegate = attachment.runDelegate
        attachStr.addAttribute(
            kCTRunDelegateAttributeName as NSAttributedString.Key,
            value: runDelegate,
            range: NSRange(location: 0, length: 1)
        )
        s.append(attachStr)
        return s
    }

    // Mixed: normal + bold + link-styled
    func mixedText() -> NSAttributedString {
        let s = NSMutableAttributedString()
        let yellow = UIColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        let pink = UIColor(red: 1, green: 0.4, blue: 0.7, alpha: 1)
        s.append(attr("Litext supports ", font: body14, color: .white))
        s.append(attr("rich text", font: bold14, color: yellow))
        s.append(attr(" rendering with full CoreText pipeline — ", font: body14, color: .white))
        s.append(attr("bold", font: bold14, color: .white))
        s.append(attr(", ", font: body14, color: .white))
        s.append(attr("colors", font: body14, color: pink))
        s.append(attr(", attachments, and more.", font: body14, color: .white))
        return s
    }

    private func attr(
        _ string: String,
        font: UIFont,
        color: UIColor,
        underline: Bool = false
    ) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        if underline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return NSAttributedString(string: string, attributes: attrs)
    }
}

// MARK: - Code Block View

private struct CodeBlockView: View {
    let code: String

    var body: some View {
        Text(code)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.green)
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.top, 6)
    }
}

#Preview {
    ContentView()
}
