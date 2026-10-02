//
//  LabelViewPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  TextLabelView, built in code the way a UIKit or AppKit app builds it, with
//  a delegate that reports taps and selection.
//

import Litext
import SwiftUI

struct LabelViewPage: View {
    private static let code = """
    let label = TextLabelView()
    label.attributedText = text
    label.isSelectable = true
    label.linkHighlightColor = .systemOrange.withAlphaComponent(0.25)
    label.delegate = self   // TextLabelViewDelegate

    // Auto Layout: the label wraps at the width it is given, or at
    // preferredMaxLayoutWidth when that is set.
    label.translatesAutoresizingMaskIntoConstraints = false
    label.preferredMaxLayoutWidth = 320

    func textLabelView(
        _ label: TextLabelView,
        didTapHighlightRegion region: TextLabel.HighlightRegion,
        at location: CGPoint,
    ) {
        print(region.linkURL as Any, region.stringRange)
    }

    func textLabelView(_ label: TextLabelView, didChangeSelection selection: NSRange?) {
        print(label.selectedPlainText() ?? "")
    }
    """

    @State private var events = LabelViewEvents()
    @State private var isSelectable = true
    @State private var fontSize = 17.0

    var body: some View {
        CatalogPageScaffold(.labelView, code: Self.code) {
            PlatformViewHost.label {
                TextLabelView()
            } update: { label in
                label.delegate = events
                label.isSelectable = isSelectable
                label.linkHighlightColor = PlatformColor.systemOrange.withAlphaComponent(0.25)
                let text = Self.makeText(fontSize: fontSize)
                if !label.attributedText.isEqual(to: text) {
                    label.attributedText = text
                }
            }
            .accessibilityIdentifier("demo.labelView.label")
        } controls: {
            Toggle("isSelectable", isOn: $isSelectable)
            CatalogSlider("Font size", value: $fontSize, in: 11 ... 32, step: 1) { "\(Int($0)) pt" }
            CatalogReadout("Last region", value: events.lastRegion, identifier: "state.labelView.region")
            CatalogReadout("Selection range", value: events.selectionRange, identifier: "state.labelView.range")
            CatalogReadout("Selected text", value: events.selectedText, identifier: "state.labelView.text")
        }
    }

    private static func makeText(fontSize: CGFloat) -> NSAttributedString {
        let body: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: fontSize),
            .foregroundColor: PlatformColor.label,
        ]
        let text = NSMutableAttributedString(
            string: "TextLabelView is a UIView on iOS, tvOS and visionOS and an NSView on macOS. Its delegate hears about ",
            attributes: body,
        )
        var link = body
        link[.link] = URL(string: "https://developer.apple.com/documentation/coretext")
        link[.foregroundColor] = PlatformColor.systemBlue
        text.append(NSAttributedString(string: "taps on links", attributes: link))
        text.append(NSAttributedString(
            string: " and every change of the selection, as the readouts below show.",
            attributes: body,
        ))
        return text
    }
}

/// Receives the label's delegate callbacks and keeps what they reported for the readouts.
@Observable
final class LabelViewEvents: TextLabelViewDelegate {
    var lastRegion = "none"
    var selectionRange = "none"
    var selectedText = "none"

    func textLabelView(
        _: TextLabelView,
        didTapHighlightRegion region: TextLabel.HighlightRegion,
        at _: CGPoint,
    ) {
        let target = region.linkURL?.absoluteString ?? "attachment"
        lastRegion = "\(target) \(NSStringFromRange(region.stringRange))"
    }

    func textLabelView(_ label: TextLabelView, didChangeSelection selection: NSRange?) {
        selectionRange = selection.map(NSStringFromRange) ?? "none"
        selectedText = label.selectedPlainText() ?? "none"
    }
}
