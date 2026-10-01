//
//  TextLabel.swift
//  Litext
//
//  Created by Litext Team.
//

import SwiftUI

// MARK: - TextLabel

#if !os(watchOS)
    /// The representable conformance lives in an extension, so the main-actor
    /// isolation (and Sendable) it used to infer on the struct is spelled out here.
    @preconcurrency @MainActor
    public struct TextLabel {
        private let content: Content
        private var isSelectable: Bool = false
        private var selectionBackgroundColor: PlatformColor?
        private var onTapLink: ((URL) -> Void)?
        private var onSelectionChange: ((String?) -> Void)?

        @MainActor
        private func makeLabel(coordinator: Coordinator) -> TextLabelView {
            let label = TextLabelView()
            label.delegate = coordinator
            label.setContentHuggingPriority(.required, for: .vertical)
            label.setContentCompressionResistancePriority(.required, for: .vertical)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return label
        }

        @MainActor
        private func apply(
            to label: TextLabelView,
            environment: EnvironmentValues,
            coordinator: Coordinator
        ) {
            coordinator.onTapLink = onTapLink
            coordinator.onSelectionChange = onSelectionChange
            // These assignments can clear a live selection. Hold selection callbacks
            // until the update finishes so they never write state mid-update.
            coordinator.isApplyingUpdate = true
            defer { coordinator.isApplyingUpdate = false }
            let resolved = content.resolve(in: environment)
            if !label.attributedText.isEqual(to: resolved) {
                label.attributedText = resolved
            }
            label.isSelectable = isSelectable
            label.selectionBackgroundColor = selectionBackgroundColor
        }

        /// Measures the label at SwiftUI's proposed width. Returns nil when the
        /// proposal has no usable width so SwiftUI falls back to the intrinsic size.
        @available(iOS 16.0, macCatalyst 16.0, tvOS 16.0, visionOS 1.0, macOS 13.0, *)
        @MainActor
        private func fittingSize(for proposal: ProposedViewSize, label: TextLabelView) -> CGSize? {
            guard let width = proposal.width, width.isValidLayoutDimension, width > 0 else { return nil }
            let suggested = label.textLayout.sizeThatFits(
                CGSize(width: width, height: .greatestFiniteMagnitude)
            )
            // Horizontal hugging is low, so the label takes the proposed width; the
            // height is rounded the same way `intrinsicContentSize` rounds it.
            return CGSize(width: width, height: label.pixelCeil(suggested.height))
        }
    }

    #if canImport(UIKit)
        extension TextLabel: UIViewRepresentable {
            public func makeUIView(context: Context) -> TextLabelView {
                makeLabel(coordinator: context.coordinator)
            }

            public func updateUIView(_ uiView: TextLabelView, context: Context) {
                apply(to: uiView, environment: context.environment, coordinator: context.coordinator)
            }

            @available(iOS 16.0, macCatalyst 16.0, tvOS 16.0, visionOS 1.0, *)
            public func sizeThatFits(
                _ proposal: ProposedViewSize,
                uiView: TextLabelView,
                context _: Context
            ) -> CGSize? {
                fittingSize(for: proposal, label: uiView)
            }

            public func makeCoordinator() -> Coordinator {
                Coordinator(onTapLink: onTapLink, onSelectionChange: onSelectionChange)
            }
        }

    #elseif canImport(AppKit)
        extension TextLabel: NSViewRepresentable {
            public func makeNSView(context: Context) -> TextLabelView {
                makeLabel(coordinator: context.coordinator)
            }

            public func updateNSView(_ nsView: TextLabelView, context: Context) {
                apply(to: nsView, environment: context.environment, coordinator: context.coordinator)
            }

            @available(macOS 13.0, *)
            public func sizeThatFits(
                _ proposal: ProposedViewSize,
                nsView: TextLabelView,
                context _: Context
            ) -> CGSize? {
                fittingSize(for: proposal, label: nsView)
            }

            public func makeCoordinator() -> Coordinator {
                Coordinator(onTapLink: onTapLink, onSelectionChange: onSelectionChange)
            }
        }
    #endif

    // MARK: - Modifiers

    public extension TextLabel {
        /// Enables or disables text selection.
        /// - Parameter enabled: Whether text selection is enabled.
        /// - Returns: A modified label.
        func selectable(_ enabled: Bool = true) -> TextLabel {
            var copy = self
            copy.isSelectable = enabled
            return copy
        }

        /// Sets a handler for link taps.
        /// - Parameter action: The action to perform when a link is tapped.
        /// - Returns: A modified label.
        func onTapLink(_ action: @escaping (URL) -> Void) -> TextLabel {
            var copy = self
            copy.onTapLink = action
            return copy
        }

        /// Sets a handler for selection changes.
        /// - Parameter action: The action to perform when selected plain text changes.
        /// - Returns: A modified label.
        func onSelectionChange(_ action: @escaping (String?) -> Void) -> TextLabel {
            var copy = self
            copy.onSelectionChange = action
            return copy
        }

        /// Sets the selection background color.
        /// - Parameter color: The color to use for the selection background. Pass nil to use the default.
        /// - Returns: A modified label.
        func selectionBackgroundColor(_ color: PlatformColor?) -> TextLabel {
            var copy = self
            copy.selectionBackgroundColor = color
            return copy
        }
    }

    // MARK: - Coordinator

    extension TextLabel {
        open class Coordinator: NSObject, TextLabelViewDelegate {
            var onTapLink: ((URL) -> Void)?
            var onSelectionChange: ((String?) -> Void)?

            /// Set while `TextLabel` pushes SwiftUI state into the view.
            var isApplyingUpdate = false
            private var pendingSelectedText: String?
            private var hasPendingSelectionChange = false

            init(onTapLink: ((URL) -> Void)?, onSelectionChange: ((String?) -> Void)?) {
                self.onTapLink = onTapLink
                self.onSelectionChange = onSelectionChange
            }

            open func textLabelView(
                _: TextLabelView,
                didTapHighlightRegion region: TextLabel.HighlightRegion,
                at _: CGPoint
            ) {
                guard let url = region.linkURL else { return }
                if let onTapLink {
                    onTapLink(url)
                } else {
                    Self.openURL(url)
                }
            }

            open func textLabelView(_ label: TextLabelView, didChangeSelection _: NSRange?) {
                let selectedText = label.selectedPlainText()
                guard isApplyingUpdate else {
                    // This value is newer than any deferred one, which must not land after it.
                    hasPendingSelectionChange = false
                    pendingSelectedText = nil
                    onSelectionChange?(selectedText)
                    return
                }
                // Changes made during a SwiftUI update are reported one main-actor hop
                // later, coalesced to the latest value.
                pendingSelectedText = selectedText
                guard !hasPendingSelectionChange else { return }
                hasPendingSelectionChange = true
                Task { @MainActor [weak self] in
                    self?.flushPendingSelectionChange()
                }
            }

            open func textLabelView(_: TextLabelView, didDragSelectionAt _: CGPoint) {}

            private func flushPendingSelectionChange() {
                guard hasPendingSelectionChange else { return }
                let selectedText = pendingSelectedText
                hasPendingSelectionChange = false
                pendingSelectedText = nil
                onSelectionChange?(selectedText)
            }

            private static func openURL(_ url: URL) {
                #if os(macOS)
                    NSWorkspace.shared.open(url)
                #elseif os(tvOS)
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                #else
                    UIApplication.shared.open(url)
                #endif
            }
        }
    }
