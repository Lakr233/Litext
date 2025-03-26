//
//  Created for LitextSamples.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import UIKit

// Define the delegate protocol for communication with the main view controller
protocol ControlPanelDelegate: AnyObject {
    func controlPanel(_ controlPanel: ControlPanelViewController, didChangeFontSize fontSize: CGFloat)
    func controlPanel(_ controlPanel: ControlPanelViewController, didChangeFontWeight fontWeight: UIFont.Weight)
    func controlPanel(_ controlPanel: ControlPanelViewController, didChangeFontStyle fontStyle: ViewController.FontStyle)
    func controlPanel(_ controlPanel: ControlPanelViewController, didChangeAlignment alignment: NSTextAlignment)
    func controlPanel(_ controlPanel: ControlPanelViewController, didChangeLineSpacing lineSpacing: CGFloat)
    func controlPanel(_ controlPanel: ControlPanelViewController, didChangeParagraphSpacing paragraphSpacing: CGFloat)
    func controlPanel(_ controlPanel: ControlPanelViewController, didChangeTextColor textColor: UIColor)
    func controlPanel(_ controlPanel: ControlPanelViewController, didChangeBackgroundColor backgroundColor: UIColor?)
}

class ControlPanelViewController: UIViewController {
    // Main components
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    // Control options
    var fontSize: CGFloat = 16
    var lineSpacing: CGFloat = 6
    var paragraphSpacing: CGFloat = 10
    var alignment: NSTextAlignment = .left
    var textColor: UIColor = .label
    var fontWeight: UIFont.Weight = .regular
    var fontStyle: ViewController.FontStyle = .normal
    var backgroundColor: UIColor? = nil

    // Control sections and options
    let sections = ["Font", "Paragraph", "Color"]
    let options: [[String]] = [
        ["Size", "Weight", "Style"],
        ["Alignment", "Line Spacing", "Paragraph Spacing"],
        ["Text Color", "Background"],
    ]

    // Delegate
    weak var delegate: ControlPanelDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGroupedBackground
        setupTableView()
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(dismiss)),
        ]
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }
}

// MARK: - UITableViewDelegate & UITableViewDataSource

