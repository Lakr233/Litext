//
//  SelectionPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Selection on TextLabelView: by touch, mouse and keyboard, and from code,
//  with the delegate's reports and the selected text read back.
//

import Litext
import SwiftUI

struct SelectionPage: View {
    private static let code = """
    let label = TextLabelView()
    label.isSelectable = true
    label.selectionBackgroundColor = .systemYellow.withAlphaComponent(0.35) // nil: system color
    label.delegate = self

    label.selectWord(at: 12)        // as a double-click does
    label.selectLine(at: 12)        // the paragraph, as a triple-click does
    label.selectAll()
    label.selectionRange = NSRange(location: 4, length: 10)
    label.clearSelection()

    label.selectedPlainText()       // String?
    label.selectedAttributedText()  // attachments replaced by their text
    label.copySelection()           // to the pasteboard, and returned
    label.selectionContains(point)  // point in view coordinates

    func textLabelView(_ label: TextLabelView, didChangeSelection selection: NSRange?) { }
    func textLabelView(_ label: TextLabelView, didDragSelectionAt location: CGPoint) { }

    // SwiftUI
    TextLabel(attributedString: text)
        .selectable()
        .selectionBackgroundColor(.systemGreen.withAlphaComponent(0.3))
        .onSelectionChange { selectedText = $0 }
    """

    private static let selectionColors: [(name: String, color: PlatformColor?)] = [
        ("Default", nil),
        ("Yellow", PlatformColor.systemYellow.withAlphaComponent(0.35)),
        ("Green", PlatformColor.systemGreen.withAlphaComponent(0.3)),
        ("Pink", PlatformColor.systemPink.withAlphaComponent(0.25)),
    ]

    @State private var events = SelectionEvents()
    @State private var isSelectable = true
    @State private var colorIndex = 0
    @State private var index = 6.0
    @State private var swiftUISelection = "none"
    private let text = Self.makeText()
    private let swiftUIText = Self.makeSwiftUIText()

    var body: some View {
        CatalogPageScaffold(.selection, code: Self.code) {
            VStack(alignment: .leading, spacing: 16) {
                PlatformViewHost.label {
                    TextLabelView()
                } update: { label in
                    events.label = label
                    label.delegate = events
                    label.isSelectable = isSelectable
                    label.selectionBackgroundColor = Self.selectionColors[colorIndex].color
                    label.attributedText = text
                }
                .accessibilityIdentifier("demo.selection.label")

                Divider()
                Text("SwiftUI TextLabel with .selectable() and .onSelectionChange")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextLabel(attributedString: swiftUIText)
                    .selectable(isSelectable)
                    .selectionBackgroundColor(Self.selectionColors[colorIndex].color)
                    .onSelectionChange { swiftUISelection = $0 ?? "none" }
                    .accessibilityIdentifier("demo.selection.swiftUI")
                CatalogNote(Self.hint, systemImage: "cursorarrow.and.square.on.square.dashed")
            }
        } controls: {
            Toggle("isSelectable", isOn: $isSelectable)
            CatalogPicker(
                "selectionBackgroundColor",
                selection: $colorIndex,
                options: Array(Self.selectionColors.indices),
            ) { Self.selectionColors[$0].name }
            CatalogSlider(
                "Character index",
                value: $index,
                in: 0 ... Double(text.length - 1),
                step: 1,
            ) { Self.describeCharacter(at: Int($0), in: text) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading) {
                Button("selectWord(at:)") { events.label?.selectWord(at: Int(index)) }
                    .accessibilityIdentifier("demo.selection.selectWord")
                Button("selectLine(at:)") { events.label?.selectLine(at: Int(index)) }
                    .accessibilityIdentifier("demo.selection.selectLine")
                Button("selectAll()") { events.label?.selectAll() }
                    .accessibilityIdentifier("demo.selection.selectAll")
                Button("Range of 10") {
                    events.label?.selectionRange = NSRange(location: Int(index), length: 10)
                }
                .accessibilityIdentifier("demo.selection.setRange")
                Button("clearSelection()") { events.label?.clearSelection() }
                    .accessibilityIdentifier("demo.selection.clear")
                Button("copySelection()") { events.copy() }
                    .accessibilityIdentifier("demo.selection.copy")
            }
            .buttonStyle(.bordered)
            CatalogReadout("selectionRange", value: events.range, identifier: "state.selection.range")
            CatalogReadout("selectedPlainText()", value: events.plainText, identifier: "state.selection.text")
            CatalogReadout(
                "selectedAttributedText()",
                value: events.attributedSummary,
                identifier: "state.selection.attributed",
            )
            CatalogReadout("Selection changes", value: "\(events.changeCount)", identifier: "state.selection.changes")
            CatalogReadout(
                "didDragSelectionAt",
                value: events.dragLocation,
                identifier: "state.selection.drag",
            )
            CatalogReadout(
                "isInteractionInProgress",
                value: events.isInteractionInProgress,
                identifier: "state.selection.inProgress",
            )
            CatalogReadout("Copied", value: events.copied, identifier: "state.selection.copied")
            CatalogReadout("SwiftUI selection", value: swiftUISelection, identifier: "state.selection.swiftUI")
        }
    }

