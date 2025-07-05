//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import AppKit
import Litext

final class ViewController: NSViewController {
    let scrollView = NSScrollView()
    let label = LTXLabel()
    let controlButton = NSButton(title: "Text Controls", target: nil, action: nil)

    var fontSize: CGFloat = 14
    var lineSpacing: CGFloat = 4
    var paragraphSpacing: CGFloat = 10
    var alignment: NSTextAlignment = .left
    var textColor: NSColor = .textColor
    var fontWeight: NSFont.Weight = .regular
    var fontStyle: FontStyle = .normal
    var backgroundColor: NSColor = .clear

    enum FontStyle {
        case normal
        case italic
        case boldItalic
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupLayout()
        updateAttributedText()

        label.isSelectable = true

        controlButton.target = self
        controlButton.action = #selector(showControlPanel)
    }

    func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        view.addSubview(scrollView)

        label.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = label

        controlButton.translatesAutoresizingMaskIntoConstraints = false
        controlButton.bezelStyle = .rounded
        controlButton.controlSize = .large
        view.addSubview(controlButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -50),

            controlButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            controlButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            controlButton.widthAnchor.constraint(equalToConstant: 150),
            controlButton.heightAnchor.constraint(equalToConstant: 30),
        ])

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: scrollView.topAnchor),
            label.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
        ])
    }

    override func viewWillLayout() {
        super.viewWillLayout()
    }

    @objc func showControlPanel() {
        let controlPanelVC = ControlPanelViewController()
        controlPanelVC.delegate = self

        controlPanelVC.fontSize = fontSize
        controlPanelVC.lineSpacing = lineSpacing
        controlPanelVC.paragraphSpacing = paragraphSpacing
        controlPanelVC.alignment = alignment
        controlPanelVC.textColor = textColor
        controlPanelVC.fontWeight = fontWeight
        controlPanelVC.fontStyle = fontStyle
        controlPanelVC.backgroundColor = backgroundColor

        presentAsSheet(controlPanelVC)
    }

    func updateAttributedText() {
        let attributedString = NSMutableAttributedString()

        attributedString.append(
            NSAttributedString(
                string: "Hello, Litext!\n\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize + 2, weight: .bold),
                    .foregroundColor: textColor,
                ]
            )
        )

        attributedString.append(
            NSAttributedString(
                string: "This is a rich text label supporting ",
                attributes: [
                    .font: createFont(),
                    .foregroundColor: textColor,
                ]
            )
        )

        attributedString.append(
            NSAttributedString(
                string: "clickable links",
                attributes: [
                    .font: createFont(),
                    .link: URL(string: "https://example.com")!,
                    .foregroundColor: NSColor.linkColor,
                ]
            )
        )

        attributedString.append(
            NSAttributedString(
                string: ", ",
                attributes: [
                    .font: createFont(),
                    .foregroundColor: textColor,
                ]
            )
        )

        attributedString.append(
            NSAttributedString(
                string: "underlined text",
                attributes: [
                    .font: createFont(),
                    .foregroundColor: textColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: NSColor.systemBlue,
                ]
            )
        )

        attributedString.append(
            NSAttributedString(
                string: ", ",
                attributes: [
                    .font: createFont(),
                    .foregroundColor: textColor,
                ]
            )
        )

        attributedString.append(
            NSAttributedString(
                string: "strikethrough",
                attributes: [
                    .font: createFont(),
                    .foregroundColor: textColor,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: NSColor.systemRed,
                ]
            )
        )

        attributedString.append(
            NSAttributedString(
                string: " and embedded views:\n\n",
                attributes: [
                    .font: createFont(),
                    .foregroundColor: textColor,
                ]
            )
        )

        let attachment: LTXAttachment = .init()
        let switchView = NSSwitch()
        attachment.view = switchView
        attachment.size = switchView.intrinsicContentSize

        attributedString.append(
            NSAttributedString(
                string: LTXReplacementText,
                attributes: [
                    LTXAttachmentAttributeName: attachment,
                    kCTRunDelegateAttributeName as NSAttributedString.Key: attachment.runDelegate,
                ]
            )
        )

        attributedString.append(
            NSAttributedString(
                string: " Toggle Switch",
                attributes: [
                    .font: createFont(),
                    .foregroundColor: textColor,
                ]
            )
        )

        let buttonAttachment = LTXAttachment()
        let buttonView = NSButton(title: "Click Me", target: nil, action: nil)
        buttonView.bezelStyle = .rounded
        buttonView.controlSize = .small
        buttonAttachment.view = buttonView
        buttonAttachment.size = buttonView.intrinsicContentSize

        attributedString.append(
            NSAttributedString(
                string: "\n\n",
                attributes: [
                    .font: createFont(),
                    .foregroundColor: textColor,
                ]
            )
        )

        attributedString.append(
            NSAttributedString(
                string: LTXReplacementText,
                attributes: [
                    LTXAttachmentAttributeName: buttonAttachment,
                    kCTRunDelegateAttributeName as NSAttributedString.Key: buttonAttachment.runDelegate,
                ]
            )
        )

        attributedString.append(
            NSAttributedString(
                string: "\n\n组合样式：",
                attributes: [
                    .font: createFont(),
                    .foregroundColor: textColor,
                ]
            )
        )

        attributedString.append(
            NSAttributedString(
                string: "粗体带下划线",
                attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: NSColor.systemPurple,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ]
            )
        )

        attributedString.append(
            NSAttributedString(
                string: " 和 ",
                attributes: [
                    .font: createFont(),
                    .foregroundColor: textColor,
                ]
            )
        )

        attributedString.append(
            NSAttributedString(
                string: "高亮背景文本",
                attributes: [
                    .font: createFont(),
                    .foregroundColor: NSColor.black,
                    .backgroundColor: NSColor.systemYellow,
                ]
            )
        )

        attributedString.append(
            NSAttributedString(
                string: "\n\n中文测试，那只敏捷的棕毛狐狸🦊跳上了那只懒狗🐶。",
                attributes: [
                    .font: createFont(),
                    .foregroundColor: textColor,
                ]
            )
        )

        attributedString.append(
            NSAttributedString(
                string: "\n\n这是一段被删除的文字，",
                attributes: [
                    .font: createFont(),
                    .foregroundColor: NSColor.systemGray,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                ]
            )
        )

        attributedString.append(
            NSAttributedString(
                string: "这是新文字。",
                attributes: [
                    .font: createFont(),
                    .foregroundColor: NSColor.systemGreen,
                ]
            )
        )

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.paragraphSpacing = paragraphSpacing
        paragraphStyle.alignment = alignment

        attributedString.addAttributes(
            [.paragraphStyle: paragraphStyle],
            range: NSRange(location: 0, length: attributedString.length)
        )

        label.backgroundColor = backgroundColor
        label.attributedText = attributedString
        label.delegate = self
    }

    private func createFont() -> NSFont {
        var font: NSFont

        switch fontStyle {
        case .normal:
            font = NSFont.systemFont(ofSize: fontSize, weight: fontWeight)
        case .italic:
            let descriptor = NSFontDescriptor(name: "HelveticaNeue-Italic", size: fontSize)
            font = NSFont(descriptor: descriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        case .boldItalic:
            let descriptor = NSFontDescriptor(name: "HelveticaNeue-BoldItalic", size: fontSize)
            font = NSFont(descriptor: descriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        }

        return font
    }

    func handleLinkTap(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

extension ViewController: LTXLabelDelegate {
    func ltxLabelDidTapOnHighlightContent(_: Litext.LTXLabel, region: Litext.LTXHighlightRegion?, location _: CGPoint) {
        if let url = region?.attributes[.link] as? URL {
            handleLinkTap(url)
        }
    }

    func ltxLabelSelectionDidChange(_: Litext.LTXLabel, selection: NSRange?) {
        print(String(describing: selection))
    }

    func ltxLabelDetectedUserEventMovingAtLocation(_ ltxLabel: LTXLabel, location: CGPoint) {
        print(#function, ltxLabel, location)
    }
}

// MARK: - ControlPanelDelegate

extension ViewController: ControlPanelDelegate {
    func controlPanel(_: ControlPanelViewController, didChangeFontSize fontSize: CGFloat) {
        self.fontSize = fontSize
        updateAttributedText()
    }

    func controlPanel(_: ControlPanelViewController, didChangeFontWeight fontWeight: NSFont.Weight) {
        self.fontWeight = fontWeight
        updateAttributedText()
    }

    func controlPanel(_: ControlPanelViewController, didChangeFontStyle fontStyle: FontStyle) {
        self.fontStyle = fontStyle
        updateAttributedText()
    }

    func controlPanel(_: ControlPanelViewController, didChangeAlignment alignment: NSTextAlignment) {
        self.alignment = alignment
        updateAttributedText()
    }

    func controlPanel(_: ControlPanelViewController, didChangeLineSpacing lineSpacing: CGFloat) {
        self.lineSpacing = lineSpacing
        updateAttributedText()
    }

    func controlPanel(_: ControlPanelViewController, didChangeParagraphSpacing paragraphSpacing: CGFloat) {
        self.paragraphSpacing = paragraphSpacing
        updateAttributedText()
    }

    func controlPanel(_: ControlPanelViewController, didChangeTextColor textColor: NSColor) {
        self.textColor = textColor
        updateAttributedText()
    }

    func controlPanel(_: ControlPanelViewController, didChangeBackgroundColor backgroundColor: NSColor?) {
        self.backgroundColor = backgroundColor ?? .clear
        updateAttributedText()
    }
}
