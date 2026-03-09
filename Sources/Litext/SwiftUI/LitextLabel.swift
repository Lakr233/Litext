//
//  LitextLabel.swift
//  Litext
//
//  Created by Litext Team.
//

import SwiftUI

// MARK: - LitextLabel

#if canImport(UIKit) && !os(watchOS)
    import UIKit

    public struct LitextLabel: UIViewRepresentable {
        private let content: Content
        private var isSelectable: Bool = false
        private var selectionBackgroundColor: UIColor?
        private var onTapLink: ((URL) -> Void)?

        // MARK: - Initializers

        /// Creates a label with a localized string key.
        /// - Parameters:
        ///   - key: The localized string key.
        ///   - attributes: Text attributes to apply.
        public init(
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
        public init(
            _ string: String,
            attributes: [NSAttributedString.Key: Any] = [:]
        ) {
            content = .string(string, attributes: attributes)
        }

        /// Creates a label with an NSAttributedString.
        /// - Parameter attributedString: The attributed string to display.
        public init(attributedString: NSAttributedString) {
            content = .attributedString(attributedString)
        }

        /// Creates a label with an AttributedString.
        /// - Parameter attributedString: The attributed string to display.
        @available(iOS 15.0, macCatalyst 15.0, tvOS 15.0, visionOS 1.0, *)
        public init(attributedString: AttributedString) {
            content = .attributedString(NSAttributedString(attributedString))
        }

        // MARK: - UIViewRepresentable

        public func makeUIView(context: Context) -> LTXLabel {
            let label = LTXLabel()
            label.delegate = context.coordinator
            label.setContentHuggingPriority(.required, for: .vertical)
            label.setContentCompressionResistancePriority(.required, for: .vertical)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return label
        }

        public func updateUIView(_ uiView: LTXLabel, context: Context) {
            let resolved = content.resolve(in: context.environment)
            if !uiView.attributedText.isEqual(to: resolved) {
                uiView.attributedText = resolved
            }
            uiView.isSelectable = isSelectable
            uiView.selectionBackgroundColor = selectionBackgroundColor
            context.coordinator.onTapLink = onTapLink
        }

        public func makeCoordinator() -> Coordinator {
            Coordinator(onTapLink: onTapLink)
        }

        // MARK: - Modifiers

        /// Enables or disables text selection.
        /// - Parameter enabled: Whether text selection is enabled.
        /// - Returns: A modified label.
        public func selectable(_ enabled: Bool = true) -> LitextLabel {
            var copy = self
            copy.isSelectable = enabled
            return copy
        }

        /// Sets a handler for link taps.
        /// - Parameter action: The action to perform when a link is tapped.
        /// - Returns: A modified label.
        public func onTapLink(_ action: @escaping (URL) -> Void) -> LitextLabel {
            var copy = self
            copy.onTapLink = action
            return copy
        }

        /// Sets the selection background color.
        /// - Parameter color: The color to use for the selection background. Pass nil to use the default.
        /// - Returns: A modified label.
        public func selectionBackgroundColor(_ color: UIColor?) -> LitextLabel {
            var copy = self
            copy.selectionBackgroundColor = color
            return copy
        }

        // MARK: - Coordinator

        public class Coordinator: NSObject, LTXLabelDelegate {
            var onTapLink: ((URL) -> Void)?

            init(onTapLink: ((URL) -> Void)?) {
                self.onTapLink = onTapLink
            }

            public func ltxLabelDidTapOnHighlightContent(
                _: LTXLabel,
                region: LTXHighlightRegion?,
                location _: CGPoint
            ) {
                guard let region else { return }
                if let url = region.attributes[.link] as? URL {
                    if let onTapLink {
                        onTapLink(url)
                    } else {
                        #if os(iOS) || os(visionOS)
                            UIApplication.shared.open(url)
                        #elseif os(tvOS)
                            UIApplication.shared.open(url, options: [:], completionHandler: nil)
                        #endif
                    }
                }
            }

            public func ltxLabelSelectionDidChange(_: LTXLabel, selection _: NSRange?) {}

            public func ltxLabelDetectedUserEventMovingAtLocation(_: LTXLabel, location _: CGPoint) {}
        }
    }

#elseif canImport(AppKit)
    import AppKit

    public struct LitextLabel: NSViewRepresentable {
        private let content: Content
        private var isSelectable: Bool = false
        private var selectionBackgroundColor: NSColor?
        private var onTapLink: ((URL) -> Void)?

        // MARK: - Initializers

        /// Creates a label with a localized string key.
        /// - Parameters:
        ///   - key: The localized string key.
        ///   - attributes: Text attributes to apply.
        public init(
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
        public init(
            _ string: String,
            attributes: [NSAttributedString.Key: Any] = [:]
        ) {
            content = .string(string, attributes: attributes)
        }

        /// Creates a label with an NSAttributedString.
        /// - Parameter attributedString: The attributed string to display.
        public init(attributedString: NSAttributedString) {
            content = .attributedString(attributedString)
        }

        /// Creates a label with an AttributedString.
        /// - Parameter attributedString: The attributed string to display.
        @available(macOS 12.0, *)
        public init(attributedString: AttributedString) {
            content = .attributedString(NSAttributedString(attributedString))
        }

        // MARK: - NSViewRepresentable

        public func makeNSView(context: Context) -> LTXLabel {
            let label = LTXLabel()
            label.delegate = context.coordinator
            label.setContentHuggingPriority(.required, for: .vertical)
            label.setContentCompressionResistancePriority(.required, for: .vertical)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return label
        }

        public func updateNSView(_ nsView: LTXLabel, context: Context) {
            let resolved = content.resolve(in: context.environment)
            if !nsView.attributedText.isEqual(to: resolved) {
                nsView.attributedText = resolved
            }
            nsView.isSelectable = isSelectable
            nsView.selectionBackgroundColor = selectionBackgroundColor
            context.coordinator.onTapLink = onTapLink
        }

        public func makeCoordinator() -> Coordinator {
            Coordinator(onTapLink: onTapLink)
        }

        // MARK: - Modifiers

        /// Enables or disables text selection.
        /// - Parameter enabled: Whether text selection is enabled.
        /// - Returns: A modified label.
        public func selectable(_ enabled: Bool = true) -> LitextLabel {
            var copy = self
            copy.isSelectable = enabled
            return copy
        }

        /// Sets a handler for link taps.
        /// - Parameter action: The action to perform when a link is tapped.
        /// - Returns: A modified label.
        public func onTapLink(_ action: @escaping (URL) -> Void) -> LitextLabel {
            var copy = self
            copy.onTapLink = action
            return copy
        }

        /// Sets the selection background color.
        /// - Parameter color: The color to use for the selection background. Pass nil to use the default.
        /// - Returns: A modified label.
        public func selectionBackgroundColor(_ color: NSColor?) -> LitextLabel {
            var copy = self
            copy.selectionBackgroundColor = color
            return copy
        }

        // MARK: - Coordinator

        public class Coordinator: NSObject, LTXLabelDelegate {
            var onTapLink: ((URL) -> Void)?

            init(onTapLink: ((URL) -> Void)?) {
                self.onTapLink = onTapLink
            }

            public func ltxLabelDidTapOnHighlightContent(
                _: LTXLabel,
                region: LTXHighlightRegion?,
                location _: CGPoint
            ) {
                guard let region else { return }
                if let url = region.attributes[.link] as? URL {
                    if let onTapLink {
                        onTapLink(url)
                    } else {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            public func ltxLabelSelectionDidChange(_: LTXLabel, selection _: NSRange?) {}

            public func ltxLabelDetectedUserEventMovingAtLocation(_: LTXLabel, location _: CGPoint) {}
        }
    }
#endif

// MARK: - LitextLabel (watchOS)

#if os(watchOS)
    import SwiftUI

    /// A read-only rich text label for watchOS.
    /// Renders attributed text (including highlight regions and attachment views) using an
    /// off-screen CGContext so the CoreText pipeline is identical to other platforms.
    public struct LitextLabel: View {
        private let content: Content

        public init(
            _ key: LocalizedStringKey,
            attributes: [NSAttributedString.Key: Any] = [:]
        ) {
            content = .localizedKey(key, attributes: attributes)
        }

        @_disfavoredOverload
        public init(
            _ string: String,
            attributes: [NSAttributedString.Key: Any] = [:]
        ) {
            content = .string(string, attributes: attributes)
        }

        public init(attributedString: NSAttributedString) {
            content = .attributedString(attributedString)
        }

        public init(attributedString: AttributedString) {
            content = .attributedString(NSAttributedString(attributedString))
        }

        public var body: some View {
            _LTXWatchBody(content: content)
        }
    }

    @MainActor
    private struct _LTXWatchBody: View {
        let content: Content

        @Environment(\.litextBundle) private var litextBundle
        @Environment(\.displayScale) private var displayScale
        @State private var layout: LTXTextLayout = .init(attributedString: .init())
        @State private var layoutSize: CGSize = .init(width: 1, height: 1)
        @State private var renderedImage: CGImage?

        private struct AttachmentItem: Identifiable {
            let id: Int
            let view: AnyView
            let viewRect: CGRect
        }

        private func makeAttachmentItems() -> [AttachmentItem] {
            layout.highlightRegions.compactMap { region -> AttachmentItem? in
                guard
                    let attachment = region.attributes[LTXAttachmentAttributeName] as? LTXAttachment,
                    let swiftUIView = attachment.swiftUIView,
                    let ctRect = region.cgRects.first
                else { return nil }
                // CoreText origin is bottom-left; SwiftUI origin is top-left
                let viewRect = CGRect(
                    x: ctRect.origin.x,
                    y: layoutSize.height - ctRect.origin.y - ctRect.height,
                    width: ctRect.width,
                    height: ctRect.height
                )
                return AttachmentItem(id: region.stringRange.location, view: swiftUIView, viewRect: viewRect)
            }
        }

        var body: some View {
            let items = makeAttachmentItems()
            ZStack(alignment: .topLeading) {
                if let img = renderedImage {
                    Image(decorative: img, scale: displayScale)
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
                    Color.clear
                        .onAppear { updateLayout(width: geo.size.width) }
                        .onChange(of: geo.size.width) { newWidth in
                            updateLayout(width: newWidth)
                        }
                }
            }
        }

        private func updateLayout(width: CGFloat) {
            guard width > 0 else { return }
            var env = EnvironmentValues()
            env.litextBundle = litextBundle
            let attrString = content.resolve(in: env)
            let newLayout = LTXTextLayout(attributedString: attrString)
            let suggested = newLayout.suggestContainerSize(
                withSize: CGSize(width: width, height: .greatestFiniteMagnitude)
            )
            let size = CGSize(width: width, height: max(1, suggested.height))
            newLayout.containerSize = size
            newLayout.updateHighlightRegions()
            layout = newLayout
            layoutSize = size
            renderedImage = renderToImage(layout: newLayout, size: size, scale: displayScale)
        }

        private func renderToImage(
            layout: LTXTextLayout,
            size: CGSize,
            scale: CGFloat
        ) -> CGImage? {
            let pw = Int(size.width * scale)
            let ph = Int(size.height * scale)
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
            // LTXTextLayout.draw(in:) expects a UIKit-style context (origin top-left).
            // A raw CGContext has origin bottom-left, so pre-flip here to cancel
            // the flip that draw(in:) will apply internally.
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            layout.draw(in: ctx)
            return ctx.makeImage()
        }
    }
#endif

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
        #if !os(watchOS)
            return mergeWithDefaults(attributes)
        #else
            // On watchOS, PlatformFont/PlatformColor are not available.
            // Users are expected to supply fully-attributed NSAttributedString.
            return attributes
        #endif
    }

    #if canImport(UIKit) && !os(watchOS) || canImport(AppKit)
        private static func mergeWithDefaults(
            _ attributes: [NSAttributedString.Key: Any]
        ) -> [NSAttributedString.Key: Any] {
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
        }
    #endif
}

// MARK: - LocalizedStringKey Resolution

extension LocalizedStringKey {
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
    /// Sets the bundle used for localizing strings in LitextLabel.
    /// - Parameter bundle: The bundle to use for localization.
    /// - Returns: A view with the bundle environment value set.
    func litextBundle(_ bundle: Bundle) -> some View {
        environment(\.litextBundle, bundle)
    }
}

// MARK: - Platform Extensions

#if canImport(UIKit)
// UIKit uses UIColor which already has .label
#elseif canImport(AppKit)
    fileprivate extension NSColor {
        static var label: NSColor {
            .labelColor
        }
    }
#endif
