//
//  Created for LitextSampleMac.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import AppKit

protocol ControlPanelDelegate: AnyObject {
    func controlPanel(_ controlPanel: ControlPanelViewController, didChangeFontSize fontSize: CGFloat)
    func controlPanel(_ controlPanel: ControlPanelViewController, didChangeFontWeight fontWeight: NSFont.Weight)
    func controlPanel(_ controlPanel: ControlPanelViewController, didChangeFontStyle fontStyle: ViewController.FontStyle)
    func controlPanel(_ controlPanel: ControlPanelViewController, didChangeAlignment alignment: NSTextAlignment)
    func controlPanel(_ controlPanel: ControlPanelViewController, didChangeLineSpacing lineSpacing: CGFloat)
    func controlPanel(_ controlPanel: ControlPanelViewController, didChangeParagraphSpacing paragraphSpacing: CGFloat)
    func controlPanel(_ controlPanel: ControlPanelViewController, didChangeTextColor textColor: NSColor)
    func controlPanel(_ controlPanel: ControlPanelViewController, didChangeBackgroundColor backgroundColor: NSColor?)
}

class ControlPanelViewController: NSViewController {
    private let stackView = NSStackView()
    private let closeButton = NSButton(title: "关闭", target: nil, action: nil)

    private var fontSizeValueLabel: NSTextField!
    private var lineSpacingValueLabel: NSTextField!
    private var paragraphSpacingValueLabel: NSTextField!

    var fontSize: CGFloat = 14
    var lineSpacing: CGFloat = 4
    var paragraphSpacing: CGFloat = 10
    var alignment: NSTextAlignment = .left
    var textColor: NSColor = .textColor
    var fontWeight: NSFont.Weight = .regular
    var fontStyle: ViewController.FontStyle = .normal
    var backgroundColor: NSColor? = nil

    weak var delegate: ControlPanelDelegate?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        preferredContentSize = NSSize(width: 500, height: 500)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Text Controls"

        if let window = view.window {
            window.minSize = NSSize(width: 200, height: 200)
        }

