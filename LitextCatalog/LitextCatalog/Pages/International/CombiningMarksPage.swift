//
//  CombiningMarksPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Base letters with combining marks, from a single accent to stacks, and
//  scripts whose vowels are marks. Normalization changes the storage, not the
//  picture, and selection keeps each cluster whole.
//

import Litext
import SwiftUI

struct CombiningMarksPage: View {
    private static let code = """
    // "é" can be one scalar (U+00E9) or two (U+0065 U+0301). Both draw the
    // same; ranges count UTF-16 units, so they differ in length.
    let composed = text.precomposedStringWithCanonicalMapping     // NFC
    let decomposed = text.decomposedStringWithCanonicalMapping    // NFD

    label.attributedText = NSAttributedString(string: decomposed, attributes: attributes)
    label.isSelectable = true

    // Word selection and drags land on cluster boundaries, so a mark is never
    // separated from its base letter.
    label.selectWord(at: index)
    let selected = label.selectedPlainText()!
    print(selected.count, selected.unicodeScalars.count, selected.utf16.count)
    """

    enum Normalization: String, CaseIterable, Hashable {
        case asTyped
        case nfc
        case nfd

        var title: String {
            switch self {
            case .asTyped: "As typed"
            case .nfc: "NFC"
            case .nfd: "NFD"
            }
        }

        func apply(to string: String) -> String {
            switch self {
            case .asTyped: string
            case .nfc: string.precomposedStringWithCanonicalMapping
            case .nfd: string.decomposedStringWithCanonicalMapping
            }
        }
    }

    private static let samples = [
        "Café, cafe\u{301}, naïve, Ångström, A\u{30A}ngstro\u{308}m",
        "Stacked: e\u{301}\u{302}\u{304} o\u{308}\u{303} Z\u{351}\u{354}a\u{306}\u{317}l\u{35B}\u{30C}g\u{30C}\u{316}o\u{350}\u{325}",
        "Tiếng Việt: Người ở đâu? Phở bò, bánh mì, cà phê sữa đá.",
        "ไทย: น้ำที่นี่ใสมาก กุ้งก้ามกราม",
        "हिन्दी: नमस्ते, क्षत्रिय, द्वारा, श्रृंखला",
        "Hebrew points: בְּרֵאשִׁית בָּרָא",
    ]

    @State private var events = SelectionReadoutEvents()
    @State private var normalization = Normalization.asTyped
    @State private var fontSize = 22.0

    var body: some View {
        let text = Self.makeText(normalization: normalization, fontSize: fontSize)
        CatalogPageScaffold(.combiningMarks, code: Self.code) {
            VStack(alignment: .leading, spacing: 10) {
                PlatformViewHost.label {
                    TextLabelView()
                } update: { label in
                    events.label = label
                    label.delegate = events
                    label.isSelectable = true
                    label.attributedText = text
                }
                .accessibilityIdentifier("demo.combiningMarks.label")
                CatalogNote(
                    "Marks that stack far above or below their letter can reach outside the line box and be "
                        + "clipped at the label's edges: sizes come from typographic bounds, as with UILabel.",
                )
            }
        } controls: {
            CatalogPicker("Normalization", selection: $normalization, options: Normalization.allCases) { $0.title }
            CatalogSlider("Font size", value: $fontSize, in: 14 ... 40, step: 1) { "\(Int($0)) pt" }
            CatalogReadout(
                "Whole text: Characters / scalars / UTF-16",
                value: "\(text.string.count) / \(text.string.unicodeScalars.count) / \(text.length)",
                identifier: "state.combiningMarks.totals",
            )
            HStack {
                Button("Select “Ångström”") { events.selectWord(containing: "ngstr") }
                    .accessibilityIdentifier("demo.combiningMarks.selectWord")
                Button("Clear") { events.label?.clearSelection() }
            }
            .buttonStyle(.bordered)
            CatalogReadout("selectionRange", value: events.range, identifier: "state.combiningMarks.range")
            CatalogReadout("Selected text", value: events.text, identifier: "state.combiningMarks.text")
            CatalogReadout(
                "Characters / scalars / UTF-16",
                value: "\(events.characterCount) / \(events.scalarCount) / \(events.utf16Length)",
                identifier: "state.combiningMarks.counts",
            )
        }
    }

    private static func makeText(normalization: Normalization, fontSize: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = fontSize * 0.4
        let string = samples.map(normalization.apply(to:)).joined(separator: "\n")
        return NSAttributedString(string: string, attributes: [
            .font: PlatformFont.systemFont(ofSize: fontSize),
            .foregroundColor: PlatformColor.label,
            .paragraphStyle: paragraph,
        ])
    }
}

extension SelectionReadoutEvents {
    /// Selects the word that contains `fragment`, the first time it occurs.
    func selectWord(containing fragment: String) {
        guard let label else { return }
        let location = (label.attributedText.string as NSString).range(of: fragment).location
        guard location != NSNotFound else { return }
        label.selectWord(at: location)
    }
}
