//
//  PlatformViewHost.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  The one representable the catalog uses to show a UIKit or AppKit view in
//  SwiftUI. Pages that are about TextLabelView itself build their label in
//  code and hand it to this host; pages about SwiftUI use TextLabel instead.
//

import Litext
import SwiftUI

/// Hosts a UIKit or AppKit view in SwiftUI.
///
/// `make` runs once; `update` runs on every SwiftUI update, so it can push state from
/// the page into the view. `fittingSize` answers SwiftUI's size proposals; without
/// one, the view's own intrinsic size is used.
///
/// ```swift
/// PlatformViewHost.label {
///     let label = TextLabelView()
///     label.isSelectable = true
///     return label
/// } update: { label in
///     label.attributedText = text
/// }
/// ```
struct PlatformViewHost<Content: PlatformView> {
    let make: () -> Content
    var update: (Content) -> Void = { _ in }
    var fittingSize: ((Content, ProposedViewSize) -> CGSize?)?

    init(
        make: @escaping () -> Content,
        update: @escaping (Content) -> Void = { _ in },
        fittingSize: ((Content, ProposedViewSize) -> CGSize?)? = nil,
    ) {
        self.make = make
        self.update = update
        self.fittingSize = fittingSize
    }
}

#if canImport(UIKit)
    extension PlatformViewHost: UIViewRepresentable {
        func makeUIView(context _: Context) -> Content {
            let view = make()
            update(view)
            return view
        }

        func updateUIView(_ uiView: Content, context _: Context) {
            update(uiView)
        }

        func sizeThatFits(_ proposal: ProposedViewSize, uiView: Content, context _: Context) -> CGSize? {
            fittingSize?(uiView, proposal)
        }
    }
#else
    extension PlatformViewHost: NSViewRepresentable {
        func makeNSView(context _: Context) -> Content {
            let view = make()
            update(view)
            return view
        }

        func updateNSView(_ nsView: Content, context _: Context) {
            update(nsView)
        }

        func sizeThatFits(_ proposal: ProposedViewSize, nsView: Content, context _: Context) -> CGSize? {
            fittingSize?(nsView, proposal)
        }
    }
#endif

extension PlatformViewHost where Content: TextLabelView {
    /// Hosts a `TextLabelView` (or a subclass) that takes the proposed width and the
    /// height its text needs at that width, the way the SwiftUI `TextLabel` sizes itself.
    static func label(
        make: @escaping () -> Content,
        update: @escaping (Content) -> Void = { _ in },
    ) -> PlatformViewHost {
        PlatformViewHost(make: make, update: update) { label, proposal in
            fittingLabelSize(label, proposal: proposal)
        }
    }

    /// The proposed width, and the height `label` needs at that width; `nil` when the
    /// proposal has no usable width, so SwiftUI falls back to the intrinsic size.
    static func fittingLabelSize(_ label: Content, proposal: ProposedViewSize) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let fitting = label.textLayout.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitting.height.rounded(.up))
    }
}
