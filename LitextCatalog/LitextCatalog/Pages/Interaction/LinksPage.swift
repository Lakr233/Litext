//
//  LinksPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Links in an attributed string: the delegate that hears taps, the pressed
//  highlight's color and corner radius, and the forms a link value can take.
//

import Litext
import SwiftUI

struct LinksPage: View {
    private static let code = """
    // A link is the .link attribute, holding a URL or a String.
    text.addAttribute(.link, value: URL(string: "https://example.com")!, range: range)
    text.addAttribute(.link, value: "litext://catalog/links", range: other)

    let label = TextLabelView()
    label.attributedText = text
    label.linkHighlightColor = .systemOrange.withAlphaComponent(0.3) // nil: link color at 10%
    label.linkHighlightCornerRadius = 8
    label.delegate = self

    func textLabelView(
        _ label: TextLabelView,
        didTapHighlightRegion region: TextLabel.HighlightRegion,
        at location: CGPoint,
    ) {
        guard region.kind == .link, let url = region.linkURL else { return }
        open(url)   // TextLabelView opens nothing by itself
    }

    // SwiftUI: TextLabel opens links with the system unless you handle them.
    TextLabel(attributedString: text)
        .onTapLink { url in lastLink = url }
    """

    private static let highlightColors: [(name: String, color: PlatformColor?)] = [
        ("Default", nil),
        ("Orange", PlatformColor.systemOrange.withAlphaComponent(0.3)),
        ("Green", PlatformColor.systemGreen.withAlphaComponent(0.3)),
        ("Purple", PlatformColor.systemPurple.withAlphaComponent(0.3)),
    ]

    @Environment(\.openURL) private var openURL
    @State private var events = LinkTapEvents()
    @State private var colorIndex = 1
    @State private var cornerRadius = 4.0
    @State private var opensLinks = false
    @State private var swiftUILink = "none"
    private let text = Self.makeText()
    private let swiftUIText = Self.makeSwiftUIText()

    var body: some View {
        CatalogPageScaffold(.links, code: Self.code) {
            VStack(alignment: .leading, spacing: 16) {
                PlatformViewHost.label {
                    TextLabelView()
                } update: { label in
                    let openURL = openURL
                    let opensLinks = opensLinks
                    events.open = { url in
                        if opensLinks {
                            openURL(url)
                        }
                    }
                    label.delegate = events
                    label.linkHighlightColor = Self.highlightColors[colorIndex].color
                    label.linkHighlightCornerRadius = cornerRadius
                    label.attributedText = text
                }
                .accessibilityIdentifier("demo.links.label")

                Divider()
                Text("SwiftUI TextLabel with .onTapLink")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextLabel(attributedString: swiftUIText)
                    .onTapLink { url in
                        swiftUILink = url.absoluteString
                        if opensLinks {
                            openURL(url)
                        }
                    }
                    .accessibilityIdentifier("demo.links.swiftUI")
            }
        } controls: {
            CatalogPicker(
                "linkHighlightColor",
                selection: $colorIndex,
                options: Array(Self.highlightColors.indices),
            ) { Self.highlightColors[$0].name }
            CatalogSlider("linkHighlightCornerRadius", value: $cornerRadius, in: 0 ... 12, step: 1) { "\(Int($0)) pt" }
            HighlightPreview(color: Self.highlightColors[colorIndex].color, cornerRadius: cornerRadius)
            #if !os(tvOS)
                Toggle("Open tapped links in the browser", isOn: $opensLinks)
            #endif
            CatalogReadout("Last link", value: events.lastURL, identifier: "state.links.lastURL")
            CatalogReadout("Value type", value: events.valueType, identifier: "state.links.valueType")
            CatalogReadout("stringRange", value: events.range, identifier: "state.links.range")
            CatalogReadout("Tap location", value: events.location, identifier: "state.links.location")
            CatalogReadout("Taps", value: "\(events.tapCount)", identifier: "state.links.taps")
            CatalogReadout("SwiftUI .onTapLink", value: swiftUILink, identifier: "state.links.swiftUI")
            CatalogNote(Self.hint)
        }
    }

    private static var hint: String {
        #if os(macOS)
            "Press and hold the mouse on a link to see the highlight; the tap is reported when you release over it."
        #elseif os(tvOS)
            "tvOS has no pointer over the label, so links cannot be tapped there; the highlight settings still apply."
        #else
            "Touch and hold a link to see the highlight; the tap is reported when you lift your finger over it."
        #endif
    }