#endif

// MARK: - TextLabel (watchOS)

#if os(watchOS)
    /// A read-only rich text label for watchOS.
    /// Renders attributed text (including highlight regions and attachment views) using an
    /// off-screen CGContext so the CoreText pipeline is identical to other platforms.
    public struct TextLabel: View {
        private let content: Content

        public var body: some View {
            _TextLabelWatchBody(content: content)
        }
    }

    @MainActor
    private struct _TextLabelWatchBody: View {
        let content: Content

        @Environment(\.litextBundle) private var litextBundle
        @Environment(\.displayScale) private var displayScale
        @State private var layout: TextLabel.Layout = .init(attributedString: .init())
        @State private var layoutSize: CGSize = .init(width: 1, height: 1)
        @State private var renderedImage: CGImage?
        @State private var renderedScale: CGFloat = 1

        /// Everything the rendered bitmap depends on. The resolved string already
        /// reflects `litextBundle`, so a bundle change shows up as a text change.
        private struct LayoutKey: Equatable {
            let width: CGFloat
            let text: NSAttributedString
            let scale: CGFloat

            static func == (lhs: LayoutKey, rhs: LayoutKey) -> Bool {
                lhs.width == rhs.width
                    && lhs.scale == rhs.scale
                    && lhs.text.isEqual(to: rhs.text)
            }
        }

        private struct AttachmentItem: Identifiable {
            let id: Int
            let view: AnyView
            let viewRect: CGRect
        }

        private func makeAttachmentItems() -> [AttachmentItem] {
            layout.highlightRegions.compactMap { region -> AttachmentItem? in
                guard
                    region.kind == .attachment,
                    let attachment = region.attributes[.litextAttachment] as? TextLabel.Attachment,
                    let swiftUIView = attachment.swiftUIView,
                    let ctRect = region.rects.first
                else { return nil }
                let viewRect = layout.viewRect(fromLayoutRect: ctRect)
                return AttachmentItem(id: region.stringRange.location, view: swiftUIView, viewRect: viewRect)
            }
        }

        private func resolveContent() -> NSAttributedString {
            var env = EnvironmentValues()
            env.litextBundle = litextBundle
            return content.resolve(in: env)
        }

        var body: some View {
            let items = makeAttachmentItems()
            let resolved = resolveContent()
            ZStack(alignment: .topLeading) {
                if let img = renderedImage {
                    // Present the bitmap at the scale it was rendered with.
                    Image(decorative: img, scale: renderedScale)
                }
                ForEach(items) { item in
                    item.view
                        .frame(width: item.viewRect.width, height: item.viewRect.height)
                        .offset(x: item.viewRect.minX, y: item.viewRect.minY)
                }
            }
            .frame(height: max(1, layoutSize.height))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { geo in
                    // Snapshot the string: a key holding the caller's mutable string would
                    // compare equal to itself after an in-place edit.
                    let key = LayoutKey(
                        width: geo.size.width,
                        text: resolved.copy() as! NSAttributedString,
                        scale: displayScale
                    )
                    Color.clear
                        .onAppear { updateLayout(for: key) }
                        .onChange(of: key) { newKey in
                            updateLayout(for: newKey)
                        }
                }
            }
        }

        private func updateLayout(for key: LayoutKey) {
            let width = key.width
            // An invalid width (NaN, negative or infinite) lays out and renders nothing.
            guard width.isValidLayoutDimension, width > 0 else { return }
            let newLayout = TextLabel.Layout(attributedString: key.text)
            let suggested = newLayout.sizeThatFits(
                CGSize(width: width, height: .greatestFiniteMagnitude)
            )
            let size = CGSize(width: width, height: max(1, suggested.height))
            newLayout.containerSize = size
            newLayout.updateHighlightRegions()
            layout = newLayout
            layoutSize = size
            renderedImage = renderToImage(layout: newLayout, size: size, scale: key.scale)
            renderedScale = key.scale
        }

        private func renderToImage(
            layout: TextLabel.Layout,
            size: CGSize,
            scale: CGFloat
        ) -> CGImage? {
            guard size.isValidLayoutSize, scale.isFinite, scale > 0 else { return nil }
            // Round up so the last pixel row and column of glyphs are never clipped.
            let pw = Int((size.width * scale).rounded(.up))
            let ph = Int((size.height * scale).rounded(.up))
            guard pw > 0, ph > 0 else { return nil }

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(
                data: nil,
                width: pw,
                height: ph,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return nil }

            ctx.scaleBy(x: scale, y: scale)
            // TextLabel.Layout.draw(in:) expects a UIKit-style context (origin top-left).
            // A raw CGContext has origin bottom-left, so pre-flip here to cancel
            // the flip that draw(in:) will apply internally.
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            layout.draw(in: ctx)
            return ctx.makeImage()
        }
    }
