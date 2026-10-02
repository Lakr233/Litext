//
//  HitTestingPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  The point-to-text queries: the character, the caret indices and the link or
//  attachment under a point, and the conversions between view and layout space.
//

import Litext
import SwiftUI

struct HitTestingPage: View {
    private static let code = """
    // `point` is in the label's coordinates (top-left origin), such as a
    // touch location or a converted mouse location.
    let character = label.characterIndex(at: point)      // the character under it
    let region = label.highlightRegion(at: point)        // link or attachment
    print(region?.kind, region?.stringRange, region?.linkURL)

    // The layout works in CoreText space (lower-left origin).
    let layoutPoint = label.layoutPoint(fromViewPoint: point)
    let caret = label.textLayout.textIndex(at: layoutPoint)          // nil between lines
    let nearest = label.textLayout.nearestTextIndex(at: layoutPoint) // nearest line

    // Mark the character: its rects come back in layout space.
    let cluster = (label.attributedText.string as NSString)
        .rangeOfComposedCharacterSequence(at: character!)
    let marks = label.textLayout.rects(for: cluster)
        .map { label.viewRect(fromLayoutRect: $0) }
    """

    @State private var model = HitProbeModel()
    @State private var showsRegions = true
    @State private var fontSize = 19.0
    @State private var text = Self.makeText(fontSize: 19)
    #if os(tvOS)
        @State private var probeX = 0.3
        @State private var probeY = 0.2
    #endif

    var body: some View {
        CatalogPageScaffold(.hitTesting, code: Self.code) {
            VStack(alignment: .leading, spacing: 12) {
                PlatformViewHost<HitProbeLabel>.label {
                    let label = HitProbeLabel()
                    #if !os(tvOS)
                        // tvOS starts from the sliders' point instead.
                        label.initialProbeIndex = Self.initialProbeIndex
                    #endif
                    return label
                } update: { label in
                    let model = model
                    label.onResult = { result in
                        if model.result != result {
                            model.result = result
                        }
                    }
                    label.showsRegionRects = showsRegions
                    #if os(tvOS)
                        label.probeFraction = CGPoint(x: probeX, y: probeY)
                    #endif
                    // An equal string is ignored, so this is cheap on every update.
                    label.attributedText = text
                }
                .accessibilityIdentifier("demo.hitTesting.label")
                CatalogNote(Self.hint, systemImage: "hand.point.up.left")
            }
            .onChange(of: fontSize) { _, size in text = Self.makeText(fontSize: size) }
        } controls: {
            #if os(tvOS)
                CatalogSlider("Probe x", value: $probeX, in: 0 ... 1, step: 0.02) { "\(Int($0 * 100))%" }
                CatalogSlider("Probe y", value: $probeY, in: 0 ... 1, step: 0.02) { "\(Int($0 * 100))%" }
            #endif
            Toggle("Outline the region under the probe", isOn: $showsRegions)
            CatalogSlider("Font size", value: $fontSize, in: 13 ... 34, step: 1) { "\(Int($0)) pt" }
            readouts
        }
    }

    @ViewBuilder
    private var readouts: some View {
        let result = model.result
        CatalogReadout(
            "View point",
            value: result.map { HitProbeResult.describe($0.viewPoint) } ?? "none",
            identifier: "state.hitTesting.viewPoint",
        )
        CatalogReadout(
            "layoutPoint(fromViewPoint:)",
            value: result.map { HitProbeResult.describe($0.layoutPoint) } ?? "none",
            identifier: "state.hitTesting.layoutPoint",
        )
        CatalogReadout(
            "characterIndex(at:)",
            value: HitProbeResult.describe(result?.characterIndex),
            identifier: "state.hitTesting.characterIndex",
        )
        CatalogReadout(
            "Character",
            value: result?.clusterText.map { "“\($0)” \(HitProbeResult.describe(result?.clusterRange))" } ?? "none",
            identifier: "state.hitTesting.character",
        )
        CatalogReadout(
            "textIndex(at:)",
            value: HitProbeResult.describe(result?.textIndex),
            identifier: "state.hitTesting.textIndex",
        )
        CatalogReadout(
            "nearestTextIndex(at:)",
            value: HitProbeResult.describe(result?.nearestTextIndex),
            identifier: "state.hitTesting.nearestTextIndex",
        )
        CatalogReadout(
            "highlightRegion(at:)",
            value: result?.regionKind.map { "\($0) \(HitProbeResult.describe(result?.regionRange))" } ?? "nil",
            identifier: "state.hitTesting.region",
        )
        CatalogReadout(
            "linkURL",
            value: result?.regionURL ?? "nil",
            identifier: "state.hitTesting.linkURL",
        )
        CatalogNote(
            "textIndex(at:) and nearestTextIndex(at:) return caret positions, so the right half of a "
                + "letter gives the next index; characterIndex(at:) returns the character itself. "
                + "Region rects are slightly enlarged, as they are for taps.",
            systemImage: "info.circle",
        )
    }

    private static var hint: String {
        #if os(macOS)
            "Move the pointer over the text. The pink box is the character under it, the orange outline the link or attachment."
        #elseif os(tvOS)
            "tvOS has no pointer over the text: move the probe with the sliders below."
        #elseif os(visionOS)
            "Look at the text with a pinch, or touch it. The pink box is the character, the orange outline the link or attachment."
        #else
            "Touch and drag over the text, or hover with a trackpad on iPad. The pink box is the character, the orange outline the link or attachment."
        #endif
    }

    private static let linkText = "a link long enough to wrap from one line onto the next"

    private static var initialProbeIndex: Int {
        (makeText(fontSize: 17).string as NSString).range(of: linkText).location + 2
    }

    private static func makeText(fontSize: CGFloat) -> NSAttributedString {
        let body: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: fontSize),
            .foregroundColor: PlatformColor.label,
        ]
        let text = NSMutableAttributedString(string: "Probe anywhere: plain words, ", attributes: body)
        var link = body
        link[.link] = URL(string: "https://github.com/Lakr233/Litext")
        link[.foregroundColor] = PlatformColor.systemBlue
        text.append(NSAttributedString(string: linkText, attributes: link))
        text.append(NSAttributedString(string: ", an attachment ", attributes: body))
        let side = (fontSize * 1.2).rounded()
        let attachment = TextLabel.Attachment(
            size: CGSize(width: side, height: side),
            view: CatalogAttachmentViews.symbol(
                "scope",
                color: .systemPurple,
                size: CGSize(width: side, height: side),
            ),
        )
        text.append(attachment.attributedString(attributes: body))
        text.append(NSAttributedString(
            string: ", emoji 👩‍💻🇨🇭, and a gap between lines below.\n\nThe last line starts after an empty paragraph.",
            attributes: body,
        ))
        return text
    }
}
