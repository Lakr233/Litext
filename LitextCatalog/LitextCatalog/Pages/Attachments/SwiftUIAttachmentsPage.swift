//
//  SwiftUIAttachmentsPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  SwiftUI views inside a SwiftUI TextLabel. Off watchOS an attachment shows
//  a UIView or NSView, so each SwiftUI view goes through a hosting view; the
//  hosted views stay live and redraw on their own as their state changes.
//

import Litext
import SwiftUI

struct SwiftUIAttachmentsPage: View {
    private static let code = """
    // Off watchOS an attachment takes a platform view: host the SwiftUI view.
    let host = NSHostingView(rootView: TagView("Swift 6"))   // UIHostingController(…).view on iOS
    let tag = NamedAttachment(name: "tag", size: CGSize(width: 64, height: 22), view: host)

    // An attachment can say what to copy in place of its view.
    final class NamedAttachment: TextLabel.Attachment {
        override func attributedStringRepresentation() -> NSAttributedString {
            NSAttributedString(string: "[\\(name)]")
        }
    }

    TextLabel(attributedString: text)
        .selectable(true)
        // Taps the label itself receives on an attachment: one without a view,
        // or the few points around a view. Touches on a view go to the view.
        .onTapAttachment { attachment in tapped = (attachment as? NamedAttachment)?.name }
        .onSelectionChange { copied = $0 ?? "" }
    """

    @State private var model = SwiftUIAttachmentsModel()
    @State private var isSelectable = true

    var body: some View {
        CatalogPageScaffold(.swiftUIAttachments, code: Self.code) {
            TextLabel(attributedString: model.text)
                .selectable(isSelectable)
                .onTapAttachment { attachment in
                    model.recordTap(on: attachment)
                }
                .onSelectionChange { model.selectedText = $0 ?? "none" }
                .accessibilityIdentifier("demo.swiftUIAttachments.label")
        } controls: {
            Toggle("Selectable", isOn: $isSelectable)
            Button("Shuffle the chart") {
                withAnimation(.snappy) { model.chart.shuffle() }
            }
            .accessibilityIdentifier("demo.swiftUIAttachments.shuffle")
            CatalogReadout("Likes (SwiftUI button)", value: "\(model.chart.likes)", identifier: "state.swiftUIAttachments.likes")
            CatalogReadout("onTapAttachment", value: model.lastTap, identifier: "state.swiftUIAttachments.tap")
            CatalogReadout("Selected text", value: model.selectedText, identifier: "state.swiftUIAttachments.selection")
            CatalogNote(
                "The dashed blank is an attachment with no view, painted by a LineDrawingAction: the label receives its taps, so onTapAttachment fires. Taps on a hosted view go to that view, which is why the heart is a SwiftUI Button.",
            )
        }
    }
}

/// An attachment with a name, copied as "[name]".
private final class NamedAttachment: TextLabel.Attachment {
    let name: String

    init(name: String, size: CGSize, view: PlatformView?) {
        self.name = name
        super.init()
        self.size = size
        self.view = view
    }

    override func attributedStringRepresentation() -> NSAttributedString {
        NSAttributedString(string: "[\(name)]")
    }
}

/// State the hosted SwiftUI views read, so they update without the text changing.
@Observable
private final class SwiftUIAttachmentChart {
    var values: [Double] = [0.3, 0.8, 0.5, 1, 0.6]
    var likes = 12

    func shuffle() {
        values = values.map { _ in Double.random(in: 0.15 ... 1) }
    }
}

@Observable
private final class SwiftUIAttachmentsModel {
    var lastTap = "none"
    var selectedText = "none"
    let chart = SwiftUIAttachmentChart()
    @ObservationIgnored private(set) var text = NSAttributedString()
    @ObservationIgnored private var blankTaps = 0

    init() {
        text = makeText()
    }

    func recordTap(on attachment: TextLabel.Attachment) {
        let name = (attachment as? NamedAttachment)?.name ?? "unnamed"
        if name == "blank" {
            blankTaps += 1
        }
        lastTap = name == "blank" ? "blank (\(blankTaps)×)" : name
    }

    private func makeText() -> NSAttributedString {
        let font = PlatformFont.systemFont(ofSize: 17)
        let body: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: PlatformColor.label,
        ]
        let text = NSMutableAttributedString()
        func append(_ string: String) {
            text.append(NSAttributedString(string: string, attributes: body))
        }
        func append(_ name: String, size: CGSize, content: some View) {
            let attachment = NamedAttachment(
                name: name,
                size: size,
                view: CatalogAttachmentViews.hosting(content, size: size),
            )
            attachment.descent = max((size.height - font.xHeight) / 2, 0)
            text.append(attachment.attributedString(attributes: body))
        }

        append("A capsule tag ")
        append("tag: Swift 6", size: CGSize(width: 64, height: 22), content: TagChip(title: "Swift 6"))
        append(", an avatar ")
        append("avatar: LT", size: CGSize(width: 24, height: 24), content: AvatarBadge(initials: "LT"))
        append(", a live chart ")
        append("chart", size: CGSize(width: 64, height: 22), content: MiniBarChart(chart: chart))
        append(" that redraws when you shuffle it, and a heart ")
        append("like button", size: CGSize(width: 56, height: 24), content: LikeButton(chart: chart))
        append(" that counts its own taps. Fill in the ")

        let blank = NamedAttachment(name: "blank", size: CGSize(width: 72, height: 22), view: nil)
        blank.descent = max((22 - font.xHeight) / 2, 0)
        var blankAttributes = body
        blankAttributes[.litextLineDrawingAction] = Self.blankPainter(for: blank, at: text.length)
        text.append(blank.attributedString(attributes: blankAttributes))
        append(" to see onTapAttachment fire.")
        return text
    }

    /// Paints a dashed box where the view-less attachment at `index` sits.
    private static func blankPainter(for blank: TextLabel.Attachment, at index: Int) -> TextLabel.LineDrawingAction {
        let size = blank.size
        let descent = blank.descent ?? 0
        let color = PlatformColor.systemTeal.cgColor
        return TextLabel.LineDrawingAction { context, line, origin in
            let x = CTLineGetOffsetForStringIndex(line, index, nil)
            let rect = CGRect(x: origin.x + x, y: origin.y - descent, width: size.width, height: size.height)
                .insetBy(dx: 1, dy: 1)
            context.setStrokeColor(color)
            context.setFillColor(color.copy(alpha: 0.12) ?? color)
            context.setLineWidth(1.5)
            context.setLineDash(phase: 0, lengths: [4, 3])
            let path = CGPath(roundedRect: rect, cornerWidth: 5, cornerHeight: 5, transform: nil)
            context.addPath(path)
            context.fillPath()
            context.addPath(path)
            context.strokePath()
        }
    }
}

// MARK: - Hosted views

private struct TagChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().fill(Color.orange.gradient))
    }
}

private struct AvatarBadge: View {
    let initials: String

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Text(initials)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
    }
}

private struct MiniBarChart: View {
    let chart: SwiftUIAttachmentChart

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(chart.values.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.gradient)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .scaleEffect(x: 1, y: chart.values[index], anchor: .bottom)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)))
    }
}

private struct LikeButton: View {
    let chart: SwiftUIAttachmentChart

    var body: some View {
        Button {
            chart.likes += 1
        } label: {
            Label("\(chart.likes)", systemImage: "heart.fill")
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Capsule().fill(Color.pink.opacity(0.18)))
                .foregroundStyle(.pink)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("demo.swiftUIAttachments.like")
    }
}
