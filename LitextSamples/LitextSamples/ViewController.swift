//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import Litext
import SafariServices
import UIKit

class ViewController: UIViewController {
    let scrollView = UIScrollView()
    let contentView = UIView()
    let label = LTXLabel()
    let controlButton = UIButton(type: .system)
    
    private var contentHeightConstraint: NSLayoutConstraint?

    var fontSize: CGFloat = 16
    var lineSpacing: CGFloat = 6
    var paragraphSpacing: CGFloat = 10
    var alignment: NSTextAlignment = .left
    var textColor: UIColor = .label
    var fontWeight: UIFont.Weight = .regular
    var fontStyle: FontStyle = .normal
    var backgroundColor: UIColor = .clear

    enum FontStyle {
        case normal
        case italic
        case boldItalic
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Litext Demo"
        view.backgroundColor = .systemBackground

        setupLayout()
        updateAttributedText()
    }

    func setupLayout() {
        // Setup scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true
        view.addSubview(scrollView)

        // Setup content view
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        // Setup label
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = backgroundColor
        contentView.addSubview(label)

        // Setup control button
        controlButton.translatesAutoresizingMaskIntoConstraints = false
        controlButton.setTitle("Text Controls", for: .normal)
        controlButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        controlButton.backgroundColor = .systemBlue
        controlButton.setTitleColor(.white, for: .normal)
        controlButton.layer.cornerRadius = 12
        controlButton.addTarget(self, action: #selector(showControlPanel), for: .touchUpInside)
        view.addSubview(controlButton)

        // Layout constraints
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),

            controlButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            controlButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            controlButton.widthAnchor.constraint(equalToConstant: 150),
            controlButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let margins = view.layoutMargins
        label.preferredMaxLayoutWidth = view.bounds.width - margins.left - margins.right - 40

        let contentHeight = max(
            label.intrinsicContentSize.height + 200,
            scrollView.bounds.height
        )
        
        if let existingConstraint = contentHeightConstraint {
            existingConstraint.constant = contentHeight
        } else {
            contentHeightConstraint = contentView.heightAnchor.constraint(equalToConstant: contentHeight)
            contentHeightConstraint?.priority = .required
            contentHeightConstraint?.isActive = true
        }
    }

    @objc func showControlPanel() {
        let controlPanelVC = ControlPanelViewController()
        controlPanelVC.isModalInPresentation = false

        controlPanelVC.delegate = self

        controlPanelVC.fontSize = fontSize
        controlPanelVC.lineSpacing = lineSpacing
        controlPanelVC.paragraphSpacing = paragraphSpacing
        controlPanelVC.alignment = alignment
        controlPanelVC.textColor = textColor
        controlPanelVC.fontWeight = fontWeight
        controlPanelVC.fontStyle = fontStyle
        controlPanelVC.backgroundColor = backgroundColor

        if let sheet = controlPanelVC.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }

        present(controlPanelVC, animated: true)
    }

    func updateAttributedText() {
        let attributedString = NSMutableAttributedString()

        attributedString.append(
            NSAttributedString(
                string: "Hello, Litext!\n\n",
                attributes: [
                    .font: UIFont.systemFont(ofSize: fontSize + 2, weight: .bold),
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
                    .foregroundColor: UIColor.systemBlue,
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
                    .underlineColor: UIColor.systemBlue,
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
                    .strikethroughColor: UIColor.systemRed,
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

        let attachment = LTXAttachment(viewProvider: LTXAttachmentViewProviderSwitch())

        attributedString.append(
            NSAttributedString(
                string: LTXReplacementText,
                attributes: [ LTXAttachmentAttributeName: attachment, ]
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

        let buttonAttachment = LTXAttachment(viewProvider: LTXAttachmentViewProviderButton(title: "Hello World"))

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
                attributes: [ LTXAttachmentAttributeName: buttonAttachment ]
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
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: UIColor.systemPurple,
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
                    .foregroundColor: UIColor.black,
                    .backgroundColor: UIColor.systemYellow,
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
                    .foregroundColor: UIColor.systemGray,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                ]
            )
        )

        attributedString.append(
            NSAttributedString(
                string: "这是新文字。",
                attributes: [
                    .font: createFont(),
                    .foregroundColor: UIColor.systemGreen,
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
        label.isSelectable = true

        label.attributedText = attributedString
        label.delegate = self
    }

    private func createFont() -> UIFont {
        var font: UIFont

        switch fontStyle {
        case .normal:
            font = UIFont.systemFont(ofSize: fontSize, weight: fontWeight)
        case .italic:
            let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
                .withSymbolicTraits(.traitItalic)!
            font = UIFont(descriptor: descriptor, size: fontSize)
        case .boldItalic:
            let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
                .withSymbolicTraits([.traitItalic, .traitBold])!
            font = UIFont(descriptor: descriptor, size: fontSize)
        }

        return font
    }

    func handleLinkTap(_ url: URL) {
        let safariVC = SFSafariViewController(url: url)
        present(safariVC, animated: true)
    }

    func updateTextAttributesForStyleChange() {
        updateAttributedText()
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

    func controlPanel(_: ControlPanelViewController, didChangeFontWeight fontWeight: UIFont.Weight) {
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

    func controlPanel(_: ControlPanelViewController, didChangeTextColor textColor: UIColor) {
        self.textColor = textColor
        updateAttributedText()
    }

    func controlPanel(_: ControlPanelViewController, didChangeBackgroundColor backgroundColor: UIColor?) {
        self.backgroundColor = backgroundColor ?? .clear
        updateAttributedText()
    }
}
