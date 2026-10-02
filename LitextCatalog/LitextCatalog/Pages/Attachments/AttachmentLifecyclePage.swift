//
//  AttachmentLifecyclePage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  When attachment views come and go: a label keeps the views of attachments
//  that stay in its text, adds the views of new ones, and lets go of the
//  views its text no longer mentions. Weak references count what is alive.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct AttachmentLifecyclePage: View {
    private static let code = """
    // Same attachment objects in new text: the label keeps their views.
    label.attributedText = sentence(with: attachments, words: otherWords)

    // New attachment objects: their views are added, and the old views are
    // removed and released with the old attachments.
    attachments = (0 ..< count).map { _ in TextLabel.Attachment(size: size, view: makeView()) }
    label.attributedText = sentence(with: attachments, words: words)

    // Text without attachments removes every view.
    label.attributedText = NSAttributedString(string: "No attachments.")

    // The run delegate retains a small metrics box, not the attachment, so
    // dropping the attachment releases it and its view.
    """

    @State private var model = AttachmentLifecycleModel()
    @State private var count = 4.0
    @State private var autoReplaces = false

    var body: some View {
        CatalogPageScaffold(.attachmentLifecycle, code: Self.code) {
            PlatformViewHost.label {
                TextLabelView()
            } update: { label in
                if label.attributedText !== model.text, !label.attributedText.isEqual(to: model.text) {
                    label.attributedText = model.text
                }
            }
            .accessibilityIdentifier("demo.attachmentLifecycle.label")
        } controls: {
            CatalogSlider("Attachments", value: $count, in: 1 ... 12, step: 1) { "\(Int($0))" }
            ViewThatFits(in: .horizontal) {
                HStack { actionButtons }
                VStack(alignment: .leading) { actionButtons }
            }
            Toggle("Replace automatically", isOn: $autoReplaces)
            CatalogReadout("Views alive", value: "\(model.alive)", identifier: "state.attachmentLifecycle.alive")
            CatalogReadout("Views created", value: "\(model.created)", identifier: "state.attachmentLifecycle.created")
            CatalogReadout("In the text", value: "\(model.attachmentCount)", identifier: "state.attachmentLifecycle.inText")
            CatalogReadout("Last change", value: model.lastEvent, identifier: "state.attachmentLifecycle.event")
            CatalogNote(
                "CoreText keeps the attributes of the last string it typeset on each thread, so on iOS the views of the previous text can stay alive until the next string is typeset. The count settles one change later.",
                systemImage: "info.circle",
            )
        }
        .onChange(of: count) { _, newCount in
            model.replaceWithNewAttachments(count: Int(newCount))
        }
        .task(id: autoReplaces) {
            // Polls the weak references, and replaces the text on a timer when asked to.
            var tick = 0
            while !Task.isCancelled {
                model.refreshAliveCount()
                if autoReplaces, tick % 3 == 2 {
                    if tick % 6 == 2 {
                        model.replaceWithNewAttachments(count: Int(count))
                    } else {
                        model.rewordKeepingAttachments()
                    }
                }
                tick += 1
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    @ViewBuilder private var actionButtons: some View {
        Button("New attachments") { model.replaceWithNewAttachments(count: Int(count)) }
            .accessibilityIdentifier("demo.attachmentLifecycle.new")
        Button("Reword, keep attachments") { model.rewordKeepingAttachments() }
            .accessibilityIdentifier("demo.attachmentLifecycle.reword")
        Button("Remove all") { model.removeAttachments() }
            .accessibilityIdentifier("demo.attachmentLifecycle.remove")
    }
}

@Observable
private final class AttachmentLifecycleModel {
    private(set) var text = NSAttributedString()
    private(set) var created = 0
    private(set) var alive = 0
    private(set) var lastEvent = "none"
    private(set) var attachmentCount = 0

    @ObservationIgnored private var attachments: [TextLabel.Attachment] = []
    @ObservationIgnored private var createdViews: [WeakView] = []
    @ObservationIgnored private var wordingIndex = 0

    private static let size = CGSize(width: 24, height: 24)
    private static let colors: [PlatformColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPink, .systemPurple, .systemTeal]
    private static let wordings = [
        ["One", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"],
        ["Alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa", "lambda", "mu"],
        ["Red", "orange", "yellow", "green", "teal", "blue", "indigo", "violet", "pink", "brown", "gray", "black"],
    ]

    init() {
        replaceWithNewAttachments(count: 4)
    }

    func replaceWithNewAttachments(count: Int) {
        attachments = (0 ..< count).map { index in
            created += 1
            let view = CatalogAttachmentViews.symbol(
                "\(created % 50).circle.fill",
                color: Self.colors[index % Self.colors.count],
                size: Self.size,
            )
            createdViews.append(WeakView(view))
            let attachment = TextLabel.Attachment(size: Self.size, view: view)
            attachment.descent = 6
            return attachment
        }
        rebuildText()
        lastEvent = "\(count) new views"
        scheduleRefresh()
    }

    func rewordKeepingAttachments() {
        wordingIndex = (wordingIndex + 1) % Self.wordings.count
        rebuildText()
        lastEvent = attachments.isEmpty ? "reworded" : "reworded, \(attachments.count) views kept"
        scheduleRefresh()
    }

    func removeAttachments() {
        attachments = []
        rebuildText()
        lastEvent = "removed all"
        scheduleRefresh()
    }

    func refreshAliveCount() {
        createdViews.removeAll { $0.view == nil }
        if alive != createdViews.count {
            alive = createdViews.count
        }
    }

    private func scheduleRefresh() {
        // The label drops old views in its next layout pass; count after it.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            self?.refreshAliveCount()
        }
    }

    private func rebuildText() {
        let body: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 17),
            .foregroundColor: PlatformColor.label,
        ]
        let words = Self.wordings[wordingIndex]
        let text = NSMutableAttributedString()
        if attachments.isEmpty {
            text.append(NSAttributedString(
                string: "No attachments in this text, so the label shows no views.",
                attributes: body,
            ))
        }
        for (index, attachment) in attachments.enumerated() {
            text.append(NSAttributedString(string: "\(words[index % words.count]) ", attributes: body))
            text.append(attachment.attributedString(attributes: body))
            text.append(NSAttributedString(string: index == attachments.count - 1 ? "." : ", ", attributes: body))
        }
        self.text = text
        attachmentCount = attachments.count
    }
}

/// A weak reference to a view, to see whether anything still keeps it alive.
@MainActor
private final class WeakView {
    weak var view: PlatformView?

    init(_ view: PlatformView) {
        self.view = view
    }
}
