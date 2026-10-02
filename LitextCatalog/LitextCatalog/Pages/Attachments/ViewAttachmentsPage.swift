//
//  ViewAttachmentsPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Platform views of several sizes placed inline with TextLabel.Attachment,
//  resized in place and wrapped with the text around them.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct ViewAttachmentsPage: View {
    private static let code = """
    let size = CGSize(width: 64, height: 84)
    let attachment = TextLabel.Attachment(size: size, view: photoView)

    let text = NSMutableAttributedString(string: "A photo ", attributes: body)
    // attributedString(attributes:) gives the attachment's character a font, so
    // the line around it keeps its metrics.
    text.append(attachment.attributedString(attributes: body))
    text.append(NSAttributedString(string: " flows with the text.", attributes: body))
    label.attributedText = text

    // Resizing a displayed attachment: change its size, then re-typeset.
    attachment.size = CGSize(width: 96, height: 126)
    label.reloadTextLayout()
    """

    @State private var model = ViewAttachmentsModel()
    @State private var scale = 1.0
    @State private var containerWidth = 760.0

    var body: some View {
        CatalogPageScaffold(.viewAttachments, code: Self.code) {
            PlatformViewHost.label {
                let label = TextLabelView()
                label.isSelectable = true
                return label
            } update: { label in
                if label.attributedText !== model.text, !label.attributedText.isEqual(to: model.text) {
                    label.attributedText = model.text
                }
                if model.applyScale(scale) {
                    label.reloadTextLayout()
                }
            }
            .frame(maxWidth: containerWidth, alignment: .leading)
            .overlay(alignment: .trailing) {
                if containerWidth < CatalogStyle.readableWidth {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.5))
                        .frame(width: 1)
                        .offset(x: 8)
                }
            }
            .accessibilityIdentifier("demo.viewAttachments.label")
        } controls: {
            CatalogSlider("Attachment scale", value: $scale, in: 0.5 ... 2, step: 0.1) {
                $0.formatted(.number.precision(.fractionLength(1))) + "×"
            }
            CatalogSlider("Container width", value: $containerWidth, in: 160 ... CatalogStyle.readableWidth, step: 10) {
                $0 >= CatalogStyle.readableWidth ? "Full" : "\(Int($0)) pt"
            }
            CatalogReadout("Photo size", value: model.photoSizeDescription, identifier: "state.viewAttachments.photoSize")
            CatalogNote("Touches on an attachment's view go to the view: the label neither selects text nor reports a tap there.")
        }
    }
}

/// Holds the attachments, so their views survive SwiftUI updates.
@Observable
private final class ViewAttachmentsModel {
    private(set) var photoSizeDescription = ""

    @ObservationIgnored let text: NSAttributedString
    @ObservationIgnored private let attachments: [(attachment: TextLabel.Attachment, baseSize: CGSize)]
    @ObservationIgnored private var appliedScale = 1.0

    init() {
        let icon = CGSize(width: 20, height: 20)
        let photo = CGSize(width: 64, height: 84)
        let banner = CGSize(width: 220, height: 36)
        let attachments = [
            (TextLabel.Attachment(
                size: icon,
                view: CatalogAttachmentViews.symbol("sparkles", color: .systemYellow, size: icon),
            ), icon),
            (TextLabel.Attachment(size: photo, view: CatalogAttachmentViews.hosting(PhotoTile(), size: photo)), photo),
            (TextLabel.Attachment(size: banner, view: CatalogAttachmentViews.hosting(BannerTile(), size: banner)), banner),
        ]
        self.attachments = attachments.map { (attachment: $0.0, baseSize: $0.1) }

        let body: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 17),
            .foregroundColor: PlatformColor.label,
        ]
        let text = NSMutableAttributedString()
        func append(_ string: String) {
            text.append(NSAttributedString(string: string, attributes: body))
        }
        append("A small icon ")
        text.append(attachments[0].0.attributedString(attributes: body))
        append(" sits in the line like a glyph. A taller view ")
        text.append(attachments[1].0.attributedString(attributes: body))
        append(" makes its line taller, and the lines after it move down. A wide banner ")
        text.append(attachments[2].0.attributedString(attributes: body))
        append(" wraps onto a line of its own when the rest of the line has no room for it. Drag the sliders to watch every attachment reflow with the words around it.")
        self.text = text
        photoSizeDescription = Self.describe(photo)
    }

    /// Resizes every attachment to `scale` times its base size; `true` when anything changed.
    func applyScale(_ scale: Double) -> Bool {
        guard scale != appliedScale else { return false }
        appliedScale = scale
        for entry in attachments {
            entry.attachment.size = CGSize(
                width: (entry.baseSize.width * scale).rounded(),
                height: (entry.baseSize.height * scale).rounded(),
            )
        }
        let photoSize = attachments[1].attachment.size
        // Published after the SwiftUI update that triggered it.
        Task { @MainActor in self.photoSizeDescription = Self.describe(photoSize) }
        return true
    }

    private static func describe(_ size: CGSize) -> String {
        "\(Int(size.width)) × \(Int(size.height)) pt"
    }
}

/// A stand-in for a photo: a gradient landscape.
private struct PhotoTile: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(LinearGradient(colors: [.teal, .indigo], startPoint: .top, endPoint: .bottom))
            .overlay {
                Image(systemName: "mountain.2.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(10)
            }
    }
}

/// A wide call-to-action banner.
private struct BannerTile: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.accentColor.gradient)
            .overlay {
                Label("A wide banner attachment", systemImage: "rectangle.wide")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 8)
            }
    }
}