extension ControlPanelViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in _: UITableView) -> Int {
        sections.count
    }

    func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        options[section].count
    }

    func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section]
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.textLabel?.text = options[indexPath.section][indexPath.row]
        cell.accessoryType = .disclosureIndicator

        // Add detail text based on current settings
        switch (indexPath.section, indexPath.row) {
        case (0, 0): // Font Size
            cell.detailTextLabel?.text = "\(Int(fontSize))pt"
        case (0, 1): // Font Weight
            let weightName = switch fontWeight {
            case .regular: "Regular"
            case .medium: "Medium"
            case .semibold: "Semibold"
            case .bold: "Bold"
            default: "Regular"
            }
            cell.detailTextLabel?.text = weightName
        case (0, 2): // Font Style
            let styleName = switch fontStyle {
            case .normal: "Normal"
            case .italic: "Italic"
            case .boldItalic: "Bold Italic"
            }
            cell.detailTextLabel?.text = styleName
        case (1, 0): // Alignment
            let alignmentName = switch alignment {
            case .left: "Left"
            case .center: "Center"
            case .right: "Right"
            case .justified: "Justified"
            default: "Left"
            }
            cell.detailTextLabel?.text = alignmentName
        case (1, 1): // Line Spacing
            cell.detailTextLabel?.text = "\(Int(lineSpacing))pt"
        case (1, 2): // Paragraph Spacing
            cell.detailTextLabel?.text = "\(Int(paragraphSpacing))pt"
        case (2, 0): // Text Color
            cell.detailTextLabel?.text = getColorName(textColor)
        case (2, 1): // Background Color
            cell.detailTextLabel?.text = backgroundColor == nil ? "None" : getColorName(backgroundColor!)
        default:
            cell.detailTextLabel?.text = nil
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch (indexPath.section, indexPath.row) {
        case (0, 0): // Font Size
            showFontSizeOptions()
        case (0, 1): // Font Weight
            showFontWeightOptions()
        case (0, 2): // Font Style
            showFontStyleOptions()
        case (1, 0): // Alignment
            showAlignmentOptions()
        case (1, 1): // Line Spacing
            showLineSpacingOptions()
        case (1, 2): // Paragraph Spacing
            showParagraphSpacingOptions()
        case (2, 0): // Text Color
            showTextColorOptions()
        case (2, 1): // Background Color
            showBackgroundColorOptions()
        default:
            break
        }
    }

    private func getColorName(_ color: UIColor) -> String {
        if color == .label { return "Default" }
        if color == .systemRed { return "Red" }
        if color == .systemBlue { return "Blue" }
        if color == .systemGreen { return "Green" }
        if color == .systemPurple { return "Purple" }
        if color == .systemOrange { return "Orange" }
        return "Custom"
    }

    // MARK: - Option Menus

    func showFontSizeOptions() {
        let alert = UIAlertController(title: "Font Size", message: nil, preferredStyle: .actionSheet)

        for size in [12, 14, 16, 18, 20, 22, 24] {
            alert.addAction(UIAlertAction(title: "\(size)pt", style: .default) { [weak self] _ in
                guard let self else { return }
                fontSize = CGFloat(size)
                delegate?.controlPanel(self, didChangeFontSize: CGFloat(size))
                tableView.reloadData()
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = tableView
        present(alert, animated: true)
    }

    func showFontWeightOptions() {
        let alert = UIAlertController(title: "Font Weight", message: nil, preferredStyle: .actionSheet)

        let weights: [(String, UIFont.Weight)] = [
            ("Regular", .regular),
            ("Medium", .medium),
            ("Semibold", .semibold),
            ("Bold", .bold),
        ]

        for (name, weight) in weights {
            alert.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                guard let self else { return }
                fontWeight = weight
                delegate?.controlPanel(self, didChangeFontWeight: weight)
                tableView.reloadData()
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = tableView
        present(alert, animated: true)
    }

    func showFontStyleOptions() {
        let alert = UIAlertController(title: "Font Style", message: nil, preferredStyle: .actionSheet)

        let styles: [(String, ViewController.FontStyle)] = [
            ("Normal", .normal),
            ("Italic", .italic),
            ("Bold Italic", .boldItalic),
        ]

        for (name, style) in styles {
            alert.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                guard let self else { return }
                fontStyle = style
                delegate?.controlPanel(self, didChangeFontStyle: style)
                tableView.reloadData()
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = tableView
        present(alert, animated: true)
    }

    func showAlignmentOptions() {
        let alert = UIAlertController(title: "Text Alignment", message: nil, preferredStyle: .actionSheet)

        let alignments: [(String, NSTextAlignment)] = [
            ("Left", .left),
            ("Center", .center),
            ("Right", .right),
            ("Justified", .justified),
        ]

        for (name, align) in alignments {
            alert.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                guard let self else { return }
                alignment = align
                delegate?.controlPanel(self, didChangeAlignment: align)
                tableView.reloadData()
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = tableView
        present(alert, animated: true)
    }

    func showLineSpacingOptions() {
        let alert = UIAlertController(title: "Line Spacing", message: nil, preferredStyle: .actionSheet)

        for spacing in [0, 2, 4, 6, 8, 10, 12] {
            alert.addAction(UIAlertAction(title: "\(spacing)pt", style: .default) { [weak self] _ in
                guard let self else { return }
                lineSpacing = CGFloat(spacing)
                delegate?.controlPanel(self, didChangeLineSpacing: CGFloat(spacing))
                tableView.reloadData()
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = tableView
        present(alert, animated: true)
    }

    func showParagraphSpacingOptions() {
        let alert = UIAlertController(title: "Paragraph Spacing", message: nil, preferredStyle: .actionSheet)

        for spacing in [0, 5, 10, 15, 20, 25, 30] {
            alert.addAction(UIAlertAction(title: "\(spacing)pt", style: .default) { [weak self] _ in
                guard let self else { return }
                paragraphSpacing = CGFloat(spacing)
                delegate?.controlPanel(self, didChangeParagraphSpacing: CGFloat(spacing))
                tableView.reloadData()
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = tableView
        present(alert, animated: true)
    }

    func showTextColorOptions() {
        let alert = UIAlertController(title: "Text Color", message: nil, preferredStyle: .actionSheet)

        let colors: [(String, UIColor)] = [
            ("Default", .label),
            ("Red", .systemRed),
            ("Blue", .systemBlue),
            ("Green", .systemGreen),
            ("Purple", .systemPurple),
            ("Orange", .systemOrange),
        ]

        for (name, color) in colors {
            alert.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                guard let self else { return }
                textColor = color
                delegate?.controlPanel(self, didChangeTextColor: color)
                tableView.reloadData()
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = tableView
        present(alert, animated: true)
    }

    func showBackgroundColorOptions() {
        let alert = UIAlertController(title: "Background Color", message: nil, preferredStyle: .actionSheet)

        let colors: [(String, UIColor?)] = [
            ("None", nil),
            ("Light Gray", UIColor.systemGray6),
            ("Light Yellow", UIColor.systemYellow.withAlphaComponent(0.15)),
            ("Light Green", UIColor.systemGreen.withAlphaComponent(0.15)),
            ("Light Blue", UIColor.systemBlue.withAlphaComponent(0.15)),
            ("Light Pink", UIColor.systemPink.withAlphaComponent(0.15)),
            ("Light Purple", UIColor.systemPurple.withAlphaComponent(0.15)),
        ]

        for (name, color) in colors {
            alert.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                guard let self else { return }
                backgroundColor = color
                delegate?.controlPanel(self, didChangeBackgroundColor: color)
                tableView.reloadData()
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = tableView
        present(alert, animated: true)
    }
}