    private static var hint: String {
        #if os(macOS)
            "Drag to select, double-click a word, triple-click a paragraph. Click into the text, then ⌘A selects "
                + "all and ⌘C copies; Edit ▸ Copy works too. The two labels keep separate selections."
        #elseif os(tvOS)
            "tvOS has no touch selection; the buttons below select from code, and the label still draws it."
        #elseif os(visionOS)
            "Pinch and hold a word to select it, then drag the handles. A tap on the selection shows the menu."
        #else
            "Touch and hold a word to select it, then drag the handles. Double-tap selects a word, triple-tap a "
                + "paragraph; a tap on the selection shows the menu. With a hardware keyboard, ⌘A and ⌘C work."
        #endif
    }

    private static func describeCharacter(at index: Int, in text: NSAttributedString) -> String {
        let string = text.string as NSString
        guard index < string.length else { return "\(index)" }
        let character = string.substring(with: string.rangeOfComposedCharacterSequence(at: index))
        let shown = character == "\n" ? "⏎" : character == " " ? "␣" : character
        return "\(index) “\(shown)”"
    }

    private static func makeText() -> NSAttributedString {
        let body: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 17),
            .foregroundColor: PlatformColor.label,
        ]
        let text = NSMutableAttributedString(
            string: "Select words, lines or everything. The selection follows ",
            attributes: body,
        )
        var bold = body
        bold[.font] = PlatformFont.systemFont(ofSize: 17, weight: .bold)
        text.append(NSAttributedString(string: "styled runs", attributes: bold))
        text.append(NSAttributedString(string: " and ", attributes: body))
        var link = body
        link[.link] = URL(string: "https://github.com/Lakr233/Litext")
        link[.foregroundColor] = PlatformColor.systemBlue
        text.append(NSAttributedString(string: "links", attributes: link))
        text.append(NSAttributedString(
            string: " alike.\nA second paragraph shows what selectLine(at:) means: the whole paragraph, "
                + "without its line break, however many lines it wraps to.",
            attributes: body,
        ))
        return text
    }

    private static func makeSwiftUIText() -> NSAttributedString {
        NSAttributedString(
            string: "This TextLabel reports the selected plain text through its closure.",
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 15),
                .foregroundColor: PlatformColor.secondaryLabel,
            ],
        )
    }
}

/// Keeps what the label's delegate reported about the selection.
@Observable
final class SelectionEvents: TextLabelViewDelegate {
    @ObservationIgnored weak var label: TextLabelView?
    var range = "nil"
    var plainText = "nil"
    var attributedSummary = "nil"
    var changeCount = 0
    var dragLocation = "none"
    var isInteractionInProgress = "false"
    var copied = "nothing yet"

    func textLabelView(_ label: TextLabelView, didChangeSelection selection: NSRange?) {
        changeCount += 1
        range = selection.map { "{\($0.location), \($0.length)}" } ?? "nil"
        plainText = label.selectedPlainText().map { "“\($0)”" } ?? "nil"
        attributedSummary = Self.summary(of: label.selectedAttributedText())
        isInteractionInProgress = "\(label.isInteractionInProgress)"
    }

    func textLabelView(_ label: TextLabelView, didDragSelectionAt location: CGPoint) {
        let contains = label.selectionContains(location)
        dragLocation = "(\(Int(location.x)), \(Int(location.y))) inside: \(contains)"
        isInteractionInProgress = "\(label.isInteractionInProgress)"
    }

    func copy() {
        guard let label else { return }
        let copiedText = label.copySelection()
        copied = copiedText.length == 0 ? "nothing selected" : "\(copiedText.length) characters"
    }

    /// The number of attribute runs and the fonts in them.
    private static func summary(of text: NSAttributedString?) -> String {
        guard let text else { return "nil" }
        var runs = 0
        var weights: [String] = []
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, _, _ in
            runs += 1
            if attributes[.link] != nil {
                weights.append("link")
            } else if let font = attributes[.font] as? PlatformFont {
                weights.append(font.fontName.contains("Bold") || font.fontName.contains("bold") ? "bold" : "regular")
            }
        }
        return "\(runs) run\(runs == 1 ? "" : "s"): \(weights.joined(separator: ", "))"
    }
}
