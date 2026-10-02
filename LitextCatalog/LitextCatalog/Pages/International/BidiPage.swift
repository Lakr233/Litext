//
//  BidiPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Right-to-left scripts and mixed-direction lines, with the paragraph's base
//  direction and alignment as knobs, and a selection that spans direction
//  changes.
//

import Litext
import SwiftUI

struct BidiPage: View {
    private static let code = """
    let paragraph = NSMutableParagraphStyle()
    paragraph.baseWritingDirection = .rightToLeft   // .natural follows the first strong letter
    paragraph.alignment = .natural                  // leading edge of that direction

    let text = NSAttributedString(
        string: "LTR שלום عربى 123",
        attributes: [.font: PlatformFont.systemFont(ofSize: 17), .paragraphStyle: paragraph],
    )

    let label = TextLabelView()
    label.attributedText = text
    label.isSelectable = true
    label.delegate = self   // didChangeSelection reports logical (storage) ranges
    """

    enum Direction: String, CaseIterable, Hashable {
        case natural
        case leftToRight
        case rightToLeft

        var title: String {
            switch self {
            case .natural: "Natural"
            case .leftToRight: "LTR"
            case .rightToLeft: "RTL"
            }
        }

        var writingDirection: NSWritingDirection {
            switch self {
            case .natural: .natural
            case .leftToRight: .leftToRight
            case .rightToLeft: .rightToLeft
            }
        }
    }

    enum Alignment: String, CaseIterable, Hashable {
        case natural
        case left
        case center
        case right
        case justified

        var title: String {
            switch self {
            case .natural: "Natural"
            case .left: "Left"
            case .center: "Center"
            case .right: "Right"
            case .justified: "Justify"
            }
        }

        var textAlignment: NSTextAlignment {
            switch self {
            case .natural: .natural
            case .left: .left
            case .center: .center
            case .right: .right
            case .justified: .justified
            }
        }
    }

    @State private var events = SelectionReadoutEvents()
    @State private var direction = Direction.natural
    @State private var alignment = Alignment.natural

    var body: some View {
        CatalogPageScaffold(.bidi, code: Self.code) {
            VStack(alignment: .leading, spacing: 10) {
                PlatformViewHost.label {
                    TextLabelView()
                } update: { label in
                    events.label = label
                    label.delegate = events
                    label.isSelectable = true
                    label.attributedText = Self.makeText(direction: direction, alignment: alignment)
                }
                .accessibilityIdentifier("demo.bidi.label")
                CatalogNote(
                    "Selection ranges are logical: a range that crosses from Hebrew into English and the digits "
                        + "is one storage range, drawn as several visual pieces.",
                )
            }
        } controls: {
            CatalogPicker("baseWritingDirection", selection: $direction, options: Direction.allCases) { $0.title }
            CatalogPicker("alignment", selection: $alignment, options: Alignment.allCases) { $0.title }
            HStack {
                Button("Select the mixed line") { events.selectParagraph(containing: "LTR") }
                    .accessibilityIdentifier("demo.bidi.selectMixed")
                Button("Clear") { events.label?.clearSelection() }
            }
            .buttonStyle(.bordered)
            CatalogReadout("selectionRange", value: events.range, identifier: "state.bidi.range")
            CatalogReadout("Selected text", value: events.text, identifier: "state.bidi.text")
            CatalogReadout("Visual pieces", value: events.pieces, identifier: "state.bidi.pieces")
        }
    }

    private static func makeText(direction: Direction, alignment: Alignment) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = direction.writingDirection
        paragraph.alignment = alignment.textAlignment
        paragraph.paragraphSpacing = 10
        let body: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 18),
            .foregroundColor: PlatformColor.label,
            .paragraphStyle: paragraph,
        ]
        let lines = [
            "LTR שלום عربى 123",
            "עברית נכתבת מימין לשמאל, אבל מספרים כמו 2025 ו־3.14 נשארים משמאל לימין.",
            "العربية تُكتب من اليمين إلى اليسار، والحروف تتصل ببعضها: مرحبا بالعالم ١٢٣.",
            "English with an embedded quote: he said “שלום עולם” and left at 10:30.",
            "Arabic price السعر: 45.99 USD (ضريبة 5٪) in an English sentence.",
        ]
        return NSAttributedString(string: lines.joined(separator: "\n"), attributes: body)
    }
}

/// Keeps a label's selection for the readouts: its logical range, its text and
/// the number of rects it draws as.
@Observable
final class SelectionReadoutEvents: TextLabelViewDelegate {
    @ObservationIgnored weak var label: TextLabelView?
    var range = "nil"
    var text = "nil"
    var pieces = "0"
    var utf16Length = 0
    var characterCount = 0
    var scalarCount = 0

    func textLabelView(_ label: TextLabelView, didChangeSelection selection: NSRange?) {
        range = selection.map { "{\($0.location), \($0.length)}" } ?? "nil"
        let selected = label.selectedPlainText()
        text = selected.map { "“\($0)”" } ?? "nil"
        utf16Length = selected?.utf16.count ?? 0
        characterCount = selected?.count ?? 0
        scalarCount = selected?.unicodeScalars.count ?? 0
        pieces = selection.map { "\(label.textLayout.rects(for: $0).count)" } ?? "0"
    }

    /// Selects the paragraph that contains `marker`.
    func selectParagraph(containing marker: String) {
        guard let label else { return }
        let location = (label.attributedText.string as NSString).range(of: marker).location
        guard location != NSNotFound else { return }
        label.selectLine(at: location)
    }
}
