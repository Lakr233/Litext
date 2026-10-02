//
//  AttachmentDescentPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  TextLabel.Attachment.descent: how far an attachment hangs below the
//  baseline, compared across the default, zero, the font's descent and a value
//  of your own, with the baselines drawn over the text.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct AttachmentDescentPage: View {
    private static let code = """
    let attachment = TextLabel.Attachment(size: CGSize(width: 36, height: 36), view: box)

    attachment.descent = nil            // default: a tenth of the height
    attachment.descent = 0              // sits on the baseline
    attachment.descent = -font.descender // bottom lines up with the descenders
    attachment.descent = 12             // clamped to 0 ... size.height

    // CoreText reads the metrics when it typesets, so re-typeset a label
    // that already shows the attachment.
    label.reloadTextLayout()
    """

    @State private var model = AttachmentDescentModel()
    @State private var height = 36.0
    @State private var customDescent = 18.0
    @State private var showsGuides = true

    var body: some View {
        CatalogPageScaffold(.attachmentDescent, code: Self.code) {
            VStack(alignment: .leading, spacing: 12) {
                PlatformViewHost<OverlayLabelView>.label {
                    OverlayLabelView()
                } update: { label in
                    if label.attributedText !== model.text, !label.attributedText.isEqual(to: model.text) {
                        label.attributedText = model.text
                    }
                    if model.apply(height: height, customDescent: customDescent) {
                        label.reloadTextLayout()
                    }
                    let showsGuides = showsGuides
                    let fontDescent = model.fontDescent
                    label.overlay = { label, context in
                        guard showsGuides else { return }
                        AttachmentDescentGuides.draw(over: label, fontDescent: fontDescent, in: context)
                    }
                    label.setNeedsTextDisplay()
                }
                .accessibilityIdentifier("demo.attachmentDescent.label")

                HStack(spacing: 14) {
                    guideSwatch("Baseline", .red, dashed: false)
                    guideSwatch("Font descent", .gray, dashed: true)
                    guideSwatch("Attachment box", .green, dashed: false)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } controls: {
            CatalogSlider("Attachment height", value: $height, in: 12 ... 64, step: 1) { "\(Int($0)) pt" }
            CatalogSlider("Your descent", value: $customDescent, in: 0 ... height, step: 1) { "\(Int($0)) pt" }
            Toggle("Show baselines and boxes", isOn: $showsGuides)
            CatalogReadout(
                "Default (nil)",
                value: "\(Self.points(height * 0.1)) below",
                identifier: "state.attachmentDescent.default",
            )
            CatalogReadout(
                "Font descent",
                value: "\(Self.points(model.fontDescent)) below",
                identifier: "state.attachmentDescent.font",
            )
            CatalogReadout(
                "Yours",
                value: "\(Self.points(min(customDescent, height))) below, \(Self.points(height - min(customDescent, height))) above",
                identifier: "state.attachmentDescent.custom",
            )
        }
        .onChange(of: height) { _, newHeight in
            customDescent = min(customDescent, newHeight)
        }
    }

    private func guideSwatch(_ title: String, _ color: Color, dashed: Bool) -> some View {
        Label {
            Text(title)
        } icon: {
            Rectangle()
                .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 2] : []))
                .frame(width: 14, height: 0.5)
        }
    }

    private static func points(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0 ... 1)))) pt"
    }
}

/// The four attachments and the text that shows them side by side.
@Observable
private final class AttachmentDescentModel {
    @ObservationIgnored let text: NSAttributedString
    @ObservationIgnored let fontDescent: CGFloat
    @ObservationIgnored private let defaultBox: TextLabel.Attachment
    @ObservationIgnored private let zeroBox: TextLabel.Attachment
    @ObservationIgnored private let fontBox: TextLabel.Attachment
    @ObservationIgnored private let customBox: TextLabel.Attachment
    @ObservationIgnored private var applied: (height: Double, descent: Double)?

    init() {
        let font = PlatformFont.systemFont(ofSize: 26)
        fontDescent = -font.descender
        let size = CGSize(width: 36, height: 36)
        func box(_ color: Color) -> TextLabel.Attachment {
            TextLabel.Attachment(size: size, view: CatalogAttachmentViews.hosting(DescentBox(color: color), size: size))
        }
        defaultBox = box(.blue)
        zeroBox = box(.orange)
        fontBox = box(.purple)
        customBox = box(.green)
        zeroBox.descent = 0
        fontBox.descent = fontDescent

        let body: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: PlatformColor.label,
        ]
        let caption: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 13),
            .foregroundColor: PlatformColor.secondaryLabel,
        ]
        let text = NSMutableAttributedString()
        for (attachment, title) in [
            (defaultBox, "nil"),
            (zeroBox, "0"),
            (fontBox, "font"),
            (customBox, "yours"),
        ] {
            text.append(NSAttributedString(string: "Hxgy ", attributes: body))
            text.append(attachment.attributedString(attributes: body))
            text.append(NSAttributedString(string: " \(title)   ", attributes: caption))
        }
        self.text = text
    }

    /// Applies the sliders; `true` when an attachment changed and the label must re-typeset.
    func apply(height: Double, customDescent: Double) -> Bool {
        guard applied?.height != height || applied?.descent != customDescent else { return false }
        applied = (height, customDescent)
        let size = CGSize(width: height, height: height)
        for attachment in [defaultBox, zeroBox, fontBox, customBox] {
            attachment.size = size
        }
        customBox.descent = customDescent
        return true
    }
}

/// A square that marks its own vertical middle, so its position against the baseline reads at a glance.
private struct DescentBox: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color.opacity(0.35))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(color, lineWidth: 1.5)
            }
    }
}

private enum AttachmentDescentGuides {
    static func draw(over label: OverlayLabelView, fontDescent: CGFloat, in context: CGContext) {
        for line in label.layoutLines {
            let baseline = label.baselineSegment(of: line)
            OverlayPainter.line(from: baseline.start, to: baseline.end, color: .systemRed, in: context)
            let descentY = baseline.start.y + fontDescent
            OverlayPainter.line(
                from: CGPoint(x: baseline.start.x, y: descentY),
                to: CGPoint(x: baseline.end.x, y: descentY),
                color: .systemGray,
                in: context,
                dash: [4, 3],
            )
        }
        // The attachment runs report the box the run delegate reserved: height above
        // the baseline is size.height - descent, below is the descent.
        for run in label.layoutRuns(matching: .litextAttachment) {
            OverlayPainter.stroke(
                label.viewRect(fromLayoutRect: run.rect).insetBy(dx: -2, dy: -2),
                color: .systemGreen,
                in: context,
                fillAlpha: 0,
            )
        }
    }
}
