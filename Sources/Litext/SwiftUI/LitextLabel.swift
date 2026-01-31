//
//  LitextLabel.swift
//  Litext
//
//  Created by Litext Team.
//

import SwiftUI

// MARK: - LitextLabel

#if canImport(UIKit)
    import UIKit

    public struct LitextLabel: UIViewRepresentable {
        private let content: Content
        private var isSelectable: Bool = false
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
            uiView.attributedText = content.resolve(in: context.environment)
            uiView.isSelectable = isSelectable
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
            nsView.attributedText = content.resolve(in: context.environment)
            nsView.isSelectable = isSelectable
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
                attributes: Self.mergeWithDefaults(attributes)
            )

        case let .string(string, attributes):
            return NSAttributedString(
                string: string,
                attributes: Self.mergeWithDefaults(attributes)
            )
        }
    }

    private static func mergeWithDefaults(
        _ attributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        var result: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: PlatformFont.systemFontSize),
            .foregroundColor: PlatformColor.label,
        ]
        for (key, value) in attributes {
            result[key] = value
        }
        return result
    }
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

#if canImport(AppKit) && !canImport(UIKit)
    fileprivate extension NSColor {
        static var label: NSColor {
            .labelColor
        }
    }
#endif
