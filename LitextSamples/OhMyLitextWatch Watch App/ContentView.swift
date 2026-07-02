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
                TextLabel(attributedString: basicStyledText())

                sectionLabel("Code Block")
                TextLabel(attributedString: codeBlockText())

                sectionLabel("Mixed Rich Text")
                TextLabel(attributedString: mixedText())

                sectionLabel("Linked Attachment")
                TextLabel(attributedString: linkedAttachmentText())
                    .accessibilityIdentifier("fixture.attachment.linked")

                sectionLabel("RTL / Bidi")
                TextLabel(attributedString: rtlBidiText())
                    .accessibilityIdentifier("fixture.rtl")

                sectionLabel("Line Drawing")
                TextLabel(attributedString: lineDrawingText())
                    .accessibilityIdentifier("fixture.line-drawing")

                sectionLabel("Empty")
                TextLabel(attributedString: NSAttributedString(string: ""))
                    .accessibilityIdentifier("fixture.empty")
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

    /// Code block using TextLabel.Attachment + AnyView
    func codeBlockText() -> NSAttributedString {
        let s = NSMutableAttributedString()
        let orange = UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 1)
        s.append(attr("Call ", font: body14, color: .white))
        s.append(attr("TextLabel(", font: mono12, color: orange))
        s.append(attr("attributedString:", font: mono12, color: .white))
        s.append(attr(")\n", font: mono12, color: orange))

        // Inline code block as attachment
        let codeText = "TextLabel(attributedString: str)"
        let blockWidth: CGFloat = WKInterfaceDevice.current().screenBounds.width - 20
        let codeFont = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let lineCount = CGFloat(codeText.components(separatedBy: "\n").count)
        let blockHeight = ceil(codeFont.lineHeight * lineCount + 12 + 6) // 6pt padding top + bottom + 6pt top gap

        let attachment = TextLabel.Attachment()
        attachment.size = CGSize(width: blockWidth, height: blockHeight)
        attachment.swiftUIView = AnyView(
            CodeBlockView(code: codeText)
                .frame(width: blockWidth, height: blockHeight)
        )

        s.append(attachment.attributedString())
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

    func linkedAttachmentText() -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(attr("Tap-style linked view: ", font: body14, color: .white))

        let attachment = TextLabel.Attachment()
        attachment.size = CGSize(width: 120, height: 28)
        attachment.swiftUIView = AnyView(
            Text("LINKED VIEW")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 120, height: 28)
                .background(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        )

        result.append(attachment.attributedString(attributes: [
            .link: URL(string: "https://example.com/watch-linked-attachment")!,
        ]))
        return result
    }

    func rtlBidiText() -> NSAttributedString {
        attr("RTL / bidi: English שלום عربى 123 mixed.", font: body14, color: .white)
    }

    func lineDrawingText() -> NSAttributedString {
        let action = TextLabel.LineDrawingAction { context, line, origin in
            var descent: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, &descent, nil))
            let underlineY = origin.y - descent - CGFloat(2)
            context.setStrokeColor(UIColor.green.cgColor)
            context.setLineWidth(1)
            context.move(to: CGPoint(x: origin.x, y: underlineY))
            context.addLine(to: CGPoint(x: origin.x + width, y: underlineY))
            context.strokePath()
        }
        let text = NSMutableAttributedString(attributedString: attr("Line callback underline.", font: body14, color: .white))
        text.addAttribute(.litextLineDrawingAction, value: action, range: NSRange(location: 0, length: text.length))
        return text
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
