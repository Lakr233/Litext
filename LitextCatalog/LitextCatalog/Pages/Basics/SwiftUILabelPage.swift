//
//  SwiftUILabelPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  TextLabel, the SwiftUI view, and every modifier it has.
//

import Litext
import SwiftUI

struct SwiftUILabelPage: View {
    private static let code = """
    TextLabel(attributedString: text)
        .selectable(true)
        .selectionBackgroundColor(.systemYellow.withAlphaComponent(0.3))
        .onTapLink { url in lastLink = url.absoluteString }
        .onTapAttachment { attachment in tappedAttachment = attachment }
        .onSelectionChange { selected in selectedText = selected ?? "" }

    // Localized keys are looked up in this bundle instead of the main one.
    someView.litextBundle(.module)
    """

    private static let selectionColors: [(name: String, color: PlatformColor?)] = [
        ("Default", nil),
        ("Yellow", PlatformColor.systemYellow.withAlphaComponent(0.35)),
        ("Green", PlatformColor.systemGreen.withAlphaComponent(0.25)),
        ("Pink", PlatformColor.systemPink.withAlphaComponent(0.25)),
    ]

    @State private var isSelectable = true
    @State private var selectionColorIndex = 0
    @State private var lastLink = ""
    @State private var attachmentTaps = 0
    @State private var selectedText = ""
    @State private var text = Self.makeText()

    var body: some View {
        CatalogPageScaffold(.swiftUILabel, code: Self.code) {
            TextLabel(attributedString: text)
                .selectable(isSelectable)
                .selectionBackgroundColor(Self.selectionColors[selectionColorIndex].color)
                .onTapLink { lastLink = $0.absoluteString }
                .onTapAttachment { _ in attachmentTaps += 1 }
                .onSelectionChange { selectedText = $0 ?? "" }
                .accessibilityIdentifier("demo.swiftUI.label")
        } controls: {
            Toggle("Selectable", isOn: $isSelectable)
            CatalogPicker(
                "Selection color",
                selection: $selectionColorIndex,
                options: Array(Self.selectionColors.indices),
            ) { Self.selectionColors[$0].name }
            CatalogReadout("Last link", value: lastLink.isEmpty ? "none" : lastLink, identifier: "state.lastTappedURL")
            CatalogReadout("Attachment taps", value: "\(attachmentTaps)", identifier: "state.attachmentTaps")
            CatalogReadout("Selected text", value: selectedText.isEmpty ? "none" : selectedText, identifier: "state.selectedText")
        }
    }

    private static func makeText() -> NSAttributedString {
        let body: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 17),
            .foregroundColor: PlatformColor.label,
        ]
        let text = NSMutableAttributedString(string: "TextLabel takes an attributed string and shows it with ", attributes: body)
        var link = body
        link[.link] = URL(string: "https://github.com/Lakr233/Litext")
        link[.foregroundColor] = PlatformColor.systemBlue
        text.append(NSAttributedString(string: "links you can tap", attributes: link))
        text.append(NSAttributedString(string: ", attachments like this one ", attributes: body))

        let size = CGSize(width: 22, height: 22)
        let attachment = TextLabel.Attachment(
            size: size,
            view: CatalogAttachmentViews.symbol("star.fill", color: .systemOrange, size: size),
        )
        text.append(attachment.attributedString(attributes: body))
        text.append(NSAttributedString(
            string: " that report their own taps, and a selection that reports what it covers. Drag across the text to select it.",
            attributes: body,
        ))
        return text
    }
}