#endif

// MARK: - Shared Initializers

public extension TextLabel {
    /// Creates a label with a localized string key.
    /// - Parameters:
    ///   - key: The localized string key.
    ///   - attributes: Text attributes to apply.
    init(
        _ key: LocalizedStringKey,
        attributes: [NSAttributedString.Key: Any] = [:]
    ) {
        content = .localizedKey(key, attributes: attributes)
    }

    /// Creates a label with a plain string.
    /// - Parameters:
    ///   - string: The string to display.
    ///   - attributes: Text attributes to apply.
    @_disfavoredOverload
    init(
        _ string: String,
        attributes: [NSAttributedString.Key: Any] = [:]
    ) {
        content = .string(string, attributes: attributes)
    }

    /// Creates a label with an NSAttributedString.
    /// - Parameter attributedString: The attributed string to display.
    init(attributedString: NSAttributedString) {
        content = .attributedString(attributedString)
    }

    /// Creates a label with an AttributedString.
    /// - Parameter attributedString: The attributed string to display.
    @available(iOS 15.0, macCatalyst 15.0, tvOS 15.0, visionOS 1.0, macOS 12.0, watchOS 8.0, *)
    init(attributedString: AttributedString) {
        content = .attributedString(NSAttributedString(attributedString))
    }
}