        setupStackView()
        setupCloseButton()
        setupFontControls()
        setupParagraphControls()
        setupColorControls()
    }

    private func setupStackView() {
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.spacing = 20
        stackView.alignment = .leading
        stackView.distribution = .fill
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -60), // 为关闭按钮留出空间
        ])
    }

    private func setupCloseButton() {
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .rounded
        closeButton.controlSize = .large
        closeButton.target = self
        closeButton.action = #selector(closePanel)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            closeButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 100),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    // MARK: - Font Controls

    private func setupFontControls() {
        let fontSection = createSectionHeader("Font")
        stackView.addArrangedSubview(fontSection)

        // Font Size Control
        let sizeRow = NSStackView()
        sizeRow.orientation = .horizontal
        sizeRow.spacing = 10

        let sizeLabel = NSTextField(labelWithString: "Size:")
        let sizeSlider = NSSlider(value: Double(fontSize), minValue: 10, maxValue: 24, target: self, action: #selector(fontSizeChanged(_:)))
        fontSizeValueLabel = NSTextField(labelWithString: "\(Int(fontSize))pt")

        sizeRow.addArrangedSubview(sizeLabel)
        sizeRow.addArrangedSubview(sizeSlider)
        sizeRow.addArrangedSubview(fontSizeValueLabel)
        stackView.addArrangedSubview(sizeRow)

        // Font Weight Control
        let weightRow = NSStackView()
        weightRow.orientation = .horizontal
        weightRow.spacing = 10

        let weightLabel = NSTextField(labelWithString: "Weight:")
        let weightPopup = NSPopUpButton(frame: .zero, pullsDown: false)

        let weights: [(String, NSFont.Weight)] = [
            ("Regular", .regular),
            ("Medium", .medium),
            ("Semibold", .semibold),
            ("Bold", .bold),
        ]

        for (index, (name, weight)) in weights.enumerated() {
            weightPopup.addItem(withTitle: name)
            if weight == fontWeight {
                weightPopup.selectItem(at: index)
            }
        }

        weightPopup.target = self
        weightPopup.action = #selector(fontWeightChanged(_:))

        weightRow.addArrangedSubview(weightLabel)
        weightRow.addArrangedSubview(weightPopup)
        stackView.addArrangedSubview(weightRow)

        // Font Style Control
        let styleRow = NSStackView()
        styleRow.orientation = .horizontal
        styleRow.spacing = 10

        let styleLabel = NSTextField(labelWithString: "Style:")
        let stylePopup = NSPopUpButton(frame: .zero, pullsDown: false)

        let styles = ["Normal", "Italic", "Bold Italic"]
        stylePopup.addItems(withTitles: styles)
        stylePopup.selectItem(at: fontStyle.rawValue)
        stylePopup.target = self
        stylePopup.action = #selector(fontStyleChanged(_:))

        styleRow.addArrangedSubview(styleLabel)
        styleRow.addArrangedSubview(stylePopup)
        stackView.addArrangedSubview(styleRow)
    }

    // MARK: - Paragraph Controls

    private func setupParagraphControls() {
        let paragraphSection = createSectionHeader("Paragraph")
        stackView.addArrangedSubview(paragraphSection)

        // Alignment Control
        let alignmentRow = NSStackView()
        alignmentRow.orientation = .horizontal
        alignmentRow.spacing = 10

        let alignmentLabel = NSTextField(labelWithString: "Alignment:")
        let alignmentSegment = NSSegmentedControl(labels: ["Left", "Center", "Right", "Justified"], trackingMode: .selectOne, target: self, action: #selector(alignmentChanged(_:)))

        switch alignment {
        case .left: alignmentSegment.selectedSegment = 0
        case .center: alignmentSegment.selectedSegment = 1
        case .right: alignmentSegment.selectedSegment = 2
        case .justified: alignmentSegment.selectedSegment = 3
        default: alignmentSegment.selectedSegment = 0
        }

        alignmentRow.addArrangedSubview(alignmentLabel)
        alignmentRow.addArrangedSubview(alignmentSegment)
        stackView.addArrangedSubview(alignmentRow)

        // Line Spacing Control
        let lineSpacingRow = NSStackView()
        lineSpacingRow.orientation = .horizontal
        lineSpacingRow.spacing = 10

        let lineSpacingLabel = NSTextField(labelWithString: "Line Spacing:")
        let lineSpacingSlider = NSSlider(value: Double(lineSpacing), minValue: 0, maxValue: 20, target: self, action: #selector(lineSpacingChanged(_:)))
        lineSpacingValueLabel = NSTextField(labelWithString: "\(Int(lineSpacing))pt")

        lineSpacingRow.addArrangedSubview(lineSpacingLabel)
        lineSpacingRow.addArrangedSubview(lineSpacingSlider)
        lineSpacingRow.addArrangedSubview(lineSpacingValueLabel)
        stackView.addArrangedSubview(lineSpacingRow)

        // Paragraph Spacing Control
        let paragraphSpacingRow = NSStackView()
        paragraphSpacingRow.orientation = .horizontal
        paragraphSpacingRow.spacing = 10

        let paragraphSpacingLabel = NSTextField(labelWithString: "Paragraph Spacing:")
        let paragraphSpacingSlider = NSSlider(value: Double(paragraphSpacing), minValue: 0, maxValue: 30, target: self, action: #selector(paragraphSpacingChanged(_:)))
        paragraphSpacingValueLabel = NSTextField(labelWithString: "\(Int(paragraphSpacing))pt")

        paragraphSpacingRow.addArrangedSubview(paragraphSpacingLabel)
        paragraphSpacingRow.addArrangedSubview(paragraphSpacingSlider)
        paragraphSpacingRow.addArrangedSubview(paragraphSpacingValueLabel)
        stackView.addArrangedSubview(paragraphSpacingRow)
    }

    // MARK: - Color Controls

    private func setupColorControls() {
        let colorSection = createSectionHeader("Color")
        stackView.addArrangedSubview(colorSection)

        // Text Color Control
        let textColorRow = NSStackView()
        textColorRow.orientation = .horizontal
        textColorRow.spacing = 10

        let textColorLabel = NSTextField(labelWithString: "Text Color:")
        let textColorWell = NSColorWell()
        textColorWell.color = textColor
        textColorWell.target = self
        textColorWell.action = #selector(textColorChanged(_:))

        textColorRow.addArrangedSubview(textColorLabel)
        textColorRow.addArrangedSubview(textColorWell)
        stackView.addArrangedSubview(textColorRow)

        // Background Color Control
        let bgColorRow = NSStackView()
        bgColorRow.orientation = .horizontal
        bgColorRow.spacing = 10

        let bgColorLabel = NSTextField(labelWithString: "Background:")
        let bgColorWell = NSColorWell()
        bgColorWell.color = backgroundColor ?? .clear
        bgColorWell.target = self
        bgColorWell.action = #selector(backgroundColorChanged(_:))

        let clearBgButton = NSButton(title: "Clear", target: self, action: #selector(clearBackgroundColor(_:)))
        clearBgButton.bezelStyle = .rounded

        bgColorRow.addArrangedSubview(bgColorLabel)
        bgColorRow.addArrangedSubview(bgColorWell)
        bgColorRow.addArrangedSubview(clearBgButton)
        stackView.addArrangedSubview(bgColorRow)
    }

    private func createSectionHeader(_ title: String) -> NSView {
        let headerView = NSView()
        headerView.translatesAutoresizingMaskIntoConstraints = false

        let headerLabel = NSTextField(labelWithString: title)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = NSFont.boldSystemFont(ofSize: 16)

        let separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator

        headerView.addSubview(headerLabel)
        headerView.addSubview(separator)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: headerView.topAnchor),
            headerLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),

            separator.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 4),
            separator.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),

            headerView.widthAnchor.constraint(equalToConstant: 460),
            headerView.heightAnchor.constraint(equalToConstant: 30),
        ])

        return headerView
    }

    // MARK: - Control Actions

    @objc func fontSizeChanged(_ sender: NSSlider) {
        fontSize = CGFloat(sender.doubleValue)
        fontSizeValueLabel.stringValue = "\(Int(fontSize))pt"
        delegate?.controlPanel(self, didChangeFontSize: fontSize)
    }

    @objc func fontWeightChanged(_ sender: NSPopUpButton) {
        let weights: [NSFont.Weight] = [.regular, .medium, .semibold, .bold]
        fontWeight = weights[sender.indexOfSelectedItem]
        delegate?.controlPanel(self, didChangeFontWeight: fontWeight)
    }

    @objc func fontStyleChanged(_ sender: NSPopUpButton) {
        switch sender.indexOfSelectedItem {
        case 0: fontStyle = .normal
        case 1: fontStyle = .italic
        case 2: fontStyle = .boldItalic
        default: fontStyle = .normal
        }
        delegate?.controlPanel(self, didChangeFontStyle: fontStyle)
    }

    @objc func alignmentChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: alignment = .left
        case 1: alignment = .center
        case 2: alignment = .right
        case 3: alignment = .justified
        default: alignment = .left
        }
        delegate?.controlPanel(self, didChangeAlignment: alignment)
    }

    @objc func lineSpacingChanged(_ sender: NSSlider) {
        lineSpacing = CGFloat(sender.doubleValue)
        lineSpacingValueLabel.stringValue = "\(Int(lineSpacing))pt"
        delegate?.controlPanel(self, didChangeLineSpacing: lineSpacing)
    }

    @objc func paragraphSpacingChanged(_ sender: NSSlider) {
        paragraphSpacing = CGFloat(sender.doubleValue)
        paragraphSpacingValueLabel.stringValue = "\(Int(paragraphSpacing))pt"
        delegate?.controlPanel(self, didChangeParagraphSpacing: paragraphSpacing)
    }

    @objc func textColorChanged(_ sender: NSColorWell) {
        textColor = sender.color
        delegate?.controlPanel(self, didChangeTextColor: textColor)
    }

    @objc func backgroundColorChanged(_ sender: NSColorWell) {
        backgroundColor = sender.color
        delegate?.controlPanel(self, didChangeBackgroundColor: backgroundColor)
    }

    @objc func clearBackgroundColor(_: NSButton) {
        backgroundColor = nil
        delegate?.controlPanel(self, didChangeBackgroundColor: nil)
    }

    // MARK: - 关闭面板

    @objc func closePanel() {
        dismiss(nil)
    }
}

// 为FontStyle枚举添加rawValue支持
extension ViewController.FontStyle {
    var rawValue: Int {
        get {
            switch self {
            case .normal: 0
            case .italic: 1
            case .boldItalic: 2
            }
        }
        set {}
    }
}
