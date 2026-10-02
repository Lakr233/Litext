//
//  EmojiPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Emoji built from many scalars: ZWJ sequences, flags, skin tones, keycaps
//  and presentation selectors, each hit-tested and selected as one character.
//

import Litext
import SwiftUI

struct EmojiPage: View {
    private static let code = """
    // Emoji need no setup: Apple Color Emoji is a fallback of the system font.
    let text = NSAttributedString(string: "Family 👨‍👩‍👧‍👦 flag 🇨🇭", attributes: attributes)
    label.attributedText = text

    // A family is 7 scalars and 11 UTF-16 units, but one character.
    if let index = label.characterIndex(at: point) {
        let string = label.attributedText.string as NSString
        let cluster = string.rangeOfComposedCharacterSequence(at: index)
        print(string.substring(with: cluster), cluster)   // 👨‍👩‍👧‍👦 {7, 11}
    }
    """

    private static let lines: [(caption: String, emoji: String)] = [
        ("ZWJ sequences", "👨‍👩‍👧‍👦 👩‍👩‍👦 🧑‍🧑‍🧒 👩🏽‍🔬 🧑🏿‍🚀 🐻‍❄️ ❤️‍🔥"),
        ("Flags", "🇯🇵 🇨🇭 🇧🇷 🇰🇷 🏳️‍🌈 🏴‍☠️ 🏴󠁧󠁢󠁳󠁣󠁴󠁿"),
        ("Skin tones", "👋 👋🏻 👋🏼 👋🏽 👋🏾 👋🏿 🤝🏻 🫱🏼‍🫲🏿"),
        ("Keycaps", "1️⃣ 2️⃣ #️⃣ *️⃣ 🔟"),
        ("Presentation selectors", "☺︎ ☺️ ❤︎ ❤️ ✈︎ ✈️ ↔︎ ↔️"),
    ]

    @State private var model = HitProbeModel()
    @State private var fontSize = 22.0
    @State private var text = Self.makeText(fontSize: 22)
    @State private var selection = SelectionReadoutEvents()

    var body: some View {
        CatalogPageScaffold(.emoji, code: Self.code) {
            VStack(alignment: .leading, spacing: 10) {
                PlatformViewHost<HitProbeLabel>.label {
                    let label = HitProbeLabel()
                    label.showsRegionRects = false
                    label.initialProbeIndex = Self.initialProbeIndex
                    return label
                } update: { label in
                    let model = model
                    label.onResult = { result in
                        if model.result != result {
                            model.result = result
                        }
                    }
                    selection.label = label
                    label.delegate = selection
                    label.isSelectable = true
                    label.attributedText = text
                }
                .onChange(of: fontSize) { _, size in text = Self.makeText(fontSize: size) }
                .accessibilityIdentifier("demo.emoji.label")
                CatalogNote(Self.hint, systemImage: "hand.point.up.left")
                CatalogNote(
                    "Emoji bitmaps can draw a little outside the typographic bounds the label sizes its lines "
                        + "from, so their edges may clip at the top or bottom of the label. This is a known limitation.",
                    systemImage: "exclamationmark.triangle",
                )
            }
        } controls: {
            CatalogSlider("Font size", value: $fontSize, in: 13 ... 48, step: 1) { "\(Int($0)) pt" }
            let result = model.result
            CatalogReadout("Character", value: result?.clusterText ?? "none", identifier: "state.emoji.character")
            CatalogReadout(
                "characterIndex(at:)",
                value: HitProbeResult.describe(result?.characterIndex),
                identifier: "state.emoji.index",
            )
            CatalogReadout(
                "UTF-16 range",
                value: HitProbeResult.describe(result?.clusterRange),
                identifier: "state.emoji.range",
            )
            CatalogReadout(
                "Scalars",
                value: HitProbeResult.scalars(of: result?.clusterText),
                identifier: "state.emoji.scalars",
            )
            CatalogReadout("Selected", value: selection.text, identifier: "state.emoji.selected")
            CatalogReadout(
                "Selected: Characters / UTF-16",
                value: "\(selection.characterCount) / \(selection.utf16Length)",
                identifier: "state.emoji.selectedCounts",
            )
        }
    }

    private static var hint: String {
        #if os(macOS)
            "Move the pointer over an emoji to see the character the label finds; drag to select."
        #elseif os(tvOS)
            "tvOS has no pointer over the text; the readouts show the family emoji the probe starts on."
        #else
            "Touch an emoji (or hover with a trackpad) to see the character the label finds; touch and hold to select."
        #endif
    }

    private static var initialProbeIndex: Int {
        (makeText(fontSize: 22).string as NSString).range(of: "👨‍👩‍👧‍👦").location
    }

    private static func makeText(fontSize: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = fontSize * 0.35
        let caption: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: max(fontSize * 0.6, 11), weight: .semibold),
            .foregroundColor: PlatformColor.secondaryLabel,
            .paragraphStyle: paragraph,
        ]
        let body: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: fontSize),
            .foregroundColor: PlatformColor.label,
            .paragraphStyle: paragraph,
        ]
        let text = NSMutableAttributedString()
        for line in lines {
            text.append(NSAttributedString(string: line.caption + "  ", attributes: caption))
            text.append(NSAttributedString(string: line.emoji + "\n", attributes: body))
        }
        text.append(NSAttributedString(string: "Mixed sizes  ", attributes: caption))
        let sizes: [(CGFloat, String)] = [(0.6, "small 🌱 "), (1, "body 🌿 "), (1.6, "large 🌳")]
        for (scale, fragment) in sizes {
            var attributes = body
            attributes[.font] = PlatformFont.systemFont(ofSize: (fontSize * scale).rounded())
            text.append(NSAttributedString(string: fragment, attributes: attributes))
        }
        return text
    }
}
