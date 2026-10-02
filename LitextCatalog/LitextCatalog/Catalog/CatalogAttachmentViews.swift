//
//  CatalogAttachmentViews.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Small platform views pages put inside text as attachments. On iOS, macOS,
//  tvOS and visionOS an attachment shows a UIView or NSView, so SwiftUI
//  content goes through a hosting view first.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

enum CatalogAttachmentViews {
    /// An SF Symbol drawn in `color`, for an attachment of `size`.
    static func symbol(_ systemName: String, color: PlatformColor, size: CGSize) -> PlatformView {
        #if canImport(UIKit)
            let view = UIImageView(image: UIImage(systemName: systemName))
            view.tintColor = color
            view.contentMode = .scaleAspectFit
        #else
            let view = NSImageView()
            view.image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
            view.contentTintColor = color
            view.imageScaling = .scaleProportionallyUpOrDown
        #endif
        view.frame = CGRect(origin: .zero, size: size)
        return view
    }

    /// A platform view that shows `content`, for an attachment of `size`.
    static func hosting(_ content: some View, size: CGSize) -> PlatformView {
        let view = CatalogHostingView(rootView: content)
        view.frame = CGRect(origin: .zero, size: size)
        return view
    }
}

#if canImport(UIKit)
    /// Shows a SwiftUI view inside a UIKit view hierarchy, keeping its hosting
    /// controller alive for as long as the view lives.
    final class CatalogHostingView<Content: View>: UIView {
        private let controller: UIHostingController<Content>

        init(rootView: Content) {
            controller = UIHostingController(rootView: rootView)
            super.init(frame: .zero)
            controller.view.backgroundColor = .clear
            controller.view.frame = bounds
            controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(controller.view)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
#else
    typealias CatalogHostingView = NSHostingView
#endif