// MARK: - Content

private enum Content {
    case attributedString(NSAttributedString)
    case localizedKey(LocalizedStringKey, attributes: [NSAttributedString.Key: Any])
    case string(String, attributes: [NSAttributedString.Key: Any])

    func resolve(in environment: EnvironmentValues) -> NSAttributedString {
        switch self {
        case let .attributedString(attrString):
            return attrString

        case let .localizedKey(key, attributes):
            let resolvedString = key.resolve(in: environment)
            return NSAttributedString(
                string: resolvedString,
                attributes: Self.withDefaults(attributes)
            )

        case let .string(string, attributes):
            return NSAttributedString(
                string: string,
                attributes: Self.withDefaults(attributes)
            )
        }
    }

    private static func withDefaults(
        _ attributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        #if os(watchOS)
            // On watchOS, PlatformFont/PlatformColor are not available.
            // Users are expected to supply fully-attributed NSAttributedString.
            return attributes
        #else
            #if os(tvOS)
                let defaultFont = PlatformFont.preferredFont(forTextStyle: .body)
            #else
                let defaultFont = PlatformFont.systemFont(ofSize: PlatformFont.systemFontSize)
            #endif
            var result: [NSAttributedString.Key: Any] = [
                .font: defaultFont,
                .foregroundColor: PlatformColor.label,
            ]
            for (key, value) in attributes {
                result[key] = value
            }
            return result
        #endif
    }
}

// MARK: - LocalizedStringKey Resolution

extension LocalizedStringKey {
    /// Resolves plain localized keys only. Interpolation and locale-specific
    /// formatting embedded in `LocalizedStringKey` are not preserved.
    func resolve(in environment: EnvironmentValues) -> String {
        let mirror = Mirror(reflecting: self)
        for child in mirror.children {
            if child.label == "key", let key = child.value as? String {
                let bundle = environment.litextBundle ?? .main
                return NSLocalizedString(key, bundle: bundle, comment: "")
            }
        }
        return String(describing: self)
    }
}

public extension EnvironmentValues {
    @Entry var litextBundle: Bundle?
}

public extension View {
    /// Sets the bundle used for localizing strings in TextLabel.
    /// - Parameter bundle: The bundle to use for localization.
    /// - Returns: A view with the bundle environment value set.
    func litextBundle(_ bundle: Bundle) -> some View {
        environment(\.litextBundle, bundle)
    }
}