    private static func makeText() -> NSAttributedString {
        let body: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 17),
            .foregroundColor: PlatformColor.label,
        ]
        let text = NSMutableAttributedString(string: "A link can hold a ", attributes: body)

        var urlLink = body
        urlLink[.link] = URL(string: "https://github.com/Lakr233/Litext")
        urlLink[.foregroundColor] = PlatformColor.systemBlue
        text.append(NSAttributedString(string: "URL value", attributes: urlLink))
        text.append(NSAttributedString(string: " or a ", attributes: body))

        var stringLink = body
        stringLink[.link] = "litext://catalog/links?from=string"
        stringLink[.foregroundColor] = PlatformColor.systemTeal
        text.append(NSAttributedString(string: "String value", attributes: stringLink))
        text.append(NSAttributedString(
            string: "; HighlightRegion.linkURL resolves both. A link can carry any style, like ",
            attributes: body,
        ))

        var styled = body
        styled[.link] = URL(string: "https://developer.apple.com/documentation/coretext")
        styled[.font] = PlatformFont.catalogFont(ofSize: 17, weight: .semibold, italic: true)
        styled[.foregroundColor] = PlatformColor.systemPink
        styled[.underlineStyle] = NSUnderlineStyle.single.rawValue
        text.append(NSAttributedString(string: "this bold, italic, underlined one", attributes: styled))
        text.append(NSAttributedString(string: ", and a ", attributes: body))

        var long = body
        long[.link] = URL(string: "https://www.unicode.org/reports/tr14/")
        long[.foregroundColor] = PlatformColor.systemIndigo
        text.append(NSAttributedString(
            string: "long link that wraps from one line onto the next one",
            attributes: long,
        ))
        text.append(NSAttributedString(
            string: " highlights every line it covers. A link without a foreground color ",
            attributes: body,
        ))
        var plain = body
        plain[.link] = URL(string: "https://example.com/plain")
        text.append(NSAttributedString(string: "keeps the text color", attributes: plain))
        text.append(NSAttributedString(string: ".", attributes: body))
        return text
    }

    private static func makeSwiftUIText() -> NSAttributedString {
        let body: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 15),
            .foregroundColor: PlatformColor.secondaryLabel,
        ]
        let text = NSMutableAttributedString(string: "Without .onTapLink, TextLabel opens ", attributes: body)
        var link = body
        link[.link] = URL(string: "https://www.apple.com")
        link[.foregroundColor] = PlatformColor.systemBlue
        text.append(NSAttributedString(string: "links like this", attributes: link))
        text.append(NSAttributedString(string: " with the system; with it, your closure decides.", attributes: body))
        return text
    }
}

/// A swatch of the pressed-link highlight with the chosen color and radius.
private struct HighlightPreview: View {
    let color: PlatformColor?
    let cornerRadius: CGFloat

    var body: some View {
        HStack {
            Text("Pressed highlight")
                .foregroundStyle(.secondary)
            Spacer()
            Text("pressed link")
                .foregroundStyle(.blue)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private var fill: Color {
        if let color {
            #if canImport(UIKit)
                Color(uiColor: color)
            #else
                Color(nsColor: color)
            #endif
        } else {
            Color.blue.opacity(0.1)
        }
    }
}

/// Keeps what the label's delegate reported about link taps.
@Observable
final class LinkTapEvents: TextLabelViewDelegate {
    var lastURL = "none"
    var valueType = "none"
    var range = "none"
    var location = "none"
    var tapCount = 0
    @ObservationIgnored var open: (URL) -> Void = { _ in }

    func textLabelView(
        _: TextLabelView,
        didTapHighlightRegion region: TextLabel.HighlightRegion,
        at location: CGPoint,
    ) {
        guard region.kind == .link else { return }
        tapCount += 1
        lastURL = region.linkURL?.absoluteString ?? "invalid"
        valueType = region.attributes[.link] is URL ? "URL" : "String"
        range = "{\(region.stringRange.location), \(region.stringRange.length)}"
        self.location = "(\(Int(location.x)), \(Int(location.y)))"
        if let url = region.linkURL {
            open(url)
        }
    }
}
